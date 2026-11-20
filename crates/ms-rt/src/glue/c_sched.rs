//! The scheduler services that C natives call (`runtime/include/ms_sched.h`): cancellation, the
//! blocking pool, and on Windows the overlapped pipes and waitable objects. Thin wrappers over
//! [`super`]; the contracts are the ones documented there. They go away when the scheduler itself
//! is written in C.
// This module is the C ABI boundary of the C natives.
#![allow(unsafe_code)]

/// Whether a stop request (SIGINT or SIGTERM) is pending for the running task.
#[unsafe(no_mangle)]
pub extern "C" fn ms_sched_cancel_pending() -> bool {
    super::cancel_pending()
}

/// Delivers a pending cancel by return (see `fault::cancel_return`). The caller releases what
/// it holds first and returns a zero result at once; without cancel edges this does not return.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn ms_sched_cancel_return() {
    crate::fault::cancel_return();
}

/// The OS code of the first failed write to standard output, or 0.
#[unsafe(no_mangle)]
pub extern "C" fn ms_sched_stdout_error() -> i32 {
    crate::io::stdout_error()
}

/// Writes out the runtime's buffered standard output.
#[unsafe(no_mangle)]
pub extern "C" fn ms_sched_flush_stdout() {
    crate::io::flush_stdout();
}

/// Whether a bounded read of the running task has used its time.
#[unsafe(no_mangle)]
pub extern "C" fn ms_sched_read_limit_passed() -> bool {
    super::read_limit_passed()
}

/// Lends the running task's stack to another thread (`lend`) or takes it back: a task with its stack lent
/// keeps its pages while parked. The blocking pool (`runtime/std/pool.c`) uses it for jobs that read the caller's
/// frame.
#[unsafe(no_mangle)]
pub extern "C" fn ms_sched_task_pin(lend: bool) {
    // SAFETY: called on the runtime thread by the running task.
    unsafe { crate::task::pin_current(lend) };
}

/// What a Windows pipe call reports: `MS_SCHED_PIPE_OK`, a stop request, or an OS error.
#[cfg(windows)]
mod windows {
    use super::super::pipe::{self, Stop};

    const PIPE_OK: i32 = 0;
    const PIPE_CANCELLED: i32 = 1;
    const PIPE_ERROR: i32 = 2;
    /// `ERROR_IO_DEVICE`, for a failure without an OS code.
    const ERROR_IO_DEVICE: i32 = 1117;

    fn os_error(e: &std::io::Error) -> i32 {
        e.raw_os_error().unwrap_or(ERROR_IO_DEVICE)
    }

    /// Takes over an overlapped named pipe; false when it was not opened for overlapped I/O.
    ///
    /// # Safety
    /// `handle` is an open named-pipe handle opened with `FILE_FLAG_OVERLAPPED`.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn ms_sched_pipe_adopt(handle: isize) -> bool {
        // SAFETY: forwarded from the caller.
        unsafe { pipe::adopt(handle) }
    }

    /// Whether `handle` is a pipe adopted here.
    #[unsafe(no_mangle)]
    pub extern "C" fn ms_sched_pipe_is_adopted(handle: isize) -> bool {
        pipe::is_adopted(handle)
    }

    /// Reads up to `capacity` bytes, parking until some arrive; `*count` is 0 at end of stream.
    ///
    /// # Safety
    /// `buffer` holds `capacity` writable bytes; `count` and `os_error` are writable.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn ms_sched_pipe_read(
        handle: isize,
        buffer: *mut u8,
        capacity: usize,
        count: *mut usize,
        os_code: *mut i32,
    ) -> i32 {
        // SAFETY: per the contract.
        let buf = unsafe { core::slice::from_raw_parts_mut(buffer, capacity) };
        match pipe::read(handle, buf) {
            Ok(n) => {
                // SAFETY: writable per the contract.
                unsafe { *count = n };
                PIPE_OK
            }
            Err(Stop::Cancelled) => PIPE_CANCELLED,
            Err(Stop::Io(e)) => {
                // SAFETY: writable per the contract.
                unsafe { *os_code = os_error(&e) };
                PIPE_ERROR
            }
        }
    }

    /// Writes all of `data`, parking while the pipe is busy.
    ///
    /// # Safety
    /// `data` holds `length` readable bytes; `os_code` is writable.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn ms_sched_pipe_write(
        handle: isize,
        data: *const u8,
        length: usize,
        os_code: *mut i32,
    ) -> i32 {
        // SAFETY: per the contract.
        let bytes = unsafe { core::slice::from_raw_parts(data, length) };
        match pipe::write(handle, bytes) {
            Ok(()) => PIPE_OK,
            Err(Stop::Cancelled) => PIPE_CANCELLED,
            Err(Stop::Io(e)) => {
                // SAFETY: writable per the contract.
                unsafe { *os_code = os_error(&e) };
                PIPE_ERROR
            }
        }
    }

    /// Closes an adopted pipe.
    #[unsafe(no_mangle)]
    pub extern "C" fn ms_sched_pipe_close(handle: isize) {
        pipe::close(handle);
    }

    /// Parks until the waitable `handle` is signalled or the timeout passes: `0` signalled, `1`
    /// timed out, `2` stop request, `3` the object cannot be watched.
    ///
    /// # Safety
    /// `handle` is an open waitable handle that stays open until `ms_sched_object_forget`.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn ms_sched_object_wait(handle: isize, timeout_ns: i64) -> i32 {
        use super::super::{WAIT_TIMEOUT, object};
        // SAFETY: forwarded from the caller.
        match unsafe { object::try_wait(handle, timeout_ns) } {
            Ok(Some(bits)) if bits & WAIT_TIMEOUT != 0 => 1,
            Ok(Some(_)) => 0,
            Ok(None) => 3,
            Err(_) => 2,
        }
    }

    /// Ends the watch of `ms_sched_object_wait`; call before closing the handle.
    #[unsafe(no_mangle)]
    pub extern "C" fn ms_sched_object_forget(handle: isize) {
        super::super::object::forget(handle);
    }
}
