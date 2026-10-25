//! Child processes.
//!
//! Children start in their own process group (a job object on Windows) so a kill reaches the
//! whole tree.
//! Waiting parks the task on the child's exit and its pipes at once (a pidfd on Linux, a kqueue
//! on macOS). On Windows `Subprocess.wait` parks on the process handle through a thread-pool
//! wait, while `run` still checks its pipes in short slices. Either way other tasks run and a
//! pending cancellation kills the tree and unwinds.
use crate::ipc::ChildEnd;
use alloc::vec::Vec;
use ms_rt::glue::{cancel_pending, cancelled};
use ms_rt_abi::{STATUS_FAILED, STATUS_OUTPUT_LIMIT, STATUS_TIMEOUT};
use ms_std_fs::err::{Fail, Res, describe};
use ms_std_fs::sys;

/// How long a waiting task parks between checks of the child and its pipes when it cannot park
/// on the child's exit.
const POLL_MS: i64 = 2;
/// How long the pipes may stay open after the child exited (`exec.Cmd.WaitDelay`).
const WAIT_DELAY_NS: i64 = 1_000_000_000;
pub const BACKGROUND_OUTPUT: &[u8] = b"the command finished but a background process kept its output open; close or redirect its output, or set a timeout";

#[cfg(unix)]
#[path = "plat/unix.rs"]
#[allow(unsafe_code)] // libc pipes and poll
mod plat;
#[cfg(windows)]
#[path = "plat/windows.rs"]
#[allow(unsafe_code)]
mod plat;

pub use crate::spawn::{Child, StdStream, start};
#[cfg(windows)]
pub use plat::duplex_pipe;
pub use plat::pipe;

/// Monotonic nanoseconds since the first call.
pub fn now_ns() -> i64 {
    static ORIGIN: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
    ORIGIN
        .get_or_init(std::time::Instant::now)
        .elapsed()
        .as_nanos() as i64
}
use plat::{Waiter, set_nonblocking, wait_io, would_block};

/// Parks the task `ms` milliseconds so other tasks run meanwhile.
fn sleep_ms(ms: i64) {
    ms_rt::glue::task_sleep(ms.max(0) * 1_000_000);
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
            let _ = plat::close(self.0);
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
    let (mut in_w, in_r) = pipe(false).map_err(start_failure)?;
    let (mut out_r, out_w) = pipe(true).map_err(start_failure)?;
    let (mut err_r, err_w) = pipe(true).map_err(start_failure)?;
    let child = start(
        program,
        args,
        [
            StdStream::Pipe(in_r.0),
            StdStream::Pipe(out_w.0),
            StdStream::Pipe(err_w.0),
        ],
        None,
        &[],
    )?;
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
    let mut waiter = Waiter::new(child.0.exit_fd(), [in_w.0, out_r.0, err_r.0]);

    loop {
        if cancel_pending() {
            drop(child);
            cancelled();
        }
        if !child.0.poll() {
            exited_at = None;
        } else if exited_at.is_none() {
            exited_at = Some(now_ns());
            if let Some(w) = &mut waiter {
                w.exited();
            }
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
        let park = || {
            let until = [deadline, exited_at.map(|t| t + WAIT_DELAY_NS)]
                .into_iter()
                .flatten()
                .min();
            if let Some(w) = &waiter {
                w.park(until.map_or(-1, |u| u - now));
            } else {
                sleep_ms(until.map_or(POLL_MS, |u| ((u - now) / 1_000_000).clamp(1, POLL_MS)));
            }
        };
        let ready = wait_io([in_w.0, out_r.0, err_r.0], 0);
        if !ready.contains(&true) {
            park();
            continue;
        }

        // Whether a read or write did anything; when none did, the pipes are idle.
        let mut progressed = false;
        if ready[0] && in_w.is_open() {
            let (before, end) = (written, input.len().min(written + 64 * 1024));
            match plat::write(in_w.0, &input[written..end]) {
                Ok(n) => written += n,
                Err(e) if would_block(e) => {}
                // The child closed its input early; the remainder is dropped.
                Err(_) => written = input.len(),
            }
            progressed = written != before;
            if written >= input.len() {
                in_w.close();
            }
        }
        for (slot, is_err) in [(1usize, false), (2usize, true)] {
            if !ready[slot] {
                continue;
            }
            let reader = if is_err { &mut err_r } else { &mut out_r };
            let result = plat::read(reader.0, &mut buf);
            progressed |= !matches!(result, Err(e) if would_block(e));
            match result {
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
        if !progressed {
            park();
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

/// Where `spawn` sends each standard stream, as the case index of `Stdio`.
pub const STDIO_PIPE: i64 = 0;
pub const STDIO_INHERIT: i64 = 1;
pub const STDIO_NULL: i64 = 2;

/// A long-lived child with the parent ends of its piped streams; a stream that is not piped is
/// closed.
pub struct Subprocess {
    pub child: Child,
    pub closed: bool,
    pub stdin: Fd,
    pub stdout: Fd,
    pub stderr: Fd,
}

/// Starts `program`; `modes` gives stdin, stdout and stderr each as a `STDIO_*` value.
pub fn spawn(program: &[u8], args: &[Vec<u8>], modes: [i64; 3]) -> Res<Subprocess> {
    spawn_with(program, args, modes, None, &[])
}

/// [`spawn`] with the extra variables `env` and the child's end of an IPC pipe.
pub fn spawn_with(
    program: &[u8],
    args: &[Vec<u8>],
    modes: [i64; 3],
    ipc: Option<&ChildEnd>,
    env: &[(&str, &[u8])],
) -> Res<Subprocess> {
    let mut parent = [
        Fd(sys::INVALID_FD),
        Fd(sys::INVALID_FD),
        Fd(sys::INVALID_FD),
    ];
    let mut child_ends = Vec::new();
    let mut streams = [StdStream::Null; 3];
    for (i, mode) in modes.into_iter().enumerate() {
        streams[i] = match mode {
            STDIO_PIPE => {
                // The parent writes the child's stdin and reads the rest.
                let (mine, theirs) = pipe(i != 0).map_err(start_failure)?;
                let fd = theirs.0;
                parent[i] = mine;
                child_ends.push(theirs);
                StdStream::Pipe(fd)
            }
            STDIO_INHERIT => StdStream::Inherit,
            _ => StdStream::Null,
        };
    }
    let child = start(program, args, streams, ipc, env)?;
    drop(child_ends);
    let [stdin, stdout, stderr] = parent;
    Ok(Subprocess {
        child,
        closed: false,
        stdin,
        stdout,
        stderr,
    })
}

impl Subprocess {
    /// Waits for exit, or `Timeout` when `timeout_ns` elapses first (the child keeps running).
    pub fn wait(&mut self, timeout_ns: Option<i64>) -> Res<i64> {
        let deadline = timeout_ns.map(|t| now_ns().saturating_add(t));
        loop {
            ms_rt::glue::poll_cancel();
            if self.child.poll() {
                return Ok(self.child.code.unwrap_or(-1));
            }
            let now = now_ns();
            if deadline.is_some_and(|d| now >= d) {
                return Err(Fail::status(STATUS_TIMEOUT));
            }
            if !self.child.park_until_exit(deadline.map_or(-1, |d| d - now)) {
                sleep_ms(deadline.map_or(POLL_MS, |d| ((d - now) / 1_000_000).clamp(1, POLL_MS)));
            }
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
        let mut p = spawn(b"cat", &[], [STDIO_PIPE; 3]).unwrap();
        assert_eq!(p.wait(Some(20_000_000)).unwrap_err().status, STATUS_TIMEOUT);
        sys::write(p.stdin.0, b"ping").unwrap();
        p.stdin.close();
        assert_eq!(p.wait(Some(5_000_000_000)).unwrap(), 0);
        let mut buf = [0u8; 8];
        assert_eq!(sys::read(p.stdout.0, &mut buf).unwrap(), 4);
        p.stop();
        let mut sleeper = spawn(b"sleep", &args(&["30"]), [STDIO_PIPE; 3]).unwrap();
        // Waits park on the child's exit (pidfd or kqueue) instead of checking in slices.
        assert!(sleeper.child.exit_fd().is_some());
        sleeper.child.signal(false);
        assert_eq!(sleeper.wait(Some(5_000_000_000)).unwrap(), -1);
    }

    #[test]
    fn subprocess_streams_inherit_or_discard() {
        let _guard = crate::environment_guard();
        // A null stdin reads as end of input at once; only the piped stderr has a parent end.
        let mut p = spawn(
            b"sh",
            &args(&["-c", "cat; echo done >&2"]),
            [STDIO_NULL, STDIO_INHERIT, STDIO_PIPE],
        )
        .unwrap();
        assert!(!p.stdin.is_open() && !p.stdout.is_open() && p.stderr.is_open());
        assert_eq!(p.wait(Some(5_000_000_000)).unwrap(), 0);
        let mut buf = [0u8; 8];
        assert_eq!(sys::read(p.stderr.0, &mut buf).unwrap(), 5);
        assert_eq!(&buf[..5], b"done\n");
    }
}

#[cfg(all(test, windows))]
mod windows_tests {
    use super::*;

    fn args(list: &[&str]) -> Vec<Vec<u8>> {
        list.iter().map(|s| s.as_bytes().to_vec()).collect()
    }

    #[test]
    fn waits_park_on_the_process_handle() {
        let mut quick = spawn(b"cmd", &args(&["/c", "exit 3"]), [STDIO_NULL; 3]).unwrap();
        assert_eq!(quick.wait(Some(20_000_000_000)).unwrap(), 3);
        let mut slow = spawn(
            b"cmd",
            &args(&["/c", "ping -n 30 127.0.0.1"]),
            [STDIO_NULL; 3],
        )
        .unwrap();
        assert_eq!(
            slow.wait(Some(50_000_000)).unwrap_err().status,
            STATUS_TIMEOUT
        );
        // A second wait on the same child reuses its watch.
        assert_eq!(
            slow.wait(Some(50_000_000)).unwrap_err().status,
            STATUS_TIMEOUT
        );
        slow.child.signal(true);
        assert!(slow.wait(Some(20_000_000_000)).is_ok());
    }

    #[test]
    fn run_parks_on_overlapped_pipes() {
        let out = run(
            b"cmd",
            &args(&["/c", "findstr x & echo err 1>&2"]),
            b"ax\r\nb\r\n",
            1 << 20,
            Some(20_000_000_000),
        )
        .unwrap();
        assert_eq!(out.code, 0);
        assert_eq!(out.stdout, b"ax\r\n");
        assert!(out.stderr.starts_with(b"err"));
        let big = b"x\r\n".repeat(100_000);
        let echoed = run(
            b"cmd",
            &args(&["/c", "findstr x"]),
            &big,
            1 << 20,
            Some(20_000_000_000),
        )
        .unwrap();
        assert_eq!(echoed.stdout.len(), big.len());
    }
}
