//! The generated signature table the compiler marshals calls from (`ms-lower/rt_symbols.txt`)
//! lists exactly the functions the embedded runtime archive exports.

use object::read::archive::ArchiveFile;
use object::{Object as _, ObjectSymbol as _};
use std::collections::BTreeSet;
use std::io::Read as _;

const ARCHIVE_GZ: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/libms_native.a.gz"));
const TABLE: &str = include_str!("../../ms-lower/rt_symbols.txt");

/// Data exports, which have no signature to list: the `extern` variables the public headers declare
/// (`extern const MsTypeDesc msrt_desc_int;`, `extern uint8_t msrt_ascii_chars[][2];`).
fn data_exports() -> BTreeSet<String> {
    let headers =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../src/runtime/include/ms_rt");
    let mut names = BTreeSet::new();
    for entry in std::fs::read_dir(headers).expect("runtime headers") {
        let path = entry.expect("header").path();
        if path.extension().is_none_or(|extension| extension != "h") {
            continue;
        }
        let text = std::fs::read_to_string(&path).expect("read header");
        for line in text.lines() {
            let Some(declaration) = line.strip_prefix("extern ") else {
                continue;
            };
            if declaration.contains('(') {
                continue;
            }
            let name = declaration
                .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                .rfind(|word| runtime_name(word));
            names.extend(name.map(str::to_string));
        }
    }
    names
}

/// Runtime prefixes the compiler calls; other exports (libc shims, Rust internals) are not catalogued.
fn runtime_name(name: &str) -> bool {
    name.starts_with("msrt_") || name.starts_with("msstd_")
}

fn exported() -> BTreeSet<String> {
    let mut bytes = Vec::new();
    flate2::read::GzDecoder::new(ARCHIVE_GZ)
        .read_to_end(&mut bytes)
        .expect("gunzip the archive");
    let archive = ArchiveFile::parse(bytes.as_slice()).expect("archive");
    let mut names = BTreeSet::new();
    for member in archive.members() {
        let member = member.expect("member");
        let Ok(data) = member.data(bytes.as_slice()) else {
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
    TABLE
        .lines()
        .filter(|l| runtime_name(l) && !l.contains(" @inline")) // `@inline`: lowered as MIR, no C body to export
        .filter_map(|l| l.split('(').next())
        .map(str::to_string)
        .chain(data_exports())
        .collect()
}

#[test]
fn runtime_symbol_catalogue_matches_archive() {
    let (exported, catalogued) = (exported(), catalogued());
    let unlisted: Vec<_> = exported.difference(&catalogued).collect();
    let stale: Vec<_> = catalogued.difference(&exported).collect();
    assert!(
        unlisted.is_empty() && stale.is_empty(),
        "crates/ms-lower/rt_symbols.txt is out of date (run `ms run src/ms/symbols.ms`).\nexported but not listed: {unlisted:?}\nlisted but not exported: {stale:?}"
    );
}
