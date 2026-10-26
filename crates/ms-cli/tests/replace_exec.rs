//! `ProcessControl.replace` swaps the process image for another program.
#![cfg(unix)]

use std::path::Path;
use std::process::Command;

const PROGRAM: &str = r#"from "@std/process.ms" import control

export def main() -> Int:
    let outcome = control().replace(
        program: "/bin/sh",
        arguments: ["sh", "-c", "echo replaced $MS_REPLACED"],
        environment: {"MS_REPLACED": "yes"}
    )
    return 1
"#;

#[test]
fn replace_runs_the_program_with_exactly_the_given_environment() {
    let dir = std::env::temp_dir().join(format!("ms-replace-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let source = dir.join("replace.ms");
    std::fs::write(&source, PROGRAM).unwrap();
    let binary = dir.join("replace");
    let ms = Path::new(env!("CARGO_BIN_EXE_ms"));
    let built = Command::new(ms)
        .args([
            "build",
            source.to_str().unwrap(),
            "-o",
            binary.to_str().unwrap(),
        ])
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let ran = Command::new(&binary)
        .env("MS_INHERITED", "no")
        .output()
        .unwrap();
    assert!(
        ran.status.success(),
        "{}",
        String::from_utf8_lossy(&ran.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&ran.stdout).trim(), "replaced yes");
    let _ = std::fs::remove_dir_all(&dir);
}
