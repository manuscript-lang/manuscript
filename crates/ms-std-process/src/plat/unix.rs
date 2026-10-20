//! Unix pipes, clock and readiness polling for child processes.
use super::Fd;
use ms_std_fs::sys;

pub fn now_ns() -> i64 {
    // SAFETY: zeroed `timespec` is a valid out buffer.
    let mut t: libc::timespec = unsafe { core::mem::zeroed() };
    // SAFETY: `t` is writable.
    unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut t) };
    t.tv_sec as i64 * 1_000_000_000 + t.tv_nsec as i64
}

pub fn pipe() -> Result<(Fd, Fd), i32> {
    let mut fds = [0i32; 2];
    // SAFETY: `fds` has room for two descriptors.
    if unsafe { sys::pipe_cloexec(&mut fds, false) } != 0 {
        return Err(sys::errno());
    }
    Ok((Fd(fds[0]), Fd(fds[1])))
}

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

/// Sleeps `ms` milliseconds.
pub fn sleep_ms(ms: i64) {
    sys::sleep_ms(ms as i32);
}

/// Whether a read or write would only have blocked (`EAGAIN`).
pub fn would_block(e: i32) -> bool {
    e == libc::EAGAIN
}
