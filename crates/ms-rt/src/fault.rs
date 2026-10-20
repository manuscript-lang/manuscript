//! Faults, the cleanup stack, call depth, cancellation and process exit.
use crate::global::Global;
#[allow(unused_imports)]
use crate::sys;
use core::fmt;
use core::sync::atomic::{AtomicU8, Ordering};
use ms_rt_abi::{FuncEntry, LineEntry, MAX_FAULT_FRAMES, ScopeEntry, TABLES_WITH_SCOPES, Tables};
use std::io::Write as _;

/// Current depth of recursive calls (generated code updates it inline).
#[unsafe(no_mangle)]
pub static mut msrt_call_depth: i64 = 0;
/// Non-zero (the signal number) once a stop was requested and not shielded.
#[unsafe(no_mangle)]
pub static msrt_cancel_flag: AtomicU8 = AtomicU8::new(0);

pub static TABLES: Global<*const Tables> = Global::new(core::ptr::null());
/// Lowest and highest valid stack addresses for frame walking (0 = unknown).
pub static STACK_LO: Global<usize> = Global::new(0);
pub static STACK_HI: Global<usize> = Global::new(0);

type CleanupFn = unsafe extern "C-unwind" fn(*mut u8);
static CLEANUPS: Global<Vec<(usize, usize)>> = Global::new(Vec::new());
pub(crate) static SHIELD: Global<u32> = Global::new(0);
pub static PENDING_SIGNAL: AtomicU8 = AtomicU8::new(0);
static FAULTING: Global<bool> = Global::new(false);
static SECONDARY: Global<Vec<Vec<u8>>> = Global::new(Vec::new());

/// Stop request aimed at the running task (see `task`); 0 when none.
static TASK_CANCEL: Global<u8> = Global::new(0);

/// Value of `msrt_cancel_flag` when cancellation is not shielded.
pub(crate) fn unshielded_cancel_flag() -> u8 {
    // SAFETY: single threaded access.
    let task = unsafe { *TASK_CANCEL.ptr() };
    PENDING_SIGNAL.load(Ordering::Relaxed).max(task)
}

/// Records a stop request aimed at the running task.
pub(crate) fn set_live_task_cancel(v: u8) {
    // SAFETY: single threaded access.
    unsafe {
        *TASK_CANCEL.ptr() = v;
        if *SHIELD.ptr() == 0 {
            msrt_cancel_flag.store(unshielded_cancel_flag(), Ordering::Relaxed);
        }
    }
}

/// The per-task slice of runtime state; `task` swaps it on every context switch.
pub(crate) struct Ctx {
    cleanups: Vec<(usize, usize)>,
    guards: Vec<GuardFrame>,
    secondary: Vec<Vec<u8>>,
    eq_pairs: Vec<(usize, usize)>,
    primary: Option<Vec<u8>>,
    shield: u32,
    faulting: bool,
    depth: i64,
    cancel: u8,
    stack_lo: usize,
    stack_hi: usize,
}

impl Ctx {
    /// State of a task that has not run yet, with the given stack bounds.
    pub(crate) const fn new(stack_lo: usize, stack_hi: usize) -> Ctx {
        Ctx {
            cleanups: Vec::new(),
            guards: Vec::new(),
            secondary: Vec::new(),
            eq_pairs: Vec::new(),
            primary: None,
            shield: 0,
            faulting: false,
            depth: 0,
            cancel: 0,
            stack_lo,
            stack_hi,
        }
    }

    pub(crate) fn set_cancel(&mut self, v: u8) {
        self.cancel = v;
    }

    /// Whether the task is inside a cleanup action that shields it from cancellation.
    pub(crate) fn shielded(&self) -> bool {
        self.shield > 0
    }
}

/// Whether the running task is inside a shielded cleanup action.
pub(crate) fn live_shielded() -> bool {
    // SAFETY: single threaded access.
    unsafe { *SHIELD.ptr() > 0 }
}

/// Exchanges `c` with the live per-task state.
///
/// # Safety
/// Single threaded; callers pair two swaps per context switch.
pub(crate) unsafe fn swap_ctx(c: &mut Ctx) {
    // SAFETY: single threaded access to the runtime globals.
    unsafe {
        core::ptr::swap(CLEANUPS.ptr(), &mut c.cleanups);
        core::ptr::swap(GUARDS.ptr(), &mut c.guards);
        core::ptr::swap(SECONDARY.ptr(), &mut c.secondary);
        crate::desc::swap_eq_pairs(&mut c.eq_pairs);
        core::ptr::swap(PRIMARY.ptr(), &mut c.primary);
        core::ptr::swap(SHIELD.ptr(), &mut c.shield);
        core::ptr::swap(FAULTING.ptr(), &mut c.faulting);
        core::ptr::swap(core::ptr::addr_of_mut!(msrt_call_depth), &mut c.depth);
        core::ptr::swap(TASK_CANCEL.ptr(), &mut c.cancel);
        core::ptr::swap(STACK_LO.ptr(), &mut c.stack_lo);
        core::ptr::swap(STACK_HI.ptr(), &mut c.stack_hi);
        msrt_cancel_flag.store(
            if *SHIELD.ptr() == 0 {
                unshielded_cancel_flag()
            } else {
                0
            },
            Ordering::Relaxed,
        );
    }
}

/// Fault reported while no frames or cleanup are meaningful (allocator exhaustion).
#[cold]
pub fn fatal(msg: &[u8]) -> ! {
    #[cfg(test)]
    {
        std::panic::panic_any(crate::testutil::FaultPayload(
            std::string::String::from_utf8_lossy(msg).into_owned(),
        ));
    }
    #[cfg(not(test))]
    {
        crate::io::flush_stdout();
        sys::write_all(sys::STDERR, msg);
        sys::write_all(sys::STDERR, b"\n");
        // SAFETY: terminating the process.
        unsafe { sys::_exit(ms_rt_abi::EXIT_FAULT) }
    }
}

#[inline(always)]
fn frame_pointer() -> usize {
    let fp: usize;
    // SAFETY: reads a register, no memory access.
    unsafe {
        #[cfg(miri)]
        {
            fp = 0;
        }
        #[cfg(all(not(miri), target_arch = "x86_64"))]
        core::arch::asm!("mov {}, rbp", out(reg) fp, options(nomem, nostack, preserves_flags));
        #[cfg(all(not(miri), target_arch = "aarch64"))]
        core::arch::asm!("mov {}, x29", out(reg) fp, options(nomem, nostack, preserves_flags));
        #[cfg(not(any(miri, target_arch = "x86_64", target_arch = "aarch64")))]
        {
            fp = 0;
        }
    }
    fp
}

/// Walks a frame-pointer chain starting at `fp`, calling `f(return_address)`
/// until it returns false or the chain ends.
///
/// # Safety
/// `fp` must be null or point into a live frame-pointer chain of this thread.
pub unsafe fn walk_frames(mut fp: usize, mut f: impl FnMut(usize) -> bool) {
    // SAFETY: reading the global stack bounds, set once at start.
    let (lo, hi) = unsafe { (*STACK_LO.ptr(), *STACK_HI.ptr()) };
    let mut steps = 0usize;
    while fp != 0 && fp.is_multiple_of(8) && steps < 1_000_000 {
        if hi != 0 && (fp < lo || fp.checked_add(16).is_none_or(|end| end > hi)) {
            break;
        }
        // SAFETY: `fp` is inside the stack bounds (or bounds are unknown and the
        // caller promised a valid chain).
        let (next, ret) = unsafe { (*(fp as *const usize), *((fp + 8) as *const usize)) };
        if ret == 0 || !f(ret) {
            break;
        }
        if next <= fp {
            break;
        }
        fp = next;
        steps += 1;
    }
}

fn cstr(t: &Tables, off: u32) -> &'static [u8] {
    if off == u32::MAX || off as usize >= t.strings_len {
        return b"?";
    }
    // SAFETY: the compiler emits NUL-terminated strings inside the blob.
    unsafe {
        let p = t.strings.add(off as usize);
        let max = t.strings_len - off as usize;
        let mut n = 0;
        while n < max && *p.add(n) != 0 {
            n += 1;
        }
        core::slice::from_raw_parts(p, n)
    }
}

/// Finds the function containing `pc` (a return address).
pub fn find_func(t: &Tables, pc: usize) -> Option<&'static FuncEntry> {
    if t.funcs.is_null() || t.func_count == 0 {
        return None;
    }
    // SAFETY: the table is `func_count` sorted entries of read-only data.
    let funcs = unsafe { core::slice::from_raw_parts(t.funcs, t.func_count) };
    let probe = pc.wrapping_sub(1);
    let idx = funcs.partition_point(|e| e.addr <= probe);
    if idx == 0 {
        return None;
    }
    let e = &funcs[idx - 1];
    if probe < e.addr + e.size as usize {
        Some(e)
    } else {
        None
    }
}

/// Source line of a return address inside `func`, with the inlining scope of that line.
pub fn find_line(t: &Tables, func: &FuncEntry, pc: usize) -> (u32, u32, u32) {
    if !t.lines.is_null() && t.line_count > 0 {
        // SAFETY: sorted `line_count` read-only entries.
        let lines = unsafe { core::slice::from_raw_parts(t.lines, t.line_count) };
        // `pc` is a return address; the call instruction lies in the range ending just before it.
        let probe = pc.wrapping_sub(1);
        let idx = lines.partition_point(|e: &LineEntry| e.pc <= probe);
        if idx > 0 {
            let e = &lines[idx - 1];
            if e.pc >= func.addr {
                let file = if e.file_off == u32::MAX {
                    func.file_off
                } else {
                    e.file_off
                };
                let scope = if t.abi_version >= TABLES_WITH_SCOPES && !t.line_scopes.is_null() {
                    // SAFETY: `line_scopes` parallels `lines`.
                    unsafe { *t.line_scopes.add(idx - 1) }
                } else {
                    0
                };
                return (e.line, file, scope);
            }
        }
    }
    (func.line, func.file_off, 0)
}

/// The inlined-callee scope `id` (1-based), if the table has it.
fn scope_entry(t: &Tables, id: u32) -> Option<ScopeEntry> {
    if t.abi_version < TABLES_WITH_SCOPES
        || t.scopes.is_null()
        || id == 0
        || id as usize > t.scope_count
    {
        return None;
    }
    // SAFETY: `scope_count` read-only entries; `id` is in range.
    Some(unsafe { *t.scopes.add(id as usize - 1) })
}

/// Windows native frames do not use the generated code's frame layout. Recover
/// the first source frame with native unwind metadata, then follow only the
/// contiguous generated caller chain. Stop at native/glue boundaries rather
/// than reconstructing a partial native register context.
#[cfg(windows)]
unsafe fn walk_fault_frames(_fp: usize, t: &Tables, mut f: impl FnMut(usize) -> bool) {
    let Some((mut pc, mut fp)) = sys::source_frame(|pc| find_func(t, pc).is_some()) else {
        return;
    };
    let (lo, hi) = sys::stack_limits();
    for _ in 0..256 {
        if find_func(t, pc).is_none() || !f(pc) {
            break;
        }
        let Some(end) = fp.checked_add(16) else { break };
        if !fp.is_multiple_of(8) || fp < lo || end > hi {
            break;
        }
        // SAFETY: the first frame came from the native CONTEXT; subsequent
        // frames belong to registered generated callers and stay in this stack.
        let (next, ret) = unsafe { (*(fp as *const usize), *((fp + 8) as *const usize)) };
        if next <= fp {
            break;
        }
        (pc, fp) = (ret, next);
    }
}

#[cfg(not(windows))]
unsafe fn walk_fault_frames(fp: usize, _t: &Tables, f: impl FnMut(usize) -> bool) {
    // SAFETY: forwarded live frame-pointer chain.
    unsafe { walk_frames(fp, f) }
}

/// Notes frames omitted because they repeat the line above, then resets the count.
fn push_repeats(out: &mut Vec<u8>, repeated: &mut usize) {
    if *repeated > 0 {
        out.extend_from_slice(b"\n  ... previous frame repeated ");
        crate::num::push_i64(out, *repeated as i64);
        out.extend_from_slice(b" more times");
        *repeated = 0;
    }
}

/// Appends `file:line in name` lines for the source frames found from `fp`.
fn describe_frames(out: &mut Vec<u8>, fp: usize) {
    // SAFETY: tables pointer is set once at start.
    let t = unsafe { *TABLES.ptr() };
    if t.is_null() {
        return;
    }
    // SAFETY: non-null table installed by `msrt_start`.
    let t = unsafe { &*t };
    let mut shown = 0;
    let mut truncated = false;
    // Identical consecutive frames (deep recursion) collapse into one line and a count.
    let mut last = (u32::MAX, 0u32, u32::MAX);
    let mut repeated = 0usize;
    // SAFETY: `fp` comes from `frame_pointer()` of the faulting thread.
    unsafe {
        walk_fault_frames(fp, t, |ret| {
            let Some(func) = find_func(t, ret) else {
                return true;
            };
            let (mut line, mut file, mut scope) = find_line(t, func, ret);
            // Compiler-generated glue (function-value thunks) has no source position.
            if line == 0 {
                return true;
            }
            // Frames of inlined callees, innermost first, then the physical function.
            let mut name = func.name_off;
            loop {
                let next = scope_entry(t, scope);
                if let Some(sc) = &next {
                    name = sc.name_off;
                    if sc.file_off != u32::MAX {
                        file = sc.file_off;
                    }
                }
                if (file, line, name) == last {
                    repeated += 1;
                } else {
                    if shown == MAX_FAULT_FRAMES {
                        truncated = true;
                        return false;
                    }
                    push_repeats(out, &mut repeated);
                    out.extend_from_slice(b"\n  at ");
                    out.extend_from_slice(cstr(t, file));
                    out.push(b':');
                    crate::num::push_i64(out, line as i64);
                    out.extend_from_slice(b" in ");
                    out.extend_from_slice(cstr(t, name));
                    last = (file, line, name);
                    shown += 1;
                }
                let Some(sc) = next else { break };
                line = sc.call_line;
                scope = sc.parent;
                // A wrapper without a position of its own has no frame once its callee is shown.
                if line == 0 && scope == 0 {
                    break;
                }
                name = func.name_off;
                file = func.file_off;
            }
            true
        });
    }
    push_repeats(out, &mut repeated);
    if truncated {
        out.extend_from_slice(b"\n  ... outer frames omitted");
    }
}

/// Runs `f(arg)` with cancellation shielded.
fn run_shielded(f: CleanupFn, arg: *mut u8) {
    // SAFETY: single threaded access to the shield counter; the action was
    // registered by generated code with a valid function pointer.
    unsafe {
        *SHIELD.ptr() += 1;
        msrt_cancel_flag.store(0, Ordering::Relaxed);
        f(arg);
        *SHIELD.ptr() -= 1;
        if *SHIELD.ptr() == 0 {
            msrt_cancel_flag.store(unshielded_cancel_flag(), Ordering::Relaxed);
        }
    }
}

/// Shields the running task from stop requests until the matching `msrt_shield_exit`, for
/// work that must drain after SIGINT/SIGTERM (a server finishing in-flight requests).
#[unsafe(no_mangle)]
pub extern "C" fn msrt_shield_enter() {
    // SAFETY: single threaded access to the shield counter.
    unsafe {
        *SHIELD.ptr() += 1;
        msrt_cancel_flag.store(0, Ordering::Relaxed);
    }
}

/// Ends one `msrt_shield_enter`; a stop request that arrived meanwhile applies again.
#[unsafe(no_mangle)]
pub extern "C" fn msrt_shield_exit() {
    // SAFETY: single threaded access to the shield counter.
    unsafe {
        *SHIELD.ptr() = (*SHIELD.ptr()).saturating_sub(1);
        if *SHIELD.ptr() == 0 {
            msrt_cancel_flag.store(unshielded_cancel_flag(), Ordering::Relaxed);
        }
    }
}

/// Pops and runs the innermost cleanup action; false when none remain.
fn run_one_cleanup() -> bool {
    // SAFETY: single threaded access to the cleanup stack.
    let action = unsafe {
        let stack = &mut *CLEANUPS.ptr();
        if stack.len() <= guard_base() {
            None
        } else {
            stack.pop()
        }
    };
    match action {
        Some((f, arg)) => {
            // SAFETY: `f` was stored from a valid `CleanupFn` whose provenance `as usize` exposed.
            let f: CleanupFn = unsafe {
                core::mem::transmute::<*const (), CleanupFn>(core::ptr::with_exposed_provenance(f))
            };
            run_shielded(f, core::ptr::with_exposed_provenance_mut(arg));
            true
        }
        None => false,
    }
}

/// The full fault path: trace, cleanups LIFO, report, exit 70.
#[cold]
#[inline(never)]
pub fn fault(msg: &[u8]) -> ! {
    let mut report = Vec::with_capacity(msg.len() + 256);
    report.extend_from_slice(msg);
    fault_vec(report)
}

/// [`fault`] with the message already in an owned buffer, which becomes the report: a guarded
/// fault leaves by a jump, so no caller frame gets to free a buffer of its own.
#[cold]
#[inline(never)]
pub fn fault_vec(mut report: Vec<u8>) -> ! {
    // SAFETY: single threaded access to the fault state.
    unsafe {
        if *FAULTING.ptr() {
            // A fault inside a cleanup action: record it and keep unwinding from here.
            (*SECONDARY.ptr()).push(report);
            while run_one_cleanup() {}
            finish_report(None)
        }
        *FAULTING.ptr() = true;
    }
    describe_frames(&mut report, frame_pointer());
    // SAFETY: single threaded; a fault inside a cleanup action finishes this report.
    unsafe { *PRIMARY.ptr() = Some(report) };
    while run_one_cleanup() {}
    finish_report(None)
}

/// Starts the fault message of `skip(reason)`; ms-lower writes the same marker.
#[cfg(not(test))]
const SKIP_MARKER: &[u8] = b"\x01SKIP\x01";

static PRIMARY: Global<Option<Vec<u8>>> = Global::new(None);

fn finish_report(primary: Option<Vec<u8>>) -> ! {
    // SAFETY: single threaded access to the report state.
    let mut report = unsafe {
        if let Some(p) = primary {
            *PRIMARY.ptr() = Some(p);
        }
        (*PRIMARY.ptr()).take().unwrap_or_default()
    };
    // SAFETY: single threaded access to the fault state.
    unsafe {
        for message in (*SECONDARY.ptr()).drain(..) {
            report.extend_from_slice(b"\ncleanup fault: ");
            report.extend_from_slice(&message);
        }
        *FAULTING.ptr() = false;
    }
    #[cfg(test)]
    {
        std::panic::panic_any(crate::testutil::FaultPayload(
            std::string::String::from_utf8_lossy(report.as_slice()).into_owned(),
        ));
    }
    #[cfg(not(test))]
    {
        if guard_active() {
            guard_exit(GUARD_FAULT, report)
        }
        if report.as_slice().starts_with(SKIP_MARKER)
            && !report
                .as_slice()
                .windows(16)
                .any(|w| w == b"\ncleanup fault: ")
        {
            // `skip`: the cleanups ran; report the reason (the first line) and end with success.
            let line = report
                .as_slice()
                .split(|b| *b == b'\n')
                .next()
                .unwrap_or_default();
            let mut out = Vec::new();
            out.extend_from_slice(line);
            out.push(b'\n');
            crate::io::flush_stdout();
            sys::write_all(sys::STDERR, out.as_slice());
            crate::process::exit(0)
        }
        report.push(b'\n');
        crate::io::flush_stdout();
        sys::write_all(sys::STDERR, report.as_slice());
        crate::process::exit(ms_rt_abi::EXIT_FAULT)
    }
}

/// Faults with a formatted message.
#[cold]
pub fn fault_fmt(args: fmt::Arguments) -> ! {
    let mut b = Vec::new();
    let _ = b.write_fmt(args);
    fault_vec(b)
}

/// Convenience: `fault!("fmt {}", x)`.
#[macro_export]
macro_rules! fault {
    ($($arg:tt)*) => { $crate::fault::fault_fmt(format_args!($($arg)*)) };
}

// ---- exported entry points ----

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_fault(msg: *const u8, len: usize) -> ! {
    // SAFETY: caller passes a readable range.
    fault(unsafe { core::slice::from_raw_parts(msg, len) })
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_fault_string(s: *mut ms_rt_abi::StrObj) -> ! {
    // SAFETY: caller passes a live string.
    fault(unsafe { crate::string::bytes(s) })
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_depth() -> ! {
    // SAFETY: single threaded counter reset so cleanups can run calls.
    unsafe { msrt_call_depth = 0 };
    fault_fmt(format_args!(
        "call depth limit exceeded ({} nested calls); check the recursion for a missing base case, or iterate instead",
        ms_rt_abi::MAX_CALL_DEPTH
    ))
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_index_fault(index: i64, length: i64) -> ! {
    fault_fmt(format_args!(
        "index {index} out of range for length {length}; pass a default: get(index:, default: ...)"
    ))
}

/// Faults for an invalid index of a list mutator over `len` elements; `operation` is 0 for
/// `insert` (which also accepts `len`), 1 for `remove` and 2 for `set`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_list_index_fault(operation: i64, index: i64, len: i64) -> ! {
    let (name, hi) = match operation {
        0 => ("List.insert", len),
        1 => ("List.remove", len - 1),
        _ => ("List.set", len - 1),
    };
    if operation != 0 && len == 0 {
        fault_fmt(format_args!(
            "{name}: index has no valid value for an empty collection, found {index}"
        ))
    }
    fault_fmt(format_args!(
        "{name}: index must be between {} and {hi} (negative indexes count from the end), found {index}",
        -len
    ))
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_unwrap_none() -> ! {
    fault(
        b"called Optional.get() on none; check is_some first, or pass a default: get(default: ...)",
    )
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_result_get() -> ! {
    fault(b"called Result.get() on error; check is_ok first, or pass a default: get(default: ...)")
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_result_err() -> ! {
    fault(b"called Result.err() on ok; check is_error first")
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_int_overflow() -> ! {
    fault(b"Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt")
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_div_zero() -> ! {
    fault(b"Int./: division by zero; right must be nonzero, found 0")
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_rem_zero() -> ! {
    fault(b"Int.%: remainder by zero; right must be nonzero, found 0")
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_div_overflow(a: i64, b: i64) -> ! {
    fault_fmt(format_args!(
        "Int./: overflow; found left {a} and right {b}; result must be between {} and {}",
        i64::MIN,
        i64::MAX
    ))
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_cleanup_push(f: CleanupFn, arg: *mut u8) -> usize {
    // SAFETY: single threaded access to the cleanup stack.
    unsafe {
        let s = &mut *CLEANUPS.ptr();
        s.push((f as usize, arg as usize));
        s.len()
    }
}

/// Runs the action behind `handle` (and newer pending ones first).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cleanup_run(handle: usize) {
    // SAFETY: single threaded access to the cleanup stack.
    while unsafe { (*CLEANUPS.ptr()).len() } >= handle && handle > 0 {
        if !run_one_cleanup() {
            break;
        }
    }
}

/// Drops the action behind `handle` (and newer pending ones) without running them.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cleanup_discard(handle: usize) {
    // SAFETY: single threaded access to the cleanup stack.
    unsafe {
        let stack = &mut *CLEANUPS.ptr();
        while stack.len() >= handle && handle > 0 {
            if stack.pop().is_none() {
                break;
            }
        }
    }
}

/// Unwinds on a stop request: runs cleanups and exits 130/143.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cancelled() -> ! {
    let sig = PENDING_SIGNAL.load(core::sync::atomic::Ordering::Relaxed);
    while run_one_cleanup() {}
    #[cfg(test)]
    {
        std::panic::panic_any(crate::testutil::FaultPayload(std::format!(
            "cancelled {sig}"
        )));
    }
    #[cfg(not(test))]
    if guard_active() {
        guard_exit(GUARD_CANCELLED, Vec::new())
    }
    #[cfg(not(test))]
    crate::process::exit(if sig == sys::SIGINT as u8 {
        ms_rt_abi::EXIT_INTERRUPT
    } else {
        ms_rt_abi::EXIT_TERMINATE
    })
}

// ---- guarded calls ----

/// Result of `msrt_guard_call`.
const GUARD_OK: u8 = 0;
const GUARD_FAULT: u8 = 1;
const GUARD_CANCELLED: u8 = 2;

/// State captured on entry to a guarded call, restored when a fault leaves it.
#[derive(Clone, Copy)]
#[cfg_attr(test, allow(dead_code))]
struct GuardFrame {
    /// Address of the register save slot owned by the `msrt_guard_call` frame.
    jmp: usize,
    cleanups: usize,
    depth: i64,
    shield: u32,
    eq_pairs: usize,
    /// `jmp` is the register buffer of `expect_fault` (Windows) rather than a guard slot.
    #[cfg_attr(not(windows), allow(dead_code))]
    trap: bool,
}

static GUARDS: Global<Vec<GuardFrame>> = Global::new(Vec::new());

/// Length of the cleanup stack below the innermost guard (0 outside guards).
#[inline]
fn guard_base() -> usize {
    // SAFETY: single threaded access to the guard stack.
    unsafe {
        let g = &*GUARDS.ptr();
        match g.as_slice().last() {
            Some(f) => f.cleanups,
            None => 0,
        }
    }
}

#[cfg(not(test))]
fn guard_active() -> bool {
    // SAFETY: single threaded access to the guard stack.
    unsafe { !(*GUARDS.ptr()).is_empty() }
}

/// Leaves the innermost guard with `status`, handing the message to its caller. The jump skips
/// destructors, so the message buffer is released here first.
#[cfg(not(test))]
fn guard_exit(status: u8, message: Vec<u8>) -> ! {
    // SAFETY: single threaded access; the frame belongs to a live `msrt_guard_call`.
    unsafe {
        let f = (*GUARDS.ptr())
            .pop()
            .unwrap_or_else(|| fatal(b"runtime invariant: no guard"));
        *FAULTING.ptr() = false;
        msrt_call_depth = f.depth;
        *SHIELD.ptr() = f.shield;
        msrt_cancel_flag.store(
            if f.shield == 0 {
                unshielded_cancel_flag()
            } else {
                0
            },
            Ordering::Relaxed,
        );
        crate::desc::eq_truncate(f.eq_pairs);
        #[cfg(windows)]
        if f.trap {
            crate::trap::leave(f.jmp as *mut usize, status == GUARD_FAULT, message)
        }
        GUARD_MESSAGE = if status == GUARD_FAULT {
            crate::string::from_bytes(&message)
        } else {
            core::ptr::null_mut()
        };
        drop(message);
        guard_jump(f.jmp as *mut usize, status as usize)
    }
}

/// Opens a guard frame for `expect_fault`, whose registers are saved in `buf`.
///
/// # Safety
/// Single threaded; paired with [`pop_trap_guard`] or a fault that leaves through it.
#[cfg(all(windows, not(test)))]
pub(crate) unsafe fn push_trap_guard(buf: *mut usize) {
    // SAFETY: single threaded runtime state.
    unsafe {
        (*GUARDS.ptr()).push(GuardFrame {
            jmp: buf as usize,
            cleanups: (*CLEANUPS.ptr()).len(),
            depth: msrt_call_depth,
            shield: *SHIELD.ptr(),
            eq_pairs: crate::desc::eq_len(),
            trap: true,
        });
    }
}

/// Drops the frame opened by [`push_trap_guard`] when the operation ended without a fault.
///
/// # Safety
/// Single threaded.
#[cfg(all(windows, not(test)))]
pub(crate) unsafe fn pop_trap_guard() {
    // SAFETY: single threaded runtime state.
    unsafe {
        (*GUARDS.ptr()).pop();
    }
}

#[cfg(not(test))]
static mut GUARD_MESSAGE: *mut ms_rt_abi::StrObj = core::ptr::null_mut();

#[cfg(not(test))]
unsafe extern "C" {
    /// Saves callee-saved registers and the stack pointer in `*jmp`, calls `code(data)` and
    /// returns 0, or returns the value given to `guard_jump` when that is called later.
    fn msrt_guard_enter(
        jmp: *mut usize,
        code: unsafe extern "C-unwind" fn(*mut u8),
        data: *mut u8,
    ) -> usize;
    #[link_name = "msrt_guard_jump"]
    fn guard_jump(jmp: *mut usize, status: usize) -> !;
}

// Windows x64 passes arguments in rcx, rdx and r8, expects 32 bytes of shadow space at calls
// and treats rdi, rsi and xmm6-xmm15 as callee-saved.
#[cfg(all(not(test), target_arch = "x86_64", windows))]
core::arch::global_asm!(
    ".text",
    concat!(".globl ", sym!("msrt_guard_enter")),
    concat!(".globl ", sym!("msrt_guard_jump")),
    concat!(sym!("msrt_guard_enter"), ":"),
    "push rbp",
    "push rbx",
    "push rdi",
    "push rsi",
    "push r12",
    "push r13",
    "push r14",
    "push r15",
    "sub rsp, 168",
    "movups [rsp], xmm6",
    "movups [rsp + 16], xmm7",
    "movups [rsp + 32], xmm8",
    "movups [rsp + 48], xmm9",
    "movups [rsp + 64], xmm10",
    "movups [rsp + 80], xmm11",
    "movups [rsp + 96], xmm12",
    "movups [rsp + 112], xmm13",
    "movups [rsp + 128], xmm14",
    "movups [rsp + 144], xmm15",
    "mov [rcx], rsp",
    "mov rax, rdx",
    "mov rcx, r8",
    "sub rsp, 32",
    "call rax",
    "add rsp, 32",
    "xor eax, eax",
    "1:",
    "movups xmm6, [rsp]",
    "movups xmm7, [rsp + 16]",
    "movups xmm8, [rsp + 32]",
    "movups xmm9, [rsp + 48]",
    "movups xmm10, [rsp + 64]",
    "movups xmm11, [rsp + 80]",
    "movups xmm12, [rsp + 96]",
    "movups xmm13, [rsp + 112]",
    "movups xmm14, [rsp + 128]",
    "movups xmm15, [rsp + 144]",
    "add rsp, 168",
    "pop r15",
    "pop r14",
    "pop r13",
    "pop r12",
    "pop rsi",
    "pop rdi",
    "pop rbx",
    "pop rbp",
    "ret",
    concat!(sym!("msrt_guard_jump"), ":"),
    "mov rsp, [rcx]",
    "mov rax, rdx",
    "jmp 1b",
);

#[cfg(all(not(test), target_arch = "x86_64", not(windows)))]
core::arch::global_asm!(
    ".text",
    concat!(".globl ", sym!("msrt_guard_enter")),
    concat!(".globl ", sym!("msrt_guard_jump")),
    concat!(sym!("msrt_guard_enter"), ":"),
    "push rbp",
    "push rbx",
    "push r12",
    "push r13",
    "push r14",
    "push r15",
    "sub rsp, 8",
    "mov [rdi], rsp",
    "mov rax, rsi",
    "mov rdi, rdx",
    "call rax",
    "xor eax, eax",
    "1:",
    "add rsp, 8",
    "pop r15",
    "pop r14",
    "pop r13",
    "pop r12",
    "pop rbx",
    "pop rbp",
    "ret",
    concat!(sym!("msrt_guard_jump"), ":"),
    "mov rsp, [rdi]",
    "mov rax, rsi",
    "jmp 1b",
);

#[cfg(all(not(test), target_arch = "aarch64"))]
core::arch::global_asm!(
    ".text",
    concat!(".globl ", sym!("msrt_guard_enter")),
    concat!(".globl ", sym!("msrt_guard_jump")),
    concat!(sym!("msrt_guard_enter"), ":"),
    "sub sp, sp, #160",
    "stp x29, x30, [sp, #0]",
    "stp x19, x20, [sp, #16]",
    "stp x21, x22, [sp, #32]",
    "stp x23, x24, [sp, #48]",
    "stp x25, x26, [sp, #64]",
    "stp x27, x28, [sp, #80]",
    "stp d8, d9, [sp, #96]",
    "stp d10, d11, [sp, #112]",
    "stp d12, d13, [sp, #128]",
    "stp d14, d15, [sp, #144]",
    "mov x3, sp",
    "str x3, [x0]",
    "mov x0, x2",
    "blr x1",
    "mov x0, #0",
    "1:",
    "ldp x29, x30, [sp, #0]",
    "ldp x19, x20, [sp, #16]",
    "ldp x21, x22, [sp, #32]",
    "ldp x23, x24, [sp, #48]",
    "ldp x25, x26, [sp, #64]",
    "ldp x27, x28, [sp, #80]",
    "ldp d8, d9, [sp, #96]",
    "ldp d10, d11, [sp, #112]",
    "ldp d12, d13, [sp, #128]",
    "ldp d14, d15, [sp, #144]",
    "add sp, sp, #160",
    "ret",
    concat!(sym!("msrt_guard_jump"), ":"),
    "ldr x3, [x0]",
    "mov sp, x3",
    "mov x0, x1",
    "b 1b",
);

/// Runs `code(data)` as an isolated request. A fault (or stop request) inside it runs the
/// cleanups registered since entry and returns 1 (fault, with the report in `*msg_out`) or 2
/// (cancelled, `*msg_out` null) instead of ending the process. Returns 0 when `code` returns.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_guard_call(
    code: unsafe extern "C-unwind" fn(*mut u8),
    data: *mut u8,
    msg_out: *mut *mut ms_rt_abi::StrObj,
) -> u8 {
    // SAFETY: single threaded runtime state; the frame is popped before returning.
    unsafe {
        if !msg_out.is_null() {
            *msg_out = core::ptr::null_mut();
        }
        let mut slot: usize = 0;
        (*GUARDS.ptr()).push(GuardFrame {
            jmp: core::ptr::addr_of_mut!(slot) as usize,
            cleanups: (*CLEANUPS.ptr()).len(),
            depth: msrt_call_depth,
            shield: *SHIELD.ptr(),
            eq_pairs: crate::desc::eq_len(),
            trap: false,
        });
        #[cfg(not(test))]
        {
            let r = msrt_guard_enter(core::ptr::addr_of_mut!(slot), code, data);
            if r == 0 {
                (*GUARDS.ptr()).pop();
                return GUARD_OK;
            }
            if !msg_out.is_null() {
                *msg_out = GUARD_MESSAGE;
            } else if !GUARD_MESSAGE.is_null() {
                crate::obj::release(GUARD_MESSAGE as *mut ms_rt_abi::Obj);
            }
            GUARD_MESSAGE = core::ptr::null_mut();
            r as u8
        }
        #[cfg(test)]
        {
            let depth = msrt_call_depth;
            let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| code(data)));
            (*GUARDS.ptr()).pop();
            match r {
                Ok(()) => GUARD_OK,
                Err(e) => {
                    let Ok(p) = e.downcast::<crate::testutil::FaultPayload>() else {
                        fatal(b"unexpected panic in guard")
                    };
                    *FAULTING.ptr() = false;
                    msrt_call_depth = depth;
                    if p.0.starts_with("cancelled ") {
                        return GUARD_CANCELLED;
                    }
                    if !msg_out.is_null() {
                        *msg_out = crate::string::from_bytes(p.0.as_bytes());
                    }
                    GUARD_FAULT
                }
            }
        }
    }
}

#[cfg(test)]
pub fn reset_for_tests() {
    // SAFETY: tests hold the global lock.
    unsafe {
        (*CLEANUPS.ptr()).clear();
        (*GUARDS.ptr()).clear();
        *FAULTING.ptr() = false;
        *SHIELD.ptr() = 0;
        (*SECONDARY.ptr()).clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{fault_of, lock};

    static LOG: Global<[u8; 8]> = Global::new([0; 8]);
    static LOG_N: Global<usize> = Global::new(0);

    unsafe extern "C-unwind" fn log_action(arg: *mut u8) {
        // SAFETY: tests hold the lock; LOG has room for 8 entries.
        unsafe {
            let n = *LOG_N.ptr();
            (*LOG.ptr())[n] = arg as usize as u8;
            *LOG_N.ptr() = n + 1;
        }
    }

    unsafe extern "C-unwind" fn faulting_action(_arg: *mut u8) {
        fault(b"close failed");
    }

    unsafe extern "C-unwind" fn request(data: *mut u8) {
        // SAFETY: tests pass a pointer to a live u8.
        unsafe {
            msrt_cleanup_push(log_action, core::ptr::without_provenance_mut(2));
            if *data == 1 {
                fault(b"handler failed");
            }
            *data += 10;
        }
    }

    #[test]
    fn guard_isolates_a_fault_and_keeps_outer_cleanups() {
        let _g = lock();
        reset_for_tests();
        // SAFETY: tests hold the global lock and pass valid pointers.
        unsafe {
            *LOG_N.ptr() = 0;
            msrt_cleanup_push(log_action, core::ptr::without_provenance_mut(1));
            let mut msg: *mut ms_rt_abi::StrObj = core::ptr::null_mut();
            let mut data = 1u8;
            assert_eq!(msrt_guard_call(request, &mut data, &mut msg), 1);
            assert!(!msg.is_null());
            assert!(crate::string::bytes(msg).starts_with(b"handler failed"));
            assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[2]);
            assert_eq!((*CLEANUPS.ptr()).len(), 1);
            let mut ok = 0u8;
            assert_eq!(msrt_guard_call(request, &mut ok, &mut msg), 0);
            assert!(msg.is_null());
            assert_eq!(ok, 10);
            assert_eq!((*CLEANUPS.ptr()).len(), 2);
            reset_for_tests();
        }
    }

    #[test]
    fn cleanups_run_lifo_on_fault_with_secondary() {
        let _g = lock();
        reset_for_tests();
        // SAFETY: test-only access.
        unsafe { *LOG_N.ptr() = 0 };
        // SAFETY: valid function pointers.
        unsafe {
            msrt_cleanup_push(log_action, core::ptr::dangling_mut::<u8>());
            msrt_cleanup_push(faulting_action, core::ptr::null_mut());
            msrt_cleanup_push(log_action, 3 as *mut u8);
        }
        let text = fault_of(|| fault(b"boom")).unwrap();
        assert_eq!(text, "boom\ncleanup fault: close failed");
        // SAFETY: test-only access.
        unsafe {
            assert_eq!(&(&*LOG.ptr())[..*LOG_N.ptr()], &[3, 1]);
        }
    }

    #[test]
    fn cleanup_run_pops_to_handle() {
        let _g = lock();
        reset_for_tests();
        // SAFETY: test-only access and valid function pointers.
        unsafe {
            *LOG_N.ptr() = 0;
            let h1 = msrt_cleanup_push(log_action, core::ptr::dangling_mut::<u8>());
            let _h2 = msrt_cleanup_push(log_action, core::ptr::without_provenance_mut(2));
            msrt_cleanup_run(h1);
            assert_eq!(&(&*LOG.ptr())[..*LOG_N.ptr()], &[2, 1]);
            msrt_cleanup_run(h1);
            assert_eq!(*LOG_N.ptr(), 2);
        }
    }

    #[test]
    fn walk_frames_rejects_frame_pointers_that_wrap_the_address_space() {
        let _g = lock();
        reset_for_tests();
        // SAFETY: test-only access to the stack bounds, restored below.
        unsafe {
            *STACK_LO.ptr() = 0x1000;
            *STACK_HI.ptr() = 0x2000;
            // `fp + 16` wraps to 8, which a plain add would accept as below `hi`.
            walk_frames(usize::MAX - 7, |_| panic!("read a frame outside the stack"));
            *STACK_LO.ptr() = 0;
            *STACK_HI.ptr() = 0;
        }
    }

    #[test]
    fn frames_resolve_through_tables() {
        let _g = lock();
        reset_for_tests();
        // Fake frame chain: three frames with return addresses 0x1010, 0x2010, 0x9999.
        let mut chain: [[usize; 2]; 3] = [[0, 0x1010], [0, 0x2010], [0, 0x9999]];
        // Every link derives from one raw pointer to the whole chain, so the exposed address
        // may be dereferenced later (a shared reference per frame would cover only that frame).
        let base = chain.as_mut_ptr();
        // SAFETY: the offsets stay inside `chain`.
        unsafe {
            (*base)[0] = base.add(1).expose_provenance();
            (*base.add(1))[0] = base.add(2).expose_provenance();
        }
        let strings = b"\0outer\0inner\0a.ms\0";
        let funcs = [
            FuncEntry {
                addr: 0x1000,
                size: 0x100,
                name_off: 7,
                file_off: 13,
                line: 3,
            },
            FuncEntry {
                addr: 0x2000,
                size: 0x100,
                name_off: 1,
                file_off: 13,
                line: 9,
            },
        ];
        let lines = [LineEntry {
            pc: 0x1008,
            line: 4,
            file_off: u32::MAX,
        }];
        let t = Tables {
            abi_version: 1,
            reserved: 0,
            line_scopes: core::ptr::null(),
            scopes: core::ptr::null(),
            scope_count: 0,
            funcs: funcs.as_ptr(),
            func_count: 2,
            lines: lines.as_ptr(),
            line_count: 1,
            strings: strings.as_ptr(),
            strings_len: strings.len(),
        };
        // SAFETY: test-only access to globals; `t` outlives the use.
        unsafe { *TABLES.ptr() = &t };
        let mut out = Vec::new();
        describe_frames(&mut out, base.expose_provenance());
        // SAFETY: restore.
        unsafe { *TABLES.ptr() = core::ptr::null() };
        assert_eq!(
            core::str::from_utf8(out.as_slice()).unwrap(),
            "\n  at a.ms:4 in inner\n  at a.ms:9 in outer"
        );
    }

    #[test]
    fn named_faults_use_go_messages() {
        let _g = lock();
        reset_for_tests();
        assert_eq!(
            fault_of(|| msrt_index_fault(7, 3)).unwrap(),
            "index 7 out of range for length 3; pass a default: get(index:, default: ...)"
        );
        assert_eq!(
            fault_of(|| msrt_fault_depth()).unwrap(),
            "call depth limit exceeded (200000 nested calls); check the recursion for a missing base case, or iterate instead"
        );
    }
}
