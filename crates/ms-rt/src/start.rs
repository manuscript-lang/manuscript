//! Process entry: tables, signals, the main thread with its large stack, exit status.
use crate::alloc;
use crate::fault::{self, PENDING_SIGNAL, STACK_HI, STACK_LO, TABLES};
use crate::global::Global;
use crate::string;
use crate::sys;
use core::ffi::c_void;
use core::sync::atomic::Ordering;
use ms_rt_abi::{MAX_MAIN_EXIT, Tables, VecVal};

/// Stack of the thread that runs `main` (the 200,000-call depth limit must be reachable).
const STACK_SIZE: usize = 1 << 30;
const GUARD: usize = 1 << 16;
/// Grace period after the first stop request before cleanup is abandoned.
const CLEANUP_GRACE_SECS: u32 = 30;

static ARGC: Global<i32> = Global::new(0);
static ARGV: Global<*const *const u8> = Global::new(core::ptr::null());
static MAIN_FN: Global<Option<extern "C-unwind" fn() -> i64>> = Global::new(None);
static MAIN_RESULT: Global<i64> = Global::new(0);
/// `CLOCK_MONOTONIC` nanoseconds when the runtime started; 0 before `msrt_start`.
static START_NANOS: Global<i64> = Global::new(0);

#[repr(C)]
struct Timespec {
    sec: i64,
    nsec: i64,
}

unsafe extern "C" {
    fn clock_gettime(clock: i32, ts: *mut Timespec) -> i32;
}

#[cfg(target_os = "macos")]
const CLOCK_MONOTONIC: i32 = 6;
#[cfg(not(target_os = "macos"))]
const CLOCK_MONOTONIC: i32 = 1;

/// Monotonic nanoseconds since the runtime started (the origin of `process.uptime()`); 0 when not started.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_start_nanos() -> i64 {
    // SAFETY: written once by `msrt_start` before any other thread exists.
    unsafe { *START_NANOS.ptr() }
}

extern "C" fn on_stop(sig: i32) {
    let prev = PENDING_SIGNAL.swap(sig as u8, Ordering::Relaxed);
    if prev != 0 {
        PENDING_SIGNAL.store(prev, Ordering::Relaxed);
        sys::write_all(
            sys::STDERR,
            b"incomplete cleanup: a second stop request arrived before cleanup finished\n",
        );
        // SAFETY: ends the process without cleanup.
        unsafe { sys::_exit(ms_rt_abi::EXIT_FAULT) }
    }
    // SAFETY: the shield counter and cancel flag are word-sized and only read here.
    unsafe {
        if *fault::SHIELD.ptr() == 0 {
            core::ptr::write_volatile(core::ptr::addr_of_mut!(fault::msrt_cancel_flag), sig as u8);
        }
        sys::alarm(CLEANUP_GRACE_SECS);
    }
    crate::task::kick();
}

extern "C" fn on_alarm(_: i32) {
    sys::write_all(
        sys::STDERR,
        b"incomplete cleanup: cleanup did not finish within 30s of the stop request\n",
    );
    // SAFETY: ends the process without cleanup.
    unsafe { sys::_exit(ms_rt_abi::EXIT_FAULT) }
}

fn install(sig: i32, handler: extern "C" fn(i32)) {
    install_raw(sig, handler as *const () as usize);
}

/// `SIG_IGN`: a write to a closed socket or pipe reports `EPIPE` instead of killing the process.
const SIG_IGN: usize = 1;
/// `SIGPIPE` is 13 on Linux and macOS.
const SIGPIPE: i32 = 13;

fn install_raw(sig: i32, handler: usize) {
    let act = sys::sigaction_t {
        handler,
        mask: [0; 16],
        flags: 0,
        restorer: 0,
    };
    // SAFETY: installs a handler that only touches atomics and async-signal-safe calls.
    unsafe { sys::sigaction(sig, &act, core::ptr::null_mut()) };
}

extern "C" fn thread_main(_: *mut c_void) -> *mut c_void {
    // SAFETY: single threaded globals set by `msrt_start` before the thread exists.
    unsafe {
        let f = (*MAIN_FN.ptr()).unwrap_or_else(|| fault::fatal(b"missing main"));
        let value = f();
        if core::ptr::read_volatile(core::ptr::addr_of!(fault::msrt_cancel_flag)) != 0 {
            fault::msrt_cancelled();
        }
        if !(0..=MAX_MAIN_EXIT).contains(&value) {
            fault::fault(b"main exit code must be between 0 and 125; return 0 for success or a small positive Int for failure (126 and above are reserved by shells)");
        }
        *MAIN_RESULT.ptr() = value;
    }
    core::ptr::null_mut()
}

/// Runtime entry called from the `main` the compiler emits. Returns the exit status.
///
/// # Safety
/// `tables` is null or a valid table; `argv` has `argc` valid C strings.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_start(
    main_fn: extern "C-unwind" fn() -> i64,
    tables: *const Tables,
    argc: i32,
    argv: *const *const u8,
) -> i32 {
    // SAFETY: one-time process setup before any other runtime use.
    unsafe {
        *TABLES.ptr() = tables;
        *ARGC.ptr() = argc;
        *ARGV.ptr() = argv;
        *MAIN_FN.ptr() = Some(main_fn);
        let mut now = Timespec { sec: 0, nsec: 0 };
        clock_gettime(CLOCK_MONOTONIC, &mut now);
        *START_NANOS.ptr() = now.sec * 1_000_000_000 + now.nsec;
        install(sys::SIGINT, on_stop);
        install(sys::SIGTERM, on_stop);
        install(sys::SIGALRM, on_alarm);
        install_raw(SIGPIPE, SIG_IGN);
        crate::profile::start();

        let stack = sys::mmap(
            core::ptr::null_mut(),
            STACK_SIZE,
            sys::PROT_READ | sys::PROT_WRITE,
            sys::MAP_PRIVATE | sys::MAP_ANONYMOUS | sys::MAP_NORESERVE,
            -1,
            0,
        );
        if stack as isize == -1 {
            fault::fatal(b"cannot allocate the main stack");
        }
        sys::mprotect(stack, GUARD, 0);
        *STACK_LO.ptr() = stack as usize + GUARD;
        *STACK_HI.ptr() = stack as usize + STACK_SIZE;
        let mut attr = core::mem::zeroed::<sys::pthread_attr_buf>();
        sys::pthread_attr_init(&mut attr);
        sys::pthread_attr_setstack(&mut attr, stack.add(GUARD), STACK_SIZE - GUARD);
        let mut tid = 0usize;
        if sys::pthread_create(&mut tid, &attr, thread_main, core::ptr::null_mut()) != 0 {
            fault::fatal(b"cannot start the main thread");
        }
        sys::pthread_join(tid, core::ptr::null_mut());
        crate::io::flush_stdout();
        crate::profile::finish();
        *MAIN_RESULT.ptr() as i32
    }
}

/// `List[String]` of the whole native argv, including `argv[0]` (`process.control().info().arguments`).
///
/// # Safety
/// `out` must be writable.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_argv(out: *mut VecVal) {
    // SAFETY: argv was recorded by `msrt_start` (or is empty).
    unsafe {
        let (argc, argv) = (*ARGC.ptr(), *ARGV.ptr());
        let n = if argc > 0 && !argv.is_null() {
            argc as usize
        } else {
            0
        };
        let p = if n == 0 {
            core::ptr::null_mut()
        } else {
            alloc::alloc(n * 8)
        } as *mut *mut ms_rt_abi::StrObj;
        for i in 0..n {
            let a = *argv.add(i);
            let mut len = 0;
            while *a.add(len) != 0 {
                len += 1;
            }
            *p.add(i) = string::from_bytes(core::slice::from_raw_parts(a, len));
        }
        *out = VecVal {
            ptr: p as *mut u8,
            len: n,
            cap: n,
        };
    }
}

/// `args()`: `List[String]` of the program arguments (argv[1..]).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_args(out: *mut VecVal) {
    // SAFETY: argv was recorded by `msrt_start` (or is empty).
    unsafe {
        let (argc, argv) = (*ARGC.ptr(), *ARGV.ptr());
        let n = if argc > 1 { argc as usize - 1 } else { 0 };
        let p = if n == 0 {
            core::ptr::null_mut()
        } else {
            alloc::alloc(n * 8)
        } as *mut *mut ms_rt_abi::StrObj;
        for i in 0..n {
            let mut a = *argv.add(i + 1);
            let mut len = 0;
            while *a.add(len) != 0 {
                len += 1;
            }
            a = *argv.add(i + 1);
            *p.add(i) = string::from_bytes(core::slice::from_raw_parts(a, len));
        }
        *out = VecVal {
            ptr: p as *mut u8,
            len: n,
            cap: n,
        };
    }
}
