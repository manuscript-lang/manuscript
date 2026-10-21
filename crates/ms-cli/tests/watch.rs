#![cfg(unix)]
//! `ms run --watch` and `ms test --watch` against the real binary: a saved change rebuilds and
//! restarts, a broken edit keeps the old program, and Ctrl-C ends the watch with status 130.

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{Receiver, channel};
use std::time::{Duration, Instant};

const WAIT: Duration = Duration::from_secs(120);

struct Watch {
    child: Child,
    lines: Receiver<String>,
    seen: Vec<String>,
}

impl Watch {
    fn start(directory: &Path, args: &[&str]) -> Watch {
        let mut child = Command::new(env!("CARGO_BIN_EXE_ms"))
            .args(args)
            .current_dir(directory)
            .stdin(Stdio::null())
            .stdout(std::fs::File::create(directory.join("stdout.txt")).expect("stdout file"))
            .stderr(Stdio::piped())
            .spawn()
            .expect("spawn ms");
        let stderr = child.stderr.take().expect("stderr");
        let (sender, lines) = channel();
        std::thread::spawn(move || {
            for line in BufReader::new(stderr).lines().map_while(Result::ok) {
                if sender.send(line).is_err() {
                    break;
                }
            }
        });
        Watch {
            child,
            lines,
            seen: Vec::new(),
        }
    }

    /// Wait for a stderr line containing `text`, returning it.
    fn until(&mut self, text: &str) -> String {
        let deadline = Instant::now() + WAIT;
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            match self.lines.recv_timeout(left) {
                Ok(line) => {
                    self.seen.push(line.clone());
                    if line.contains(text) {
                        return line;
                    }
                }
                Err(_) => panic!("no {text:?} in {:#?}", self.seen),
            }
        }
    }

    fn stdout(&self, directory: &Path) -> String {
        std::fs::read_to_string(directory.join("stdout.txt")).unwrap_or_default()
    }

    /// Ctrl-C, then the exit status.
    fn interrupt(mut self) -> Option<i32> {
        let status = Command::new("kill")
            .args(["-INT", &self.child.id().to_string()])
            .status()
            .expect("kill");
        assert!(status.success());
        self.child.wait().expect("wait").code()
    }
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("ms-watch-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn program(exit: i32) -> String {
    format!("export fn main() Int:\n    return {exit}\n")
}

/// Rewrite after a pause, so the new modification time differs on coarse file systems.
fn save(path: &Path, text: &str) {
    std::thread::sleep(Duration::from_millis(1100));
    std::fs::write(path, text).unwrap();
}

#[test]
fn run_restarts_after_each_change_and_survives_a_broken_edit() {
    let dir = scratch("run");
    let source = dir.join("main.ms");
    std::fs::write(&source, program(3)).unwrap();
    let mut watch = Watch::start(&dir, &["run", "main.ms", "--watch"]);
    watch.until("ms: started run");
    watch.until("ms: exited with status 3; waiting for changes");

    save(&source, "export fn main() Int:\n    return \"x\"\n");
    watch.until("expected Int, found String");
    watch.until("ms: waiting for changes");

    save(&source, &program(4));
    watch.until("ms: restarted run");
    watch.until("ms: exited with status 4; waiting for changes");
    assert_eq!(watch.interrupt(), Some(130));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn test_reruns_after_each_change() {
    let dir = scratch("test");
    let source = dir.join("sample_test.ms");
    let tests = |expected: i32| {
        format!(
            "import {{expect_equal}} from \"@std/testing.ms\"\n\ntest \"adds\":\n    try expect_equal(1 + 1, {expected})\n"
        )
    };
    std::fs::write(&source, tests(3)).unwrap();
    let mut watch = Watch::start(&dir, &["test", "sample_test.ms", "--watch"]);
    watch.until("ms: waiting for changes");
    assert!(watch.stdout(&dir).contains("FAIL sample_test.ms::adds"));

    save(&source, &tests(2));
    watch.until("ms: waiting for changes");
    assert!(watch.stdout(&dir).contains("PASS sample_test.ms::adds"));
    assert_eq!(watch.interrupt(), Some(130));
    let _ = std::fs::remove_dir_all(&dir);
}
