//! `@std/time` natives. Symbols are `msstd_time_<name>`.
//!
//! Values: `Duration` is an `i64` of nanoseconds passed by value. `Timestamp` is
//! `repr(C) { seconds: i64, nanos: i64 }` and `Instant` is `repr(C) { domain: u64, tick: i64 }`;
//! both are passed by pointer and returned through a trailing `out`. Fallible functions return a
//! status (`0` ok, else an `ms-rt-abi` `STATUS_*` code) and write the result only on success.
//! Arithmetic faults carry the Go runtime's message text.
#![no_std]

extern crate alloc;

pub mod civil;
pub mod core_time;
mod sys;
pub mod zone;

pub use core_time as logic;

use alloc::string::String;
use core_time::Ts;
use ms_rt_abi::{STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_OUT_OF_RANGE};
use ms_std_core::{StatusCode, Str, abi_record, native};
use ms_std_rt::{fault, fault_fmt, poll_cancel, task_sleep};

abi_record! {
    #[derive(Clone, Copy)]
    pub struct Timestamp {
        pub seconds: i64,
        pub nanos: i64,
    }
}

abi_record! {
    #[derive(Clone, Copy)]
    pub struct Instant {
        pub domain: u64,
        pub tick: i64,
    }
}

abi_record! {
    /// `Calendar` fields in declaration order, then the zone name (owned string).
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
        pub zone: Str,
    }
}

/// The clock domain of the process monotonic clock (`time.clock()`).
const MONOTONIC_DOMAIN: u64 = 1;

fn ts(t: &Timestamp) -> Ts {
    Ts {
        seconds: t.seconds,
        nanos: t.nanos,
    }
}

fn stamp(t: Ts) -> Timestamp {
    Timestamp {
        seconds: t.seconds,
        nanos: t.nanos,
    }
}

fn code<T>(r: Result<T, u8>) -> Result<T, StatusCode> {
    r.map_err(StatusCode)
}

fn same_clock(a: &Instant, b: &Instant) {
    if a.domain != b.domain {
        fault("instants belong to different clock domains");
    }
}

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

fn duration_of(operation: &str, n: i64, scale: i64) -> i64 {
    let (low, high) = (i64::MIN / scale, i64::MAX / scale);
    if n < low || n > high {
        fault_fmt(format_args!(
            "{operation}: value must be between {low} and {high}, found {n}"
        ));
    }
    n * scale
}

native! {
    safe fn msstd_time_duration_add(left: i64, other: i64) -> i64 {
        checked_add("Duration.add", "value", "other", left, other)
    }

    safe fn msstd_time_duration_plus(left: i64, right: i64) -> i64 {
        checked_add("Duration.+", "left", "right", left, right)
    }

    safe fn msstd_time_duration_minus(left: i64, right: i64) -> i64 {
        checked_sub("Duration.-", "left", "right", left, right)
    }

    safe fn msstd_time_duration_subtract(left: i64, other: i64) -> i64 {
        checked_sub("Duration.subtract", "value", "other", left, other)
    }

    safe fn msstd_time_int_milliseconds(n: i64) -> i64 {
        duration_of("Int.milliseconds", n, 1_000_000)
    }

    safe fn msstd_time_int_seconds(n: i64) -> i64 {
        duration_of("Int.seconds", n, 1_000_000_000)
    }

    safe fn msstd_time_int_minutes(n: i64) -> i64 {
        duration_of("Int.minutes", n, 60_000_000_000)
    }

    safe fn msstd_time_duration_multiply(value: i64, factor: i64) -> i64 {
        value
            .checked_mul(factor)
            .unwrap_or_else(|| overflow("Duration.multiply", "value", "factor", value, factor))
    }

    safe fn msstd_time_duration_divide(value: i64, divisor: i64) -> i64 {
        if divisor == 0 {
            fault("Duration.divide: division by zero; divisor must be nonzero, found 0");
        }
        value
            .checked_div(divisor)
            .unwrap_or_else(|| overflow("Duration.divide", "value", "divisor", value, divisor))
    }

    safe fn msstd_time_duration_negate(value: i64) -> i64 {
        value
            .checked_neg()
            .unwrap_or_else(|| range_fault("Duration.negate", value))
    }

    safe fn msstd_time_duration_abs(value: i64) -> i64 {
        value
            .checked_abs()
            .unwrap_or_else(|| range_fault("Duration.abs", value))
    }

    safe fn msstd_time_duration_compare(left: i64, other: i64) -> i64 {
        (left > other) as i64 - (left < other) as i64
    }

    safe fn msstd_time_duration_to_microseconds(value: i64) -> i64 {
        value / 1_000
    }

    safe fn msstd_time_duration_to_milliseconds(value: i64) -> i64 {
        value / 1_000_000
    }

    safe fn msstd_time_duration_to_seconds(value: i64) -> f64 {
        value as f64 / 1e9
    }

    safe fn msstd_time_duration_to_minutes(value: i64) -> f64 {
        value as f64 / 6e10
    }

    safe fn msstd_time_duration_to_hours(value: i64) -> f64 {
        value as f64 / 3.6e12
    }

    // ---- Instant and clocks ----

    fn msstd_time_instant_shift(value: &Instant, duration: i64) -> out Instant {
        Instant {
            domain: value.domain,
            tick: checked_add("Instant.shift", "value", "duration", value.tick, duration),
        }
    }

    fn msstd_time_instant_unshift(value: &Instant, duration: i64) -> out Instant {
        Instant {
            domain: value.domain,
            tick: checked_sub("Instant.-", "value", "duration", value.tick, duration),
        }
    }

    fn msstd_time_instant_difference(left: &Instant, other: &Instant) -> i64 {
        same_clock(left, other);
        checked_sub("Instant.difference", "value", "other", left.tick, other.tick)
    }

    fn msstd_time_instant_compare(left: &Instant, other: &Instant) -> i64 {
        same_clock(left, other);
        (left.tick > other.tick) as i64 - (left.tick < other.tick) as i64
    }

    fn msstd_time_instant_equal(left: &Instant, other: &Instant) -> bool {
        same_clock(left, other);
        left.tick == other.tick
    }

    /// `time.clock().now()`: nanoseconds since the first reading in this process.
    fn msstd_time_clock_now() -> out Instant {
        Instant {
            domain: MONOTONIC_DOMAIN,
            tick: sys::monotonic_since_start(),
        }
    }

    /// `time.wall_clock().now()`.
    fn msstd_time_wall_clock_now() -> out Timestamp {
        let (seconds, nanos) = sys::realtime();
        Timestamp { seconds, nanos }
    }

    /// `time.sleep(duration)`: parks the current task, so other tasks (server handlers) keep
    /// running; wakes early only to unwind a stop request.
    safe fn msstd_time_sleep(duration: i64) -> () {
        if duration < 0 {
            fault_fmt(format_args!(
                "sleep: duration (nanoseconds) must be between 0 and {}, found {duration}",
                i64::MAX
            ));
        }
        poll_cancel();
        task_sleep(duration);
    }

    // ---- Timestamp ----

    /// `time.timestamp(seconds, nanoseconds)`.
    fn msstd_time_timestamp(seconds: i64, nanoseconds: i64) -> Result<Timestamp, StatusCode> {
        code(logic::new_timestamp(seconds, nanoseconds)).map(stamp)
    }

    /// `time.parse_timestamp(text)`.
    fn msstd_time_parse_timestamp(text: &str) -> Result<Timestamp, StatusCode> {
        code(logic::parse_timestamp(text.as_bytes())).map(stamp)
    }

    fn msstd_time_timestamp_to_string(value: &Timestamp) -> String {
        logic::to_string(ts(value))
    }

    fn msstd_time_timestamp_shift(value: &Timestamp, duration: i64) -> Result<Timestamp, StatusCode> {
        code(logic::shift(ts(value), duration)).map(stamp)
    }

    fn msstd_time_timestamp_difference(
        left: &Timestamp,
        other: &Timestamp,
    ) -> Result<i64, StatusCode> {
        code(logic::difference(ts(left), ts(other)))
    }

    fn msstd_time_timestamp_compare(left: &Timestamp, other: &Timestamp) -> i64 {
        logic::compare(ts(left), ts(other))
    }

    fn msstd_time_timestamp_calendar(
        value: &Timestamp,
        zone: &str,
    ) -> Result<CalendarOut, StatusCode> {
        let c = code(logic::calendar(ts(value), zone))?;
        let v = c.civil;
        Ok(CalendarOut {
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
            zone: Str::new(&c.zone),
        })
    }

    fn msstd_time_timestamp_format(
        value: &Timestamp,
        pattern: &str,
        zone: &str,
    ) -> Result<String, StatusCode> {
        let text = code(logic::format(ts(value), pattern.as_bytes(), zone))?;
        Ok(String::from_utf8_lossy(&text).into_owned())
    }

    /// `time.from_calendar(year, month, day, hour, minute, second, nanosecond, zone)`.
    fn msstd_time_from_calendar(
        year: i64,
        month: i64,
        day: i64,
        hour: i64,
        minute: i64,
        second: i64,
        nanosecond: i64,
        zone: &str,
    ) -> Result<Timestamp, StatusCode> {
        code(logic::from_calendar(
            year, month, day, hour, minute, second, nanosecond, zone,
        ))
        .map(stamp)
    }

    /// `time.local_zone()`.
    safe fn msstd_time_local_zone() -> String {
        zone::local_zone_name()
    }

    /// `TimeError.message()` for a status code.
    safe fn msstd_time_error_message(status: u8) -> &'static str {
        match status {
            STATUS_INVALID_INPUT => "time: invalid input",
            STATUS_INVALID_DATA => "time: invalid data",
            STATUS_OUT_OF_RANGE => "time: value out of range",
            _ => "time: operation failed",
        }
    }
}
