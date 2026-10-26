//! Whole-file reads release their descriptor when a task is cancelled while waiting on a FIFO.
#![cfg(target_os = "linux")]

use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const PROGRAM: &str = include_str!("fifo_cleanup/program.ms");

#[test]
fn cancelled_whole_file_reads_do_not_leak_descriptors() {
    let dir = std::env::temp_dir().join(format!("ms-fifo-cleanup-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let fifo = dir.join("pipe");
    assert!(
        Command::new("mkfifo")
            .arg(&fifo)
            .status()
            .unwrap()
            .success()
    );
    let source = dir.join("cleanup.ms");
    std::fs::write(&source, PROGRAM).unwrap();
    let binary = dir.join("cleanup");
    let built = Command::new(env!("CARGO_BIN_EXE_ms"))
        .arg("build")
        .arg(&source)
        .arg("-o")
        .arg(&binary)
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );

    let mut child = Command::new(&binary)
        .arg(&fifo)
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(20);
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            break status;
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            let _ = child.wait();
            panic!("FIFO cancellation did not finish within 20 s");
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    let mut output = String::new();
    std::io::Read::read_to_string(&mut child.stdout.take().unwrap(), &mut output).unwrap();
    assert!(status.success(), "{output}");
    let counts: Vec<usize> = output
        .split_whitespace()
        .map(|n| n.parse().unwrap())
        .collect();
    assert_eq!(counts.len(), 3, "{output}");
    assert_eq!(
        counts[0], 10,
        "every read must have been cancelled: {output}"
    );
    assert_eq!(
        counts[1], counts[2],
        "cancelled reads leaked descriptors: {output}"
    );
    let _ = std::fs::remove_dir_all(&dir);
}
