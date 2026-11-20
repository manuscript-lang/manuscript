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

mod fs_io {
    use super::*;
    use ms_rt_abi::{STATUS_ALREADY_EXISTS, STATUS_NOT_FOUND, VecVal};
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
            assert_eq!(
                msstd_fs_create_directory(dir, 1, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(
                msstd_fs_write_file(file, &data, 0, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(
                msstd_fs_write_file(file, &data, 0, ErrSlot(core::ptr::null_mut())),
                STATUS_ALREADY_EXISTS
            );
            assert_eq!(
                msstd_fs_append_file(file, &data, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(
                msstd_fs_read_file(file, HasRaw(0), 0, &mut out, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(contents(&out), b"hellohello");
            assert_eq!(
                msstd_fs_stat(file, 1, info.as_mut_ptr(), ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            let i = info.assume_init();
            assert_eq!((i.size, text(i.name.as_ptr()).as_str()), (10, "a.txt"));
            let mut listed = VecVal {
                ptr: core::ptr::null_mut(),
                len: 0,
                cap: 0,
            };
            assert_eq!(
                msstd_fs_list(
                    dir,
                    HasRaw(0),
                    0,
                    &mut listed,
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_OK
            );
            assert_eq!(listed.len, 1);
            let missing = st("/tmp/msrt-fs-missing/none");
            assert_eq!(
                msstd_fs_read_file(
                    missing,
                    HasRaw(0),
                    0,
                    &mut out,
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_NOT_FOUND
            );
            assert_eq!(
                msstd_fs_remove(dir, 1, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(
                msstd_fs_remove(dir, 1, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            let mut s = ms_rt::string::NO_STR;
            assert_eq!(
                msstd_fs_read_link(file, &mut s, ErrSlot(core::ptr::null_mut())),
                STATUS_NOT_FOUND
            );
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
            assert_eq!(
                msstd_fs_create_directory(deep, 1, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(
                msstd_fs_write_file(a, &data, 0, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );

            let mode = st("r+");
            assert_eq!(
                msstd_fs_open(a, mode, 0o600, &mut handle, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(
                msstd_fs_file_read_at(
                    handle,
                    2,
                    HasRaw(1),
                    2,
                    &mut out,
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_OK
            );
            assert_eq!(contents(&out), b"cd");
            let x = vec_of(b"XY");
            assert_eq!(
                msstd_fs_file_write_at(handle, 1, &x, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(
                msstd_fs_file_truncate(handle, 4, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(
                msstd_fs_file_seek(handle, 0, 0, &mut size, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(
                msstd_fs_file_read_file(
                    handle,
                    HasRaw(0),
                    0,
                    &mut out,
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_OK
            );
            assert_eq!(contents(&out), b"aXYd");
            assert_eq!(
                msstd_io_close(handle.cast(), ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(
                msstd_fs_file_sync(handle, ErrSlot(core::ptr::null_mut())),
                ms_rt_abi::STATUS_CLOSED
            );
            ms_rt::obj::msrt_obj_drop(handle.cast());

            let mut cursor: *mut ms_rt::ffi::ObjCell<ms_std_fs::dir::Directory> =
                core::ptr::null_mut();
            assert_eq!(
                msstd_fs_directory_open(r, &mut cursor, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            let mut entry = std::mem::MaybeUninit::<ms_std_fs::EntryOut>::uninit();
            let mut seen = Vec::new();
            while msstd_fs_directory_read(
                cursor,
                entry.as_mut_ptr(),
                ErrSlot(core::ptr::null_mut()),
            ) == STATUS_OK
            {
                let e = entry.assume_init_read();
                seen.push((text(e.name.as_ptr()), e.directory));
            }
            seen.sort();
            assert_eq!(seen, [("a.txt".into(), 0), ("sub".into(), 1)]);
            msstd_fs_directory_close(cursor);
            ms_rt::obj::msrt_obj_drop(cursor.cast());

            let mut filter = Counting {
                hdr: ms_rt_abi::Closure {
                    hdr: ms_rt_abi::Obj {
                        clone: None,
                        drop: None,
                    },
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
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(0),
                    0,
                    core::ptr::addr_of_mut!(filter).cast(),
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_OK
            );
            assert_eq!(filter.count, 4);
            let copied = st(&std::format!("{root}-out/a.txt"));
            assert_eq!(
                msstd_fs_read_file(
                    copied,
                    HasRaw(0),
                    0,
                    &mut out,
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_OK
            );
            assert_eq!(contents(&out), b"aXYd");
            let skipped = st(&std::format!("{root}-out/sub/deep"));
            assert_eq!(
                msstd_fs_read_file(
                    skipped,
                    HasRaw(0),
                    0,
                    &mut out,
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_NOT_FOUND
            );

            assert_eq!(
                msstd_fs_remove(r, 1, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(
                msstd_fs_remove(dest, 1, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
        }
    }

    #[test]
    fn file_watchers_through_the_abi() {
        let _g = lock();
        let dir = std::env::temp_dir().join(std::format!("msrt-watch-{}", std::process::id()));
        let root = dir.to_str().unwrap().to_owned();
        let r = st(&root);
        let overflow = st("error");
        let mut h: *mut ms_rt::ffi::ObjCell<ms_std_fs::watch::Watcher> = core::ptr::null_mut();
        let mut events = empty();
        // SAFETY: valid runtime strings, live handles and writable outputs throughout.
        unsafe {
            assert_eq!(
                msstd_fs_create_directory(r, 1, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(
                msstd_fs_watch_native(
                    r,
                    1,
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(0),
                    0,
                    st("bogus"),
                    &mut h,
                    ErrSlot(core::ptr::null_mut())
                ),
                ms_rt_abi::STATUS_INVALID_INPUT
            );
            assert_eq!(
                msstd_fs_watch_native(
                    r,
                    1,
                    ms_rt_abi::HasRaw(0),
                    0,
                    ms_rt_abi::HasRaw(0),
                    0,
                    overflow,
                    &mut h,
                    ErrSlot(core::ptr::null_mut())
                ),
                STATUS_OK
            );
            let file = st(dir.join("x").to_str().unwrap());
            assert_eq!(
                msstd_fs_write_file(file, &vec_of(b"1"), 0, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert_eq!(
                msstd_fs_watch_next(h, &mut events, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
            assert!(events.len >= 1);
            msstd_fs_watch_close(h);
            assert_eq!(
                msstd_fs_watch_next(h, &mut events, ErrSlot(core::ptr::null_mut())),
                ms_rt_abi::STATUS_CLOSED
            );
            ms_rt::obj::msrt_obj_drop(h.cast());
            assert_eq!(
                msstd_fs_remove(r, 1, ErrSlot(core::ptr::null_mut())),
                STATUS_OK
            );
        }
    }
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
