//! The operating-system surface of this crate, in one place.
//!
//! Everything platform specific lives behind this module: the borrowed handle type
//! and the way to get one (`AsSock`), one-socket polling, a thread-safe wake-up
//! handle, the server's readiness set (`Poller`), and a few socket options. The rest of
//! the crate is written against these names and holds no `cfg`.
//!
//! * Unix: file descriptors, `poll(2)`, `eventfd`, `epoll`.
//! * Windows: `SOCKET`s, `WSAPoll`, a loopback datagram socket as the wake-up, and a
//!   `WSAPoll` set rebuilt per poll. Winsock has no pollable handle for a set of
//!   sockets, so the server reactor parks in short slices instead (see
//!   `Poller::park`).

use std::ops::BitOr;

#[cfg(unix)]
mod unix;
#[cfg(unix)]
pub use unix::*;

#[cfg(windows)]
mod windows;
#[cfg(windows)]
pub use windows::*;

/// Readiness of a socket in a [`Poller`], as interest and as report.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Ev(u8);

impl Ev {
    pub const NONE: Ev = Ev(0);
    /// Readable (or a pending accept).
    pub const IN: Ev = Ev(1);
    /// Writable.
    pub const OUT: Ev = Ev(2);
    /// Hang-up or error; only ever reported.
    pub const HUP: Ev = Ev(4);

    pub fn contains(self, other: Ev) -> bool {
        self.0 & other.0 == other.0
    }

    pub fn intersects(self, other: Ev) -> bool {
        self.0 & other.0 != 0
    }
}

impl BitOr for Ev {
    type Output = Ev;

    fn bitor(self, rhs: Ev) -> Ev {
        Ev(self.0 | rhs.0)
    }
}
