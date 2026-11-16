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
use std::time::Duration;

/// A supplied timeout below zero.
#[derive(Clone, Copy, Debug)]
pub struct NegativeTimeout;

/// An optional absolute time limit, in nanoseconds on the runtime's monotonic clock
/// ([`rt::monotonic_ns`]), so a wait hands it to the scheduler as it is and reads no clock.
#[derive(Clone, Copy, Debug)]
pub struct Deadline(Option<i64>);

impl Deadline {
    pub const fn none() -> Deadline {
        Deadline(None)
    }

    pub fn after(d: Duration) -> Deadline {
        Deadline(Some(
            rt::monotonic_ns().saturating_add(d.as_nanos().min(i64::MAX as u128) as i64),
        ))
    }

    /// The deadline at `at_ns` on [`rt::monotonic_ns`].
    pub const fn at_ns(at_ns: i64) -> Deadline {
        Deadline(Some(at_ns))
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
        self.0
            .map(|t| Duration::from_nanos((t - rt::monotonic_ns()).max(0) as u64))
    }

    pub fn expired(&self) -> bool {
        self.0.is_some_and(|t| rt::monotonic_ns() >= t)
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
pub(crate) fn parks() -> bool {
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

/// Like [`wait_fd`] but reports a cancellation as `Err(Cancelled)` instead of jumping, so the
/// caller's frames unwind with ordinary returns and run their destructors. The error must reach
/// the FFI boundary (`ffi::report`), which then runs the cancellation path.
pub fn try_wait_fd(
    fd: Borrowed<'_>,
    interest: Interest,
    deadline: Deadline,
) -> Result<Wait, rt::Cancelled> {
    if !parks() {
        return Ok(wait_poll(fd, interest, deadline));
    }
    if rt::cancel_requested() {
        return Err(rt::Cancelled);
    }
    let events = match interest {
        Interest::Read => 1,
        Interest::Write => 2,
    };
    let got = rt::wait_fd_at(fd, events, deadline.0);
    if got & 16 != 0 {
        return Err(rt::Cancelled);
    }
    Ok(if got & 8 != 0 && got & 7 == 0 {
        Wait::TimedOut
    } else {
        Wait::Ready
    })
}

fn wait_task(fd: Borrowed<'_>, interest: Interest, deadline: Deadline) -> Wait {
    rt::check_cancel();
    let events = match interest {
        Interest::Read => 1,
        Interest::Write => 2,
    };
    let got = rt::wait_fd_at(fd, events, deadline.0);
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
    let got = token.park_at(deadline.0);
    if got & 16 != 0 {
        rt::cancelled();
    }
    if got == 0 {
        Wait::Ready
    } else {
        Wait::TimedOut
    }
}

/// Like [`wait_token`] but reports a cancellation as `Err(Cancelled)` (see [`try_wait_fd`]).
pub fn try_wait_token(token: &rt::Token, deadline: Deadline) -> Result<Wait, rt::Cancelled> {
    if rt::cancel_pending() {
        return Err(rt::Cancelled);
    }
    let got = token.park_at(deadline.0);
    if got & 16 != 0 {
        return Err(rt::Cancelled);
    }
    Ok(if got == 0 {
        Wait::Ready
    } else {
        Wait::TimedOut
    })
}

/// The wait of a thread the runtime's scheduler does not run (a unit-test thread): one blocking
/// poll of the descriptor until it is ready or the deadline passes. No cancellation can reach
/// such a thread, so nothing needs to be re-checked.
fn wait_poll(fd: Borrowed<'_>, interest: Interest, deadline: Deadline) -> Wait {
    loop {
        if sys::poll_one(fd, interest == Interest::Write, deadline.remaining()) {
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
) -> Result<Option<O>, rt::Cancelled> {
    if !parks() {
        return Ok(Some(f(&input)));
    }
    rt::check()?;
    let timeout = deadline
        .remaining()
        .map_or(-1, |left| left.as_nanos().min(i64::MAX as u128) as i64);
    ms_rt::glue::pool::try_run(lane, input, f, rt::within_waiter(timeout))
        .map_err(|_| rt::Cancelled)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Instant;

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

    /// A wait with no deadline returns on the event and not before it: the descriptor becomes
    /// readable only after the flag is set, and nothing here sleeps or times.
    #[test]
    fn an_unbounded_wait_returns_on_the_event_only() {
        use crate::sys::AsSock;
        use std::io::Write;
        use std::net::{TcpListener, TcpStream};
        use std::sync::atomic::{AtomicBool, Ordering};
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let mut client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let (server, _) = listener.accept().unwrap();
        let (go_tx, go_rx) = std::sync::mpsc::channel::<()>();
        let written = AtomicBool::new(false);
        let written_ref = &written;
        std::thread::scope(|scope| {
            scope.spawn(move || {
                go_rx.recv().unwrap();
                written_ref.store(true, Ordering::SeqCst);
                client.write_all(b"x").unwrap();
            });
            go_tx.send(()).unwrap();
            let got = wait_fd(server.as_sock(), Interest::Read, Deadline::none());
            assert_eq!(got, Wait::Ready);
            assert!(written.load(Ordering::SeqCst));
        });
    }

    #[test]
    fn a_wait_with_a_deadline_and_no_event_times_out() {
        use crate::sys::AsSock;
        use std::net::{TcpListener, TcpStream};
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let _client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let (server, _) = listener.accept().unwrap();
        let got = wait_fd(
            server.as_sock(),
            Interest::Read,
            Deadline::after(Duration::from_millis(20)),
        );
        // A real deadline: time has to pass for it.
        assert_eq!(got, Wait::TimedOut);
    }
}
