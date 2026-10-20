//! The scheduler's descriptor poller: epoll on Linux, kqueue on macOS. A task parks on one
//! descriptor at a time; each registration is one-shot.

use crate::fault;
#[cfg(unix)]
use crate::sys;
use crate::task::{WAIT_HUP, WAIT_READ, WAIT_WRITE};
#[cfg(unix)]
use core::sync::atomic::AtomicI32;
use core::sync::atomic::Ordering;

#[cfg(unix)]
const EINTR: i32 = 4;

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
const WAKE_TAG: u64 = u64::MAX;

#[cfg(target_os = "linux")]
mod imp {
    use super::*;

    const EPOLL_CTL_ADD: i32 = 1;
    const EPOLL_CTL_MOD: i32 = 3;
    const EPOLLIN: u32 = 1;
    const EPOLLOUT: u32 = 4;
    const EPOLLERR: u32 = 8;
    const EPOLLHUP: u32 = 0x10;
    const EPOLLONESHOT: u32 = 1 << 30;
    const EPOLL_CLOEXEC: i32 = 0x80000;
    const EPERM: i32 = 1;
    const ENOENT: i32 = 2;
    const EEXIST: i32 = 17;

    #[repr(C)]
    #[cfg_attr(target_arch = "x86_64", repr(packed))]
    #[derive(Clone, Copy)]
    struct EpollEvent {
        events: u32,
        data: u64,
    }

    unsafe extern "C" {
        fn eventfd(init: u32, flags: i32) -> i32;
        fn epoll_create1(flags: i32) -> i32;
        fn epoll_ctl(epfd: i32, op: i32, fd: i32, ev: *mut EpollEvent) -> i32;
        fn epoll_wait(epfd: i32, events: *mut EpollEvent, max: i32, timeout_ms: i32) -> i32;
    }

    pub unsafe fn create() -> i32 {
        // SAFETY: plain syscall wrappers.
        unsafe {
            let ep = epoll_create1(EPOLL_CLOEXEC);
            let wake = eventfd(0, 0o4000 | 0o2000000);
            if ep < 0 || wake < 0 {
                fault::fault(b"cannot create the I/O poller");
            }
            let mut ev = EpollEvent {
                events: EPOLLIN,
                data: WAKE_TAG,
            };
            epoll_ctl(ep, EPOLL_CTL_ADD, wake, &mut ev);
            WAKE_FD.store(wake, Ordering::Relaxed);
            ep
        }
    }

    pub fn kick() {
        let fd = WAKE_FD.load(Ordering::Relaxed);
        if fd >= 0 {
            let one: u64 = 1;
            // SAFETY: writes eight bytes from a live local.
            unsafe { sys::write(fd, core::ptr::addr_of!(one).cast(), 8) };
        }
    }

    pub unsafe fn close(ep: i32) {
        // SAFETY: both descriptors belong to the poller.
        unsafe {
            sys::close(ep);
            sys::close(WAKE_FD.swap(-1, Ordering::Relaxed));
        }
    }

    pub unsafe fn watch(ep: i32, fd: i32, events: u32) -> Watch {
        let mut mask = EPOLLONESHOT;
        if events & WAIT_READ != 0 {
            mask |= EPOLLIN;
        }
        if events & WAIT_WRITE != 0 {
            mask |= EPOLLOUT;
        }
        let mut ev = EpollEvent {
            events: mask,
            data: fd as u64,
        };
        // SAFETY: `ev` is live for the calls.
        unsafe {
            let mut r = epoll_ctl(ep, EPOLL_CTL_MOD, fd, &mut ev);
            if r < 0 && sys::last_errno() == ENOENT {
                r = epoll_ctl(ep, EPOLL_CTL_ADD, fd, &mut ev);
                if r < 0 && sys::last_errno() == EEXIST {
                    r = epoll_ctl(ep, EPOLL_CTL_MOD, fd, &mut ev);
                }
            }
            if r >= 0 {
                Watch::Armed
            } else if sys::last_errno() == EPERM {
                Watch::Always
            } else {
                Watch::Failed
            }
        }
    }

    pub unsafe fn wait(ep: i32, timeout_ms: i32, out: &mut [Ready; 64]) -> Option<usize> {
        let mut events = [EpollEvent { events: 0, data: 0 }; 64];
        // SAFETY: `events` holds 64 slots.
        unsafe {
            let n = epoll_wait(ep, events.as_mut_ptr(), 64, timeout_ms);
            if n < 0 {
                if sys::last_errno() == EINTR {
                    return None;
                }
                fault::fault(b"I/O poller failed");
            }
            let mut count = 0;
            for ev in events.iter().take(n as usize) {
                let (bits, tag) = (ev.events, ev.data);
                if tag == WAKE_TAG {
                    let mut drain = 0u64;
                    sys::read(
                        WAKE_FD.load(Ordering::Relaxed),
                        core::ptr::addr_of_mut!(drain).cast(),
                        8,
                    );
                    continue;
                }
                let mut r = 0;
                if bits & (EPOLLIN | EPOLLERR | EPOLLHUP) != 0 {
                    r |= WAIT_READ;
                }
                if bits & (EPOLLOUT | EPOLLERR | EPOLLHUP) != 0 {
                    r |= WAIT_WRITE;
                }
                if bits & (EPOLLERR | EPOLLHUP) != 0 {
                    r |= WAIT_HUP;
                }
                out[count] = Ready {
                    fd: tag as usize,
                    bits: r,
                };
                count += 1;
            }
            Some(count)
        }
    }
}

#[cfg(target_os = "macos")]
mod imp {
    use super::*;
    use core::ffi::c_void;

    const EVFILT_READ: i16 = -1;
    const EVFILT_WRITE: i16 = -2;
    const EV_ADD: u16 = 0x1;
    const EV_DISABLE: u16 = 0x8;
    const EV_ONESHOT: u16 = 0x10;
    const EV_ERROR: u16 = 0x4000;
    const EV_EOF: u16 = 0x8000;
    const F_SETFD: i32 = 2;
    const F_SETFL: i32 = 4;
    const FD_CLOEXEC: i32 = 1;
    const O_NONBLOCK: i32 = 4;

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct Kevent {
        ident: usize,
        filter: i16,
        flags: u16,
        fflags: u32,
        data: isize,
        udata: *mut c_void,
    }

    const EMPTY: Kevent = Kevent {
        ident: 0,
        filter: 0,
        flags: 0,
        fflags: 0,
        data: 0,
        udata: core::ptr::null_mut(),
    };

    #[repr(C)]
    struct Timespec {
        sec: i64,
        nsec: i64,
    }

    unsafe extern "C" {
        fn kqueue() -> i32;
        fn kevent(
            kq: i32,
            changes: *const Kevent,
            nchanges: i32,
            events: *mut Kevent,
            nevents: i32,
            timeout: *const Timespec,
        ) -> i32;
        fn fcntl(fd: i32, cmd: i32, ...) -> i32;
    }

    /// Read side of the wake pipe, registered under `WAKE_TAG`.
    static WAKE_READ: AtomicI32 = AtomicI32::new(-1);

    fn change(fd: i32, filter: i16, flags: u16, tag: u64) -> Kevent {
        Kevent {
            ident: fd as usize,
            filter,
            flags,
            fflags: 0,
            data: 0,
            udata: tag as usize as *mut c_void,
        }
    }

    pub unsafe fn create() -> i32 {
        // SAFETY: plain syscall wrappers over live locals.
        unsafe {
            let kq = kqueue();
            let mut fds = [-1i32; 2];
            if kq < 0 || sys::pipe(fds.as_mut_ptr()) < 0 {
                fault::fault(b"cannot create the I/O poller");
            }
            for fd in [kq, fds[0], fds[1]] {
                fcntl(fd, F_SETFD, FD_CLOEXEC);
            }
            for fd in [fds[0], fds[1]] {
                fcntl(fd, F_SETFL, O_NONBLOCK);
            }
            let add = change(fds[0], EVFILT_READ, EV_ADD, WAKE_TAG);
            kevent(kq, &add, 1, core::ptr::null_mut(), 0, core::ptr::null());
            WAKE_READ.store(fds[0], Ordering::Relaxed);
            WAKE_FD.store(fds[1], Ordering::Relaxed);
            kq
        }
    }

    pub fn kick() {
        let fd = WAKE_FD.load(Ordering::Relaxed);
        if fd >= 0 {
            let one = 1u8;
            // SAFETY: writes one byte from a live local; a full pipe already has a wake pending.
            unsafe { sys::write(fd, core::ptr::addr_of!(one).cast(), 1) };
        }
    }

    pub unsafe fn close(kq: i32) {
        // SAFETY: all three descriptors belong to the poller.
        unsafe {
            sys::close(kq);
            sys::close(WAKE_READ.swap(-1, Ordering::Relaxed));
            sys::close(WAKE_FD.swap(-1, Ordering::Relaxed));
        }
    }

    pub unsafe fn watch(kq: i32, fd: i32, events: u32) -> Watch {
        // The direction not waited for is added disabled, which also clears a stale
        // registration left by an earlier wait.
        let state = |wanted: bool| {
            if wanted {
                EV_ADD | EV_ONESHOT
            } else {
                EV_ADD | EV_DISABLE
            }
        };
        let changes = [
            change(fd, EVFILT_READ, state(events & WAIT_READ != 0), fd as u64),
            change(fd, EVFILT_WRITE, state(events & WAIT_WRITE != 0), fd as u64),
        ];
        // SAFETY: `changes` holds two entries; no events are collected.
        let r = unsafe {
            kevent(
                kq,
                changes.as_ptr(),
                2,
                core::ptr::null_mut(),
                0,
                core::ptr::null(),
            )
        };
        if r >= 0 { Watch::Armed } else { Watch::Failed }
    }

    pub unsafe fn wait(kq: i32, timeout_ms: i32, out: &mut [Ready; 64]) -> Option<usize> {
        let mut events = [EMPTY; 64];
        let limit = Timespec {
            sec: i64::from(timeout_ms / 1000),
            nsec: i64::from(timeout_ms % 1000) * 1_000_000,
        };
        let wait = if timeout_ms < 0 {
            core::ptr::null()
        } else {
            &limit as *const Timespec
        };
        // SAFETY: `events` holds 64 slots; `limit` outlives the call.
        unsafe {
            let n = kevent(kq, core::ptr::null(), 0, events.as_mut_ptr(), 64, wait);
            if n < 0 {
                if sys::last_errno() == EINTR {
                    return None;
                }
                fault::fault(b"I/O poller failed");
            }
            let mut count = 0;
            for ev in events.iter().take(n as usize) {
                let tag = ev.udata as usize as u64;
                if tag == WAKE_TAG {
                    let mut drain = [0u8; 64];
                    let fd = WAKE_READ.load(Ordering::Relaxed);
                    while sys::read(fd, drain.as_mut_ptr().cast(), 64) > 0 {}
                    continue;
                }
                let mut r = if ev.filter == EVFILT_READ {
                    WAIT_READ
                } else {
                    WAIT_WRITE
                };
                if ev.flags & (EV_EOF | EV_ERROR) != 0 {
                    r |= WAIT_READ | WAIT_WRITE | WAIT_HUP;
                }
                out[count] = Ready {
                    fd: tag as usize,
                    bits: r,
                };
                count += 1;
            }
            Some(count)
        }
    }
}

#[cfg(windows)]
mod imp {
    //! `WSAPoll` over the sockets tasks wait on, plus a loopback UDP socket that interrupts it.
    //! `WSAPoll` only knows sockets, so any other handle (a regular file, a pipe) is reported
    //! ready at once, as a file is on Unix.
    use super::*;
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
    static FDS: Global<Vec<PollFd>> = Global::new(Vec::new());
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
            Some(i) => fds[i + 1] = entry,
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
