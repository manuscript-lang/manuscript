//! CI uses quiet mode, but stale expected failures must still be named and rejected.
#![cfg(unix)]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::process::Command;

#[test]
fn quiet_strict_run_names_unexpected_passes_and_rejects_them() {
    let root = std::env::temp_dir().join(format!("ms-conform-unexpected-{}", std::process::id()));
    fs::create_dir_all(&root).unwrap();
    let corpus = root.join("fixtures");
    fs::create_dir_all(&corpus).unwrap();
    fs::write(corpus.join("fixed.ms"), "# conform: phase=run\n").unwrap();
    fs::write(
        corpus.join("fixed.expected.json"),
        r#"{"expected":{"exit_code":0,"stdout":"","stderr":""}}"#,
    )
    .unwrap();
    let compiler = root.join("ms");
    fs::write(&compiler, "#!/bin/sh\nexit 0\n").unwrap();
    fs::set_permissions(&compiler, fs::Permissions::from_mode(0o755)).unwrap();
    let allow = root.join("expect-fail.txt");
    fs::write(&allow, "fixed\n").unwrap();

    for strict in [false, true] {
        let mut command = Command::new(env!("CARGO_BIN_EXE_ms-conform"));
        command
            .args(["run", "--quiet", "--corpus"])
            .arg(&corpus)
            .arg("--ms")
            .arg(&compiler)
            .arg("--expect-fail")
            .arg(&allow);
        if strict {
            command.arg("--strict");
        }
        let output = command.output().unwrap();
        let stdout = String::from_utf8(output.stdout).unwrap();
        assert_eq!(output.status.code(), Some(i32::from(strict)), "{stdout}");
        assert!(stdout.contains("1 unexpected pass"), "{stdout}");
        assert!(
            stdout.contains("UNEXPECTED PASS fixed: remove from the expect-fail file"),
            "{stdout}"
        );
    }
    fs::remove_dir_all(root).unwrap();
}
