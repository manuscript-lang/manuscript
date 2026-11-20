//! Process entry: tables, signals, the main thread with its large stack, exit status.
use crate::alloc;
#[cfg(unix)]
use crate::fault::STACK_LO;
use crate::fault::{self, PENDING_SIGNAL, TABLES};
use crate::global::Process;
use crate::string;
use crate::sys;
use core::ffi::c_void;
use core::sync::atomic::Ordering;
use ms_rt_abi::record::{FaultKind, Record};
use ms_rt_abi::{MAX_MAIN_EXIT, Tables, VecVal};

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
        incomplete_cleanup(
            b"incomplete cleanup: a second stop request arrived before cleanup finished",
        );

        // SAFETY: ends the process without cleanup.
        unsafe { sys::_exit(FaultKind::IncompleteCleanup.exit_status()) }
    }
    fault::raise_main_cancel(sig as u8);
    // SAFETY: runs the hooks `ms_on_stop` registered; they are async-signal-safe by contract.
    unsafe { ms_stop_hooks_run() };
    arm_grace_timer();
    crate::task::kick();
}

unsafe extern "C" {
    /// Runs the stop hooks of user extern shims (runtime/core/cabi.c).
    fn ms_stop_hooks_run();
}

/// Reports a stop that cleanup did not survive, on standard error and in the fault record.
fn incomplete_cleanup(message: &[u8]) {
    sys::write_all(sys::STDERR, message);
    sys::write_all(sys::STDERR, b"\n");
    fault::write_record(&Record::new(FaultKind::IncompleteCleanup, message));
}

fn grace_expired() -> ! {
    incomplete_cleanup(
        b"incomplete cleanup: cleanup did not finish within 30s of the stop request",
    );
    // SAFETY: ends the process without cleanup.
    unsafe { sys::_exit(FaultKind::IncompleteCleanup.exit_status()) }
}

/// The body of the main task: runs the program's `main` and records its result.
///
/// # Safety
/// Single threaded globals set by `msrt_start` before the thread exists; `done` is the token
/// `run_main` waits on.
unsafe extern "C-unwind" fn main_task(done: *mut u8) {
    // SAFETY: as documented.
    unsafe {
        let f = (*MAIN_FN.ptr()).unwrap_or_else(|| fault::fatal(b"missing main"));
        #[cfg(feature = "stats")]
        crate::alloc::reset_requested();
        let value = f();
        if fault::cancel_flag().load(Ordering::Relaxed) != 0 {
            // The main task's own boundary: nothing above it takes an exit, so it jumps.
            fault::msrt_cancelled();
        }
        if !(0..=MAX_MAIN_EXIT).contains(&value) {
            fault::fault(b"main exit code must be between 0 and 125; return 0 for success or a small positive Int for failure (126 and above are reserved by shells)");
        }
        *MAIN_RESULT.ptr() = value;
        // A process that frees at exit also unwinds the tasks still parked, so what they own is released.
        if msrt_exit_frees() != 0 {
            crate::task::unwind_others();
        }
    }
    // SAFETY: `done` is the live token `run_main` waits on.
    unsafe { crate::task::msrt_token_post(done as usize as u64, 1) };
}

/// Whether `main` frees the plain memory it still owns when it returns. The process exits next,
/// so a normal build skips it; the counting build keeps it so a leak shows, and
/// `MS_FREE_AT_EXIT` keeps it for valgrind.
#[unsafe(no_mangle)]
// ms: leaf domain=unwind
pub extern "C" fn msrt_exit_frees() -> u8 {
    u8::from(cfg!(feature = "stats") || std::env::var_os("MS_FREE_AT_EXIT").is_some())
}

/// Runs `main` as the isolate's main task on a stack of its own and returns when it ends.
///
/// # Safety
/// See [`main_task`].
unsafe fn run_main() {
    crate::alloc::claim_heap();
    crate::profile::attach_alloc_sampling();
    crate::isolate::set_main();
    fault::set_main_hdr();
    // SAFETY: this thread is the runtime thread; the root flow waits shielded so a stop request
    // reaches the main task, not this wait.
    unsafe { crate::task::run_main_task(main_task) };
    // Scheduler threads end with the program; a counting build then sees their heaps released too.
    crate::sched::shutdown();
    // The scheduler state lives in a thread-local with no destructor: release it here so a leak
    // checker (valgrind) sees nothing still owned by the exiting thread.
    crate::task::teardown();
    #[cfg(feature = "stats")]
    report_leaks();
}

/// Counting builds: reports what is still live after the scheduler state was released.
/// Runs on the isolate's own thread, whose allocator and task state it reads.
#[cfg(feature = "stats")]
fn report_leaks() {
    crate::watch::stop();
    fault::release_fault_state();
    crate::glue::pool::reap_at_exit();
    {
        if std::env::var_os("MS_PARK_COUNT").is_some() {
            eprintln!("ms-rt parks: {}", crate::task::sweep::parks());
        }
        {
            let (blocks, bytes) = crate::alloc::rust_heap_live();
            eprintln!("ms-rt rust heap at exit: blocks={blocks} bytes={bytes}");
        }
        eprintln!("ms-rt live blocks at exit: {}", crate::alloc::live_blocks());
        if crate::alloc::live_blocks() != 0 {
            // Which size classes still hold blocks: a flaky leak names its blocks by size.
            let by_size: Vec<String> = crate::alloc::live_by_size()
                .iter()
                .map(|(size, n)| match size {
                    0 => format!("large={n}"),
                    _ => format!("{size}B={n}"),
                })
                .collect();
            eprintln!("ms-rt live blocks by size: {}", by_size.join(" "));
        }
        let [allocs, bytes] = crate::alloc::requested();
        let k = crate::string::copy_counts();
        eprintln!(
            "ms-rt counts: allocs={allocs} alloc_bytes={bytes} list_copies={} list_copy_bytes={} string_clones={} string_clone_bytes={}",
            k[0], k[1], k[2], k[3]
        );
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

    /// How far below the stack's lowest usable address a fault still counts as overflow; a
    /// frame bigger than the guard can skip past it.
    const OVERFLOW_REACH: usize = 1 << 20;

    /// Runs on the faulting thread's alternate stack (see `ms_sys_fault_handler_install`): ends the
    /// process for a stack overflow and returns for any other fault.
    pub(super) extern "C" fn report_overflow(addr: usize) {
        // SAFETY: the global is only written by the runtime thread, which is the one that faulted.
        let lo = unsafe { *STACK_LO.ptr() };
        if lo != 0 && addr < lo + 4096 && addr + OVERFLOW_REACH >= lo {
            fault::fatal_kind(
                FaultKind::StackOverflow,
                b"stack overflow: recursion too deep or stack frames too large",
            );
        }
    }

    /// Reports a stack overflow by name instead of dying from a bare SIGSEGV. Must run on the
    /// thread that runs `main`, whose alternate stack the handler needs.
    pub fn install_overflow_handler() {
        let _ = sys::fault_handler_install(report_overflow);
    }

    pub fn install_stop_handlers() {
        install(sys::SIGINT, on_stop as *const () as usize);
        install(sys::SIGTERM, on_stop as *const () as usize);
        install(sys::SIGALRM, on_alarm as *const () as usize);
        // A write to a closed socket or pipe must surface as EPIPE, not kill the process
        // (Rust's own runtime does the same). Spawned children get the default back.
        install(sys::SIGPIPE, sys::SIG_IGN);
    }

    extern "C" fn thread_main(_: *mut c_void) {
        install_overflow_handler();
        // SAFETY: see `run_main`.
        unsafe { run_main() };
    }

    /// Runs `main` on a thread of its own and waits for it. The thread's stack only hosts the
    /// scheduler; `main` runs on a task stack.
    pub unsafe fn run_on_big_stack() {
        // SAFETY: one-time setup before the thread exists.
        unsafe {
            let thread = sys::thread_spawn(0, thread_main, core::ptr::null_mut());
            if thread == 0 {
                fault::fatal(b"cannot start the main thread");
            }
            sys::thread_join(thread);
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

    extern "C" fn grace_thread(_: *mut c_void) {
        sys::sleep_ms(CLEANUP_GRACE_SECS * 1000);
        grace_expired()
    }

    pub fn arm_grace_timer() {
        // SAFETY: the thread only sleeps and then ends the process.
        unsafe { sys::thread_spawn(0, grace_thread, core::ptr::null_mut()) };
    }

    pub fn install_stop_handlers() {
        // SAFETY: registers a handler that only touches atomics and async-safe calls.
        unsafe { sys::set_ctrl_handler(ctrl_handler) };
    }

    extern "C" fn thread_main(_: *mut c_void) {
        // SAFETY: see `run_main`.
        unsafe {
            crate::profile::attach_runtime_thread();
            run_main();
        }
    }

    /// Runs `main` on a thread of its own and waits for it.
    pub unsafe fn run_on_big_stack() {
        // SAFETY: one-time setup before the thread exists.
        unsafe {
            let thread = sys::thread_spawn(0, thread_main, core::ptr::null_mut());
            if thread == 0 {
                fault::fatal(b"cannot start the main thread");
            }
            sys::thread_join(thread);
        }
    }
}

use os::{arm_grace_timer, install_stop_handlers, run_on_big_stack};

/// Gives the calling thread, a worker isolate's, the per-thread fault handling `main` has.
pub fn install_thread_fault_handler() {
    #[cfg(unix)]
    os::install_overflow_handler();
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
        let status = *MAIN_RESULT.ptr() as i32;
        let lost = crate::io::stdout_error();
        if lost != 0 && status == 0 {
            // Output the buffer could not deliver (a full disk, a closed descriptor): say so
            // instead of exiting as if it had been written.
            let mut text = std::io::Error::from_raw_os_error(lost).to_string();
            if let Some(i) = text.rfind(" (os error ") {
                text.truncate(i);
            }
            sys::write_all(
                sys::STDERR,
                format!("error: write to standard output: {text}\n").as_bytes(),
            );
            return 1;
        }
        status
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
