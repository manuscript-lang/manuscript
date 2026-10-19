//! Drives the exported `msstd_*` natives of the `ms-std-*` crates through the C ABI with real runtime strings.
use crate::string::{bytes, from_bytes};
use crate::testutil::{assert_fault, lock};
use ms_rt_abi::{
    STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_OK, STATUS_OUT_OF_RANGE, StrObj,
};
use ms_std_time::*;
use std::string::String;

fn st(t: &str) -> *mut StrObj {
    from_bytes(t.as_bytes())
}

fn text(s: *const StrObj) -> String {
    // SAFETY: tests pass live strings.
    String::from_utf8_lossy(unsafe { bytes(s) }).into_owned()
}

#[test]
fn duration_arithmetic_and_faults() {
    let _g = lock();
    assert_eq!(msstd_time_duration_add(2, 3), 5);
    assert_eq!(msstd_time_duration_to_milliseconds(2_500_000), 2);
    assert_eq!(msstd_time_duration_to_seconds(1_500_000_000), 1.5);
    assert_fault(
        "Duration.add: overflow; found value (nanoseconds) 9223372036854775807 and other (nanoseconds) 1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807",
        || msstd_time_duration_add(i64::MAX, 1),
    );
    assert_fault(
        "Duration.multiply: overflow; found value (nanoseconds) 4611686018427387904 and factor 2; result nanoseconds must be between -9223372036854775808 and 9223372036854775807",
        || msstd_time_duration_multiply(1 << 62, 2),
    );
    assert_fault(
        "Duration.divide: division by zero; divisor must be nonzero, found 0",
        || msstd_time_duration_divide(1, 0),
    );
    assert_fault(
        "Duration.abs: value (nanoseconds) must be between -9223372036854775807 and 9223372036854775807, found -9223372036854775808",
        || msstd_time_duration_abs(i64::MIN),
    );
    assert_fault(
        "sleep: duration (nanoseconds) must be between 0 and 9223372036854775807, found -1",
        || msstd_time_sleep(-1),
    );
    msstd_time_sleep(1_000_000);
}

#[test]
fn instants_share_a_domain() {
    let _g = lock();
    let mut a = Instant { domain: 0, tick: 0 };
    let mut b = a;
    // SAFETY: valid pointers.
    unsafe {
        msstd_time_clock_now(&mut a);
        msstd_time_instant_shift(&a, 5, &mut b);
        assert_eq!(msstd_time_instant_difference(&b, &a), 5);
        assert_eq!(msstd_time_instant_compare(&a, &b), -1);
        assert_eq!(msstd_time_instant_equal(&a, &a), 1);
        let other = Instant { domain: 2, tick: 0 };
        assert_fault("instants belong to different clock domains", || {
            msstd_time_instant_compare(&a, &other)
        });
    }
}

#[test]
fn timestamps_round_trip_through_strings() {
    let _g = lock();
    let mut t = Timestamp {
        seconds: 0,
        nanos: 0,
    };
    // SAFETY: valid pointers and live strings.
    unsafe {
        assert_eq!(
            msstd_time_parse_timestamp(st("2024-07-04T16:05:09.5Z"), &mut t),
            STATUS_OK
        );
        assert_eq!(
            text(msstd_time_timestamp_to_string(&t)),
            "2024-07-04T16:05:09.5Z"
        );
        assert_eq!(
            msstd_time_parse_timestamp(st("nope"), &mut t),
            STATUS_INVALID_DATA
        );
        assert_eq!(
            msstd_time_timestamp(0, 1_000_000_000, &mut t),
            STATUS_OUT_OF_RANGE
        );
        assert_eq!(msstd_time_timestamp(1_720_109_109, 0, &mut t), STATUS_OK);

        let mut cal = std::mem::MaybeUninit::<CalendarOut>::uninit();
        assert_eq!(
            msstd_time_timestamp_calendar(&t, st("Asia/Tokyo"), cal.as_mut_ptr()),
            STATUS_OK
        );
        let cal = cal.assume_init();
        assert_eq!(
            (cal.year, cal.month, cal.day, cal.hour, cal.offset_seconds),
            (2024, 7, 5, 1, 9 * 3600)
        );
        assert_eq!(text(cal.zone), "JST");
        let mut c2 = std::mem::MaybeUninit::<CalendarOut>::uninit();
        assert_eq!(
            msstd_time_timestamp_calendar(&t, st("Mars/Base"), c2.as_mut_ptr()),
            STATUS_INVALID_INPUT
        );

        let mut out: *mut StrObj = std::ptr::null_mut();
        assert_eq!(
            msstd_time_timestamp_format(&t, st("YYYY/MM/DD HH:mm ZZ"), st("+05:30"), &mut out),
            STATUS_OK
        );
        assert_eq!(text(out), "2024/07/04 21:35 +05:30");

        let mut back = Timestamp {
            seconds: 0,
            nanos: 0,
        };
        assert_eq!(
            msstd_time_from_calendar(2024, 7, 4, 21, 35, 9, 0, st("+05:30"), &mut back),
            STATUS_OK
        );
        assert_eq!((back.seconds, back.nanos), (t.seconds, 0));
        assert_eq!(
            msstd_time_from_calendar(2024, 2, 30, 0, 0, 0, 0, st("UTC"), &mut back),
            STATUS_OUT_OF_RANGE
        );

        let mut d = 0i64;
        let mut later = t;
        assert_eq!(
            msstd_time_timestamp_shift(&t, 1_500_000_000, &mut later),
            STATUS_OK
        );
        assert_eq!(
            msstd_time_timestamp_difference(&later, &t, &mut d),
            STATUS_OK
        );
        assert_eq!(d, 1_500_000_000);
        assert_eq!(msstd_time_timestamp_compare(&t, &later), -1);
        assert_eq!(
            text(msstd_time_error_message(STATUS_OUT_OF_RANGE)),
            "time: value out of range"
        );
    }
}
