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

use std::collections::HashMap;
use std::hash::Hash;
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

/// The interest to register for `ev`: watching nothing still watches for readability, so
/// hang-up and error are reported.
pub(crate) fn mio_interest(ev: Ev) -> mio::Interest {
    match (ev.contains(Ev::IN), ev.contains(Ev::OUT)) {
        (_, false) => mio::Interest::READABLE,
        (false, true) => mio::Interest::WRITABLE,
        (true, true) => mio::Interest::READABLE | mio::Interest::WRITABLE,
    }
}

/// What mio reported for one registration.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Raised {
    pub token: u64,
    pub read: bool,
    pub write: bool,
    pub hup: bool,
}

impl From<&mio::event::Event> for Raised {
    fn from(e: &mio::event::Event) -> Raised {
        Raised {
            token: e.token().0 as u64,
            read: e.is_readable(),
            write: e.is_writable(),
            hup: e.is_error() || e.is_read_closed() || e.is_write_closed(),
        }
    }
}

/// The sockets of a [`Poller`], found by handle (to update or delete) and by token (to
/// resolve an event).
pub(crate) struct Sockets<R> {
    by_handle: HashMap<R, (u64, Ev)>,
    by_token: HashMap<u64, R>,
}

impl<R> Default for Sockets<R> {
    fn default() -> Sockets<R> {
        Sockets {
            by_handle: HashMap::new(),
            by_token: HashMap::new(),
        }
    }
}

impl<R: Copy + Eq + Hash> Sockets<R> {
    pub fn set(&mut self, handle: R, token: u64, ev: Ev) {
        self.by_handle.insert(handle, (token, ev));
        self.by_token.insert(token, handle);
    }

    pub fn remove(&mut self, handle: R) {
        if let Some((token, _)) = self.by_handle.remove(&handle) {
            self.by_token.remove(&token);
        }
    }

    /// Turns what mio raised into `(token, events)` pairs.
    ///
    /// mio reports edges, the server reads and writes as if readiness were level-triggered,
    /// so a socket that reported a read or write is passed to `rearm`: the kernel then
    /// reports it again while it is still ready. A socket with no interest in the direction
    /// reported is dropped without re-arming, so unread input cannot spin the loop; only
    /// hang-up and error get through.
    pub fn report(
        &self,
        raised: impl Iterator<Item = Raised>,
        max: usize,
        out: &mut Vec<(u64, Ev)>,
        mut rearm: impl FnMut(R, u64, Ev),
    ) {
        for r in raised.take(max) {
            let Some(&handle) = self.by_token.get(&r.token) else {
                continue;
            };
            let Some(&(_, want)) = self.by_handle.get(&handle) else {
                continue;
            };
            let mut ev = Ev::NONE;
            if r.read && want.contains(Ev::IN) {
                ev = ev | Ev::IN;
            }
            if r.write && want.contains(Ev::OUT) {
                ev = ev | Ev::OUT;
            }
            let moved = ev != Ev::NONE;
            if r.hup {
                ev = ev | Ev::HUP;
            }
            if ev == Ev::NONE {
                continue;
            }
            if moved {
                rearm(handle, r.token, want);
            }
            out.push((r.token, ev));
        }
    }
}
