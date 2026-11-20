//! The poller on the C reactor (`runtime/io/reactor.c`, libuv). On Windows the reactor also owns the overlapped
//! named pipes and the waited-on kernel objects (`runtime/io/windows/platform.c`).
//! Same contract as the mio poller in `poller.rs`; the scheduler does not know the difference.

use super::*;

unsafe extern "C" {
    fn ms_io_open(is_main: bool, reactor: *mut *mut core::ffi::c_void) -> bool;
    fn ms_io_close(is_main: bool);
    fn ms_io_wake(reactor: *mut core::ffi::c_void);
    fn ms_io_kick();
    fn ms_io_watch(fd: i32, events: u32) -> i32;
    fn ms_io_unwatch(fd: i32);
    fn ms_io_forget(fd: i32);
    fn ms_io_wait(timeout_ns: i64, out: *mut Ready, capacity: usize, count: *mut usize) -> bool;
    fn ms_io_set_completion_sink(sink: Option<unsafe extern "C" fn(u64, i32, u32)>);
    fn ms_sched_post_completion(id: u64, result: i32, kind: u32);
}

/// The reactor `ms_io_wake` takes, movable into the isolate's wake closure.
struct WakeHandle(*mut core::ffi::c_void);
// SAFETY: `uv_async_send` is the one libuv call that is safe from any thread; the reactor lives
// until `close` clears the isolate's wake closure.
unsafe impl Send for WakeHandle {}
unsafe impl Sync for WakeHandle {}

pub unsafe fn create() -> i32 {
    let main = crate::isolate::is_main();
    let mut reactor = core::ptr::null_mut();
    // SAFETY: opens this thread's reactor and stores it in `reactor`.
    if !unsafe { ms_io_open(main, &mut reactor) } {
        fault::fault(b"cannot create the I/O poller");
    }
    // SAFETY: the sink posts to this thread's scheduler, which is the thread that runs the reactor's wait.
    unsafe { ms_io_set_completion_sink(Some(ms_sched_post_completion)) };
    let wake = WakeHandle(reactor);
    crate::isolate::set_wake(Some(Box::new(move || {
        let w = &wake;
        // SAFETY: the reactor outlives the closure (`close` unsets it first).
        unsafe { ms_io_wake(w.0) };
    })));
    0
}

pub fn kick() {
    // SAFETY: async-signal-safe; a no-op before the main loop opens.
    unsafe { ms_io_kick() };
}

pub fn unwatch(fd: i32) {
    // SAFETY: only the scheduler thread reaches its loop.
    unsafe { ms_io_unwatch(fd) };
}

pub fn forget(fd: i32) {
    // SAFETY: as above.
    unsafe { ms_io_forget(fd) };
}

pub unsafe fn close(_: i32) {
    crate::isolate::set_wake(None);
    // SAFETY: closes this thread's loop.
    unsafe { ms_io_close(crate::isolate::is_main()) };
}

pub unsafe fn watch(_: i32, fd: i32, events: u32) -> Watch {
    // SAFETY: only the scheduler thread reaches its loop.
    match unsafe { ms_io_watch(fd, events) } {
        0 => Watch::Armed,
        1 => Watch::Always,
        _ => Watch::Failed,
    }
}

pub unsafe fn wait(_: i32, timeout_ns: i64, out: &mut [MaybeUninit<Ready>; 64]) -> Option<usize> {
    let mut count = 0;
    // SAFETY: the reactor writes at most `out.len()` entries and reports how many.
    let ok = unsafe { ms_io_wait(timeout_ns, out.as_mut_ptr().cast(), out.len(), &mut count) };
    ok.then_some(count)
}

/// Windows pipes and kernel objects, through the reactor (`ms_io_pipe_*`, `ms_io_object_*` in `reactor.h`).
#[cfg(windows)]
mod windows {
    use std::io::{Error, ErrorKind, Result};

    /// `MsBytes` and `MsBytesMut`: a pointer and a length, passed by value.
    #[repr(C)]
    struct Span {
        ptr: *mut u8,
        len: usize,
    }

    /// `MsIoPipeStatus`.
    const PIPE_OK: i32 = 0;
    const PIPE_WOULD_BLOCK: i32 = 1;
    const PIPE_END: i32 = 2;
    const PIPE_FAILED: i32 = 3;

    unsafe extern "C" {
        fn ms_io_pipe_adopt(handle: usize) -> bool;
        fn ms_io_pipe_adopted(handle: usize) -> bool;
        fn ms_io_pipe_read(
            handle: usize,
            buffer: Span,
            count: *mut usize,
            os_code: *mut i32,
        ) -> i32;
        fn ms_io_pipe_write(handle: usize, data: Span, count: *mut usize, os_code: *mut i32)
        -> i32;
        fn ms_io_pipe_group(handle: usize, key: usize);
        fn ms_io_pipe_drop(handle: usize);
        fn ms_io_object_watch(handle: usize) -> bool;
        fn ms_io_object_drop(handle: usize);
    }

    /// What a pipe call came to, as the `io::Result` the callers match on.
    fn outcome(status: i32, count: usize, os_code: i32, end: ErrorKind) -> Result<usize> {
        match status {
            PIPE_OK => Ok(count),
            PIPE_WOULD_BLOCK => Err(ErrorKind::WouldBlock.into()),
            PIPE_END => Err(end.into()),
            PIPE_FAILED => Err(Error::from_raw_os_error(os_code)),
            _ => Err(ErrorKind::NotFound.into()),
        }
    }

    /// Takes over the overlapped named pipe `handle`; false (the handle still the caller's) when it was not
    /// opened for overlapped I/O.
    ///
    /// # Safety
    /// `handle` is an open named-pipe handle, owned by the poller from now on.
    pub unsafe fn pipe_adopt(handle: usize) -> bool {
        // SAFETY: forwarded from the caller; only the scheduler thread reaches its reactor.
        unsafe { ms_io_pipe_adopt(handle) }
    }

    /// One non-blocking read from an adopted pipe; `WouldBlock` until data arrives, `BrokenPipe` at end of stream.
    pub fn pipe_read(handle: usize, buf: &mut [u8]) -> Result<usize> {
        let (mut count, mut code) = (0, 0);
        let span = Span {
            ptr: buf.as_mut_ptr(),
            len: buf.len(),
        };
        // SAFETY: the span is a live buffer and the outputs are writable.
        let status = unsafe { ms_io_pipe_read(handle, span, &mut count, &mut code) };
        outcome(status, count, code, ErrorKind::BrokenPipe)
    }

    /// One non-blocking write to an adopted pipe; `WouldBlock` while an earlier write is in flight.
    pub fn pipe_write(handle: usize, buf: &[u8]) -> Result<usize> {
        let (mut count, mut code) = (0, 0);
        let span = Span {
            ptr: buf.as_ptr().cast_mut(),
            len: buf.len(),
        };
        // SAFETY: the span is a live buffer the reactor only reads, and the outputs are writable.
        let status = unsafe { ms_io_pipe_write(handle, span, &mut count, &mut code) };
        outcome(status, count, code, ErrorKind::BrokenPipe)
    }

    /// Whether `handle` is a pipe the poller adopted.
    pub fn pipe_adopted(handle: usize) -> bool {
        // SAFETY: only reads the reactor's table.
        unsafe { ms_io_pipe_adopted(handle) }
    }

    /// Wakes the task waiting on `key` for reading whenever the adopted pipe `handle` becomes ready.
    pub fn pipe_group(handle: usize, key: usize) {
        // SAFETY: plain table update on the scheduler thread.
        unsafe { ms_io_pipe_group(handle, key) }
    }

    /// Closes an adopted pipe.
    pub fn pipe_drop(handle: usize) {
        // SAFETY: as above.
        unsafe { ms_io_pipe_drop(handle) }
    }

    /// Watches the waitable kernel object `handle` (a process); false when the wait cannot be registered.
    ///
    /// # Safety
    /// `handle` stays open until [`object_drop`].
    pub unsafe fn object_watch(handle: usize) -> bool {
        // SAFETY: forwarded from the caller.
        unsafe { ms_io_object_watch(handle) }
    }

    /// Ends the watch on `handle`; the caller may close it afterwards.
    pub fn object_drop(handle: usize) {
        // SAFETY: as above.
        unsafe { ms_io_object_drop(handle) }
    }
}

#[cfg(windows)]
pub use windows::*;
