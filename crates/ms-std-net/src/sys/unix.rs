//! Unix: descriptors, `poll(2)`, `eventfd` (a pipe off Linux) and a mio readiness set.

use super::Ev;
use crate::rt;
use mio::unix::SourceFd;
#[cfg(any(target_os = "linux", target_os = "android"))]
use rustix::event::EventfdFlags;
use rustix::event::{self, PollFd, PollFlags};
use rustix::io;
use rustix::time::Timespec;
use std::cell::RefCell;
use std::collections::HashMap;
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
/// mio reports edges, the server reads and writes as if readiness were level-triggered, so
/// a socket is re-registered each time it is reported: the kernel then reports it again
/// while it is still ready. A socket with no interest is kept registered, for hang-up and
/// error only; its reads and writes are dropped without re-arming.
pub struct Poller {
    poll: RefCell<mio::Poll>,
    registry: mio::Registry,
    events: RefCell<mio::Events>,
    sockets: RefCell<Sockets>,
}

/// The registered sockets, found by descriptor (to update or delete) and by token (to
/// resolve an event).
#[derive(Default)]
struct Sockets {
    by_fd: HashMap<Raw, (u64, Ev)>,
    by_token: HashMap<u64, Raw>,
}

impl Sockets {
    fn set(&mut self, fd: Raw, token: u64, ev: Ev) {
        self.by_fd.insert(fd, (token, ev));
        self.by_token.insert(token, fd);
    }

    fn remove(&mut self, fd: Raw) {
        if let Some((token, _)) = self.by_fd.remove(&fd) {
            self.by_token.remove(&token);
        }
    }
}

const MAX_EVENTS: usize = 64;

fn interest(ev: Ev) -> mio::Interest {
    match (ev.contains(Ev::IN), ev.contains(Ev::OUT)) {
        (_, false) => mio::Interest::READABLE,
        (false, true) => mio::Interest::WRITABLE,
        (true, true) => mio::Interest::READABLE | mio::Interest::WRITABLE,
    }
}

impl Poller {
    pub fn new() -> Poller {
        let poll = mio::Poll::new().expect("poller");
        let registry = poll.registry().try_clone().expect("poller registry");
        Poller {
            poll: RefCell::new(poll),
            registry,
            events: RefCell::new(mio::Events::with_capacity(MAX_EVENTS)),
            sockets: RefCell::new(Sockets::default()),
        }
    }

    /// Registers `fd` for `ev`, or updates an earlier registration.
    fn arm(&self, fd: Raw, token: u64, ev: Ev) -> std::io::Result<()> {
        let (mut source, token) = (SourceFd(&fd), mio::Token(token as usize));
        match self.registry.reregister(&mut source, token, interest(ev)) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                self.registry.register(&mut source, token, interest(ev))
            }
            r => r,
        }
    }

    pub fn add(&self, sock: Borrowed<'_>, token: u64, ev: Ev) -> bool {
        let fd = sock.as_raw_fd();
        let armed = self.arm(fd, token, ev).is_ok();
        if armed {
            self.sockets.borrow_mut().set(fd, token, ev);
        }
        armed
    }

    pub fn modify(&self, sock: Borrowed<'_>, token: u64, ev: Ev) {
        let fd = sock.as_raw_fd();
        if self.arm(fd, token, ev).is_ok() {
            self.sockets.borrow_mut().set(fd, token, ev);
        }
    }

    pub fn delete(&self, sock: Borrowed<'_>) {
        let fd = sock.as_raw_fd();
        let _ = self.registry.deregister(&mut SourceFd(&fd));
        self.sockets.borrow_mut().remove(fd);
    }

    /// Collects up to `max` ready `(token, events)` pairs into `out` without blocking.
    pub fn poll(&self, out: &mut Vec<(u64, Ev)>, max: usize) {
        out.clear();
        let mut events = self.events.borrow_mut();
        if self
            .poll
            .borrow_mut()
            .poll(&mut events, Some(Duration::ZERO))
            .is_err()
        {
            return;
        }
        let sockets = self.sockets.borrow();
        for e in events.iter().take(max) {
            let token = e.token().0 as u64;
            let Some(&fd) = sockets.by_token.get(&token) else {
                continue;
            };
            let Some(&(_, interest)) = sockets.by_fd.get(&fd) else {
                continue;
            };
            let mut ev = Ev::NONE;
            if e.is_readable() && interest.contains(Ev::IN) {
                ev = ev | Ev::IN;
            }
            if e.is_writable() && interest.contains(Ev::OUT) {
                ev = ev | Ev::OUT;
            }
            let reads_and_writes = ev;
            if e.is_error() || e.is_read_closed() || e.is_write_closed() {
                ev = ev | Ev::HUP;
            }
            if ev == Ev::NONE {
                continue;
            }
            if reads_and_writes != Ev::NONE {
                // Report it again next time while it stays ready.
                let _ = self.arm(fd, token, interest);
            }
            out.push((token, ev));
        }
    }

    /// Parks the running task until something may be ready (or 50 ms pass); returns
    /// the runtime's ready bits.
    pub fn park(&self) -> u32 {
        let fd = self.poll.borrow().as_raw_fd();
        // SAFETY: the descriptor belongs to `self.poll`, which outlives the call.
        rt::wait_fd(unsafe { BorrowedFd::borrow_raw(fd) }, 1, 50_000_000)
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
