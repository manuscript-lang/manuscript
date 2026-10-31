//! `redirect_to_null` sends the process's own standard streams to the null device.

use std::io::Write;
use std::process::{Command, Stdio};

#[test]
fn standard_streams_redirect_to_null() {
    let file = format!("{}/tests/redirect_null/main.ms", env!("CARGO_MANIFEST_DIR"));
    let mut child = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["run", &file])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    // The child may exit before reading; a broken pipe is fine.
    let _ = child.stdin.take().unwrap().write_all(b"unread\n");
    let out = child.wait_with_output().unwrap();
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert_eq!(out.status.code(), Some(0), "{stderr}");
    assert_eq!(String::from_utf8_lossy(&out.stdout), "before\n");
    assert_eq!(stderr, "");
}
