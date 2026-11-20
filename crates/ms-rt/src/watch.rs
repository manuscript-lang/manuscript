//! The watcher of the C scheduler (`runtime/core/watch.c`): a thread that looks at the scheduler threads from
//! outside, for the hook of the Rust HTTP server that sends a resting thread to take the connections of a held-up
//! one. Goes away with `ms-std-net`.
#![allow(unsafe_code)]

/// One look of the watcher at the threads.
#[derive(Clone, Copy, Debug)]
#[repr(C)]
pub struct Look {
    pub now: u64,
    pub last: u64,
}

/// Called at every look with the resting threads (bit `i` for thread `i`); answers whether to look often for a while.
pub type Hook = extern "C" fn(Look, u64) -> bool;

unsafe extern "C" {
    fn ms_watch_epoch() -> u64;
    fn ms_watch_add_hook(hook: Hook) -> bool;
    fn ms_watch_stirred(isolate: u32) -> u64;
}

/// The watcher's clock as of its last look.
pub fn epoch() -> u64 {
    // SAFETY: reads an atomic.
    unsafe { ms_watch_epoch() }
}

/// Adds `hook` (once) and starts the watcher.
pub fn add_hook(hook: Hook) {
    // SAFETY: a plain function pointer.
    let _ = unsafe { ms_watch_add_hook(hook) };
}

/// The clock when `thread` last left its rest.
pub fn stirred(thread: usize) -> u64 {
    // SAFETY: reads an atomic.
    unsafe { ms_watch_stirred(thread as u32) }
}
