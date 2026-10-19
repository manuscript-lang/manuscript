//! Unix: descriptors, `poll(2)`, `eventfd` (a pipe off Linux) and `epoll` (`kqueue` off Linux).

use super::Ev;
use crate::rt;
use rustix::event::{self, PollFd, PollFlags};
#[cfg(any(target_os = "linux", target_os = "android"))]
use rustix::event::{EventfdFlags, epoll};
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

/// The server's set of watched sockets.
#[cfg(any(target_os = "linux", target_os = "android"))]
pub struct Poller {
    epoll: OwnedFd,
    buf: RefCell<Vec<epoll::Event>>,
}

#[cfg(any(target_os = "linux", target_os = "android"))]
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

#[cfg(any(target_os = "linux", target_os = "android"))]
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

#[cfg(any(target_os = "linux", target_os = "android"))]
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

/// The server's set of watched sockets.
#[cfg(not(any(target_os = "linux", target_os = "android")))]
pub struct Poller {
    queue: OwnedFd,
    events: RefCell<Vec<rustix::event::kqueue::Event>>,
}

#[cfg(not(any(target_os = "linux", target_os = "android")))]
impl Poller {
    pub fn new() -> Poller {
        Poller {
            queue: rustix::event::kqueue::kqueue().expect("kqueue"),
            events: RefCell::new(Vec::new()),
        }
    }

    /// Applies the changes for one descriptor: each direction is enabled when wanted and
    /// removed otherwise.
    fn apply(&self, sock: Borrowed<'_>, token: u64, ev: Ev) -> bool {
        use rustix::event::kqueue::{self, Event, EventFilter};
        let raw = sock.as_raw_fd();
        let udata = token as usize as *mut std::ffi::c_void;
        let mut ok = true;
        for (filter, wanted) in [
            (EventFilter::Read(raw), ev.contains(Ev::IN)),
            (EventFilter::Write(raw), ev.contains(Ev::OUT)),
        ] {
            let flags = if wanted {
                kqueue::EventFlags::ADD | kqueue::EventFlags::ENABLE
            } else {
                kqueue::EventFlags::DELETE
            };
            let change = [Event::new(filter, flags, udata)];
            // SAFETY: `sock` stays open while it is registered; callers delete it before
            // closing it (closing also drops the registration).
            let sent =
                unsafe { kqueue::kevent(&self.queue, &change, &mut Vec::<Event>::new(), None) };
            // Deleting a direction that was never added is not a failure.
            if sent.is_err() && wanted {
                ok = false;
            }
        }
        ok
    }

    pub fn add(&self, sock: Borrowed<'_>, token: u64, ev: Ev) -> bool {
        self.apply(sock, token, ev)
    }

    pub fn modify(&self, sock: Borrowed<'_>, token: u64, ev: Ev) {
        self.apply(sock, token, ev);
    }

    pub fn delete(&self, sock: Borrowed<'_>) {
        self.apply(sock, 0, Ev::NONE);
    }

    /// Collects up to `max` ready `(token, events)` pairs into `out` without blocking.
    pub fn poll(&self, out: &mut Vec<(u64, Ev)>, max: usize) {
        use rustix::event::kqueue::{self, EventFilter};
        out.clear();
        let mut events = self.events.borrow_mut();
        events.clear();
        events.reserve(max);
        // SAFETY: no change list is passed, so no descriptor is referenced.
        let got = unsafe { kqueue::kevent(&self.queue, &[], &mut *events, Some(Duration::ZERO)) };
        if got.is_err() {
            return;
        }
        for e in events.iter() {
            let mut ev = match e.filter() {
                EventFilter::Read(_) => Ev::IN,
                EventFilter::Write(_) => Ev::OUT,
                _ => Ev::NONE,
            };
            if e.flags()
                .intersects(kqueue::EventFlags::EOF | kqueue::EventFlags::ERROR)
            {
                ev = ev | Ev::HUP;
            }
            out.push((e.udata() as usize as u64, ev));
        }
    }

    /// Parks the running task until something may be ready (or 50 ms pass); returns
    /// the runtime's ready bits.
    pub fn park(&self) -> u32 {
        rt::wait_fd(self.queue.as_fd(), 1, 50_000_000)
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
