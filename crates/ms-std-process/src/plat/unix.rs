//! Unix pipes, clock and readiness polling for child processes.
use super::Fd;
use ms_std_fs::sys;

/// A pipe `(parent, child)` for one standard stream: the parent reads it when `parent_reads`,
/// else writes it.
pub fn pipe(parent_reads: bool) -> Result<(Fd, Fd), i32> {
    let mut fds = [0i32; 2];
    // SAFETY: `fds` has room for two descriptors.
    if unsafe { sys::pipe_cloexec(&mut fds, false) } != 0 {
        return Err(sys::errno());
    }
    let (r, w) = (Fd(fds[0]), Fd(fds[1]));
    Ok(if parent_reads { (r, w) } else { (w, r) })
}

pub use sys::{close, read, write};

pub fn set_nonblocking(fd: sys::Fd, _write_end: bool) {
    // SAFETY: plain fcntl calls.
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFL);
        libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK);
    }
}

/// Waits up to `slice_ms` for the parent ends of the pipes: which of `[stdin writable, stdout
/// readable, stderr readable]` are ready. A negative descriptor is skipped.
pub fn wait_io(fds: [sys::Fd; 3], slice_ms: i64) -> [bool; 3] {
    let mut polls = [libc::pollfd {
        fd: -1,
        events: 0,
        revents: 0,
    }; 3];
    for (i, events) in [libc::POLLOUT, libc::POLLIN, libc::POLLIN]
        .into_iter()
        .enumerate()
    {
        if fds[i] >= 0 {
            polls[i] = libc::pollfd {
                fd: fds[i],
                events,
                revents: 0,
            };
        }
    }
    // Pipes closed and the child still running: sleep a short slice instead of polling nothing.
    let slice = if fds.iter().all(|&p| p < 0) {
        slice_ms.min(2)
    } else {
        slice_ms
    };
    // SAFETY: `polls` is valid for three entries.
    unsafe { libc::poll(polls.as_mut_ptr(), 3, slice as i32) };
    [
        polls[0].revents != 0,
        polls[1].revents != 0,
        polls[2].revents != 0,
    ]
}

/// Whether a read or write would only have blocked (`EAGAIN`).
pub fn would_block(e: i32) -> bool {
    e == libc::EAGAIN
}

/// One descriptor that becomes readable when the child exits or one of `run`'s pipes is ready:
/// an epoll set over the child's pidfd and the parent's pipe ends, so the task parks on all of
/// them at once.
#[cfg(target_os = "linux")]
pub struct Waiter {
    set: Fd,
    exit: sys::Fd,
}

#[cfg(target_os = "linux")]
impl Waiter {
    /// `None` without an exit descriptor (Linux before 5.3); the caller checks in slices.
    /// Closing a pipe end removes it from the set.
    pub fn new(exit: Option<sys::Fd>, pipes: [sys::Fd; 3]) -> Option<Waiter> {
        let exit = exit?;
        // SAFETY: plain system call.
        let set = unsafe { libc::epoll_create1(libc::EPOLL_CLOEXEC) };
        if set < 0 {
            return None;
        }
        let waiter = Waiter { set: Fd(set), exit };
        let interests = [libc::EPOLLOUT, libc::EPOLLIN, libc::EPOLLIN];
        for (fd, events) in [(exit, libc::EPOLLIN)]
            .into_iter()
            .chain(pipes.into_iter().zip(interests))
        {
            if fd >= 0 && waiter.ctl(libc::EPOLL_CTL_ADD, fd, events) != 0 {
                return None;
            }
        }
        Some(waiter)
    }

    fn ctl(&self, op: i32, fd: sys::Fd, events: i32) -> i32 {
        let mut event = libc::epoll_event {
            events: events as u32,
            u64: fd as u64,
        };
        // SAFETY: `event` outlives the call.
        unsafe { libc::epoll_ctl(self.set.0, op, fd, &mut event) }
    }

    /// Stops watching the child once it is reaped; its descriptor stays readable.
    pub fn exited(&mut self) {
        if self.exit >= 0 {
            self.ctl(libc::EPOLL_CTL_DEL, self.exit, 0);
            self.exit = -1;
        }
    }

    /// Parks the task until something in the set is ready or `timeout_ns` passes (negative: no
    /// limit).
    pub fn park(&self, timeout_ns: i64) {
        ms_rt::glue::task_wait_fd(self.set.0, ms_rt::glue::WAIT_READ, timeout_ns);
    }
}

/// One descriptor that becomes readable when the child exits or one of `run`'s pipes is ready:
/// a kqueue over the child's exit kqueue and the parent's pipe ends, so the task parks on all of
/// them at once.
#[cfg(not(target_os = "linux"))]
pub struct Waiter {
    set: Fd,
    exit: sys::Fd,
}

#[cfg(not(target_os = "linux"))]
impl Waiter {
    /// `None` without an exit descriptor (the child had exited before it could be watched);
    /// the caller checks in slices. Closing a pipe end removes it from the set.
    pub fn new(exit: Option<sys::Fd>, pipes: [sys::Fd; 3]) -> Option<Waiter> {
        let exit = exit?;
        // SAFETY: plain system call.
        let set = unsafe { libc::kqueue() };
        if set < 0 {
            return None;
        }
        // SAFETY: plain fcntl call on the new descriptor.
        unsafe { libc::fcntl(set, libc::F_SETFD, libc::FD_CLOEXEC) };
        let waiter = Waiter { set: Fd(set), exit };
        let filters = [libc::EVFILT_WRITE, libc::EVFILT_READ, libc::EVFILT_READ];
        for (fd, filter) in [(exit, libc::EVFILT_READ)]
            .into_iter()
            .chain(pipes.into_iter().zip(filters))
        {
            if fd >= 0 && waiter.change(fd, filter, libc::EV_ADD) != 0 {
                return None;
            }
        }
        Some(waiter)
    }

    fn change(&self, fd: sys::Fd, filter: i16, flags: u16) -> i32 {
        // SAFETY: a zeroed `kevent` is valid; `change` outlives the call.
        unsafe {
            let mut change: libc::kevent = core::mem::zeroed();
            change.ident = fd as libc::uintptr_t;
            change.filter = filter;
            change.flags = flags;
            libc::kevent(
                self.set.0,
                &change,
                1,
                core::ptr::null_mut(),
                0,
                core::ptr::null(),
            )
        }
    }

    /// Stops watching the child once it is reaped; its descriptor stays readable.
    pub fn exited(&mut self) {
        if self.exit >= 0 {
            self.change(self.exit, libc::EVFILT_READ, libc::EV_DELETE);
            self.exit = -1;
        }
    }

    /// Parks the task until something in the set is ready or `timeout_ns` passes (negative: no
    /// limit).
    pub fn park(&self, timeout_ns: i64) {
        ms_rt::glue::task_wait_fd(self.set.0, ms_rt::glue::WAIT_READ, timeout_ns);
    }
}
