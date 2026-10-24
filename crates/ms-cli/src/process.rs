//! Child processes under signal forwarding.
//!
//! `ms` stays alive until the native program completes
//! its own cancellation and cleanup: SIGINT and SIGTERM sent to `ms` are
//! forwarded to the child instead of killing the launcher on Unix. Windows has no POSIX
//! `kill`: an interrupted child is force-stopped through its handle, without a cleanup guarantee.

// The only FFI in the CLI: std has no signal API, so `signal`/`kill` come from libc.
#![allow(unsafe_code)]

use std::process::{Child, ExitStatus};
use std::sync::atomic::{AtomicI32, Ordering};
use std::time::{Duration, Instant};

const SIGINT: i32 = 2;
const SIGTERM: i32 = 15;
const SIG_DFL: usize = 0;

unsafe extern "C" {
    fn signal(signum: i32, handler: usize) -> usize;
    #[cfg(unix)]
    fn kill(pid: i32, signum: i32) -> i32;
}

/// Forwards `signum` to `child`. Windows has no `kill`, so the child is terminated instead.
fn send_signal(child: &mut Child, signum: i32) {
    #[cfg(unix)]
    {
        // SAFETY: the pid belongs to a child of this process that has not been reaped.
        unsafe { kill(child.id() as i32, signum) };
    }
    #[cfg(not(unix))]
    {
        let _ = signum;
        let _ = child.kill();
    }
}

static PENDING: AtomicI32 = AtomicI32::new(0);

extern "C" fn record(signum: i32) {
    PENDING.store(signum, Ordering::SeqCst);
}

/// How a supervised child ended.
pub struct Waited {
    pub status: ExitStatus,
    /// The deadline passed and the child was killed.
    pub timed_out: bool,
    /// SIGINT or SIGTERM arrived while waiting (forwarded on Unix; force-stop on Windows).
    pub interrupted: bool,
}

/// SIGINT and SIGTERM are recorded instead of killing `ms` while this lives;
/// the previous dispositions return on drop. Catch before spawning the child: a signal sent as
/// soon as the child reports ready must not find the launcher still on the default disposition.
pub struct Stops {
    old_int: usize,
    old_term: usize,
}

impl Stops {
    pub fn catch() -> Stops {
        PENDING.store(0, Ordering::SeqCst);
        // SAFETY: `record` is async-signal-safe (one atomic store) and has the C ABI
        // `signal` expects; the previous disposition is restored on drop.
        unsafe {
            Stops {
                old_int: signal(SIGINT, record as *const () as usize),
                old_term: signal(SIGTERM, record as *const () as usize),
            }
        }
    }

    /// The signal that arrived since the last call, if any.
    pub fn take(&self) -> Option<i32> {
        Some(PENDING.swap(0, Ordering::SeqCst)).filter(|&signum| signum != 0)
    }
}

impl Drop for Stops {
    fn drop(&mut self) {
        let restore = |old: usize| if old == usize::MAX { SIG_DFL } else { old };
        // SAFETY: restoring the dispositions returned by the earlier calls.
        unsafe {
            signal(SIGINT, restore(self.old_int));
            signal(SIGTERM, restore(self.old_term));
        }
    }
}

/// Wait for `child`, forwarding SIGINT and SIGTERM received meanwhile.
pub fn wait_with_signals(child: &mut Child, stops: &Stops) -> std::io::Result<ExitStatus> {
    wait_supervised(child, stops, None, &mut || {}).map(|waited| waited.status)
}

/// Wait for `child`, forwarding SIGINT and SIGTERM, killing it once `timeout`
/// has elapsed, and calling `poll` about every 10 milliseconds (to drain pipes).
pub fn wait_supervised(
    child: &mut Child,
    stops: &Stops,
    timeout: Option<Duration>,
    poll: &mut dyn FnMut(),
) -> std::io::Result<Waited> {
    let started = Instant::now();
    let (mut timed_out, mut interrupted) = (false, false);
    let mut last = None;
    let result = loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                break Ok(Waited {
                    status,
                    timed_out,
                    interrupted,
                });
            }
            Ok(None) => {}
            Err(error) => break Err(error),
        }
        if let Some(pending) = stops.take() {
            interrupted = true;
            last = Some(pending);
            send_signal(child, pending);
        }
        if !timed_out && timeout.is_some_and(|limit| started.elapsed() >= limit) {
            timed_out = true;
            let _ = child.kill();
        }
        poll();
        std::thread::sleep(Duration::from_millis(10));
    };
    // Hand the signal back to the caller's `Stops` (and a surrounding one in the watch loops).
    if let Some(pending) = last {
        PENDING.store(pending, Ordering::SeqCst);
    }
    result
}

/// Ask `child` to stop the way Ctrl-C does, so it can cancel and clean up.
pub fn interrupt(child: &mut Child) {
    send_signal(child, SIGINT);
}

/// The exit status as a process status: the code, or 128 + signal (the shell convention).
pub fn exit_code(status: ExitStatus) -> i32 {
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        status
            .code()
            .or_else(|| status.signal().map(|s| 128 + s))
            .unwrap_or(255)
    }
    #[cfg(not(unix))]
    {
        status.code().unwrap_or(255)
    }
}
