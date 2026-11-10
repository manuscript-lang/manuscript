//! Exercise the private atomic-write helpers verbatim, with deterministic file-operation failures.
use crate::common;
use std::process::Command;

fn helper(name: &str) -> String {
    let source = include_str!("../../../stdlib/os/fs.ms");
    let marker = format!("fn {name}(");
    let start = source.find(&marker).expect("atomic helper exists");
    let mut declaration = String::new();
    let mut body = false;
    for line in source[start..].lines() {
        if body && !line.is_empty() && !line.starts_with(char::is_whitespace) {
            break;
        }
        body |= line.ends_with(':');
        declaration.push_str(line);
        declaration.push('\n');
    }
    declaration
}

#[test]
fn atomic_write_names_and_failure_order() {
    let dir = common::scratch("atomic-write-helpers");
    let file = dir.join("main.ms");
    let source = format!(
        "{}\n{}\n{}",
        include_str!("atomic_write/main.ms"),
        helper("temporary_name"),
        helper("finish_atomic"),
    );
    std::fs::write(&file, source).unwrap();
    for profile in ["Debug", "Release"] {
        let output = Command::new(env!("CARGO_BIN_EXE_ms"))
            .args(["run", file.to_str().unwrap(), "--build-type", profile])
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{profile}: {}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr),
        );
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            include_str!("atomic_write/expected.txt"),
            "{profile}",
        );
    }
    std::fs::remove_dir_all(dir).unwrap();
}
