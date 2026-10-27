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
use ms_rt_abi::{MAX_MAIN_EXIT, Tables, VecVal};

/// Grace period after the first stop request before cleanup is abandoned.
const CLEANUP_GRACE_SECS: u32 = 30;

static ARGC: Process<i32> = Process::new(0);
static ARGV: Process<*const *const u8> = Process::new(core::ptr::null());
/// Leading program arguments that `msrt_args` hides: the test runner's selector.
static ARG_SKIP: Process<i32> = Process::new(0);
static MAIN_FN: Process<Option<extern "C-unwind" fn() -> i64>> = Process::new(None);
static MAIN_RESULT: Process<i64> = Process::new(0);

/// The environment variable that starts a child at a process entry (`@std/processes.ms`)
/// instead of `main`: see [`entry_value`].
pub const ENTRY_ENV: &str = "MS_ENTRY";
/// The child's entry, read from [`ENTRY_ENV`] at start: the code and drop words of the runner
/// closure, then of the entry closure it captures, each as an offset from `msrt_start`.
static ENTRY: Process<Option<[i64; 4]>> = Process::new(None);

fn image_base() -> i64 {
    msrt_start as *const () as usize as i64
}

/// The value of [`ENTRY_ENV`] that starts a child of the same executable at `runner`: a
/// closure taking nothing whose one capture is a closure without captures (a named function),
/// as `ProcessGroup.spawn` makes. Both run again in the child from their code and drop words;
/// the parent and child are one image, so the words keep their offsets from `msrt_start`.
///
/// # Safety
/// `runner` is a live closure of that shape.
pub unsafe fn entry_value(runner: *mut ms_rt_abi::Closure) -> stdalloc::string::String {
    // SAFETY: the caller guarantees the shape: the capture is the entry closure pointer.
    unsafe {
        let entry =
            *(runner as *const *mut ms_rt_abi::Closure).byte_add(ms_rt_abi::CLOSURE_CAPTURE_OFFSET);
        let base = image_base();
        let words = [
            (*runner).code as i64,
            (*runner).hdr.drop.map_or(0, |d| d as usize as i64),
            (*entry).code as i64,
            (*entry).hdr.drop.map_or(0, |d| d as usize as i64),
        ];
        let mut out = stdalloc::string::String::new();
        for (i, w) in words.iter().enumerate() {
            if i > 0 {
                out.push(':');
            }
            out.push_str(&stdalloc::format!("{}", w - base));
        }
        out
    }
}

fn parse_entry(value: &[u8]) -> Option<[i64; 4]> {
    let text = core::str::from_utf8(value).ok()?;
    let mut words = [0i64; 4];
    let mut parts = text.split(':');
    for w in &mut words {
        *w = parts.next()?.parse().ok()?;
    }
    parts.next().is_none().then_some(words)
}

/// Runs the child's entry: rebuilds the entry closure and the runner that captures it, then
/// calls the runner, which serves the entry over the IPC pipe.
///
/// # Safety
/// `words` came from [`entry_value`] in a process of this same executable.
unsafe fn run_entry(words: [i64; 4]) {
    use ms_rt_abi::{CLOSURE_CAPTURE_OFFSET, Closure, Obj};
    let base = image_base();
    let word = |w: i64| (w + base) as usize;
    // SAFETY: as documented; the drop words are drop glue of exactly these closures.
    unsafe {
        let closure = |code: i64, drop: i64, size: usize| {
            let obj = alloc::alloc(size) as *mut Closure;
            (*obj).hdr = Obj {
                rc: 1,
                drop: (drop != 0)
                    .then(|| core::mem::transmute::<usize, ms_rt_abi::DropFn>(word(drop))),
            };
            (*obj).code = word(code) as *const u8;
            obj
        };
        let entry = closure(words[2], words[3], CLOSURE_CAPTURE_OFFSET);
        let runner = closure(words[0], words[1], CLOSURE_CAPTURE_OFFSET + 8);
        *(runner as *mut *mut Closure).byte_add(CLOSURE_CAPTURE_OFFSET) = entry;
        let code: unsafe extern "C-unwind" fn(*mut Closure) = core::mem::transmute((*runner).code);
        code(runner);
        crate::obj::msrt_release(runner.cast());
    }
}
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
    fault::raise_main_cancel(sig as u8);
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

/// The body of the main task: runs the program's `main` and records its result.
///
/// # Safety
/// Single threaded globals set by `msrt_start` before the thread exists; `done` is the token
/// `run_main` waits on.
unsafe extern "C-unwind" fn main_task(done: *mut u8) {
    // SAFETY: as documented.
    unsafe {
        let f = (*MAIN_FN.ptr()).unwrap_or_else(|| fault::fatal(b"missing main"));
        let value = match *ENTRY.ptr() {
            Some(words) => {
                run_entry(words);
                0
            }
            None => f(),
        };
        if fault::cancel_flag().load(Ordering::Relaxed) != 0 {
            fault::msrt_cancelled();
        }
        if !(0..=MAX_MAIN_EXIT).contains(&value) {
            fault::fault(b"main exit code must be between 0 and 125; return 0 for success or a small positive Int for failure (126 and above are reserved by shells)");
        }
        *MAIN_RESULT.ptr() = value;
    }
    // SAFETY: `done` is the live token `run_main` waits on.
    unsafe { crate::task::msrt_token_post(done as usize as u64, 1) };
}

/// Runs `main` as the isolate's main task on a stack of its own and returns when it ends.
///
/// # Safety
/// See [`main_task`].
unsafe fn run_main() {
    crate::alloc::claim_arena(true);
    crate::isolate::set_main();
    fault::set_main_hdr();
    // SAFETY: this thread is the runtime thread; the root flow waits shielded so a stop request
    // reaches the main task, not this wait.
    unsafe { crate::task::run_main_task(main_task) };
    #[cfg(feature = "stats")]
    report_leaks();
}

/// Counting builds: sweeps the main isolate's scheduler state, then reports what is still live.
/// Runs on the isolate's own thread, whose allocator and task state it reads.
#[cfg(feature = "stats")]
fn report_leaks() {
    crate::task::teardown();
    {
        eprintln!("ms-rt live blocks at exit: {}", crate::alloc::live_blocks());
        // SAFETY: the counters belong to this isolate.
        let c = unsafe { *crate::string::STR_COUNTS.ptr() };
        if c.iter().any(|n| *n != 0) {
            eprintln!(
                "ms-rt string drops: {} static, {} owned; copies: {} static, {} owned",
                c[0], c[1], c[2], c[3]
            );
        }
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
            #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
            if std::env::var_os("MS_DIAG_FRAMES").is_some() {
                let mctx = (_ctx.add(48) as *const usize).read_unaligned();
                let reg = |i: usize| ((mctx + 16 + i * 8) as *const usize).read_unaligned();
                let (fp, lr, sp, pc) = (reg(29), reg(30), reg(31), reg(32));
                let mut out = std::vec::Vec::new();
                fault::diag_describe(&mut out, &[pc.wrapping_add(1), lr], fp);
                let text = std::format!(
                    "SEGV addr={addr:#x} pc={pc:#x} lr={lr:#x} sp={sp:#x} fp={fp:#x} lo={lo:#x}{}\n",
                    std::string::String::from_utf8_lossy(&out)
                );
                sys::write(2, text.as_ptr().cast(), text.len());
            }
            // Not ours: restore the default action and return so the access faults again.
            let dfl = sys::sigaction_t::new(0, 0);
            sys::sigaction(sig, &dfl, core::ptr::null_mut());
        }
    }

    /// Reports a stack overflow by name instead of dying from a bare SIGSEGV. Must run on the
    /// thread that runs `main`, whose alternate stack the handler needs.
    pub fn install_overflow_handler() {
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
        install_overflow_handler();
        // SAFETY: see `run_main`.
        unsafe { run_main() };
        core::ptr::null_mut()
    }

    /// Runs `main` on a thread of its own and waits for it. The thread's stack only hosts the
    /// scheduler; `main` runs on a task stack.
    pub unsafe fn run_on_big_stack() {
        // SAFETY: one-time setup before the thread exists.
        unsafe {
            let mut attr = core::mem::zeroed::<sys::pthread_attr_buf>();
            sys::pthread_attr_init(&mut attr);
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
        // SAFETY: see `run_main`.
        unsafe {
            crate::profile::attach_runtime_thread();
            run_main();
        }
        0
    }

    /// Runs `main` on a thread of its own and waits for it.
    pub unsafe fn run_on_big_stack() {
        // SAFETY: one-time setup before the thread exists.
        unsafe {
            let thread = sys::thread_spawn(0, thread_main);
            if thread.is_null() {
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
        *ENTRY.ptr() = sys::env_var(b"MS_ENTRY\0").and_then(parse_entry);
        *START_NANOS.ptr() = sys::monotonic_ns();
        install_stop_handlers();
        crate::profile::start();
        run_on_big_stack();
        crate::io::flush_stdout();
        crate::process::run_exit_hooks();
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
