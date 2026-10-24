//! Every `stdin()` call reads where the previous handle stopped, including what it read ahead.

use std::io::Write;
use std::process::{Command, Stdio};

#[test]
fn successive_stdin_handles_continue_one_stream() {
    let file = format!("{}/tests/stdin_handles/main.ms", env!("CARGO_MANIFEST_DIR"));
    let mut child = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["run", &file])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(b"a\nb\nc\nd\ne\n")
        .unwrap();
    let out = child.wait_with_output().unwrap();
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert_eq!(out.status.code(), Some(0), "{stderr}");
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        "0:a\n1:b\n2:c\nrest:d\ne\n"
    );
}
