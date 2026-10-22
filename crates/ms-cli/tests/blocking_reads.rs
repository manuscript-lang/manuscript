//! A request handler blocked reading standard input parks its task: the server keeps answering
//! other requests, and the handler finishes once input arrives.
#![cfg(unix)]

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const SERVER: &str = include_str!("../../../tests/e2e/testdata/waits/stdin-server.source");

fn get(conn: &mut TcpStream, path: &str) {
    write!(conn, "GET {path} HTTP/1.1\r\nHost: t\r\n\r\n").unwrap();
}

/// Reads one response with a small body and returns its last line.
fn response(conn: &mut TcpStream) -> String {
    let mut text = String::new();
    let mut buf = [0u8; 1024];
    while !text.contains("\r\n\r\n") || !text.ends_with('\n') || text.ends_with("\r\n\r\n") {
        let n = conn.read(&mut buf).expect("response");
        assert!(n > 0, "connection closed: {text:?}");
        text.push_str(&String::from_utf8_lossy(&buf[..n]));
    }
    assert!(text.starts_with("HTTP/1.1 200"), "{text}");
    text.trim_end().rsplit('\n').next().unwrap().to_string()
}

/// Kills the server however the test ends, so a failure cannot leave it holding the test's pipes.
struct Killed(std::process::Child);

impl Drop for Killed {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[test]
fn a_handler_reading_stdin_does_not_stall_the_server() {
    let dir = std::env::temp_dir().join(format!("ms-blocking-reads-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("server.ms");
    std::fs::write(&file, SERVER).unwrap();
    let binary = dir.join("server");
    let ms = Path::new(env!("CARGO_BIN_EXE_ms"));
    let built = Command::new(ms)
        .args([
            "build",
            file.to_str().unwrap(),
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
    let mut child = Killed(
        Command::new(&binary)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .expect("spawn"),
    );
    let mut address = String::new();
    BufReader::new(child.0.stdout.take().unwrap())
        .read_line(&mut address)
        .unwrap();
    let timeout = Some(Duration::from_secs(10));

    let mut waiting = TcpStream::connect(address.trim()).unwrap();
    waiting.set_read_timeout(timeout).unwrap();
    get(&mut waiting, "/line");
    // A second handler waits on the same descriptor.
    let mut second = TcpStream::connect(address.trim()).unwrap();
    second.set_read_timeout(timeout).unwrap();
    get(&mut second, "/line");
    // Give the handlers time to start reading.
    std::thread::sleep(Duration::from_millis(100));

    let mut other = TcpStream::connect(address.trim()).unwrap();
    other.set_read_timeout(timeout).unwrap();
    let start = Instant::now();
    for _ in 0..20 {
        get(&mut other, "/health");
        assert_eq!(response(&mut other), "ok");
    }
    let elapsed = start.elapsed();

    let input = child.0.stdin.as_mut().unwrap();
    // One line at a time, so each handler reads exactly one; either may get either.
    input.write_all(b"hello\n").unwrap();
    std::thread::sleep(Duration::from_millis(200));
    input.write_all(b"world\n").unwrap();
    let mut lines = [response(&mut waiting), response(&mut second)];
    lines.sort();
    drop(child);
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(lines, ["hello", "world"]);
    assert!(
        elapsed < Duration::from_secs(1),
        "20 requests took {elapsed:?} while a handler waited for input"
    );
}
