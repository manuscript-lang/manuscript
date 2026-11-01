//! The generated signature table the compiler marshals calls from (`ms-lower/rt_symbols.txt`)
//! lists exactly the functions the embedded runtime archive exports.

use object::read::archive::ArchiveFile;
use object::{Object as _, ObjectSymbol as _};
use std::collections::BTreeSet;
use std::io::Read as _;

const ARCHIVE_GZ: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/libms_native.a.gz"));
const TABLE: &str = include_str!("../../ms-lower/rt_symbols.txt");

/// Exports the table cannot list: data symbols and assembly entry points, which have no Rust signature.
const UNLISTED: &[&str] = &[
    "msrt_desc_int",
    "msrt_desc_float",
    "msrt_desc_float32",
    "msrt_desc_bool",
    "msrt_desc_string",
    "msrt_desc_bytes",
    "msrt_ascii_chars",
    "msrt_guard_jump",
    "msrt_task_tramp",
];

/// Runtime prefixes the compiler calls; other exports (libc shims, Rust internals) are not catalogued.
fn runtime_name(name: &str) -> bool {
    name.starts_with("msrt_") || name.starts_with("msstd_")
}

/// Assembly entry points that exist on one platform family only. Windows has no context-switch
/// task stacks and uses a setjmp-style trap restore instead of fork.
#[cfg(windows)]
const UNIX_ONLY: &[&str] = &["msrt_ctx_switch", "msrt_task_tramp"];
#[cfg(windows)]
const WINDOWS_ONLY: &[&str] = &["msrt_trap_restore"];
#[cfg(not(windows))]
const UNIX_ONLY: &[&str] = &[];
#[cfg(not(windows))]
const WINDOWS_ONLY: &[&str] = &[];

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
        .filter(|l| runtime_name(l))
        .filter_map(|l| l.split('(').next())
        .chain(UNLISTED.iter().copied())
        .map(str::to_string)
        .collect()
}

#[test]
fn runtime_symbol_catalogue_matches_archive() {
    let (mut exported, mut catalogued) = (exported(), catalogued());
    for name in WINDOWS_ONLY {
        exported.remove(*name);
    }
    for name in UNIX_ONLY {
        catalogued.remove(*name);
    }
    let unlisted: Vec<_> = exported.difference(&catalogued).collect();
    let stale: Vec<_> = catalogued.difference(&exported).collect();
    assert!(
        unlisted.is_empty() && stale.is_empty(),
        "crates/ms-lower/rt_symbols.txt is out of date (run `cargo xtask symbols`).\nexported but not listed: {unlisted:?}\nlisted but not exported: {stale:?}"
    );
}
