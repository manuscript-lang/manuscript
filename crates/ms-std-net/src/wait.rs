//! Deadlines and blocking waits for the ms thread.
//!
//! Every blocking operation waits through [`wait_fd`] or [`Task::wait`], which park
//! the running `ms-rt` task so the server reactor and request handlers (other tasks)
//! run while it waits. A stop request wakes the wait and takes the runtime's
//! cancellation path.
//!
//! Unit tests run on many threads, which the runtime's scheduler does not support: there a
//! thread parks only once it serves (see `use_tasks`), and otherwise polls in slices.

use crate::rt;
use crate::sys::{self, Borrowed, Wake};
#[cfg(test)]
use std::cell::Cell;
use std::sync::Arc;
use std::sync::mpsc;
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
    TASKS.with(|t| t.set(true));
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
    crate::http::server::give_up_reactor_role();
    let events = match interest {
        Interest::Read => 1,
        Interest::Write => 2,
    };
    let timeout = deadline
        .remaining()
        .map_or(-1, |d| d.as_nanos().min(i64::MAX as u128) as i64);
    let got = rt::wait_fd(fd, events, timeout);
    if got & 16 != 0 {
        rt::cancelled();
    }
    if got & 8 != 0 && got & 7 == 0 {
        Wait::TimedOut
    } else {
        Wait::Ready
    }
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
    crate::http::server::give_up_reactor_role();
    if rt::sleep(d.as_nanos().min(i64::MAX as u128) as i64) & 16 != 0 {
        rt::cancelled();
    }
}

/// A background computation whose completion wakes the ms thread.
pub struct Task<T> {
    rx: mpsc::Receiver<T>,
    wake: Arc<Wake>,
}

/// Runs `f` on a helper thread. `f` must not call into the runtime.
pub fn spawn_blocking<T: Send + 'static>(
    f: impl FnOnce() -> T + Send + 'static,
) -> Option<Task<T>> {
    let wake = Arc::new(Wake::new()?);
    let signal = wake.clone();
    let (tx, rx) = mpsc::channel();
    std::thread::Builder::new()
        .name("ms-net-blocking".into())
        .spawn(move || {
            let value = f();
            let _ = tx.send(value);
            signal.notify();
        })
        .ok()?;
    Some(Task { rx, wake })
}

impl<T> Task<T> {
    /// Waits for the result; `None` when the deadline passes first.
    pub fn wait(self, deadline: Deadline) -> Option<T> {
        loop {
            if let Ok(v) = self.rx.try_recv() {
                return Some(v);
            }
            if wait_fd(self.wake.sock(), Interest::Read, deadline) == Wait::TimedOut {
                return self.rx.try_recv().ok();
            }
        }
    }
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

    #[test]
    fn tasks_deliver_and_time_out() {
        let t = spawn_blocking(|| 7).unwrap();
        assert_eq!(t.wait(Deadline::after(Duration::from_secs(2))), Some(7));
        let t = spawn_blocking(|| {
            std::thread::sleep(Duration::from_millis(300));
            1
        })
        .unwrap();
        assert_eq!(t.wait(Deadline::after(Duration::from_millis(20))), None);
    }
}
