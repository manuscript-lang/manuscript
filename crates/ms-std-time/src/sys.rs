//! The two OS clock calls behind `time.clock()`, `time.wall_clock()` and `time.sleep()`.
#![allow(unsafe_code)]

use core::sync::atomic::{AtomicI64, Ordering};

#[repr(C)]
struct Timespec {
    tv_sec: i64,
    tv_nsec: i64,
}

unsafe extern "C" {
    fn clock_gettime(clock: i32, ts: *mut Timespec) -> i32;
    fn nanosleep(req: *const Timespec, rem: *mut Timespec) -> i32;
}

const CLOCK_REALTIME: i32 = 0;
#[cfg(target_os = "macos")]
const CLOCK_MONOTONIC: i32 = 6;
#[cfg(not(target_os = "macos"))]
const CLOCK_MONOTONIC: i32 = 1;

fn read_clock(clock: i32) -> (i64, i64) {
    let mut t = Timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    // SAFETY: `t` is writable.
    unsafe { clock_gettime(clock, &mut t) };
    (t.tv_sec, t.tv_nsec)
}

/// Wall-clock seconds and nanoseconds since the Unix epoch.
pub fn realtime() -> (i64, i64) {
    read_clock(CLOCK_REALTIME)
}

/// Nanoseconds since the first reading in this process.
pub fn monotonic_since_start() -> i64 {
    static START: AtomicI64 = AtomicI64::new(i64::MIN);
    let (s, n) = read_clock(CLOCK_MONOTONIC);
    let now = s * 1_000_000_000 + n;
    let start = match START.compare_exchange(i64::MIN, now, Ordering::Relaxed, Ordering::Relaxed) {
        Ok(_) => now,
        Err(start) => start,
    };
    now - start
}

/// Sleeps up to `nanos` and returns how long it actually slept (less when a signal interrupts).
pub fn sleep(nanos: i64) -> i64 {
    let req = Timespec {
        tv_sec: nanos / 1_000_000_000,
        tv_nsec: nanos % 1_000_000_000,
    };
    let mut rem = Timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    // SAFETY: both pointers are valid for the call.
    let interrupted = unsafe { nanosleep(&req, &mut rem) } != 0;
    if interrupted {
        nanos - (rem.tv_sec * 1_000_000_000 + rem.tv_nsec)
    } else {
        nanos
    }
}
