//! An explicitly skipped native test step does not fail source verification.

use std::process::Command;

#[test]
fn no_test_succeeds_only_when_source_checks_pass() {
    let root = std::env::temp_dir().join(format!("ms-cli-verify-{}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    let path = root.join("main.ms");
    std::fs::write(&path, "def main() -> Int:\n    return 0\n").unwrap();
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
        "def main() -> Int:\n    return missing\n",
        "def main( ) -> Int:\n    return 0\n",
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
