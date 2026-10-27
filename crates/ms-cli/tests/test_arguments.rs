//! Test runner options must not consume arguments intended for the program.

use std::process::Command;

#[test]
fn test_program_receives_options_after_the_separator_unchanged() {
    let root = std::env::temp_dir().join(format!("ms-cli-test-arguments-{}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    std::fs::write(
        root.join("test.ms"),
        include_str!(
            "test_arguments/test-program-receives-options-after-the-separator-unchanged.ms"
        ),
    )
    .unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&root)
        .args([
            "test",
            "test.ms",
            "--json",
            "--repeat=2",
            "--",
            "--list",
            "--repeat=2",
            "--timeout=0",
            "--",
            "--help",
        ])
        .output()
        .unwrap();
    let stdout = std::str::from_utf8(&output.stdout).unwrap();
    assert!(
        output.status.success(),
        "{stdout}\n{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let document = ms_json::parse(stdout).unwrap();
    assert!(document.get("listed").is_none(), "{stdout}");
    let summary = document.get("summary").unwrap();
    assert_eq!(summary.get("selected").unwrap().as_i64(), Some(2));
    assert_eq!(summary.get("passed").unwrap().as_i64(), Some(2));
    assert_eq!(summary.get("failed").unwrap().as_i64(), Some(0));
    std::fs::remove_dir_all(root).unwrap();
}
