//! Discovery must not replace filesystem names before selecting source modules.

#![cfg(unix)]

mod common;

use common::*;
use ms_driver::project::{Project, discover_modules};
use ms_driver::{LoadOptions, load_file};
use ms_syntax::Phase;
use std::ffi::OsString;
use std::os::unix::ffi::OsStringExt;
use std::path::Path;

fn raw_file(root: &str, name: &[u8]) {
    std::fs::write(
        Path::new(root).join(OsString::from_vec(name.to_vec())),
        "fn broken(",
    )
    .unwrap();
}

fn project(root: &str) -> Project {
    std::fs::create_dir_all(join(root, "src")).unwrap();
    Project {
        root: root.to_string(),
        source: join(root, "src"),
        ..Default::default()
    }
}

#[test]
fn source_discovery_never_replaces_distinct_byte_names() {
    let dir = TempDir::new();
    let p = project(dir.path());
    let dot = write(&p.source, ".ms", "");
    let valid = write(&p.source, "�.ms", "");
    assert_eq!(discover_modules(&p, true).unwrap(), [dot, valid]);
    raw_file(&p.source, b"\xff.ms");
    assert!(discover_modules(&p, false).unwrap().is_empty());
    let error = discover_modules(&p, true).expect_err("lossy source-name collision accepted");
    assert!(error.to_string().contains("UTF-8"), "{error}");
    assert!(error.to_string().contains("rename"), "{error}");
}

#[test]
fn test_discovery_never_replaces_distinct_byte_names() {
    for (valid, raw) in [
        ("�_test.ms", b"\xff_test.ms".as_slice()),
        ("�_bench.ms", b"\xff_bench.ms".as_slice()),
    ] {
        let dir = TempDir::new();
        let p = project(dir.path());
        write(&p.root, valid, "");
        raw_file(&p.root, raw);
        for include_source in [false, true] {
            let error = discover_modules(&p, include_source)
                .expect_err("lossy test-name collision accepted");
            assert!(error.to_string().contains("UTF-8"), "{error}");
        }
    }
}

#[test]
fn excluded_entries_do_not_require_unicode_names() {
    let dir = TempDir::new();
    let p = project(dir.path());
    let valid = write(&p.source, "value.ms", "");
    raw_file(&p.source, b"\xff.txt");
    for skipped in ["vendor", "node_modules"] {
        let directory = join(&p.source, skipped);
        std::fs::create_dir_all(&directory).unwrap();
        raw_file(&directory, b"\xff.ms");
    }
    let hidden = Path::new(&p.source).join(OsString::from_vec(b".\xff".to_vec()));
    std::fs::create_dir(&hidden).unwrap();
    std::fs::write(hidden.join("bad.ms"), "fn broken(").unwrap();
    let linked = Path::new(&p.source).join(OsString::from_vec(b"link\xff.ms".to_vec()));
    std::os::unix::fs::symlink(&p.source, linked).unwrap();
    // A separate project outside source is not a source-module root of this scan.
    let separate = join(&p.root, "separate");
    write(&separate, "ms.toml", "[project]");
    raw_file(&separate, b"\xff.ms");
    assert_eq!(discover_modules(&p, true).unwrap(), [valid]);
    assert!(discover_modules(&p, false).unwrap().is_empty());
}

#[test]
fn directory_discovery_never_replaces_distinct_byte_names() {
    let dir = TempDir::new();
    let p = project(dir.path());
    write(&p.source, "child�/value.ms", "");
    let raw = Path::new(&p.source).join(OsString::from_vec(b"child\xff".to_vec()));
    std::fs::create_dir(&raw).unwrap();
    std::fs::write(raw.join("value.ms"), "fn broken(").unwrap();
    let error = discover_modules(&p, true).expect_err("lossy directory-name collision accepted");
    assert!(error.to_string().contains("UTF-8"), "{error}");
}

#[test]
fn manifest_loading_reports_discovery_name_errors() {
    let dir = TempDir::new();
    let p = project(dir.path());
    write(&p.source, "�.ms", "");
    raw_file(&p.source, b"\xff.ms");
    let manifest = write(
        &p.root,
        "ms.toml",
        "[project]\nname = \"names\"\nsource = \"src\"\n",
    );
    let graph = load_file(&manifest, LoadOptions::default());
    assert_eq!(graph.diagnostics.len(), 1, "{:?}", graph.diagnostics);
    assert_eq!(graph.diagnostics[0].phase, Phase::Resolution);
    assert!(graph.diagnostics[0].message.contains("UTF-8"));
}
