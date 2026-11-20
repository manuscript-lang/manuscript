//! The Unix poller on the C reactor (`runtime/io/reactor.c`, libuv): the `c-reactor` feature.
//! Same contract as the mio poller in `poller.rs`; the scheduler does not know the difference.

use super::*;

unsafe extern "C" {
    fn msio_open(is_main: i32) -> *mut core::ffi::c_void;
    fn msio_close(is_main: i32);
    fn msio_wake(wake: *mut core::ffi::c_void);
    fn msio_kick();
    fn msio_watch(fd: i32, events: u32) -> i32;
    fn msio_unwatch(fd: i32);
    fn msio_forget(fd: i32);
    fn msio_wait(timeout_ns: i64, out: *mut Ready, cap: usize) -> isize;
}

/// The handle `msio_wake` takes, movable into the isolate's wake closure.
struct WakeHandle(*mut core::ffi::c_void);
// SAFETY: `uv_async_send` is the one libuv call that is safe from any thread; the handle lives
// until `close` clears the isolate's wake closure.
unsafe impl Send for WakeHandle {}
unsafe impl Sync for WakeHandle {}

pub unsafe fn create() -> i32 {
    let main = i32::from(crate::isolate::is_main());
    // SAFETY: opens this thread's loop.
    let wake = unsafe { msio_open(main) };
    if wake.is_null() {
        fault::fault(b"cannot create the I/O poller");
    }
    let wake = WakeHandle(wake);
    crate::isolate::set_wake(Some(Box::new(move || {
        let w = &wake;
        // SAFETY: the loop outlives the closure (`close` unsets it first).
        unsafe { msio_wake(w.0) };
    })));
    0
}

/// Interrupts the wait; one `uv_async_send`, so signal handlers may call it.
pub fn kick() {
    // SAFETY: async-signal-safe; a no-op before the main loop opens.
    unsafe { msio_kick() };
}

pub fn unwatch(fd: i32) {
    // SAFETY: only the scheduler thread reaches its loop.
    unsafe { msio_unwatch(fd) };
}

pub fn forget(fd: i32) {
    // SAFETY: as above.
    unsafe { msio_forget(fd) };
}

pub unsafe fn close(_: i32) {
    crate::isolate::set_wake(None);
    // SAFETY: closes this thread's loop.
    unsafe { msio_close(i32::from(crate::isolate::is_main())) };
}

pub unsafe fn watch(_: i32, fd: i32, events: u32) -> Watch {
    // SAFETY: only the scheduler thread reaches its loop.
    match unsafe { msio_watch(fd, events) } {
        0 => Watch::Armed,
        1 => Watch::Always,
        _ => Watch::Failed,
    }
}

pub unsafe fn wait(_: i32, timeout_ns: i64, out: &mut [MaybeUninit<Ready>; 64]) -> Option<usize> {
    // SAFETY: the reactor writes at most 64 entries and the count it returns.
    let n = unsafe { msio_wait(timeout_ns, out.as_mut_ptr().cast(), out.len()) };
    usize::try_from(n).ok()
}
