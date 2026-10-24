//! Faults, the cleanup stack, call depth, cancellation and process exit.
use crate::global::Process;
#[allow(unused_imports)]
use crate::sys;
use core::fmt;
use core::sync::atomic::{AtomicU8, Ordering};
use ms_rt_abi::{FuncEntry, LineEntry, MAX_FAULT_FRAMES, ScopeEntry, TABLES_WITH_SCOPES, Tables};
use std::io::Write as _;

/// The words generated code reads, one block per task stack. On Unix it sits at the base of the
/// task's stack slot, which generated code finds by masking the stack pointer; elsewhere it is
/// reached through `msrt_isolate_hdr`.
#[repr(C)]
pub struct Hdr {
    /// Lowest stack address recursive calls may reach before they fault (0 = no limit);
    /// generated code compares the stack pointer against it on entry to a recursive function.
    pub limit: usize,
    /// Non-zero (the signal number) once a stop was requested and not shielded.
    pub cancel: AtomicU8,
    /// Nesting depth of the task's cancellation shields. A signal handler on any thread reads it
    /// for the main isolate's running task, so it lives here and not in a thread-local.
    pub shield: core::cell::Cell<u32>,
}

// SAFETY: `shield` is written by the owning isolate only and read racily as a single word by
// stop-signal handlers, which tolerate a stale value (the next switch recomputes the flag).
unsafe impl Sync for Hdr {}

impl Hdr {
    pub const fn new(limit: usize) -> Hdr {
        Hdr {
            limit,
            cancel: AtomicU8::new(0),
            shield: core::cell::Cell::new(0),
        }
    }
}

crate::isolate_static! {
    /// The block of the thread's own flow, used until a task stack is switched to.
    static ROOT_HDR: Hdr = Hdr::new(0);
    /// The running task's block; null before the first switch (the root block then).
    static CUR_HDR: *mut Hdr = core::ptr::null_mut();
}

/// The main isolate's running-task block, for stop-signal handlers that run on any thread.
static MAIN_CUR: core::sync::atomic::AtomicPtr<Hdr> =
    core::sync::atomic::AtomicPtr::new(core::ptr::null_mut());

/// The running task's block.
#[inline(always)]
pub(crate) fn cur_hdr() -> *mut Hdr {
    // SAFETY: this isolate's state.
    let p = unsafe { *CUR_HDR.ptr() };
    if p.is_null() { ROOT_HDR.ptr() } else { p }
}

/// Generated code on targets without slot-aligned stacks finds the running task's [`Hdr`]
/// through this call.
#[unsafe(no_mangle)]
pub extern "C" fn msrt_isolate_hdr() -> *mut Hdr {
    cur_hdr()
}

/// The running task's cancel flag.
#[inline(always)]
pub fn cancel_flag() -> &'static AtomicU8 {
    // SAFETY: the block lives as long as its stack.
    unsafe { &(*cur_hdr()).cancel }
}

/// Makes the calling isolate the one stop signals are delivered to.
pub fn set_main_hdr() {
    MAIN_CUR.store(cur_hdr(), Ordering::Release);
}

/// Called by a stop-signal handler on any thread: raises the cancel flag of the main isolate's
/// running task unless it is shielded.
pub fn raise_main_cancel(sig: u8) {
    let hdr = MAIN_CUR.load(Ordering::Acquire);
    if hdr.is_null() {
        return;
    }
    // SAFETY: a task block outlives its stack's use; `shield` is read as one word.
    unsafe {
        if core::ptr::read_volatile((*hdr).shield.as_ptr()) == 0 {
            (*hdr).cancel.store(sig, Ordering::Relaxed);
        }
    }
}

/// The cancellation-shield depth of the running task, as a place.
pub(crate) struct ShieldRef;
pub(crate) static SHIELD: ShieldRef = ShieldRef;
impl ShieldRef {
    #[inline(always)]
    pub(crate) fn ptr(&self) -> *mut u32 {
        // SAFETY: the block lives as long as its stack.
        unsafe { (*cur_hdr()).shield.as_ptr() }
    }
}

pub static TABLES: Process<*const Tables> = Process::new(core::ptr::null());
/// Lowest and highest valid stack addresses for frame walking (0 = unknown). Process-wide until
/// worker isolates exist: the Windows sampler thread and the `SIGPROF` handler read them from other
/// threads (see `proposals/worker-threads.md`).
pub static STACK_LO: Process<usize> = Process::new(0);
pub static STACK_HI: Process<usize> = Process::new(0);

/// Stack kept free below the limit for fault reporting and cleanups.
const STACK_RESERVE_MAX: usize = 1 << 20;
const STACK_RESERVE_MIN: usize = 64 << 10;
/// Stack left to cleanups that run after a depth fault.
const STACK_CLEANUP_RESERVE: usize = 16 << 10;

/// Deepest stack recursion may use: a runaway recursion touches this much memory before it faults.
const STACK_RECURSION_MAX: usize = 256 << 20;

/// Bound fault/profiler traversal work independently of the recursion stack limit.
const MAX_STACK_WALK_FRAMES: usize = 1_000_000;

/// Windows unwinds walker-internal frames before reaching the same starting
/// frame as the Unix walker. Only callers recovered after that anchor count.
#[cfg(any(windows, test))]
#[derive(Default)]
pub(crate) struct NativeFrameBudget(Option<usize>);

#[cfg(any(windows, test))]
impl NativeFrameBudget {
    pub(crate) fn visit(&mut self, is_anchor: bool) -> bool {
        if let Some(remaining) = self.0 {
            self.0 = remaining.checked_sub(1);
            return self.0.is_some();
        }
        if is_anchor {
            self.0 = Some(MAX_STACK_WALK_FRAMES);
        }
        true
    }

    pub(crate) fn remaining(&self) -> Option<usize> {
        self.0
    }
}

/// The recursion limit for a stack spanning `lo..hi`: recursion may use the top 256 MiB, minus
/// a reserve of an eighth (64 KiB..1 MiB) for fault reporting. 0 when the bounds are unknown.
pub(crate) const fn stack_limit(lo: usize, hi: usize) -> usize {
    if lo == 0 || hi <= lo {
        return 0;
    }
    let mut start = lo;
    if hi - lo > STACK_RECURSION_MAX {
        start = hi - STACK_RECURSION_MAX;
    }
    let mut reserve = (hi - start) / 8;
    if reserve < STACK_RESERVE_MIN {
        reserve = STACK_RESERVE_MIN;
    }
    if reserve > STACK_RESERVE_MAX {
        reserve = STACK_RESERVE_MAX;
    }
    start + reserve
}

/// Records the bounds of the running stack and the recursion limit derived from them.
///
/// # Safety
/// Single threaded runtime state.
#[cfg(windows)]
pub(crate) unsafe fn set_stack_bounds(lo: usize, hi: usize) {
    // SAFETY: single threaded access to the runtime globals.
    unsafe {
        *STACK_LO.ptr() = lo;
        *STACK_HI.ptr() = hi;
        (*cur_hdr()).limit = stack_limit(lo, hi);
    }
}

type CleanupFn = unsafe extern "C-unwind" fn(*mut u8);
crate::isolate_static! {
    static CLEANUPS: Vec<(usize, usize)> = Vec::new();
}
pub static PENDING_SIGNAL: AtomicU8 = AtomicU8::new(0);
crate::isolate_static! {
    static FAULTING: bool = false;
}
crate::isolate_static! {
    static SECONDARY: Vec<Vec<u8>> = Vec::new();
}
crate::isolate_static! {
/// Stop request aimed at the running task (see `task`); 0 when none.
    static TASK_CANCEL: u8 = 0;
}
/// Value of the cancel flag when cancellation is not shielded.
pub(crate) fn unshielded_cancel_flag() -> u8 {
    // SAFETY: single threaded access.
    let task = unsafe { *TASK_CANCEL.ptr() };
    crate::isolate::pending_cancel().max(task)
}

/// Records a stop request aimed at the running task.
pub(crate) fn set_live_task_cancel(v: u8) {
    // SAFETY: single threaded access.
    unsafe {
        *TASK_CANCEL.ptr() = v;
        if *SHIELD.ptr() == 0 {
            cancel_flag().store(unshielded_cancel_flag(), Ordering::Relaxed);
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
    faulting: bool,
    /// The task's block (null until set: the root block).
    hdr: *mut Hdr,
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
            faulting: false,
            hdr: core::ptr::null_mut(),
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
        let hdr = if self.hdr.is_null() {
            ROOT_HDR.ptr()
        } else {
            self.hdr
        };
        // SAFETY: the block lives as long as its stack.
        unsafe { (*hdr).shield.get() > 0 }
    }

    /// The task's block (null for the root task before it ever ran).
    #[cfg(windows)]
    pub(crate) fn hdr_ptr(&self) -> *mut Hdr {
        self.hdr
    }

    /// Binds the task to its block and gives it the recursion limit of its stack.
    pub(crate) fn set_hdr(&mut self, hdr: *mut Hdr) {
        self.hdr = hdr;
        // SAFETY: the block was just prepared for this task.
        unsafe { (*hdr).limit = stack_limit(self.stack_lo, self.stack_hi) };
    }
}

/// Whether the running task is inside a shielded cleanup action.
pub(crate) fn live_shielded() -> bool {
    // SAFETY: single threaded access.
    unsafe { *SHIELD.ptr() > 0 }
}

/// Starts an independent fault boundary in an `expect_fault` fork child. Inherited cleanup
/// actions and guard targets belong to the caller, whose external resources remain live.
/// Cancellation, shielding and stack limits still describe the running operation.
///
/// # Safety
/// Only call in the fork child before running the asserted operation.
#[cfg(unix)]
pub(crate) unsafe fn isolate_trap_child() {
    // SAFETY: fork gives this child its own copy of the single-threaded runtime state.
    unsafe {
        (*CLEANUPS.ptr()).clear();
        (*GUARDS.ptr()).clear();
        *FAULTING.ptr() = false;
        *PRIMARY.ptr() = None;
        (*SECONDARY.ptr()).clear();
    }
    crate::desc::eq_truncate(0);
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
        core::ptr::swap(FAULTING.ptr(), &mut c.faulting);
        core::ptr::swap(CUR_HDR.ptr(), &mut c.hdr);
        core::ptr::swap(TASK_CANCEL.ptr(), &mut c.cancel);
        core::ptr::swap(STACK_LO.ptr(), &mut c.stack_lo);
        core::ptr::swap(STACK_HI.ptr(), &mut c.stack_hi);
        cancel_flag().store(
            if *SHIELD.ptr() == 0 {
                unshielded_cancel_flag()
            } else {
                0
            },
            Ordering::Relaxed,
        );
        if crate::isolate::is_main() {
            MAIN_CUR.store(cur_hdr(), Ordering::Release);
        } else {
            crate::isolate::publish_hdr(cur_hdr());
        }
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
    while fp != 0 && fp.is_multiple_of(8) && steps < MAX_STACK_WALK_FRAMES {
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

/// How far above a frame's stack pointer to look for its frame record, in bytes.
#[cfg(any(windows, test))]
const FRAME_RECORD_SCAN: usize = 4096;

/// Windows native frames do not use the generated code's frame layout. Recover
/// the first source frame with native unwind metadata, then follow only the
/// contiguous generated caller chain. Stop at native/glue boundaries rather
/// than reconstructing a partial native register context.
#[cfg(windows)]
unsafe fn walk_fault_frames(_fp: usize, anchor: usize, t: &Tables, f: impl FnMut(usize) -> bool) {
    #[cfg(target_arch = "x86_64")]
    // SAFETY: written once by the depth-fault shim on this thread, before any report is built.
    let site = unsafe { core::ptr::replace(core::ptr::addr_of_mut!(DEPTH_SITE), [0; 2]) };
    #[cfg(target_arch = "x86_64")]
    let recovered = if site[0] != 0 && anchor == fault_vec as *const () as usize {
        // The depth limit was hit: the shim saved the generated frame, which a diverging Rust
        // function between here and there may have clobbered in the register the unwinder reads.
        Some((site[0], 0, site[1], MAX_STACK_WALK_FRAMES - 2))
    } else {
        sys::source_frame(anchor, |pc| find_func(t, pc).is_some())
    };
    #[cfg(not(target_arch = "x86_64"))]
    let recovered = sys::source_frame(anchor, |pc| find_func(t, pc).is_some());
    let Some((pc, sp, fp, remaining)) = recovered else {
        return;
    };
    let (lo, hi) = sys::stack_limits();
    // A capture unwinds through the scope runtime, whose frames can leave the CONTEXT frame
    // register pointing at a caller's record, so it finds the generated frame's own record.
    let fp = if anchor == capture_frames as *const () as usize {
        // SAFETY: `sp` is the live stack pointer of the recovered frame, below `hi`.
        unsafe { frame_record(sp, lo, hi, |pc| find_func(t, pc).is_some()) }.unwrap_or(fp)
    } else {
        fp
    };
    // SAFETY: source_frame recovered the current generated frame and stack_limits
    // bounds the live thread stack.
    unsafe { walk_source_frames(pc, fp, t, lo, hi, remaining, f) }
}

/// The address of the first frame record `[saved fp, return address]` at or above `sp` whose
/// return address `is_source` accepts and whose saved fp lies further up the stack.
///
/// # Safety
/// `sp..hi` is live stack memory.
#[cfg(any(windows, test))]
unsafe fn frame_record(
    sp: usize,
    lo: usize,
    hi: usize,
    mut is_source: impl FnMut(usize) -> bool,
) -> Option<usize> {
    let first = sp.checked_add(7)? & !7;
    let last = first
        .checked_add(FRAME_RECORD_SCAN)?
        .min(hi.checked_sub(16)?);
    let mut at = first;
    while at <= last {
        if at >= lo {
            // SAFETY: `at + 16 <= hi` within the live stack.
            let (next, ret) = unsafe { (*(at as *const usize), *((at + 8) as *const usize)) };
            if next > at && next.is_multiple_of(8) && next < hi && is_source(ret) {
                return Some(at);
            }
        }
        at += 8;
    }
    None
}

#[cfg(any(windows, test))]
unsafe fn walk_source_frames(
    mut pc: usize,
    mut fp: usize,
    t: &Tables,
    lo: usize,
    hi: usize,
    remaining: usize,
    mut f: impl FnMut(usize) -> bool,
) {
    // Each link must advance within the stack, so the stack bounds terminate
    // even a malformed chain. Apply the shared raw-frame work budget after the
    // native prefix, rather than imposing a separate Windows source-frame cap.
    for _ in 0..remaining {
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
unsafe fn walk_fault_frames(fp: usize, _anchor: usize, _t: &Tables, f: impl FnMut(usize) -> bool) {
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

/// Returns `t` with its function and line tables ordered by address. The compiler emits them in
/// declaration order, but a linker may place functions differently (macOS arm64 moves functions
/// that only reach a noreturn call away from the rest), and the lookups binary-search by address.
///
/// # Safety
/// `t` must be null or point to valid tables that live for the whole process.
pub unsafe fn address_ordered_tables(t: *const Tables) -> *const Tables {
    // SAFETY: the caller promises valid tables.
    let Some(tr) = (unsafe { t.as_ref() }) else {
        return t;
    };
    if tr.funcs.is_null() || tr.func_count == 0 {
        return t;
    }
    // SAFETY: `func_count` read-only entries.
    let funcs = unsafe { core::slice::from_raw_parts(tr.funcs, tr.func_count) };
    if funcs.is_sorted_by_key(|e| e.addr) {
        return t;
    }
    let mut sorted_funcs = funcs.to_vec();
    sorted_funcs.sort_by_key(|e| e.addr);
    let mut out = Tables { ..*tr };
    out.funcs = Vec::leak(sorted_funcs).as_ptr();
    if !tr.lines.is_null() && tr.line_count > 0 {
        // SAFETY: `line_count` read-only entries, with `line_scopes` parallel when present.
        let lines = unsafe { core::slice::from_raw_parts(tr.lines, tr.line_count) };
        let scoped = tr.abi_version >= TABLES_WITH_SCOPES && !tr.line_scopes.is_null();
        let mut order: Vec<usize> = (0..lines.len()).collect();
        order.sort_by_key(|&i| lines[i].pc);
        out.lines = Vec::leak(order.iter().map(|&i| lines[i]).collect::<Vec<_>>()).as_ptr();
        if scoped {
            // SAFETY: `line_scopes` parallels `lines`.
            let scopes = unsafe { core::slice::from_raw_parts(tr.line_scopes, tr.line_count) };
            out.line_scopes =
                Vec::leak(order.iter().map(|&i| scopes[i]).collect::<Vec<_>>()).as_ptr();
        }
    }
    Box::into_raw(Box::new(out))
}

/// Return addresses of the calling frames, innermost first, for a later [`describe_started`].
#[inline(never)]
pub fn capture_frames() -> Vec<usize> {
    let mut out = Vec::new();
    // SAFETY: tables pointer is set once at start.
    let t = unsafe { *TABLES.ptr() };
    if t.is_null() {
        return out;
    }
    // SAFETY: non-null table installed by `msrt_start`; the frame pointer is this thread's live
    // chain, and on Windows the anchor is this function, as `fault_vec` is for a fault.
    unsafe {
        walk_fault_frames(
            frame_pointer(),
            capture_frames as *const () as usize,
            &*t,
            |ret| {
                out.push(ret);
                out.len() < 2 * MAX_FAULT_FRAMES
            },
        );
    }
    out
}

/// Appends the source frames of `captured` under a `task started by:` line.
#[cfg(not(test))]
fn describe_started(out: &mut Vec<u8>, captured: &[usize]) {
    let mark = out.len();
    out.extend_from_slice(b"\n  task started by:");
    let header = out.len();
    describe_with(out, |_, visit| {
        for &ret in captured {
            if !visit(ret) {
                break;
            }
        }
    });
    if out.len() == header {
        out.truncate(mark);
    }
}

/// Appends `file:line in name` lines for the source frames found from `fp`.
fn describe_frames(out: &mut Vec<u8>, fp: usize) {
    // SAFETY: `fp` comes from `frame_pointer()` of the faulting thread.
    describe_with(out, |t, visit| unsafe {
        walk_fault_frames(fp, fault_vec as *const () as usize, t, visit)
    });
}

/// Appends `file:line in name` lines for the source frames `drive` visits, innermost first.
fn describe_with(out: &mut Vec<u8>, drive: impl FnOnce(&Tables, &mut dyn FnMut(usize) -> bool)) {
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
    {
        drive(t, &mut |ret| {
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
                if line == 0 {
                    // A thunk inlined into its caller has no position of its own.
                } else if (file, line, name) == last {
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
        cancel_flag().store(0, Ordering::Relaxed);
        f(arg);
        *SHIELD.ptr() -= 1;
        if *SHIELD.ptr() == 0 {
            cancel_flag().store(unshielded_cancel_flag(), Ordering::Relaxed);
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
        cancel_flag().store(0, Ordering::Relaxed);
    }
}

/// Ends one `msrt_shield_enter`; a stop request that arrived meanwhile applies again.
#[unsafe(no_mangle)]
pub extern "C" fn msrt_shield_exit() {
    // SAFETY: single threaded access to the shield counter.
    unsafe {
        *SHIELD.ptr() = (*SHIELD.ptr()).saturating_sub(1);
        if *SHIELD.ptr() == 0 {
            cancel_flag().store(unshielded_cancel_flag(), Ordering::Relaxed);
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

crate::isolate_static! {
    static PRIMARY: Option<Vec<u8>> = None;
}
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

/// Reports a fault that left a guarded task (its cleanups already ran) and ends the process
/// with the fault status. A no-op under the unit-test runtime, which keeps faults as panics.
pub fn exit_with_report(msg: &ms_rt_abi::StrVal, started: &[usize]) {
    #[cfg(not(test))]
    {
        // SAFETY: `msg` is a string the guard just produced.
        let mut report = unsafe { core::slice::from_raw_parts(msg.data(), msg.len()) }.to_vec();
        describe_started(&mut report, started);
        report.push(b'\n');
        crate::io::flush_stdout();
        sys::write_all(sys::STDERR, report.as_slice());
        crate::process::exit(ms_rt_abi::EXIT_FAULT)
    }
    #[cfg(test)]
    let _ = (msg, started);
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
pub unsafe extern "C-unwind" fn msrt_fault_string(s: *const ms_rt_abi::StrVal) -> ! {
    // SAFETY: caller passes a live string.
    fault(unsafe { crate::string::bytes(s) })
}

/// Lowers the recursion limit so cleanups can run calls in the reserve. A function of its own that
/// returns: the Windows frame walk recovers the faulting frame's `rbp` by unwinding, and a
/// diverging function is free to leave a register it used (here the new limit) unrestored.
#[inline(never)]
fn lower_depth_limit() {
    // SAFETY: single threaded limit change.
    unsafe {
        let lo = *STACK_LO.ptr();
        (*cur_hdr()).limit = if lo == 0 {
            0
        } else {
            lo + STACK_CLEANUP_RESERVE
        };
    }
}

/// Where the generated code was when it hit the depth limit: the return address into it and its
/// `rbp`, saved by the entry shim before any Rust code can reuse the register.
#[cfg(all(windows, target_arch = "x86_64"))]
static mut DEPTH_SITE: [usize; 2] = [0; 2];

#[cfg(all(windows, target_arch = "x86_64", not(test)))]
core::arch::global_asm!(
    ".globl msrt_fault_depth",
    "msrt_fault_depth:",
    "mov rax, [rsp]",
    "mov [rip + {site}], rax",
    "mov [rip + {site} + 8], rbp",
    "jmp {body}",
    site = sym DEPTH_SITE,
    body = sym fault_depth_body,
);

#[cfg(not(all(windows, target_arch = "x86_64", not(test))))]
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_depth() -> ! {
    fault_depth_body()
}

#[inline(always)]
extern "C-unwind" fn fault_depth_body() -> ! {
    lower_depth_limit();
    fault(
        b"stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the recursion for a missing base case, or iterate instead",
    )
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
pub extern "C-unwind" fn msrt_fault_int_range() -> ! {
    fault(b"Int overflow; the result does not fit the sized integer type's range, so bound the operands or use a wider type")
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
    let sig = crate::isolate::pending_cancel();
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
    limit: usize,
    shield: u32,
    eq_pairs: usize,
    /// `jmp` is the register buffer of `expect_fault` (Windows) rather than a guard slot.
    #[cfg_attr(not(windows), allow(dead_code))]
    trap: bool,
}

crate::isolate_static! {
    static GUARDS: Vec<GuardFrame> = Vec::new();
}
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
        (*cur_hdr()).limit = f.limit;
        *SHIELD.ptr() = f.shield;
        cancel_flag().store(
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
            crate::string::NO_STR
        };
        drop(message);
        guard_jump(f.jmp as *mut usize, status as usize)
    }
}

/// Opens a guard frame for `expect_fault`, whose registers are saved in `buf`.
///
/// # Safety
/// Single threaded; paired with [`pop_trap_guard`] or a fault that leaves through it.
#[cfg(windows)]
pub(crate) unsafe fn push_trap_guard(buf: *mut usize) {
    // SAFETY: single threaded runtime state.
    unsafe {
        (*GUARDS.ptr()).push(GuardFrame {
            jmp: buf as usize,
            cleanups: (*CLEANUPS.ptr()).len(),
            limit: (*cur_hdr()).limit,
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
#[cfg(windows)]
pub(crate) unsafe fn pop_trap_guard() {
    // SAFETY: single threaded runtime state.
    unsafe {
        (*GUARDS.ptr()).pop();
    }
}

#[cfg(not(test))]
static mut GUARD_MESSAGE: ms_rt_abi::StrVal = crate::string::NO_STR;

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
    msg_out: *mut ms_rt_abi::StrVal,
) -> u8 {
    // SAFETY: single threaded runtime state; the frame is popped before returning.
    unsafe {
        if !msg_out.is_null() {
            *msg_out = crate::string::NO_STR;
        }
        let mut slot: usize = 0;
        (*GUARDS.ptr()).push(GuardFrame {
            jmp: core::ptr::addr_of_mut!(slot) as usize,
            cleanups: (*CLEANUPS.ptr()).len(),
            limit: (*cur_hdr()).limit,
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
                *msg_out = core::ptr::read(&raw const GUARD_MESSAGE);
            } else {
                let held = &raw const GUARD_MESSAGE;
                crate::string::release_opt(&*held);
            }
            GUARD_MESSAGE = crate::string::NO_STR;
            r as u8
        }
        #[cfg(test)]
        {
            let limit = (*cur_hdr()).limit;
            let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| code(data)));
            (*GUARDS.ptr()).pop();
            match r {
                Ok(()) => GUARD_OK,
                Err(e) => {
                    let Ok(p) = e.downcast::<crate::testutil::FaultPayload>() else {
                        fatal(b"unexpected panic in guard")
                    };
                    *FAULTING.ptr() = false;
                    (*cur_hdr()).limit = limit;
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

    static LOG: Process<[u8; 8]> = Process::new([0; 8]);
    static LOG_N: Process<usize> = Process::new(0);

    #[test]
    fn native_frame_budget_counts_only_callers_after_the_anchor() {
        let mut budget = NativeFrameBudget::default();
        assert!(budget.visit(false));
        assert_eq!(budget.remaining(), None);
        assert!(budget.visit(true));
        assert_eq!(budget.remaining(), Some(MAX_STACK_WALK_FRAMES));
        assert!(budget.visit(false));
        assert!(budget.visit(false));
        assert_eq!(budget.remaining(), Some(MAX_STACK_WALK_FRAMES - 2));
        for _ in 2..MAX_STACK_WALK_FRAMES {
            assert!(budget.visit(false));
        }
        assert_eq!(budget.remaining(), Some(0));
        assert!(!budget.visit(false));
    }

    #[test]
    fn frame_record_skips_stale_slots_to_the_first_valid_record() {
        // [junk, junk, saved fp -> slot 5, return address, caller record...]
        let mut stack = [0usize; 8];
        let ptr = stack.as_mut_ptr();
        let base = ptr.expose_provenance();
        // SAFETY: all writes are inside the array.
        unsafe {
            *ptr = 0x1;
            *ptr.add(1) = 0x2;
            *ptr.add(2) = base + 5 * 8;
            *ptr.add(3) = 0x1010;
        }
        let hi = base + 8 * 8;
        // SAFETY: the array outlives the scan and covers `base..hi`.
        let found = unsafe { frame_record(base, base, hi, |pc| pc == 0x1010) };
        assert_eq!(found, Some(base + 2 * 8));
        // SAFETY: as above.
        assert_eq!(unsafe { frame_record(base, base, hi, |_| false) }, None);
    }

    #[test]
    fn source_frame_walk_keeps_deep_recursion_and_stops_at_native_boundary() {
        let mut chain = vec![[0usize, 0x1010usize]; MAX_STACK_WALK_FRAMES + 2];
        let base = chain.as_mut_ptr();
        let len = chain.len();
        // SAFETY: all frame links point inside this one allocation.
        unsafe {
            for index in 0..len - 1 {
                (*base.add(index))[0] = base.add(index + 1).expose_provenance();
            }
        }
        let funcs = [FuncEntry {
            addr: 0x1000,
            size: 0x100,
            name_off: 0,
            file_off: 0,
            line: 1,
        }];
        let tables = Tables {
            abi_version: 1,
            reserved: 0,
            line_scopes: core::ptr::null(),
            scopes: core::ptr::null(),
            scope_count: 0,
            funcs: funcs.as_ptr(),
            func_count: funcs.len(),
            lines: core::ptr::null(),
            line_count: 0,
            strings: core::ptr::null(),
            strings_len: 0,
        };
        let lo = base.expose_provenance();
        let hi = lo + core::mem::size_of_val(chain.as_slice());
        // Two native callers have already consumed the shared raw-frame budget.
        let mut budget = NativeFrameBudget::default();
        assert!(budget.visit(true));
        assert!(budget.visit(false));
        assert!(budget.visit(false));
        for remaining in [0, 1, budget.remaining().unwrap(), MAX_STACK_WALK_FRAMES] {
            let mut count = 0;
            // SAFETY: the synthetic frame chain and tables outlive the walk.
            unsafe {
                walk_source_frames(0x1010, lo, &tables, lo, hi, remaining, |pc| {
                    assert_eq!(pc, 0x1010);
                    count += 1;
                    true
                });
            }
            assert_eq!(count, remaining);
        }
        // A real native boundary ends the source walk before its budget expires.
        // SAFETY: the selected frame is inside the allocation.
        unsafe { (*base.add(200_000))[1] = 0x9999 };
        let mut count = 0;
        // SAFETY: the synthetic frame chain and tables outlive the walk.
        unsafe {
            walk_source_frames(0x1010, lo, &tables, lo, hi, MAX_STACK_WALK_FRAMES, |_| {
                count += 1;
                true
            });
        }
        assert_eq!(count, 200_001);

        // A backward link must terminate without dereferencing it.
        // SAFETY: mutate the first frame inside the same allocation.
        unsafe { (*base)[0] = lo };
        count = 0;
        // SAFETY: the same valid synthetic chain, now ending immediately.
        unsafe {
            walk_source_frames(0x1010, lo, &tables, lo, hi, MAX_STACK_WALK_FRAMES, |_| {
                count += 1;
                true
            });
        }
        assert_eq!(count, 1);
    }

    #[cfg(unix)]
    #[test]
    fn trap_child_reset_preserves_cancellation_shield_and_stack_state() {
        let _lock = lock();
        // Temporarily install an isolated context instead of forking to inspect every field.
        let mut saved = Ctx::new(0, 0);
        let signal = PENDING_SIGNAL.swap(15, Ordering::Relaxed);
        unsafe {
            swap_ctx(&mut saved);
            *SHIELD.ptr() = 2;
            *TASK_CANCEL.ptr() = 1;
            cancel_flag().store(0, Ordering::Relaxed);
            *STACK_LO.ptr() = 100;
            *STACK_HI.ptr() = 1000;
            (*cur_hdr()).limit = 200;
            (*CLEANUPS.ptr()).push((0, 0));
            (*GUARDS.ptr()).push(GuardFrame {
                jmp: 0,
                cleanups: 1,
                limit: 200,
                shield: 2,
                eq_pairs: 1,
                trap: false,
            });
            *FAULTING.ptr() = true;
            *PRIMARY.ptr() = Some(b"inherited".to_vec());
            (*SECONDARY.ptr()).push(b"secondary".to_vec());
            crate::desc::swap_eq_pairs(&mut vec![(1, 2)]);

            isolate_trap_child();

            assert!((*CLEANUPS.ptr()).is_empty());
            assert!((*GUARDS.ptr()).is_empty());
            assert!(!*FAULTING.ptr());
            assert!((*PRIMARY.ptr()).is_none());
            assert!((*SECONDARY.ptr()).is_empty());
            assert_eq!(crate::desc::eq_len(), 0);
            assert_eq!(*SHIELD.ptr(), 2);
            assert_eq!(*TASK_CANCEL.ptr(), 1);
            assert_eq!(PENDING_SIGNAL.load(Ordering::Relaxed), 15);
            assert_eq!(cancel_flag().load(Ordering::Relaxed), 0);
            assert_eq!(*STACK_LO.ptr(), 100);
            assert_eq!(*STACK_HI.ptr(), 1000);
            let limit = (*cur_hdr()).limit;
            assert_eq!(limit, 200);

            PENDING_SIGNAL.store(signal, Ordering::Relaxed);
            swap_ctx(&mut saved);
        }
    }

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
            let mut msg = crate::string::NO_STR;
            let mut data = 1u8;
            assert_eq!(msrt_guard_call(request, &mut data, &mut msg), 1);
            assert!(!msg.ptr_word.is_null());
            assert!(crate::string::bytes(&msg).starts_with(b"handler failed"));
            assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[2]);
            assert_eq!((*CLEANUPS.ptr()).len(), 1);
            let mut ok = 0u8;
            assert_eq!(msrt_guard_call(request, &mut ok, &mut msg), 0);
            assert!(msg.ptr_word.is_null());
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
    fn unordered_tables_are_sorted_by_address() {
        let funcs = [
            FuncEntry {
                addr: 0x3000,
                size: 0x10,
                name_off: 0,
                file_off: 0,
                line: 1,
            },
            FuncEntry {
                addr: 0x1000,
                size: 0x10,
                name_off: 0,
                file_off: 0,
                line: 2,
            },
        ];
        let lines = [
            LineEntry {
                pc: 0x3004,
                line: 10,
                file_off: u32::MAX,
            },
            LineEntry {
                pc: 0x1004,
                line: 20,
                file_off: u32::MAX,
            },
        ];
        let scopes = [7u32, 8];
        let t = Tables {
            abi_version: TABLES_WITH_SCOPES,
            reserved: 0,
            funcs: funcs.as_ptr(),
            func_count: 2,
            lines: lines.as_ptr(),
            line_count: 2,
            strings: core::ptr::null(),
            strings_len: 0,
            line_scopes: scopes.as_ptr(),
            scopes: core::ptr::null(),
            scope_count: 0,
        };
        // SAFETY: valid tables that outlive the call.
        let sorted = unsafe { &*address_ordered_tables(&t) };
        let f = find_func(sorted, 0x1008).expect("function at 0x1000");
        assert_eq!(f.line, 2);
        assert_eq!(find_line(sorted, f, 0x1008), (20, f.file_off, 8));
        let f = find_func(sorted, 0x3008).expect("function at 0x3000");
        assert_eq!(find_line(sorted, f, 0x3008), (10, f.file_off, 7));
    }

    // Windows walks the faulting thread's native CONTEXT, not a frame-pointer chain; the native
    // fault-trace tests in ms-clif cover that walker.
    #[cfg(not(windows))]
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
            "stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the recursion for a missing base case, or iterate instead"
        );
    }
}
