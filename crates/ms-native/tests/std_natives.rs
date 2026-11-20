//! Drives the exported `msstd_*` natives of the `ms-std-*` crates through the C ABI with real runtime strings.
#![allow(
    unsafe_code,
    clippy::undocumented_unsafe_blocks,
    clippy::missing_safety_doc
)]
use ms_rt::string::{bytes, from_bytes};
use ms_rt_abi::{ErrSlot, HasRaw};
use std::cell::Cell;
use std::sync::{Mutex, MutexGuard};

static LOCK: Mutex<()> = Mutex::new(());

/// Serializes tests that touch runtime globals.
fn lock() -> MutexGuard<'static, ()> {
    LOCK.lock().unwrap_or_else(|e| e.into_inner())
}

/// The env var that tells a re-executed test binary which `assert_fault` call to run.
const FAULT_CALL: &str = "MS_ASSERT_FAULT_CALL";
/// The process exit status of a runtime fault.
const EXIT_FAULT: i32 = ms_rt_abi::EXIT_ABORT;
thread_local! {
    /// Calls to `assert_fault` so far in this test (each test runs on its own thread).
    static FAULT_CALLS: Cell<usize> = const { Cell::new(0) };
}

/// Asserts the closure faults with exactly this first line (frames ignored). A fault ends the
/// process, so the test binary re-runs this test in a new process: that child skips the earlier
/// `assert_fault` calls, runs this one, and must exit with the fault status and report.
#[track_caller]
fn assert_fault<R>(message: &str, operation: impl FnOnce() -> R) {
    let call = FAULT_CALLS.replace(FAULT_CALLS.get() + 1);
    if let Ok(target) = std::env::var(FAULT_CALL) {
        if target.parse() == Ok(call) {
            operation();
            std::process::exit(0);
        }
        return;
    }
    let test = std::thread::current()
        .name()
        .expect("test thread name")
        .to_string();
    let out = std::process::Command::new(std::env::current_exe().expect("test binary"))
        .args(["--exact", &test, "--test-threads=1", "--nocapture"])
        .env(FAULT_CALL, call.to_string())
        .output()
        .expect("spawn the test binary");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert_eq!(
        out.status.code(),
        Some(EXIT_FAULT),
        "expected a fault; stderr:\n{stderr}"
    );
    let report = stderr.lines().find(|l| l.contains(message));
    assert!(
        report.is_some(),
        "no report line has {message:?}; stderr:\n{stderr}"
    );
}
use ms_rt_abi::{
    STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_OK, STATUS_OUT_OF_RANGE, StrVal,
};
use ms_std_time::*;
use std::string::String;

/// A string argument that lives for the rest of the test run.
fn st(t: &str) -> *const StrVal {
    Box::leak(Box::new(from_bytes(t.as_bytes())))
}

/// Calls a string-returning native on a fresh output slot and reads the result.
fn ret(f: impl FnOnce(*mut StrVal)) -> String {
    let mut out = ms_rt::string::NO_STR;
    f(&mut out);
    text(&out)
}

fn text(s: *const StrVal) -> String {
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
            ret(|o| msstd_time_timestamp_to_string(&t, o)),
            "2024-07-04T16:05:09.5Z"
        );
        assert_eq!(
            msstd_time_parse_timestamp(st("nope"), &mut t),
            STATUS_INVALID_DATA
        );
        t = Timestamp {
            seconds: 1_720_109_109,
            nanos: 0,
        };

        // Zone names resolve in Manuscript; the natives take the offset and abbreviation.
        let mut cal = std::mem::MaybeUninit::<CalendarOut>::uninit();
        msstd_time_timestamp_calendar(&t, 9 * 3600, st("JST"), cal.as_mut_ptr());
        let cal = cal.assume_init();
        assert_eq!(
            (cal.year, cal.month, cal.day, cal.hour, cal.offset_seconds),
            (2024, 7, 5, 1, 9 * 3600)
        );
        assert_eq!(text(cal.zone.as_ptr()), "JST");

        let mut out = ms_rt::string::NO_STR;
        msstd_time_timestamp_format(
            &t,
            st("YYYY/MM/DD HH:mm ZZ"),
            5 * 3600 + 1800,
            st("+05:30"),
            &mut out,
        );
        assert_eq!(text(&out), "2024/07/04 21:35 +05:30");

        let mut local = 0_i64;
        assert_eq!(
            msstd_time_local_from_calendar(2024, 7, 4, 21, 35, 9, 0, &mut local),
            STATUS_OK
        );
        let mut back = Timestamp {
            seconds: 0,
            nanos: 0,
        };
        assert_eq!(
            msstd_time_from_local(local, 0, 5 * 3600 + 1800, &mut back),
            STATUS_OK
        );
        assert_eq!((back.seconds, back.nanos), (t.seconds, 0));
        assert_eq!(
            msstd_time_local_from_calendar(2024, 2, 30, 0, 0, 0, 0, &mut local),
            STATUS_OUT_OF_RANGE
        );

        assert_eq!(
            ret(|o| msstd_time_error_message(STATUS_OUT_OF_RANGE, o)),
            "time: value out of range"
        );
    }
}

mod process {
    use super::*;
    use ms_rt_abi::VecVal;
    use ms_std_process::*;

    fn empty() -> VecVal {
        VecVal {
            ptr: core::ptr::null_mut(),
            len: 0,
            cap: 0,
        }
    }

    #[test]
    fn memory_usage_reports_heap_and_resident() {
        let _g = lock();
        // The heap figures describe the calling isolate's arena.
        ms_rt::alloc::claim_heap();
        let blocks: std::vec::Vec<*mut u8> = (0..1000).map(|_| ms_rt::alloc::alloc(64)).collect();
        let mut out = std::mem::MaybeUninit::<MemoryOut>::uninit();
        // SAFETY: `out` is writable.
        let (status, m) = unsafe {
            let s = msstd_process_memory_usage(out.as_mut_ptr(), ErrSlot(core::ptr::null_mut()));
            (s, out.assume_init_read())
        };
        for b in blocks {
            // SAFETY: allocated above.
            unsafe { ms_rt::alloc::free(b) };
        }
        if !cfg!(any(target_os = "linux", target_os = "macos", windows)) {
            assert_eq!(status, ms_rt_abi::STATUS_UNSUPPORTED);
            return;
        }
        assert_eq!(status, STATUS_OK);
        assert!(m.heap_used >= 64_000 && m.heap_total >= m.heap_used);
        assert!(m.resident > 0 && m.external >= 0);
    }

    // These moved to C (runtime/std/process.c); the archive defines them.
    unsafe extern "C" {
        fn msstd_process_working_directory(out: *mut ms_rt_abi::StrVal, err: ErrSlot) -> u8;
        fn msstd_process_set_environment(
            name: *const ms_rt_abi::StrVal,
            has_value: HasRaw,
            value: *const ms_rt_abi::StrVal,
            err: ErrSlot,
        ) -> u8;
        fn msstd_process_environment(
            names: *mut ms_rt_abi::VecVal,
            values: *mut ms_rt_abi::VecVal,
            err: ErrSlot,
        ) -> u8;
    }

    #[test]
    fn control_through_the_abi() {
        let _g = lock();
        // SAFETY: valid runtime values and out pointers throughout.
        unsafe {
            let started = msstd_process_uptime();
            let uptime = msstd_process_uptime();
            assert!(started >= 0 && uptime >= started);
            let mut cwd = ms_rt::string::NO_STR;
            assert_eq!(
                msstd_process_working_directory(&mut cwd, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert!(!text(&cwd).is_empty());
            assert_eq!(
                msstd_process_set_environment(
                    st("MS_ABI_VAR"),
                    HasRaw(1),
                    st("x"),
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_OK
            );
            let (mut names, mut values) = (empty(), empty());
            assert_eq!(
                msstd_process_environment(&mut names, &mut values, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(names.len, values.len);
            assert_eq!(
                msstd_process_set_environment(
                    st("A=B"),
                    HasRaw(0),
                    st(""),
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_INVALID_INPUT
            );
            let mut info = std::mem::MaybeUninit::<ProcessInfoOut>::uninit();
            assert_eq!(
                msstd_process_info(info.as_mut_ptr(), ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            let i = info.assume_init();
            let os = if cfg!(target_os = "macos") {
                "darwin"
            } else if cfg!(windows) {
                "windows"
            } else {
                "linux"
            };
            assert_eq!((text(i.os.as_ptr()).as_str(), i.pid > 0), (os, true));
        }
    }
}
