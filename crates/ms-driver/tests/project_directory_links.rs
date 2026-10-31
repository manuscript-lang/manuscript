//! Directory links are not modules, including when supplied as a discovery root.

#![cfg(unix)]

mod common;

use common::*;
use ms_driver::project::{Project, discover_modules};

#[test]
fn source_root_directory_links_are_skipped_regardless_of_suffix() {
    let dir = TempDir::new();
    let root = dir.path().to_string();
    let source = join(&root, "src");
    write(&source, "value.ms", "");
    let test = write(&source, "value_test.ms", "");
    for name in [
        "linked",
        "linked.ms",
        "linked_test.ms",
        "test.ms",
        "bench.ms",
    ] {
        let linked = join(&root, name);
        std::os::unix::fs::symlink(&source, &linked).unwrap();
        let project = Project {
            root: root.clone(),
            source: linked,
            ..Default::default()
        };
        for all in [false, true] {
            assert_eq!(
                discover_modules(&project, all).unwrap(),
                std::slice::from_ref(&test),
                "source={name}, include_source={all}"
            );
        }
    }
}

#[test]
fn source_root_file_links_keep_source_and_test_selection() {
    for name in ["linked.ms", "linked_test.ms", "linked_bench.ms"] {
        let dir = TempDir::new();
        let root = dir.path().to_string();
        let source = write(&root, "data.ms", "");
        let linked = join(&root, name);
        std::os::unix::fs::symlink(&source, &linked).unwrap();
        let project = Project {
            root,
            source: linked.clone(),
            ..Default::default()
        };
        assert_eq!(
            discover_modules(&project, true).unwrap(),
            std::slice::from_ref(&linked)
        );
        let tests = discover_modules(&project, false).unwrap();
        if name == "linked.ms" {
            assert!(tests.is_empty());
        } else {
            assert_eq!(tests, [linked]);
        }
    }
}
