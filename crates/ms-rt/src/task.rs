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
use crate::fault::{self, Ctx, PENDING_SIGNAL, msrt_cancel_flag};
use crate::global::Global;
use crate::sys;
use core::cmp::Reverse;
use core::ptr::null_mut;
use core::sync::atomic::Ordering;
use ms_rt_abi::StrVal;
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
/// `msrt_task_spawn` flag: a fault in the task ends the process (exit 70) as for a detached
/// task, but the task can still be joined and cancelled.
pub const SPAWN_FATAL: u32 = 2;

/// `msrt_token_new` flag: another thread will post the token, so while it is unposted the
/// scheduler waits for it instead of reporting a deadlock.
pub const TOKEN_REMOTE: u32 = 1;

const DEFAULT_STACK: usize = 256 << 20;
const MIN_STACK: usize = 128 << 10;
#[cfg(unix)]
const GUARD: usize = 64 << 10;
const STACK_POOL: usize = 32;
/// Address space reserved for a task a group starts (committed lazily).
const TASK_GROUP_STACK: usize = 16 << 20;
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
    /// Heap size that triggers dropping the entries of tasks that no longer wait on them.
    timer_limit: usize,
    /// `fd_waiters[fd]` is the handle of the task waiting on `fd`, or 0.
    fd_waiters: Vec<u64>,
    fd_waiting: usize,
    epfd: i32,
    pool: Vec<usize>,
    zombie_stack: (usize, usize),
    zombie_task: *mut Task,
    live: usize,
    tokens: Vec<Token>,
    free_tokens: Vec<usize>,
    /// Live tokens still expecting a post from another thread.
    remote_tokens: usize,
}

/// Posts from other threads, delivered by the scheduler on the runtime thread.
static INBOX: std::sync::Mutex<Vec<(u64, u64)>> = std::sync::Mutex::new(Vec::new());
/// Whether `INBOX` may hold posts; spares the scheduler the lock when nothing was posted.
static INBOX_FULL: core::sync::atomic::AtomicBool = core::sync::atomic::AtomicBool::new(false);

static SCHED: Global<Sched> = Global::new(Sched {
    cur: null_mut(),
    main: null_mut(),
    ready: VecDeque::new(),
    slots: Vec::new(),
    free_slots: Vec::new(),
    timers: BinaryHeap::new(),
    timer_limit: MIN_TIMER_LIMIT,
    fd_waiters: Vec::new(),
    fd_waiting: 0,
    epfd: -1,
    pool: Vec::new(),
    zombie_stack: (0, 0),
    zombie_task: null_mut(),
    live: 0,
    tokens: Vec::new(),
    free_tokens: Vec::new(),
    remote_tokens: 0,
});

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

/// How stacks are created and switched. Unix switches raw stacks with assembly; Windows uses
/// fibers so the thread environment block follows the stack (guard-page growth, stack bounds).
#[cfg(not(windows))]
mod stack {
    use super::*;

    pub const POOLED: bool = true;

    unsafe extern "C" {
        /// Saves callee-saved registers on the current stack, stores its pointer in `*save`,
        /// then resumes the stack `next` was saved from.
        fn msrt_ctx_switch(save: *mut usize, next: usize);
        fn msrt_task_tramp();
    }

    #[cfg(target_arch = "x86_64")]
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
        main = sym super::task_main,
    );

    #[cfg(target_arch = "aarch64")]
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
        main = sym super::task_main,
    );

    /// Builds the first frame of a new stack so that switching to it enters `msrt_task_tramp`.
    unsafe fn initial_sp(top: usize) -> usize {
        // SAFETY: `top` is the 16-byte aligned end of a writable stack with room for the frame.
        unsafe {
            #[cfg(target_arch = "x86_64")]
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

    /// Maps a stack of `len` bytes with a guard at the bottom; null on failure.
    pub unsafe fn create(len: usize) -> *mut u8 {
        let p = sys::map_anon(len);
        if !p.is_null() {
            // SAFETY: the lowest pages of the fresh mapping.
            unsafe { sys::guard(p, GUARD) };
        }
        p
    }

    pub unsafe fn destroy(base: *mut u8, len: usize) {
        // SAFETY: the caller guarantees the mapping is unused.
        unsafe { sys::unmap(base, len) };
    }

    /// Stack bounds and initial context of a stack from [`create`].
    pub unsafe fn prepare(base: *mut u8, len: usize) -> (usize, usize, usize) {
        let top = (base as usize + len) & !15;
        // SAFETY: `top` ends a writable stack.
        (base as usize + GUARD, top, unsafe { initial_sp(top) })
    }

    /// The first task record of the thread needs no stack of its own.
    pub unsafe fn adopt_thread() -> usize {
        0
    }

    pub unsafe fn switch(cur: *mut Task, next: *mut Task) {
        // SAFETY: both records are live; `next` was prepared or saved by a previous switch.
        unsafe { msrt_ctx_switch(&mut (*cur).sp, (*next).sp) };
    }
}

#[cfg(windows)]
mod stack {
    use super::*;
    use core::ffi::c_void;

    pub const POOLED: bool = false;

    unsafe extern "system" fn entry(_: *mut c_void) {
        task_main()
    }

    /// A fiber with `len` bytes of reserved stack, committed as it grows.
    pub unsafe fn create(len: usize) -> *mut u8 {
        // SAFETY: plain Win32 call.
        unsafe { sys::fiber_create(len, entry) }
    }

    pub unsafe fn destroy(base: *mut u8, _len: usize) {
        // SAFETY: the fiber is not running (the caller runs on another one).
        unsafe { sys::fiber_delete(base) };
    }

    /// Fibers carry their own bounds, which `task_main` records when it starts.
    pub unsafe fn prepare(base: *mut u8, _len: usize) -> (usize, usize, usize) {
        (0, 0, base as usize)
    }

    /// Turns the calling thread into a fiber so it can be switched away from.
    pub unsafe fn adopt_thread() -> usize {
        // SAFETY: called once on the runtime thread.
        unsafe { sys::fiber_adopt() as usize }
    }

    pub unsafe fn switch(_cur: *mut Task, next: *mut Task) {
        // SAFETY: `sp` holds the fiber handle of a live task.
        unsafe { sys::fiber_switch((*next).sp as *mut u8) };
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
            slot.gen_ = slot.gen_.wrapping_add(1).max(1);
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
    let mut s = sched();
    if len == DEFAULT_STACK
        && let Some(base) = s.pool.pop()
    {
        return base as *mut u8;
    }
    // SAFETY: the lowest pages of the fresh mapping become the guard.
    unsafe {
        let p = stack::create(len);
        if p.is_null() {
            fault::fault(b"cannot allocate a task stack");
        }
        p
    }
}

unsafe fn release_stack(base: usize, len: usize) {
    let mut s = sched();
    if stack::POOLED && len == DEFAULT_STACK && s.pool.len() < STACK_POOL {
        s.pool.push(base);
        return;
    }
    // SAFETY: the stack came from `alloc_stack` and no task runs on it.
    unsafe { stack::destroy(base as *mut u8, len) };
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
            crate::poller::unwatch((*t).wait_fd);
            s.fd_waiters[(*t).wait_fd as usize] = 0;
            s.fd_waiting -= 1;
            (*t).wait_fd = -1;
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

/// Wakes timers that have expired.
unsafe fn expire_timers(now: i64) {
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
        if !s.main.is_null() && (*s.main).state == State::Waiting && !shielded(s.main) {
            wake(s.main, WAIT_CANCELLED);
            woke = true;
        }
        for i in 0..s.slots.len() {
            let t = s.slots[i].task;
            if !t.is_null() && (*t).state == State::Waiting && !shielded(t) {
                wake(t, WAIT_CANCELLED);
                woke = true;
            }
        }
    }
    woke
}

/// Blocks until at least one task is runnable.
unsafe fn reactor_wait() {
    let mut s = sched();
    // SAFETY: syscalls with valid buffers; task records are live.
    unsafe {
        loop {
            // Tasks in a shielded cleanup keep waiting; they see the stop request afterwards.
            if PENDING_SIGNAL.load(Ordering::Relaxed) != 0 && cancel_all_waiters() {
                return;
            }
            deliver_remote_posts();
            let now = clock_ns();
            expire_timers(now);
            if !s.ready.is_empty() {
                return;
            }
            let mut timeout_ms = -1;
            while let Some(&Reverse((deadline, h))) = s.timers.peek() {
                let t = lookup(h);
                if t.is_null() || (*t).state != State::Waiting || (*t).deadline != deadline {
                    s.timers.pop();
                    continue;
                }
                let ns = (deadline - now).max(0);
                timeout_ms = ((ns + 999_999) / 1_000_000).min(i32::MAX as i64) as i32;
                break;
            }
            if timeout_ms < 0 && s.fd_waiting == 0 && s.remote_tokens == 0 {
                fault::fault(b"deadlock: every task is waiting and nothing can wake them; a wait has no matching completion, timer, I/O or cancellation");
            }
            let mut ready = [crate::poller::Ready { fd: 0, bits: 0 }; 64];
            let Some(n) = crate::poller::wait(poller_fd(), timeout_ms, &mut ready) else {
                continue;
            };
            for ev in ready.iter().take(n) {
                let fd = ev.fd;
                if fd >= s.fd_waiters.len() {
                    continue;
                }
                let t = lookup(s.fd_waiters[fd]);
                if t.is_null() {
                    continue;
                }
                wake(t, ev.bits & ((*t).wait_events | WAIT_HUP));
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
                fault::swap_ctx(&mut (*cur).ctx);
                fault::swap_ctx(&mut (*next).ctx);
                s.cur = next;
                stack::switch(cur, next);
                after_switch();
                return;
            }
            reactor_wait();
        }
    }
}

/// First code run on a new task's stack.
extern "C" fn task_main() -> ! {
    // SAFETY: the scheduler set `cur` to this task before switching to it.
    unsafe {
        #[cfg(windows)]
        {
            let (lo, hi) = sys::stack_limits();
            fault::set_stack_bounds(lo, hi);
        }
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
                fault::exit_with_report(&msg);
            }
            (*t).msg = msg;
        }
        if !(*t).owned.is_null() {
            crate::obj::msrt_release(core::mem::replace(&mut (*t).owned, null_mut()));
        }
        (*t).state = State::Done;
        s.zombie_stack = ((*t).stack as usize, (*t).stack_len);
        (*t).stack = null_mut();
        if (*t).detached {
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
/// caller parks or yields. `stack_bytes` of 0 selects the default (256 MiB of address space,
/// committed lazily). With `SPAWN_DETACHED` nobody joins the task and a fault in it ends the
/// process (exit 70); otherwise the fault is returned by `msrt_task_join`.
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
        let len = if stack_bytes == 0 {
            DEFAULT_STACK
        } else {
            stack_bytes.max(MIN_STACK).next_multiple_of(4096)
        };
        let base = alloc_stack(len);
        let (lo, hi, sp) = stack::prepare(base, len);
        let t = new_task(Ctx::new(lo, hi));
        (*t).stack = base;
        (*t).stack_len = len;
        (*t).entry = Some(entry);
        (*t).arg = arg;
        (*t).detached = flags & SPAWN_DETACHED != 0;
        (*t).fatal = flags & SPAWN_FATAL != 0;
        (*t).sp = sp;
        sched().ready.push_back((*t).handle);
        (*t).handle
    }
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

/// Hook run by a task just before it parks (on a descriptor, a timer, a token or a join); zero
/// when none is installed. Single threaded like the scheduler.
static PREPARK: core::sync::atomic::AtomicUsize = core::sync::atomic::AtomicUsize::new(0);

/// Installs (or, with `None`, removes) the hook a task runs just before it parks. A native that
/// lends its own task to another job (the HTTP reactor running handlers inline) uses it to hand
/// that job on, so a handler that sleeps or waits does not stall everything else.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_task_set_prepark(hook: Option<unsafe extern "C-unwind" fn()>) {
    PREPARK.store(hook.map_or(0, |f| f as usize), Ordering::Relaxed);
}

/// Parks the current task until `fd` is ready for `events` (`WAIT_READ`, `WAIT_WRITE`), the
/// timeout (nanoseconds, negative for none) expires, or cancellation is requested. Returns the
/// ready bits, `WAIT_TIMEOUT`, or `WAIT_CANCELLED`. A file that cannot be polled (a regular
/// file) is reported ready at once. One task may wait on a given descriptor at a time.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_wait_fd(fd: i32, events: u32, timeout_ns: i64) -> u32 {
    // SAFETY: single threaded scheduler.
    unsafe {
        let cur = ensure_init();
        if msrt_cancel_flag.load(Ordering::Relaxed) != 0 {
            return WAIT_CANCELLED;
        }
        let mut s = sched();
        if fd >= 0 {
            let fd_idx = fd as usize;
            while s.fd_waiters.len() <= fd_idx {
                s.fd_waiters.push(0);
            }
            if s.fd_waiters[fd_idx] != 0 {
                fault::fault(b"another task is already waiting on this file descriptor");
            }
            match crate::poller::watch(poller_fd(), fd, events) {
                crate::poller::Watch::Armed => {}
                crate::poller::Watch::Always => return events & (WAIT_READ | WAIT_WRITE),
                crate::poller::Watch::Failed => {
                    fault::fault(b"cannot wait on this file descriptor");
                }
            }
            s.fd_waiters[fd_idx] = (*cur).handle;
            s.fd_waiting += 1;
            (*cur).wait_fd = fd;
        }
        // After the check above, so a file that is always ready does not count as a park.
        before_park();
        (*cur).wait_events = events;
        set_deadline(cur, timeout_ns);
        (*cur).state = State::Waiting;
        switch_away();
        (*cur).wait_result
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
            sched.timers.retain(|&Reverse((deadline, h))| {
                let t = lookup_in(slots, h);
                !t.is_null() && (*t).state == State::Waiting && (*t).deadline == deadline
            });
            s.timer_limit = (s.timers.len() * 2).max(MIN_TIMER_LIMIT);
        }
    }
}

/// Runs the pre-park hook, if one is installed.
unsafe fn before_park() {
    let hook = PREPARK.load(Ordering::Relaxed);
    if hook != 0 {
        // SAFETY: only `msrt_task_set_prepark` stores here, and it stores a function pointer.
        unsafe {
            let hook: unsafe extern "C-unwind" fn() = core::mem::transmute(hook);
            hook();
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

/// Number of tasks that exist (running, runnable, waiting, or finished but not yet joined).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_count() -> usize {
    // SAFETY: single threaded scheduler.
    unsafe {
        ensure_init();
    }
    sched().live
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
    unsafe {
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
        if (*t).state != State::Done {
            if msrt_cancel_flag.load(Ordering::Relaxed) != 0 {
                return 2;
            }
            before_park();
        }
        // The hook can run other code; look again.
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

// ---- closure tasks (`@std/tasks.ms`) ----

/// Entry of a task that runs a `Callable[[], Unit]`: calls the closure with itself as its
/// environment, as every closure call does.
unsafe extern "C-unwind" fn closure_entry(arg: *mut u8) {
    let closure = arg as *mut ms_rt_abi::Closure;
    // SAFETY: `arg` is the retained closure object `msrt_tasks_spawn` stored.
    unsafe {
        let code: unsafe extern "C-unwind" fn(*mut ms_rt_abi::Closure) =
            core::mem::transmute((*closure).code);
        code(closure);
    }
}

/// Starts a task that runs `closure`, which the caller lends: the task retains it and releases it
/// when it ends, by return, cancellation, or fault. A fault in the task ends the process.
/// Returns the task handle.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_tasks_spawn(closure: *mut ms_rt_abi::Closure) -> i64 {
    // SAFETY: single threaded scheduler; `closure` is a live closure object.
    unsafe {
        crate::obj::msrt_retain(closure.cast());
        let h = msrt_task_spawn(closure_entry, closure.cast(), SPAWN_FATAL, TASK_GROUP_STACK);
        (*lookup(h)).owned = closure.cast();
        h as i64
    }
}

/// Waits for a task started by `msrt_tasks_spawn`: 0 when it returned, 1 when it was cancelled.
/// If the caller is itself cancelled while waiting, the cancellation unwinds the caller.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_tasks_join(handle: i64) -> u8 {
    // SAFETY: single threaded scheduler.
    unsafe {
        let status = msrt_task_join(handle as u64, null_mut());
        if status == 2 && msrt_cancel_flag.load(Ordering::Relaxed) != 0 {
            fault::msrt_cancelled();
        }
        u8::from(status != 0)
    }
}

/// Requests cancellation of a task started by `msrt_tasks_spawn`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_tasks_cancel(handle: i64) {
    // SAFETY: single threaded scheduler.
    unsafe { msrt_task_cancel(handle as u64) }
}

// ---- tokens ----

fn token_mut(s: &mut Sched, id: u64) -> Option<&mut Token> {
    let idx = (id & 0xffff_ffff) as usize;
    let k = s.tokens.get_mut(idx.checked_sub(1)?)?;
    (k.live && k.gen_ as u64 == id >> 32).then_some(k)
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
        s.remote_tokens -= 1;
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
    if !INBOX_FULL.swap(false, Ordering::Acquire) {
        return;
    }
    let posts = std::mem::take(&mut *INBOX.lock().unwrap_or_else(|e| e.into_inner()));
    for (id, value) in posts {
        // SAFETY: runs on the runtime thread.
        unsafe { post(id, value, true) };
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
        let idx = match s.free_tokens.pop() {
            Some(i) => i,
            None => {
                s.tokens.push(Token {
                    gen_: 0,
                    live: false,
                    remote: false,
                    waiter: 0,
                    posted: None,
                });
                s.tokens.len() - 1
            }
        };
        let k = &mut s.tokens[idx];
        k.gen_ = k.gen_.wrapping_add(1).max(1);
        k.live = true;
        k.remote = remote;
        k.waiter = 0;
        k.posted = None;
        let id = (k.gen_ as u64) << 32 | (idx as u64 + 1);
        if remote {
            s.remote_tokens += 1;
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
        if msrt_cancel_flag.load(Ordering::Relaxed) != 0 {
            return WAIT_CANCELLED;
        }
        before_park();
        // The hook can run other code; look again.
        if take(value_out) {
            return 0;
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
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_token_post_remote(id: u64, value: u64) {
    INBOX
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .push((id, value));
    INBOX_FULL.store(true, Ordering::Release);
    kick();
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
        if remote {
            s.remote_tokens -= 1;
        }
        s.free_tokens.push((id & 0xffff_ffff) as usize - 1);
    }
}

/// Drops all scheduler state (unit tests run several scenarios in one process; the leak sweep
/// calls it at exit so only real leaks remain in the live-block count).
#[cfg(any(test, feature = "stats"))]
pub fn reset_for_tests() {
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
        s.cur = null_mut();
        s.main = null_mut();
        s.ready = VecDeque::new();
        s.slots = Vec::new();
        s.free_slots = Vec::new();
        s.timers = BinaryHeap::new();
        s.timer_limit = MIN_TIMER_LIMIT;
        s.fd_waiters = Vec::new();
        s.fd_waiting = 0;
        s.epfd = -1;
        s.zombie_stack = (0, 0);
        s.zombie_task = null_mut();
        s.live = 0;
        s.tokens = Vec::new();
        s.free_tokens = Vec::new();
        s.remote_tokens = 0;
        INBOX_FULL.store(false, Ordering::Relaxed);
        INBOX.lock().unwrap_or_else(|e| e.into_inner()).clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::lock;

    static LOG: Global<[u8; 16]> = Global::new([0; 16]);
    static LOG_N: Global<usize> = Global::new(0);

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
        reset_for_tests();
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
        reset_for_tests();
    }

    unsafe extern "C-unwind" fn hook() {
        note(7);
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn the_prepark_hook_runs_before_each_park_and_only_then() {
        let _g = lock();
        reset_for_tests();
        // SAFETY: tests hold the global lock; every handle is joined once.
        unsafe {
            *LOG_N.ptr() = 0;
            msrt_task_set_prepark(Some(hook));
            let a = msrt_task_spawn(counter, core::ptr::without_provenance_mut(1), 0, 0);
            // The join parks: the hook runs first. Each yield is not a park.
            assert_eq!(msrt_task_join(a, null_mut()), 0);
            let b = msrt_task_spawn(sleeper, core::ptr::without_provenance_mut(1), 0, 0);
            msrt_task_yield();
            // `b` parked in its sleep; it has not finished, so this join parks too.
            assert_eq!(msrt_task_join(b, null_mut()), 0);
            let c = msrt_task_spawn(counter, core::ptr::without_provenance_mut(2), 0, 0);
            for _ in 0..4 {
                msrt_task_yield();
            }
            // `c` is done: joining it does not park.
            assert_eq!(msrt_task_join(c, null_mut()), 0);
            msrt_task_set_prepark(None);
            assert_eq!(
                &(&(*LOG.ptr()))[..*LOG_N.ptr()],
                &[7, 10, 11, 12, 7, 7, 1, 20, 21, 22]
            );
        }
        reset_for_tests();
    }

    static TOKEN: Global<u64> = Global::new(0);
    static GOT: Global<(u32, u64)> = Global::new((0, 0));

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
        reset_for_tests();
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
        reset_for_tests();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_timed_out_park_keeps_the_token_and_the_late_post() {
        let _g = lock();
        reset_for_tests();
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
        reset_for_tests();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn cancelling_a_task_parked_on_a_token_releases_the_token() {
        let _g = lock();
        reset_for_tests();
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
        reset_for_tests();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn posts_to_a_freed_token_do_not_reach_its_reused_slot() {
        let _g = lock();
        reset_for_tests();
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
        reset_for_tests();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_remote_post_wakes_a_parked_scheduler() {
        let _g = lock();
        reset_for_tests();
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
        reset_for_tests();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn freeing_an_unposted_remote_token_stops_counting_it() {
        let _g = lock();
        reset_for_tests();
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
        reset_for_tests();
    }

    #[cfg(unix)]
    mod fd_waits {
        use super::*;

        static RESULT: Global<u32> = Global::new(0);

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
            reset_for_tests();
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
            reset_for_tests();
        }

        #[test]
        fn wakes_on_readable_then_stays_ready() {
            let _g = lock();
            reset_for_tests();
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
            reset_for_tests();
        }

        #[test]
        fn times_out_when_nothing_arrives() {
            let _g = lock();
            reset_for_tests();
            let fds = pipe();
            // SAFETY: tests hold the global lock.
            let got = unsafe { msrt_task_wait_fd(fds[0], WAIT_READ, 10_000_000) };
            assert_eq!(got, WAIT_TIMEOUT);
            close_all(fds);
            reset_for_tests();
        }

        #[test]
        fn writable_end_is_ready() {
            let _g = lock();
            reset_for_tests();
            let fds = pipe();
            // SAFETY: tests hold the global lock.
            let got = unsafe { msrt_task_wait_fd(fds[1], WAIT_WRITE, 1_000_000_000) };
            assert_eq!(got & WAIT_WRITE, WAIT_WRITE);
            close_all(fds);
            reset_for_tests();
        }
    }

    /// Runs `f` as a shielded cleanup action would: cancellation is off until it returns.
    fn shielded_call<R>(f: impl FnOnce() -> R) -> R {
        // SAFETY: tests hold the global lock and run on the task that owns the live globals.
        unsafe {
            *fault::SHIELD.ptr() += 1;
            msrt_cancel_flag.store(0, Ordering::Relaxed);
            let r = f();
            *fault::SHIELD.ptr() -= 1;
            r
        }
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
            PENDING_SIGNAL.store(2, Ordering::Relaxed);
            StopRequest
        }
    }

    impl Drop for StopRequest {
        fn drop(&mut self) {
            PENDING_SIGNAL.store(0, Ordering::Relaxed);
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "parks on the poller")]
    fn stop_request_does_not_interrupt_a_shielded_wait() {
        let _g = lock();
        reset_for_tests();
        let _stop = StopRequest::raise();
        // SAFETY: tests hold the global lock; the sleeps run on the test's own task.
        unsafe {
            // A parked task is woken at once by a stop request ...
            assert_eq!(msrt_task_sleep(3_000_000), WAIT_CANCELLED);
            // ... except while it runs a cleanup action, which waits out its sleep.
            let r = shielded_call(|| msrt_task_sleep(3_000_000));
            assert_eq!(r, WAIT_TIMEOUT);
        }
        reset_for_tests();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn cancelling_a_task_does_not_interrupt_its_shielded_wait() {
        let _g = lock();
        reset_for_tests();
        // SAFETY: tests hold the global lock; every handle is joined once.
        unsafe {
            *LOG_N.ptr() = 0;
            let t = msrt_task_spawn(shielded_sleeper, null_mut(), 0, 0);
            msrt_task_yield();
            msrt_task_cancel(t);
            assert_eq!(msrt_task_join(t, null_mut()), 0);
            assert_eq!(&(&(*LOG.ptr()))[..*LOG_N.ptr()], &[1]);
        }
        reset_for_tests();
    }
}
