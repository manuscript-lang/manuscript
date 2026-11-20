//! The monotonic clock of the C runtime.
#![allow(unsafe_code)]

unsafe extern "C" {
    fn ms_sys_monotonic_ns() -> i64;
}

/// Nanoseconds on the monotonic clock, the base of every deadline of the scheduler.
pub fn monotonic_ns() -> i64 {
    // SAFETY: reads the clock.
    unsafe { ms_sys_monotonic_ns() }
}
