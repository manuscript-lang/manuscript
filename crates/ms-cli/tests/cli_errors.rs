//! Command-line mistakes name the nearest command and the likely fix.

use std::process::Command;

fn ms(args: &[&str]) -> (i32, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(args)
        .output()
        .unwrap();
    (
        out.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    )
}

#[test]
fn help_for_unknown_command_lists_commands() {
    let (status, err) = ms(&["help", "bogus"]);
    assert_eq!(status, 2);
    assert!(err.contains("unknown command: bogus"), "{err}");
    assert!(err.contains("Commands: check,"), "{err}");
}

#[test]
fn path_in_command_position_suggests_run() {
    let (status, err) = ms(&["main.ms"]);
    assert_eq!(status, 2);
    assert!(err.contains("ms run main.ms"), "{err}");
}

#[test]
fn run_json_reports_temporary_directory_errors() {
    let root = std::env::temp_dir().join(format!("ms-run-json-temp-{}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    let source = root.join("main.ms");
    std::fs::write(&source, "export def main() -> Int:\n    return 0\n").unwrap();
    let unavailable = root.join("missing");
    let output = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["run", source.to_str().unwrap(), "--json"])
        .env("TMPDIR", &unavailable)
        .env("TMP", &unavailable)
        .env("TEMP", &unavailable)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    let stdout = std::str::from_utf8(&output.stdout).unwrap();
    let document = ms_json::parse(stdout).unwrap();
    assert_eq!(
        document.get("reason").unwrap().as_str(),
        Some("execution_error")
    );
    assert_eq!(document.get("exit_code").unwrap().as_i64(), Some(1));
    assert_eq!(
        document
            .get("diagnostics")
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        1
    );
    std::fs::remove_dir_all(root).unwrap();
}
