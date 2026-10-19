//! Unix: descriptors, `poll(2)`, `eventfd` and `epoll`.

use super::Ev;
use crate::rt;
use rustix::event::{self, EventfdFlags, PollFd, PollFlags, epoll};
use rustix::io;
use rustix::time::Timespec;
use std::cell::RefCell;
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
pub struct Wake(OwnedFd);

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

/// The server's set of watched sockets.
pub struct Poller {
    epoll: OwnedFd,
    buf: RefCell<Vec<epoll::Event>>,
}

fn to_flags(ev: Ev) -> epoll::EventFlags {
    let mut flags = epoll::EventFlags::empty();
    if ev.contains(Ev::IN) {
        flags |= epoll::EventFlags::IN;
    }
    if ev.contains(Ev::OUT) {
        flags |= epoll::EventFlags::OUT;
    }
    flags
}

fn from_flags(flags: epoll::EventFlags) -> Ev {
    let mut ev = Ev::NONE;
    if flags.contains(epoll::EventFlags::IN) {
        ev = ev | Ev::IN;
    }
    if flags.contains(epoll::EventFlags::OUT) {
        ev = ev | Ev::OUT;
    }
    if flags.intersects(epoll::EventFlags::HUP | epoll::EventFlags::ERR | epoll::EventFlags::RDHUP)
    {
        ev = ev | Ev::HUP;
    }
    ev
}

impl Default for Poller {
    fn default() -> Poller {
        Poller::new()
    }
}

impl Poller {
    pub fn new() -> Poller {
        Poller {
            epoll: epoll::create(epoll::CreateFlags::CLOEXEC).expect("epoll"),
            buf: RefCell::new(Vec::new()),
        }
    }

    pub fn add(&self, sock: Borrowed<'_>, token: u64, ev: Ev) -> bool {
        epoll::add(
            &self.epoll,
            sock,
            epoll::EventData::new_u64(token),
            to_flags(ev),
        )
        .is_ok()
    }

    pub fn modify(&self, sock: Borrowed<'_>, token: u64, ev: Ev) {
        let _ = epoll::modify(
            &self.epoll,
            sock,
            epoll::EventData::new_u64(token),
            to_flags(ev),
        );
    }

    pub fn delete(&self, sock: Borrowed<'_>) {
        let _ = epoll::delete(&self.epoll, sock);
    }

    /// Collects up to `max` ready `(token, events)` pairs into `out` without blocking.
    pub fn poll(&self, out: &mut Vec<(u64, Ev)>, max: usize) {
        out.clear();
        let mut buf = self.buf.borrow_mut();
        buf.resize(
            max,
            epoll::Event {
                flags: epoll::EventFlags::empty(),
                data: epoll::EventData::new_u64(0),
            },
        );
        let timeout = Timespec {
            tv_sec: 0,
            tv_nsec: 0,
        };
        let n = epoll::wait(&self.epoll, &mut buf[..], Some(&timeout)).unwrap_or_default();
        out.extend(buf[..n].iter().map(|e| (e.data.u64(), from_flags(e.flags))));
    }

    /// Parks the running task until something may be ready (or 50 ms pass); returns
    /// the runtime's ready bits.
    pub fn park(&self) -> u32 {
        rt::wait_fd(self.epoll.as_fd(), 1, 50_000_000)
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
