//! Windows pipes, clock and readiness polling for child processes.
use super::Fd;
use core::ptr::{null, null_mut};
use ms_std_fs::sys;
use windows_sys::Win32::Foundation::HANDLE;
use windows_sys::Win32::System::Pipes::{CreatePipe, PIPE_NOWAIT, SetNamedPipeHandleState};

/// An anonymous pipe `(read, write)`. Neither end is inheritable; `start` makes the ends the child
/// uses inheritable only for the duration of the spawn.
pub fn pipe() -> Result<(Fd, Fd), i32> {
    let (mut r, mut w): (HANDLE, HANDLE) = (null_mut(), null_mut());
    // SAFETY: both outputs are writable.
    if unsafe { CreatePipe(&mut r, &mut w, null(), 0) } == 0 {
        return Err(sys::errno());
    }
    Ok((Fd(r as isize), Fd(w as isize)))
}

/// Puts the parent's write end into non-blocking mode so a full pipe does not stall the loop.
/// Read ends are polled with `PeekNamedPipe` instead.
pub fn set_nonblocking(fd: sys::Fd, write_end: bool) {
    if write_end {
        let mode = PIPE_NOWAIT;
        // SAFETY: `fd` is an open pipe handle and `mode` is readable.
        unsafe { SetNamedPipeHandleState(fd as HANDLE, &mode, null(), null()) };
    }
}

/// Waits up to `slice_ms` for the parent ends of the pipes: which of `[stdin writable, stdout
/// readable, stderr readable]` are ready. An invalid handle is skipped. A Windows pipe cannot be
/// waited on for writability, so an open stdin always counts as ready and the
/// non-blocking write reports how much fit.
pub fn wait_io(fds: [sys::Fd; 3], slice_ms: i64) -> [bool; 3] {
    let open = |fd: sys::Fd| fd != sys::INVALID_FD;
    // Pipes closed and the child still running: pause briefly instead of polling nothing.
    let slice_ms = if fds.iter().any(|&fd| open(fd)) {
        slice_ms
    } else {
        slice_ms.min(2)
    };
    let mut waited = 0;
    loop {
        let ready = [
            open(fds[0]),
            open(fds[1]) && sys::wait_ready(fds[1], sys::Interest::Read, 0),
            open(fds[2]) && sys::wait_ready(fds[2], sys::Interest::Read, 0),
        ];
        if ready.iter().any(|&r| r) || waited >= slice_ms {
            return ready;
        }
        sys::sleep_ms(1);
        waited += 1;
    }
}

/// Whether a failed read or write only means "try later". A full non-blocking pipe reports
/// success with zero bytes instead, so no error qualifies.
pub fn would_block(_: i32) -> bool {
    false
}

/// Windows pipes cannot be waited on with the process handle; the caller checks in slices.
pub enum Waiter {}

impl Waiter {
    pub fn new(_exit: Option<sys::Fd>, _pipes: [sys::Fd; 3]) -> Option<Waiter> {
        None
    }

    pub fn exited(&mut self) {
        match *self {}
    }

    pub fn park(&self, _timeout_ns: i64) {
        match *self {}
    }
}
