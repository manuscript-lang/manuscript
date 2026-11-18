//! Windows counterpart of `shutdown.rs`: a Ctrl-Break sent to a child in its own process group
//! reaches the program as SIGINT, for a native build and for the `ms run` launcher.
#![cfg(windows)]

use crate::common::scratch;
use std::io::{BufRead, BufReader, Read};
use std::os::windows::process::CommandExt;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{Receiver, channel};
use std::time::Duration;

const CREATE_NEW_PROCESS_GROUP: u32 = 0x0000_0200;
const CTRL_BREAK_EVENT: u32 = 1;
const WAIT: Duration = Duration::from_secs(20);

unsafe extern "system" {
    fn GenerateConsoleCtrlEvent(event: u32, group: u32) -> i32;
}

const OBSERVER: &str = include_str!("programs/observer.source");

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

/// Starts `program` in a new process group, waits for it to print `waiting`, sends Ctrl-Break to
/// the group and returns its exit status and remaining output.
fn interrupt(program: &Path, args: &[&str]) -> (Option<i32>, Vec<String>) {
    let mut child: Child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .creation_flags(CREATE_NEW_PROCESS_GROUP)
        .spawn()
        .expect("spawn");
    let lines = reader(child.stdout.take().unwrap());
    let errors = reader(child.stderr.take().unwrap());
    let first = lines.recv_timeout(WAIT);
    if first.as_deref() != Ok("waiting") {
        let _ = child.kill();
        let stderr: Vec<String> = errors.try_iter().collect();
        panic!("child did not report readiness: {first:?} {stderr:?}");
    }
    // SAFETY: plain Win32 call; the child's process id names its process group.
    let sent = unsafe { GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, child.id()) };
    if sent == 0 {
        let _ = child.kill();
        panic!(
            "GenerateConsoleCtrlEvent failed: {}",
            std::io::Error::last_os_error()
        );
    }
    let (done, waited) = channel();
    let id = child.id();
    std::thread::spawn(move || {
        let _ = done.send(child.wait());
    });
    let Ok(status) = waited.recv_timeout(WAIT) else {
        let _ = Command::new("taskkill")
            .args(["/F", "/T", "/PID", &id.to_string()])
            .status();
        panic!("child did not exit after Ctrl-Break");
    };
    (status.unwrap().code(), lines.try_iter().collect())
}

#[test]
fn ctrl_break_is_sigint_for_a_native_build_and_the_launcher() {
    let dir = scratch("shutdown-windows");
    let file = dir.join("observer.ms");
    std::fs::write(&file, OBSERVER).unwrap();
    let binary = dir.join("observer.exe");
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
    let (native, lines) = interrupt(&binary, &[]);
    assert_eq!(native, Some(128 + 2), "native {lines:?}");
    let (launched, lines) = interrupt(ms, &["run", file.to_str().unwrap()]);
    assert_eq!(launched, Some(128 + 2), "launcher {lines:?}");
}
