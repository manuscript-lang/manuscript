//! The I/O poller behind the task reactor: epoll on Linux, kqueue on macOS.
//!
//! One-shot readiness: [`arm`] registers interest in a descriptor and the next [`wait`] reports
//! it once. A wake descriptor lets a signal handler interrupt a wait ([`kick`]).
use crate::fault;
use crate::sys;
use core::sync::atomic::{AtomicI32, Ordering};

/// Readable (or at end of file).
pub const EV_READ: u8 = 1;
/// Writable.
pub const EV_WRITE: u8 = 2;
/// Error or hang-up.
pub const EV_HUP: u8 = 4;

/// Event tag reported for the wake descriptor.
pub const WAKE_TAG: u64 = u64::MAX;

/// One readiness report: the descriptor (or [`WAKE_TAG`]) and `EV_*` bits.
#[derive(Clone, Copy)]
pub struct Ready {
    pub tag: u64,
    pub bits: u8,
}

pub const EMPTY: Ready = Ready { tag: 0, bits: 0 };

/// Result of [`arm`].
pub enum Arm {
    Armed,
    /// The descriptor cannot be polled (a regular file): treat it as always ready.
    AlwaysReady,
    Failed,
}

/// Descriptor written by [`kick`]; -1 before the poller exists.
static WAKE_FD: AtomicI32 = AtomicI32::new(-1);

pub const EINTR: i32 = 4;

#[cfg(not(target_vendor = "apple"))]
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

    pub fn kick() {
        let fd = WAKE_FD.load(Ordering::Relaxed);
        if fd >= 0 {
            let one: u64 = 1;
            // SAFETY: writes eight bytes from a live local.
            unsafe { sys::write(fd, core::ptr::addr_of!(one).cast(), 8) };
        }
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

    pub unsafe fn arm(ep: i32, fd: i32, read: bool, write: bool) -> Arm {
        let mut mask = EPOLLONESHOT;
        if read {
            mask |= EPOLLIN;
        }
        if write {
            mask |= EPOLLOUT;
        }
        let mut ev = EpollEvent {
            events: mask,
            data: fd as u64,
        };
        // SAFETY: valid event record; descriptor errors are reported through errno.
        unsafe {
            let mut r = epoll_ctl(ep, EPOLL_CTL_MOD, fd, &mut ev);
            if r < 0 && sys::last_errno() == ENOENT {
                r = epoll_ctl(ep, EPOLL_CTL_ADD, fd, &mut ev);
                if r < 0 && sys::last_errno() == EEXIST {
                    r = epoll_ctl(ep, EPOLL_CTL_MOD, fd, &mut ev);
                }
            }
            if r >= 0 {
                Arm::Armed
            } else if sys::last_errno() == EPERM {
                Arm::AlwaysReady
            } else {
                Arm::Failed
            }
        }
    }

    pub unsafe fn wait(ep: i32, out: &mut [Ready], timeout_ms: i32) -> i32 {
        let mut events = [EpollEvent { events: 0, data: 0 }; 64];
        let max = out.len().min(events.len());
        // SAFETY: `events` holds `max` slots.
        let n = unsafe { epoll_wait(ep, events.as_mut_ptr(), max as i32, timeout_ms) };
        for (slot, ev) in out.iter_mut().zip(events.iter()).take(n.max(0) as usize) {
            let (e, tag) = (ev.events, ev.data);
            let mut bits = 0;
            if e & EPOLLIN != 0 {
                bits |= EV_READ;
            }
            if e & EPOLLOUT != 0 {
                bits |= EV_WRITE;
            }
            if e & (EPOLLERR | EPOLLHUP) != 0 {
                bits |= EV_HUP;
            }
            *slot = Ready { tag, bits };
        }
        n
    }

    pub unsafe fn drain_wake() {
        let mut drain = 0u64;
        // SAFETY: reads eight bytes into a live local.
        unsafe {
            sys::read(
                WAKE_FD.load(Ordering::Relaxed),
                core::ptr::addr_of_mut!(drain).cast(),
                8,
            );
        }
    }

    pub unsafe fn close(ep: i32) {
        // SAFETY: closes descriptors this module opened.
        unsafe {
            sys::close(ep);
            sys::close(WAKE_FD.swap(-1, Ordering::Relaxed));
        }
    }
}

#[cfg(target_vendor = "apple")]
mod imp {
    use super::*;

    const EVFILT_READ: i16 = -1;
    const EVFILT_WRITE: i16 = -2;
    const EV_ADD: u16 = 0x1;
    const EV_DELETE: u16 = 0x2;
    const EV_ONESHOT: u16 = 0x10;
    const EV_CLEAR: u16 = 0x20;
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
        udata: *mut core::ffi::c_void,
    }

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

    const ZERO: Kevent = Kevent {
        ident: 0,
        filter: 0,
        flags: 0,
        fflags: 0,
        data: 0,
        udata: core::ptr::null_mut(),
    };

    fn change(fd: i32, filter: i16, flags: u16, tag: u64) -> Kevent {
        Kevent {
            ident: fd as usize,
            filter,
            flags,
            udata: tag as usize as *mut core::ffi::c_void,
            ..ZERO
        }
    }

    pub fn kick() {
        let fd = WAKE_FD.load(Ordering::Relaxed);
        if fd >= 0 {
            let one = 1u8;
            // SAFETY: writes one byte from a live local (async-signal-safe).
            unsafe { sys::write(fd, core::ptr::addr_of!(one).cast(), 1) };
        }
    }

    pub unsafe fn create() -> i32 {
        // SAFETY: plain syscall wrappers.
        unsafe {
            let kq = kqueue();
            let mut fds = [-1i32; 2];
            if kq < 0 || sys::pipe(fds.as_mut_ptr()) < 0 {
                fault::fault(b"cannot create the I/O poller");
            }
            fcntl(kq, F_SETFD, FD_CLOEXEC);
            for fd in fds {
                fcntl(fd, F_SETFD, FD_CLOEXEC);
                fcntl(fd, F_SETFL, O_NONBLOCK);
            }
            let ev = change(fds[0], EVFILT_READ, EV_ADD | EV_CLEAR, WAKE_TAG);
            kevent(kq, &ev, 1, core::ptr::null_mut(), 0, core::ptr::null());
            WAKE_FD.store(fds[1], Ordering::Relaxed);
            READ_END.store(fds[0], Ordering::Relaxed);
            kq
        }
    }

    static READ_END: AtomicI32 = AtomicI32::new(-1);

    pub unsafe fn arm(kq: i32, fd: i32, read: bool, write: bool) -> Arm {
        let tag = fd as u64;
        // SAFETY: valid change records; deleting a filter that is not registered fails harmlessly.
        unsafe {
            // A one-shot filter that did not fire is still registered; clear both first so a
            // stale event cannot wake a later waiter.
            for filter in [EVFILT_READ, EVFILT_WRITE] {
                let del = change(fd, filter, EV_DELETE, tag);
                kevent(kq, &del, 1, core::ptr::null_mut(), 0, core::ptr::null());
            }
            for (wanted, filter) in [(read, EVFILT_READ), (write, EVFILT_WRITE)] {
                if !wanted {
                    continue;
                }
                let add = change(fd, filter, EV_ADD | EV_ONESHOT, tag);
                if kevent(kq, &add, 1, core::ptr::null_mut(), 0, core::ptr::null()) < 0 {
                    return Arm::Failed;
                }
            }
        }
        Arm::Armed
    }

    pub unsafe fn wait(kq: i32, out: &mut [Ready], timeout_ms: i32) -> i32 {
        let mut events = [ZERO; 64];
        let max = out.len().min(events.len());
        let ts = Timespec {
            sec: (timeout_ms.max(0) / 1000) as i64,
            nsec: (timeout_ms.max(0) % 1000) as i64 * 1_000_000,
        };
        let timeout = if timeout_ms < 0 {
            core::ptr::null()
        } else {
            &ts as *const Timespec
        };
        // SAFETY: `events` holds `max` slots.
        let n = unsafe {
            kevent(
                kq,
                core::ptr::null(),
                0,
                events.as_mut_ptr(),
                max as i32,
                timeout,
            )
        };
        for (slot, ev) in out.iter_mut().zip(events.iter()).take(n.max(0) as usize) {
            let tag = if ev.udata as usize as u64 == WAKE_TAG {
                WAKE_TAG
            } else {
                ev.ident as u64
            };
            let mut bits = 0;
            if ev.filter == EVFILT_READ {
                bits |= EV_READ;
            }
            if ev.filter == EVFILT_WRITE {
                bits |= EV_WRITE;
            }
            if ev.flags & (EV_EOF | EV_ERROR) != 0 {
                bits |= EV_HUP;
            }
            *slot = Ready { tag, bits };
        }
        n
    }

    pub unsafe fn drain_wake() {
        let mut buf = [0u8; 64];
        // SAFETY: reads into a live buffer; the descriptor is non-blocking.
        unsafe {
            sys::read(
                READ_END.load(Ordering::Relaxed),
                buf.as_mut_ptr().cast(),
                buf.len(),
            );
        }
    }

    pub unsafe fn close(kq: i32) {
        // SAFETY: closes descriptors this module opened.
        unsafe {
            sys::close(kq);
            sys::close(WAKE_FD.swap(-1, Ordering::Relaxed));
            sys::close(READ_END.swap(-1, Ordering::Relaxed));
        }
    }
}

pub use imp::{arm, close, create, drain_wake, kick, wait};
