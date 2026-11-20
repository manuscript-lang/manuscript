//! Which isolate the caller is.
#![allow(unsafe_code)]

unsafe extern "C" {
    fn ms_sched_is_worker() -> bool;
}

/// Whether the calling isolate is a worker.
pub fn is_worker() -> bool {
    // SAFETY: reads the thread's registration.
    unsafe { ms_sched_is_worker() }
}
