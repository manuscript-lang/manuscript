//! An explicitly skipped native test step does not fail source verification.

use std::process::Command;

#[test]
fn dash_prefixed_target_reaches_every_verification_step() {
    let root = std::env::temp_dir().join(format!("ms-cli-verify-dash-{}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    std::fs::write(
        root.join("-input.ms"),
        "import expect_equal from \"@std/test/test.ms\"\n\ntest \"adds\":\n    try expect_equal(1 + 1, 2)\n",
    )
    .unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(&root)
        .args(["verify", "--json", "--", "-input.ms"])
        .output()
        .unwrap();
    let stdout = std::str::from_utf8(&output.stdout).unwrap();
    assert!(
        output.status.success(),
        "{stdout}\n{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let document = ms_json::parse(stdout).unwrap();
    assert_eq!(document.get("ok").unwrap().as_bool(), Some(true));
    let steps = document.get("steps").unwrap().as_array().unwrap();
    assert_eq!(steps.len(), 4);
    for (step, name) in steps.iter().zip(["check", "fmt", "lint", "test"]) {
        assert_eq!(step.get("name").unwrap().as_str(), Some(name));
        assert_eq!(step.get("status").unwrap().as_str(), Some("passed"));
        assert_eq!(step.get("exit_code").unwrap().as_i64(), Some(0));
    }
    let summary = steps[3].get("result").unwrap().get("summary").unwrap();
    assert_eq!(summary.get("passed").unwrap().as_i64(), Some(1));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn no_test_succeeds_only_when_source_checks_pass() {
    let root = std::env::temp_dir().join(format!("ms-cli-verify-{}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    let path = root.join("main.ms");
    std::fs::write(&path, "fn main() Int:\n    return 0\n").unwrap();
    for json in [false, true] {
        let mut command = Command::new(env!("CARGO_BIN_EXE_ms"));
        command
            .current_dir(&root)
            .args(["verify", "main.ms", "--no-test"]);
        if json {
            command.arg("--json");
        }
        let out = command.output().unwrap();
        let stdout = String::from_utf8(out.stdout).unwrap();
        assert!(out.status.success(), "{stdout}");
        if json {
            assert!(stdout.contains("\"ok\": true"), "{stdout}");
            assert!(stdout.contains("\"reason\": \"--no-test\""), "{stdout}");
        } else {
            assert!(stdout.contains("test   skipped"), "{stdout}");
        }
    }

    for source in [
        "fn main() Int:\n    return missing\n",
        "fn main( ) Int:\n    return 0\n",
    ] {
        std::fs::write(&path, source).unwrap();
        let out = Command::new(env!("CARGO_BIN_EXE_ms"))
            .current_dir(&root)
            .args(["verify", "main.ms", "--no-test", "--json"])
            .output()
            .unwrap();
        let stdout = String::from_utf8(out.stdout).unwrap();
        assert_eq!(out.status.code(), Some(1), "{stdout}");
        assert!(stdout.contains("\"ok\": false"), "{stdout}");
        assert!(stdout.contains("\"status\": \"failed\""), "{stdout}");
    }
    std::fs::remove_dir_all(root).unwrap();
}
