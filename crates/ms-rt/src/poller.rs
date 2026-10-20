//! The scheduler's descriptor poller. A task parks on one descriptor at a time; each
//! registration is one-shot and level-like: registering an already-ready descriptor reports
//! it at once. Unix uses mio (epoll, kqueue); Windows keeps a `WSAPoll` shim until sockets
//! move to mio's own types.

use crate::fault;
#[cfg(unix)]
use crate::sys;
use crate::task::{WAIT_HUP, WAIT_READ, WAIT_WRITE};
#[cfg(unix)]
use core::sync::atomic::AtomicI32;
use core::sync::atomic::Ordering;

/// A descriptor that became ready, with the `WAIT_*` bits it reports.
#[derive(Clone, Copy)]
pub struct Ready {
    pub fd: usize,
    pub bits: u32,
}

/// What registering a descriptor came to.
pub enum Watch {
    Armed,
    /// The descriptor cannot be polled (a regular file): ready at once.
    Always,
    Failed,
}

/// Write side of the descriptor that interrupts the wait; used by signal handlers.
#[cfg(unix)]
static WAKE_FD: AtomicI32 = AtomicI32::new(-1);

#[cfg(unix)]
mod imp {
    use super::*;
    use crate::global::Global;
    use mio::event::Event;
    use mio::unix::SourceFd;
    use mio::unix::pipe;
    use mio::{Events, Interest, Poll, Token};
    use std::io::{ErrorKind, Read};
    use std::os::fd::AsRawFd;
    use std::time::Duration;

    const WAKE_TOKEN: Token = Token(usize::MAX);
    const EPERM: i32 = 1;

    struct State {
        poll: Poll,
        events: Events,
        wake_rx: pipe::Receiver,
        // Owns the write end that `WAKE_FD` points at.
        _wake_tx: pipe::Sender,
    }

    static STATE: Global<Option<State>> = Global::new(None);

    fn state() -> &'static mut State {
        // SAFETY: only the scheduler thread reaches the poller state.
        match unsafe { &mut *STATE.ptr() } {
            Some(s) => s,
            None => fault::fault(b"the I/O poller is not open"),
        }
    }

    /// Opens the poller; the returned value is only a placeholder for the old descriptor API.
    pub unsafe fn create() -> i32 {
        let open = || -> std::io::Result<State> {
            let poll = Poll::new()?;
            let (tx, mut rx) = pipe::new()?;
            poll.registry()
                .register(&mut rx, WAKE_TOKEN, Interest::READABLE)?;
            WAKE_FD.store(tx.as_raw_fd(), Ordering::Relaxed);
            Ok(State {
                poll,
                events: Events::with_capacity(64),
                wake_rx: rx,
                _wake_tx: tx,
            })
        };
        match open() {
            // SAFETY: only the scheduler thread reaches the poller state.
            Ok(s) => unsafe { *STATE.ptr() = Some(s) },
            Err(_) => fault::fault(b"cannot create the I/O poller"),
        }
        0
    }

    /// Interrupts the wait. One `write`, so signal handlers may call it.
    pub fn kick() {
        let fd = WAKE_FD.load(Ordering::Relaxed);
        if fd >= 0 {
            let one = 1u8;
            // SAFETY: writes one byte from a live local; a full pipe already holds a wake-up.
            unsafe { sys::write(fd, core::ptr::addr_of!(one).cast(), 1) };
        }
    }

    pub unsafe fn close(_: i32) {
        WAKE_FD.store(-1, Ordering::Relaxed);
        // SAFETY: only the scheduler thread reaches the poller state.
        unsafe { *STATE.ptr() = None };
    }

    pub unsafe fn watch(_: i32, fd: i32, events: u32) -> Watch {
        let mut interest = None;
        if events & WAIT_READ != 0 {
            interest = Some(Interest::READABLE);
        }
        if events & WAIT_WRITE != 0 {
            interest = Some(interest.map_or(Interest::WRITABLE, |i| i | Interest::WRITABLE));
        }
        let interest = interest.unwrap_or(Interest::READABLE);
        let registry = state().poll.registry();
        let (token, mut source) = (Token(fd as usize), SourceFd(&fd));
        // Re-registering reports a descriptor that is already ready, which is what makes a
        // wait level-like on top of mio's edge-triggered events.
        let mut r = registry.reregister(&mut source, token, interest);
        if matches!(&r, Err(e) if e.kind() == ErrorKind::NotFound) {
            r = registry.register(&mut source, token, interest);
            if matches!(&r, Err(e) if e.kind() == ErrorKind::AlreadyExists) {
                r = registry.reregister(&mut source, token, interest);
            }
        }
        match r {
            Ok(()) => Watch::Armed,
            Err(e) if e.raw_os_error() == Some(EPERM) => Watch::Always,
            Err(_) => Watch::Failed,
        }
    }

    fn bits(ev: &Event) -> u32 {
        let mut r = 0;
        if ev.is_readable() || ev.is_read_closed() {
            r |= WAIT_READ;
        }
        if ev.is_writable() || ev.is_write_closed() {
            r |= WAIT_WRITE;
        }
        if ev.is_error() || (ev.is_read_closed() && ev.is_write_closed()) {
            r |= WAIT_READ | WAIT_WRITE | WAIT_HUP;
        }
        r
    }

    pub unsafe fn wait(_: i32, timeout_ms: i32, out: &mut [Ready; 64]) -> Option<usize> {
        let s = state();
        let timeout = (timeout_ms >= 0).then(|| Duration::from_millis(timeout_ms as u64));
        match s.poll.poll(&mut s.events, timeout) {
            Ok(()) => {}
            Err(e) if e.kind() == ErrorKind::Interrupted => return None,
            Err(_) => fault::fault(b"I/O poller failed"),
        }
        let mut count = 0;
        for ev in s.events.iter() {
            if ev.token() == WAKE_TOKEN {
                let mut drain = [0u8; 64];
                while matches!(s.wake_rx.read(&mut drain), Ok(n) if n > 0) {}
                continue;
            }
            out[count] = Ready {
                fd: ev.token().0,
                bits: bits(ev),
            };
            count += 1;
        }
        Some(count)
    }
}

#[cfg(windows)]
mod imp {
    //! `WSAPoll` over the sockets tasks wait on, plus a loopback UDP socket that interrupts it.
    //! `WSAPoll` only knows sockets, so any other handle (a regular file, a pipe) is reported
    //! ready at once, as a file is on Unix.
    use super::*;
    use crate::buf::RawVec;
    use crate::global::Global;
    use core::sync::atomic::AtomicUsize;

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct PollFd {
        fd: usize,
        events: i16,
        revents: i16,
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct SockAddrIn {
        family: u16,
        /// Network byte order.
        port: u16,
        /// Network byte order.
        addr: u32,
        zero: [u8; 8],
    }

    const AF_INET: i32 = 2;
    const SOCK_DGRAM: i32 = 2;
    const IPPROTO_UDP: i32 = 17;
    const FIONBIO: i32 = 0x8004_667Eu32 as i32;
    const SOL_SOCKET: i32 = 0xFFFF;
    const SO_TYPE: i32 = 0x1008;
    const POLLRDNORM: i16 = 0x100;
    const POLLWRNORM: i16 = 0x10;
    const POLLERR: i16 = 0x1;
    const POLLHUP: i16 = 0x2;
    const POLLNVAL: i16 = 0x4;
    const INVALID_SOCKET: usize = usize::MAX;

    #[link(name = "ws2_32", kind = "raw-dylib")]
    unsafe extern "system" {
        fn WSAStartup(version: u16, data: *mut u8) -> i32;
        fn socket(af: i32, kind: i32, proto: i32) -> usize;
        fn bind(s: usize, addr: *const SockAddrIn, len: i32) -> i32;
        fn getsockname(s: usize, addr: *mut SockAddrIn, len: *mut i32) -> i32;
        fn getsockopt(s: usize, level: i32, name: i32, val: *mut u8, len: *mut i32) -> i32;
        fn ioctlsocket(s: usize, cmd: i32, arg: *mut u32) -> i32;
        fn sendto(
            s: usize,
            buf: *const u8,
            len: i32,
            flags: i32,
            to: *const SockAddrIn,
            tolen: i32,
        ) -> i32;
        fn recvfrom(
            s: usize,
            buf: *mut u8,
            len: i32,
            flags: i32,
            from: *mut SockAddrIn,
            fromlen: *mut i32,
        ) -> i32;
        fn WSAPoll(fds: *mut PollFd, n: u32, timeout: i32) -> i32;
        fn closesocket(s: usize) -> i32;
    }

    /// Entry 0 is the wake socket; the rest are one-shot registrations of waiting tasks.
    static FDS: Global<RawVec<PollFd>> = Global::new(RawVec::new());
    static WAKE_SOCKET: AtomicUsize = AtomicUsize::new(INVALID_SOCKET);
    /// Port of the wake socket on 127.0.0.1, network byte order.
    static WAKE_PORT: AtomicUsize = AtomicUsize::new(0);
    const LOOPBACK: u32 = u32::from_ne_bytes([127, 0, 0, 1]);

    pub unsafe fn create() -> i32 {
        // SAFETY: plain Winsock calls over live locals.
        unsafe {
            let mut data = [0u64; 64];
            let s = if WSAStartup(0x0202, data.as_mut_ptr().cast()) == 0 {
                socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            } else {
                INVALID_SOCKET
            };
            let mut addr = SockAddrIn {
                family: AF_INET as u16,
                port: 0,
                addr: LOOPBACK,
                zero: [0; 8],
            };
            let mut len = size_of::<SockAddrIn>() as i32;
            let mut nonblocking = 1u32;
            if s == INVALID_SOCKET
                || bind(s, &addr, len) != 0
                || getsockname(s, &mut addr, &mut len) != 0
                || ioctlsocket(s, FIONBIO, &mut nonblocking) != 0
            {
                fault::fault(b"cannot create the I/O poller");
            }
            WAKE_PORT.store(addr.port as usize, Ordering::Relaxed);
            WAKE_SOCKET.store(s, Ordering::Relaxed);
            let fds = &mut *FDS.ptr();
            fds.clear();
            fds.push(PollFd {
                fd: s,
                events: POLLRDNORM,
                revents: 0,
            });
        }
        0
    }

    pub fn kick() {
        let s = WAKE_SOCKET.load(Ordering::Relaxed);
        if s != INVALID_SOCKET {
            let to = SockAddrIn {
                family: AF_INET as u16,
                port: WAKE_PORT.load(Ordering::Relaxed) as u16,
                addr: LOOPBACK,
                zero: [0; 8],
            };
            let one = 1u8;
            // SAFETY: sends one byte from a live local; a full buffer already has a wake pending.
            unsafe { sendto(s, &one, 1, 0, &to, size_of::<SockAddrIn>() as i32) };
        }
    }

    pub unsafe fn close(_: i32) {
        let s = WAKE_SOCKET.swap(INVALID_SOCKET, Ordering::Relaxed);
        if s != INVALID_SOCKET {
            // SAFETY: the socket belongs to the poller.
            unsafe { closesocket(s) };
        }
        // SAFETY: single threaded access.
        unsafe { (*FDS.ptr()).clear() };
    }

    fn is_socket(fd: usize) -> bool {
        let (mut kind, mut len) = (0i32, 4i32);
        // SAFETY: valid out pointers; a non-socket handle just fails.
        unsafe {
            getsockopt(
                fd,
                SOL_SOCKET,
                SO_TYPE,
                core::ptr::addr_of_mut!(kind).cast(),
                &mut len,
            ) == 0
        }
    }

    pub unsafe fn watch(_: i32, fd: i32, events: u32) -> Watch {
        let fd = fd as usize;
        if !is_socket(fd) {
            return Watch::Always;
        }
        let mut mask = 0;
        if events & WAIT_READ != 0 {
            mask |= POLLRDNORM;
        }
        if events & WAIT_WRITE != 0 {
            mask |= POLLWRNORM;
        }
        // SAFETY: single threaded access.
        let fds = unsafe { &mut *FDS.ptr() };
        let entry = PollFd {
            fd,
            events: mask,
            revents: 0,
        };
        // A registration left by an earlier wait that ended another way is replaced.
        match fds.as_slice().iter().skip(1).position(|e| e.fd == fd) {
            Some(i) => fds.set(i + 1, entry),
            None => fds.push(entry),
        }
        Watch::Armed
    }

    pub unsafe fn wait(_: i32, timeout_ms: i32, out: &mut [Ready; 64]) -> Option<usize> {
        // SAFETY: single threaded access; the array holds `len` entries.
        unsafe {
            let fds = &mut *FDS.ptr();
            let n = WSAPoll(
                fds.as_mut_slice().as_mut_ptr(),
                fds.len() as u32,
                timeout_ms,
            );
            if n < 0 {
                fault::fault(b"I/O poller failed");
            }
            if fds.as_slice()[0].revents != 0 {
                let mut drain = [0u8; 64];
                let s = WAKE_SOCKET.load(Ordering::Relaxed);
                while recvfrom(
                    s,
                    drain.as_mut_ptr(),
                    64,
                    0,
                    core::ptr::null_mut(),
                    core::ptr::null_mut(),
                ) > 0
                {}
            }
            let mut count = 0;
            let mut i = 1;
            while i < fds.len() && count < out.len() {
                let e = fds.as_slice()[i];
                if e.revents == 0 {
                    i += 1;
                    continue;
                }
                let mut bits = 0;
                if e.revents & POLLRDNORM != 0 {
                    bits |= WAIT_READ;
                }
                if e.revents & POLLWRNORM != 0 {
                    bits |= WAIT_WRITE;
                }
                if e.revents & (POLLERR | POLLHUP | POLLNVAL) != 0 {
                    bits |= WAIT_READ | WAIT_WRITE | WAIT_HUP;
                }
                out[count] = Ready { fd: e.fd, bits };
                count += 1;
                // One-shot: the task re-arms when it waits again.
                fds.swap_remove(i);
            }
            Some(count)
        }
    }
}

pub use imp::{close, create, kick, wait, watch};
