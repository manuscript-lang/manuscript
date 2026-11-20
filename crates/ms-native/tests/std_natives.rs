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
