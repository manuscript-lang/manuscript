//! Child processes under signal forwarding.
//!
//! Like the Go launcher, `ms` stays alive until the native program completes
//! its own cancellation and cleanup: SIGINT and SIGTERM sent to `ms` are
//! forwarded to the child instead of killing the launcher.

// The only FFI in the CLI: std has no signal API, so `signal`/`kill` come from libc.
#![allow(unsafe_code)]

use std::process::{Child, ExitStatus};
use std::sync::atomic::{AtomicI32, Ordering};
use std::time::Duration;

const SIGINT: i32 = 2;
const SIGTERM: i32 = 15;
const SIG_DFL: usize = 0;

unsafe extern "C" {
    fn signal(signum: i32, handler: usize) -> usize;
    fn kill(pid: i32, signum: i32) -> i32;
}

static PENDING: AtomicI32 = AtomicI32::new(0);

extern "C" fn record(signum: i32) {
    PENDING.store(signum, Ordering::SeqCst);
}

/// Wait for `child`, forwarding SIGINT and SIGTERM received meanwhile.
pub fn wait_with_signals(child: &mut Child) -> std::io::Result<ExitStatus> {
    PENDING.store(0, Ordering::SeqCst);
    // SAFETY: `record` is async-signal-safe (one atomic store) and has the C ABI
    // `signal` expects; the previous disposition is restored below.
    let (old_int, old_term) = unsafe {
        (
            signal(SIGINT, record as *const () as usize),
            signal(SIGTERM, record as *const () as usize),
        )
    };
    let result = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Ok(status),
            Ok(None) => {}
            Err(error) => break Err(error),
        }
        let pending = PENDING.swap(0, Ordering::SeqCst);
        if pending != 0 {
            // SAFETY: the pid belongs to a child of this process that has not been reaped.
            unsafe { kill(child.id() as i32, pending) };
        }
        std::thread::sleep(Duration::from_millis(10));
    };
    // SAFETY: restoring the dispositions returned by the earlier calls.
    unsafe {
        signal(
            SIGINT,
            if old_int == usize::MAX {
                SIG_DFL
            } else {
                old_int
            },
        );
        signal(
            SIGTERM,
            if old_term == usize::MAX {
                SIG_DFL
            } else {
                old_term
            },
        );
    }
    result
}

/// The exit status as a process status: the code, or 255 when killed by a signal.
pub fn exit_code(status: ExitStatus) -> i32 {
    status.code().unwrap_or(255)
}
