//! Deadlines and blocking waits for the ms thread.
//!
//! Every blocking operation waits through [`wait_fd`] or [`Task::wait`], which park
//! the running `ms-rt` task so the server reactor and request handlers (other tasks)
//! run while it waits. A stop request wakes the wait and takes the runtime's
//! cancellation path.

use crate::rt;
use rustix::event::{self, EventfdFlags, PollFd, PollFlags};
use rustix::io;
use rustix::time::Timespec;
use std::cell::Cell;
use std::os::fd::{AsFd, AsRawFd, BorrowedFd, OwnedFd};
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

thread_local! {
    static TASKS: Cell<bool> = const { Cell::new(false) };
}

/// Makes this thread's waits park the running `ms-rt` task. Done by the first
/// server, whose reactor and request tasks need the scheduler; a thread without
/// one (a helper thread, a program that only dials out) waits by polling.
pub fn use_tasks() {
    TASKS.with(|t| t.set(true));
}

/// Waits until `fd` is ready for `interest` (hang-up and error count as ready, so
/// the next read or write reports them) or the deadline passes. With tasks enabled
/// the task parks, so the server reactor and request handlers run meanwhile.
/// Faults with the runtime's cancellation when a stop was requested.
pub fn wait_fd(fd: BorrowedFd<'_>, interest: Interest, deadline: Deadline) -> Wait {
    if TASKS.with(Cell::get) {
        wait_task(fd, interest, deadline)
    } else {
        wait_poll(fd, interest, deadline)
    }
}

fn wait_task(fd: BorrowedFd<'_>, interest: Interest, deadline: Deadline) -> Wait {
    rt::check_cancel();
    crate::http::server::give_up_reactor_role();
    let events = match interest {
        Interest::Read => 1,
        Interest::Write => 2,
    };
    let timeout = deadline
        .remaining()
        .map_or(-1, |d| d.as_nanos().min(i64::MAX as u128) as i64);
    let got = rt::wait_fd(fd.as_raw_fd(), events, timeout);
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

fn wait_poll(fd: BorrowedFd<'_>, interest: Interest, deadline: Deadline) -> Wait {
    let flags = match interest {
        Interest::Read => PollFlags::IN,
        Interest::Write => PollFlags::OUT,
    };
    loop {
        rt::check_cancel();
        let slice = deadline.remaining().map_or(SLICE, |left| left.min(SLICE));
        let timeout = Timespec {
            tv_sec: slice.as_secs() as _,
            tv_nsec: slice.subsec_nanos() as _,
        };
        let mut fds = [PollFd::new(&fd, flags)];
        match event::poll(&mut fds, Some(&timeout)) {
            Ok(_) if !fds[0].revents().is_empty() => return Wait::Ready,
            Err(io::Errno::INTR) | Ok(_) => {}
            Err(_) => return Wait::Ready,
        }
        if deadline.expired() {
            return Wait::TimedOut;
        }
    }
}

/// Sleeps for `d` while serving handlers; faults on cancellation.
pub fn sleep(d: Duration) {
    let deadline = Deadline::after(d);
    let pipe = match event::eventfd(0, EventfdFlags::CLOEXEC | EventfdFlags::NONBLOCK) {
        Ok(fd) => fd,
        Err(_) => {
            std::thread::sleep(d);
            return;
        }
    };
    let _ = wait_fd(pipe.as_fd(), Interest::Read, deadline);
}

/// A background computation whose completion wakes the ms thread.
pub struct Task<T> {
    rx: mpsc::Receiver<T>,
    wake: Arc<OwnedFd>,
}

/// Runs `f` on a helper thread. `f` must not call into the runtime.
pub fn spawn_blocking<T: Send + 'static>(
    f: impl FnOnce() -> T + Send + 'static,
) -> Option<Task<T>> {
    let wake = Arc::new(event::eventfd(0, EventfdFlags::CLOEXEC | EventfdFlags::NONBLOCK).ok()?);
    let (tx, rx) = mpsc::channel();
    let signal = wake.clone();
    std::thread::Builder::new()
        .name("ms-net-blocking".into())
        .spawn(move || {
            let value = f();
            let _ = tx.send(value);
            let _ = io::write(&*signal, &1u64.to_ne_bytes());
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
            if wait_fd(self.wake.as_fd(), Interest::Read, deadline) == Wait::TimedOut {
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
