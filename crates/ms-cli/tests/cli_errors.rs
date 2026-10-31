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

#[cfg(unix)]
#[test]
fn invalid_unicode_argument_does_not_select_a_different_file() {
    use std::os::unix::ffi::OsStringExt;

    let dir = std::env::temp_dir().join(format!("ms-cli-invalid-unicode-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("\u{fffd}.ms"), "").unwrap();

    let invalid = std::ffi::OsString::from_vec(vec![0xff, b'.', b'm', b's']);
    let output = Command::new(env!("CARGO_BIN_EXE_ms"))
        .arg("check")
        .arg(invalid)
        .current_dir(&dir)
        .output()
        .unwrap();
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert_eq!(output.status.code(), Some(2), "{output:?}");
    assert!(output.stdout.is_empty(), "{output:?}");
    assert!(stderr.contains("argument is not valid UTF-8;"), "{stderr}");
    assert!(
        stderr.contains("pass UTF-8 command-line arguments"),
        "{stderr}"
    );

    let valid = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["check", "\u{fffd}.ms"])
        .current_dir(&dir)
        .output()
        .unwrap();
    assert!(valid.status.success(), "{valid:?}");
    assert!(valid.stderr.is_empty(), "{valid:?}");
    assert_eq!(
        String::from_utf8(valid.stdout).unwrap(),
        "Checked \u{fffd}.ms\n"
    );
    let _ = std::fs::remove_dir_all(&dir);
}
