//! Deadlines and blocking waits for the ms thread.
//!
//! Every blocking operation waits through [`wait_fd`] or [`blocking`], which park
//! the running `ms-rt` task so the server reactor and request handlers (other tasks)
//! run while it waits. A stop request wakes the wait and takes the runtime's
//! cancellation path.
//!
//! Unit tests run on many threads, which the runtime's scheduler does not support: there a
//! thread parks only once it serves (see `use_tasks`), and otherwise polls in slices.

use crate::rt;
use crate::sys::{self, Borrowed};
pub use ms_rt::glue::pool::Lane;
#[cfg(test)]
use std::cell::Cell;
use std::time::{Duration, Instant};

/// A supplied timeout below zero.
#[derive(Clone, Copy, Debug)]
pub struct NegativeTimeout;

/// An optional absolute time limit.
#[derive(Clone, Copy, Debug)]
pub struct Deadline(Option<Instant>);

impl Deadline {
    pub const fn none() -> Deadline {
        Deadline(None)
    }

    pub fn after(d: Duration) -> Deadline {
        Deadline(Instant::now().checked_add(d))
    }

    /// From an optional timeout in nanoseconds. A negative value is invalid.
    pub fn from_nanos(timeout: Option<i64>) -> Result<Deadline, NegativeTimeout> {
        match timeout {
            None => Ok(Deadline::none()),
            Some(ns) if ns < 0 => Err(NegativeTimeout),
            Some(ns) => Ok(Deadline::after(Duration::from_nanos(ns as u64))),
        }
    }

    /// Time left, or `None` without a limit.
    pub fn remaining(&self) -> Option<Duration> {
        self.0.map(|t| t.saturating_duration_since(Instant::now()))
    }

    pub fn expired(&self) -> bool {
        self.0.is_some_and(|t| Instant::now() >= t)
    }

    pub fn is_none(&self) -> bool {
        self.0.is_none()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Interest {
    Read,
    Write,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Wait {
    Ready,
    TimedOut,
}

#[cfg(test)]
thread_local! {
    static TASKS: Cell<bool> = const { Cell::new(false) };
}

/// Tests: makes this thread's waits park the running `ms-rt` task. Done by the first server
/// of a test thread, which then holds the scheduler for the rest of the test.
pub fn use_tasks() {
    #[cfg(test)]
    {
        crate::http::server::serialize_tests();
        TASKS.with(|t| t.set(true));
    }
}

/// Whether waits park the task: always, except on a test thread without a server.
fn parks() -> bool {
    #[cfg(test)]
    return TASKS.with(Cell::get);
    #[cfg(not(test))]
    true
}

/// Waits until `fd` is ready for `interest` (hang-up and error count as ready, so
/// the next read or write reports them) or the deadline passes. The task parks, so the
/// server reactor and request handlers run meanwhile. Faults with the runtime's
/// cancellation when a stop was requested.
pub fn wait_fd(fd: Borrowed<'_>, interest: Interest, deadline: Deadline) -> Wait {
    if parks() {
        wait_task(fd, interest, deadline)
    } else {
        wait_poll(fd, interest, deadline)
    }
}

fn wait_task(fd: Borrowed<'_>, interest: Interest, deadline: Deadline) -> Wait {
    rt::check_cancel();
    let events = match interest {
        Interest::Read => 1,
        Interest::Write => 2,
    };
    let got = rt::wait_fd(fd, events, timeout_ns(deadline));
    if got & 16 != 0 {
        rt::cancelled();
    }
    if got & 8 != 0 && got & 7 == 0 {
        Wait::TimedOut
    } else {
        Wait::Ready
    }
}

/// Parks until `token` is posted or the deadline passes. Faults with the runtime's
/// cancellation when a stop was requested.
pub fn wait_token(token: &rt::Token, deadline: Deadline) -> Wait {
    rt::check_cancel();
    let got = token.park(timeout_ns(deadline));
    if got & 16 != 0 {
        rt::cancelled();
    }
    if got == 0 {
        Wait::Ready
    } else {
        Wait::TimedOut
    }
}

/// The runtime's timeout for `deadline`: nanoseconds left, or -1 for none.
fn timeout_ns(deadline: Deadline) -> i64 {
    deadline
        .remaining()
        .map_or(-1, |d| d.as_nanos().min(i64::MAX as u128) as i64)
}

/// Longest a polling wait sleeps before it re-checks the cancel flag.
const SLICE: Duration = Duration::from_millis(50);

fn wait_poll(fd: Borrowed<'_>, interest: Interest, deadline: Deadline) -> Wait {
    loop {
        rt::check_cancel();
        let slice = deadline.remaining().map_or(SLICE, |left| left.min(SLICE));
        if sys::poll_one(fd, interest == Interest::Write, slice) {
            return Wait::Ready;
        }
        if deadline.expired() {
            return Wait::TimedOut;
        }
    }
}

/// Sleeps for `d` while serving handlers; faults on cancellation.
pub fn sleep(d: Duration) {
    if !parks() {
        std::thread::sleep(d);
        return;
    }
    rt::check_cancel();
    if rt::sleep(d.as_nanos().min(i64::MAX as u128) as i64) & 16 != 0 {
        rt::cancelled();
    }
}

/// Runs `f(&input)` on the shared blocking pool and parks until it finishes; `None` when the
/// deadline passes first (the late result is dropped). `f` must not call into the runtime.
/// Unit tests, which do not park, run it inline.
pub fn blocking<I: Send + Sync + 'static, O: Send + 'static>(
    lane: Lane,
    input: I,
    f: fn(&I) -> O,
    deadline: Deadline,
) -> Option<O> {
    if !parks() {
        return Some(f(&input));
    }
    rt::check_cancel();
    let timeout = deadline
        .remaining()
        .map_or(-1, |left| left.as_nanos().min(i64::MAX as u128) as i64);
    ms_rt::glue::pool::run(lane, input, f, timeout)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deadlines() {
        assert!(Deadline::from_nanos(Some(-1)).is_err());
        assert!(Deadline::from_nanos(None).unwrap().is_none());
        let d = Deadline::from_nanos(Some(0)).unwrap();
        assert!(d.expired());
    }

    #[test]
    fn sleep_serves_the_deadline() {
        let start = Instant::now();
        sleep(Duration::from_millis(30));
        assert!(start.elapsed() >= Duration::from_millis(30));
    }
}
