//! `@std/time` natives. Symbols are `msstd_time_<name>`.
//!
//! Values: `Duration` is an `i64` of nanoseconds passed by value. `Timestamp` is
//! `repr(C) { seconds: i64, nanos: i64 }` and `Instant` is `repr(C) { domain: u64, tick: i64 }`;
//! both are passed by pointer and returned through a trailing `out`. Fallible functions return a
//! status (`0` ok, else an `ms-rt-abi` `STATUS_*` code) and write the result only on success.
//! Arithmetic faults carry the Go runtime's message text.
#![no_std]
// The exports below are the C ABI compiled code links against.
#![allow(unsafe_code)]
#![allow(clippy::missing_safety_doc)]

extern crate alloc;

pub mod civil;
pub mod core_time;
pub mod zone;

pub use core_time as logic;

use core_time::Ts;
use ms_rt_abi::{
    STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_OK, STATUS_OUT_OF_RANGE, StrObj,
};
use ms_std_rt::{fault, fault_fmt, new_string, str_bytes};

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Timestamp {
    pub seconds: i64,
    pub nanos: i64,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Instant {
    pub domain: u64,
    pub tick: i64,
}

/// `Calendar` fields in declaration order, then the zone name (owned string).
#[repr(C)]
pub struct CalendarOut {
    pub year: i64,
    pub month: i64,
    pub day: i64,
    pub hour: i64,
    pub minute: i64,
    pub second: i64,
    pub nanosecond: i64,
    pub weekday: i64,
    pub day_of_year: i64,
    pub offset_seconds: i64,
    pub zone: *mut StrObj,
}

/// The clock domain of the process monotonic clock (`time.clock()`).
const MONOTONIC_DOMAIN: u64 = 1;

fn ts(t: &Timestamp) -> Ts {
    Ts {
        seconds: t.seconds,
        nanos: t.nanos,
    }
}

fn put(out: *mut Timestamp, t: Ts) {
    // SAFETY: callers pass a writable `out`.
    unsafe {
        *out = Timestamp {
            seconds: t.seconds,
            nanos: t.nanos,
        }
    };
}

fn status<T>(r: Result<T, u8>, ok: impl FnOnce(T)) -> u8 {
    match r {
        Ok(v) => {
            ok(v);
            STATUS_OK
        }
        Err(code) => code,
    }
}

// ---------------------------------------------------------------------------
// Duration
// ---------------------------------------------------------------------------

fn overflow(operation: &str, left_label: &str, right_label: &str, left: i64, right: i64) -> ! {
    let unit = if right_label == "factor" || right_label == "divisor" {
        ""
    } else {
        " (nanoseconds)"
    };
    fault_fmt(format_args!(
        "{operation}: overflow; found {left_label} (nanoseconds) {left} and {right_label}{unit} {right}; result nanoseconds must be between {} and {}",
        i64::MIN,
        i64::MAX
    ))
}

fn range_fault(operation: &str, value: i64) -> ! {
    fault_fmt(format_args!(
        "{operation}: value (nanoseconds) must be between {} and {}, found {value}",
        i64::MIN + 1,
        i64::MAX
    ))
}

fn checked_add(operation: &str, ll: &str, rl: &str, left: i64, right: i64) -> i64 {
    left.checked_add(right)
        .unwrap_or_else(|| overflow(operation, ll, rl, left, right))
}

fn checked_sub(operation: &str, ll: &str, rl: &str, left: i64, right: i64) -> i64 {
    left.checked_sub(right)
        .unwrap_or_else(|| overflow(operation, ll, rl, left, right))
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_add(left: i64, other: i64) -> i64 {
    checked_add("Duration.add", "value", "other", left, other)
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_plus(left: i64, right: i64) -> i64 {
    checked_add("Duration.+", "left", "right", left, right)
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_minus(left: i64, right: i64) -> i64 {
    checked_sub("Duration.-", "left", "right", left, right)
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_subtract(left: i64, other: i64) -> i64 {
    checked_sub("Duration.subtract", "value", "other", left, other)
}

/// `n` units of `scale` nanoseconds as a `Duration`; a value outside the representable range faults.
fn duration_of(operation: &str, n: i64, scale: i64) -> i64 {
    let (low, high) = (i64::MIN / scale, i64::MAX / scale);
    if n < low || n > high {
        fault_fmt(format_args!(
            "{operation}: value must be between {low} and {high}, found {n}"
        ));
    }
    n * scale
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_int_milliseconds(n: i64) -> i64 {
    duration_of("Int.milliseconds", n, 1_000_000)
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_int_seconds(n: i64) -> i64 {
    duration_of("Int.seconds", n, 1_000_000_000)
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_int_minutes(n: i64) -> i64 {
    duration_of("Int.minutes", n, 60_000_000_000)
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_multiply(value: i64, factor: i64) -> i64 {
    value
        .checked_mul(factor)
        .unwrap_or_else(|| overflow("Duration.multiply", "value", "factor", value, factor))
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_divide(value: i64, divisor: i64) -> i64 {
    if divisor == 0 {
        fault("Duration.divide: division by zero; divisor must be nonzero, found 0");
    }
    value
        .checked_div(divisor)
        .unwrap_or_else(|| overflow("Duration.divide", "value", "divisor", value, divisor))
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_negate(value: i64) -> i64 {
    value
        .checked_neg()
        .unwrap_or_else(|| range_fault("Duration.negate", value))
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_abs(value: i64) -> i64 {
    value
        .checked_abs()
        .unwrap_or_else(|| range_fault("Duration.abs", value))
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_compare(left: i64, other: i64) -> i64 {
    (left > other) as i64 - (left < other) as i64
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_to_microseconds(value: i64) -> i64 {
    value / 1_000
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_to_milliseconds(value: i64) -> i64 {
    value / 1_000_000
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_to_seconds(value: i64) -> f64 {
    value as f64 / 1e9
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_to_minutes(value: i64) -> f64 {
    value as f64 / 6e10
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_duration_to_hours(value: i64) -> f64 {
    value as f64 / 3.6e12
}

// ---------------------------------------------------------------------------
// Instant and clocks
// ---------------------------------------------------------------------------

fn same_clock(a: &Instant, b: &Instant) {
    if a.domain != b.domain {
        fault("instants belong to different clock domains");
    }
}

/// # Safety
/// `value` and `out` must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_instant_shift(
    value: *const Instant,
    duration: i64,
    out: *mut Instant,
) {
    // SAFETY: caller contract.
    unsafe {
        let v = *value;
        *out = Instant {
            domain: v.domain,
            tick: checked_add("Instant.shift", "value", "duration", v.tick, duration),
        };
    }
}

/// `Instant - Duration`.
///
/// # Safety
/// `value` and `out` must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_instant_unshift(
    value: *const Instant,
    duration: i64,
    out: *mut Instant,
) {
    // SAFETY: caller contract.
    unsafe {
        let v = *value;
        *out = Instant {
            domain: v.domain,
            tick: checked_sub("Instant.-", "value", "duration", v.tick, duration),
        };
    }
}

/// # Safety
/// Both pointers must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_instant_difference(
    left: *const Instant,
    other: *const Instant,
) -> i64 {
    // SAFETY: caller contract.
    let (l, o) = unsafe { (*left, *other) };
    same_clock(&l, &o);
    checked_sub("Instant.difference", "value", "other", l.tick, o.tick)
}

/// # Safety
/// Both pointers must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_instant_compare(
    left: *const Instant,
    other: *const Instant,
) -> i64 {
    // SAFETY: caller contract.
    let (l, o) = unsafe { (*left, *other) };
    same_clock(&l, &o);
    (l.tick > o.tick) as i64 - (l.tick < o.tick) as i64
}

/// # Safety
/// Both pointers must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_instant_equal(
    left: *const Instant,
    other: *const Instant,
) -> u8 {
    // SAFETY: caller contract.
    let (l, o) = unsafe { (*left, *other) };
    same_clock(&l, &o);
    (l.tick == o.tick) as u8
}

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

/// `time.clock().now()`: nanoseconds since the first reading in this process.
///
/// # Safety
/// `out` must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_clock_now(out: *mut Instant) {
    static START: core::sync::atomic::AtomicI64 = core::sync::atomic::AtomicI64::new(i64::MIN);
    let (s, n) = read_clock(CLOCK_MONOTONIC);
    let now = s * 1_000_000_000 + n;
    let start = match START.compare_exchange(
        i64::MIN,
        now,
        core::sync::atomic::Ordering::Relaxed,
        core::sync::atomic::Ordering::Relaxed,
    ) {
        Ok(_) => now,
        Err(start) => start,
    };
    // SAFETY: caller contract.
    unsafe {
        *out = Instant {
            domain: MONOTONIC_DOMAIN,
            tick: now - start,
        }
    };
}

/// `time.wall_clock().now()`.
///
/// # Safety
/// `out` must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_wall_clock_now(out: *mut Timestamp) {
    let (s, n) = read_clock(CLOCK_REALTIME);
    put(
        out,
        Ts {
            seconds: s,
            nanos: n,
        },
    );
}

/// `time.sleep(duration)`: wakes early only to unwind a stop request.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_sleep(duration: i64) {
    if duration < 0 {
        fault_fmt(format_args!(
            "sleep: duration (nanoseconds) must be between 0 and {}, found {duration}",
            i64::MAX
        ));
    }
    let mut remaining = duration;
    loop {
        if ms_std_rt::cancel_pending() {
            ms_std_rt::cancelled();
        }
        if remaining <= 0 {
            return;
        }
        // Short slices bound the latency of a stop request that lands between the check and the sleep.
        let slice = remaining.min(50_000_000);
        let req = Timespec {
            tv_sec: slice / 1_000_000_000,
            tv_nsec: slice % 1_000_000_000,
        };
        let mut rem = Timespec {
            tv_sec: 0,
            tv_nsec: 0,
        };
        // SAFETY: both pointers are valid for the call.
        let interrupted = unsafe { nanosleep(&req, &mut rem) } != 0;
        let slept = if interrupted {
            slice - (rem.tv_sec * 1_000_000_000 + rem.tv_nsec)
        } else {
            slice
        };
        remaining -= slept;
    }
}

// ---------------------------------------------------------------------------
// Timestamp
// ---------------------------------------------------------------------------

/// `time.timestamp(seconds, nanoseconds)`.
///
/// # Safety
/// `out` must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_timestamp(
    seconds: i64,
    nanoseconds: i64,
    out: *mut Timestamp,
) -> u8 {
    status(logic::new_timestamp(seconds, nanoseconds), |t| put(out, t))
}

/// `time.parse_timestamp(text)`.
///
/// # Safety
/// `text` must be a live string and `out` valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_parse_timestamp(
    text: *const StrObj,
    out: *mut Timestamp,
) -> u8 {
    // SAFETY: caller contract.
    status(logic::parse_timestamp(unsafe { str_bytes(text) }), |t| {
        put(out, t)
    })
}

/// # Safety
/// `value` must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_timestamp_to_string(
    value: *const Timestamp,
) -> *mut StrObj {
    // SAFETY: caller contract.
    new_string(logic::to_string(ts(unsafe { &*value })).as_bytes())
}

/// # Safety
/// `value` and `out` must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_timestamp_shift(
    value: *const Timestamp,
    duration: i64,
    out: *mut Timestamp,
) -> u8 {
    // SAFETY: caller contract.
    status(logic::shift(ts(unsafe { &*value }), duration), |t| {
        put(out, t)
    })
}

/// # Safety
/// All pointers must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_timestamp_difference(
    left: *const Timestamp,
    other: *const Timestamp,
    out: *mut i64,
) -> u8 {
    // SAFETY: caller contract.
    let r = logic::difference(ts(unsafe { &*left }), ts(unsafe { &*other }));
    // SAFETY: caller contract.
    status(r, |d| unsafe { *out = d })
}

/// # Safety
/// Both pointers must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_timestamp_compare(
    left: *const Timestamp,
    other: *const Timestamp,
) -> i64 {
    // SAFETY: caller contract.
    logic::compare(ts(unsafe { &*left }), ts(unsafe { &*other }))
}

/// # Safety
/// `value`, `zone` and `out` must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_timestamp_calendar(
    value: *const Timestamp,
    zone: *const StrObj,
    out: *mut CalendarOut,
) -> u8 {
    // SAFETY: caller contract.
    let r = logic::calendar(ts(unsafe { &*value }), &zone_text(zone));
    status(r, |c| {
        let v = c.civil;
        // SAFETY: caller contract.
        unsafe {
            *out = CalendarOut {
                year: v.year,
                month: v.month,
                day: v.day,
                hour: v.hour,
                minute: v.minute,
                second: v.second,
                nanosecond: v.nanosecond,
                weekday: v.weekday,
                day_of_year: v.day_of_year,
                offset_seconds: c.offset_seconds,
                zone: new_string(c.zone.as_bytes()),
            }
        };
    })
}

/// # Safety
/// All pointers must be valid; `out` receives an owned string on success.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_timestamp_format(
    value: *const Timestamp,
    pattern: *const StrObj,
    zone: *const StrObj,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    let r = logic::format(
        ts(unsafe { &*value }),
        unsafe { str_bytes(pattern) },
        &zone_text(zone),
    );
    // SAFETY: caller contract.
    status(r, |text| unsafe { *out = new_string(&text) })
}

/// `time.from_calendar(year, month, day, hour, minute, second, nanosecond, zone)`.
///
/// # Safety
/// `zone` must be a live string and `out` valid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msstd_time_from_calendar(
    year: i64,
    month: i64,
    day: i64,
    hour: i64,
    minute: i64,
    second: i64,
    nanosecond: i64,
    zone: *const StrObj,
    out: *mut Timestamp,
) -> u8 {
    let r = logic::from_calendar(
        year,
        month,
        day,
        hour,
        minute,
        second,
        nanosecond,
        &zone_text(zone),
    );
    status(r, |t| put(out, t))
}

/// `time.local_zone()`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_local_zone() -> *mut StrObj {
    new_string(zone::local_zone_name().as_bytes())
}

/// `TimeError.message()` for a status code.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msstd_time_error_message(status: u8) -> *mut StrObj {
    new_string(match status {
        STATUS_INVALID_INPUT => b"time: invalid input",
        STATUS_INVALID_DATA => b"time: invalid data",
        STATUS_OUT_OF_RANGE => b"time: value out of range",
        _ => b"time: operation failed",
    })
}

fn zone_text(zone: *const StrObj) -> alloc::string::String {
    // SAFETY: callers pass a live string.
    alloc::string::String::from_utf8_lossy(unsafe { str_bytes(zone) }).into_owned()
}
