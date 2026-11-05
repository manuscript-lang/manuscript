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

/// Results of a park, ORed together.
pub const WAIT_READ: u32 = 1;
pub const WAIT_WRITE: u32 = 2;
pub const WAIT_HUP: u32 = 4;
pub const WAIT_TIMEOUT: u32 = 8;
pub const WAIT_CANCELLED: u32 = 16;
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
    epfd: -1,
    pool: Vec::new(),
    pool_clean: 0,
    carve: (0, 0),
    regions: Vec::new(),
    round: 0,
    scan: 0,
    zombie_stack: (0, 0),
    zombie_task: null_mut(),
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

/// Points the region of `t`'s stack at `t`'s block, so code running on it finds its block.
unsafe fn publish_region(t: *mut Task) {
    // SAFETY: `t` is live and has a stack; the cell page is committed on first use.
    unsafe {
        if (*t).stack.is_null() {
            return;
        }
        region_cell((*t).stack as usize).write(&mut (*t).hdr);
        // Returning into a lower segment runs code there too.
        for k in 0..(*t).seg {
            region_cell(*(*t).segs.as_ptr().add(k)).write(&mut (*t).hdr);
        }
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

// ---- records and handles ----

fn clock_ns() -> i64 {
    sys::monotonic_ns()
}

fn lookup_in(slots: &[Slot], h: u64) -> *mut Task {
    let idx = (h & 0xffff_ffff) as usize;
    match slots.get(idx.wrapping_sub(1)) {
        Some(slot) if slot.gen_ == (h >> 32) as u32 => slot.task,
        _ => null_mut(),
    }
}

fn lookup(h: u64) -> *mut Task {
    lookup_in(&sched().slots, h)
}

unsafe fn new_task(ctx: Ctx) -> *mut Task {
    let mut s = sched();
    let t = alloc::alloc(size_of::<Task>()) as *mut Task;
    let (idx, gen_) = match s.free_slots.pop() {
        Some(i) => {
            let slot = &mut s.slots[i];
            slot.gen_ = (slot.gen_.wrapping_add(1) & 0x7fff_ffff).max(1);
            slot.task = t;
            (i, slot.gen_)
        }
        None => {
            s.slots.push(Slot { task: t, gen_: 1 });
            (s.slots.len() - 1, 1)
        }
    };
    // SAFETY: `t` is a fresh block of the right size.
    unsafe {
        t.write(Task {
            handle: (gen_ as u64) << 32 | (idx as u64 + 1),
            state: State::Ready,
            sp: 0,
            ctx,
            stack: null_mut(),
            stack_len: 0,
            entry: None,
            arg: null_mut(),
            detached: false,
            joiner: 0,
            status: 0,
            msg: crate::string::NO_STR,
            wait_fd: -1,
            wait_events: 0,
            wait_result: 0,
            deadline: NO_DEADLINE,
            wait_token: 0,
            fatal: false,
            owned: null_mut(),
            kill_at: NO_DEADLINE,
            started_by: Vec::new(),
            timed_out: false,
            defer_deadline: i64::MAX,
            promise: 0,
            hdr: fault::Hdr::new(0),
            frozen: null_mut(),
            frozen_len: 0,
            parked_round: 0,
            pinned: 0,
            #[cfg(windows)]
            teb: sys::teb_stack(),
            segs: Vec::new(),
            seg: 0,
            left: Vec::new(),
            #[cfg(windows)]
            seg_teb: Vec::new(),
        });
    }
    s.live += 1;
    t
}

unsafe fn free_task(t: *mut Task) {
    let mut s = sched();
    // SAFETY: `t` is a live record from `new_task`; its slot is cleared before release.
    unsafe {
        let idx = ((*t).handle & 0xffff_ffff) as usize - 1;
        s.slots[idx].task = null_mut();
        s.free_slots.push(idx);
        if !(*t).frozen.is_null() {
            sys::free((*t).frozen.cast());
        }
        core::ptr::drop_in_place(t);
        alloc::free(t as *mut u8);
    }
    s.live -= 1;
}

/// Creates the record of the thread's current flow of control on first use.
unsafe fn ensure_init() -> *mut Task {
    let mut s = sched();
    if s.cur.is_null() {
        // SAFETY: first use; the live globals belong to this flow, so its saved context starts empty.
        unsafe {
            let t = new_task(Ctx::new(0, 0));
            (*t).sp = stack::adopt_thread();
            (*t).state = State::Running;
            s.cur = t;
            s.main = t;
        }
    }
    s.cur
}

// ---- stacks ----

unsafe fn alloc_stack(len: usize) -> *mut u8 {
    // SAFETY: forwarded.
    let p = unsafe { try_alloc_stack(len) };
    if p.is_null() {
        fault::fault(
            b"cannot allocate a task stack: too many tasks at once (the process is out of address space or, on a Linux kernel before 6.13, out of memory mappings: raise vm.max_map_count)",
        );
    }
    p
}

/// A pooled or fresh stack of `len` bytes; null when none is left.
unsafe fn try_alloc_stack(len: usize) -> *mut u8 {
    let mut s = sched();
    if let Some(at) = s.pool.iter().rposition(|&(_, pooled)| pooled == len) {
        // The entry that moves into `at` may still hold pages.
        s.pool_clean = s.pool_clean.min(at);
        return s.pool.swap_remove(at).0 as *mut u8;
    }
    let _ = s;
    // SAFETY: the lowest pages of the fresh mapping become the guard.
    unsafe { stack::create(len) }
}

/// A finished task's stack goes to the pool. Slots are never unmapped one at a time: that would
/// split their region's mapping, and `vm.max_map_count` bounds how many mappings a process may
/// have (about 32k tasks, #2483). Regions go back at teardown.
unsafe fn release_stack(base: usize, len: usize) {
    sched().pool.push((base, len));
}

/// Stacks the pool keeps with their pages when the scheduler idles; the rest give the pages back.
const STACK_POOL_WARM: usize = 256;

/// Called before the scheduler blocks: after a burst of tasks the pool holds many stacks, and
/// each keeps the pages its task touched. The oldest give them back (one call per stack, once),
/// so a quiet server returns to its working set; the newest stay warm for the next request.
unsafe fn trim_idle_stacks() {
    let mut s = sched();
    let end = s.pool.len().saturating_sub(STACK_POOL_WARM);
    for at in s.pool_clean..end {
        let (base, len) = s.pool[at];
        // SAFETY: a pooled stack is unused; its guard stays and the stack stays mapped.
        unsafe {
            sys::release(
                (base + GUARD) as *mut u8,
                stack_top(base, len) - base - GUARD,
            )
        };
    }
    s.pool_clean = s.pool_clean.max(end);
}

/// Called before the scheduler blocks: a task parked for `HIBERNATE_ROUNDS` idle rounds has its
/// used stack copied to the heap and its pages given back, so an idle task costs its records
/// and not a page (a Java virtual thread's freeze). `thaw` copies the bytes back to the same
/// addresses before the task runs again, so every pointer into the stack stays valid. Nothing
/// writes to a parked task's stack; a pool job that borrows a slice of its caller's frame pins the
/// task (`pin_current`) so it is skipped until the job is done.
///
/// One call walks every slot once, `HIBERNATE_SCAN` at a time, and stops early when work has
/// arrived, so a wake-up never waits for a million slots; the next idle round resumes where it
/// stopped.
unsafe fn hibernate_idle() {
    let mut s = sched();
    s.round = s.round.wrapping_add(1);
    let round = s.round;
    let n = s.slots.len();
    if n == 0 {
        return;
    }
    // The blocking task is still on its stack with a stale saved pointer: never freeze it.
    let cur = s.cur;
    let mut at = s.scan.min(n);
    let mut left = n;
    while left > 0 {
        let chunk = HIBERNATE_SCAN.min(left);
        left -= chunk;
        for _ in 0..chunk {
            if at == n {
                at = 0;
            }
            let t = s.slots[at].task;
            at += 1;
            // SAFETY: slots hold live records or null.
            unsafe {
                if t.is_null()
                    || t == cur
                    || (*t).state != State::Waiting
                    || (*t).seg != 0
                    || (*t).pinned != 0
                    || !(*t).frozen.is_null()
                    || (*t).stack.is_null()
                    || round.wrapping_sub((*t).parked_round) < HIBERNATE_ROUNDS
                {
                    continue;
                }
                freeze(t);
            }
        }
        if crate::sched::work_available() || crate::sched::signalled() {
            break;
        }
    }
    s.scan = at;
}

/// Marks the running task's stack as lent out (`lend` true) or returned (`lend` false): a pool
/// job that borrows a slice of the caller's frame, or a promise task that reads what its work
/// captured, reads the frame while the task is parked, so the task must not hibernate until the
/// borrower is done.
pub(crate) unsafe fn pin_current(lend: bool) {
    // SAFETY: called on the runtime thread by the running task.
    unsafe {
        let cur = ensure_init();
        if lend {
            (*cur).pinned += 1;
        } else {
            (*cur).pinned -= 1;
        }
    }
}

/// Lends the running task's stack out until [`return_lent`] is called with the handle this
/// returns: the promise it starts reads the frame its work captured from, for as long as the
/// promise's task runs.
pub(crate) unsafe fn lend_current() -> u64 {
    // SAFETY: called on the runtime thread by the running task.
    unsafe {
        pin_current(true);
        (*ensure_init()).handle
    }
}

/// Returns a stack lent with [`lend_current`]; nothing to do when the task has ended since.
pub(crate) unsafe fn return_lent(handle: u64) {
    let t = lookup(handle);
    if t.is_null() {
        return;
    }
    // SAFETY: a live record of this thread's scheduler.
    unsafe { (*t).pinned -= 1 };
}

/// Copies the used part of `t`'s stack to the heap and gives all its pages back.
unsafe fn freeze(t: *mut Task) {
    // SAFETY: `t` is parked, so nothing runs on its stack; `sp` is its saved stack pointer.
    unsafe {
        let top = stack_top((*t).stack as usize, (*t).stack_len);
        let sp = (*t).sp;
        let len = top - sp;
        // The system allocator sizes the copy exactly; the runtime's large classes round a
        // 3 KiB stack up to a 4 KiB block, which would give back nothing.
        let copy = sys::malloc(len.max(1)) as *mut u8;
        if copy.is_null() {
            fault::fatal(b"out of memory");
        }
        core::ptr::copy_nonoverlapping(sp as *const u8, copy, len);
        (*t).frozen = copy;
        (*t).frozen_len = len;
        // The whole stack: pages below `sp` that deeper calls touched and left behind go too,
        // and the segments a deep recursion grew into, all unused on the home segment.
        let low = (*t).stack as usize + GUARD;
        sys::release(low as *mut u8, top - low);
        for &base in &(*t).segs {
            sys::release((base + GUARD) as *mut u8, SLOT - GUARD);
        }
    }
}

/// Copies a hibernating task's stack back before it runs.
unsafe fn thaw(t: *mut Task) {
    // SAFETY: `t` is about to run; its stack range is reserved and nothing else uses it.
    unsafe {
        let sp = (*t).sp;
        let len = (*t).frozen_len;
        let page = sp & !4095;
        if !sys::commit(page as *mut u8, sp + len - page)
            || !sys::commit_guard((page - 4096) as *mut u8)
        {
            fault::fatal(b"cannot commit a task stack");
        }
        #[cfg(windows)]
        {
            (*t).teb[1] = page;
        }
        core::ptr::copy_nonoverlapping((*t).frozen, sp as *mut u8, len);
        sys::free((*t).frozen.cast());
        (*t).frozen = null_mut();
        (*t).frozen_len = 0;
    }
}

/// Frees what finished tasks left behind; runs on the stack of a task that is still alive.
unsafe fn reap() {
    let mut s = sched();
    // SAFETY: the zombie's stack is no longer in use; its record is unreachable.
    unsafe {
        if s.zombie_stack.0 != 0 {
            let (base, len) = s.zombie_stack;
            s.zombie_stack = (0, 0);
            release_stack(base, len);
        }
        if !s.zombie_task.is_null() {
            let t = s.zombie_task;
            s.zombie_task = null_mut();
            free_task(t);
        }
    }
}

// ---- reactor ----

pub use crate::poller::kick;

/// Opens the poller if no wait has yet (the Windows pipe registry lives in it).
#[cfg(windows)]
pub(crate) fn ensure_poller() {
    // SAFETY: single threaded scheduler.
    unsafe { poller_fd() };
}

unsafe fn poller_fd() -> i32 {
    let mut s = sched();
    if s.epfd < 0 {
        // SAFETY: creates the poller descriptors.
        s.epfd = unsafe { crate::poller::create() };
    }
    s.epfd
}

/// Marks `t` runnable with the given park result.
unsafe fn wake(t: *mut Task, result: u32) {
    let mut s = sched();
    // SAFETY: `t` is a live waiting task.
    unsafe {
        if (*t).state != State::Waiting {
            return;
        }
        if (*t).wait_fd >= 0 {
            let fd = (*t).wait_fd;
            let queue = &mut s.fd_waiters[fd as usize];
            queue.retain(|&h| h != (*t).handle);
            let empty = queue.is_empty();
            s.fd_waiting -= 1;
            (*t).wait_fd = -1;
            if empty {
                crate::poller::unwatch(fd);
            } else {
                // The poller watches what the waiters left behind still ask for.
                rearm(fd);
            }
        }
        if (*t).wait_token != 0 {
            if let Some(k) = token_mut(&mut s, (*t).wait_token) {
                k.waiter = 0;
            }
            (*t).wait_token = 0;
        }
        (*t).deadline = NO_DEADLINE;
        (*t).wait_result = result;
        (*t).state = State::Ready;
        s.ready.push_back((*t).handle);
    }
}

/// Cancels tasks whose time limit has passed.
unsafe fn expire_kills(now: i64) {
    let mut s = sched();
    while let Some(&Reverse((deadline, h))) = s.kills.peek()
        && deadline <= now
    {
        s.kills.pop();
        // SAFETY: handles are validated by `lookup`.
        unsafe {
            let t = lookup(h);
            if !t.is_null() && (*t).state != State::Done && (*t).kill_at == deadline {
                (*t).timed_out = true;
                msrt_task_cancel(h);
            }
        }
    }
}

/// Wakes timers that have expired.
unsafe fn expire_timers(now: i64) {
    // SAFETY: forwarded contract.
    unsafe { expire_kills(now) };
    crate::promise::expire(now);
    let mut s = sched();
    while let Some(&Reverse((deadline, h))) = s.timers.peek()
        && deadline <= now
    {
        s.timers.pop();
        // SAFETY: handles are validated by `lookup`.
        unsafe {
            let t = lookup(h);
            if !t.is_null() && (*t).state == State::Waiting && (*t).deadline == deadline {
                wake(t, WAIT_TIMEOUT);
            }
        }
    }
}

/// Whether `t` runs a cleanup action, which cancellation must not interrupt.
/// Whether `t` holds a stop shield, which keeps SIGINT/SIGTERM from waking it.
unsafe fn stop_shielded(t: *mut Task) -> bool {
    // SAFETY: `t` is a live record; the running task's state is in the live globals.
    unsafe {
        if t == sched().cur {
            (*fault::cur_hdr()).stop_shield.load(Ordering::Relaxed) > 0
        } else {
            (*t).ctx.stop_shielded()
        }
    }
}

unsafe fn shielded(t: *mut Task) -> bool {
    // SAFETY: `t` is a live record; the running task's state is in the live globals.
    unsafe {
        if t == sched().cur {
            fault::live_shielded()
        } else {
            (*t).ctx.shielded()
        }
    }
}

/// Wakes every waiting task that is not shielded with `WAIT_CANCELLED`, the main task first.
/// Returns whether any task woke.
unsafe fn cancel_all_waiters() -> bool {
    let s = sched();
    let mut woke = false;
    // SAFETY: slots hold live records or null.
    unsafe {
        if !s.main.is_null()
            && (*s.main).state == State::Waiting
            && !shielded(s.main)
            && !stop_shielded(s.main)
        {
            wake(s.main, WAIT_CANCELLED);
            woke = true;
        }
        for i in 0..s.slots.len() {
            let t = s.slots[i].task;
            if !t.is_null() && (*t).state == State::Waiting && !shielded(t) && !stop_shielded(t) {
                wake(t, WAIT_CANCELLED);
                woke = true;
            }
        }
    }
    woke
}

/// Delivers descriptor readiness, waiting at most `timeout_ns` nanoseconds (0 never blocks, -1
/// waits for an event).
unsafe fn poll_ready(timeout_ns: i64) {
    let mut s = sched();
    let mut ready = [crate::poller::Ready { fd: 0, bits: 0 }; 64];
    // SAFETY: the poller owns its registrations; handles are checked before waking tasks.
    unsafe {
        let Some(n) = crate::poller::wait(poller_fd(), timeout_ns, &mut ready) else {
            return;
        };
        for ev in ready.iter().take(n) {
            if ev.fd >= s.fd_waiters.len() {
                continue;
            }
            // Every waiter the event concerns wakes; the one that gets the resource proceeds
            // and the others wait again. `wake` re-arms for those that stay.
            let queue = s.fd_waiters[ev.fd].clone();
            for h in queue {
                if h & PROMISE_TAG != 0 {
                    let id = (h & !PROMISE_TAG) as i64;
                    if crate::promise::fd_ready(id, ev.bits) {
                        let q = &mut s.fd_waiters[ev.fd];
                        q.retain(|&w| w != h);
                        s.fd_waiting -= 1;
                        if s.fd_waiters[ev.fd].is_empty() {
                            crate::poller::unwatch(ev.fd as i32);
                        }
                    }
                    continue;
                }
                let t = lookup(h);
                if t.is_null() {
                    continue;
                }
                let bits = ev.bits & ((*t).wait_events | WAIT_HUP);
                if bits != 0 {
                    wake(t, bits);
                }
            }
            if !s.fd_waiters[ev.fd].is_empty() {
                // The registration is one-shot: waiters the event did not concern need it again.
                rearm(ev.fd as i32);
            }
        }
    }
}

/// Ends the wait the scheduler is about to fault out of. Cleanup may park again, and a
/// contained fault must leave both its token and any joined task available to later waiters.
unsafe fn abandon_wait() {
    let mut s = sched();
    // SAFETY: `cur` is the task that is parking.
    unsafe {
        let cur = s.cur;
        if cur.is_null() || (*cur).state != State::Waiting {
            return;
        }
        if (*cur).wait_token != 0 {
            if let Some(k) = token_mut(&mut s, (*cur).wait_token) {
                k.waiter = 0;
            }
            (*cur).wait_token = 0;
        }
        // A join has no token. Release its claim before fault cleanup can join the target.
        // Only this exceptional path scans slots; normal joins still clear their own claim.
        for slot in &s.slots {
            let t = slot.task;
            if !t.is_null() && (*t).joiner == (*cur).handle {
                (*t).joiner = 0;
            }
        }
        (*cur).deadline = NO_DEADLINE;
        (*cur).state = State::Running;
    }
}

const CROSS_ISOLATE_DEADLOCK: &[u8] = b"deadlock: every isolate is waiting on another (a worker channel or worker result) and nothing can wake them";

/// Blocks until at least one task is runnable.
unsafe fn reactor_wait() {
    let mut s = sched();
    // SAFETY: syscalls with valid buffers; task records are live.
    unsafe {
        loop {
            // Tasks in a shielded cleanup keep waiting; they see the stop request afterwards.
            if crate::isolate::pending_cancel() != 0 && cancel_all_waiters() {
                return;
            }
            deliver_remote_posts();
            let now = clock_ns();
            expire_timers(now);
            if !s.ready.is_empty() || crate::sched::work_available() {
                return;
            }
            let mut timeout_ns = -1;
            while let Some(&Reverse((deadline, h))) = s.timers.peek() {
                let t = lookup(h);
                if t.is_null() || (*t).state != State::Waiting || (*t).deadline != deadline {
                    s.timers.pop();
                    continue;
                }
                timeout_ns = (deadline - now).max(0);
                break;
            }
            while let Some(&Reverse((deadline, h))) = s.kills.peek() {
                let t = lookup(h);
                if t.is_null() || (*t).state == State::Done || (*t).kill_at != deadline {
                    s.kills.pop();
                    continue;
                }
                let ns = (deadline - now).max(0);
                timeout_ns = if timeout_ns < 0 {
                    ns
                } else {
                    timeout_ns.min(ns)
                };
                break;
            }
            if let Some(deadline) = crate::promise::next_deadline() {
                let ns = (deadline - now).max(0);
                timeout_ns = if timeout_ns < 0 {
                    ns
                } else {
                    timeout_ns.min(ns)
                };
            }
            let mut parked = false;
            if timeout_ns < 0 && s.fd_waiting == 0 {
                if s.remote_tokens == 0 {
                    abandon_wait();
                    fault::fault_kind(FaultKind::Deadlock, b"deadlock: every task is waiting and nothing can wake them; a wait has no matching completion, timer, I/O or cancellation");
                }
                // Waiting only on other isolates: stuck if they all wait like this.
                parked = s.remote_tokens == s.peer_tokens;
            }
            if parked && crate::isolate::enter_idle() {
                abandon_wait();
                fault::fault_kind(FaultKind::Deadlock, CROSS_ISOLATE_DEADLOCK);
            }
            crate::sched::set_idle(true);
            // Work may have arrived between the last look and now.
            if crate::sched::work_available() || crate::sched::signalled() {
                crate::sched::set_idle(false);
                continue;
            }
            trim_idle_stacks();
            hibernate_idle();
            poll_ready(timeout_ns);
            crate::sched::set_idle(false);
            if parked && crate::isolate::leave_idle() {
                abandon_wait();
                fault::fault_kind(FaultKind::Deadlock, CROSS_ISOLATE_DEADLOCK);
            }
        }
    }
}

// ---- switching ----

unsafe fn after_switch() {
    // SAFETY: running on a live task's stack.
    unsafe { reap() };
}

/// Runs the next runnable task; returns when the calling task is scheduled again.
/// The caller has already set its state (Ready and queued, Waiting, or Done).
unsafe fn switch_away() {
    let mut s = sched();
    // SAFETY: single threaded scheduler; stacks and records outlive the switch.
    unsafe {
        let cur = s.cur;
        // A busy ready queue must not starve timers, I/O, remote posts, or signal cancellation.
        // Only the idle path may block; avoid clock and poll syscalls when nothing needs them.
        if crate::isolate::pending_cancel() != 0 {
            cancel_all_waiters();
        }
        if !s.tokens.is_empty() || crate::sched::signalled() {
            deliver_remote_posts();
        }
        if !s.kills.is_empty() || !s.timers.is_empty() || crate::promise::has_timers() {
            expire_timers(clock_ns());
        }
        if s.fd_waiting != 0 {
            poll_ready(0);
        }
        loop {
            if let Some(h) = s.ready.pop_front() {
                let next = lookup(h);
                if next.is_null() || (*next).state != State::Ready {
                    continue;
                }
                if next == cur {
                    (*cur).state = State::Running;
                    return;
                }
                (*next).state = State::Running;
                crate::sched::publish_busy(s.ready.len() + 1);
                if (*cur).state == State::Waiting {
                    (*cur).parked_round = s.round;
                }
                if !(*next).frozen.is_null() {
                    thaw(next);
                }
                publish_region(next);
                fault::swap_ctx(&mut (*cur).ctx);
                fault::swap_ctx(&mut (*next).ctx);
                fault::publish_current_hdr();
                s.cur = next;
                stack::switch(cur, next);
                after_switch();
                return;
            }
            // Nothing is ready: start a promise, this thread's own or one taken from a busy thread.
            if let Some(start) = crate::sched::next_pending() {
                crate::promise::execute(start);
                continue;
            }
            crate::sched::publish_busy(0);
            reactor_wait();
        }
    }
}

/// First code run on a new task's stack.
extern "C" fn task_main() -> ! {
    // SAFETY: the scheduler set `cur` to this task before switching to it.
    unsafe {
        after_switch();
        let mut s = sched();
        let t = s.cur;
        let entry = (*t)
            .entry
            .take()
            .unwrap_or_else(|| fault::fatal(b"runtime invariant: task without an entry"));
        if (*t).detached {
            entry((*t).arg);
        } else {
            let mut msg = crate::string::NO_STR;
            (*t).status = fault::msrt_guard_call(entry, (*t).arg, &mut msg);
            if (*t).status == 1 && (*t).fatal {
                if isolate::is_worker() {
                    // A worker contains its faults: the first one ends its main task, and
                    // `run_worker_task` hands the report to the parent.
                    let first = &mut *FATAL.ptr();
                    if first.is_empty() {
                        *first = fault::fault_report(&msg, &(*t).started_by);
                        isolate::raise_cancel(isolate::id(), sys::SIGTERM as u8);
                    }
                } else {
                    fault::exit_with_report(&msg, &(*t).started_by);
                }
            }
            (*t).msg = msg;
            if (*t).promise != 0 {
                crate::promise::task_ended((*t).promise, (*t).status, &(*t).msg, &(*t).started_by);
            }
        }
        if !(*t).owned.is_null() {
            crate::obj::drop_obj(core::mem::replace(&mut (*t).owned, null_mut()));
        }
        (*t).state = State::Done;
        s.zombie_stack = ((*t).stack as usize, (*t).stack_len);
        (*t).stack = null_mut();
        // A task ends on its home segment; the ones it grew into are free now.
        for base in core::mem::take(&mut (*t).segs) {
            s.pool.push((base, SLOT));
        }
        if (*t).promise != 0 {
            // A promise's task is never joined: the promise learns of its end by event.
            crate::string::release_opt(&core::mem::replace(&mut (*t).msg, crate::string::NO_STR));
            s.zombie_task = t;
        } else if (*t).detached {
            s.zombie_task = t;
        } else if (*t).joiner != 0 {
            let j = lookup((*t).joiner);
            if !j.is_null() {
                wake(j, 0);
            }
        }
        switch_away();
        fault::fatal(b"runtime invariant: a finished task was resumed")
    }
}

// ---- exported API ----

/// Starts `entry(arg)` as a new task and returns its handle. The task first runs when the
/// caller parks or yields. Every task gets a `SLOT` of address space, committed lazily; the
/// runtime's own `ROOT_STACK` request gives a main task a region (256 MiB). With
/// `SPAWN_DETACHED` nobody joins the task and a fault in it ends the process (exit 67);
/// otherwise the fault is returned by `msrt_task_join`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_spawn(
    entry: Entry,
    arg: *mut u8,
    flags: u32,
    stack_bytes: usize,
) -> u64 {
    // SAFETY: single threaded scheduler.
    unsafe {
        ensure_init();
        let len = if stack_bytes == ROOT_STACK {
            REGION
        } else {
            SLOT
        };
        let base = alloc_stack(len);
        let (lo, hi, sp) = stack::prepare(base, len);
        let t = new_task(Ctx::new(lo, hi));
        (*t).stack = base;
        (*t).stack_len = len;
        let hdr: *mut fault::Hdr = &mut (*t).hdr;
        (*t).ctx.set_hdr(hdr);
        #[cfg(windows)]
        {
            (*t).teb = [hi, hi - stack::INITIAL_COMMIT, base as usize];
        }
        (*t).entry = Some(entry);
        (*t).arg = arg;
        (*t).detached = flags & SPAWN_DETACHED != 0;
        (*t).fatal = flags & SPAWN_FATAL != 0;
        (*t).sp = sp;
        sched().ready.push_back((*t).handle);
        (*t).handle
    }
}

/// Runs `entry` as the isolate's main task and returns when it ends. The caller's own flow
/// only waits, shielded from stop requests (they go to the main task, which cleans up and exits).
///
/// # Safety
/// `entry` receives the token the caller waits on and must post it when it finishes.
pub unsafe fn run_main_task(entry: Entry) {
    // SAFETY: single threaded scheduler.
    unsafe {
        ensure_init();
        let done = msrt_token_new(0);
        let h = msrt_task_spawn(entry, done as usize as *mut u8, SPAWN_DETACHED, ROOT_STACK);
        sched().main = lookup(h);
        fault::msrt_shield_enter();
        sched().waiting_roots += 1;
        let mut value = 0;
        while msrt_token_park(done, -1, &mut value) != 0 {}
        sched().waiting_roots -= 1;
        fault::msrt_shield_exit();
        msrt_token_free(done);
    }
}

/// Runs `entry(arg)` as a worker isolate's main task and returns its outcome (0 returned,
/// 1 fault, 2 cancelled) with the fault report. The caller's own flow only waits, shielded.
///
/// # Safety
/// `entry` must be safe to call with `arg` on a task stack of this isolate.
pub unsafe fn run_worker_task(entry: Entry, arg: *mut u8) -> (u8, Vec<u8>) {
    // SAFETY: single threaded scheduler.
    unsafe {
        ensure_init();
        let h = msrt_task_spawn(entry, arg, 0, ROOT_STACK);
        sched().main = lookup(h);
        fault::msrt_shield_enter();
        sched().waiting_roots += 1;
        let mut msg = crate::string::NO_STR;
        let status = msrt_task_join(h, &mut msg);
        sched().waiting_roots -= 1;
        fault::msrt_shield_exit();
        let fatal = core::mem::take(&mut *FATAL.ptr());
        if !fatal.is_empty() {
            crate::string::release_opt(&msg);
            return (1, fatal);
        }
        let report = if msg.is_empty() {
            Vec::new()
        } else {
            crate::string::bytes(&msg).to_vec()
        };
        crate::string::release_opt(&msg);
        (status, report)
    }
}

crate::isolate_static! {
    /// The report of the first fatal task fault in a worker isolate, empty until one happens.
    static FATAL: Vec<u8> = Vec::new();
}

/// Lets other runnable tasks run, then continues.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_yield() {
    // SAFETY: single threaded scheduler.
    unsafe {
        let cur = ensure_init();
        (*cur).state = State::Ready;
        sched().ready.push_back((*cur).handle);
        switch_away();
    }
}

/// Parks the current task until `fd` is ready for `events` (`WAIT_READ`, `WAIT_WRITE`), the
/// timeout (nanoseconds, negative for none) expires, or cancellation is requested. Returns the
/// ready bits, `WAIT_TIMEOUT`, or `WAIT_CANCELLED`. A file that cannot be polled (a regular
/// file) is reported ready at once. Several tasks may wait on one descriptor: each wakes when
/// it becomes ready for what that task asked, and the one that gets the resource proceeds.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_wait_fd(fd: i32, events: u32, timeout_ns: i64) -> u32 {
    // SAFETY: single threaded scheduler.
    unsafe {
        let cur = ensure_init();
        if cancel_flag().load(Ordering::Relaxed) != 0 {
            return WAIT_CANCELLED;
        }
        let mut s = sched();
        if fd >= 0 {
            let fd_idx = fd as usize;
            while s.fd_waiters.len() <= fd_idx {
                s.fd_waiters.push(Vec::new());
            }
            // Tasks already waiting keep their place; the poller watches what all of them ask.
            let mut asked = events;
            for &h in &s.fd_waiters[fd_idx] {
                let other = waiter_events(h);
                asked = ((asked | other) & !WAIT_KEEP) | (asked & other & WAIT_KEEP);
            }
            match crate::poller::watch(poller_fd(), fd, asked) {
                crate::poller::Watch::Armed => {}
                crate::poller::Watch::Always => return events & (WAIT_READ | WAIT_WRITE),
                crate::poller::Watch::Failed => {
                    fault::fault(b"cannot wait on this file descriptor");
                }
            }
            (*cur).wait_events = events;
            s.fd_waiters[fd_idx].push((*cur).handle);
            s.fd_waiting += 1;
            (*cur).wait_fd = fd;
        }
        (*cur).wait_events = events;
        set_deadline(cur, timeout_ns);
        (*cur).state = State::Waiting;
        switch_away();
        (*cur).wait_result
    }
}

/// Registers promise `id` as a waiter of `fd` for `events`. Returns whether `fd` is ready at once
/// (it cannot be polled, like a regular file), or `None` when it cannot be waited on.
pub(crate) unsafe fn watch_fd_for_promise(fd: i32, events: u32, id: i64) -> Option<bool> {
    let mut s = sched();
    // SAFETY: single threaded scheduler.
    unsafe {
        let fd_idx = fd as usize;
        while s.fd_waiters.len() <= fd_idx {
            s.fd_waiters.push(Vec::new());
        }
        let mut asked = events;
        for &h in &s.fd_waiters[fd_idx] {
            let other = waiter_events(h);
            asked = ((asked | other) & !WAIT_KEEP) | (asked & other & WAIT_KEEP);
        }
        match crate::poller::watch(poller_fd(), fd, asked) {
            crate::poller::Watch::Armed => {}
            crate::poller::Watch::Always => return Some(true),
            crate::poller::Watch::Failed => return None,
        }
        s.fd_waiters[fd_idx].push(id as u64 | PROMISE_TAG);
        s.fd_waiting += 1;
        Some(false)
    }
}

/// Removes promise `id` from the waiters of `fd`, if it is still one.
pub(crate) unsafe fn unwatch_fd_for_promise(fd: i32, id: i64) {
    let mut s = sched();
    // SAFETY: single threaded scheduler.
    unsafe {
        let Some(queue) = s.fd_waiters.get_mut(fd as usize) else {
            return;
        };
        let before = queue.len();
        queue.retain(|&h| h != id as u64 | PROMISE_TAG);
        if queue.len() == before {
            return;
        }
        let empty = queue.is_empty();
        s.fd_waiting -= 1;
        if empty {
            crate::poller::unwatch(fd);
        } else {
            rearm(fd);
        }
    }
}

/// Registers `fd` with the poller for what its waiters ask, or for nothing when none remain.
unsafe fn rearm(fd: i32) {
    let s = sched();
    // SAFETY: waiter handles are checked before use.
    unsafe {
        let mut asked = 0;
        let mut keep = WAIT_KEEP;
        for &h in &s.fd_waiters[fd as usize] {
            let events = waiter_events(h);
            if events != 0 {
                asked |= events & (WAIT_READ | WAIT_WRITE);
                keep &= events;
            }
        }
        if asked == 0 {
            asked = WAIT_READ;
        }
        // A registration that cannot be renewed leaves its tasks to their timeouts.
        let _ = crate::poller::watch(poller_fd(), fd, asked | keep);
    }
}

/// Arms the timer of a park that times out after `timeout_ns` (negative: never).
unsafe fn set_deadline(cur: *mut Task, timeout_ns: i64) {
    let mut s = sched();
    // SAFETY: `cur` is the running task; slots hold live records or null.
    unsafe {
        (*cur).deadline = NO_DEADLINE;
        if timeout_ns < 0 {
            return;
        }
        let deadline = clock_ns().saturating_add(timeout_ns);
        (*cur).deadline = deadline;
        s.timers.push(Reverse((deadline, (*cur).handle)));
        if s.timers.len() > s.timer_limit {
            // A task woken by its descriptor leaves its entry behind until the deadline;
            // a loop of short waits with long timeouts must not grow the heap without bound.
            let sched = &mut *s;
            let slots = &sched.slots;
            let (own, fresh) = ((*cur).handle, deadline);
            // The calling task is not Waiting yet, but its entry was just pushed and must stay.
            sched.timers.retain(|&Reverse((deadline, h))| {
                let t = lookup_in(slots, h);
                (h == own && deadline == fresh)
                    || (!t.is_null() && (*t).state == State::Waiting && (*t).deadline == deadline)
            });
            s.timer_limit = (s.timers.len() * 2).max(MIN_TIMER_LIMIT);
        }
    }
}

/// Ends the registration a `WAIT_KEEP` wait left on `fd`; call it before closing `fd`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_task_forget_fd(fd: i32) {
    crate::poller::forget(fd);
}

/// Parks the current task for `ns` nanoseconds. Returns `WAIT_TIMEOUT` or `WAIT_CANCELLED`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_sleep(ns: i64) -> u32 {
    // SAFETY: forwards to the park path.
    unsafe { msrt_task_wait_fd(-1, 0, ns.max(0)) }
}

/// Handle of the running task.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_current() -> u64 {
    // SAFETY: single threaded scheduler.
    unsafe { (*ensure_init()).handle }
}

/// Number of tasks that exist (running, runnable, waiting, or finished but not yet joined),
/// not counting the flow that only waits for the isolate's main task.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_count() -> usize {
    // SAFETY: single threaded scheduler.
    unsafe {
        ensure_init();
    }
    sched().live - sched().waiting_roots
}

/// Requests cancellation of a task: a parked task wakes with `WAIT_CANCELLED`, and the task's
/// cancellation checks fire. A handle that no longer exists is ignored.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_cancel(handle: u64) {
    // SAFETY: single threaded scheduler.
    unsafe {
        let cur = ensure_init();
        let t = lookup(handle);
        if t.is_null() || (*t).state == State::Done {
            return;
        }
        if t == cur {
            fault::set_live_task_cancel(1);
            // A parked task runs the reactor on its own stack, so it can be the one expiring its kill timer.
            if (*t).state == State::Waiting && !shielded(t) {
                wake(t, WAIT_CANCELLED);
            }
            return;
        }
        (*t).ctx.set_cancel(1);
        if !shielded(t) {
            wake(t, WAIT_CANCELLED);
        }
    }
}

/// Waits for a joinable task to finish and returns its outcome: 0 returned, 1 fault (report in
/// `*msg_out`, owned by the caller), 2 cancelled. If the caller is cancelled while waiting it
/// returns 2 without consuming the task. Each task is joined once.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_join(handle: u64, msg_out: *mut StrVal) -> u8 {
    // SAFETY: single threaded scheduler.
    unsafe { join(handle, msg_out, false) }
}

/// The body of `msrt_task_join`. With `keep` the task stays joinable and its fault message is not
/// taken. Whether the task was cancelled for running past its time limit is left in `TIMED_OUT`.
unsafe fn join(handle: u64, msg_out: *mut StrVal, keep: bool) -> u8 {
    // SAFETY: single threaded scheduler.
    unsafe {
        *TIMED_OUT.ptr() = false;
        let cur = ensure_init();
        if !msg_out.is_null() {
            *msg_out = crate::string::NO_STR;
        }
        let t = lookup(handle);
        if t.is_null() {
            fault::fault(b"join: no such task");
        }
        if (*t).detached {
            fault::fault(b"join: the task is detached");
        }
        if t == cur {
            fault::fault(b"join: a task cannot join itself");
        }
        if (*t).joiner != 0 {
            fault::fault(b"join: the task is already being joined");
        }
        if (*t).state != State::Done && cancel_flag().load(Ordering::Relaxed) != 0 {
            return 2;
        }
        if (*t).state != State::Done {
            (*t).joiner = (*cur).handle;
            (*cur).wait_events = 0;
            (*cur).state = State::Waiting;
            switch_away();
            (*t).joiner = 0;
            if (*cur).wait_result == WAIT_CANCELLED && (*t).state != State::Done {
                return 2;
            }
        }
        let status = (*t).status;
        *TIMED_OUT.ptr() = (*t).timed_out && status == 2;
        if keep {
            return status;
        }
        let msg = core::mem::replace(&mut (*t).msg, crate::string::NO_STR);
        if msg_out.is_null() {
            crate::string::release_opt(&msg);
        } else {
            *msg_out = msg;
        }
        free_task(t);
        status
    }
}

crate::isolate_static! {
    static TIMED_OUT: bool = false;
}

// ---- closure tasks (`@std/concurrency/promise.ms`) ----

/// Entry of a task that runs a `fn() Unit`: calls the closure with itself as its
/// environment, as every closure call does.
unsafe extern "C-unwind" fn closure_entry(arg: *mut u8) {
    let closure = arg as *mut ms_rt_abi::Closure;
    // SAFETY: `arg` is the retained closure object `spawn_promise_task` stored.
    unsafe {
        // The closure itself checks for a cancellation that came before it first ran
        // (`msrt_scope_started`), once it has registered the cleanup that closes its channel end.
        let code: unsafe extern "C-unwind" fn(*mut ms_rt_abi::Closure) =
            core::mem::transmute((*closure).code);
        code(closure);
    }
}

/// Changes when the running task is cancelled for running too long: `limit_ns` from now, or
/// never when negative. Replaces any earlier limit.
pub fn limit_current(limit_ns: i64) {
    // SAFETY: single threaded scheduler; the running task's record is live.
    unsafe {
        let t = ensure_init();
        (*t).kill_at = NO_DEADLINE;
        arm_kill((*t).handle, limit_ns);
    }
}

/// Cancels task `h` once it has run `limit_ns` nanoseconds; a negative limit means never.
unsafe fn arm_kill(h: u64, limit_ns: i64) {
    // SAFETY: single threaded scheduler; `h` is a live task.
    unsafe {
        if limit_ns < 0 {
            return;
        }
        let t = lookup(h);
        let at = clock_ns().saturating_add(limit_ns);
        (*t).kill_at = at;
        let mut s = sched();
        s.kills.push(Reverse((at, h)));
        if s.kills.len() > s.kill_limit {
            // Completed tasks leave future deadlines behind. Compact geometrically so
            // repeated short tasks with long limits retain space proportional to live work.
            let sched = &mut *s;
            let slots = &sched.slots;
            sched.kills.retain(|&Reverse((deadline, handle))| {
                let t = lookup_in(slots, handle);
                !t.is_null() && (*t).state != State::Done && (*t).kill_at == deadline
            });
            s.kill_limit = (s.kills.len() * 2).max(MIN_TIMER_LIMIT);
        }
    }
}

/// Starts `closure` as the task of promise `promise`, which frees itself when it ends. A fault in
/// it ends only the promise. The closure stays owned by whoever created the promise, who releases
/// it when told the task is over. Returns the task handle.
///
/// # Safety
/// `closure` must be a live closure object that outlives the task.
pub(crate) unsafe fn spawn_promise_task(closure: *mut ms_rt_abi::Closure, promise: i64) -> u64 {
    // SAFETY: single threaded scheduler; forwarded contract.
    unsafe {
        let h = msrt_task_spawn(closure_entry, closure.cast(), 0, 0);
        let t = lookup(h);
        (*t).promise = promise;
        (*t).started_by = fault::capture_frames();
        h
    }
}

/// The deadline of the deferred promise the running task is executing (`i64::MAX`: none).
pub fn defer_deadline() -> i64 {
    // SAFETY: single threaded scheduler; the running task's record is live.
    unsafe { (*ensure_init()).defer_deadline }
}

/// Sets that deadline and returns the one it replaces.
pub(crate) fn set_defer_deadline(at: i64) -> i64 {
    // SAFETY: single threaded scheduler; the running task's record is live.
    unsafe { core::mem::replace(&mut (*ensure_init()).defer_deadline, at) }
}

/// Lets a promise that has not started begin, then lets the ready tasks run: polling `done`
/// makes progress even when the polling task never waits.
pub(crate) unsafe fn pump() {
    if let Some(start) = crate::sched::next_pending() {
        crate::promise::execute(start);
    }
    // SAFETY: forwards to the yield path.
    unsafe { msrt_task_yield() };
}

// ---- tokens ----

fn token_mut(s: &mut Sched, id: u64) -> Option<&mut Token> {
    let idx = (id & 0xffff_ffff) as usize;
    let k = s.tokens.get_mut(idx.checked_sub(1)?)?;
    (k.live
        && k.gen_ as u64 == (id >> 32) & GEN_MASK as u64
        && (id >> isolate::ID_SHIFT) as usize == isolate::id())
    .then_some(k)
}

/// Records a post to `id` and wakes its waiter. A post to a freed token, or to one that holds
/// a post nobody has taken yet, is dropped.
unsafe fn post(id: u64, value: u64, remote: bool) {
    let mut s = sched();
    let Some(k) = token_mut(&mut s, id) else {
        return;
    };
    if remote && k.remote {
        k.remote = false;
        let peer = core::mem::take(&mut k.peer);
        s.remote_tokens -= 1;
        s.peer_tokens -= usize::from(peer);
    }
    let k = token_mut(&mut s, id).unwrap_or_else(|| fault::fatal(b"runtime invariant: token"));
    if k.posted.is_some() {
        return;
    }
    k.posted = Some(value);
    let waiter = k.waiter;
    if waiter != 0 {
        // SAFETY: handles are validated by `lookup`.
        unsafe {
            let t = lookup(waiter);
            if !t.is_null() {
                wake(t, 0);
            }
        }
    }
}

/// Delivers the posts other threads made since the last call.
unsafe fn deliver_remote_posts() {
    for (id, value) in isolate::take_posts() {
        // SAFETY: runs on the runtime thread.
        unsafe { post(id, value, true) };
    }
    if crate::sched::signalled() {
        crate::promise::apply_events();
    }
}

/// Creates a park token. With `TOKEN_REMOTE` another thread will post it: the runtime
/// then counts it as a pending wake-up until the post arrives or the token is freed.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_token_new(flags: u32) -> u64 {
    // SAFETY: single threaded scheduler.
    unsafe {
        ensure_init();
        let remote = flags & TOKEN_REMOTE != 0;
        if remote {
            // A remote post kicks the poller, which must exist before the post can happen.
            poller_fd();
        }
        let mut s = sched();
        if s.tokens.is_empty() {
            // Registry slots can be reused by later isolates. Resume their generation history,
            // but recreate only vacant slots, never another isolate's values or waiters.
            for gen_ in isolate::take_token_generations() {
                let idx = s.tokens.len();
                s.tokens.push(Token {
                    gen_,
                    live: false,
                    remote: false,
                    peer: false,
                    waiter: 0,
                    posted: None,
                });
                if gen_ < GEN_MASK {
                    s.free_tokens.push(idx);
                }
            }
        }
        let idx = match s.free_tokens.pop() {
            Some(i) => i,
            None => {
                s.tokens.push(Token {
                    gen_: 0,
                    live: false,
                    remote: false,
                    peer: false,
                    waiter: 0,
                    posted: None,
                });
                s.tokens.len() - 1
            }
        };
        let k = &mut s.tokens[idx];
        k.gen_ += 1;
        k.live = true;
        k.remote = remote;
        k.peer = remote && flags & TOKEN_PEER != 0;
        k.waiter = 0;
        k.posted = None;
        let id =
            (isolate::id() as u64) << isolate::ID_SHIFT | (k.gen_ as u64) << 32 | (idx as u64 + 1);
        if remote {
            s.remote_tokens += 1;
            s.peer_tokens += usize::from(flags & TOKEN_PEER != 0);
        }
        id
    }
}

/// Parks the current task until `id` is posted, the timeout (nanoseconds, negative for none)
/// passes, or cancellation is requested. Returns 0 with the posted value in `*value_out`,
/// `WAIT_TIMEOUT`, or `WAIT_CANCELLED`. A post made before the park is kept, so the park
/// returns at once; the park takes the post, so the token can be posted and parked on again.
/// It also stays usable after a timeout or cancellation. Faults for a freed
/// token or one another task waits on.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_token_park(
    id: u64,
    timeout_ns: i64,
    value_out: *mut u64,
) -> u32 {
    // SAFETY: single threaded scheduler; `value_out` is null or writable.
    unsafe {
        let cur = ensure_init();
        let take = |value_out: *mut u64| -> bool {
            let mut s = sched();
            let k = token_mut(&mut s, id)
                .unwrap_or_else(|| fault::fault(b"park on a token that does not exist"));
            match k.posted.take() {
                Some(v) => {
                    if !value_out.is_null() {
                        *value_out = v;
                    }
                    true
                }
                None => false,
            }
        };
        if take(value_out) {
            return 0;
        }
        if cancel_flag().load(Ordering::Relaxed) != 0 {
            return WAIT_CANCELLED;
        }
        let mut s = sched();
        let k = token_mut(&mut s, id)
            .unwrap_or_else(|| fault::fault(b"park on a token that does not exist"));
        if k.waiter != 0 {
            fault::fault(b"another task is already waiting on this token");
        }
        k.waiter = (*cur).handle;
        (*cur).wait_token = id;
        (*cur).wait_events = 0;
        set_deadline(cur, timeout_ns);
        (*cur).state = State::Waiting;
        switch_away();
        let result = (*cur).wait_result;
        if result == 0 && !take(value_out) {
            fault::fatal(b"runtime invariant: woken token without a post");
        }
        result
    }
}

/// Posts `value` to `id` from the runtime thread: wakes its waiter, or keeps the post for the
/// next park. A post to a freed token, or to one that already holds a post, is dropped.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_token_post(id: u64, value: u64) {
    // SAFETY: single threaded scheduler.
    unsafe {
        ensure_init();
        post(id, value, false);
    }
}

/// Posts `value` to `id` from any thread. It takes effect when the scheduler next looks, and
/// interrupts a scheduler that is blocked. Touches no runtime state but a locked queue.
/// A post to a token that already holds an untaken post is coalesced into it: a token carries a wake, not a
/// count, so a waiter re-checks its own state after waking (promise waits and pipes do; they never lose work).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_token_post_remote(id: u64, value: u64) {
    isolate::post_remote(id, value);
}

/// Ends `id`: later posts to it are dropped and its slot is reused. Faults while a task waits
/// on it. Freeing a token that does not exist does nothing.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_token_free(id: u64) {
    // SAFETY: single threaded scheduler.
    unsafe {
        ensure_init();
        let mut s = sched();
        let Some(k) = token_mut(&mut s, id) else {
            return;
        };
        if k.waiter != 0 {
            fault::fault(b"a token was freed while a task waits on it");
        }
        k.live = false;
        k.posted = None;
        let remote = std::mem::replace(&mut k.remote, false);
        let peer = core::mem::take(&mut k.peer);
        let reusable = k.gen_ < GEN_MASK;
        if remote {
            s.remote_tokens -= 1;
            s.peer_tokens -= usize::from(peer);
        }
        // Retire an exhausted slot instead of wrapping back to a still-stale id.
        if reusable {
            s.free_tokens.push((id & 0xffff_ffff) as usize - 1);
        }
    }
}

/// Drops all scheduler state: a worker isolate calls it as it ends; unit tests run several
/// scenarios in one process; the leak sweep calls it at exit so only real leaks remain in the
/// live-block count.
pub fn teardown() {
    crate::promise::teardown();
    fault::retire_hdr();
    // SAFETY: callers hold the global lock or run after main returned; no task is mid-switch.
    unsafe {
        let mut s = sched();
        for i in 0..s.slots.len() {
            let t = s.slots[i].task;
            if !t.is_null() {
                let base = (*t).stack;
                if !base.is_null() {
                    release_stack(base as usize, (*t).stack_len);
                }
                core::ptr::drop_in_place(t);
                alloc::free(t as *mut u8);
            }
        }
        if s.epfd >= 0 {
            crate::poller::close(s.epfd);
        }
        // The isolate's pool owns mappings too. Its thread-local state has no destructor,
        // so a worker that exits must release the cached stacks as well as active ones.
        s.pool = Vec::new();
        s.pool_clean = 0;
        s.carve = (0, 0);
        for base in core::mem::take(&mut s.regions) {
            sys::unmap(base as *mut u8, REGION);
        }
        s.round = 0;
        s.scan = 0;
        s.cur = null_mut();
        s.main = null_mut();
        s.ready = VecDeque::new();
        s.slots = Vec::new();
        s.free_slots = Vec::new();
        s.timers = BinaryHeap::new();
        s.kills = BinaryHeap::new();
        s.timer_limit = MIN_TIMER_LIMIT;
        s.kill_limit = MIN_TIMER_LIMIT;
        s.fd_waiters = Vec::new();
        s.fd_waiting = 0;
        s.epfd = -1;
        s.zombie_stack = (0, 0);
        s.zombie_task = null_mut();
        s.live = 0;
        if !s.tokens.is_empty() {
            isolate::save_token_generations(s.tokens.iter().map(|token| token.gen_).collect());
        }
        s.tokens = Vec::new();
        s.free_tokens = Vec::new();
        s.remote_tokens = 0;
        s.peer_tokens = 0;
        isolate::clear_posts();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::global::Process;
    use crate::testutil::lock;

    static LOG: Process<[u8; 16]> = Process::new([0; 16]);
    static LOG_N: Process<usize> = Process::new(0);

    /// A binding held across another `sched()` access must stay valid; Miri's Stacked Borrows
    /// rejected the previous `&'static mut` return here.
    #[test]
    fn scheduler_handles_do_not_alias() {
        let _g = lock();
        let mut held = sched();
        let before = held.live;
        sched().live += 1;
        held.live += 1;
        assert_eq!(held.live, before + 2);
        sched().live -= 2;
    }

    fn note(v: u8) {
        // SAFETY: tests hold the lock; the log has room for 16 entries.
        unsafe {
            let n = *LOG_N.ptr();
            (*LOG.ptr())[n] = v;
            *LOG_N.ptr() = n + 1;
        }
    }

    unsafe extern "C-unwind" fn counter(arg: *mut u8) {
        let id = arg as usize as u8;
        for i in 0..3 {
            note(id * 10 + i);
            // SAFETY: called from a running task.
            unsafe { msrt_task_yield() };
        }
    }

    unsafe extern "C-unwind" fn sleeper(arg: *mut u8) {
        // SAFETY: called from a running task.
        let r = unsafe { msrt_task_sleep(arg as usize as i64 * 1_000_000) };
        note(if r == WAIT_TIMEOUT {
            arg as usize as u8
        } else {
            99
        });
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn tasks_interleave_sleep_and_join() {
        let _g = lock();
        teardown();
        // SAFETY: tests hold the global lock; every handle is joined once.
        unsafe {
            *LOG_N.ptr() = 0;
            let a = msrt_task_spawn(counter, core::ptr::without_provenance_mut(1), 0, 0);
            let b = msrt_task_spawn(counter, core::ptr::without_provenance_mut(2), 0, 0);
            assert_eq!(msrt_task_join(a, null_mut()), 0);
            assert_eq!(msrt_task_join(b, null_mut()), 0);
            assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[10, 20, 11, 21, 12, 22]);

            *LOG_N.ptr() = 0;
            let slow = msrt_task_spawn(sleeper, core::ptr::without_provenance_mut(20), 0, 0);
            let fast = msrt_task_spawn(sleeper, core::ptr::without_provenance_mut(5), 0, 0);
            assert_eq!(msrt_task_join(slow, null_mut()), 0);
            assert_eq!(msrt_task_join(fast, null_mut()), 0);
            assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[5, 20]);
            assert_eq!(msrt_task_count(), 1);
        }
        teardown();
    }

    unsafe extern "C-unwind" fn deadlocked_token(arg: *mut u8) {
        // SAFETY: the test owns the live token and deliberately supplies no completion.
        unsafe { msrt_token_park(arg as u64, -1, null_mut()) };
    }

    unsafe extern "C-unwind" fn deadlocked_join(arg: *mut u8) {
        // SAFETY: the test owns the live task, which has no matching completion.
        unsafe { msrt_task_join(arg as u64, null_mut()) };
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_deadlocked_token_wait_releases_its_registration() {
        let _g = lock();
        teardown();
        // SAFETY: the guard contains the deliberate deadlock and all state is isolate-local.
        unsafe {
            let token = msrt_token_new(0);
            let status = fault::msrt_guard_call(deadlocked_token, token as *mut u8, null_mut());
            let waiter = token_mut(&mut sched(), token).unwrap().waiter;
            let running = (*sched().cur).state == State::Running;
            teardown();
            assert_eq!(status, 1);
            assert_eq!(waiter, 0, "a faulted wait must release its token");
            assert!(running, "fault cleanup must run as a running task");
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_deadlocked_join_releases_the_targets_joiner() {
        let _g = lock();
        teardown();
        // SAFETY: the guard contains the deliberate deadlock and teardown releases the task.
        unsafe {
            let token = msrt_token_new(0);
            let target = msrt_task_spawn(deadlocked_token, token as *mut u8, 0, 0);
            msrt_task_yield();
            let status = fault::msrt_guard_call(deadlocked_join, target as *mut u8, null_mut());
            let joiner = (*lookup(target)).joiner;
            let running = (*sched().cur).state == State::Running;
            teardown();
            assert_eq!(status, 1);
            assert_eq!(joiner, 0, "a faulted join must stop claiming its target");
            assert!(running, "fault cleanup must run as a running task");
        }
    }

    #[test]
    #[cfg(unix)]
    fn idle_trim_keeps_the_newest_pooled_stacks_warm() {
        let _g = lock();
        teardown();
        // SAFETY: a fabricated pool entry is a mapped slot that no task uses.
        unsafe {
            let n = STACK_POOL_WARM + 3;
            let slots: Vec<usize> = (0..n).map(|_| stack::create(SLOT) as usize).collect();
            for &base in &slots {
                assert!(base != 0);
                // Touch the top page, where a stack's first frames live.
                *((base + SLOT - 4096) as *mut u8) = 1;
                release_stack(base, SLOT);
            }
            trim_idle_stacks();
            assert_eq!(sched().pool_clean, 3);
            // The warm stacks keep their contents. A trimmed stack's pages went back to the
            // system, but macOS frees them lazily, so what they read as is unspecified; they
            // must stay writable.
            for (at, &base) in slots.iter().enumerate() {
                let page = (base + SLOT - 4096) as *mut u8;
                if at >= 3 {
                    assert_eq!(*page, 1, "warm stack {at}");
                }
                *page = 2;
                assert_eq!(*page, 2, "stack {at} stays usable");
            }
            // Taking a stack back lowers the clean mark only when an older entry moves.
            let _ = alloc_stack(SLOT);
            assert_eq!(sched().pool_clean, 3);
            teardown();
        }
    }

    #[test]
    #[cfg(unix)]
    fn teardown_unmaps_pooled_task_stacks() {
        let _g = lock();
        teardown();
        // SAFETY: the entry ignores its argument and the test joins the task once.
        unsafe {
            let h = msrt_task_spawn(long_wait, null_mut(), 0, 0);
            msrt_task_cancel(h);
            assert_eq!(msrt_task_join(h, null_mut()), 0);
            let pooled = sched()
                .pool
                .iter()
                .map(|&(base, _)| base)
                .collect::<Vec<_>>();
            assert!(
                !pooled.is_empty(),
                "the completed stack must enter the pool"
            );
            let page_size = libc::sysconf(libc::_SC_PAGESIZE);
            assert!(page_size > 0);
            let page_size = page_size as usize;
            for &base in &pooled {
                assert_eq!(
                    libc::msync(base as *mut core::ffi::c_void, page_size, libc::MS_ASYNC),
                    0,
                    "the control stack must still be mapped before teardown"
                );
            }
            teardown();
            for base in pooled {
                // Darwin mincore reports residency even for holes. msync checks mappings:
                // an unmapped page must fail with ENOMEM on both Darwin and Linux.
                for offset in (0..SLOT).step_by(page_size) {
                    assert_eq!(
                        libc::msync(
                            (base + offset) as *mut core::ffi::c_void,
                            page_size,
                            libc::MS_ASYNC
                        ),
                        -1,
                        "teardown left a task stack page mapped"
                    );
                    assert_eq!(
                        std::io::Error::last_os_error().raw_os_error(),
                        Some(libc::ENOMEM)
                    );
                }
            }
        }
    }

    /// Parks on the token in `arg`, then writes what it found on its stack into the token's
    /// value slot, so a hibernation that lost or moved the stack shows.
    unsafe extern "C-unwind" fn park_on_token(arg: *mut u8) {
        let token = arg as usize as u64;
        let marker = std::hint::black_box([0x5a5a_u16; 512]);
        let mut value = 0;
        // SAFETY: called on a live task; the test posts the token.
        unsafe {
            msrt_token_park(token, -1, &mut value);
            let sum: u64 = std::hint::black_box(&marker)
                .iter()
                .map(|&m| m as u64)
                .sum();
            assert_eq!(sum, 0x5a5a * 512, "stack contents survived hibernation");
        }
    }

    #[test]
    fn parked_tasks_hibernate_and_resume_on_the_same_stack() {
        let _g = lock();
        teardown();
        // SAFETY: the test owns the token and joins the task.
        unsafe {
            let token = msrt_token_new(0);
            let h = msrt_task_spawn(park_on_token, token as usize as *mut u8, 0, 0);
            msrt_task_yield();
            let t = lookup(h);
            assert!((*t).state == State::Waiting);
            assert!((*t).frozen.is_null());
            // Two idle rounds after the park: the task gives its pages back.
            hibernate_idle();
            hibernate_idle();
            hibernate_idle();
            assert!(
                !(*t).frozen.is_null(),
                "a task parked for two rounds hibernates"
            );
            let top = stack_top((*t).stack as usize, (*t).stack_len);
            assert_eq!((*t).frozen_len, top - (*t).sp);
            // The copy holds the parked frames: the marker array `park_on_token` keeps live.
            let copy = core::slice::from_raw_parts((*t).frozen, (*t).frozen_len);
            let markers = copy
                .as_chunks::<2>()
                .0
                .iter()
                .filter(|w| w == &&[0x5a, 0x5a])
                .count();
            assert!(
                markers >= 512,
                "the frozen copy holds the stack ({markers} marker words)"
            );
            msrt_token_post(token, 7);
            assert_eq!(msrt_task_join(h, null_mut()), 0);
            assert!(sched().pool.iter().any(|&(base, _)| base == top - SLOT));
            msrt_token_free(token);
            teardown();
        }
    }

    static PARK_RESULT: core::sync::atomic::AtomicU32 = core::sync::atomic::AtomicU32::new(0);

    /// Parks on the read end of the pipe in `arg` and records what the wait returned.
    unsafe extern "C-unwind" fn park_on_fd(arg: *mut u8) {
        let fd = arg as usize as i32;
        // SAFETY: called on a live task; the test cancels it.
        let got = unsafe { msrt_task_wait_fd(fd, WAIT_READ, -1) };
        PARK_RESULT.store(got, Ordering::Relaxed);
    }

    /// A connected socket pair, the waitable descriptor every platform has.
    fn socket_pair() -> (std::net::TcpStream, std::net::TcpStream) {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let client = std::net::TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let (server, _) = listener.accept().unwrap();
        (client, server)
    }

    fn raw_socket(stream: &std::net::TcpStream) -> i32 {
        #[cfg(unix)]
        {
            std::os::fd::AsRawFd::as_raw_fd(stream)
        }
        #[cfg(windows)]
        {
            std::os::windows::io::AsRawSocket::as_raw_socket(stream) as i32
        }
    }

    #[test]
    fn a_hibernating_task_sees_its_cancellation() {
        let _g = lock();
        teardown();
        let (client, _server) = socket_pair();
        let fd = raw_socket(&client);
        // SAFETY: the test keeps the sockets open and joins the task.
        unsafe {
            PARK_RESULT.store(0, Ordering::Relaxed);
            let h = msrt_task_spawn(park_on_fd, fd as usize as *mut u8, 0, 0);
            msrt_task_yield();
            let t = lookup(h);
            assert!((*t).state == State::Waiting);
            hibernate_idle();
            hibernate_idle();
            hibernate_idle();
            assert!(!(*t).frozen.is_null(), "the parked task hibernates");
            msrt_task_cancel(h);
            assert_eq!(msrt_task_join(h, null_mut()), 0);
            assert_eq!(
                PARK_RESULT.load(Ordering::Relaxed) & WAIT_CANCELLED,
                WAIT_CANCELLED
            );
            teardown();
        }
    }

    static WORK_TOKEN: core::sync::atomic::AtomicU64 = core::sync::atomic::AtomicU64::new(0);
    static PROMISE_ID: core::sync::atomic::AtomicI64 = core::sync::atomic::AtomicI64::new(0);

    unsafe extern "C" fn drop_closure(obj: *mut ms_rt_abi::Obj) {
        // SAFETY: the capture-free closure owns this allocation.
        unsafe { alloc::free(obj.cast()) };
    }

    /// A promise's work: parks on `WORK_TOKEN` until the test posts it.
    unsafe extern "C-unwind" fn promise_work(_: *mut ms_rt_abi::Closure) {
        let mut value = 0;
        // SAFETY: called from the promise's task.
        unsafe { msrt_token_park(WORK_TOKEN.load(Ordering::Relaxed), -1, &mut value) };
    }

    /// Starts a promise (whose work reads this frame) and parks on the token in `arg`.
    unsafe extern "C-unwind" fn start_promise_then_park(arg: *mut u8) {
        let token = arg as usize as u64;
        let mut value = 0;
        // SAFETY: the closure is handed to the promise; the test ends the work and drops the promise.
        unsafe {
            let id = crate::promise::msrt_promise_new();
            let closure = crate::obj::new_obj(size_of::<ms_rt_abi::Closure>(), None, drop_closure)
                .cast::<ms_rt_abi::Closure>();
            (*closure).code = promise_work as *const u8;
            crate::promise::msrt_promise_start_here(id, closure);
            PROMISE_ID.store(id, Ordering::Relaxed);
            msrt_token_park(token, -1, &mut value);
        }
    }

    #[test]
    fn a_task_whose_promise_still_runs_does_not_hibernate() {
        let _g = lock();
        teardown();
        // SAFETY: the test owns the tokens, ends the promise's work and joins the task.
        unsafe {
            let token = msrt_token_new(0);
            let work = msrt_token_new(0);
            WORK_TOKEN.store(work, Ordering::Relaxed);
            let h = msrt_task_spawn(start_promise_then_park, token as usize as *mut u8, 0, 0);
            msrt_task_yield();
            msrt_task_yield();
            let t = lookup(h);
            assert!((*t).state == State::Waiting);
            hibernate_idle();
            hibernate_idle();
            hibernate_idle();
            assert!(
                (*t).frozen.is_null(),
                "a task whose promise may read its frame keeps its pages"
            );
            // The work ends: its task reports to the creator, whose stack is its own again.
            msrt_token_post(work, 1);
            let id = PROMISE_ID.load(Ordering::Relaxed);
            // The work put no result, so the promise reports a failure; it is over all the same.
            assert_eq!(
                crate::promise::msrt_promise_wait(id, -1),
                crate::promise::FAILED
            );
            crate::promise::msrt_promise_drop(id);
            hibernate_idle();
            hibernate_idle();
            hibernate_idle();
            assert!(
                !(*t).frozen.is_null(),
                "the task hibernates once the promise is over"
            );
            msrt_token_post(token, 1);
            assert_eq!(msrt_task_join(h, null_mut()), 0);
            msrt_token_free(token);
            msrt_token_free(work);
            teardown();
        }
    }

    /// Parks on the token in `arg` with its stack lent out, as a pool job's borrow does.
    unsafe extern "C-unwind" fn park_pinned(arg: *mut u8) {
        let token = arg as usize as u64;
        let mut value = 0;
        // SAFETY: called on a live task; the test posts the token.
        unsafe {
            pin_current(true);
            msrt_token_park(token, -1, &mut value);
            pin_current(false);
        }
    }

    /// Grows onto a segment twice over (the shim grows once more), checks each run is inside the
    /// segment's bounds with the segment's limit, and that the home segment is back afterwards.
    unsafe extern "C-unwind" fn grow_twice(arg: *mut u8) {
        // SAFETY: called on a live task.
        unsafe {
            let cur = ensure_init();
            let home = fault::segment_state();
            let mut probe = [0usize; 2];
            msrt_task_grow(on_segment, probe.as_mut_ptr().cast());
            assert_eq!((*cur).seg, 0);
            assert_eq!(fault::segment_state(), home);
            assert_eq!(probe[0], 2, "the shim ran on two segments");
            assert!(
                probe[1] < home.0 || probe[1] >= home.1,
                "the shim ran outside the home slot"
            );
            assert_eq!((*cur).segs.len(), 2);
            // The segments stay with the task: growing again allocates nothing.
            probe = [0; 2];
            msrt_task_grow(on_segment, probe.as_mut_ptr().cast());
            assert_eq!((*cur).segs.len(), 2);
            // A guard exit from a segment is the e2e fixture `task-stack-growth`'s to check:
            // the test build's guard unwinds a Rust panic, which cannot cross stacks on Windows.
            *(arg as *mut usize) = 1;
        }
    }

    unsafe extern "C-unwind" fn on_segment(block: *mut u8) {
        // SAFETY: `block` is the probe of `grow_twice`.
        unsafe {
            let cur = ensure_init();
            let p = block as *mut usize;
            let local = 0usize;
            let sp = core::ptr::addr_of!(local) as usize;
            let (lo, hi, chain) = fault::segment_state();
            assert!(
                sp >= lo && sp < hi,
                "the shim runs within the segment's bounds"
            );
            assert_ne!(chain, 0, "a grown segment chains to the one below");
            assert_eq!((*cur).hdr.limit, fault::stack_limit(lo, hi));
            *p.add(1) = sp;
            *p += 1;
            if *p < 2 {
                msrt_task_grow(on_segment, block);
            }
        }
    }

    #[test]
    fn a_task_grows_onto_segments_and_comes_back() {
        let _g = lock();
        teardown();
        // SAFETY: the test joins the task.
        unsafe {
            let mut done = 0usize;
            let h = msrt_task_spawn(grow_twice, core::ptr::addr_of_mut!(done).cast(), 0, 0);
            assert_eq!(msrt_task_join(h, null_mut()), 0);
            assert_eq!(done, 1);
            // The task's segments went back to the pool with its slot.
            assert_eq!(sched().pool.len(), 3);
            teardown();
        }
    }

    #[test]
    fn a_task_whose_stack_is_lent_out_does_not_hibernate() {
        let _g = lock();
        teardown();
        // SAFETY: the test owns the token and joins the task.
        unsafe {
            let token = msrt_token_new(0);
            let h = msrt_task_spawn(park_pinned, token as usize as *mut u8, 0, 0);
            msrt_task_yield();
            let t = lookup(h);
            assert!((*t).state == State::Waiting);
            hibernate_idle();
            hibernate_idle();
            hibernate_idle();
            assert!((*t).frozen.is_null(), "a lent stack keeps its pages");
            msrt_token_post(token, 1);
            assert_eq!(msrt_task_join(h, null_mut()), 0);
            msrt_token_free(token);
            teardown();
        }
    }

    unsafe extern "C-unwind" fn long_wait(_: *mut u8) {
        // SAFETY: called on a live task; the test cancels it after checking the heap.
        unsafe { msrt_task_sleep(3_600_000_000_000) };
    }

    unsafe extern "C-unwind" fn short_sleeps(_: *mut u8) {
        for _ in 0..100 {
            // SAFETY: called from a running task.
            unsafe { msrt_task_sleep(100_000) };
        }
    }

    /// A timer shorter than a millisecond must not wait a whole one (the poll timeout used to
    /// round up): 100 sleeps of 100 us take about 10 ms, and at least 100 ms when rounded up.
    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn sleeps_shorter_than_a_millisecond_are_not_rounded_up() {
        let _g = lock();
        teardown();
        let mut best = u64::MAX;
        // SAFETY: tests hold the global lock; every handle is joined once.
        unsafe {
            // The best of a few runs, so a loaded machine does not fail the test.
            for _ in 0..3 {
                let start = std::time::Instant::now();
                let h = msrt_task_spawn(short_sleeps, null_mut(), 0, 0);
                assert_eq!(msrt_task_join(h, null_mut()), 0);
                best = best.min(start.elapsed().as_millis() as u64);
            }
        }
        teardown();
        assert!(best < 80, "100 sleeps of 100 us took {best} ms");
    }

    unsafe extern "C-unwind" fn busy(_: *mut u8) {
        for _ in 0..100 {
            // SAFETY: called from a running task.
            unsafe { msrt_task_yield() };
        }
        note(2);
    }

    unsafe extern "C-unwind" fn immediate_timer(_: *mut u8) {
        // SAFETY: called from a running task.
        assert_eq!(unsafe { msrt_task_sleep(0) }, WAIT_TIMEOUT);
        note(1);
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn timers_progress_while_tasks_stay_ready() {
        let _g = lock();
        teardown();
        // SAFETY: tests hold the global lock; every handle is joined once.
        unsafe {
            *LOG_N.ptr() = 0;
            let timer = msrt_task_spawn(immediate_timer, null_mut(), 0, 0);
            let spinner = msrt_task_spawn(busy, null_mut(), 0, 0);
            assert_eq!(msrt_task_join(timer, null_mut()), 0);
            assert_eq!(msrt_task_join(spinner, null_mut()), 0);
            assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[1, 2]);
        }
        teardown();
    }

    unsafe extern "C-unwind" fn posted_token(arg: *mut u8) {
        let mut value = 0;
        // SAFETY: the test keeps this token live through the join.
        assert_eq!(unsafe { msrt_token_park(arg as u64, -1, &mut value) }, 0);
        assert_eq!(value, 42);
        note(1);
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn remote_posts_progress_while_tasks_stay_ready() {
        let _g = lock();
        teardown();
        // SAFETY: tests hold the global lock; every handle is joined once.
        unsafe {
            *LOG_N.ptr() = 0;
            let token = msrt_token_new(TOKEN_REMOTE);
            let waiter = msrt_task_spawn(posted_token, token as *mut u8, 0, 0);
            let spinner = msrt_task_spawn(busy, null_mut(), 0, 0);
            std::thread::spawn(move || msrt_token_post_remote(token, 42))
                .join()
                .unwrap();
            assert_eq!(msrt_task_join(waiter, null_mut()), 0);
            assert_eq!(msrt_task_join(spinner, null_mut()), 0);
            msrt_token_free(token);
            assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[1, 2]);
        }
        teardown();
    }

    /// A wait for a plain thread (a blocking-pool job, a helper) is not a deadlock even while a
    /// token that only another isolate could post is also pending.
    #[test]
    fn a_thread_post_is_not_a_deadlock_beside_a_pending_peer_token() {
        let _g = lock();
        teardown();
        // SAFETY: tests hold the global lock; the test thread plays the main isolate.
        unsafe {
            let peer = msrt_token_new(TOKEN_REMOTE | TOKEN_PEER);
            let plain = msrt_token_new(TOKEN_REMOTE);
            std::thread::spawn(move || {
                std::thread::sleep(std::time::Duration::from_millis(50));
                msrt_token_post_remote(plain, 7);
            });
            let mut value = 0;
            assert_eq!(msrt_token_park(plain, -1, &mut value), 0);
            assert_eq!(value, 7);
            msrt_token_free(plain);
            msrt_token_free(peer);
        }
        teardown();
    }

    static TOKEN: Process<u64> = Process::new(0);
    static GOT: Process<(u32, u64)> = Process::new((0, 0));

    unsafe extern "C-unwind" fn token_parker(arg: *mut u8) {
        let mut v = 0;
        // SAFETY: called from a running task; the token outlives the park.
        let r = unsafe { msrt_token_park(*TOKEN.ptr(), arg as usize as i64, &mut v) };
        // SAFETY: tests hold the lock.
        unsafe { *GOT.ptr() = (r, v) };
    }

    unsafe extern "C-unwind" fn token_poster(arg: *mut u8) {
        // SAFETY: called from a running task.
        unsafe { msrt_token_post(*TOKEN.ptr(), arg as usize as u64) };
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn tokens_deliver_posts_made_before_and_during_a_park() {
        let _g = lock();
        teardown();
        // SAFETY: tests hold the global lock; every handle is joined once.
        unsafe {
            let id = msrt_token_new(0);
            msrt_token_post(id, 7);
            // A second post while the first is untaken is dropped.
            msrt_token_post(id, 8);
            let mut v = 0;
            assert_eq!(msrt_token_park(id, -1, &mut v), 0);
            assert_eq!(v, 7);

            // The park took the post: the next one waits for a new post.
            *TOKEN.ptr() = id;
            let parker = msrt_task_spawn(
                token_parker,
                core::ptr::without_provenance_mut(usize::MAX),
                0,
                0,
            );
            let poster = msrt_task_spawn(token_poster, core::ptr::without_provenance_mut(9), 0, 0);
            assert_eq!(msrt_task_join(parker, null_mut()), 0);
            assert_eq!(msrt_task_join(poster, null_mut()), 0);
            assert_eq!(*GOT.ptr(), (0, 9));
            msrt_token_free(id);
        }
        teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_timed_out_park_keeps_the_token_and_the_late_post() {
        let _g = lock();
        teardown();
        // SAFETY: tests hold the global lock.
        unsafe {
            let id = msrt_token_new(0);
            let mut v = 0;
            assert_eq!(msrt_token_park(id, 1_000_000, &mut v), WAIT_TIMEOUT);
            msrt_token_post(id, 3);
            assert_eq!(msrt_token_park(id, 1_000_000, &mut v), 0);
            assert_eq!(v, 3);
            msrt_token_free(id);
        }
        teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn cancelling_a_task_parked_on_a_token_releases_the_token() {
        let _g = lock();
        teardown();
        // SAFETY: tests hold the global lock; the handle is joined once.
        unsafe {
            let id = msrt_token_new(0);
            *TOKEN.ptr() = id;
            let parker = msrt_task_spawn(
                token_parker,
                core::ptr::without_provenance_mut(usize::MAX),
                0,
                0,
            );
            msrt_task_yield();
            msrt_task_cancel(parker);
            assert_eq!(msrt_task_join(parker, null_mut()), 0);
            assert_eq!((*GOT.ptr()).0, WAIT_CANCELLED);
            // Nobody waits any more, so the token can be freed.
            msrt_token_free(id);
        }
        teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn posts_to_a_freed_token_do_not_reach_its_reused_slot() {
        let _g = lock();
        teardown();
        // SAFETY: tests hold the global lock.
        unsafe {
            let old = msrt_token_new(0);
            msrt_token_free(old);
            let new = msrt_token_new(0);
            assert_eq!(old & 0xffff_ffff, new & 0xffff_ffff, "the slot is reused");
            assert_ne!(old, new);
            msrt_token_post(old, 1);
            msrt_token_post_remote(old, 2);
            let mut v = 0;
            assert_eq!(msrt_token_park(new, 1_000_000, &mut v), WAIT_TIMEOUT);
            msrt_token_free(new);
        }
        teardown();
    }

    #[test]
    fn an_exhausted_token_generation_does_not_revive_a_stale_id() {
        let _g = lock();
        teardown();
        // SAFETY: tests hold the runtime lock and own both tokens.
        unsafe {
            let old = msrt_token_new(0);
            // Exercise the last generation without spending a million cycles reaching it.
            let slot = (old as u32 as usize) - 1;
            sched().tokens[slot].gen_ = GEN_MASK;
            let generation_mask = u64::from(GEN_MASK) << 32;
            msrt_token_free((old & !generation_mask) | generation_mask);
            let new = msrt_token_new(0);
            msrt_token_post(old, 42);
            let result = msrt_token_park(new, 1_000_000, null_mut());
            msrt_token_free(new);
            teardown();
            assert_eq!(result, WAIT_TIMEOUT, "a stale post reached a wrapped token");
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_remote_post_wakes_a_parked_scheduler() {
        let _g = lock();
        teardown();
        // SAFETY: tests hold the global lock.
        unsafe {
            let id = msrt_token_new(TOKEN_REMOTE);
            let poster = std::thread::spawn(move || {
                std::thread::sleep(std::time::Duration::from_millis(20));
                msrt_token_post_remote(id, 42);
            });
            // No timer and no descriptor: only the pending remote post keeps this from being
            // reported as a deadlock.
            let mut v = 0;
            assert_eq!(msrt_token_park(id, -1, &mut v), 0);
            assert_eq!(v, 42);
            assert_eq!(sched().remote_tokens, 0);
            poster.join().unwrap();
            msrt_token_free(id);
        }
        teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn freeing_an_unposted_remote_token_stops_counting_it() {
        let _g = lock();
        teardown();
        // SAFETY: tests hold the global lock.
        unsafe {
            let id = msrt_token_new(TOKEN_REMOTE);
            assert_eq!(sched().remote_tokens, 1);
            msrt_token_free(id);
            assert_eq!(sched().remote_tokens, 0);
            // The late post is dropped when it is delivered.
            msrt_token_post_remote(id, 1);
            deliver_remote_posts();
            assert_eq!(sched().remote_tokens, 0);
        }
        teardown();
    }

    #[cfg(unix)]
    mod fd_waits {
        use super::*;

        static RESULT: Process<u32> = Process::new(0);

        fn pipe() -> [i32; 2] {
            let mut fds = [0i32; 2];
            // SAFETY: `fds` has room for the two descriptors.
            assert_eq!(unsafe { sys::pipe(fds.as_mut_ptr()) }, 0);
            fds
        }

        fn put(fd: i32) {
            // SAFETY: writes one byte from a live buffer.
            assert_eq!(unsafe { sys::write(fd, b"x".as_ptr().cast(), 1) }, 1);
        }

        unsafe extern "C-unwind" fn reader(arg: *mut u8) {
            // SAFETY: called from a running task; `arg` is a pipe read end.
            let r = unsafe { msrt_task_wait_fd(arg as usize as i32, WAIT_READ, 2_000_000_000) };
            // SAFETY: tests hold the lock.
            unsafe { *RESULT.ptr() = r };
        }

        unsafe extern "C-unwind" fn writer(arg: *mut u8) {
            // SAFETY: called from a running task.
            unsafe { msrt_task_sleep(5_000_000) };
            put(arg as usize as i32);
        }

        fn close_all(fds: [i32; 2]) {
            // SAFETY: both descriptors are open and owned by the test.
            unsafe {
                sys::close(fds[0]);
                sys::close(fds[1]);
            }
        }

        #[test]
        fn timers_of_woken_waits_do_not_pile_up() {
            let _g = lock();
            teardown();
            let fds = pipe();
            put(fds[1]);
            // SAFETY: tests hold the global lock; the descriptor stays open.
            unsafe {
                // A sleeper with an earlier deadline holds the heap's head, so the stale entries
                // behind it are never popped lazily.
                msrt_task_spawn(sleeper, core::ptr::without_provenance_mut(10_000), 0, 0);
                // Each wait returns at once (the byte stays unread) and leaves its hour-long
                // deadline in the heap; the heap must not keep all of them.
                for _ in 0..10 * MIN_TIMER_LIMIT {
                    let r = msrt_task_wait_fd(fds[0], WAIT_READ, 3_600_000_000_000);
                    assert_eq!(r & WAIT_READ, WAIT_READ);
                }
                assert!(sched().timers.len() <= 2 * MIN_TIMER_LIMIT);
            }
            close_all(fds);
            teardown();
        }

        unsafe extern "C-unwind" fn ready_reader(arg: *mut u8) {
            // SAFETY: the test owns this pipe until the task joins.
            let result = unsafe { msrt_task_wait_fd(arg as i32, WAIT_READ, -1) };
            assert_ne!(result & WAIT_READ, 0);
            note(1);
        }

        #[test]
        #[cfg_attr(miri, ignore = "context switches use inline assembly")]
        fn io_progresses_while_tasks_stay_ready() {
            let _g = lock();
            teardown();
            let fds = pipe();
            put(fds[1]);
            // SAFETY: tests hold the global lock; the pipe stays open through both joins.
            unsafe {
                *LOG_N.ptr() = 0;
                let reader = msrt_task_spawn(ready_reader, fds[0] as *mut u8, 0, 0);
                let spinner = msrt_task_spawn(busy, null_mut(), 0, 0);
                assert_eq!(msrt_task_join(reader, null_mut()), 0);
                assert_eq!(msrt_task_join(spinner, null_mut()), 0);
                assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[1, 2]);
            }
            close_all(fds);
            teardown();
        }

        #[test]
        fn wakes_on_readable_then_stays_ready() {
            let _g = lock();
            teardown();
            let fds = pipe();
            // SAFETY: tests hold the global lock; every handle is joined once.
            unsafe {
                *RESULT.ptr() = 0;
                let r = msrt_task_spawn(
                    reader,
                    core::ptr::without_provenance_mut(fds[0] as usize),
                    0,
                    0,
                );
                let w = msrt_task_spawn(
                    writer,
                    core::ptr::without_provenance_mut(fds[1] as usize),
                    0,
                    0,
                );
                assert_eq!(msrt_task_join(r, null_mut()), 0);
                assert_eq!(msrt_task_join(w, null_mut()), 0);
                assert_eq!(*RESULT.ptr() & WAIT_READ, WAIT_READ);
                // Level triggered: the byte is still unread, so a new wait returns at once.
                assert_eq!(
                    msrt_task_wait_fd(fds[0], WAIT_READ, 1_000_000_000) & WAIT_READ,
                    WAIT_READ
                );
            }
            close_all(fds);
            teardown();
        }

        unsafe extern "C-unwind" fn shared_reader(arg: *mut u8) {
            // SAFETY: the test owns this pipe until the tasks join.
            let result = unsafe { msrt_task_wait_fd(arg as i32, WAIT_READ, 2_000_000_000) };
            note(if result & WAIT_READ != 0 { 1 } else { 2 });
        }

        unsafe extern "C-unwind" fn impatient_reader(arg: *mut u8) {
            // SAFETY: as `shared_reader`.
            let result = unsafe { msrt_task_wait_fd(arg as i32, WAIT_READ, 5_000_000) };
            note(if result == WAIT_TIMEOUT { 3 } else { 4 });
        }

        #[test]
        #[cfg_attr(miri, ignore = "context switches use inline assembly")]
        fn several_tasks_wait_on_one_descriptor() {
            let _g = lock();
            teardown();
            let fds = pipe();
            // SAFETY: tests hold the global lock; the pipe stays open through every join.
            unsafe {
                *LOG_N.ptr() = 0;
                let fd = core::ptr::without_provenance_mut(fds[0] as usize);
                let a = msrt_task_spawn(shared_reader, fd, 0, 0);
                let b = msrt_task_spawn(shared_reader, fd, 0, 0);
                // One waiter leaves by timeout; the others must stay registered.
                let c = msrt_task_spawn(impatient_reader, fd, 0, 0);
                let w = msrt_task_spawn(
                    writer,
                    core::ptr::without_provenance_mut(fds[1] as usize),
                    0,
                    0,
                );
                for h in [a, b, c, w] {
                    assert_eq!(msrt_task_join(h, null_mut()), 0);
                }
                let mut log = (&(*LOG.ptr()))[..*LOG_N.ptr()].to_vec();
                log.sort();
                assert_eq!(log, [1, 1, 3]);
            }
            close_all(fds);
            teardown();
        }

        #[test]
        fn times_out_when_nothing_arrives() {
            let _g = lock();
            teardown();
            let fds = pipe();
            // SAFETY: tests hold the global lock.
            let got = unsafe { msrt_task_wait_fd(fds[0], WAIT_READ, 10_000_000) };
            assert_eq!(got, WAIT_TIMEOUT);
            close_all(fds);
            teardown();
        }

        #[test]
        fn writable_end_is_ready() {
            let _g = lock();
            teardown();
            let fds = pipe();
            // SAFETY: tests hold the global lock.
            let got = unsafe { msrt_task_wait_fd(fds[1], WAIT_WRITE, 1_000_000_000) };
            assert_eq!(got & WAIT_WRITE, WAIT_WRITE);
            close_all(fds);
            teardown();
        }
    }

    /// Runs `f` as a shielded cleanup action would: cancellation is off until it returns.
    fn shielded_call<R>(f: impl FnOnce() -> R) -> R {
        fault::SHIELD.set(fault::SHIELD.get() + 1);
        cancel_flag().store(0, Ordering::Relaxed);
        let r = f();
        fault::SHIELD.set(fault::SHIELD.get() - 1);
        r
    }

    unsafe extern "C-unwind" fn shielded_sleeper(_: *mut u8) {
        let r = shielded_call(|| {
            // SAFETY: called from a running task.
            unsafe { msrt_task_sleep(3_000_000) }
        });
        note(if r == WAIT_TIMEOUT { 1 } else { 2 });
    }

    /// Clears the simulated stop request even when an assertion fails.
    struct StopRequest;

    impl StopRequest {
        fn raise() -> Self {
            fault::PENDING_SIGNAL.store(2, Ordering::Relaxed);
            StopRequest
        }
    }

    impl Drop for StopRequest {
        fn drop(&mut self) {
            fault::PENDING_SIGNAL.store(0, Ordering::Relaxed);
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "parks on the poller")]
    fn stop_request_does_not_interrupt_a_shielded_wait() {
        let _g = lock();
        teardown();
        let _stop = StopRequest::raise();
        // SAFETY: tests hold the global lock; the sleeps run on the test's own task.
        unsafe {
            // A parked task is woken at once by a stop request ...
            assert_eq!(msrt_task_sleep(3_000_000), WAIT_CANCELLED);
            // ... except while it runs a cleanup action, which waits out its sleep.
            let r = shielded_call(|| msrt_task_sleep(3_000_000));
            assert_eq!(r, WAIT_TIMEOUT);
        }
        teardown();
    }

    unsafe extern "C-unwind" fn stop_shielded_sleeper(_: *mut u8) {
        fault::stop_shield_enter();
        // SAFETY: called from a running task.
        let r = unsafe { msrt_task_sleep(3_000_000_000) };
        fault::stop_shield_exit();
        note(if r == WAIT_CANCELLED { 2 } else { 1 });
    }

    #[test]
    #[cfg_attr(miri, ignore = "parks on the poller")]
    fn a_stop_shield_holds_back_stop_requests_but_not_a_cancel_of_the_task() {
        let _g = lock();
        teardown();
        // SAFETY: tests hold the global lock; every handle is joined once.
        unsafe {
            *LOG_N.ptr() = 0;
            // A stop request leaves the shielded task asleep: it ends by its own timeout.
            let stop = StopRequest::raise();
            let held = msrt_task_spawn(stop_shielded_sleeper, null_mut(), 0, 0);
            msrt_task_yield();
            assert!(!cancel_all_waiters_woke_any());
            drop(stop);
            cancel_flag().store(0, Ordering::Relaxed);
            // A cancel aimed at the task wakes it at once.
            msrt_task_cancel(held);
            msrt_task_join(held, null_mut());
            assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[2]);
        }
        teardown();
    }

    unsafe fn cancel_all_waiters_woke_any() -> bool {
        // SAFETY: tests hold the global lock.
        unsafe { cancel_all_waiters() }
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn cancelling_a_task_does_not_interrupt_its_shielded_wait() {
        let _g = lock();
        teardown();
        // SAFETY: tests hold the global lock; every handle is joined once.
        unsafe {
            *LOG_N.ptr() = 0;
            let t = msrt_task_spawn(shielded_sleeper, null_mut(), 0, 0);
            msrt_task_yield();
            msrt_task_cancel(t);
            assert_eq!(msrt_task_join(t, null_mut()), 0);
            assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[1]);
        }
        teardown();
    }
}
