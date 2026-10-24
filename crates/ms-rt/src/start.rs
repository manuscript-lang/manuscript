//! Process entry: tables, signals, the main thread with its large stack, exit status.
use crate::alloc;
use crate::fault::{self, PENDING_SIGNAL, STACK_LO, TABLES};
use crate::global::Process;
use crate::string;
use crate::sys;
use core::ffi::c_void;
use core::sync::atomic::Ordering;
use ms_rt_abi::{MAX_MAIN_EXIT, Tables, VecVal};

/// Stack of the thread that runs `main` (deep recursion has to fit).
const STACK_SIZE: usize = 1 << 30;
#[cfg(unix)]
const GUARD: usize = 1 << 16;
/// Grace period after the first stop request before cleanup is abandoned.
const CLEANUP_GRACE_SECS: u32 = 30;

static ARGC: Process<i32> = Process::new(0);
static ARGV: Process<*const *const u8> = Process::new(core::ptr::null());
/// Leading program arguments that `msrt_args` hides: the test runner's selector.
static ARG_SKIP: Process<i32> = Process::new(0);
static MAIN_FN: Process<Option<extern "C-unwind" fn() -> i64>> = Process::new(None);
static MAIN_RESULT: Process<i64> = Process::new(0);
/// `CLOCK_MONOTONIC` nanoseconds when the runtime started; 0 before `msrt_start`.
static START_NANOS: Process<i64> = Process::new(0);

/// Monotonic nanoseconds since the runtime started (the origin of `process.uptime()`); 0 when not started.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_start_nanos() -> i64 {
    // SAFETY: written once by `msrt_start` before any other thread exists.
    unsafe { *START_NANOS.ptr() }
}

/// First stop request: ask the running code to unwind. A second one before cleanup finished
/// ends the process.
fn stop_requested(sig: i32) {
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
            fault::msrt_cancel_flag.store(sig as u8, Ordering::Relaxed);
        }
    }
    arm_grace_timer();
    crate::task::kick();
}

fn grace_expired() -> ! {
    sys::write_all(
        sys::STDERR,
        b"incomplete cleanup: cleanup did not finish within 30s of the stop request\n",
    );
    // SAFETY: ends the process without cleanup.
    unsafe { sys::_exit(ms_rt_abi::EXIT_FAULT) }
}

/// Runs the program's `main` and records its result; shared by both platforms' thread entries.
///
/// # Safety
/// Single threaded globals set by `msrt_start` before the thread exists.
unsafe fn run_main() {
    // SAFETY: as documented.
    unsafe {
        let f = (*MAIN_FN.ptr()).unwrap_or_else(|| fault::fatal(b"missing main"));
        let value = f();
        if fault::msrt_cancel_flag.load(Ordering::Relaxed) != 0 {
            fault::msrt_cancelled();
        }
        if !(0..=MAX_MAIN_EXIT).contains(&value) {
            fault::fault(b"main exit code must be between 0 and 125; return 0 for success or a small positive Int for failure (126 and above are reserved by shells)");
        }
        *MAIN_RESULT.ptr() = value;
    }
}

#[cfg(unix)]
mod os {
    use super::*;

    extern "C" fn on_stop(sig: i32) {
        stop_requested(sig);
    }

    extern "C" fn on_alarm(_: i32) {
        grace_expired()
    }

    fn install(sig: i32, handler: usize) {
        let act = sys::sigaction_t::new(handler, 0);
        // SAFETY: installs a handler that only touches atomics and async-signal-safe calls.
        unsafe { sys::sigaction(sig, &act, core::ptr::null_mut()) };
    }

    pub fn arm_grace_timer() {
        // SAFETY: plain syscall.
        unsafe { sys::alarm(CLEANUP_GRACE_SECS) };
    }

    /// Size of the alternate stack the overflow handler runs on.
    const ALT_STACK: usize = 64 << 10;
    /// How far below the stack's lowest usable address a fault still counts as overflow; a
    /// frame bigger than the guard can skip past it.
    const OVERFLOW_REACH: usize = 1 << 20;

    extern "C" fn on_fault(sig: i32, info: *const u8, _ctx: *const u8) {
        // SAFETY: the kernel passes a valid `siginfo_t`; the globals are only written by the
        // runtime thread, which is the one that faulted.
        unsafe {
            let addr = info
                .add(sys::SI_ADDR_OFFSET)
                .cast::<usize>()
                .read_unaligned();
            let lo = *STACK_LO.ptr();
            if lo != 0 && addr < lo + 4096 && addr + OVERFLOW_REACH >= lo {
                fault::fatal(b"stack overflow: recursion too deep or stack frames too large");
            }
            // Not ours: restore the default action and return so the access faults again.
            let dfl = sys::sigaction_t::new(0, 0);
            sys::sigaction(sig, &dfl, core::ptr::null_mut());
        }
    }

    /// Reports a stack overflow by name instead of dying from a bare SIGSEGV. Must run on the
    /// thread that runs `main`, whose alternate stack the handler needs.
    fn install_overflow_handler() {
        // SAFETY: the alternate stack is never freed; the handler only makes async-signal-safe
        // calls before exiting.
        unsafe {
            let stack = sys::map_anon(ALT_STACK);
            if stack.is_null() {
                return;
            }
            let alt = sys::stack_t {
                ss_sp: stack.cast(),
                ss_flags: 0,
                ss_size: ALT_STACK,
            };
            if sys::sigaltstack(&alt, core::ptr::null_mut()) != 0 {
                return;
            }
            let handler: extern "C" fn(i32, *const u8, *const u8) = on_fault;
            let act = sys::sigaction_t::new(
                handler as *const () as usize,
                sys::SA_SIGINFO | sys::SA_ONSTACK,
            );
            sys::sigaction(sys::SIGSEGV, &act, core::ptr::null_mut());
            sys::sigaction(sys::SIGBUS, &act, core::ptr::null_mut());
        }
    }

    pub fn install_stop_handlers() {
        install(sys::SIGINT, on_stop as *const () as usize);
        install(sys::SIGTERM, on_stop as *const () as usize);
        install(sys::SIGALRM, on_alarm as *const () as usize);
        // A write to a closed socket or pipe must surface as EPIPE, not kill the process
        // (Rust's own runtime does the same). Spawned children get the default back.
        install(sys::SIGPIPE, sys::SIG_IGN);
    }

    extern "C" fn thread_main(_: *mut c_void) -> *mut c_void {
        #[cfg(target_os = "linux")]
        crate::alloc::claim_arena();
        install_overflow_handler();
        // SAFETY: see `run_main`.
        unsafe { run_main() };
        core::ptr::null_mut()
    }

    /// Runs `main` on a thread with a large stack and waits for it.
    pub unsafe fn run_on_big_stack() {
        // SAFETY: one-time setup; the mapping outlives the thread.
        unsafe {
            let stack = sys::map_anon(STACK_SIZE);
            if stack.is_null() {
                fault::fatal(b"cannot allocate the main stack");
            }
            sys::guard(stack, GUARD);
            fault::set_stack_bounds(stack as usize + GUARD, stack as usize + STACK_SIZE);
            let mut attr = core::mem::zeroed::<sys::pthread_attr_buf>();
            sys::pthread_attr_init(&mut attr);
            sys::pthread_attr_setstack(&mut attr, stack.add(GUARD).cast(), STACK_SIZE - GUARD);
            let mut tid = 0usize;
            if sys::pthread_create(&mut tid, &attr, thread_main, core::ptr::null_mut()) != 0 {
                fault::fatal(b"cannot start the main thread");
            }
            sys::pthread_join(tid, core::ptr::null_mut());
        }
    }
}

#[cfg(windows)]
mod os {
    use super::*;

    /// Console control events: Ctrl-C and Ctrl-Break stop like SIGINT; close, logoff and
    /// shutdown like SIGTERM. Windows runs the handler on a thread of its own.
    unsafe extern "system" fn ctrl_handler(kind: u32) -> i32 {
        let sig = match kind {
            0 | 1 => sys::SIGINT,
            2 | 5 | 6 => sys::SIGTERM,
            _ => return 0,
        };
        stop_requested(sig);
        1
    }

    unsafe extern "system" fn grace_thread(_: *mut c_void) -> u32 {
        sys::sleep_ms(CLEANUP_GRACE_SECS * 1000);
        grace_expired()
    }

    pub fn arm_grace_timer() {
        // SAFETY: the thread only sleeps and then ends the process.
        unsafe { sys::thread_spawn(0, grace_thread) };
    }

    pub fn install_stop_handlers() {
        // SAFETY: registers a handler that only touches atomics and async-safe calls.
        unsafe { sys::set_ctrl_handler(ctrl_handler) };
    }

    unsafe extern "system" fn thread_main(_: *mut c_void) -> u32 {
        // SAFETY: see `run_main`; the bounds are written before any other code reads them.
        unsafe {
            let (lo, hi) = sys::stack_limits();
            fault::set_stack_bounds(lo, hi);
            crate::profile::attach_runtime_thread();
            run_main();
        }
        0
    }

    /// Runs `main` on a thread whose stack reserves `STACK_SIZE` bytes (committed as it grows)
    /// and waits for it.
    pub unsafe fn run_on_big_stack() {
        // SAFETY: one-time setup before the thread exists.
        unsafe {
            let thread = sys::thread_spawn(STACK_SIZE, thread_main);
            if thread.is_null() {
                fault::fatal(b"cannot start the main thread");
            }
            sys::thread_join(thread);
        }
    }
}

use os::{arm_grace_timer, install_stop_handlers, run_on_big_stack};

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
        *TABLES.ptr() = fault::address_ordered_tables(tables);
        *ARGC.ptr() = argc;
        *ARGV.ptr() = argv;
        *MAIN_FN.ptr() = Some(main_fn);
        *START_NANOS.ptr() = sys::monotonic_ns();
        install_stop_handlers();
        crate::profile::start();
        run_on_big_stack();
        crate::io::flush_stdout();
        crate::process::run_exit_hooks();
        crate::profile::finish();
        #[cfg(feature = "stats")]
        crate::task::reset_for_tests();
        #[cfg(feature = "stats")]
        {
            eprintln!("ms-rt live blocks at exit: {}", crate::alloc::live_blocks());
            let c = *crate::string::STR_COUNTS.ptr();
            if c.iter().any(|n| *n != 0) {
                eprintln!(
                    "ms-rt string drops: {} static, {} owned; copies: {} static, {} owned",
                    c[0], c[1], c[2], c[3]
                );
            }
        }
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
            alloc::alloc(n * core::mem::size_of::<ms_rt_abi::StrVal>())
        } as *mut ms_rt_abi::StrVal;
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

/// The test runner calls this once it has read the test selector, so `args()` is the
/// program's own arguments.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_args_consume() {
    // SAFETY: the runner calls this once, before any task runs.
    unsafe { *ARG_SKIP.ptr() = 1 };
}

/// `args()`: `List[String]` of the program arguments (argv[1..], less the test selector).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_args(out: *mut VecVal) {
    // SAFETY: argv was recorded by `msrt_start` (or is empty).
    unsafe {
        let (argc, argv) = (*ARGC.ptr(), *ARGV.ptr());
        let first = 1 + *ARG_SKIP.ptr();
        let n = if argc > first {
            (argc - first) as usize
        } else {
            0
        };
        let p = if n == 0 {
            core::ptr::null_mut()
        } else {
            alloc::alloc(n * core::mem::size_of::<ms_rt_abi::StrVal>())
        } as *mut ms_rt_abi::StrVal;
        for i in 0..n {
            let mut a = *argv.add(i + first as usize);
            let mut len = 0;
            while *a.add(len) != 0 {
                len += 1;
            }
            a = *argv.add(i + first as usize);
            *p.add(i) = string::from_bytes(core::slice::from_raw_parts(a, len));
        }
        *out = VecVal {
            ptr: p as *mut u8,
            len: n,
            cap: n,
        };
    }
}
