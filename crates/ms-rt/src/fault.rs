//! Faults, the cleanup stack, call depth, cancellation and process exit.
use crate::global::Process;
#[allow(unused_imports)]
use crate::sys;
use core::cell::Cell;
use core::fmt;
use core::sync::atomic::{AtomicU8, Ordering};
use ms_rt_abi::record::{self, FaultKind, Record};
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
    /// Non-zero while a guard (`msrt_guard_call`, `expect_fault`) is open on the task. Generated
    /// code registers drop-only cleanups (see `ms_mir::unwind`) just then: with no guard a fault
    /// or cancellation ends the process, which frees nothing. Sits in the padding after `cancel`.
    pub guarded: AtomicU8,
    /// Nesting depth of the task's stop shields: like `shield`, but only SIGINT/SIGTERM is held
    /// back; a cancel aimed at the task itself (its group closed, its time limit passed) applies.
    /// Sits in the padding after `guarded`, so the block stays 16 bytes.
    pub stop_shield: core::sync::atomic::AtomicU16,
    /// Nesting depth of the task's cancellation shields. A signal handler on any thread reads it
    /// for the main isolate's running task, so it lives here and not in a thread-local.
    pub shield: core::sync::atomic::AtomicU32,
}

impl Hdr {
    pub const fn new(limit: usize) -> Hdr {
        Hdr {
            limit,
            cancel: AtomicU8::new(0),
            guarded: AtomicU8::new(0),
            shield: core::sync::atomic::AtomicU32::new(0),
            stop_shield: core::sync::atomic::AtomicU16::new(0),
        }
    }
}

crate::isolate_static! {
    /// The block of the thread's own flow, used until a task stack is switched to.
    static ROOT_HDR: Hdr = Hdr::new(0);
    /// The running task's block; null before the first switch (the root block then).
    static CUR_HDR: *mut Hdr = core::ptr::null_mut();
}

/// A published header with short, signal-safe reader sections. Publishing a replacement waits
/// for readers that could have observed the old pointer before its stack can be freed or reused.
/// Readers never wait for the owner, so a signal interrupting publication cannot deadlock it.
pub(crate) struct PublishedHdr {
    ptr: core::sync::atomic::AtomicPtr<Hdr>,
    readers: core::sync::atomic::AtomicUsize,
}

impl PublishedHdr {
    pub(crate) const fn new() -> Self {
        Self {
            ptr: core::sync::atomic::AtomicPtr::new(core::ptr::null_mut()),
            readers: core::sync::atomic::AtomicUsize::new(0),
        }
    }

    /// The owner keeps `hdr` alive until a subsequent publication returns.
    pub(crate) fn publish(&self, hdr: *mut Hdr) {
        self.ptr.store(hdr, Ordering::SeqCst);
        while self.readers.load(Ordering::SeqCst) != 0 {
            core::hint::spin_loop();
        }
    }

    pub(crate) fn cancel(&self, sig: u8) {
        // Sequential consistency makes a reader either visible to publication's wait, or
        // observe the replacement pointer. Acquire/release alone permits both to miss.
        self.readers.fetch_add(1, Ordering::SeqCst);
        let hdr = self.ptr.load(Ordering::SeqCst);
        // Pairs with the fence in `unshielded_cancel_flag`: the request recorded before this call
        // and the shield depth read below cannot both miss each other (store-buffering).
        core::sync::atomic::fence(Ordering::SeqCst);
        if !hdr.is_null() {
            // SAFETY: publication cannot finish retiring this header until this reader exits.
            unsafe {
                if (*hdr).shield.load(Ordering::Relaxed) == 0
                    && (*hdr).stop_shield.load(Ordering::Relaxed) == 0
                {
                    (*hdr).cancel.store(sig, Ordering::Relaxed);
                }
            }
        }
        self.readers.fetch_sub(1, Ordering::SeqCst);
    }
}

/// The main isolate's running-task block, for stop-signal handlers that run on any thread.
static MAIN_CUR: PublishedHdr = PublishedHdr::new();

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
    MAIN_CUR.publish(cur_hdr());
}

/// Called by a stop-signal handler on any thread: raises the cancel flag of the main isolate's
/// running task unless it is shielded.
pub fn raise_main_cancel(sig: u8) {
    MAIN_CUR.cancel(sig);
}

/// Publishes the complete context transition, after the scheduler's pair of swaps.
pub(crate) fn publish_current_hdr() {
    if crate::isolate::is_main() {
        MAIN_CUR.publish(cur_hdr());
    } else {
        crate::isolate::publish_hdr(cur_hdr());
    }
    // A request can arrive after swap_ctx refreshed this flag but before publication. Readers
    // that saw the old header are now finished; recover their pending request on the new one.
    if SHIELD.get() == 0 {
        let pending = unshielded_cancel_flag();
        if pending != 0 {
            cancel_flag().fetch_max(pending, Ordering::Relaxed);
        }
    }
}

/// Unpublishes this isolate's header before scheduler teardown releases any task storage.
pub(crate) fn retire_hdr() {
    if crate::isolate::is_main() {
        MAIN_CUR.publish(core::ptr::null_mut());
    } else {
        crate::isolate::publish_hdr(core::ptr::null_mut());
    }
}

/// The cancellation-shield depth of the running task, as a place.
pub(crate) struct ShieldRef;
pub(crate) static SHIELD: ShieldRef = ShieldRef;
impl ShieldRef {
    #[inline(always)]
    pub(crate) fn get(&self) -> u32 {
        // SAFETY: the running task owns this live block; remote readers use atomic loads too.
        unsafe { (*cur_hdr()).shield.load(Ordering::Relaxed) }
    }

    #[inline(always)]
    pub(crate) fn set(&self, value: u32) {
        // SAFETY: only the owning task writes its depth; readers may run on other threads.
        unsafe { (*cur_hdr()).shield.store(value, Ordering::Relaxed) }
    }
}

pub static TABLES: Process<*const Tables> = Process::new(core::ptr::null());
crate::isolate_static! {
    /// Lowest and highest valid stack addresses of the running segment for frame walking (0 =
    /// unknown). Per thread: every scheduler thread runs its own tasks and switches these in
    /// `swap_ctx`, so a process-wide copy let two threads overwrite each other's segments and
    /// close a cycle in the chain cells.
    pub static STACK_LO: usize = 0;
    pub static STACK_HI: usize = 0;
    /// The chain cell of the running task's stack segment: the address of `[lo, hi, chain, 0]`
    /// describing the segment below it, or 0 on a task's home segment. A task that recursed past
    /// its slot runs on further segments (`task::msrt_task_grow`), and a frame walker that leaves
    /// the bounds follows the chain. The cell lives at the top of the segment, written before any
    /// frame exists there, so a signal handler can read it.
    pub static STACK_CHAIN: usize = 0;
}

/// The running segment's bounds and chain cell.
pub(crate) fn segment_state() -> (usize, usize, usize) {
    // SAFETY: reads of the per-task globals on the runtime thread.
    unsafe { (*STACK_LO.ptr(), *STACK_HI.ptr(), *STACK_CHAIN.ptr()) }
}

/// Makes `(lo, hi, chain)` the running segment (`task::msrt_task_grow`, `task::restore_segment`).
pub(crate) unsafe fn set_segment_state((lo, hi, chain): (usize, usize, usize)) {
    // SAFETY: single threaded writes of the per-task globals.
    unsafe {
        *STACK_LO.ptr() = lo;
        *STACK_HI.ptr() = hi;
        *STACK_CHAIN.ptr() = chain;
    }
}

/// Bounds of the segment the frame `fp` is on, following the chain from the current segment's
/// `(lo, hi, chain)` when `fp` is outside it; `None` when no segment holds it. Bounds of 0 mean
/// unknown, which accepts any frame as today.
///
/// # Safety
/// `chain` is 0 or the chain cell of a live segment of the running task.
pub(crate) unsafe fn segment_of(
    fp: usize,
    (lo, hi, chain): (usize, usize, usize),
) -> Option<(usize, usize, usize)> {
    let (mut lo, mut hi, mut chain) = (lo, hi, chain);
    loop {
        if hi == 0 || (fp >= lo && fp.checked_add(16).is_some_and(|end| end <= hi)) {
            return Some((lo, hi, chain));
        }
        if chain == 0 {
            return None;
        }
        // SAFETY: a chain cell is written before frames exist on its segment and stays until
        // the segment is given back, after the frames above it are gone.
        let cell = unsafe { *(chain as *const [usize; 4]) };
        (lo, hi, chain) = (cell[0], cell[1], cell[2]);
    }
}

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

type CleanupFn = unsafe extern "C-unwind" fn(*mut u8);
crate::isolate_static! {
    static CLEANUPS: Vec<(usize, usize)> = Vec::new();
}
pub static PENDING_SIGNAL: AtomicU8 = AtomicU8::new(0);
crate::isolate_static! {
    static FAULTING: bool = false;
}
crate::isolate_static! {
    /// Set while a cancellation or a fault unwinds a guarded task: its frames are abandoned,
    /// so drop cleanups registered by generated code release what the frames own. Per task: another
    /// task that ends while this one's cleanup parks must not clear it.
    static UNWIND_DROPS: bool = false;
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
    // The caller just lowered a shield depth. A concurrent `PublishedHdr::cancel` records its
    // request, fences, then reads the depth; this fence makes either it sees the lowered depth or
    // this read sees the request, so a stop request is never lost between them.
    core::sync::atomic::fence(Ordering::SeqCst);
    // SAFETY: single threaded access.
    let task = unsafe { *TASK_CANCEL.ptr() };
    // SAFETY: the running task's block is live.
    let held = unsafe { (*cur_hdr()).stop_shield.load(Ordering::Relaxed) } > 0;
    let stop = if held {
        0
    } else {
        crate::isolate::pending_cancel()
    };
    stop.max(task)
}

/// Forgets a cancel aimed at the running task, for a task that caught it with a guard and goes on.
/// A stop request (SIGINT/SIGTERM) is not affected.
pub fn acknowledge_cancel() {
    set_live_task_cancel(0)
}

/// Records a stop request aimed at the running task.
pub(crate) fn set_live_task_cancel(v: u8) {
    // SAFETY: single threaded access.
    unsafe {
        *TASK_CANCEL.ptr() = v;
        if SHIELD.get() == 0 {
            cancel_flag().store(unshielded_cancel_flag(), Ordering::Relaxed);
        }
    }
}

/// The cleanup and guard buffers of a task, kept for reuse.
pub(crate) type Spares = (Vec<(usize, usize)>, Vec<GuardFrame>);

/// The per-task slice of runtime state; `task` swaps it on every context switch.
pub(crate) struct Ctx {
    cleanups: Vec<(usize, usize)>,
    guards: Vec<GuardFrame>,
    secondary: Vec<Vec<u8>>,
    eq_pairs: Vec<(usize, usize)>,
    primary: Option<Vec<u8>>,
    faulting: bool,
    unwind_drops: bool,
    /// The task's block (null until set: the root block).
    hdr: *mut Hdr,
    cancel: u8,
    stack_lo: usize,
    stack_hi: usize,
    stack_chain: usize,
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
            unwind_drops: false,
            hdr: core::ptr::null_mut(),
            cancel: 0,
            stack_lo,
            stack_hi,
            stack_chain: 0,
        }
    }

    /// Starts with the cleanup and guard buffers of a finished task, so a new task does not
    /// grow them from empty.
    pub(crate) fn with_spares(mut self, spares: Spares) -> Ctx {
        (self.cleanups, self.guards) = spares;
        self
    }

    /// The emptied cleanup and guard buffers, for the next task to reuse.
    pub(crate) fn take_spares(&mut self) -> Spares {
        self.cleanups.clear();
        self.guards.clear();
        (
            core::mem::take(&mut self.cleanups),
            core::mem::take(&mut self.guards),
        )
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
        unsafe { (*hdr).shield.load(Ordering::Relaxed) > 0 }
    }

    /// Whether the task holds a stop shield.
    pub(crate) fn stop_shielded(&self) -> bool {
        let hdr = if self.hdr.is_null() {
            ROOT_HDR.ptr()
        } else {
            self.hdr
        };
        // SAFETY: the block lives as long as its stack.
        unsafe { (*hdr).stop_shield.load(Ordering::Relaxed) > 0 }
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
    SHIELD.get() > 0
}

/// Exchanges `c` with the live per-task state.
///
/// # Safety
/// Single threaded; callers pair two swaps per context switch, then publish the current header.
pub(crate) unsafe fn swap_ctx(c: &mut Ctx) {
    // SAFETY: single threaded access to the runtime globals.
    unsafe {
        core::ptr::swap(CLEANUPS.ptr(), &mut c.cleanups);
        core::ptr::swap(GUARDS.ptr(), &mut c.guards);
        core::ptr::swap(SECONDARY.ptr(), &mut c.secondary);
        crate::desc::swap_eq_pairs(&mut c.eq_pairs);
        core::ptr::swap(PRIMARY.ptr(), &mut c.primary);
        core::ptr::swap(FAULTING.ptr(), &mut c.faulting);
        core::ptr::swap(UNWIND_DROPS.ptr(), &mut c.unwind_drops);
        core::ptr::swap(CUR_HDR.ptr(), &mut c.hdr);
        core::ptr::swap(TASK_CANCEL.ptr(), &mut c.cancel);
        core::ptr::swap(STACK_LO.ptr(), &mut c.stack_lo);
        core::ptr::swap(STACK_HI.ptr(), &mut c.stack_hi);
        core::ptr::swap(STACK_CHAIN.ptr(), &mut c.stack_chain);
        cancel_flag().store(
            if SHIELD.get() == 0 {
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
    fatal_kind(FaultKind::Fault, msg)
}

/// [`fatal`] for a failure of a specific family, which the structured record names.
pub fn fatal_kind(kind: FaultKind, msg: &[u8]) -> ! {
    #[cfg(test)]
    {
        let _ = kind;
        std::panic::panic_any(crate::testutil::FaultPayload(
            std::string::String::from_utf8_lossy(msg).into_owned(),
        ));
    }
    #[cfg(not(test))]
    {
        crate::io::flush_stdout();
        sys::write_all(sys::STDERR, msg);
        sys::write_all(sys::STDERR, b"\n");
        write_record(&Record::new(kind, msg));
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
    let mut seg = segment_state();
    let mut steps = 0usize;
    while fp != 0 && fp.is_multiple_of(8) && steps < MAX_STACK_WALK_FRAMES {
        // SAFETY: the chain belongs to the running task.
        let Some(bounds) = (unsafe { segment_of(fp, seg) }) else {
            break;
        };
        seg = bounds;
        // SAFETY: `fp` is inside the stack bounds (or bounds are unknown and the
        // caller promised a valid chain).
        let (next, ret) = unsafe { (*(fp as *const usize), *((fp + 8) as *const usize)) };
        if ret == 0 || !f(ret) {
            break;
        }
        // Frames go up within a segment; the segment below may lie anywhere.
        if next <= fp && (seg.1 == 0 || next >= seg.0) {
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

/// Like [`find_line`], but skips back over ranges with no position to the nearest earlier one.
fn find_line_before(t: &Tables, func: &FuncEntry, pc: usize) -> (u32, u32, u32) {
    if t.lines.is_null() || t.line_count == 0 {
        return (func.line, func.file_off, 0);
    }
    // SAFETY: sorted `line_count` read-only entries.
    let lines = unsafe { core::slice::from_raw_parts(t.lines, t.line_count) };
    let probe = pc.wrapping_sub(1);
    let mut idx = lines.partition_point(|e: &LineEntry| e.pc <= probe);
    while idx > 0 {
        let e = &lines[idx - 1];
        if e.pc < func.addr {
            break;
        }
        if e.line != 0 {
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
        idx -= 1;
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
unsafe fn walk_fault_frames(
    _fp: usize,
    anchor: usize,
    t: &Tables,
    steps: &Cell<usize>,
    f: impl FnMut(usize) -> bool,
) {
    let Some((pc, sp, fp, remaining)) = sys::source_frame(anchor, |pc| find_func(t, pc).is_some())
    else {
        return;
    };
    // The native prefix spends the logical budget as the Unix walker's skipped frames do.
    steps.set(steps.get().min(remaining));
    let (lo, hi) = sys::stack_limits();
    // Generated code does not keep its frame register pointing at its own frame record: Cranelift
    // points `rbp` into a frame by an amount that differs per function, a capture unwinds through
    // the scope runtime, and a cleanup run by cancellation sits on top of the frames it unwound,
    // where the register chain is discontinuous. Find each frame's own record by its contents
    // instead of following the register.
    // SAFETY: `sp` is the live stack pointer of the recovered frame, below `hi`.
    unsafe { walk_scanned_frames((pc, sp, fp), t, lo, hi, remaining, f) }
}

/// Visits the source frames above the one running at `pc` with stack pointer `sp` and frame
/// register `fp` (the `start` triple), finding each frame's record with [`frame_record`]. Ends at the first frame no
/// record leads out of.
///
/// # Safety
/// `sp..hi` is live stack memory.
#[cfg(windows)]
unsafe fn walk_scanned_frames(
    (mut pc, mut sp, mut fp): (usize, usize, usize),
    t: &Tables,
    lo: usize,
    hi: usize,
    remaining: usize,
    mut f: impl FnMut(usize) -> bool,
) {
    for _ in 0..remaining {
        if find_func(t, pc).is_none() || !f(pc) {
            break;
        }
        // SAFETY: forwarded; a found record lies below `hi`.
        let Some(at) = (unsafe {
            frame_record(
                sp,
                fp,
                lo,
                hi,
                |pc| find_func(t, pc).is_some(),
                sys::has_unwind_info,
            )
        }) else {
            break;
        };
        // SAFETY: `frame_record` checked `at + 16 <= hi`.
        (fp, pc) = unsafe { (*(at as *const usize), *((at + 8) as *const usize)) };
        sp = at + 16;
    }
}

/// The address of the first frame record `[saved fp, return address]` at or above the frame's
/// frame register `fp` (or `sp` when `fp` is not inside the stack above it) whose return address
/// `is_source` accepts and whose saved fp lies further up the stack.
///
/// Cranelift points the frame register at or below its frame record, never above, so words below
/// `fp` are locals and stale values, not records. Where the register points at the record itself
/// (every frame up to a few hundred bytes), a record returning into native code (`is_native`) is a
/// native caller, such as a callback's shim, and ends the walk. Above `fp` in a larger frame,
/// locals can still look like records, so only a source return address counts there.
///
/// # Safety
/// `sp..hi` is live stack memory.
#[cfg(any(windows, test))]
unsafe fn frame_record(
    sp: usize,
    fp: usize,
    lo: usize,
    hi: usize,
    mut is_source: impl FnMut(usize) -> bool,
    mut is_native: impl FnMut(usize) -> bool,
) -> Option<usize> {
    let from_fp = fp >= sp && fp < hi && fp.is_multiple_of(8);
    let first = if from_fp { fp } else { sp.checked_add(7)? & !7 };
    let last = first
        .checked_add(FRAME_RECORD_SCAN)?
        .min(hi.checked_sub(16)?);
    let mut at = first;
    while at <= last {
        if at >= lo {
            // SAFETY: `at + 16 <= hi` within the live stack.
            let (next, ret) = unsafe { (*(at as *const usize), *((at + 8) as *const usize)) };
            if next > at && next.is_multiple_of(8) && next < hi {
                if is_source(ret) {
                    return Some(at);
                }
                if from_fp && at == fp && is_native(ret) {
                    return None;
                }
            }
        }
        at += 8;
    }
    None
}

#[cfg(test)]
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
unsafe fn walk_fault_frames(
    fp: usize,
    _anchor: usize,
    _t: &Tables,
    _steps: &Cell<usize>,
    f: impl FnMut(usize) -> bool,
) {
    // SAFETY: forwarded live frame-pointer chain.
    unsafe { walk_frames(fp, f) }
}

/// Source frames, innermost first; identical consecutive frames (deep recursion) collapse into one
/// with a count.
#[derive(Default)]
struct Frames {
    list: Vec<record::Frame>,
    truncated: bool,
}

impl Frames {
    /// Appends `\n  at file:line in function` lines, the repeat notes and the omission note.
    fn render(&self, out: &mut Vec<u8>) {
        for frame in &self.list {
            out.extend_from_slice(b"\n  at ");
            out.extend_from_slice(frame.file.as_bytes());
            out.push(b':');
            crate::num::push_i64(out, i64::from(frame.line));
            out.extend_from_slice(b" in ");
            out.extend_from_slice(frame.function.as_bytes());
            if frame.repeated > 0 {
                out.extend_from_slice(b"\n  ... previous frame repeated ");
                crate::num::push_i64(out, i64::from(frame.repeated));
                out.extend_from_slice(b" more times");
            }
        }
        if self.truncated {
            out.extend_from_slice(b"\n  ... outer frames omitted");
        }
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
    // Typical depth; growing from empty reallocates three times per promise started.
    let mut out = Vec::with_capacity(16);
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
            &Cell::new(MAX_STACK_WALK_FRAMES),
            |ret| {
                out.push(ret);
                out.len() < 2 * MAX_FAULT_FRAMES
            },
        );
    }
    out
}

/// The source frames of `captured`, the return addresses a task was started from.
#[cfg(not(test))]
fn started_frames(captured: &[usize]) -> Frames {
    collect_with(|_, visit, _| {
        for &ret in captured {
            if !visit(ret) {
                break;
            }
        }
    })
}

/// The source frames found from `fp`.
fn collect_frames(fp: usize) -> Frames {
    // SAFETY: `fp` comes from `frame_pointer()` of the faulting thread.
    collect_with(|t, visit, steps| unsafe {
        walk_fault_frames(fp, fault_vec as *const () as usize, t, steps, visit)
    })
}

/// The source frames `drive` visits, innermost first.
fn collect_with(
    drive: impl FnOnce(&Tables, &mut dyn FnMut(usize) -> bool, &Cell<usize>),
) -> Frames {
    let mut frames = Frames::default();
    // SAFETY: tables pointer is set once at start.
    let t = unsafe { *TABLES.ptr() };
    if t.is_null() {
        return frames;
    }
    // SAFETY: non-null table installed by `msrt_start`.
    let t = unsafe { &*t };
    let mut innermost = true;
    // The walk is bounded by logical frames, so inlining a callee into its caller does not
    // change how deep a report reaches: each inlined frame spends a step like a physical one.
    let steps = Cell::new(MAX_STACK_WALK_FRAMES);
    drive(
        t,
        &mut |ret| {
            let Some(func) = find_func(t, ret) else {
                steps.set(steps.get().saturating_sub(1));
                return steps.get() > 0;
            };
            let (mut line, mut file, mut scope) = find_line(t, func, ret);
            // The frame that raised the fault may sit in a call without a position of its own;
            // it takes the nearest earlier line.
            if line == 0 && innermost {
                (line, file, scope) = find_line_before(t, func, ret);
            }
            innermost = false;
            // Compiler-generated glue (function-value thunks) has no source position.
            if line == 0 {
                steps.set(steps.get().saturating_sub(1));
                return steps.get() > 0;
            }
            // Frames of inlined callees, innermost first, then the physical function.
            let mut name = func.name_off;
            loop {
                if steps.get() == 0 {
                    return false;
                }
                steps.set(steps.get() - 1);
                let next = scope_entry(t, scope);
                if let Some(sc) = &next {
                    name = sc.name_off;
                    if sc.file_off != u32::MAX {
                        file = sc.file_off;
                    }
                }
                if line == 0 {
                    // A thunk inlined into its caller has no position of its own.
                } else if frames.list.last().is_some_and(|f| {
                    // By text: an inlined copy of a function names itself by another table offset.
                    f.line == line
                        && f.function.as_bytes() == cstr(t, name)
                        && f.file.as_bytes() == cstr(t, file)
                }) {
                    if let Some(frame) = frames.list.last_mut() {
                        frame.repeated += 1;
                    }
                } else {
                    if frames.list.len() == MAX_FAULT_FRAMES {
                        frames.truncated = true;
                        return false;
                    }
                    frames.list.push(record::Frame {
                        file: String::from_utf8_lossy(cstr(t, file)).into_owned(),
                        line,
                        function: String::from_utf8_lossy(cstr(t, name)).into_owned(),
                        repeated: 0,
                    });
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
        },
        &steps,
    );
    frames
}

/// Runs `f(arg)` with cancellation shielded.
fn run_shielded(f: CleanupFn, arg: *mut u8) {
    // SAFETY: single threaded access to the shield counter; the action was
    // registered by generated code with a valid function pointer.
    unsafe {
        SHIELD.set(SHIELD.get() + 1);
        cancel_flag().store(0, Ordering::Relaxed);
        f(arg);
        SHIELD.set(SHIELD.get() - 1);
        if SHIELD.get() == 0 {
            cancel_flag().store(unshielded_cancel_flag(), Ordering::Relaxed);
        }
    }
}

/// Shields the running task from stop requests until the matching `msrt_shield_exit`, for
/// work that must drain after SIGINT/SIGTERM (a server finishing in-flight requests).
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C" fn msrt_shield_enter() {
    SHIELD.set(SHIELD.get() + 1);
    cancel_flag().store(0, Ordering::Relaxed);
}

/// Ends one `msrt_shield_enter`; a stop request that arrived meanwhile applies again.
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C" fn msrt_shield_exit() {
    SHIELD.set(SHIELD.get().saturating_sub(1));
    if SHIELD.get() == 0 {
        cancel_flag().store(unshielded_cancel_flag(), Ordering::Relaxed);
    }
}

/// Holds back SIGINT/SIGTERM from the running task until the matching [`stop_shield_exit`],
/// while a cancel aimed at the task itself still applies. A request handler uses it to finish
/// within the server's grace period.
pub fn stop_shield_enter() {
    // SAFETY: the running task's block is live.
    unsafe { (*cur_hdr()).stop_shield.fetch_add(1, Ordering::Relaxed) };
    if SHIELD.get() == 0 {
        cancel_flag().store(unshielded_cancel_flag(), Ordering::Relaxed);
    }
}

/// Ends one [`stop_shield_enter`]; a stop request that arrived meanwhile applies again.
pub fn stop_shield_exit() {
    // SAFETY: the running task's block is live.
    let _ = unsafe {
        (*cur_hdr())
            .stop_shield
            .try_update(Ordering::Relaxed, Ordering::Relaxed, |n| n.checked_sub(1))
    };
    if SHIELD.get() == 0 {
        cancel_flag().store(unshielded_cancel_flag(), Ordering::Relaxed);
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
        // A permanently retired interior entry has no action, but still counts as progress
        // so unwinding continues to the next live registration or its guard boundary.
        Some((0, _)) => true,
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

/// The full fault path: trace, cleanups LIFO, report, exit 67.
#[cold]
#[inline(never)]
pub fn fault(msg: &[u8]) -> ! {
    let mut report = Vec::with_capacity(msg.len() + 256);
    report.extend_from_slice(msg);
    fault_vec(report)
}

/// [`fault`] for a fault of a specific family, which the structured record names.
// Inlined so it adds no stack frame: the report's repeat count is bounded by the frame walk
// budget, and a fault at the recursion limit counts every frame between it and the fault.
#[inline(always)]
pub fn fault_kind(kind: FaultKind, msg: &[u8]) -> ! {
    // SAFETY: single threaded access to the fault state.
    unsafe { *NEXT_KIND.ptr() = kind };
    fault(msg)
}

/// [`fault_fmt`] for a fault of a specific family.
#[cold]
pub fn fault_fmt_kind(kind: FaultKind, args: fmt::Arguments) -> ! {
    // SAFETY: single threaded access to the fault state.
    unsafe { *NEXT_KIND.ptr() = kind };
    fault_fmt(args)
}

crate::isolate_static! {
    /// The family of the fault being raised, set by [`fault_kind`] just before [`fault_vec`].
    static NEXT_KIND: FaultKind = FaultKind::Fault;
}

/// The structured record of the last fault raised in the process: the CLI reads it through the
/// side channel instead of parsing the text on standard error.
static LAST_RECORD: std::sync::Mutex<Option<Record>> = std::sync::Mutex::new(None);

/// Writes `record` to the file named by `MS_FAULT_RECORD`, when there is one.
pub fn write_record(record: &Record) {
    if let Some(path) = std::env::var_os(record::RECORD_ENV) {
        let mut record = record.clone();
        record.pid = std::process::id();
        let _ = std::fs::write(path, record.encode());
    }
}

/// The structured record of the fault whose message `msg` a guard just handed over, when it is
/// still the last one raised (another thread's fault may have replaced it).
pub fn take_record(msg: &ms_rt_abi::StrVal) -> Option<Record> {
    // SAFETY: `msg` is a string the guard just produced.
    let text = unsafe { core::slice::from_raw_parts(msg.data(), msg.len()) };
    let mut last = LAST_RECORD.lock().ok()?;
    if last.as_ref().is_some_and(|r| text.starts_with(&r.message)) {
        return last.take();
    }
    None
}

/// Writes the last fault's record for the report `text` just printed. A record that does not
/// describe `text` (an earlier recovered fault) is replaced by one holding only the text.
#[cfg(not(test))]
fn write_last_record(text: &[u8], started: Frames) {
    let taken = LAST_RECORD.lock().ok().and_then(|mut r| r.take());
    let mut record = match taken {
        Some(r) if text.starts_with(&r.message) => r,
        _ => Record::new(FaultKind::Fault, text),
    };
    record.frames.extend(started.list);
    write_record(&record);
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
            *NEXT_KIND.ptr() = FaultKind::Fault;
            (*SECONDARY.ptr()).push(report);
            while run_one_cleanup() {}
            finish_report(None)
        }
        *FAULTING.ptr() = true;
    }
    let frames = collect_frames(frame_pointer());
    // SAFETY: single threaded access to the fault state.
    let kind = unsafe { core::mem::replace(&mut *NEXT_KIND.ptr(), FaultKind::Fault) };
    let mut record = Record::new(kind, &report);
    record.frames.clone_from(&frames.list);
    record.truncated = frames.truncated;
    frames.render(&mut report);
    if let Ok(mut last) = LAST_RECORD.lock() {
        *last = Some(record);
    }
    // SAFETY: single threaded; a fault inside a cleanup action finishes this report.
    unsafe { *PRIMARY.ptr() = Some(report) };
    #[cfg(not(test))]
    // SAFETY: single threaded access. A fault that leaves a guarded task abandons its frames,
    // so drop cleanups release what they own; an unguarded fault ends the process.
    unsafe {
        *UNWIND_DROPS.ptr() = guard_active();
    }
    while run_one_cleanup() {}
    finish_report(None)
}

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
            #[cfg(not(test))]
            if let Ok(mut last) = LAST_RECORD.lock()
                && let Some(record) = last.as_mut()
            {
                record.cleanup_faults.push(message);
            }
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
        report.push(b'\n');
        crate::io::flush_stdout();
        sys::write_all(sys::STDERR, report.as_slice());
        write_last_record(&report, Frames::default());
        crate::process::exit(ms_rt_abi::EXIT_FAULT)
    }
}

/// The text of a fault that left a guarded task: its message and the frames that started it.
pub fn fault_report(msg: &ms_rt_abi::StrVal, started: &[usize]) -> Vec<u8> {
    // SAFETY: `msg` is a string the guard just produced.
    let report = unsafe { core::slice::from_raw_parts(msg.data(), msg.len()) }.to_vec();
    #[cfg(not(test))]
    let report = {
        let mut report = report;
        render_started(&mut report, &started_frames(started));
        report
    };
    #[cfg(test)]
    let _ = started;
    report
}

/// Appends the frames a task was started from under a `task started by:` line.
#[cfg(not(test))]
fn render_started(out: &mut Vec<u8>, started: &Frames) {
    if !started.list.is_empty() {
        out.extend_from_slice(b"\n  task started by:");
        started.render(out);
    }
}

/// Reports a fault that left a guarded task (its cleanups already ran) and ends the process
/// with the fault status. A no-op under the unit-test runtime, which keeps faults as panics.
pub fn exit_with_report(msg: &ms_rt_abi::StrVal, started: &[usize]) {
    #[cfg(not(test))]
    {
        // SAFETY: `msg` is a string the guard just produced.
        let mut report = unsafe { core::slice::from_raw_parts(msg.data(), msg.len()) }.to_vec();
        let started = started_frames(started);
        let text = report.clone();
        render_started(&mut report, &started);
        report.push(b'\n');
        crate::io::flush_stdout();
        sys::write_all(sys::STDERR, report.as_slice());
        write_last_record(&text, started);
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
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_fault_string(s: *const ms_rt_abi::StrVal) -> ! {
    // SAFETY: caller passes a live string.
    fault(unsafe { crate::string::bytes(s) })
}

#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_fault_depth() -> ! {
    // SAFETY: single threaded limit change so cleanups can run calls in the reserve.
    unsafe {
        let lo = *STACK_LO.ptr();
        (*cur_hdr()).limit = if lo == 0 {
            0
        } else {
            lo + STACK_CLEANUP_RESERVE
        };
        crate::task::publish_limit();
    }
    fault_kind(
        FaultKind::StackOverflow,
        b"stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the recursion for a missing base case, or iterate instead",
    )
}

#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_index_fault(index: i64, length: i64) -> ! {
    fault_fmt_kind(
        FaultKind::IndexOutOfRange,
        format_args!(
            "index {index} out of range for length {length}; pass a default: get(index:, default: ...)"
        ),
    )
}

/// Faults for an invalid index of a list mutator over `len` elements; `operation` is 0 for
/// `insert` (which also accepts `len`), 1 for `remove` and 2 for `set`.
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_list_index_fault(operation: i64, index: i64, len: i64) -> ! {
    let (name, hi) = match operation {
        0 => ("List.insert", len),
        1 => ("List.remove", len - 1),
        3 => ("List.swap", len - 1),
        4 => ("List.replace", len - 1),
        _ => ("List.set", len - 1),
    };
    if operation != 0 && len == 0 {
        fault_fmt_kind(
            FaultKind::IndexOutOfRange,
            format_args!("{name}: index has no valid value for an empty collection, found {index}"),
        )
    }
    fault_fmt_kind(
        FaultKind::IndexOutOfRange,
        format_args!(
            "{name}: index must be between {} and {hi} (negative indexes count from the end), found {index}",
            -len
        ),
    )
}

#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_fault_unwrap_none() -> ! {
    fault(
        b"called Optional.get() on none; check is_some first, or pass a default: get(default: ...)",
    )
}

#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_fault_result_get() -> ! {
    fault(b"called Result.get() on error; check is_ok first, or pass a default: get(default: ...)")
}

#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_fault_result_err() -> ! {
    fault(b"called Result.err() on ok; check is_error first")
}

#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_fault_int_overflow() -> ! {
    fault_kind(FaultKind::Overflow, b"Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt")
}

#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_fault_int_range() -> ! {
    fault_kind(FaultKind::Overflow, b"Int overflow; the result does not fit the sized integer type's range, so bound the operands or use a wider type")
}

#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_fault_div_zero() -> ! {
    fault_kind(
        FaultKind::DivisionByZero,
        b"division by zero; right must be nonzero, found 0",
    )
}

#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_fault_rem_zero() -> ! {
    fault_kind(
        FaultKind::DivisionByZero,
        b"remainder by zero; right must be nonzero, found 0",
    )
}

#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_fault_div_overflow(a: i64, b: i64) -> ! {
    fault_fmt_kind(
        FaultKind::Overflow,
        format_args!(
            "division overflow; found left {a} and right {b}; result must be between {} and {}",
            i64::MIN,
            i64::MAX
        ),
    )
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_cleanup_push(f: CleanupFn, arg: *mut u8) -> usize {
    // SAFETY: single threaded access to the cleanup stack.
    unsafe {
        let s = &mut *CLEANUPS.ptr();
        s.push((f as usize, arg as usize));
        s.len()
    }
}

/// Whether the current task has registered cleanups.
#[inline]
pub(crate) fn has_cleanups() -> bool {
    // SAFETY: the cleanup stack belongs to this isolate and follows the current task.
    unsafe { !(*CLEANUPS.ptr()).is_empty() }
}

/// Runs the action behind `handle` (and newer pending ones first).
#[unsafe(no_mangle)]
// ms: leaf
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
// ms: leaf
pub extern "C-unwind" fn msrt_cleanup_discard(handle: usize) {
    // SAFETY: single threaded access to the cleanup stack.
    unsafe {
        let stack = &mut *CLEANUPS.ptr();
        while stack.len() >= handle && handle > 0 {
            if stack.pop().is_none() {
                break;
            }
        }
        prune_removed_cleanups(stack);
    }
}

/// Removes only final-retirement tombstones from the tail. Cancelled entries reserve their
/// indices until a later discard, so they must never be pruned here.
fn prune_removed_cleanups(stack: &mut Vec<(usize, usize)>) {
    while stack.last().is_some_and(|entry| entry.0 == 0) {
        stack.pop();
    }
}

/// Permanently retires exactly this action without running it or disturbing newer owners.
/// The handle must not be used again: a removed tail index can be reused by the next push.
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_cleanup_remove(handle: usize) {
    // SAFETY: single threaded access to the isolate's cleanup stack. Pushed actions are valid
    // function pointers, so the null action is reserved exclusively for removed entries.
    unsafe {
        let stack = &mut *CLEANUPS.ptr();
        if handle > 0
            && let Some(entry) = stack.get_mut(handle - 1)
        {
            *entry = (0, 0);
            prune_removed_cleanups(stack);
        }
    }
}

unsafe extern "C-unwind" fn cleanup_nothing(_: *mut u8) {}

/// Turns the action behind `handle` into one that does nothing, leaving newer actions in place.
/// The entry stays on the stack until a `msrt_cleanup_discard` of it or of an older one pops it.
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_cleanup_cancel(handle: usize) {
    // SAFETY: single threaded access to the cleanup stack.
    unsafe {
        let stack = &mut *CLEANUPS.ptr();
        if handle > 0
            && let Some(entry) = stack.get_mut(handle - 1)
        {
            *entry = (cleanup_nothing as CleanupFn as usize, 0);
        }
    }
}

/// Whether the cleanup stack is running because a cancellation or a fault leaves a guarded task.
/// Generated drop cleanups act only then: an unguarded fault ends the process and process exit
/// needs no frees.
#[unsafe(no_mangle)]
// ms: leaf domain=unwind
pub extern "C" fn msrt_unwind_drops() -> u8 {
    // SAFETY: single threaded access.
    u8::from(unsafe { *UNWIND_DROPS.ptr() })
}

/// True when a callback may leave through a guard or a registered cleanup, so an operation that
/// owns unpublished state around callbacks must register it for release.
pub(crate) fn rollback_needed() -> bool {
    // SAFETY: the current task's header stays live for this call.
    unsafe {
        (*msrt_isolate_hdr())
            .guarded
            .load(core::sync::atomic::Ordering::Relaxed)
            != 0
            || has_cleanups()
    }
}

/// Runs `cleanup` if cancellation or a fault leaves `body` by a jump (which skips Rust
/// destructors); discards it when `body` returns. Use it around a park that holds a borrow, a
/// busy flag or another guard that later tasks need.
pub fn with_cleanup<R>(cleanup: &mut dyn FnMut(), body: impl FnOnce() -> R) -> R {
    unsafe extern "C-unwind" fn run(arg: *mut u8) {
        // SAFETY: `arg` points at the `&mut dyn FnMut()` below, live until the handle is discarded.
        unsafe { (*arg.cast::<&mut dyn FnMut()>())() }
    }
    let mut cleanup = cleanup;
    // SAFETY: the entry is discarded before `cleanup` goes out of scope.
    let handle = unsafe { msrt_cleanup_push(run, (&raw mut cleanup).cast()) };
    let r = body();
    msrt_cleanup_discard(handle);
    r
}

/// Unwinds on a stop request: runs cleanups and exits 130/143.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cancelled() -> ! {
    let sig = crate::isolate::pending_cancel();
    #[cfg(not(test))]
    // SAFETY: single threaded access.
    unsafe {
        *UNWIND_DROPS.ptr() = guard_active();
    }
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
pub(crate) struct GuardFrame {
    /// Address of the register save slot owned by the `msrt_guard_call` frame.
    jmp: usize,
    cleanups: usize,
    limit: usize,
    /// The stack segment the guard was opened on (`task::current_segment`).
    seg: usize,
    shield: u32,
    eq_pairs: usize,
}

crate::isolate_static! {
    static GUARDS: Vec<GuardFrame> = Vec::new();
}
/// Opens a guard frame and tells generated code the running task is guarded.
///
/// # Safety
/// Single threaded access to the guard stack.
unsafe fn guards_push(frame: GuardFrame) {
    // SAFETY: single threaded runtime state.
    unsafe {
        (*GUARDS.ptr()).push(frame);
        (*cur_hdr()).guarded.store(1, Ordering::Relaxed);
    }
}

/// Closes the innermost guard frame.
///
/// # Safety
/// Single threaded access to the guard stack.
unsafe fn guards_pop() -> Option<GuardFrame> {
    // SAFETY: single threaded runtime state.
    unsafe {
        let g = &mut *GUARDS.ptr();
        let frame = g.pop();
        (*cur_hdr())
            .guarded
            .store(u8::from(!g.is_empty()), Ordering::Relaxed);
        frame
    }
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
        let f = guards_pop().unwrap_or_else(|| fatal(b"runtime invariant: no guard"));
        *FAULTING.ptr() = false;
        *UNWIND_DROPS.ptr() = false;
        crate::dropq::reset();
        (*cur_hdr()).limit = f.limit;
        #[cfg(windows)]
        let teb = crate::task::segment_teb(f.seg);
        crate::task::restore_segment(f.seg);
        crate::task::publish_limit();
        SHIELD.set(f.shield);
        cancel_flag().store(
            if f.shield == 0 {
                unshielded_cancel_flag()
            } else {
                0
            },
            Ordering::Relaxed,
        );
        crate::desc::eq_truncate(f.eq_pairs);
        *GUARD_MESSAGE.ptr() = if status == GUARD_FAULT {
            crate::string::from_bytes(&message)
        } else {
            crate::string::NO_STR
        };
        drop(message);
        #[cfg(windows)]
        guard_jump(f.jmp as *mut usize, status as usize, teb.as_ptr());
        #[cfg(not(windows))]
        guard_jump(f.jmp as *mut usize, status as usize)
    }
}

#[cfg(not(test))]
crate::isolate_static! {
    /// The fault message `guard_exit` hands to the landing of `msrt_guard_call`. Per thread: tasks on
    /// different scheduler threads leave guards at the same time.
    static GUARD_MESSAGE: ms_rt_abi::StrVal = crate::string::NO_STR;
}

#[cfg(not(test))]
unsafe extern "C" {
    /// Saves callee-saved registers and the stack pointer in `*jmp`, calls `code(data)` and
    /// returns 0, or returns the value given to `guard_jump` when that is called later.
    fn msrt_guard_enter(
        jmp: *mut usize,
        code: unsafe extern "C-unwind" fn(*mut u8),
        data: *mut u8,
    ) -> usize;
    #[cfg(not(windows))]
    #[link_name = "msrt_guard_jump"]
    fn guard_jump(jmp: *mut usize, status: usize) -> !;
    /// As above; `teb` holds the three thread environment block stack fields of the stack the
    /// guard frame is on, installed once the stack pointer is there (`task::segment_teb`).
    #[cfg(windows)]
    #[link_name = "msrt_guard_jump"]
    fn guard_jump(jmp: *mut usize, status: usize, teb: *const usize) -> !;
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
    "mov rax, [r8]",
    "mov gs:[0x08], rax",
    "mov rax, [r8 + 8]",
    "mov gs:[0x10], rax",
    "mov rax, [r8 + 16]",
    "mov gs:[0x1478], rax",
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

// AArch64; Windows installs the thread environment block fields from `x2` after the jump.
#[cfg(all(not(test), target_arch = "aarch64"))]
macro_rules! aarch64_guard {
    ($($install:literal),*) => {
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
    $($install,)*
    "mov x0, x1",
    "b 1b",
);
    };
}
#[cfg(all(not(test), target_arch = "aarch64", not(windows)))]
aarch64_guard!();
#[cfg(all(not(test), target_arch = "aarch64", windows))]
aarch64_guard!(
    "ldr x3, [x2]",
    "str x3, [x18, #0x08]",
    "ldr x3, [x2, #8]",
    "str x3, [x18, #0x10]",
    "ldr x3, [x2, #16]",
    "str x3, [x18, #0x1478]"
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
        guards_push(GuardFrame {
            jmp: core::ptr::addr_of_mut!(slot) as usize,
            cleanups: (*CLEANUPS.ptr()).len(),
            limit: (*cur_hdr()).limit,
            seg: crate::task::current_segment(),
            shield: SHIELD.get(),
            eq_pairs: crate::desc::eq_len(),
        });
        #[cfg(not(test))]
        {
            let r = msrt_guard_enter(core::ptr::addr_of_mut!(slot), code, data);
            if r == 0 {
                guards_pop();
                return GUARD_OK;
            }
            if !msg_out.is_null() {
                *msg_out = core::ptr::read(GUARD_MESSAGE.ptr());
            } else {
                crate::string::release_opt(&*GUARD_MESSAGE.ptr());
            }
            *GUARD_MESSAGE.ptr() = crate::string::NO_STR;
            r as u8
        }
        #[cfg(test)]
        {
            let limit = (*cur_hdr()).limit;
            let seg = crate::task::current_segment();
            let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| code(data)));
            guards_pop();
            match r {
                Ok(()) => GUARD_OK,
                Err(e) => {
                    let Ok(p) = e.downcast::<crate::testutil::FaultPayload>() else {
                        fatal(b"unexpected panic in guard")
                    };
                    *FAULTING.ptr() = false;
                    (*cur_hdr()).limit = limit;
                    crate::task::restore_segment(seg);
                    crate::task::publish_limit();
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
        (*cur_hdr()).guarded.store(0, Ordering::Relaxed);
        *FAULTING.ptr() = false;
        SHIELD.set(0);
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
    fn cancellation_during_context_publication_reaches_the_new_task() {
        let _g = crate::testutil::lock();
        std::thread::spawn(|| {
            publish_current_hdr();
            let hdr = Box::into_raw(Box::new(Hdr::new(0)));
            // SAFETY: this thread owns both headers; mimic the gap after the context swaps
            // but before the scheduler publishes its new running task.
            unsafe { *CUR_HDR.ptr() = hdr };
            crate::isolate::raise_cancel(crate::isolate::id(), 1);
            assert_eq!(cancel_flag().load(Ordering::Relaxed), 0);
            publish_current_hdr();
            let delivered = cancel_flag().load(Ordering::Relaxed);
            retire_hdr();
            // SAFETY: all readers are finished and no task runs on the temporary header.
            unsafe {
                *CUR_HDR.ptr() = core::ptr::null_mut();
                drop(Box::from_raw(hdr));
            }
            crate::isolate::unregister();
            assert_eq!(delivered, 1);
        })
        .join()
        .unwrap();
    }

    #[test]
    fn publishing_waits_while_a_reader_is_inside_its_section() {
        let _g = crate::testutil::lock();
        let published = PublishedHdr::new();
        // A reader that has not left: publication must not return, or the old header's stack
        // could be freed under it.
        published.readers.fetch_add(1, Ordering::SeqCst);
        let returned = core::sync::atomic::AtomicBool::new(false);
        std::thread::scope(|scope| {
            scope.spawn(|| {
                published.publish(core::ptr::null_mut());
                returned.store(true, Ordering::SeqCst);
            });
            std::thread::sleep(std::time::Duration::from_millis(100));
            assert!(
                !returned.load(Ordering::SeqCst),
                "publication returned while a reader was still inside its section"
            );
            published.readers.fetch_sub(1, Ordering::SeqCst);
        });
        assert!(returned.load(Ordering::SeqCst));
    }

    #[test]
    fn cancellation_header_retirement_waits_for_readers() {
        let _g = crate::testutil::lock();
        let reader = std::thread::spawn(|| {
            for _ in 0..2000 {
                raise_main_cancel(1);
                std::thread::yield_now();
            }
        });
        for _ in 0..100 {
            let hdr = Box::into_raw(Box::new(Hdr::new(0)));
            MAIN_CUR.publish(hdr);
            std::thread::yield_now();
            MAIN_CUR.publish(core::ptr::null_mut());
            // SAFETY: the header has been unpublished; all prior readers must be finished.
            unsafe { drop(Box::from_raw(hdr)) };
        }
        reader.join().unwrap();
    }

    #[test]
    fn task_header_keeps_the_codegen_layout() {
        fn assert_sync<T: Sync>() {}
        assert_sync::<Hdr>();
        assert_eq!(core::mem::offset_of!(Hdr, limit), 0);
        assert_eq!(
            core::mem::offset_of!(Hdr, cancel),
            ms_rt_abi::symbols::ISOLATE_HDR_CANCEL as usize,
        );
        assert_eq!(
            core::mem::offset_of!(Hdr, guarded),
            ms_rt_abi::symbols::ISOLATE_HDR_GUARDED as usize,
        );
        assert_eq!(core::mem::size_of::<Hdr>(), 16);
        // The region's last 16 bytes: the block's address, then the limit (`STACK_LIMIT_CELL`).
        assert_eq!(ms_rt_abi::symbols::STACK_LIMIT_CELL, 8);
    }

    #[test]
    fn concurrent_shield_updates_and_signal_reads() {
        let _g = lock();
        set_main_hdr();
        let reader = std::thread::spawn(|| {
            for _ in 0..100 {
                raise_main_cancel(2);
                std::thread::yield_now();
            }
        });
        for _ in 0..100 {
            msrt_shield_enter();
            std::thread::yield_now();
            msrt_shield_exit();
        }
        reader.join().unwrap();
        MAIN_CUR.publish(core::ptr::null_mut());
        cancel_flag().store(0, Ordering::Relaxed);
        assert!(!live_shielded());
    }

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
        // [junk, junk, saved fp -> slot 6, return address 0x1010, saved fp -> slot 6, return
        // address 0x2020, ...]
        let mut stack = [0usize; 8];
        let ptr = stack.as_mut_ptr();
        let base = ptr.expose_provenance();
        // SAFETY: all writes are inside the array.
        unsafe {
            *ptr = 0x1;
            *ptr.add(1) = 0x2;
            *ptr.add(2) = base + 6 * 8;
            *ptr.add(3) = 0x1010;
            *ptr.add(4) = base + 6 * 8;
            *ptr.add(5) = 0x2020;
        }
        let hi = base + 8 * 8;
        let at = |fp: usize, source: usize, native: usize| {
            // SAFETY: the array outlives the scan and covers `base..hi`.
            unsafe { frame_record(base, fp, base, hi, |pc| pc == source, |pc| pc == native) }
        };
        // No frame register in range: scan from the stack pointer.
        assert_eq!(at(0, 0x1010, 0), Some(base + 2 * 8));
        assert_eq!(at(0, 0x3030, 0), None);
        // The register points at the record itself: a native return ends the walk there.
        assert_eq!(at(base + 2 * 8, 0x1010, 0x1010), Some(base + 2 * 8));
        assert_eq!(at(base + 2 * 8, 0x2020, 0x1010), None);
        // Above the register, a record-shaped native pair is only a local: keep scanning.
        assert_eq!(at(base, 0x2020, 0x1010), Some(base + 4 * 8));
        // Words below the register are never read as a record.
        assert_eq!(at(base + 4 * 8, 0x1010, 0), None);
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
    fn cleanup_remove_preserves_newer_owners_and_skips_interior_holes_on_fault() {
        let _g = lock();
        reset_for_tests();
        // SAFETY: serialized runtime state and valid test callbacks.
        unsafe {
            *LOG_N.ptr() = 0;
            msrt_cleanup_push(log_action, core::ptr::without_provenance_mut(1));
            let removed = msrt_cleanup_push(log_action, core::ptr::without_provenance_mut(2));
            let newer = msrt_cleanup_push(log_action, core::ptr::without_provenance_mut(3));
            msrt_cleanup_remove(removed);
            assert_eq!((*CLEANUPS.ptr()).len(), newer);
            assert_eq!((&*CLEANUPS.ptr())[removed - 1], (0, 0));
        }
        assert_eq!(
            fault_of(|| fault(b"after transfer")).unwrap(),
            "after transfer"
        );
        // SAFETY: test-only state under the global lock.
        unsafe {
            assert_eq!(&(&*LOG.ptr())[..*LOG_N.ptr()], &[3, 1]);
            assert!((*CLEANUPS.ptr()).is_empty());
        }
    }

    #[test]
    fn cleanup_remove_reclaims_tails_without_reusing_reserved_cancelled_handles() {
        let _g = lock();
        reset_for_tests();
        // SAFETY: serialized runtime state and valid test callbacks.
        unsafe {
            *LOG_N.ptr() = 0;
            let first = msrt_cleanup_push(log_action, core::ptr::without_provenance_mut(1));
            let reserved = msrt_cleanup_push(log_action, core::ptr::without_provenance_mut(2));
            msrt_cleanup_cancel(reserved);
            msrt_cleanup_remove(first);
            assert_eq!((*CLEANUPS.ptr()).len(), reserved);
            let newer = msrt_cleanup_push(log_action, core::ptr::without_provenance_mut(3));
            msrt_cleanup_remove(newer);
            assert_eq!((*CLEANUPS.ptr()).len(), reserved);
            msrt_cleanup_discard(reserved);
            assert!((*CLEANUPS.ptr()).is_empty());
            let reused = msrt_cleanup_push(log_action, core::ptr::without_provenance_mut(4));
            assert_eq!(reused, first);
            msrt_cleanup_run(reused);
            assert_eq!(&(&*LOG.ptr())[..*LOG_N.ptr()], &[4]);
        }
    }

    #[test]
    fn cleanup_remove_is_bounded_across_repeated_temporary_transfers() {
        let _g = lock();
        reset_for_tests();
        // SAFETY: valid no-op callbacks under serialized runtime state.
        unsafe {
            let outer = msrt_cleanup_push(cleanup_nothing, core::ptr::null_mut());
            for _ in 0..10_000 {
                let old = msrt_cleanup_push(cleanup_nothing, core::ptr::null_mut());
                let replacement = msrt_cleanup_push(cleanup_nothing, core::ptr::null_mut());
                msrt_cleanup_remove(old);
                msrt_cleanup_discard(replacement);
                assert_eq!((*CLEANUPS.ptr()).len(), outer);
            }
            msrt_cleanup_remove(outer);
            assert!((*CLEANUPS.ptr()).is_empty());
        }
    }

    #[test]
    fn with_cleanup_runs_when_the_body_leaves_by_a_jump_and_not_after_a_return() {
        let _g = lock();
        reset_for_tests();
        let mut ran = 0;
        let kept = with_cleanup(&mut || ran += 1, || 7);
        assert_eq!((kept, ran), (7, 0));
        // SAFETY: test-only access to the cleanup stack.
        assert!(unsafe { (*CLEANUPS.ptr()).is_empty() });
        let mut ran = 0;
        let left = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            with_cleanup(&mut || ran += 1, || -> i32 { msrt_cancelled() })
        }));
        assert!(left.is_err());
        assert_eq!(ran, 1);
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
        collect_frames(base.expose_provenance()).render(&mut out);
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
