//! A task blocked opening or reading a named pipe with no writer parks, so a group timeout
//! cancels it and the other tasks keep running.
#![cfg(unix)]

use std::path::Path;
use std::process::Command;
use std::time::{Duration, Instant};

const PROGRAM: &str = include_str!("fifo_cancel/program.ms");

#[test]
fn a_group_timeout_cancels_tasks_blocked_on_a_fifo() {
    let dir = std::env::temp_dir().join(format!("ms-fifo-cancel-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let fifo = dir.join("pipe");
    let made = Command::new("mkfifo").arg(&fifo).status().unwrap();
    assert!(made.success());
    let source = dir.join("fifo.ms");
    std::fs::write(&source, PROGRAM).unwrap();
    let binary = dir.join("fifo");
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

    let started = Instant::now();
    let mut child = Command::new(&binary)
        .arg(&fifo)
        .stdout(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    let deadline = started + Duration::from_secs(20);
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            break status;
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            panic!("the program still waits on the pipe after 20 s");
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    let mut out = String::new();
    std::io::Read::read_to_string(&mut child.stdout.take().unwrap(), &mut out).unwrap();
    assert!(status.success(), "{out}");
    assert_eq!(out.trim(), "5 true true true");
    let _ = std::fs::remove_dir_all(&dir);
}
