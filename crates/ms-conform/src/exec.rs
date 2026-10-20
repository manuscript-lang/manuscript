//! Run a child process with captured output, optional stdin and a hard timeout.

use std::io::{Read, Write};
#[cfg(unix)]
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

/// Everything observed about one process run.
#[derive(Debug, Clone, Default)]
pub struct Output {
    /// Exit code, or `128 + signal` when the process was killed by a signal.
    pub code: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub timed_out: bool,
    pub spawn_error: Option<String>,
    pub elapsed: Duration,
}

impl Output {
    pub fn stdout_text(&self) -> String {
        String::from_utf8_lossy(&self.stdout).into_owned()
    }

    pub fn stderr_text(&self) -> String {
        String::from_utf8_lossy(&self.stderr).into_owned()
    }
}

/// Run `program args...` in `cwd`, feeding `stdin`, killing the whole process
/// group when `timeout` passes.
pub fn run(
    program: &Path,
    args: &[String],
    cwd: &Path,
    stdin: &[u8],
    timeout: Duration,
    env: &[(String, String)],
) -> Output {
    let started = Instant::now();
    let mut command = Command::new(program);
    command
        .args(args)
        .current_dir(cwd)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(unix)]
    command.process_group(0);
    for (k, v) in env {
        command.env(k, v);
    }
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            return Output {
                code: 127,
                spawn_error: Some(format!("{}: {error}", program.display())),
                elapsed: started.elapsed(),
                ..Output::default()
            };
        }
    };
    let pid = child.id();
    let input = stdin.to_vec();
    let writer = child.stdin.take().map(|mut pipe| {
        thread::spawn(move || {
            // The child may exit without reading; a broken pipe is fine.
            let _ = pipe.write_all(&input);
        })
    });
    let reader = |pipe: Option<Box<dyn Read + Send>>| {
        thread::spawn(move || {
            let mut data = Vec::new();
            if let Some(mut pipe) = pipe {
                let _ = pipe.read_to_end(&mut data);
            }
            data
        })
    };
    let out_thread = reader(
        child
            .stdout
            .take()
            .map(|p| Box::new(p) as Box<dyn Read + Send>),
    );
    let err_thread = reader(
        child
            .stderr
            .take()
            .map(|p| Box::new(p) as Box<dyn Read + Send>),
    );
    let mut timed_out = false;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) => {}
            Err(_) => break None,
        }
        if started.elapsed() >= timeout {
            timed_out = true;
            kill_group(pid);
            let _ = child.kill();
            break child.wait().ok();
        }
        thread::sleep(Duration::from_millis(5));
    };
    // Descendants of ms (the built program) may outlive it; reap the group.
    kill_group(pid);
    if let Some(writer) = writer {
        let _ = writer.join();
    }
    let stdout = out_thread.join().unwrap_or_default();
    let stderr = err_thread.join().unwrap_or_default();
    let code = match status {
        Some(s) => exit_code(s),
        None => 127,
    };
    Output {
        code,
        stdout,
        stderr,
        timed_out,
        spawn_error: None,
        elapsed: started.elapsed(),
    }
}

#[cfg(unix)]
fn exit_code(status: std::process::ExitStatus) -> i32 {
    status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(0))
}

#[cfg(not(unix))]
fn exit_code(status: std::process::ExitStatus) -> i32 {
    status.code().unwrap_or(127)
}

#[cfg(unix)]
fn kill_group(pid: u32) {
    let _ = Command::new("kill")
        .args(["-KILL", "--", &format!("-{pid}")])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// `taskkill /T` ends the process tree rooted at `pid`.
#[cfg(not(unix))]
fn kill_group(pid: u32) {
    let _ = Command::new("taskkill")
        .args(["/F", "/T", "/PID", &pid.to_string()])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    fn sh(script: &str, stdin: &str, timeout_ms: u64) -> Output {
        run(
            Path::new("/bin/sh"),
            &["-c".into(), script.into()],
            Path::new("/"),
            stdin.as_bytes(),
            Duration::from_millis(timeout_ms),
            &[],
        )
    }

    #[test]
    fn captures_streams_and_status() {
        let out = sh("cat; echo err >&2; exit 3", "in", 5000);
        assert_eq!(out.code, 3);
        assert_eq!(out.stdout_text(), "in");
        assert_eq!(out.stderr_text(), "err\n");
        assert!(!out.timed_out);
    }

    #[test]
    fn times_out_and_kills_children() {
        let out = sh("sleep 30 & sleep 30", "", 200);
        assert!(out.timed_out);
        assert!(out.elapsed < Duration::from_secs(10));
    }

    #[test]
    fn missing_program_is_reported() {
        let out = run(
            Path::new("/nonexistent/ms"),
            &[],
            Path::new("/"),
            b"",
            Duration::from_secs(1),
            &[],
        );
        assert!(out.spawn_error.is_some());
    }
}
