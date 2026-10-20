//! Child processes, ported from `osCommands` in `pkg/runtime/process.go`.
//!
//! Children start in their own process group (a job object on Windows) so a kill reaches the
//! whole tree.
//! Waiting polls in short slices, which lets a pending cancellation kill the tree and unwind.
use alloc::vec::Vec;
use ms_rt_abi::{STATUS_FAILED, STATUS_OUTPUT_LIMIT, STATUS_TIMEOUT};
use ms_std_fs::err::{Fail, Res, describe};
use ms_std_fs::sys;
use ms_std_rt::{cancel_pending, cancelled};

const SLICE_MS: i32 = 50;
/// How long the pipes may stay open after the child exited (`exec.Cmd.WaitDelay`).
const WAIT_DELAY_NS: i64 = 1_000_000_000;
pub const BACKGROUND_OUTPUT: &[u8] = b"the command finished but a background process kept its output open; close or redirect its output, or set a timeout";

#[cfg(unix)]
#[path = "plat/unix.rs"]
mod plat;
#[cfg(windows)]
#[path = "plat/windows.rs"]
mod plat;

pub use crate::spawn::{Child, start};
pub use plat::pipe;

/// Monotonic nanoseconds since the first call.
pub fn now_ns() -> i64 {
    static ORIGIN: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
    ORIGIN
        .get_or_init(std::time::Instant::now)
        .elapsed()
        .as_nanos() as i64
}
use plat::{set_nonblocking, wait_io, would_block};

/// Sleeps `ms` milliseconds.
fn sleep_ms(ms: i64) {
    std::thread::sleep(std::time::Duration::from_millis(ms.max(0) as u64));
}

/// A descriptor closed on drop.
pub struct Fd(pub sys::Fd);

impl Fd {
    pub fn take(&mut self) -> sys::Fd {
        core::mem::replace(&mut self.0, sys::INVALID_FD)
    }

    pub fn is_open(&self) -> bool {
        self.0 != sys::INVALID_FD
    }

    pub fn close(&mut self) {
        if self.is_open() {
            let _ = sys::close(self.0);
            self.0 = sys::INVALID_FD;
        }
    }
}

impl Drop for Fd {
    fn drop(&mut self) {
        self.close();
    }
}

fn start_failure(e: i32) -> Fail {
    let mut m = b"pipe: ".to_vec();
    m.extend_from_slice(describe(e).as_bytes());
    Fail {
        status: STATUS_FAILED,
        message: Some(m),
    }
}

pub struct Output {
    pub code: i64,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

/// Kills the child's group and reaps it unless it was already collected.
struct Reaper(Child);

impl Drop for Reaper {
    fn drop(&mut self) {
        if self.0.code.is_none() {
            self.0.kill_group();
            self.0.wait();
        }
    }
}

/// `run`: executes the command to completion, capturing output up to `max_output` bytes in total.
pub fn run(
    program: &[u8],
    args: &[Vec<u8>],
    input: &[u8],
    max_output: i64,
    timeout_ns: Option<i64>,
) -> Res<Output> {
    let (in_r, mut in_w) = pipe().map_err(start_failure)?;
    let (mut out_r, out_w) = pipe().map_err(start_failure)?;
    let (mut err_r, err_w) = pipe().map_err(start_failure)?;
    let child = start(program, args, in_r.0, out_w.0, err_w.0)?;
    let mut child = Reaper(child);
    drop((in_r, out_w, err_w));

    let deadline = timeout_ns.map(|t| now_ns().saturating_add(t));
    set_nonblocking(in_w.0, true);
    set_nonblocking(out_r.0, false);
    set_nonblocking(err_r.0, false);
    let mut written = 0usize;
    if input.is_empty() {
        in_w.close();
    }
    let (mut stdout, mut stderr): (Vec<u8>, Vec<u8>) = (Vec::new(), Vec::new());
    let mut remaining = max_output;
    let (mut overflow, mut timed_out, mut kept_open) = (false, false, false);
    let mut exited_at: Option<i64> = None;
    let mut buf = alloc::vec![0u8; 64 * 1024];

    loop {
        if cancel_pending() {
            drop(child);
            cancelled();
        }
        if !child.0.poll() {
            exited_at = None;
        } else if exited_at.is_none() {
            exited_at = Some(now_ns());
        }
        if exited_at.is_some() && !out_r.is_open() && !err_r.is_open() {
            break;
        }
        let now = now_ns();
        if deadline.is_some_and(|d| now >= d) {
            timed_out = true;
            child.0.kill_group();
            break;
        }
        if exited_at.is_some_and(|t| now - t >= WAIT_DELAY_NS) {
            kept_open = true;
            break;
        }
        let mut slice = SLICE_MS as i64;
        if let Some(d) = deadline {
            slice = slice.min(((d - now) / 1_000_000).max(1));
        }
        let ready = wait_io([in_w.0, out_r.0, err_r.0], slice);

        if ready[0] && in_w.is_open() {
            let end = input.len().min(written + 64 * 1024);
            match sys::write(in_w.0, &input[written..end]) {
                Ok(n) => written += n,
                Err(e) if would_block(e) => {}
                // The child closed its input early; the remainder is dropped.
                Err(_) => written = input.len(),
            }
            if written >= input.len() {
                in_w.close();
            }
        }
        for (slot, is_err) in [(1usize, false), (2usize, true)] {
            if !ready[slot] {
                continue;
            }
            let reader = if is_err { &mut err_r } else { &mut out_r };
            match sys::read(reader.0, &mut buf) {
                Ok(0) => reader.close(),
                Ok(n) => {
                    let accepted = n.min(remaining.max(0) as usize);
                    let sink = if is_err { &mut stderr } else { &mut stdout };
                    sink.extend_from_slice(&buf[..accepted]);
                    remaining -= accepted as i64;
                    if accepted != n {
                        overflow = true;
                    }
                }
                Err(e) if would_block(e) => {}
                Err(_) => reader.close(),
            }
        }
        if overflow {
            child.0.kill_group();
            break;
        }
    }
    let code = child.0.wait();
    if overflow {
        return Err(Fail::status(STATUS_OUTPUT_LIMIT));
    }
    if timed_out {
        return Err(Fail::status(STATUS_TIMEOUT));
    }
    if kept_open && code == 0 {
        return Err(Fail {
            status: STATUS_FAILED,
            message: Some(BACKGROUND_OUTPUT.to_vec()),
        });
    }
    Ok(Output {
        code,
        stdout,
        stderr,
    })
}

/// A long-lived child with its three pipes (parent ends).
pub struct Subprocess {
    pub child: Child,
    pub closed: bool,
    pub stdin: Fd,
    pub stdout: Fd,
    pub stderr: Fd,
}

pub fn spawn(program: &[u8], args: &[Vec<u8>]) -> Res<Subprocess> {
    let (in_r, in_w) = pipe().map_err(start_failure)?;
    let (out_r, out_w) = pipe().map_err(start_failure)?;
    let (err_r, err_w) = pipe().map_err(start_failure)?;
    let child = start(program, args, in_r.0, out_w.0, err_w.0)?;
    Ok(Subprocess {
        child,
        closed: false,
        stdin: in_w,
        stdout: out_r,
        stderr: err_r,
    })
}

impl Subprocess {
    /// Waits for exit, or `Timeout` when `timeout_ns` elapses first (the child keeps running).
    pub fn wait(&mut self, timeout_ns: Option<i64>) -> Res<i64> {
        let deadline = timeout_ns.map(|t| now_ns().saturating_add(t));
        loop {
            ms_std_rt::poll_cancel();
            if self.child.poll() {
                return Ok(self.child.code.unwrap_or(-1));
            }
            let now = now_ns();
            if deadline.is_some_and(|d| now >= d) {
                return Err(Fail::status(STATUS_TIMEOUT));
            }
            let slice = deadline.map_or(2, |d| ((d - now) / 1_000_000).clamp(1, 2));
            sleep_ms(slice);
        }
    }

    /// Kills the group, joins the leader, kills what remains of the group.
    pub fn stop(&mut self) {
        if self.closed {
            return;
        }
        self.closed = true;
        self.child.signal(true);
        self.child.wait();
        self.child.kill_group();
    }
}

impl Drop for Subprocess {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use ms_rt_abi::STATUS_UNAVAILABLE;

    fn args(list: &[&str]) -> Vec<Vec<u8>> {
        list.iter().map(|s| s.as_bytes().to_vec()).collect()
    }

    #[test]
    fn captures_output_and_exit_codes() {
        let _guard = crate::environment_guard();
        let out = run(
            b"sh",
            &args(&["-c", "cat; echo err >&2; exit 3"]),
            b"hello",
            i64::MAX,
            None,
        )
        .unwrap();
        assert_eq!(
            (out.code, out.stdout.as_slice(), out.stderr.as_slice()),
            (3, b"hello".as_slice(), b"err\n".as_slice())
        );
        let killed = run(b"sh", &args(&["-c", "kill -9 $$"]), b"", i64::MAX, None).unwrap();
        assert_eq!(killed.code, -1);
        assert_eq!(
            run(b"definitely-not-a-program", &[], b"", i64::MAX, None)
                .err()
                .unwrap()
                .status,
            STATUS_UNAVAILABLE
        );
    }

    #[test]
    fn limits_and_timeouts_kill_the_group() {
        let _guard = crate::environment_guard();
        let big = run(
            b"sh",
            &args(&["-c", "yes | head -c 100000"]),
            b"",
            1000,
            None,
        );
        assert_eq!(big.err().unwrap().status, STATUS_OUTPUT_LIMIT);
        let start = now_ns();
        let slow = run(
            b"sh",
            &args(&["-c", "sleep 30 & sleep 30"]),
            b"",
            i64::MAX,
            Some(100_000_000),
        );
        assert_eq!(slow.err().unwrap().status, STATUS_TIMEOUT);
        assert!(now_ns() - start < 5_000_000_000);
        let background = run(b"sh", &args(&["-c", "sleep 5 &"]), b"", i64::MAX, None);
        assert_eq!(
            background.err().unwrap().message.as_deref(),
            Some(BACKGROUND_OUTPUT)
        );
    }

    #[test]
    fn subprocess_pipes_and_close() {
        let _guard = crate::environment_guard();
        let mut p = spawn(b"cat", &[]).unwrap();
        assert_eq!(p.wait(Some(20_000_000)).unwrap_err().status, STATUS_TIMEOUT);
        sys::write(p.stdin.0, b"ping").unwrap();
        p.stdin.close();
        assert_eq!(p.wait(Some(5_000_000_000)).unwrap(), 0);
        let mut buf = [0u8; 8];
        assert_eq!(sys::read(p.stdout.0, &mut buf).unwrap(), 4);
        p.stop();
        let mut sleeper = spawn(b"sleep", &args(&["30"])).unwrap();
        sleeper.child.signal(false);
        assert_eq!(sleeper.wait(Some(5_000_000_000)).unwrap(), -1);
    }
}
