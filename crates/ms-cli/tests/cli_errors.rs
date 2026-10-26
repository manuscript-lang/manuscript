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
