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

#[cfg(target_os = "linux")]
#[test]
fn stdout_errors_are_not_reported_as_success() {
    let dir = std::env::temp_dir().join(format!("ms-cli-stdout-flush-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("empty.ms"), "").unwrap();
    let mut guide = vec!["guide", "--json"];
    guide.extend(vec!["MS1001"; 200]);
    for args in [vec!["diagram", "empty.ms"], guide] {
        let normal = Command::new(env!("CARGO_BIN_EXE_ms"))
            .args(&args)
            .current_dir(&dir)
            .output()
            .unwrap();
        assert!(normal.status.success(), "{args:?}: {normal:?}");
        assert!(!normal.stdout.is_empty(), "{args:?}: {normal:?}");
        if args[0] == "guide" {
            assert!(
                normal.stdout.len() > 16_384,
                "the large-write case must exceed buffering"
            );
        }

        let destination = std::fs::OpenOptions::new()
            .write(true)
            .open("/dev/full")
            .unwrap();
        let output = Command::new(env!("CARGO_BIN_EXE_ms"))
            .args(&args)
            .stdout(destination)
            .current_dir(&dir)
            .output()
            .unwrap();
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert_eq!(output.status.code(), Some(1), "{args:?}: {output:?}");
        assert!(output.stdout.is_empty(), "{args:?}: {output:?}");
        assert!(stderr.contains("cannot write stdout:"), "{stderr}");
        assert!(stderr.contains("check the output destination"), "{stderr}");
    }
    let _ = std::fs::remove_dir_all(dir);
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
fn help_spelling_as_an_option_value_is_validated_as_a_value() {
    for args in [
        ["diagram", "main.ms", "--view", "--help"],
        ["diagram", "main.ms", "--format", "-h"],
        ["diagram", "main.ms", "--depth", "--help"],
        ["review", "main.ms", "--format", "--help"],
        ["review", "main.ms", "--explain", "--help"],
    ] {
        let (status, err) = ms(&args);
        assert_eq!(status, 2, "{args:?}: {err}");
        assert!(!err.is_empty(), "{args:?} must report its invalid value");
    }
}

#[test]
fn init_next_command_for_hyphen_directory_is_a_file_operand() {
    let dir = std::env::temp_dir().join(format!("ms-cli-init-hyphen-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let out = std::process::Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["init", "./-demo"])
        .current_dir(&dir)
        .output()
        .unwrap();
    let text = String::from_utf8_lossy(&out.stdout);
    assert!(
        text.contains("Next: ms run ./-demo/ms.toml -- first second"),
        "{text}"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn source_only_commands_reject_program_arguments_before_discovery() {
    for command in ["inspect", "diagram"] {
        for extra in [&["extra"][..], &["--", "extra"], &["--", "--help"]] {
            let mut args = vec![command, "missing.ms"];
            args.extend_from_slice(extra);
            let output = Command::new(env!("CARGO_BIN_EXE_ms"))
                .args(&args)
                .output()
                .unwrap();
            let stderr = String::from_utf8_lossy(&output.stderr);
            assert_eq!(output.status.code(), Some(2), "{args:?}: {stderr}");
            assert!(output.stdout.is_empty(), "{args:?}: {output:?}");
            assert!(!stderr.contains("file not found:"), "{args:?}: {stderr}");
            assert!(stderr.contains("remove"), "{args:?}: {stderr}");
            assert!(
                !stderr.contains("arguments for the program go after --"),
                "{args:?}: {stderr}"
            );
        }
    }
}
