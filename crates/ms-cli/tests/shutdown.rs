//! The shutdown cookbook examples (`tests/e2e/testdata/shutdown`) against the real binary:
//! SIGINT and SIGTERM end a native build and an `ms run` launcher with status 128 + signal, and
//! the server example runs its cleanup before the synchronous farewell reaches the client.
#![cfg(unix)]

use std::io::{BufRead, BufReader, Read};
use std::net::TcpStream;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{Receiver, channel};
use std::time::{Duration, Instant};

const SIGINT: i32 = 2;
const SIGTERM: i32 = 15;
const WAIT: Duration = Duration::from_secs(20);

const OBSERVER: &str = include_str!("../../../tests/e2e/testdata/shutdown/observer.source");
const SERVER: &str = include_str!("../../../tests/e2e/testdata/shutdown/server.source");

/// A disposable child in its own process group, so a failure cannot leave an `ms run` launcher or
/// its program behind.
struct Child_ {
    child: Child,
    lines: Receiver<String>,
    stderr: Receiver<String>,
}

impl Child_ {
    fn start(program: &Path, args: &[&str]) -> Child_ {
        let mut child = Command::new(program)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .process_group(0)
            .spawn()
            .expect("spawn");
        let stdout = child.stdout.take().expect("stdout");
        let stderr = child.stderr.take().expect("stderr");
        Child_ {
            child,
            lines: reader(stdout),
            stderr: reader(stderr),
        }
    }

    fn line(&self) -> String {
        self.lines
            .recv_timeout(WAIT)
            .expect("child exited or stalled before readiness")
    }

    fn signal(&self, signal: i32) {
        let sent = Command::new("kill")
            .args([format!("-{signal}"), self.child.id().to_string()])
            .status()
            .expect("kill");
        assert!(sent.success());
    }

    /// Remaining stdout lines once the child exits, and its status.
    fn finish(&mut self) -> (Vec<String>, std::process::ExitStatus) {
        let deadline = Instant::now() + WAIT;
        let mut lines = Vec::new();
        while let Ok(line) = self
            .lines
            .recv_timeout(deadline.saturating_duration_since(Instant::now()))
        {
            lines.push(line);
        }
        let status = self.child.wait().expect("wait");
        let stderr: Vec<String> = self.stderr.try_iter().collect();
        assert!(stderr.is_empty(), "stderr {stderr:?}");
        (lines, status)
    }
}

impl Drop for Child_ {
    fn drop(&mut self) {
        let _ = Command::new("kill")
            .args([
                "-KILL".to_string(),
                "--".to_string(),
                format!("-{}", self.child.id()),
            ])
            .status();
        let _ = self.child.wait();
    }
}

fn reader(pipe: impl Read + Send + 'static) -> Receiver<String> {
    let (sender, lines) = channel();
    std::thread::spawn(move || {
        for line in BufReader::new(pipe).lines().map_while(Result::ok) {
            if sender.send(line).is_err() {
                break;
            }
        }
    });
    lines
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("ms-shutdown-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// Build the example and run it as a native binary and through the `ms run` launcher.
fn cookbook(name: &str, source: &str, check: fn(&mut Child_, i32)) {
    let dir = scratch(name);
    let file = dir.join(format!("{name}.ms"));
    std::fs::write(&file, source).unwrap();
    let binary = dir.join(name);
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
    for launcher in [false, true] {
        for signal in [SIGINT, SIGTERM] {
            let mut child = if launcher {
                Child_::start(ms, &["run", file.to_str().unwrap()])
            } else {
                Child_::start(&binary, &[])
            };
            check(&mut child, signal);
        }
    }
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn observer_sees_the_signal_and_exits_with_its_status() {
    cookbook("observer", OBSERVER, |child, signal| {
        assert_eq!(child.line(), "waiting");
        child.signal(signal);
        let (lines, status) = child.finish();
        assert_eq!(status.code(), Some(128 + signal), "{status:?} {lines:?}");
        // Observation is a race, not a shutdown guarantee: accept any valid prefix.
        let transcript = lines.join("\n");
        assert!(
            ["", "got signal", "got signal\nafter sleep"].contains(&transcript.as_str()),
            "unexpected observer transcript: {transcript:?}"
        );
    });
}

#[test]
fn server_cleanup_finishes_before_the_synchronous_farewell() {
    cookbook("server", SERVER, |child, signal| {
        let mut connection = TcpStream::connect(child.line()).expect("connect");
        connection.set_read_timeout(Some(WAIT)).unwrap();
        assert_eq!(child.line(), "ready");
        child.signal(signal);
        let mut farewell = String::new();
        connection
            .read_to_string(&mut farewell)
            .expect("read farewell and EOF");
        let (lines, status) = child.finish();
        assert_eq!(farewell, "farewell\n", "{status:?} {lines:?}");
        assert_eq!(status.code(), Some(128 + signal), "{status:?} {lines:?}");
        assert_eq!(
            lines.join("\n"),
            "worker stopped\nfarewell sent",
            "worker cleanup must finish before the synchronous farewell"
        );
        assert_eq!(status.signal(), None);
    });
}

/// A program joining a long-running worker: a stop request must cancel the worker, not wait it out.
const JOINER: &str = r#"from "@std/io.ms" import stdout
from "@std/time.ms" import nanoseconds, sleep
from "@std/workers.ms" import WorkerGroup, worker_channel

def long() -> Unit:
    var _ch = worker_channel[Int, Int]()
    for i in 0..600:
        sleep(nanoseconds(100000000))

export def main() -> Int:
    with let group = WorkerGroup[Int, Int]():
        var w = group.spawn(long).get()
        stdout().write("joining\n").get()
        stdout().flush().get()
        let outcome = w.wait()
        stdout().write(f"joined {outcome.is_ok()}\n").get()
    return 0
"#;

#[test]
fn joining_a_worker_ends_on_a_stop_request() {
    cookbook("joiner", JOINER, |child, signal| {
        assert_eq!(child.line(), "joining");
        child.signal(signal);
        let (lines, status) = child.finish();
        assert_eq!(status.code(), Some(128 + signal), "{status:?} {lines:?}");
    });
}
