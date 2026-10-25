//! Main and a worker that each wait for a message from the other end with the deadlock fault
//! instead of hanging.

use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const PROGRAM: &str =
    include_str!("../../../tests/e2e/testdata/waits/cross-isolate-deadlock.source");

#[test]
fn a_wait_cycle_across_isolates_faults() {
    let dir = std::env::temp_dir().join(format!("ms-isolate-deadlock-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("main.ms");
    std::fs::write(&file, PROGRAM).unwrap();
    let ms = Path::new(env!("CARGO_BIN_EXE_ms"));
    let mut child = Command::new(ms)
        .args(["run", file.to_str().unwrap()])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let start = Instant::now();
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            break status;
        }
        if start.elapsed() > Duration::from_secs(60) {
            let _ = child.kill();
            panic!("the program hangs instead of faulting");
        }
        std::thread::sleep(Duration::from_millis(50));
    };
    let out = child.wait_with_output().unwrap();
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(!status.success(), "{stderr}");
    assert!(stderr.contains("deadlock"), "{stderr}");
    let _ = std::fs::remove_dir_all(&dir);
}
