//! Unix: descriptors, `poll(2)`, `eventfd` (a pipe off Linux) and a mio readiness set.

use super::{Ev, Raised};
use crate::idmap::IdMap;
use crate::rt;
use mio::unix::SourceFd;
#[cfg(any(target_os = "linux", target_os = "android"))]
use rustix::event::EventfdFlags;
use rustix::event::{self, PollFd, PollFlags};
use rustix::io;
use rustix::time::Timespec;
use std::cell::{Cell, RefCell};
use std::mem::ManuallyDrop;
use std::os::fd::{AsFd, AsRawFd, BorrowedFd, OwnedFd};
use std::time::Duration;

/// A borrowed socket handle.
pub type Borrowed<'a> = BorrowedFd<'a>;
/// The handle's raw form, as the runtime takes it.
pub type Raw = i32;

/// The borrowed handle of a socket-like value.
pub trait AsSock {
    fn as_sock(&self) -> Borrowed<'_>;
}

impl<T: AsFd + ?Sized> AsSock for T {
    fn as_sock(&self) -> Borrowed<'_> {
        self.as_fd()
    }
}

pub fn raw(sock: Borrowed<'_>) -> Raw {
    sock.as_raw_fd()
}

/// Waits up to `slice` for one socket; `true` when it is ready, hung up or failed.
pub fn poll_one(sock: Borrowed<'_>, write: bool, slice: Duration) -> bool {
    let flags = if write { PollFlags::OUT } else { PollFlags::IN };
    let timeout = Timespec {
        tv_sec: slice.as_secs() as _,
        tv_nsec: slice.subsec_nanos() as _,
    };
    let mut fds = [PollFd::new(&sock, flags)];
    match event::poll(&mut fds, Some(&timeout)) {
        Ok(_) => !fds[0].revents().is_empty(),
        Err(io::Errno::INTR) => false,
        Err(_) => true,
    }
}

/// A handle another thread can signal to make a socket readable.
#[cfg(any(target_os = "linux", target_os = "android"))]
pub struct Wake(OwnedFd);

#[cfg(any(target_os = "linux", target_os = "android"))]
impl Wake {
    pub fn new() -> Option<Wake> {
        event::eventfd(0, EventfdFlags::CLOEXEC | EventfdFlags::NONBLOCK)
            .ok()
            .map(Wake)
    }

    /// Makes [`Wake::sock`] readable (and keeps it so).
    pub fn notify(&self) {
        let _ = io::write(&self.0, &1u64.to_ne_bytes());
    }

    pub fn sock(&self) -> Borrowed<'_> {
        self.0.as_fd()
    }
}

/// A handle another thread can signal to make a socket readable: a pipe, as there is no
/// `eventfd` here.
#[cfg(not(any(target_os = "linux", target_os = "android")))]
pub struct Wake {
    read: OwnedFd,
    write: OwnedFd,
}

#[cfg(not(any(target_os = "linux", target_os = "android")))]
impl Wake {
    pub fn new() -> Option<Wake> {
        let (read, write) = rustix::pipe::pipe().ok()?;
        for fd in [&read, &write] {
            rustix::io::fcntl_setfd(fd, rustix::io::FdFlags::CLOEXEC).ok()?;
            rustix::fs::fcntl_setfl(fd, rustix::fs::OFlags::NONBLOCK).ok()?;
        }
        Some(Wake { read, write })
    }

    /// Makes [`Wake::sock`] readable (and keeps it so).
    pub fn notify(&self) {
        let _ = io::write(&self.write, &[1u8]);
    }

    pub fn sock(&self) -> Borrowed<'_> {
        self.read.as_fd()
    }
}

impl Default for Poller {
    fn default() -> Poller {
        Poller::new()
    }
}

/// The server's set of watched sockets, on mio.
///
/// Each socket is registered once, edge-triggered for both directions, and stays registered
/// until [`Poller::delete`]. Interest is kept here, not in the kernel: an edge in a direction
/// nobody wants is remembered as readiness and reported once the interest returns. Readiness
/// is cleared only by [`Poller::consumed`], which callers invoke when an operation would
/// block, so a remembered edge is never lost and a stale one costs one extra attempt.
pub struct Poller {
    /// Never closed: the runtime keeps this descriptor registered between parks (`WAIT_KEEP`)
    /// and cannot tell when its number is reused, so a closed poller (a test thread's, say)
    /// would leave a later poller on the same number unwatched.
    poll: ManuallyDrop<RefCell<mio::Poll>>,
    registry: mio::Registry,
    events: RefCell<mio::Events>,
    sockets: RefCell<IdMap<Raw, Watched>>,
    by_token: RefCell<IdMap<u64, Raw>>,
    /// Tokens whose remembered readiness met new interest, reported by the next poll.
    pending: RefCell<Vec<u64>>,
    /// Registered in `poll` under `WAKE_TOKEN`: wakes a parked reactor when work appears
    /// that the kernel does not report (pending tokens, an earlier deadline, queued handlers).
    wake: Wake,
    parked: Cell<bool>,
}

const WAKE_TOKEN: u64 = u64::MAX;

struct Watched {
    token: u64,
    want: Ev,
    ready: Ev,
}

const MAX_EVENTS: usize = 64;

impl Poller {
    pub fn new() -> Poller {
        let poll = mio::Poll::new().expect("poller");
        let registry = poll.registry().try_clone().expect("poller registry");
        let wake = Wake::new().expect("poller wake-up");
        let wake_fd = wake.sock().as_raw_fd();
        registry
            .register(
                &mut SourceFd(&wake_fd),
                mio::Token(WAKE_TOKEN as usize),
                mio::Interest::READABLE,
            )
            .expect("poller wake-up registration");
        Poller {
            poll: ManuallyDrop::new(RefCell::new(poll)),
            registry,
            events: RefCell::new(mio::Events::with_capacity(MAX_EVENTS)),
            sockets: RefCell::new(IdMap::default()),
            by_token: RefCell::new(IdMap::default()),
            pending: RefCell::new(Vec::new()),
            wake,
            parked: Cell::new(false),
        }
    }

    /// Wakes the reactor task if it is parked, so its next `poll` sees work the kernel will not
    /// report. Costs one `write` only while parked.
    pub fn kick(&self) {
        if self.parked.replace(false) {
            self.wake.notify();
        }
    }

    pub fn add(&self, sock: Borrowed<'_>, token: u64, ev: Ev) -> bool {
        let fd = sock.as_raw_fd();
        if self.sockets.borrow().contains_key(&fd) {
            self.modify(sock, token, ev);
            return true;
        }
        let interest = mio::Interest::READABLE | mio::Interest::WRITABLE;
        if self
            .registry
            .register(&mut SourceFd(&fd), mio::Token(token as usize), interest)
            .is_err()
        {
            return false;
        }
        self.sockets.borrow_mut().insert(
            fd,
            Watched {
                token,
                want: ev,
                ready: Ev::NONE,
            },
        );
        self.by_token.borrow_mut().insert(token, fd);
        true
    }

    pub fn modify(&self, sock: Borrowed<'_>, token: u64, ev: Ev) {
        let fd = sock.as_raw_fd();
        let mut sockets = self.sockets.borrow_mut();
        let Some(w) = sockets.get_mut(&fd) else {
            drop(sockets);
            self.add(sock, token, ev);
            return;
        };
        let gained = Ev(ev.0 & !w.want.0);
        w.want = ev;
        if w.ready.intersects(gained) || w.ready.contains(Ev::HUP) && gained != Ev::NONE {
            self.pending.borrow_mut().push(w.token);
            drop(sockets);
            self.kick();
        }
    }

    /// Forgets that `sock` was ready for `ev`: an operation in that direction would block, so
    /// the kernel reports the next edge.
    pub fn consumed(&self, sock: Borrowed<'_>, ev: Ev) {
        if let Some(w) = self.sockets.borrow_mut().get_mut(&sock.as_raw_fd()) {
            w.ready = Ev(w.ready.0 & !ev.0);
        }
    }

    pub fn delete(&self, sock: Borrowed<'_>) {
        let fd = sock.as_raw_fd();
        if let Some(w) = self.sockets.borrow_mut().remove(&fd) {
            let _ = self.registry.deregister(&mut SourceFd(&fd));
            self.by_token.borrow_mut().remove(&w.token);
        }
    }

    /// Collects ready `(token, events)` pairs into `out` without blocking. Returns how many
    /// kernel events were read: fewer than `max` means the set was drained.
    pub fn poll(&self, out: &mut Vec<(u64, Ev)>, max: usize) -> usize {
        out.clear();
        let mut sockets = self.sockets.borrow_mut();
        let by_token = self.by_token.borrow();
        for token in self.pending.borrow_mut().drain(..) {
            let Some(w) = by_token.get(&token).and_then(|fd| sockets.get(fd)) else {
                continue;
            };
            let ev = Ev(w.ready.0 & (w.want.0 | Ev::HUP.0));
            if ev != Ev::NONE && !out.iter().any(|&(t, _)| t == token) {
                out.push((token, ev));
            }
        }
        let mut events = self.events.borrow_mut();
        if self
            .poll
            .borrow_mut()
            .poll(&mut events, Some(Duration::ZERO))
            .is_err()
        {
            return 0;
        }
        let mut raw = 0;
        for e in events.iter().take(max) {
            raw += 1;
            if e.token().0 == WAKE_TOKEN as usize {
                let mut buf = [0u8; 8];
                while io::read(self.wake.sock(), &mut buf).is_ok() {}
                continue;
            }
            let r = Raised::from(e);
            let Some(w) = by_token.get(&r.token).and_then(|fd| sockets.get_mut(fd)) else {
                continue;
            };
            let mut got = Ev::NONE;
            if r.read {
                got = got | Ev::IN;
            }
            if r.write {
                got = got | Ev::OUT;
            }
            if r.hup {
                got = got | Ev::HUP;
            }
            w.ready = w.ready | got;
            let ev = Ev(w.ready.0 & (w.want.0 | Ev::HUP.0));
            if ev != Ev::NONE {
                out.push((r.token, ev));
            }
        }
        raw
    }

    /// Parks the running task until something may be ready or `timeout_ns` passes (negative:
    /// no limit); returns the runtime's ready bits. The registration in the runtime's poller
    /// is kept between parks (edge-triggered), which is sound because the reactor drains
    /// this set before every park.
    pub fn park(&self, timeout_ns: i64) -> u32 {
        let fd = self.poll.borrow().as_raw_fd();
        self.parked.set(true);
        // SAFETY: the descriptor belongs to `self.poll`, which outlives the call.
        let got = rt::wait_fd(
            unsafe { BorrowedFd::borrow_raw(fd) },
            1 | rt::WAIT_KEEP,
            timeout_ns,
        );
        self.parked.set(false);
        got
    }
}

impl Drop for Poller {
    fn drop(&mut self) {
        // `park` keeps this descriptor registered in the runtime's poller.
        rt::forget_fd(self.poll.borrow().as_raw_fd());
    }
}

/// Whether a failed nonblocking `connect` is merely under way.
pub fn connect_in_progress(e: &std::io::Error) -> bool {
    e.raw_os_error() == Some(io::Errno::INPROGRESS.raw_os_error())
        || e.kind() == std::io::ErrorKind::WouldBlock
}

/// Options for a listening TCP socket before `bind`.
pub fn prepare_listener(sock: &socket2::Socket) -> std::io::Result<()> {
    sock.set_reuse_address(true)
}

/// Options for a freshly bound datagram socket.
pub fn prepare_udp(_sock: &std::net::UdpSocket) -> std::io::Result<()> {
    Ok(())
}
