//! Drives the exported `msstd_*` natives of the `ms-std-*` crates through the C ABI with real runtime strings.
#![allow(
    unsafe_code,
    clippy::undocumented_unsafe_blocks,
    clippy::missing_safety_doc
)]
use ms_rt::string::{bytes, from_bytes};
use ms_rt::trap;
use std::sync::{Mutex, MutexGuard};

static LOCK: Mutex<()> = Mutex::new(());

/// Serializes tests that touch runtime globals.
fn lock() -> MutexGuard<'static, ()> {
    LOCK.lock().unwrap_or_else(|e| e.into_inner())
}

/// Runs `operation` in a trap and returns the fault text it raised, or `None` when it returned.
/// Unix traps in a forked child (the production fault path); Windows has no fork, so the
/// operation runs in this frame under a setjmp-style guard and `msrt_trap_begin` returns twice.
#[inline(never)]
fn fault_of<R>(operation: impl FnOnce() -> R) -> Option<String> {
    // SAFETY: this frame stays live until `msrt_trap_end` resumes after the call.
    #[cfg(windows)]
    let began = unsafe { trap::msrt_trap_begin() };
    #[cfg(not(windows))]
    let began = trap::msrt_trap_begin();
    if began == 0 {
        operation();
        trap::msrt_trap_end();
    }
    let mut message = ms_rt_abi::StrVal::literal(std::ptr::null_mut(), 0);
    // SAFETY: the message out pointer is writable and the trap belongs to this thread.
    let faulted = unsafe { trap::msrt_trap_wait(&mut message) };
    if faulted == 0 {
        return None;
    }
    // SAFETY: a successful wait transfers a live runtime string to the caller.
    unsafe {
        let text = String::from_utf8_lossy(bytes(&message)).into_owned();
        ms_rt::string::release(&message);
        Some(text)
    }
}

/// Asserts the closure faults with exactly this first line (frames ignored).
#[track_caller]
fn assert_fault<R>(message: &str, operation: impl FnOnce() -> R) {
    let got = fault_of(operation).expect("expected a fault");
    assert_eq!(got.lines().next().unwrap_or(""), message);
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
            ret(|o| msstd_time_timestamp_to_string(&t, o)),
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
        assert_eq!(text(cal.zone.as_ptr()), "JST");
        let mut c2 = std::mem::MaybeUninit::<CalendarOut>::uninit();
        assert_eq!(
            msstd_time_timestamp_calendar(&t, st("Mars/Base"), c2.as_mut_ptr()),
            STATUS_INVALID_INPUT
        );

        let mut out = ms_rt::string::NO_STR;
        assert_eq!(
            msstd_time_timestamp_format(&t, st("YYYY/MM/DD HH:mm ZZ"), st("+05:30"), &mut out),
            STATUS_OK
        );
        assert_eq!(text(&out), "2024/07/04 21:35 +05:30");

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
            ret(|o| msstd_time_error_message(STATUS_OUT_OF_RANGE, o)),
            "time: value out of range"
        );
    }
}

mod fs_io {
    use super::*;
    use ms_rt_abi::{STATUS_ALREADY_EXISTS, STATUS_NONE, STATUS_NOT_FOUND, VecVal};
    use ms_std_fs::*;
    use ms_std_io::*;
    use std::vec::Vec;

    fn vec_of(b: &[u8]) -> VecVal {
        let mut v = VecVal {
            ptr: core::ptr::null_mut(),
            len: 0,
            cap: 0,
        };
        // SAFETY: `v` is writable.
        unsafe { ms_rt::glue::write_bytes(b, &mut v) };
        v
    }

    fn contents(v: &VecVal) -> Vec<u8> {
        // SAFETY: `v` is a live byte vector.
        unsafe { ms_rt::glue::vec_bytes(v) }.to_vec()
    }

    #[test]
    fn fs_round_trip_through_the_abi() {
        let _g = lock();
        let dir = st(&std::format!("/tmp/msrt-fs-{}", std::process::id()));
        let file = st(&std::format!("/tmp/msrt-fs-{}/a.txt", std::process::id()));
        let data = vec_of(b"hello");
        let mut out = VecVal {
            ptr: core::ptr::null_mut(),
            len: 0,
            cap: 0,
        };
        let mut info = std::mem::MaybeUninit::<InfoOut>::uninit();
        // SAFETY: valid runtime strings and out pointers throughout.
        unsafe {
            assert_eq!(msstd_fs_create_directory(dir, 1), STATUS_OK);
            assert_eq!(msstd_fs_write_file(file, &data, 0), STATUS_OK);
            assert_eq!(msstd_fs_write_file(file, &data, 0), STATUS_ALREADY_EXISTS);
            assert_eq!(msstd_fs_append_file(file, &data), STATUS_OK);
            assert_eq!(msstd_fs_read_file(file, 0, 0, &mut out), STATUS_OK);
            assert_eq!(contents(&out), b"hellohello");
            assert_eq!(msstd_fs_stat(file, 1, info.as_mut_ptr()), STATUS_OK);
            let i = info.assume_init();
            assert_eq!((i.size, text(i.name.as_ptr()).as_str()), (10, "a.txt"));
            let mut listed = VecVal {
                ptr: core::ptr::null_mut(),
                len: 0,
                cap: 0,
            };
            assert_eq!(msstd_fs_list(dir, 0, 0, &mut listed), STATUS_OK);
            assert_eq!(listed.len, 1);
            let missing = st("/tmp/msrt-fs-missing/none");
            assert_eq!(
                msstd_fs_read_file(missing, 0, 0, &mut out),
                STATUS_NOT_FOUND
            );
            assert_eq!(msstd_fs_remove(dir, 1), STATUS_OK);
            assert_eq!(msstd_fs_remove(dir, 1), STATUS_OK);
            let mut s = ms_rt::string::NO_STR;
            assert_eq!(msstd_fs_read_link(file, &mut s), STATUS_NOT_FOUND);
        }
    }

    fn empty() -> VecVal {
        VecVal {
            ptr: core::ptr::null_mut(),
            len: 0,
            cap: 0,
        }
    }

    /// A closure object that counts the entries its predicate sees.
    #[repr(C)]
    struct Counting {
        hdr: ms_rt_abi::Closure,
        count: u8,
    }

    unsafe extern "C-unwind" fn skip_deep(
        env: *mut ms_rt_abi::Closure,
        ptr: *mut u8,
        tagged: usize,
        _destination: *mut u8,
        _destination_tagged: usize,
    ) -> u8 {
        // SAFETY: `env` is the `Counting` the test passed; the source is a live string.
        unsafe { (*env.cast::<Counting>()).count += 1 };
        (!text(&StrVal {
            ptr_word: ptr,
            tagged,
        })
        .ends_with("deep")) as u8
    }

    #[test]
    fn handles_directories_glob_and_copy_through_the_abi() {
        let _g = lock();
        let root = std::format!("/tmp/msrt-fs2-{}", std::process::id());
        let (r, a, deep, dest) = (
            st(&root),
            st(&std::format!("{root}/a.txt")),
            st(&std::format!("{root}/sub/deep")),
            st(&std::format!("{root}-out")),
        );
        let mut handle: *mut ms_rt::ffi::ObjCell<ms_std_fs::stream::Stream> = core::ptr::null_mut();
        let mut out = empty();
        let mut size = 0i64;
        let data = vec_of(b"abcdef");
        // SAFETY: valid runtime strings, live handles and writable out pointers throughout.
        unsafe {
            assert_eq!(msstd_fs_create_directory(deep, 1), STATUS_OK);
            assert_eq!(msstd_fs_write_file(a, &data, 0), STATUS_OK);

            let mode = st("r+");
            let mut flags = 0i64;
            assert_eq!(msstd_fs_open_flags(mode, &mut flags), STATUS_OK);
            assert_eq!(msstd_fs_file_open(a, flags, 0o600, &mut handle), STATUS_OK);
            assert_eq!(msstd_fs_file_read_at(handle, 2, 1, 2, &mut out), STATUS_OK);
            assert_eq!(contents(&out), b"cd");
            let x = vec_of(b"XY");
            assert_eq!(msstd_fs_file_write_at(handle, 1, &x), STATUS_OK);
            assert_eq!(msstd_fs_file_truncate(handle, 4), STATUS_OK);
            assert_eq!(msstd_fs_file_seek(handle, 0, 0, &mut size), STATUS_OK);
            assert_eq!(msstd_fs_file_read_file(handle, 0, 0, &mut out), STATUS_OK);
            assert_eq!(contents(&out), b"aXYd");
            msstd_io_close(handle.cast());
            assert_eq!(msstd_fs_file_sync(handle), ms_rt_abi::STATUS_CLOSED);
            ms_rt::glue::release(handle.cast());

            let mut cursor: *mut ms_rt::ffi::ObjCell<ms_std_fs::dir::Directory> =
                core::ptr::null_mut();
            assert_eq!(msstd_fs_directory_open(r, &mut cursor), STATUS_OK);
            let mut entry = std::mem::MaybeUninit::<ms_std_fs::EntryOut>::uninit();
            let mut seen = Vec::new();
            while msstd_fs_directory_read(cursor, entry.as_mut_ptr()) == STATUS_OK {
                let e = entry.assume_init_read();
                seen.push((text(e.name.as_ptr()), e.directory));
            }
            seen.sort();
            assert_eq!(seen, [("a.txt".into(), 0), ("sub".into(), 1)]);
            msstd_fs_directory_close(cursor);
            ms_rt::glue::release(cursor.cast());

            let pattern = st("**/*.txt");
            assert_eq!(msstd_fs_glob(r, pattern, 0, 0, &mut out), STATUS_OK);
            assert_eq!(out.len, 1);

            let mut filter = Counting {
                hdr: ms_rt_abi::Closure {
                    hdr: ms_rt_abi::Obj { rc: 1, drop: None },
                    code: skip_deep as *const u8,
                },
                count: 0,
            };
            let clone = st("none");
            assert_eq!(
                msstd_fs_copy(
                    r,
                    dest,
                    1 | 16,
                    clone,
                    0,
                    0,
                    0,
                    0,
                    core::ptr::addr_of_mut!(filter).cast()
                ),
                STATUS_OK
            );
            assert_eq!(filter.count, 4);
            let copied = st(&std::format!("{root}-out/a.txt"));
            assert_eq!(msstd_fs_read_file(copied, 0, 0, &mut out), STATUS_OK);
            assert_eq!(contents(&out), b"aXYd");
            let skipped = st(&std::format!("{root}-out/sub/deep"));
            assert_eq!(
                msstd_fs_read_file(skipped, 0, 0, &mut out),
                STATUS_NOT_FOUND
            );

            let (mut names, mut values) = (empty(), empty());
            msstd_fs_constants(&mut names, &mut values);
            assert!(names.len > 10 && names.len == values.len);
            assert_eq!(msstd_fs_remove(r, 1), STATUS_OK);
            assert_eq!(msstd_fs_remove(dest, 1), STATUS_OK);
        }
    }

    // The native watcher is inotify; elsewhere `FileWatcher` falls back to polling.
    #[cfg(not(target_os = "linux"))]
    #[test]
    fn native_file_watchers_are_unsupported_off_linux() {
        let _g = lock();
        let r = st("/tmp");
        let mut h: *mut ms_rt::ffi::ObjCell<ms_std_fs::watch::Watcher> = core::ptr::null_mut();
        // SAFETY: valid runtime strings and a writable handle.
        unsafe {
            assert_eq!(
                msstd_fs_watch_native(r, 1, 0, 0, 0, 0, st("error"), &mut h),
                ms_rt_abi::STATUS_UNSUPPORTED
            );
        }
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn file_watchers_through_the_abi() {
        let _g = lock();
        let root = std::format!("/tmp/msrt-watch-{}", std::process::id());
        let r = st(&root);
        let overflow = st("error");
        let mut h: *mut ms_rt::ffi::ObjCell<ms_std_fs::watch::Watcher> = core::ptr::null_mut();
        let (mut paths, mut kinds) = (empty(), empty());
        // SAFETY: valid runtime strings, live handles and writable outputs throughout.
        unsafe {
            assert_eq!(msstd_fs_create_directory(r, 1), STATUS_OK);
            assert_eq!(
                msstd_fs_watch_native(r, 1, 0, 0, 0, 0, st("bogus"), &mut h),
                ms_rt_abi::STATUS_INVALID_INPUT
            );
            assert_eq!(
                msstd_fs_watch_native(r, 1, 0, 0, 0, 0, overflow, &mut h),
                STATUS_OK
            );
            let file = st(&std::format!("{root}/x"));
            assert_eq!(msstd_fs_write_file(file, &vec_of(b"1"), 0), STATUS_OK);
            assert_eq!(msstd_fs_watch_next(h, &mut paths, &mut kinds), STATUS_OK);
            assert_eq!((paths.len, contents(&kinds)), (1, vec![1]));
            msstd_fs_watch_close(h);
            assert_eq!(
                msstd_fs_watch_next(h, &mut paths, &mut kinds),
                ms_rt_abi::STATUS_CLOSED
            );
            ms_rt::glue::release(h.cast());
            assert_eq!(msstd_fs_remove(r, 1), STATUS_OK);
        }
    }

    #[test]
    fn io_streams_through_the_abi() {
        let _g = lock();
        let one_line = std::env::temp_dir().join(std::format!("msrt-io-{}", std::process::id()));
        std::fs::write(&one_line, "one line\n").unwrap();
        let path = st(one_line.to_str().unwrap());
        let mut h: *mut _ = core::ptr::null_mut();
        let mut chunk = VecVal {
            ptr: core::ptr::null_mut(),
            len: 0,
            cap: 0,
        };
        let mut line = ms_rt::string::NO_STR;
        // SAFETY: valid handles and out pointers throughout.
        unsafe {
            assert_eq!(
                msstd_io_open(st("/definitely/missing"), &mut h),
                ms_rt_abi::STATUS_UNAVAILABLE
            );
            assert_eq!(msstd_io_open(path, &mut h), STATUS_OK);
            assert_eq!(msstd_io_read_line(h, 1, 0, &mut line), STATUS_INVALID_INPUT);
            assert_eq!(msstd_io_read_line(h, 0, 0, &mut line), STATUS_OK);
            assert!(!text(&line).is_empty());
            assert_eq!(msstd_io_read(h, 0, 0, &mut chunk), STATUS_NONE);
            assert_eq!(msstd_io_is_closed(h), 0);
            msstd_io_close(h);
            assert_eq!(msstd_io_is_closed(h), 1);
            assert_eq!(msstd_io_read(h, 0, 0, &mut chunk), ms_rt_abi::STATUS_CLOSED);
            let err = msstd_io_standard(2);
            assert_eq!(msstd_io_flush(err), STATUS_OK);
            std::fs::remove_file(&one_line).unwrap();
        }
    }
}

mod process {
    use super::*;
    use ms_rt_abi::{STATUS_OUTPUT_LIMIT, STATUS_TIMEOUT, STATUS_UNAVAILABLE, VecVal};
    use ms_std_io::*;
    use ms_std_process::*;

    fn list_of(items: &[&str]) -> VecVal {
        let strs: std::vec::Vec<StrVal> = items.iter().map(|s| from_bytes(s.as_bytes())).collect();
        let mut v = VecVal {
            ptr: core::ptr::null_mut(),
            len: 0,
            cap: 0,
        };
        // SAFETY: `v` is writable.
        unsafe { ms_rt::glue::write_string_list(&strs, &mut v) };
        v
    }

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
        let blocks: std::vec::Vec<*mut u8> = (0..1000).map(|_| ms_rt::alloc::alloc(64)).collect();
        let mut out = std::mem::MaybeUninit::<MemoryOut>::uninit();
        // SAFETY: `out` is writable.
        let (status, m) = unsafe {
            let s = msstd_process_memory_usage(out.as_mut_ptr());
            (s, out.assume_init_read())
        };
        for b in blocks {
            // SAFETY: allocated above.
            unsafe { ms_rt::alloc::free(b) };
        }
        if !cfg!(any(target_os = "linux", windows)) {
            assert_eq!(status, ms_rt_abi::STATUS_UNSUPPORTED);
            return;
        }
        assert_eq!(status, STATUS_OK);
        assert!(m.heap_used >= 64_000 && m.heap_total >= m.heap_used);
        assert!(m.resident > 0 && m.external >= 0);
    }

    #[cfg(unix)]
    unsafe extern "C" {
        fn raise(sig: i32) -> i32;
    }

    #[cfg(unix)]
    #[test]
    fn watch_signals_through_the_abi() {
        let _g = lock();
        // SIGUSR1 is 10 on Linux and 30 on macOS.
        let usr1: i64 = if cfg!(target_os = "linux") { 10 } else { 30 };
        let list = {
            let mut v = empty();
            // SAFETY: `v` is writable.
            unsafe { ms_rt::glue::write_list(&[usr1], &mut v) };
            v
        };
        let mut h: *mut ms_rt::ffi::ObjCell<ms_std_process::signals::Watcher> =
            core::ptr::null_mut();
        let mut n = 0i64;
        // SAFETY: valid list, writable outputs and a live handle throughout.
        unsafe {
            assert_eq!(msstd_process_watch_signals(&list, 0, 0, &mut h), STATUS_OK);
            assert_eq!(raise(usr1 as i32), 0);
            assert_eq!(msstd_process_signal_next(h, &mut n), STATUS_OK);
            assert_eq!(n, usr1);
            msstd_process_signal_close(h);
            assert_eq!(
                msstd_process_signal_next(h, &mut n),
                ms_rt_abi::STATUS_CLOSED
            );
            ms_rt::glue::release(h.cast());
        }
    }

    #[test]
    fn run_and_spawn_through_the_abi() {
        let _g = lock();
        let mut out = std::mem::MaybeUninit::<CommandOut>::uninit();
        let args = list_of(&["-c", "echo hi; exit 2"]);
        let mut input = empty();
        // SAFETY: valid runtime values and out pointers throughout.
        unsafe {
            ms_rt::glue::write_bytes(b"", &mut input);
            assert_eq!(
                msstd_process_command_run(st("sh"), &args, &input, 0, 0, 0, 0, out.as_mut_ptr()),
                STATUS_OK
            );
            let o = out.assume_init_read();
            assert_eq!((o.exit_code, o.stdout.as_slice()), (2, b"hi\n".as_slice()));
            assert_eq!(
                msstd_process_command_run(
                    st("nope-nope"),
                    &args,
                    &input,
                    0,
                    0,
                    0,
                    0,
                    out.as_mut_ptr()
                ),
                STATUS_UNAVAILABLE
            );
            let spin = list_of(&["-c", "sleep 30"]);
            assert_eq!(
                msstd_process_command_run(
                    st("sh"),
                    &spin,
                    &input,
                    0,
                    0,
                    1,
                    50_000_000,
                    out.as_mut_ptr()
                ),
                STATUS_TIMEOUT
            );
            let flood = list_of(&["-c", "yes | head -c 100000"]);
            assert_eq!(
                msstd_process_command_run(st("sh"), &flood, &input, 1, 10, 0, 0, out.as_mut_ptr()),
                STATUS_OUTPUT_LIMIT
            );
            assert_eq!(
                msstd_process_command_run(st("sh"), &args, &input, 1, -1, 0, 0, out.as_mut_ptr()),
                STATUS_INVALID_INPUT
            );

            let mut child = core::ptr::null_mut();
            assert_eq!(
                msstd_process_command_spawn(st("cat"), &empty(), &mut child),
                STATUS_OK
            );
            let stdin = msstd_process_subprocess_stream(child, 0);
            let stdout = msstd_process_subprocess_stream(child, 1);
            let mut data = empty();
            ms_rt::glue::write_bytes(b"ping", &mut data);
            assert_eq!(msstd_io_write_bytes(stdin.cast(), &data), STATUS_OK);
            msstd_io_close(stdin.cast());
            let mut chunk = empty();
            assert_eq!(msstd_io_read(stdout.cast(), 0, 0, &mut chunk), STATUS_OK);
            assert_eq!(ms_rt::glue::vec_bytes(&chunk), b"ping");
            let mut code = -9;
            assert_eq!(
                msstd_process_subprocess_wait(child, 1, 5_000_000_000, &mut code),
                STATUS_OK
            );
            assert_eq!(code, 0);
            msstd_process_subprocess_close(child);
            ms_rt::glue::release(stdin.cast());
            ms_rt::glue::release(stdout.cast());
            ms_rt::glue::release(child.cast());
        }
    }

    #[test]
    fn control_through_the_abi() {
        let _g = lock();
        // SAFETY: valid runtime values and out pointers throughout.
        unsafe {
            // Uptime counts from its first call here, the monotonic clock from its own first
            // reading; reading uptime first keeps its origin no later than the clock's.
            let started = msstd_process_uptime();
            let a = msstd_process_monotonic_time();
            let uptime = msstd_process_uptime();
            assert!(started >= 0 && a >= 0 && uptime >= a && uptime >= started);
            let mut cwd = ms_rt::string::NO_STR;
            assert_eq!(msstd_process_working_directory(&mut cwd), STATUS_OK);
            assert!(!text(&cwd).is_empty());
            assert_eq!(
                msstd_process_set_environment(st("MS_ABI_VAR"), 1, st("x")),
                STATUS_OK
            );
            let (mut names, mut values) = (empty(), empty());
            assert_eq!(
                msstd_process_environment(&mut names, &mut values),
                STATUS_OK
            );
            assert_eq!(names.len, values.len);
            assert_eq!(
                msstd_process_set_environment(st("A=B"), 0, st("")),
                STATUS_INVALID_INPUT
            );
            let mut info = std::mem::MaybeUninit::<InfoOut>::uninit();
            assert_eq!(msstd_process_info(info.as_mut_ptr()), STATUS_OK);
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
