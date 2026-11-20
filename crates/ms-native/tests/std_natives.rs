//! Drives the exported `msstd_*` natives of the `ms-std-*` crates through the C ABI with real runtime strings.
#![allow(
    unsafe_code,
    clippy::undocumented_unsafe_blocks,
    clippy::missing_safety_doc
)]
use ms_rt::string::{bytes, from_bytes};
use ms_rt_abi::{ErrSlot, HasRaw};
use std::sync::{Mutex, MutexGuard};

static LOCK: Mutex<()> = Mutex::new(());

/// Serializes tests that touch runtime globals.
fn lock() -> MutexGuard<'static, ()> {
    LOCK.lock().unwrap_or_else(|e| e.into_inner())
}

use ms_rt_abi::{STATUS_INVALID_INPUT, STATUS_OK, StrVal};
use std::string::String;

/// A string argument that lives for the rest of the test run.
fn st(t: &str) -> *const StrVal {
    Box::leak(Box::new(from_bytes(t.as_bytes())))
}

fn text(s: *const StrVal) -> String {
    // SAFETY: tests pass live strings.
    String::from_utf8_lossy(unsafe { bytes(s) }).into_owned()
}

mod process {
    use super::*;
    use ms_rt_abi::{STATUS_NOT_FOUND, STATUS_OUTPUT_LIMIT, STATUS_TIMEOUT, VecVal};
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
            assert_eq!(
                msstd_process_watch_signals(
                    &list,
                    HasRaw(0),
                    0,
                    &mut h,
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_OK
            );
            assert_eq!(raise(usr1 as i32), 0);
            assert_eq!(
                msstd_process_signal_next(h, &mut n, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(n, usr1);
            msstd_process_signal_close(h);
            assert_eq!(
                msstd_process_signal_next(h, &mut n, ErrSlot(core::ptr::null_mut())),
                ms_rt_abi::STATUS_CLOSED
            );
            ms_rt::obj::msrt_obj_drop(h.cast());
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
                msstd_process_command_run(
                    st("sh"),
                    &args,
                    &input,
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(0),
                    st(""),
                    &empty(),
                    &empty(),
                    out.as_mut_ptr(),
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_OK
            );
            let o = out.assume_init_read();
            assert_eq!((o.exit_code, o.stdout.as_slice()), (2, b"hi\n".as_slice()));
            assert_eq!(
                msstd_process_command_run(
                    st("nope-nope"),
                    &args,
                    &input,
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(0),
                    st(""),
                    &empty(),
                    &empty(),
                    out.as_mut_ptr(),
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_NOT_FOUND
            );
            let spin = list_of(&["-c", "sleep 30"]);
            assert_eq!(
                msstd_process_command_run(
                    st("sh"),
                    &spin,
                    &input,
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(1),
                    50_000_000,
                    ms_rt_abi::HasRaw(0),
                    st(""),
                    &empty(),
                    &empty(),
                    out.as_mut_ptr(),
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_TIMEOUT
            );
            let flood = list_of(&["-c", "yes | head -c 100000"]);
            assert_eq!(
                msstd_process_command_run(
                    st("sh"),
                    &flood,
                    &input,
                    ms_rt_abi::HasRaw(1),
                    10,
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(0),
                    st(""),
                    &empty(),
                    &empty(),
                    out.as_mut_ptr(),
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_OUTPUT_LIMIT
            );
            assert_eq!(
                msstd_process_command_run(
                    st("sh"),
                    &args,
                    &input,
                    ms_rt_abi::HasRaw(1),
                    -1,
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(0),
                    st(""),
                    &empty(),
                    &empty(),
                    out.as_mut_ptr(),
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_INVALID_INPUT
            );

            let mut child = core::ptr::null_mut();
            assert_eq!(
                msstd_process_command_spawn(
                    st("true"),
                    &empty(),
                    0,
                    0,
                    0,
                    HasRaw(0),
                    st(""),
                    &empty(),
                    &empty(),
                    &mut child,
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_OK
            );
            let mut code = -9;
            assert_eq!(
                msstd_process_subprocess_wait(
                    child,
                    HasRaw(1),
                    5_000_000_000,
                    &mut code,
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_OK
            );
            assert_eq!(code, 0);
            msstd_process_subprocess_close(child);
            ms_rt::obj::msrt_obj_drop(child.cast());
        }
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
