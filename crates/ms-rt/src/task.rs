//! Cooperative tasks: stackful coroutines on the runtime thread, parked on file descriptors
//! and timers.
//!
//! Every task runs on the one runtime thread, so the allocator, reference counts and the
//! other runtime globals stay non-atomic. A task runs until it parks (`msrt_task_wait_fd`,
//! `msrt_task_sleep`, `msrt_task_join`) or yields; there is no preemption. Each task owns a
//! stack, a cleanup stack, a guard stack, a call depth and a cancellation request, which are
//! swapped in and out of the runtime globals on every switch (`fault::Ctx`).
//!
//! A task can also park on a token (`msrt_token_park`): a one-shot slot that code on the runtime
//! thread posts to with `msrt_token_post`, and any other thread with `msrt_token_post_remote`.
use crate::alloc;
use crate::fault::{self, Ctx, cancel_flag};
use crate::isolate;
use crate::sys;
use core::cmp::Reverse;
use core::ptr::null_mut;
use core::sync::atomic::Ordering;
use ms_rt_abi::StrVal;
use ms_rt_abi::record::FaultKind;
use std::collections::{BinaryHeap, VecDeque};

mod api;
mod reactor;
mod records;
mod tokens;

pub use api::*;
pub use reactor::*;
pub(crate) use records::*;
pub use tokens::*;

/// Results of a park, ORed together.
pub const WAIT_READ: u32 = 1;
pub const WAIT_WRITE: u32 = 2;
pub const WAIT_HUP: u32 = 4;
pub const WAIT_TIMEOUT: u32 = 8;
pub const WAIT_CANCELLED: u32 = 16;

/// Cancellation sweep hook for counting builds (`make cancel-sweep`): `MS_CANCEL_AT_PARK=n` makes
/// the n-th park of the process return `WAIT_CANCELLED`, as if the parking task had been
/// cancelled there, and `MS_PARK_COUNT=1` prints how many parks the run made. Both are absent
/// from release builds.
#[cfg(feature = "stats")]
pub mod sweep {
    use core::sync::atomic::{AtomicU64, Ordering};

    static PARKS: AtomicU64 = AtomicU64::new(0);

    std::thread_local! {
        /// The next park of this thread is the scheduler's own (a worker's root task waiting for
        /// work), which no program awaits: it is neither counted nor cancelled. The park takes the
        /// mark as it starts, before any other task runs.
        static INTERNAL: core::cell::Cell<bool> = const { core::cell::Cell::new(false) };
    }

    /// Marks this thread's next park as the scheduler's own; `internal(false)` after it clears a
    /// mark the park did not need to take.
    pub fn internal(on: bool) {
        INTERNAL.with(|i| i.set(on));
    }

    fn target() -> u64 {
        static TARGET: AtomicU64 = AtomicU64::new(u64::MAX);
        static READ: AtomicU64 = AtomicU64::new(0);
        if READ.swap(1, Ordering::Relaxed) == 0 {
            let n = std::env::var("MS_CANCEL_AT_PARK")
                .ok()
                .and_then(|v| v.parse::<u64>().ok())
                .unwrap_or(u64::MAX);
            TARGET.store(n, Ordering::Relaxed);
        }
        TARGET.load(Ordering::Relaxed)
    }

    /// Counts one park; true when this is the park to cancel.
    /// A real cancel stays recorded on the task (and survives shields), so this one does too: code that swallows
    /// the error of a cancelled park then fails at its next park, as it would under a real cancel.
    pub fn cancel_here() -> bool {
        if INTERNAL.with(|i| i.replace(false)) {
            return false;
        }
        let hit = PARKS.fetch_add(1, Ordering::Relaxed) + 1 == target();
        if hit {
            crate::fault::set_live_task_cancel(1);
        }
        hit
    }

    /// Parks made so far.
    pub fn parks() -> u64 {
        PARKS.load(Ordering::Relaxed)
    }
}

#[cfg(not(feature = "stats"))]
pub mod sweep {
    #[inline(always)]
    pub fn cancel_here() -> bool {
        false
    }

    #[inline(always)]
    pub fn internal(_: bool) {}
}
/// Request bit: keep the descriptor registered between waits instead of re-arming it. Only for
/// a descriptor whose owner drains it before every wait and keeps it open for good.
pub const WAIT_KEEP: u32 = 32;

/// `msrt_task_spawn` flag: nobody joins the task; a fault in it ends the process.
pub const SPAWN_DETACHED: u32 = 1;
/// `msrt_task_spawn` flag: a fault in the task ends the process (exit 67) as for a detached
/// task, but the task can still be joined and cancelled.
pub const SPAWN_FATAL: u32 = 2;

/// `msrt_token_new` flag: another thread will post the token, so while it is unposted the
/// scheduler waits for it instead of reporting a deadlock.
pub const TOKEN_REMOTE: u32 = 1;
/// `msrt_token_new` flag, with `TOKEN_REMOTE`: the post comes from code running in another
/// isolate, not from a thread that finishes on its own. When every isolate waits only on such
/// tokens, nothing can wake any of them, which is a deadlock.
pub const TOKEN_PEER: u32 = 2;

/// Stacks live in regions of this size, aligned to it: the stack pointer's high bits name the
/// region, whose last 16 bytes point at the running task's `fault::Hdr` (see `publish_region`).
pub const REGION: usize = ms_rt_abi::symbols::STACK_REGION as usize;
/// A task's stack: `SLOT` bytes of address space in a region, the bottom `GUARD` of them a
/// guard, committed as the stack grows, so an idle task costs one page.
pub const SLOT: usize = 512 << 10;
/// Slots per region; the region's last page holds its cell, so the top slot is left out.
const SLOTS_PER_REGION: usize = (REGION - 4096) / SLOT;
const _: () = assert!(SLOTS_PER_REGION * SLOT + 4096 <= REGION);
/// `msrt_task_spawn` stack request that gives the task a region of its own (the main task).
const ROOT_STACK: usize = REGION;
/// Address space below a stack's lowest usable page that faults when touched.
const GUARD: usize = 64 << 10;
/// Tasks parked for at least this many scheduler idle rounds give their stack pages back.
const HIBERNATE_ROUNDS: u32 = 2;
/// Segments a task may add to its home slot (`msrt_task_grow`): 256 MiB of stack in all, the
/// main task's region.
const MAX_SEGMENTS: usize = REGION / SLOT - 1;
/// Bytes at the top of a grown segment holding the bounds and chain cell of the segment below
/// it, which frame walkers follow (`fault::STACK_CHAIN`).
const CHAIN_CELL: usize = 32;
/// Task slots hibernation freezes between looks for new work, so a wake-up waits for at most
/// this many copies.
const HIBERNATE_SCAN: usize = 4096;
const NO_DEADLINE: i64 = i64::MAX;
const MIN_TIMER_LIMIT: usize = 1024;

#[derive(Clone, Copy, PartialEq, Eq)]
enum State {
    Ready,
    Running,
    Waiting,
    Done,
}

type Entry = unsafe extern "C-unwind" fn(*mut u8);

struct Task {
    handle: u64,
    state: State,
    /// Saved stack pointer while switched out.
    sp: usize,
    ctx: Ctx,
    /// Start of the mapping (guard included); null for the main task.
    stack: *mut u8,
    stack_len: usize,
    entry: Option<Entry>,
    arg: *mut u8,
    detached: bool,
    joiner: u64,
    status: u8,
    msg: StrVal,
    wait_fd: i32,
    wait_events: u32,
    wait_result: u32,
    deadline: i64,
    /// When every park of this task ends in a timeout, whatever limit the park asked for
    /// (`msrt_task_read_limit`), or `NO_DEADLINE`.
    read_limit: i64,
    /// The token this task is parked on, or 0.
    wait_token: u64,
    /// Ends the process when the task faults.
    fatal: bool,
    /// A closure the task holds a reference to, released when the task ends however it ends.
    owned: *mut ms_rt_abi::Obj,
    /// When the task is cancelled for running too long, or `NO_DEADLINE`.
    kill_at: i64,
    /// Frames of the code that started a group task, for the fault report.
    started_by: Vec<usize>,
    /// Set when the task was cancelled because `kill_at` passed.
    timed_out: bool,
    /// The monotonic time by which the deferred promise this task is running must finish
    /// (`msrt_promise_wait` with a timeout), or `i64::MAX`; waits inside it stop there.
    defer_deadline: i64,
    /// The promise this task runs (`promise::msrt_promise_start`), or 0; told when the task ends.
    promise: i64,
    /// The test output capture this task's standard output goes to, or 0 (`msrt_test_capture_set`);
    /// tasks and promises it starts inherit it.
    capture: u64,
    /// The task's block, which generated code reaches through its region's cell.
    hdr: fault::Hdr,
    /// While hibernating: the copy of the stack from `sp` to its top, and its length.
    frozen: *mut u8,
    frozen_len: usize,
    /// The scheduler idle round in which the task parked (see `hibernate_idle`).
    parked_round: u32,
    /// Lends of the task's stack to other threads in progress (`pin_current`): while one is
    /// out, the stack keeps its pages.
    pinned: u32,
    /// The thread environment block's stack fields while the task is switched out.
    #[cfg(windows)]
    teb: [usize; 3],
    /// Stack segments the task grew into (`msrt_task_grow`), slot bases in order; kept until
    /// the task ends, so a loop at a segment boundary allocates nothing.
    segs: Vec<usize>,
    /// The segment the task runs on: 0 is the home slot, `k` is `segs[k - 1]`.
    seg: usize,
    /// For each segment below the current one, the stack pointer it was left at.
    left: Vec<usize>,
    /// The thread environment block's stack fields of each segment below the current one.
    #[cfg(windows)]
    seg_teb: Vec<[usize; 3]>,
}

#[derive(Clone, Copy)]
struct Slot {
    task: *mut Task,
    gen_: u32,
}

/// One park token. Its id is `(generation << 32) | (index + 1)`; a stale id never matches.
struct Token {
    gen_: u32,
    live: bool,
    /// Expects a post from another thread that has not been delivered yet.
    remote: bool,
    /// The pending post comes from another isolate (`TOKEN_PEER`).
    peer: bool,
    /// Handle of the task parked on the token, or 0.
    waiter: u64,
    /// The value of a delivered post that the waiter has not taken yet.
    posted: Option<u64>,
}

struct Sched {
    cur: *mut Task,
    main: *mut Task,
    ready: VecDeque<u64>,
    slots: Vec<Slot>,
    free_slots: Vec<usize>,
    /// Min-heap of (deadline, handle).
    timers: BinaryHeap<Reverse<(i64, u64)>>,
    /// Min-heap of (kill deadline, handle) for tasks started with a time limit.
    kills: BinaryHeap<Reverse<(i64, u64)>>,
    /// Heap size that triggers dropping the entries of tasks that no longer wait on them.
    timer_limit: usize,
    kill_limit: usize,
    /// `fd_waiters[fd]` holds the handles of the tasks waiting on `fd`, oldest first.
    fd_waiters: Vec<Vec<u64>>,
    fd_waiting: usize,
    /// Task switches since the last non-blocking descriptor poll.
    switches_since_poll: u32,
    epfd: i32,
    /// Idle stacks (base, length) kept for reuse; a stack is reused only for the same length.
    pool: Vec<(usize, usize)>,
    /// `pool[..pool_clean]` have given their pages back (see `trim_idle_stacks`).
    pool_clean: usize,
    /// Unused slots of the current region: next slot address and the end.
    carve: (usize, usize),
    /// Every region reserved, released at teardown.
    regions: Vec<usize>,
    /// Idle rounds so far (`reactor_wait` blocking); parks are stamped with it.
    round: u32,
    /// Where the next idle round's hibernation scan starts.
    scan: usize,
    zombie_stack: (usize, usize),
    zombie_task: *mut Task,
    /// Cleanup and guard buffers of finished tasks, for the next spawn.
    spares: Vec<fault::Spares>,
    live: usize,
    /// Flows of control that only wait for the isolate's main task (not tasks of the program).
    waiting_roots: usize,
    tokens: Vec<Token>,
    free_tokens: Vec<usize>,
    /// Live tokens still expecting a post from another thread.
    remote_tokens: usize,
    /// Those of `remote_tokens` that another isolate will post.
    peer_tokens: usize,
}

/// Set in an `fd_waiters` entry that names a promise, not a task (`promise::msrt_promise_ready`).
pub(crate) const PROMISE_TAG: u64 = 1 << 63;

/// What the waiter `h` of a descriptor asks for: a task's park, or a promise's readiness wait.
unsafe fn waiter_events(h: u64) -> u32 {
    if h & PROMISE_TAG != 0 {
        return crate::promise::fd_events((h & !PROMISE_TAG) as i64);
    }
    let t = lookup(h);
    if t.is_null() {
        0
    } else {
        // SAFETY: `t` is a live record.
        unsafe { (*t).wait_events }
    }
}

/// Token generations are 20 bits: the id's high 12 bits name the owning isolate (see `isolate`).
const GEN_MASK: u32 = 0xf_ffff;

crate::isolate_static! {
    static SCHED: Sched = Sched {
    cur: null_mut(),
    main: null_mut(),
    ready: VecDeque::new(),
    slots: Vec::new(),
    free_slots: Vec::new(),
    timers: BinaryHeap::new(),
    kills: BinaryHeap::new(),
    timer_limit: MIN_TIMER_LIMIT,
    kill_limit: MIN_TIMER_LIMIT,
    fd_waiters: Vec::new(),
    fd_waiting: 0,
    switches_since_poll: 0,
    epfd: -1,
    pool: Vec::new(),
    pool_clean: 0,
    carve: (0, 0),
    regions: Vec::new(),
    round: 0,
    scan: 0,
    zombie_stack: (0, 0),
    zombie_task: null_mut(),
    spares: Vec::new(),
    live: 0,
    waiting_roots: 0,
    tokens: Vec::new(),
    free_tokens: Vec::new(),
    remote_tokens: 0,
    peer_tokens: 0,
};
}

/// The scheduler state. Each access derives a fresh short-lived reference from the raw pointer,
/// so a binding held across calls that also reach the scheduler never aliases a live `&mut`.
#[derive(Clone, Copy)]
struct SchedRef(*mut Sched);

impl core::ops::Deref for SchedRef {
    type Target = Sched;

    fn deref(&self) -> &Sched {
        // SAFETY: single threaded runtime state; the reference lasts one expression.
        unsafe { &*self.0 }
    }
}

impl core::ops::DerefMut for SchedRef {
    fn deref_mut(&mut self) -> &mut Sched {
        // SAFETY: as above.
        unsafe { &mut *self.0 }
    }
}

fn sched() -> SchedRef {
    SchedRef(SCHED.ptr())
}

// ---- context switch ----

/// How stacks are created and switched: raw stacks switched with assembly on every platform.
/// On Windows the switch also moves the thread environment block's stack bounds with the stack,
/// so the kernel's guard-page growth and stack walks keep working.
mod stack {
    use super::*;

    unsafe extern "C" {
        /// Saves callee-saved registers on the current stack, stores its pointer in `*save`,
        /// then resumes the stack `next` was saved from.
        #[cfg(not(windows))]
        fn msrt_ctx_switch(save: *mut usize, next: usize);
        /// As above; `teb` holds the three thread environment block stack fields of `next`,
        /// installed once the stack pointer is on `next`. Installing them earlier would let the
        /// saves on the current stack touch its guard page while the block describes another
        /// stack, which the kernel reports as a guard-page violation instead of growing the
        /// stack.
        #[cfg(windows)]
        fn msrt_ctx_switch(save: *mut usize, next: usize, teb: *const usize);
        fn msrt_task_tramp();
        /// Stores the stack pointer in `*save`, runs `f(arg)` on the stack ending at `top`
        /// (16-byte aligned) and comes back; the frame it leaves keeps the frame-pointer chain
        /// continuous across the two stacks.
        #[cfg(not(windows))]
        pub fn msrt_call_on_stack(
            top: usize,
            f: unsafe extern "C-unwind" fn(*mut u8),
            arg: *mut u8,
            save: *mut usize,
        );
        /// As above; `teb` holds six thread environment block stack fields: the new stack's
        /// three, installed once the stack pointer is on it, then the caller's three, put back
        /// once the stack pointer is back (see `msrt_ctx_switch`).
        #[cfg(windows)]
        pub fn msrt_call_on_stack(
            top: usize,
            f: unsafe extern "C-unwind" fn(*mut u8),
            arg: *mut u8,
            save: *mut usize,
            teb: *const usize,
        );
    }

    #[cfg(all(target_arch = "x86_64", not(windows)))]
    core::arch::global_asm!(
        ".text",
        concat!(".globl ", sym!("msrt_ctx_switch")),
        concat!(".globl ", sym!("msrt_task_tramp")),
        concat!(sym!("msrt_ctx_switch"), ":"),
        "push rbp",
        "push rbx",
        "push r12",
        "push r13",
        "push r14",
        "push r15",
        "mov [rdi], rsp",
        "mov rsp, rsi",
        "pop r15",
        "pop r14",
        "pop r13",
        "pop r12",
        "pop rbx",
        "pop rbp",
        "ret",
        concat!(sym!("msrt_task_tramp"), ":"),
        "xor ebp, ebp",
        "call {main}",
        "ud2",
        concat!(".globl ", sym!("msrt_call_on_stack")),
        concat!(sym!("msrt_call_on_stack"), ":"),
        // Frame-pointer based unwind info, so a Rust panic in a test crosses the switch.
        ".cfi_startproc",
        "push rbp",
        ".cfi_def_cfa_offset 16",
        ".cfi_offset rbp, -16",
        "mov rbp, rsp",
        ".cfi_def_cfa_register rbp",
        "mov [rcx], rsp",
        "mov rsp, rdi",
        "mov rdi, rdx",
        "call rsi",
        "mov rsp, rbp",
        "pop rbp",
        ".cfi_def_cfa rsp, 8",
        "ret",
        ".cfi_endproc",
        main = sym super::task_main,
    );

    // Windows x64: arguments in rcx and rdx; rdi, rsi and xmm6-xmm15 are callee-saved too, and
    // a call needs 32 bytes of shadow space.
    #[cfg(all(target_arch = "x86_64", windows))]
    core::arch::global_asm!(
        ".text",
        concat!(".globl ", sym!("msrt_ctx_switch")),
        concat!(".globl ", sym!("msrt_task_tramp")),
        concat!(sym!("msrt_ctx_switch"), ":"),
        "push rbp",
        "push rbx",
        "push rdi",
        "push rsi",
        "push r12",
        "push r13",
        "push r14",
        "push r15",
        "sub rsp, 160",
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
        "mov rsp, rdx",
        "mov rax, [r8]",
        "mov gs:[0x08], rax",
        "mov rax, [r8 + 8]",
        "mov gs:[0x10], rax",
        "mov rax, [r8 + 16]",
        "mov gs:[0x1478], rax",
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
        "add rsp, 160",
        "pop r15",
        "pop r14",
        "pop r13",
        "pop r12",
        "pop rsi",
        "pop rdi",
        "pop rbx",
        "pop rbp",
        "ret",
        concat!(sym!("msrt_task_tramp"), ":"),
        "xor ebp, ebp",
        "sub rsp, 32",
        "call {main}",
        "ud2",
        // The fifth argument (`teb`) is the first stack argument: above the return address and
        // the 32 bytes of shadow space, so at [rbp + 48] once rbp is pushed.
        concat!(".globl ", sym!("msrt_call_on_stack")),
        concat!(sym!("msrt_call_on_stack"), ":"),
        "push rbp",
        "mov rbp, rsp",
        "mov [r9], rsp",
        "mov rsp, rcx",
        "mov rax, [rbp + 48]",
        "mov r10, [rax]",
        "mov gs:[0x08], r10",
        "mov r10, [rax + 8]",
        "mov gs:[0x10], r10",
        "mov r10, [rax + 16]",
        "mov gs:[0x1478], r10",
        "sub rsp, 32",
        "mov rcx, r8",
        "call rdx",
        "mov rsp, rbp",
        "mov rax, [rbp + 48]",
        "mov r10, [rax + 24]",
        "mov gs:[0x08], r10",
        "mov r10, [rax + 32]",
        "mov gs:[0x10], r10",
        "mov r10, [rax + 40]",
        "mov gs:[0x1478], r10",
        "pop rbp",
        "ret",
        main = sym super::task_main,
    );

    // AArch64 (Linux, macOS and Windows share the callee-saved set: x19-x28, x29, x30, d8-d15).
    // Windows installs the thread environment block fields from `x2` after the switch, and in
    // `msrt_call_on_stack` from `x4` (kept in the frame) after each move of the stack pointer.
    #[cfg(target_arch = "aarch64")]
    macro_rules! aarch64_switch {
        ($($install:literal),*; $($enter:literal),*; $($leave:literal),*) => {
    core::arch::global_asm!(
        ".text",
        concat!(".globl ", sym!("msrt_ctx_switch")),
        concat!(".globl ", sym!("msrt_task_tramp")),
        concat!(sym!("msrt_ctx_switch"), ":"),
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
        "mov sp, x1",
        $($install,)*
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
        concat!(sym!("msrt_task_tramp"), ":"),
        "mov x29, #0",
        "bl {main}",
        "brk #0",
        concat!(".globl ", sym!("msrt_call_on_stack")),
        concat!(sym!("msrt_call_on_stack"), ":"),
        ".cfi_startproc",
        "stp x29, x30, [sp, #-32]!",
        ".cfi_def_cfa_offset 32",
        ".cfi_offset x29, -32",
        ".cfi_offset x30, -24",
        "str x4, [sp, #16]",
        "mov x29, sp",
        ".cfi_def_cfa_register x29",
        "mov x9, sp",
        "str x9, [x3]",
        "mov sp, x0",
        $($enter,)*
        "mov x0, x2",
        "blr x1",
        "mov sp, x29",
        $($leave,)*
        "ldp x29, x30, [sp], #32",
        ".cfi_def_cfa sp, 0",
        "ret",
        ".cfi_endproc",
        main = sym super::task_main,
    );
        };
    }
    #[cfg(all(target_arch = "aarch64", not(windows)))]
    aarch64_switch!(;;);
    #[cfg(all(target_arch = "aarch64", windows))]
    aarch64_switch!(
        "ldr x3, [x2]",
        "str x3, [x18, #0x08]",
        "ldr x3, [x2, #8]",
        "str x3, [x18, #0x10]",
        "ldr x3, [x2, #16]",
        "str x3, [x18, #0x1478]";
        "ldr x9, [x4]",
        "str x9, [x18, #0x08]",
        "ldr x9, [x4, #8]",
        "str x9, [x18, #0x10]",
        "ldr x9, [x4, #16]",
        "str x9, [x18, #0x1478]";
        "ldr x9, [sp, #16]",
        "ldr x10, [x9, #24]",
        "str x10, [x18, #0x08]",
        "ldr x10, [x9, #32]",
        "str x10, [x18, #0x10]",
        "ldr x10, [x9, #40]",
        "str x10, [x18, #0x1478]"
    );

    /// Builds the first frame of a new stack so that switching to it enters `msrt_task_tramp`.
    unsafe fn initial_sp(top: usize) -> usize {
        // SAFETY: `top` is the 16-byte aligned end of a writable stack with room for the frame.
        unsafe {
            #[cfg(all(target_arch = "x86_64", not(windows)))]
            {
                // Six saved registers, then the return address; after `ret` the stack pointer is
                // `top`, so the trampoline's `call` sees the ABI alignment.
                let sp = top - 7 * 8;
                let words = sp as *mut usize;
                for i in 0..6 {
                    *words.add(i) = 0;
                }
                *words.add(6) = msrt_task_tramp as *const () as usize;
                sp
            }
            #[cfg(all(target_arch = "x86_64", windows))]
            {
                // Ten vector registers (160 bytes), eight saved registers, the return address.
                let sp = top - 160 - 9 * 8;
                let words = sp as *mut usize;
                for i in 0..28 {
                    *words.add(i) = 0;
                }
                *words.add(28) = msrt_task_tramp as *const () as usize;
                sp
            }
            #[cfg(target_arch = "aarch64")]
            {
                let sp = top - 160;
                let words = sp as *mut usize;
                for i in 0..20 {
                    *words.add(i) = 0;
                }
                *words.add(1) = msrt_task_tramp as *const () as usize;
                sp
            }
        }
    }

    /// Bytes of a fresh stack committed up front where commits are explicit (Windows); the
    /// kernel commits the rest as the stack grows past the guard page below them.
    pub const INITIAL_COMMIT: usize = 8192;

    /// A `REGION`-aligned reservation with its cell page usable, recorded for teardown; null
    /// when address space runs out.
    unsafe fn map_region() -> *mut u8 {
        let base = sys::map_region(REGION);
        if base.is_null() {
            return base;
        }
        if !sys::commit((base as usize + REGION - 4096) as *mut u8, 4096) {
            // SAFETY: the fresh reservation is unused.
            unsafe { sys::unmap(base, REGION) };
            return core::ptr::null_mut();
        }
        sched().regions.push(base as usize);
        base
    }

    /// Reserves a stack of `len` bytes (`SLOT` for a task, `REGION` for a main task): address
    /// space with a guard below its lowest usable page, committed as the stack grows. Null when
    /// nothing is left.
    pub unsafe fn create(len: usize) -> *mut u8 {
        // SAFETY: single threaded scheduler.
        let base = unsafe {
            if len == REGION {
                map_region()
            } else {
                take_slot()
            }
        };
        if base.is_null() {
            return base;
        }
        // SAFETY: the guard range is the unused bottom of the fresh stack.
        if !unsafe { sys::guard(base, GUARD) } {
            // Running unguarded would let an overflow corrupt the neighboring stack: refuse
            // the stack instead. Address space stays reserved for the region's other slots.
            return core::ptr::null_mut();
        }
        base
    }

    /// The next slot: a free one, else the next unused one of the current region, else the
    /// first of a fresh region.
    unsafe fn take_slot() -> *mut u8 {
        let mut s = sched();
        if s.carve.0 == s.carve.1 {
            // SAFETY: single threaded scheduler.
            let base = unsafe { map_region() } as usize;
            if base == 0 {
                return core::ptr::null_mut();
            }
            s.carve = (base, base + SLOTS_PER_REGION * SLOT);
        }
        let slot = s.carve.0;
        s.carve.0 += SLOT;
        slot as *mut u8
    }

    /// Stack bounds and initial context of a stack from [`create`]: `(lowest usable address,
    /// one past the highest, initial stack pointer)`.
    pub unsafe fn prepare(base: *mut u8, len: usize) -> (usize, usize, usize) {
        let top = stack_top(base as usize, len);
        // The top of the stack is reserved address space: Unix commits pages on first touch,
        // Windows needs the first pages committed and a guard page below them.
        if !sys::commit((top - INITIAL_COMMIT) as *mut u8, INITIAL_COMMIT)
            || !sys::commit_guard((top - INITIAL_COMMIT - 4096) as *mut u8)
        {
            fault::fatal(b"cannot commit a task stack");
        }
        // SAFETY: the first pages are usable.
        unsafe { (base as usize + GUARD, top, initial_sp(top)) }
    }

    /// The first task record of the thread needs no stack of its own.
    pub unsafe fn adopt_thread() -> usize {
        0
    }

    pub unsafe fn switch(cur: *mut Task, next: *mut Task) {
        // SAFETY: both records are live; `next` was prepared or saved by a previous switch.
        unsafe {
            #[cfg(windows)]
            {
                (*cur).teb = sys::teb_stack();
                msrt_ctx_switch(&mut (*cur).sp, (*next).sp, (*next).teb.as_ptr())
            }
            #[cfg(not(windows))]
            msrt_ctx_switch(&mut (*cur).sp, (*next).sp)
        }
    }
}

/// One past the highest stack address of a stack at `base` with `len` bytes: a main task's
/// region keeps its last page for the region cell; a slot ends where the next begins.
fn stack_top(base: usize, len: usize) -> usize {
    if len == REGION {
        base + REGION - 4096
    } else {
        base + len
    }
}

/// The cell of the region holding `sp`, which generated code reads to find the running task's
/// block (see `ms_rt_abi::symbols::ISOLATE_HDR`).
fn region_cell(sp: usize) -> *mut *mut fault::Hdr {
    ((sp & !(REGION - 1)) + REGION - 16) as *mut *mut fault::Hdr
}

/// The word of the region holding `sp` that holds the running stack segment's recursion limit,
/// one load from the masked stack pointer (see `ms_rt_abi::symbols::STACK_LIMIT_CELL`).
fn region_limit_cell(sp: usize) -> *mut usize {
    ((sp & !(REGION - 1)) + REGION - 8) as *mut usize
}

/// Points the region of `t`'s stack at `t`'s block and recursion limit, so code running on it
/// finds them. Each segment of the task has its own limit; the one it runs on is `hdr.limit`.
unsafe fn publish_region(t: *mut Task) {
    // SAFETY: `t` is live and has a stack; the cell page is committed on first use.
    unsafe {
        if (*t).stack.is_null() {
            return;
        }
        // Returning into a lower segment runs code there too.
        for k in 0..=(*t).seg {
            let base = if k == 0 {
                (*t).stack as usize
            } else {
                *(*t).segs.as_ptr().add(k - 1)
            };
            region_cell(base).write(&mut (*t).hdr);
            let limit = if k == (*t).seg {
                (*t).hdr.limit
            } else {
                let (lo, top, _) = segment_bounds(t, k);
                fault::stack_limit(lo, top)
            };
            region_limit_cell(base).write(limit);
        }
    }
}

/// Copies the running task's recursion limit to the cell of the stack segment it is on. Called
/// after `hdr.limit` changes or the segment does.
pub(crate) fn publish_limit() {
    // SAFETY: single threaded scheduler; the task's stack and segments are live.
    unsafe {
        let cur = ensure_init();
        if (*cur).stack.is_null() {
            return;
        }
        let base = match (*cur).seg {
            0 => (*cur).stack as usize,
            k => *(*cur).segs.as_ptr().add(k - 1),
        };
        region_limit_cell(base).write((*cur).hdr.limit);
    }
}

/// Bounds of segment `k` of `t`: lowest usable address, one past the highest, and the chain cell
/// generated code's frame walkers follow to the segment below (0 on the home slot).
unsafe fn segment_bounds(t: *mut Task, k: usize) -> (usize, usize, usize) {
    // SAFETY: `t` is live and `k` is one of its segments.
    unsafe {
        if k == 0 {
            let base = (*t).stack as usize;
            return (base + GUARD, stack_top(base, (*t).stack_len), 0);
        }
        let base = *(*t).segs.as_ptr().add(k - 1);
        let top = base + SLOT - CHAIN_CELL;
        (base + GUARD, top, top)
    }
}

/// Runs `shim(block)` on the task's next stack segment: the recursion check of a cyclic function
/// found the stack pointer below the limit of the current one, so the function runs again
/// there with the parameters stored at `block` (`ms_clif::lower::depth_enter`). The segment is
/// a guarded slot like the home one, kept by the task until it ends; after 511 of them, or when
/// no slot is left, the task faults with the stack overflow report.
///
/// # Safety
/// Called by generated code on the runtime thread; `block` is a heap block the caller frees afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_grow(
    shim: unsafe extern "C-unwind" fn(*mut u8),
    block: *mut u8,
) {
    // SAFETY: single threaded scheduler; the current task is on its stack.
    unsafe {
        let cur = ensure_init();
        let k = (*cur).seg + 1;
        // A cancellation or fault inside the shim leaves by a jump that skips the caller's free of
        // `block`, so a cleanup releases it; the normal return discards the cleanup.
        let release = fault::msrt_cleanup_push(crate::obj::msrt_free, block);
        // A main task already has a whole region, the cap; the thread's own flow has no slot.
        if (*cur).stack.is_null() || (*cur).stack_len == REGION || k > MAX_SEGMENTS {
            fault::msrt_fault_depth();
        }
        if (*cur).segs.len() < k {
            let base = try_alloc_stack(SLOT);
            if base.is_null() {
                fault::msrt_fault_depth();
            }
            (*cur).segs.push(base as usize);
        }
        let base = *(*cur).segs.as_ptr().add(k - 1);
        // Commits the top pages where commits are explicit; the frame it writes is overwritten.
        stack::prepare(base as *mut u8, SLOT);
        let (lo, top, chain) = segment_bounds(cur, k);
        let prev = fault::segment_state();
        (chain as *mut [usize; 4]).write([prev.0, prev.1, prev.2, 0]);
        region_cell(base).write(&mut (*cur).hdr);
        let limit = (*cur).hdr.limit;
        (*cur).hdr.limit = fault::stack_limit(lo, top);
        region_limit_cell(base).write((*cur).hdr.limit);
        fault::set_segment_state((lo, top, chain));
        (*cur).seg = k;
        (*cur).left.push(0);
        let save: *mut usize = (*cur).left.last_mut().expect("pushed");
        #[cfg(windows)]
        {
            // The segment's thread environment block fields, then this stack's own for the
            // way back; the assembly installs each once the stack pointer has moved.
            let old = sys::teb_stack();
            (*cur).seg_teb.push(old);
            let teb = [
                base + SLOT,
                base + SLOT - stack::INITIAL_COMMIT,
                base,
                old[0],
                old[1],
                old[2],
            ];
            stack::msrt_call_on_stack(top, shim, block, save, teb.as_ptr());
            (*cur).seg_teb.pop();
        }
        #[cfg(not(windows))]
        stack::msrt_call_on_stack(top, shim, block, save);
        fault::msrt_cleanup_discard(release);
        (*cur).seg = k - 1;
        (*cur).left.pop();
        (*cur).hdr.limit = limit;
        publish_limit();
        fault::set_segment_state(prev);
    }
}

/// The segment the running task is on, recorded by a guard when it opens.
pub(crate) fn current_segment() -> usize {
    // SAFETY: single threaded scheduler.
    unsafe { (*ensure_init()).seg }
}

/// Puts the running task back on segment `seg` after a guard exit skipped the returns of the
/// grows above it: the segment's bounds and chain. The guard restores the recursion limit
/// itself, and on Windows installs the fields of [`segment_teb`] once its jump has moved the
/// stack pointer.
pub(crate) unsafe fn restore_segment(seg: usize) {
    // SAFETY: single threaded scheduler; the guard was opened on segment `seg` of this task.
    unsafe {
        let cur = ensure_init();
        if (*cur).seg == seg {
            return;
        }
        (*cur).seg = seg;
        (*cur).left.truncate(seg);
        fault::set_segment_state(segment_bounds(cur, seg));
        #[cfg(windows)]
        (*cur).seg_teb.truncate(seg);
    }
}

/// The thread environment block's stack fields of segment `seg` of the running task, as they
/// were when the task last left it; the current ones when it is on `seg`. Read before
/// [`restore_segment`].
#[cfg(windows)]
pub(crate) unsafe fn segment_teb(seg: usize) -> [usize; 3] {
    // SAFETY: single threaded scheduler.
    unsafe {
        let cur = ensure_init();
        if (*cur).seg == seg {
            sys::teb_stack()
        } else {
            *(*cur).seg_teb.as_ptr().add(seg)
        }
    }
}

#[cfg(test)]
mod tests;
