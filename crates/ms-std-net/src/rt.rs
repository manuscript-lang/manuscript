//! Hooks into the `ms-rt` runtime that the network modules need.
//!
//! Only the ms thread may call `msrt_*` (the allocator and counts are not
//! atomic); background threads of this crate never touch this module.

use std::sync::atomic::{AtomicU8, Ordering};

unsafe extern "C" {
    static msrt_cancel_flag: AtomicU8;
    fn msrt_cancelled() -> !;
}

/// Whether SIGINT/SIGTERM asked the program to stop.
pub fn cancel_requested() -> bool {
    // SAFETY: the flag is a static `u8` the runtime updates from a signal handler; atomics
    // have the layout of the integer and relaxed loads are what the ABI prescribes.
    unsafe { msrt_cancel_flag.load(Ordering::Relaxed) != 0 }
}

/// Unwinds the program through the runtime's cancellation path when a stop was requested.
pub fn check_cancel() {
    if cancel_requested() {
        // SAFETY: runs cleanups and exits; never returns.
        unsafe { msrt_cancelled() }
    }
}
