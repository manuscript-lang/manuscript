//! The Unix poller on the C reactor (`runtime/io/reactor.c`, libuv): the `c-reactor` feature.
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
