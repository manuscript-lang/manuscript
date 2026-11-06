//! `ms test a.ms b.ms` builds the files into one test executable and runs every test.

use crate::common::scratch;
use std::path::Path;
use std::process::{Command, Output};

fn stage(root: &Path, files: &[(&str, &str)]) {
    for (dir, name) in files {
        let from = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/test_many_files");
        std::fs::create_dir_all(root.join(dir)).unwrap();
        std::fs::copy(from.join(name), root.join(dir).join(name)).unwrap();
    }
}

fn test(root: &Path, files: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(root)
        .arg("test")
        .args(files)
        .output()
        .unwrap()
}

#[test]
fn files_in_different_directories_run_as_one_executable() {
    let root = scratch("test-many-files");
    stage(&root, &[("a", "first.ms"), ("b", "second.ms")]);
    let output = test(&root, &["a/first.ms", "b/second.ms"]);
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success(), "{stdout}");
    assert!(stdout.contains("PASS a/first.ms::first file"), "{stdout}");
    assert!(stdout.contains("PASS b/second.ms::second file"), "{stdout}");
    assert!(stdout.contains("2 tests, 0 failed"), "{stdout}");
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn a_failing_test_in_any_file_fails_the_run() {
    let root = scratch("test-many-files-failing");
    stage(&root, &[("a", "first.ms"), ("a", "failing.ms")]);
    let output = test(&root, &["a/first.ms", "a/failing.ms"]);
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(!output.status.success(), "{stdout}");
    assert!(
        stdout.contains("FAIL failing.ms::third file fails"),
        "{stdout}"
    );
    assert!(stdout.contains("2 tests, 1 failed"), "{stdout}");
    std::fs::remove_dir_all(root).unwrap();
}
