//! Deadlines and blocking waits for the ms thread.
//!
//! Every blocking operation waits through [`wait_fd`] or [`Task::wait`]. The
//! wait polls the descriptor in short slices so a stop request (the cancel
//! flag) is noticed, and runs queued server handlers while the ms thread would
//! otherwise sit idle (see [`crate::pump`]).

use crate::{pump, rt};
use rustix::event::{self, EventfdFlags, PollFd, PollFlags};
use rustix::io;
use rustix::time::Timespec;
use std::os::fd::{AsFd, BorrowedFd, OwnedFd};
use std::sync::Arc;
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// Longest a wait sleeps before it re-checks the cancel flag.
const SLICE: Duration = Duration::from_millis(50);

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

fn slice_for(deadline: Deadline) -> Duration {
    match deadline.remaining() {
        Some(left) => left.min(SLICE),
        None => SLICE,
    }
}

fn poll_timeout(d: Duration) -> Timespec {
    Timespec {
        tv_sec: d.as_secs() as _,
        tv_nsec: d.subsec_nanos() as _,
    }
}

/// Waits until `fd` is ready for `interest` (hang-up and error count as ready, so
/// the next read or write reports them) or the deadline passes. Faults with the
/// runtime's cancellation when a stop was requested.
pub fn wait_fd(fd: BorrowedFd<'_>, interest: Interest, deadline: Deadline) -> Wait {
    let flags = match interest {
        Interest::Read => PollFlags::IN,
        Interest::Write => PollFlags::OUT,
    };
    let service = pump::current();
    loop {
        rt::check_cancel();
        let timeout = poll_timeout(slice_for(deadline));
        let mut fds = [
            PollFd::new(&fd, flags),
            PollFd::from_borrowed_fd(service.as_ref().map_or(fd, |s| s.fd()), PollFlags::IN),
        ];
        let n = if service.is_some() { 2 } else { 1 };
        match event::poll(&mut fds[..n], Some(&timeout)) {
            Ok(_) => {
                if !fds[0].revents().is_empty() {
                    return Wait::Ready;
                }
                if n == 2 && !fds[1].revents().is_empty() {
                    if let Some(s) = &service {
                        s.service();
                    }
                    continue;
                }
            }
            Err(io::Errno::INTR) => {}
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
