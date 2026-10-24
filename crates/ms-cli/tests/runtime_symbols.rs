//! The runtime symbol catalogue the compiler marshals calls from lists exactly the functions the
//! embedded runtime archive exports.

use object::read::archive::ArchiveFile;
use object::{Object as _, ObjectSymbol as _};
use std::collections::BTreeSet;

const ARCHIVE: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/libms_native.a"));
const CATALOGUE: &str = include_str!("../../ms-rt/SYMBOLS.md");

/// Runtime prefixes the compiler calls; other exports (libc shims, Rust internals) are not catalogued.
fn runtime_name(name: &str) -> bool {
    name.starts_with("msrt_") || name.starts_with("msstd_")
}

fn exported() -> BTreeSet<String> {
    let archive = ArchiveFile::parse(ARCHIVE).expect("archive");
    let mut names = BTreeSet::new();
    for member in archive.members() {
        let member = member.expect("member");
        let Ok(data) = member.data(ARCHIVE) else {
            continue;
        };
        let Ok(file) = object::File::parse(data) else {
            continue;
        };
        for symbol in file.symbols() {
            let Ok(name) = symbol.name() else { continue };
            let name = name.trim_start_matches('_');
            if symbol.is_definition() && symbol.is_global() && runtime_name(name) {
                names.insert(name.to_string());
            }
        }
    }
    names
}

fn catalogued() -> BTreeSet<String> {
    CATALOGUE
        .lines()
        .filter(|l| runtime_name(l))
        .filter_map(|l| l.split(['(', ' ']).next())
        .map(str::to_string)
        .collect()
}

#[test]
fn runtime_symbol_catalogue_matches_archive() {
    let (exported, catalogued) = (exported(), catalogued());
    let unlisted: Vec<_> = exported.difference(&catalogued).collect();
    let stale: Vec<_> = catalogued.difference(&exported).collect();
    assert!(
        unlisted.is_empty() && stale.is_empty(),
        "crates/ms-rt/SYMBOLS.md is out of date.\nexported but not listed: {unlisted:?}\nlisted but not exported: {stale:?}"
    );
}
