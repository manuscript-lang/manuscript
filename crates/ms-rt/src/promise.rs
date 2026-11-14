//! Promise slots for `@std/concurrency/promise.ms`.
//!
//! A promise is one entry of a flat table of the thread that made it, named by an id
//! `(thread << 56) | (generation << 32) | (index + 1)`; a stale id never matches. The columns are separate arrays (state, generation, park token, result
//! slot), so the scheduler touches only what it needs. An I/O promise has no task or stack: the
//! operation tries its system call at once and registers with the poller only when it would block.
//! Only `promise(fn)` runs a task.
//!
//! Outcome codes returned by [`msrt_promise_wait`]:
//! `0` ok (the result is in the slot), `1` the operation's own error (the error value is in the slot),
//! `2` timed out, `3` cancelled, `4` closed (the result was already taken), `5` failed (a fault inside).
//! ms: domain promise
use crate::desc::slot_drop;
use crate::sched::{self, Event, Start};
use crate::{alloc, fault, task};
use core::cell::UnsafeCell;
use core::cmp::Reverse;
use ms_rt_abi::TypeDesc;
use std::collections::{BinaryHeap, VecDeque};

pub const OK: i64 = 0;
pub const ERROR: i64 = 1;
pub const TIMEOUT: i64 = 2;
pub const CANCELLED: i64 = 3;
pub const CLOSED: i64 = 4;
pub const FAILED: i64 = 5;

#[derive(Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
enum State {
    Free,
    /// Allocated, no work attached yet or still running.
    Pending,
    /// Completed with a value.
    Ok,
    /// Completed with the operation's error value.
    Error,
    /// A fault inside ended it.
    Failed,
    Cancelled,
    /// The result was taken.
    Taken,
}

/// The result slot: heap storage of `desc.size` bytes holding an owned value.
#[derive(Clone, Copy)]
struct Result {
    ptr: *mut u8,
    desc: *const TypeDesc,
}

/// A native continuation of an I/O promise. The runtime calls it with the promise, the state word
/// given to [`io_on_ready`] and the ready bits (`WAIT_READ`, `WAIT_WRITE`, `WAIT_HUP`), or
/// `WAIT_TIMEOUT` when the limit passed, or `WAIT_CANCELLED` when the promise was dropped. It
/// retries its system call and answers true once it has completed the promise with [`io_put`]. On
/// `WAIT_TIMEOUT` it must complete the promise; on `WAIT_CANCELLED` its answer is ignored and it
/// only releases what the state word names.
pub type Retry = fn(id: i64, state: usize, bits: u32) -> bool;

const NOT_STARTED: u8 = 255;
const WANT_CANCEL: u8 = 1;
/// The work's result is stored but the promise stays pending until the work's task has ended and
/// its closure, with the resources it owns, is released: a waiter sees them closed.
const HELD: u8 = 4;
/// The held result is the operation's own error.
const HELD_ERROR: u8 = 8;
/// Another thread completes this promise (a pipe peer), so a waiter's token must be remote.
const REMOTE_WAKE: u8 = 2;
/// The promise has no task: its work runs in the first task that waits on it.
const DEFERRED: u8 = 16;
/// The promise's limit passed and ended it: a `wait` reports a timeout, not a cancellation.
const TIMED_OUT: u8 = 32;
/// `stop` asked the work to cancel; if it returns without a result anyway, the promise reads as cancelled.
const STOPPED: u8 = 64;
/// The work runs in a task on the thread that created the promise and never elsewhere, so only
/// this thread can complete it: a waiter's token is local, and a blocking call made by the work
/// sees a waiter that nothing else can wake.
const HERE: u8 = 128;

// Each flag is its own bit: two sharing one made a held result look like deferred work.
const _: () = assert!(
    (WANT_CANCEL | REMOTE_WAKE | HELD | HELD_ERROR | DEFERRED | TIMED_OUT | STOPPED | HERE)
        .count_ones()
        == 8
);

const NO_RESULT: Result = Result {
    ptr: core::ptr::null_mut(),
    desc: core::ptr::null(),
};

struct Table {
    state: Vec<State>,
    generation: Vec<u32>,
    /// The token a waiter parks on, or 0.
    token: Vec<u64>,
    result: Vec<Result>,
    /// The closure of the promise's work (`promise(fn)`) while its task may still run, else 0.
    /// The creator holds a reference to it until the task has ended.
    closure: Vec<usize>,
    /// The scheduler thread the work runs on once it has started, else `NOT_STARTED`.
    thread: Vec<u8>,
    /// The handle of the task running the work on that thread, else 0.
    task: Vec<u64>,
    /// The task that started the work, whose frame the work reads its captures from, lent
    /// (`task::lend_current`) until the work's task has ended; else 0.
    creator: Vec<u64>,
    /// `WANT_CANCEL`: cancel the work as soon as it has started.
    flags: Vec<u8>,
    /// The report of the fault that ended the promise.
    report: Vec<Vec<u8>>,
    /// When a timer promise or a readiness wait times out, or `i64::MAX`.
    deadline: Vec<i64>,
    /// When the promise's limit (`msrt_promise_limit`) ends it, or `i64::MAX`.
    limit: Vec<i64>,
    /// The cancel switch the promise listens to, or 0.
    cancel: Vec<i64>,
    /// The descriptor a readiness wait watches, or -1.
    fd: Vec<i32>,
    /// What a readiness wait asks for.
    events: Vec<u32>,
    /// The native continuation of an I/O promise (`io_on_ready`) and its state word.
    retry: Vec<Option<Retry>>,
    retry_state: Vec<usize>,
    /// (deadline, id) of the timers armed; an entry whose promise is gone or finished is stale.
    timers: BinaryHeap<Reverse<(i64, i64)>>,
    /// (limit, id) of the limits armed; an entry whose promise is gone or finished is stale.
    limits: BinaryHeap<Reverse<(i64, i64)>>,
    /// (slot, token) of waiters on other threads, posted when the slot's promise changes.
    watchers: Vec<(usize, u64)>,
    free: Vec<usize>,
}

impl Table {
    const fn empty() -> Table {
        Table {
            state: Vec::new(),
            generation: Vec::new(),
            token: Vec::new(),
            result: Vec::new(),
            closure: Vec::new(),
            thread: Vec::new(),
            task: Vec::new(),
            creator: Vec::new(),
            flags: Vec::new(),
            report: Vec::new(),
            deadline: Vec::new(),
            limit: Vec::new(),
            cancel: Vec::new(),
            fd: Vec::new(),
            events: Vec::new(),
            retry: Vec::new(),
            retry_state: Vec::new(),
            timers: BinaryHeap::new(),
            limits: BinaryHeap::new(),
            watchers: Vec::new(),
            free: Vec::new(),
        }
    }
}

crate::isolate_static! {
    static TABLE: Table = Table::empty();
}

/// Releases the calling isolate's promise table as its thread ends: the columns have no destructor
/// (the table is thread-local state), so a leak checker would see them as lost. A result nobody
/// took is dropped.
pub(crate) fn teardown() {
    let t = table();
    for i in 0..t.cancel.len() {
        if t.cancel[i] != 0 {
            let id = ((sched::current() as i64) << 56)
                | (i64::from(t.generation[i]) << 32)
                | (i as i64 + 1);
            crate::cancel::unregister(t.cancel[i], id);
        }
    }
    for r in core::mem::take(&mut t.result) {
        if !r.ptr.is_null() {
            drop_block(r.ptr as usize, r.desc as usize);
        }
    }
    *t = Table::empty();
    // Fresh buffer: the capacity grew with the ends queued.
    ends().jobs = VecDeque::new();
}

fn table() -> &'static mut Table {
    // SAFETY: the table belongs to the calling isolate.
    unsafe { &mut *TABLE.ptr() }
}

/// Generations are 24 bits, above the 32-bit index.
const GEN_MASK: u32 = 0xff_ffff;

/// The thread whose table holds promise `id`.
fn owner_of(id: i64) -> usize {
    ((id >> 56) & 0x3f) as usize
}

fn index(t: &Table, id: i64) -> Option<usize> {
    if owner_of(id) != sched::current() {
        return None;
    }
    let i = usize::try_from((id & 0xffff_ffff) - 1).ok()?;
    (*t.generation.get(i)? == ((id >> 32) as u32 & GEN_MASK) && t.state[i] != State::Free)
        .then_some(i)
}

fn find(id: i64) -> usize {
    index(table(), id).unwrap_or_else(|| fault::fault(b"promise: no such promise"))
}

/// Whether promise `id` belongs to another scheduler thread's table.
fn is_foreign(id: i64) -> bool {
    id > 0 && owner_of(id) != sched::current()
}

/// What the owner of a promise answers to a request from another thread.
enum Answer {
    /// The promise no longer exists.
    Missing,
    /// The promise has not finished; the caller's token is registered and will be posted.
    Pending,
    /// The promise finished with this outcome code.
    Outcome(i64),
    Flag(bool),
    /// Whether a wait-any input is finished and whether it has deferred work to run.
    Readiness {
        done: bool,
        deferred: bool,
    },
    /// A result block taken out of the promise (null when there was none).
    Block(usize, usize),
    Bytes(Vec<u8>),
    Unit,
}

/// Runs `job` on the thread that owns promise `id`, in a task there, and returns its answer. Every
/// operation on a promise reads or changes its slot, which only the owner's thread may touch, so a
/// handle used elsewhere (a promise captured by another promise's work, or returned by one)
/// reaches the slot by asking. The caller parks on a remote token, shielded: the job must not
/// outlive the answer's destination, and the operations asked for are short or join their work.
fn ask(id: i64, job: impl FnOnce() -> Answer + Send + 'static) -> Answer {
    let owner = owner_of(id);
    if owner >= sched::MAX_THREADS || owner == sched::NONE || owner >= sched::started() {
        return Answer::Missing;
    }
    let reply = Reply(UnsafeCell::new(None));
    let theirs = ReplyPtr(&reply);
    // The job writes into this frame while the task is parked, so the stack must keep its pages
    // (not hibernate) until the answer is in.
    // SAFETY: called on the runtime thread by the running task; unpinned below.
    unsafe { task::pin_current(true) };
    // SAFETY: the token is ours until freed; the owner posts it once the answer is stored.
    let token = unsafe { task::msrt_token_new(task::TOKEN_REMOTE) };
    sched::post(
        owner,
        Event::Call(Box::new(move || {
            let answer = job();
            let reply = theirs;
            // SAFETY: the asker stays parked until this job's post arrives, so the slot outlives
            // the write; the post publishes it.
            unsafe { *(*reply.0).0.get() = Some(answer) };
            task::msrt_token_post_remote(token, 1);
        })),
    );
    fault::msrt_shield_enter();
    // Wait for the post itself, not only the answer: a post still in the inbox when the token
    // is freed would land on whichever token reuses its slot.
    let mut value = 0;
    // SAFETY: single scheduler per isolate; the token is ours.
    while unsafe { task::msrt_token_park(token, -1, &mut value) } != 0 {}
    // SAFETY: the post arrived, so the job stored the answer and no longer touches the slot.
    let answer = unsafe { (*reply.0.get()).take() }.expect("an answer before its post");
    // SAFETY: the lend ended with the job's post.
    unsafe { task::pin_current(false) };
    fault::msrt_shield_exit();
    // SAFETY: the answer arrived, so nothing posts the token again.
    unsafe { task::msrt_token_free(token) };
    answer
}

/// Where a job run by `ask` stores its answer, on the asking task's stack.
struct Reply(UnsafeCell<Option<Answer>>);

/// The job's pointer to the asker's `Reply`.
#[derive(Clone, Copy)]
struct ReplyPtr(*const Reply);

// SAFETY: the job writes the slot once, then posts the asker's token; the asker reads it only
// after taking that post, and stays parked until then.
unsafe impl Send for ReplyPtr {}

/// The faulting answer for an id that no longer exists, as a local lookup would give.
fn missing() -> ! {
    fault::fault(b"promise: no such promise")
}

/// Owner side of a foreign wait: the outcome if there is one, else registers `token` to be posted
/// when the promise changes. Registration never runs work: a wait on several promises must
/// check all of them for an existing result before running any deferred callback.
fn watch(id: i64, token: u64) -> Answer {
    let t = table();
    let Some(i) = index(t, id) else {
        return Answer::Missing;
    };
    match outcome(t, i) {
        Some(code) => Answer::Outcome(code),
        None => {
            t.watchers.push((i, token));
            Answer::Pending
        }
    }
}

/// Owner side: forgets `token` as a watcher of `id`.
fn unwatch(id: i64, token: u64) -> Answer {
    let t = table();
    if let Some(i) = index(t, id) {
        t.watchers.retain(|&w| w != (i, token));
    }
    Answer::Unit
}

fn wait_foreign(id: i64, timeout_ns: i64) -> i64 {
    let own = (timeout_ns >= 0).then(|| crate::sys::monotonic_ns().saturating_add(timeout_ns));
    let inherited = task::defer_deadline();
    let deadline = match (own, inherited) {
        (o, i64::MAX) => o,
        (Some(o), i) => Some(o.min(i)),
        (None, i) => Some(i),
    };
    loop {
        // SAFETY: the token is ours until freed.
        let token = unsafe { task::msrt_token_new(task::TOKEN_REMOTE) };
        let answer = ask(id, move || {
            if deadline.is_none() {
                run_unstarted(id);
            }
            run_deferred(id, deadline);
            watch(id, token)
        });
        let code = match answer {
            Answer::Outcome(code) => Some(code),
            Answer::Pending => None,
            _ => {
                // SAFETY: no waiter, no registration.
                unsafe { task::msrt_token_free(token) };
                missing()
            }
        };
        if let Some(code) = code {
            // SAFETY: the owner holds no registration of it.
            unsafe { task::msrt_token_free(token) };
            return code;
        }
        let remaining = deadline.map_or(-1, |d| (d - crate::sys::monotonic_ns()).max(0));
        let mut value = 0;
        // SAFETY: single scheduler per isolate; the token is ours.
        let woke = unsafe { task::msrt_token_park(token, remaining, &mut value) };
        if woke == task::WAIT_CANCELLED || woke == task::WAIT_TIMEOUT {
            ask(id, move || unwatch(id, token));
        }
        // SAFETY: the owner holds no registration of it any more.
        unsafe { task::msrt_token_free(token) };
        if woke == task::WAIT_CANCELLED {
            msrt_promise_drop(id);
            fault::msrt_cancelled();
        }
        if woke == task::WAIT_TIMEOUT {
            ask(id, move || {
                request_cancel(id);
                Answer::Unit
            });
            return TIMEOUT;
        }
    }
}

fn release_result(t: &mut Table, i: usize) {
    let r = core::mem::replace(&mut t.result[i], NO_RESULT);
    if !r.ptr.is_null() {
        // SAFETY: `ptr` holds an owned value of `desc` that was not taken.
        unsafe {
            slot_drop(&*r.desc, r.ptr);
            alloc::free(r.ptr);
        }
    }
}

/// Allocates a pending promise and returns its id.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_new() -> i64 {
    let t = table();
    let i = match t.free.pop() {
        Some(i) => i,
        None => {
            t.state.push(State::Free);
            t.generation.push(0);
            t.token.push(0);
            t.result.push(NO_RESULT);
            t.closure.push(0);
            t.thread.push(NOT_STARTED);
            t.task.push(0);
            t.creator.push(0);
            t.flags.push(0);
            t.report.push(Vec::new());
            t.deadline.push(i64::MAX);
            t.limit.push(i64::MAX);
            t.cancel.push(0);
            t.fd.push(-1);
            t.events.push(0);
            t.retry.push(None);
            t.retry_state.push(0);
            t.state.len() - 1
        }
    };
    t.generation[i] = t.generation[i].wrapping_add(1) & GEN_MASK;
    if t.generation[i] == 0 {
        t.generation[i] = 1;
    }
    t.state[i] = State::Pending;
    t.token[i] = 0;
    t.result[i] = NO_RESULT;
    t.closure[i] = 0;
    t.thread[i] = NOT_STARTED;
    t.task[i] = 0;
    t.creator[i] = 0;
    t.flags[i] = 0;
    t.report[i] = Vec::new();
    t.deadline[i] = i64::MAX;
    t.limit[i] = i64::MAX;
    t.cancel[i] = 0;
    t.fd[i] = -1;
    t.events[i] = 0;
    t.retry[i] = None;
    ((sched::current() as i64) << 56) | (i64::from(t.generation[i]) << 32) | (i as i64 + 1)
}

/// Completes `id` with the value in `value`, which moves into the promise: `failed` 0 for the
/// result, 1 for the operation's error value. A promise completes once; later calls drop the value.
/// The value crosses to the promise's thread as a block of the process heap, never copied deeper.
///
/// # Safety
/// `value` holds an owned value of `d`, which the callee takes.
// ms: takes:value
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_put(
    id: i64,
    value: *mut u8,
    d: ms_rt_abi::ValueDesc,
    failed: i64,
) {
    // SAFETY: forwarded contract.
    unsafe {
        let size = (*d).size as usize;
        let ptr = alloc::alloc(size.max(1));
        core::ptr::copy_nonoverlapping(value, ptr, size);
        deliver(
            id,
            Event::Done {
                id,
                failed: failed != 0,
                ptr: ptr as usize,
                desc: d as usize,
                pipe: 0,
            },
        );
    }
}

/// Hands `event` to the thread the promise `id` belongs to, or applies it here when that is this one.
fn deliver(id: i64, event: Event) {
    let owner = owner_of(id);
    if owner == sched::current() {
        apply(event);
    } else {
        sched::post(owner, event);
    }
}

/// Applies the events other threads sent to this one.
pub(crate) fn apply_events() {
    for event in sched::take_events() {
        match event {
            Event::Ended { id, status, report } => end_remote(id, status, report),
            event => apply(event),
        }
    }
}

/// What a task needs to finish the end of promise `id` once its closure is dropped.
struct EndJob {
    id: i64,
    status: u8,
    report: Vec<u8>,
}

/// Applies an end that came from another thread. Dropping the closure can join work (a captured
/// promise is cancelled and awaited), which needs a task to park, so it runs in one instead of in
/// the scheduler's event handling.
fn end_remote(id: i64, status: u8, report: Vec<u8>) {
    let t = table();
    let Some(i) = index(t, id) else { return };
    if t.closure[i] == 0 {
        apply(Event::Ended { id, status, report });
        return;
    }
    let ends = ends();
    ends.jobs.push_back(EndJob { id, status, report });
    if ends.enders < ENDERS {
        spawn_ender();
    }
}

/// Ends waiting for a task to run them, and how many tasks are draining them. One task per end
/// cost a stack for each: 100k short promises that ran on other threads made 100k stacks at once.
struct Ends {
    jobs: VecDeque<EndJob>,
    enders: usize,
}

crate::isolate_static! {
    static ENDS: Ends = Ends { jobs: VecDeque::new(), enders: 0 };
}

fn ends() -> &'static mut Ends {
    // SAFETY: the queue belongs to the calling isolate.
    unsafe { &mut *ENDS.ptr() }
}

/// Tasks that drain the queue of ends. A drop that waits parks only its own task.
const ENDERS: usize = 4;

fn spawn_ender() {
    ends().enders += 1;
    // SAFETY: the task is detached and ends by itself.
    unsafe { task::msrt_task_spawn(ender_entry, core::ptr::null_mut(), task::SPAWN_DETACHED, 0) };
}

/// Called when the thread has nothing to run and ends are queued: every ender is parked in a
/// drop, and a queued end might be what that drop waits for, so one more task takes the queue.
/// True when it started one.
pub(crate) fn rescue_ends() -> bool {
    if ends().jobs.is_empty() {
        return false;
    }
    spawn_ender();
    true
}

unsafe extern "C-unwind" fn ender_entry(_: *mut u8) {
    while let Some(job) = ends().jobs.pop_front() {
        finish_end(job);
    }
    ends().enders -= 1;
}

fn finish_end(job: EndJob) {
    let EndJob { id, status, report } = job;
    let t = table();
    if let Some(i) = index(t, id) {
        let closure = t.closure[i];
        if closure != 0 {
            // SAFETY: the closure handed over at start; the task is over, so this is its last use.
            // The slot keeps the closure until it is gone, so a result that arrives meanwhile waits.
            unsafe { crate::obj::drop_obj(closure as *mut ms_rt_abi::Obj) };
            if let Some(i) = index(table(), id) {
                table().closure[i] = 0;
            }
        }
    }
    apply(Event::Ended { id, status, report });
}

fn drop_block(ptr: usize, desc: usize) {
    // SAFETY: the block holds an owned value of `desc` that nobody took.
    unsafe {
        slot_drop(&*(desc as *const TypeDesc), ptr as *mut u8);
        alloc::free(ptr as *mut u8);
    }
}

fn apply(event: Event) {
    match event {
        Event::Started { id, thread, task } => {
            let t = table();
            let Some(i) = index(t, id) else { return };
            t.thread[i] = thread;
            t.task[i] = task;
            if t.flags[i] & WANT_CANCEL != 0 {
                request_cancel(id);
            }
            wake(table(), i);
        }
        Event::Done {
            id,
            failed,
            ptr,
            desc,
            pipe,
        } => {
            let t = table();
            match index(t, id) {
                // A held result is already accepted: a later completion is a duplicate.
                Some(i) if t.state[i] == State::Pending && t.flags[i] & HELD == 0 => {
                    if ptr != 0 {
                        t.result[i] = Result {
                            ptr: ptr as *mut u8,
                            desc: desc as *const TypeDesc,
                        };
                    }
                    t.retry[i] = None;
                    if t.closure[i] != 0 {
                        // The work's task is still ending; its owned resources close first.
                        t.flags[i] |= HELD | if failed { HELD_ERROR } else { 0 };
                        return;
                    }
                    t.state[i] = if failed { State::Error } else { State::Ok };
                    wake(t, i);
                }
                _ if ptr == 0 => {}
                _ if pipe != 0 => crate::pipe::unread(pipe, ptr, desc),
                _ => drop_block(ptr, desc),
            }
        }
        Event::Ended { id, status, report } => {
            let t = table();
            let Some(i) = index(t, id) else { return };
            let closure = core::mem::take(&mut t.closure[i]);
            if closure != 0 {
                // SAFETY: the closure handed over at start; the task is over, so this is its last use.
                unsafe { crate::obj::drop_obj(closure as *mut ms_rt_abi::Obj) };
            }
            let creator = core::mem::take(&mut t.creator[i]);
            if creator != 0 {
                // SAFETY: lent at start on this thread; a creator that has ended is skipped.
                unsafe { task::return_lent(creator) };
            }
            t.thread[i] = NOT_STARTED;
            if t.state[i] == State::Pending && t.flags[i] & HELD != 0 {
                t.state[i] = if t.flags[i] & HELD_ERROR != 0 {
                    State::Error
                } else {
                    State::Ok
                };
                t.flags[i] &= !(HELD | HELD_ERROR);
            } else if t.state[i] == State::Pending {
                match status {
                    1 => {
                        t.report[i] = report;
                        t.state[i] = State::Failed;
                    }
                    2 => t.state[i] = State::Cancelled,
                    _ if t.flags[i] & (TIMED_OUT | STOPPED) != 0 => t.state[i] = State::Cancelled,
                    _ => {
                        t.report[i] = b"promise: the work ended without a result".to_vec();
                        t.state[i] = State::Failed;
                    }
                }
            }
            wake(t, i);
        }
        Event::Cancel { task } => {
            // SAFETY: a stale or finished handle is a no-op.
            unsafe { task::msrt_task_cancel(task) };
        }
        Event::Stop { id } => stop(id),
        Event::Call(job) => {
            let job = Box::into_raw(Box::new(job));
            // SAFETY: the entry takes the job; the task is detached and ends by itself.
            unsafe { task::msrt_task_spawn(call_entry, job.cast(), task::SPAWN_DETACHED, 0) };
        }
    }
}

unsafe extern "C-unwind" fn call_entry(arg: *mut u8) {
    // SAFETY: `arg` is the job `apply` leaked for this task.
    let job = *unsafe { Box::from_raw(arg.cast::<Box<dyn FnOnce() + Send>>()) };
    job();
}

/// Asks for the work of promise `id` to stop at its next wait. Work that has not started is
/// removed from its queue and ends here; work that has started is told to cancel on its thread;
/// work that is between the two is cancelled as soon as it starts.
fn request_cancel(id: i64) {
    let t = table();
    let Some(i) = index(t, id) else { return };
    if t.closure[i] == 0 {
        return;
    }
    if t.thread[i] != NOT_STARTED {
        let thread = t.thread[i] as usize;
        let task = t.task[i];
        if thread == sched::current() {
            apply(Event::Cancel { task });
        } else {
            sched::post(thread, Event::Cancel { task });
        }
        return;
    }
    if let Some(closure) = sched::remove_pending(id) {
        // Never started: nothing runs, so it ends here.
        debug_assert_eq!(closure, t.closure[i]);
        apply(Event::Ended {
            id,
            status: 2,
            report: Vec::new(),
        });
        return;
    }
    t.flags[i] |= WANT_CANCEL;
}

/// Starts the promise `start` as a task on this thread and tells its creator.
pub(crate) fn execute(start: Start) {
    sched::live_add(1);
    // SAFETY: the creator holds a reference to the closure until it is told the task ended.
    let task = unsafe {
        task::spawn_promise_task(
            start.closure as *mut ms_rt_abi::Closure,
            start.id,
            start.capture,
            start.stolen_at,
        )
    };
    deliver(
        start.id,
        Event::Started {
            id: start.id,
            thread: sched::current() as u8,
            task,
        },
    );
}

/// The task of promise `id` ended with `status` (0 returned, 1 fault, 2 cancelled).
pub(crate) fn task_ended(id: i64, status: u8, msg: &ms_rt_abi::StrVal, started: &[usize]) {
    let report = if status == 1 {
        fault::fault_report(msg, started)
    } else {
        Vec::new()
    };
    let capture = task::capture();
    if status == 1
        && capture != 0
        && let Some(record) = fault::take_record(msg)
    {
        crate::io::capture_fault(capture, record.encode());
    }
    sched::live_add(-1);
    // Ending drops the closure, which closes what it captured: like any implicit close that runs
    // shielded, since a cancelled task would otherwise be cancelled again at its first park.
    fault::msrt_shield_enter();
    deliver(id, Event::Ended { id, status, report });
    fault::msrt_shield_exit();
}

/// Wakes the task waiting on slot `i`, if any.
fn wake(t: &mut Table, i: usize) {
    let token = core::mem::take(&mut t.token[i]);
    if token != 0 {
        // SAFETY: the waiter owns the token until it is woken or leaves.
        unsafe { task::msrt_token_post(token, 1) };
    }
    if !t.watchers.is_empty() {
        t.watchers.retain(|&(slot, token)| {
            if slot == i {
                task::msrt_token_post_remote(token, 1);
            }
            slot != i
        });
    }
}

/// Moves the result of a promise whose `wait` returned 0 or 1 into `out` and answers 1; the promise
/// reads as closed afterwards. Answers 0 when there is no result to take.
///
/// # Safety
/// `out` is writable memory for a value of `d`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_take(
    id: i64,
    d: ms_rt_abi::ValueDesc,
    out: *mut u8,
) -> u8 {
    let r = if is_foreign(id) {
        match ask(id, move || {
            let r = take_block(id);
            Answer::Block(r.ptr as usize, r.desc as usize)
        }) {
            Answer::Block(ptr, desc) => Result {
                ptr: ptr as *mut u8,
                desc: desc as *const TypeDesc,
            },
            _ => NO_RESULT,
        }
    } else {
        take_block(id)
    };
    if r.ptr.is_null() {
        return 0;
    }
    // SAFETY: forwarded contract; the stored value is owned and moves out.
    unsafe {
        core::ptr::copy_nonoverlapping(r.ptr, out, (*d).size as usize);
        alloc::free(r.ptr);
    }
    1
}

/// Takes the result block out of promise `id` and marks it taken; null when there is none.
fn take_block(id: i64) -> Result {
    let t = table();
    let Some(i) = index(t, id) else {
        return NO_RESULT;
    };
    let r = core::mem::replace(&mut t.result[i], NO_RESULT);
    if !r.ptr.is_null() {
        t.state[i] = State::Taken;
    }
    r
}

/// Whether `id` has finished (any outcome). A closed id reads as done.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_done(id: i64) -> u8 {
    if is_foreign(id) {
        return match ask(id, move || {
            let t = table();
            Answer::Flag(index(t, id).is_none_or(|i| t.state[i] != State::Pending))
        }) {
            Answer::Flag(done) => u8::from(done),
            _ => 1,
        };
    }
    let t = table();
    match index(t, id) {
        Some(i) if t.state[i] == State::Pending => {
            if t.closure[i] != 0 {
                // A task that has not started gets its turn, so polling `done` makes progress.
                // SAFETY: single scheduler per isolate.
                unsafe { task::pump() };
            }
            let t = table();
            index(t, id).map_or(1, |i| u8::from(t.state[i] != State::Pending))
        }
        Some(_) | None => 1,
    }
}

/// Runs promise `id` on the calling task's own stack if it is one of this thread's and no thread has
/// taken it; answers whether it ran. For a waiter that is about to wait on it anyway: a task start
/// costs far more than the call this makes.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_run_unstarted(id: i64) -> u8 {
    let t = table();
    let Some(i) = index(t, id) else { return 0 };
    if t.state[i] != State::Pending || t.closure[i] == 0 {
        return 0;
    }
    run_unstarted(id);
    let t = table();
    index(t, id).map_or(1, |i| u8::from(t.state[i] != State::Pending))
}

/// Completes `i` with no value (a finished sleep): `wait` answers 0 and nothing is left to take.
fn complete_unit(t: &mut Table, i: usize) {
    if t.state[i] == State::Pending {
        // A unit value, so `wait` takes `Unit` (an empty result reads as closed).
        put_int(t, i, 0);
    }
}

/// A promise that finishes after `ns` nanoseconds; it has no task; it finishes with a unit value.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_sleep(ns: i64) -> i64 {
    let id = msrt_promise_new();
    let t = table();
    let i = find(id);
    let deadline = crate::sys::monotonic_ns().saturating_add(ns.max(0));
    t.deadline[i] = deadline;
    t.timers.push(Reverse((deadline, id)));
    id
}

/// A promise for the readiness of `fd` for `events` (`WAIT_READ`, `WAIT_WRITE`, ...), with a
/// `timeout_ns` limit (negative: none). It finishes with an `Int` of the bits that were ready,
/// `WAIT_TIMEOUT` when the limit passed. A descriptor that cannot be polled is ready at once.
/// Returns -1 when `fd` cannot be waited on. It has no task: the poller completes the slot.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_ready(fd: i64, events: i64, timeout_ns: i64) -> i64 {
    let (fd, events) = (fd as i32, events as u32);
    let id = msrt_promise_new();
    // SAFETY: single scheduler per isolate.
    let ready = unsafe { task::watch_fd_for_promise(fd, events, id) };
    let t = table();
    let i = find(id);
    match ready {
        None => {
            msrt_promise_drop(id);
            return -1;
        }
        Some(true) => {
            put_int(
                t,
                i,
                i64::from(events & (task::WAIT_READ | task::WAIT_WRITE)),
            );
        }
        Some(false) => {
            t.fd[i] = fd;
            t.events[i] = events;
            if timeout_ns >= 0 {
                let deadline = crate::sys::monotonic_ns().saturating_add(timeout_ns);
                t.deadline[i] = deadline;
                t.timers.push(Reverse((deadline, id)));
            }
        }
    }
    id
}

fn put_int(t: &mut Table, i: usize, value: i64) {
    let ptr = alloc::alloc(8);
    // SAFETY: `ptr` is a fresh 8-byte block.
    unsafe { ptr.cast::<i64>().write(value) };
    t.result[i] = Result {
        ptr,
        desc: &crate::desc::msrt_desc_int,
    };
    t.state[i] = State::Ok;
    wake(t, i);
}

/// Completes `id` with a unit result: a block `wait` can take as `Unit` (an empty result reads as
/// closed, so a flush or write promise ends this way).
pub fn io_done_unit(id: i64) {
    let ptr = alloc::alloc(8);
    // SAFETY: `ptr` is a fresh 8-byte block.
    unsafe { ptr.cast::<i64>().write(0) };
    io_done_block(
        id,
        ptr as usize,
        &crate::desc::msrt_desc_int as *const _ as usize,
        0,
    );
}

/// A promise that is already finished with no value: the answer of a flush with nothing to drain.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_finished() -> i64 {
    let id = msrt_promise_new();
    io_done_unit(id);
    id
}

/// A new pending promise for a native operation to complete.
pub fn io_new() -> i64 {
    msrt_promise_new()
}

/// Completes the promise `id` with the owned value in `value`, which the callee takes.
///
/// # Safety
/// `value` holds an owned value of `d`.
pub unsafe fn io_put(id: i64, value: *mut u8, d: &'static TypeDesc, failed: bool) {
    // SAFETY: forwarded contract.
    unsafe { msrt_promise_put(id, value, d, i64::from(failed)) }
}

/// Completes the promise `id` with no value (a finished write): `wait` answers 0 and there is
/// nothing to take.
pub fn io_done(id: i64) {
    deliver(
        id,
        Event::Done {
            id,
            failed: false,
            ptr: 0,
            desc: 0,
            pipe: 0,
        },
    );
}

/// Completes the promise `id` with the block `ptr` of `desc` (null: no value), from any thread.
/// If the promise is gone, the value returns to `pipe` (0: it is dropped).
pub(crate) fn io_done_block(id: i64, ptr: usize, desc: usize, pipe: i64) {
    deliver(
        id,
        Event::Done {
            id,
            failed: false,
            ptr,
            desc,
            pipe,
        },
    );
}

/// Records `cancel` as the continuation that runs when pending promise `id` is dropped, with
/// `state`. A pipe read uses it to leave the pipe's list of waiting readers.
pub(crate) fn on_drop(id: i64, cancel: Retry, state: usize) {
    let t = table();
    if let Some(i) = index(t, id) {
        t.retry[i] = Some(cancel);
        t.retry_state[i] = state;
        t.flags[i] |= REMOTE_WAKE;
    }
}

/// Registers the continuation `retry` for the promise `id`: when `fd` is ready for `events` (or
/// `timeout_ns` passes; negative means no limit) the poller calls it with `state`. A descriptor
/// that cannot be polled (a regular file) calls it at once. Nothing is allocated: the
/// continuation and its state word live in the slot table. Answers false when `fd` cannot be
/// waited on.
pub fn io_on_ready(
    id: i64,
    fd: i32,
    events: u32,
    timeout_ns: i64,
    retry: Retry,
    state: usize,
) -> bool {
    // SAFETY: single scheduler per isolate.
    let ready = unsafe { task::watch_fd_for_promise(fd, events, id) };
    let t = table();
    let Some(i) = index(t, id) else { return false };
    match ready {
        None => false,
        Some(true) => {
            retry(id, state, events & (task::WAIT_READ | task::WAIT_WRITE));
            true
        }
        Some(false) => {
            t.fd[i] = fd;
            t.events[i] = events;
            t.retry[i] = Some(retry);
            t.retry_state[i] = state;
            if timeout_ns >= 0 {
                let deadline = crate::sys::monotonic_ns().saturating_add(timeout_ns);
                t.deadline[i] = deadline;
                t.timers.push(Reverse((deadline, id)));
            }
            true
        }
    }
}

/// What readiness wait `id` asks for (0 when it is not one).
pub(crate) fn fd_events(id: i64) -> u32 {
    let t = table();
    index(t, id).map_or(0, |i| t.events[i])
}

/// The poller saw `bits` on the descriptor of readiness wait `id`; answers whether it finished.
pub(crate) fn fd_ready(id: i64, bits: u32) -> bool {
    let t = table();
    let Some(i) = index(t, id) else { return true };
    let wanted = bits & (t.events[i] | task::WAIT_HUP);
    if wanted == 0 || t.state[i] != State::Pending {
        return t.state[i] != State::Pending;
    }
    if let Some(retry) = t.retry[i] {
        // A native operation tries again; it may find the descriptor not ready after all.
        let state = t.retry_state[i];
        if !retry(id, state, wanted) {
            return false;
        }
        let t = table();
        if let Some(i) = index(t, id) {
            t.fd[i] = -1;
            t.retry[i] = None;
        }
        return true;
    }
    t.fd[i] = -1;
    put_int(t, i, i64::from(wanted));
    true
}

/// Finishes the timers due at `now`: a sleep ends, a readiness wait times out.
pub(crate) fn expire(now: i64) {
    expire_limits(now);
    loop {
        let t = table();
        let Some(&Reverse((deadline, id))) = t.timers.peek() else {
            return;
        };
        if deadline > now {
            return;
        }
        t.timers.pop();
        let Some(i) = index(t, id) else { continue };
        if t.state[i] != State::Pending || t.deadline[i] != deadline {
            continue;
        }
        if t.fd[i] >= 0 {
            let fd = core::mem::replace(&mut t.fd[i], -1);
            // SAFETY: single scheduler per isolate.
            unsafe { task::unwatch_fd_for_promise(fd, id) };
            if let Some(retry) = core::mem::take(&mut t.retry[i]) {
                retry(id, t.retry_state[i], task::WAIT_TIMEOUT);
                let t = table();
                if let Some(i) = index(t, id)
                    && t.state[i] == State::Pending
                {
                    put_int(t, i, i64::from(task::WAIT_TIMEOUT));
                }
            } else {
                put_int(t, i, i64::from(task::WAIT_TIMEOUT));
            }
        } else {
            complete_unit(t, i);
        }
    }
}

/// Ends the promises whose limit has passed at `now`.
fn expire_limits(now: i64) {
    loop {
        let t = table();
        let Some(&Reverse((limit, id))) = t.limits.peek() else {
            return;
        };
        if limit > now {
            return;
        }
        t.limits.pop();
        let Some(i) = index(t, id) else { continue };
        if t.state[i] == State::Pending && t.limit[i] == limit {
            t.flags[i] |= TIMED_OUT;
            t.limit[i] = i64::MAX;
            stop(id);
        }
    }
}

/// Ends the unfinished promise `id` as cancelled, whatever it is doing: work that has a task is
/// told to cancel (the task's end completes it), and a promise with no task is completed here.
fn stop(id: i64) {
    let t = table();
    let Some(i) = index(t, id) else { return };
    if t.state[i] != State::Pending {
        return;
    }
    if t.closure[i] != 0 {
        t.flags[i] |= STOPPED;
        request_cancel(id);
        return;
    }
    if t.flags[i] & DEFERRED != 0 {
        t.flags[i] &= !DEFERRED;
        let closure = core::mem::take(&mut t.retry_state[i]);
        // SAFETY: the closure handed over to `msrt_promise_defer`, never run.
        unsafe { crate::obj::drop_obj(closure as *mut ms_rt_abi::Obj) };
    }
    if t.fd[i] >= 0 {
        let fd = core::mem::replace(&mut t.fd[i], -1);
        // SAFETY: single scheduler per isolate.
        unsafe { task::unwatch_fd_for_promise(fd, id) };
    }
    if let Some(retry) = core::mem::take(&mut t.retry[i]) {
        retry(id, t.retry_state[i], task::WAIT_CANCELLED);
    }
    let t = table();
    if let Some(i) = index(t, id)
        && t.state[i] == State::Pending
    {
        t.state[i] = State::Cancelled;
        wake(t, i);
    }
}

/// Cancels promise `id` if it has not finished: its work stops at its next wait and a `wait` reports
/// a cancellation. It never waits itself; dropping the promise joins the work.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_cancel(id: i64) {
    if is_foreign(id) {
        deliver(id, Event::Stop { id });
        return;
    }
    stop(id);
}

/// Makes promise `id` listen to the cancel switch `cancel` (`cancel.rs`): when it fires the promise is
/// cancelled, as by `msrt_promise_cancel`. This replaces any earlier switch. A switch that already fired
/// cancels it now. Call it after the work has started.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_on_cancel(id: i64, cancel: i64) {
    if is_foreign(id) {
        ask(id, move || {
            msrt_promise_on_cancel(id, cancel);
            Answer::Unit
        });
        return;
    }
    let t = table();
    let Some(i) = index(t, id) else { return };
    let previous = core::mem::replace(&mut t.cancel[i], cancel);
    if previous != 0 {
        crate::cancel::unregister(previous, id);
    }
    if crate::cancel::register(cancel, id) {
        stop(id);
    }
}

/// Stops promise `id` from the thread that fired its switch: on the promise's own thread.
pub(crate) fn stop_on_owner(id: i64) {
    deliver(id, Event::Stop { id });
}

/// Limits promise `id`: once `timeout_ns` has passed from now (negative: no time at all) and it
/// has not finished, it is cancelled and a `wait` reports a timeout. A promise with no limit costs
/// nothing; a second call replaces the first.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_limit(id: i64, timeout_ns: i64) {
    if is_foreign(id) {
        ask(id, move || {
            msrt_promise_limit(id, timeout_ns);
            Answer::Unit
        });
        return;
    }
    let t = table();
    let Some(i) = index(t, id) else { return };
    let limit = crate::sys::monotonic_ns().saturating_add(timeout_ns.max(0));
    t.limit[i] = limit;
    t.limits.push(Reverse((limit, id)));
}

/// The earliest deadline of a live timer or limit, dropping stale entries on the way.
pub(crate) fn next_deadline() -> Option<i64> {
    let t = table();
    while let Some(&Reverse((limit, id))) = t.limits.peek() {
        if let Some(i) = index(t, id)
            && t.state[i] == State::Pending
            && t.limit[i] == limit
        {
            break;
        }
        t.limits.pop();
    }
    let limit = t.limits.peek().map(|&Reverse((l, _))| l);
    while let Some(&Reverse((deadline, id))) = t.timers.peek() {
        if let Some(i) = index(t, id)
            && t.state[i] == State::Pending
            && t.deadline[i] == deadline
        {
            return Some(limit.map_or(deadline, |l| l.min(deadline)));
        }
        t.timers.pop();
    }
    limit
}

/// Whether any timer entry exists (live or stale).
pub(crate) fn has_timers() -> bool {
    !table().timers.is_empty() || !table().limits.is_empty()
}

/// Starts `work` as the task of promise `id`, on the thread the runtime picks. The closure
/// completes the promise itself with `msrt_promise_put`. A fault in it ends only this promise.
///
/// # Safety
/// `work` is a live closure object.
// ms: keeps:work spawns
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_start(id: i64, work: *mut ms_rt_abi::Closure) {
    // SAFETY: forwarded contract.
    unsafe { start_on(id, work, Mode::Anywhere) }
}

/// Starts `work` as the task of promise `id` on the least loaded thread, starting one when the limit allows. For
/// long-lived work that should spread over the cores (one serving worker per core) rather than
/// queue behind its creator. Otherwise as `msrt_promise_start`.
///
/// # Safety
/// `work` is a live closure object.
// ms: keeps:work spawns
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_start_spread(id: i64, work: *mut ms_rt_abi::Closure) {
    // SAFETY: forwarded contract.
    unsafe { start_on(id, work, Mode::Spread) }
}

/// Starts `work` as the task of promise `id`, on the calling thread and never elsewhere. For an I/O operation run as a
/// task (a fetch, a connect, a file read): it only waits, so it gains nothing from another thread, and its native
/// handles stay on the thread that made them. Otherwise as `msrt_promise_start`.
///
/// # Safety
/// `work` is a live closure object.
// ms: keeps:work spawns
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_start_here(id: i64, work: *mut ms_rt_abi::Closure) {
    // SAFETY: forwarded contract.
    unsafe { start_on(id, work, Mode::Here) }
}

/// Starts `work` as the task of promise `id` where `mode` says, on this thread when a live native
/// stream is pinned to it.
///
/// # Safety
/// `work` is a live closure object.
/// Where a promise's task starts.
#[derive(Clone, Copy, PartialEq)]
enum Mode {
    /// Queued here; an idle thread takes it once it has aged, else the creator runs it.
    Anywhere,
    /// On the calling thread.
    Here,
    /// On the least loaded thread.
    Spread,
}

unsafe fn start_on(id: i64, work: *mut ms_rt_abi::Closure, mode: Mode) {
    let i = find(id);
    let t = table();
    if t.closure[i] != 0 || t.thread[i] != NOT_STARTED {
        fault::fault(b"promise: already started");
    }
    // The caller hands the closure over: the promise owns it until the task has ended. The work
    // reads what it captured from the caller's frame, so the caller's stack stays lent out (no
    // hibernation) until then.
    t.closure[i] = work as usize;
    // SAFETY: called on the runtime thread by the running task.
    t.creator[i] = unsafe { task::lend_current() };
    if mode == Mode::Here {
        t.flags[i] |= HERE;
    }
    let start = Start {
        id,
        closure: work as usize,
        at: crate::sys::monotonic_ns(),
        capture: task::capture(),
        stolen_at: 0,
    };
    // A spread promise is placed on purpose, so a stream pinned to this thread does not hold it here.
    if mode == Mode::Here
        || sched::current() == sched::NONE
        || (mode == Mode::Anywhere && sched::pinned_here())
    {
        execute(start);
    } else if mode == Mode::Spread {
        if let Some(start) = sched::submit_spread(start) {
            execute(start);
        }
    } else {
        sched::submit(start);
    }
}

/// Makes the new promise `id` one whose work `work` runs in the task that first waits on it (or polls it), on that
/// task's stack and with no task of its own. The work may itself wait. Dropping the promise first
/// discards the work without running it. A stream `read` is one: its source's `next` runs where
/// the reader waits.
///
/// # Safety
/// `work` is a live closure object.
// ms: keeps:work
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_defer(id: i64, work: *mut ms_rt_abi::Closure) {
    let i = find(id);
    let t = table();
    // The caller hands the closure over: the promise owns it until the work runs or it is dropped.
    t.flags[i] |= DEFERRED;
    t.retry_state[i] = work as usize;
}

/// Runs promise `id` on the waiter's own stack if no thread has taken it yet: the closure leaves
/// its queue and runs here under a guard, so a fault still ends only that promise. Costs about a
/// call, against a task start. Only an unbounded wait does this; a wait with a deadline cannot
/// stop the work, so it leaves the promise to run as a task.
fn run_unstarted(id: i64) {
    let t = table();
    let Some(i) = index(t, id) else { return };
    if t.closure[i] == 0 || t.thread[i] != NOT_STARTED || t.flags[i] & WANT_CANCEL != 0 {
        return;
    }
    let Some(closure) = sched::remove_pending(id) else {
        return;
    };
    let mut msg = crate::string::NO_STR;
    // SAFETY: the promise owns the closure until `Ended`; the entry calls it as a task would.
    let status =
        unsafe { fault::msrt_guard_call(task::closure_entry, closure as *mut u8, &mut msg) };
    let report = if status == 1 {
        fault::fault_report(&msg, &[])
    } else {
        Vec::new()
    };
    // SAFETY: the guard handed over the message, released once.
    unsafe { crate::string::release_opt(&msg) };
    apply(Event::Ended { id, status, report });
}

/// Runs the deferred work of `id` if it has not run: the caller is the waiter.
fn run_deferred(id: i64, deadline: Option<i64>) -> bool {
    let t = table();
    let Some(i) = index(t, id) else { return false };
    if t.flags[i] & DEFERRED == 0 {
        return false;
    }
    t.flags[i] &= !DEFERRED;
    let closure = core::mem::take(&mut t.retry_state[i]) as *mut ms_rt_abi::Closure;
    // Waits inside the work stop at the waiter's deadline: the work runs on this stack, so only
    // its own waits can notice the limit.
    let deadline = deadline
        .unwrap_or(i64::MAX)
        .min(t.limit[i])
        .min(task::defer_deadline());
    let earlier = task::set_defer_deadline(deadline);
    // The closure handed over to `msrt_promise_defer` is dropped when the work ends, and by the
    // cleanup when a cancelled wait inside the work jumps out of it, which skips Rust destructors.
    let release = || {
        // SAFETY: the closure is ours, dropped once.
        unsafe { crate::obj::drop_obj(closure.cast()) };
    };
    // SAFETY: the code is the closure's entry.
    fault::with_cleanup(&mut || release(), || unsafe {
        let code: unsafe extern "C-unwind" fn(*mut ms_rt_abi::Closure) =
            core::mem::transmute((*closure).code);
        code(closure);
    });
    release();
    task::set_defer_deadline(earlier);
    true
}

/// A closure that calls a native entry with the argument it owns.
#[repr(C)]
struct Native {
    closure: ms_rt_abi::Closure,
    entry: unsafe extern "C-unwind" fn(*mut u8),
    arg: *mut u8,
}

/// Whether `closure` is the work of [`start_native`]: a runtime task, started from runtime frames
/// that name no source line, so a fault report gains nothing from walking its starter's stack.
pub(crate) fn is_native_work(closure: *const ms_rt_abi::Closure) -> bool {
    // SAFETY: a live closure object.
    unsafe { (*closure).code == native_code as *const u8 }
}

unsafe extern "C-unwind" fn native_code(closure: *mut ms_rt_abi::Closure) {
    // SAFETY: the task runs the `Native` that `start_native` built, which stays live meanwhile.
    unsafe {
        let n = closure.cast::<Native>();
        ((*n).entry)((*n).arg);
    }
}

unsafe extern "C" fn native_drop(obj: *mut ms_rt_abi::Obj) {
    // SAFETY: the object owns its allocation; the entry took the argument.
    unsafe { alloc::free(obj.cast()) };
}

/// Starts `entry(arg)` as a promise task on this thread (never placed elsewhere) and returns the
/// promise. `entry` owns `arg` and completes nothing: the promise just ends when it returns. A
/// fault or cancellation ends only this promise. Release it with `msrt_promise_drop` once done.
///
/// # Safety
/// `arg` must be valid for `entry`, which owns it.
pub unsafe fn start_native(entry: unsafe extern "C-unwind" fn(*mut u8), arg: *mut u8) -> i64 {
    let id = msrt_promise_new();
    // SAFETY: a fresh object with no captures to drop, handed over to the promise for the task.
    unsafe {
        let n = crate::obj::new_obj(size_of::<Native>(), None, native_drop).cast::<Native>();
        (*n).closure.code = native_code as *const u8;
        (*n).entry = entry;
        (*n).arg = arg;
        start_on(id, n.cast(), Mode::Here);
    }
    id
}

/// Whether the work of promise `id` is over, so [`msrt_promise_drop`] returns at once. Unlike
/// `msrt_promise_done` it never lets other tasks run. An id that no longer exists reads as over.
pub fn work_over(id: i64) -> bool {
    let t = table();
    index(t, id).is_none_or(|i| t.closure[i] == 0)
}

/// Asks the work of promise `id` to stop at its next wait. An id that no longer exists is ignored.
pub fn cancel(id: i64) {
    request_cancel(id)
}

fn outcome(t: &Table, i: usize) -> Option<i64> {
    match t.state[i] {
        State::Ok => Some(OK),
        State::Error => Some(ERROR),
        State::Failed => Some(FAILED),
        State::Cancelled if t.flags[i] & TIMED_OUT != 0 => Some(TIMEOUT),
        State::Cancelled => Some(CANCELLED),
        State::Taken => Some(CLOSED),
        State::Pending | State::Free => None,
    }
}

/// Whether the waiter of slot `i` may be woken from another thread.
fn needs_remote_token(t: &Table, i: usize) -> bool {
    t.flags[i] & REMOTE_WAKE != 0 || (t.closure[i] != 0 && t.flags[i] & HERE == 0)
}

/// Parks until promise `id` changes (an event, a completion, a timeout, a cancellation) and
/// returns how the park ended. The slot is looked up again afterwards, so the caller does too.
fn park_on(id: i64, timeout_ns: i64) -> u32 {
    let t = table();
    let Some(i) = index(t, id) else {
        return 0;
    };
    // The work may finish on another thread, so the scheduler must not call this a deadlock.
    let flags = if needs_remote_token(t, i) {
        task::TOKEN_REMOTE
    } else {
        0
    };
    // SAFETY: single scheduler per isolate; the token is ours until freed.
    unsafe {
        let token = task::msrt_token_new(flags);
        t.token[i] = token;
        let mut value = 0;
        let woke = task::msrt_token_park(token, timeout_ns, &mut value);
        let t = table();
        if let Some(i) = index(t, id)
            && t.token[i] == token
        {
            t.token[i] = 0;
        }
        task::msrt_token_free(token);
        woke
    }
}

/// Waits until `id` finishes or `timeout_ns` passes (negative: no limit) and returns an outcome
/// code. A timeout cancels the work, which stops at its next wait. If the waiting task itself is
/// cancelled, it unwinds; dropping the promise then cancels and joins the work.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_wait(id: i64, timeout_ns: i64) -> i64 {
    if is_foreign(id) {
        return wait_foreign(id, timeout_ns);
    }
    let own = (timeout_ns >= 0).then(|| crate::sys::monotonic_ns().saturating_add(timeout_ns));
    // The promise's own limit also bounds the wait, which is how deferred work (it runs on this
    // stack) notices it.
    let limit = index(table(), id).map_or(i64::MAX, |i| table().limit[i]);
    let own = match (own, limit) {
        (o, i64::MAX) => o,
        (Some(o), l) => Some(o.min(l)),
        (None, l) => Some(l),
    };
    // A wait inside deferred work also stops at the outer waiter's deadline.
    let inherited = task::defer_deadline();
    let deadline = match (own, inherited) {
        (o, i64::MAX) => o,
        (Some(o), i) => Some(o.min(i)),
        (None, i) => Some(i),
    };
    if deadline.is_none() {
        run_unstarted(id);
    }
    run_deferred(id, deadline);
    loop {
        let t = table();
        let i = find(id);
        if let Some(code) = outcome(t, i) {
            return code;
        }
        let remaining = deadline.map_or(-1, |d| (d - crate::sys::monotonic_ns()).max(0));
        let woke = park_on(id, remaining);
        if woke == task::WAIT_CANCELLED {
            // The promise may be a temporary that unwinding never drops (`read_file(p).wait()`):
            // cancel its work and wait for it to end now, so what it holds (a listener, a file) is
            // released before the unwinding task goes on.
            msrt_promise_drop(id);
            fault::msrt_cancelled();
        }
        let t = table();
        let Some(i) = index(t, id) else {
            return CLOSED;
        };
        if let Some(code) = outcome(t, i) {
            return code;
        }
        if woke == task::WAIT_TIMEOUT {
            request_cancel(id);
            return TIMEOUT;
        }
    }
}

/// Waits until one of the promises in `ids` (a list of ids) has finished or `timeout_ns` passes
/// (negative: no limit). Answers the index of the first finished one, or -1 on a timeout. A
/// finished promise keeps its result for `msrt_promise_wait` and `msrt_promise_take`; the others
/// are left running, for the caller to drop.
///
/// # Safety
/// `ids` points to a list of `Int` promise ids.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_wait_any(
    ids: *const ms_rt_abi::VecVal,
    timeout_ns: i64,
) -> i64 {
    // SAFETY: forwarded contract; the list is borrowed for the call and not mutated by it.
    let list: Vec<i64> =
        unsafe { core::slice::from_raw_parts((*ids).ptr.cast::<i64>(), (*ids).len) }.to_vec();
    if list.iter().any(|&id| is_foreign(id)) {
        return wait_any_mixed(&list, timeout_ns);
    }
    let first_done = |list: &[i64]| {
        let t = table();
        list.iter()
            .position(|&id| index(t, id).is_none_or(|i| t.state[i] != State::Pending))
    };
    let deadline = (timeout_ns >= 0).then(|| crate::sys::monotonic_ns().saturating_add(timeout_ns));
    // Eager inputs cannot finish on this thread while this loop runs: their events and timers
    // advance only when we park. Only a deferred callback can run work here, so rescan after
    // one runs, not once per input. Otherwise an all-pending list takes quadratic work.
    if first_done(&list).is_none() {
        for &id in &list {
            if run_deferred(id, deadline) && first_done(&list).is_some() {
                break;
            }
        }
    }
    loop {
        if let Some(at) = first_done(&list) {
            return at as i64;
        }
        // SAFETY: single scheduler per isolate; the token is ours until freed.
        unsafe {
            let remote = list
                .iter()
                .any(|&id| index(table(), id).is_some_and(|i| needs_remote_token(table(), i)));
            let token = task::msrt_token_new(if remote { task::TOKEN_REMOTE } else { 0 });
            let t = table();
            for &id in &list {
                if let Some(i) = index(t, id) {
                    if t.token[i] != 0 {
                        fault::fault(b"promise: another task is already waiting on this promise");
                    }
                    t.token[i] = token;
                }
            }
            let remaining = deadline.map_or(-1, |d| (d - crate::sys::monotonic_ns()).max(0));
            let mut value = 0;
            let woke = task::msrt_token_park(token, remaining, &mut value);
            let t = table();
            for &id in &list {
                if let Some(i) = index(t, id)
                    && t.token[i] == token
                {
                    t.token[i] = 0;
                }
            }
            task::msrt_token_free(token);
            if woke == task::WAIT_CANCELLED {
                fault::msrt_cancelled();
            }
            if let Some(at) = first_done(&list) {
                return at as i64;
            }
            if woke == task::WAIT_TIMEOUT {
                return -1;
            }
        }
    }
}

/// `msrt_promise_wait_any` over a list that holds promises of other threads: the local ones are
/// watched through their token slot as usual, the others by registering the waiter's token with
/// their owners, which post it when the promise changes.
fn wait_any_mixed(list: &[i64], timeout_ns: i64) -> i64 {
    let deadline = (timeout_ns >= 0).then(|| crate::sys::monotonic_ns().saturating_add(timeout_ns));
    let inherited = task::defer_deadline();
    let deadline = match (deadline, inherited) {
        (d, i64::MAX) => d,
        (Some(d), inherited) => Some(d.min(inherited)),
        (None, inherited) => Some(inherited),
    };
    let mut deferred = Vec::new();
    if let Some(at) = first_done_mixed(list, Some(&mut deferred)) {
        return at as i64;
    }
    // Match the same-thread path: run deferred inputs only after checking readiness, and
    // rescan after a callback because it can complete a different input. Remember which inputs
    // are deferred so eager foreign inputs do not pay for another request that does no work.
    for id in deferred {
        let foreign = is_foreign(id);
        let ran = if foreign {
            matches!(
                ask(id, move || Answer::Flag(run_deferred(id, deadline))),
                Answer::Flag(true)
            )
        } else {
            run_deferred(id, deadline)
        };
        // Even a no-op foreign request parks and can advance this thread's inputs.
        if (ran || foreign)
            && let Some(at) = first_done_mixed(list, None)
        {
            return at as i64;
        }
    }
    let mut timed_out = false;
    loop {
        // SAFETY: the token is ours until freed.
        let token = unsafe { task::msrt_token_new(task::TOKEN_REMOTE) };
        let mut finished = None;
        let mut watched = Vec::new();
        for (at, &id) in list.iter().enumerate() {
            let done = if is_foreign(id) {
                match ask(id, move || watch(id, token)) {
                    Answer::Pending => {
                        watched.push(id);
                        false
                    }
                    _ => true,
                }
            } else {
                let t = table();
                index(t, id).is_none_or(|i| t.state[i] != State::Pending)
            };
            if done {
                finished = Some(at);
                break;
            }
        }
        // A foreign registration parks this task. A local input checked earlier may finish
        // during that park, before its token was installed, so inspect local inputs once more.
        if finished.is_none() {
            finished = list.iter().position(|&id| {
                !is_foreign(id)
                    && index(table(), id).is_none_or(|i| table().state[i] != State::Pending)
            });
        }
        if finished.is_none() {
            let t = table();
            for &id in list.iter().filter(|&&id| !is_foreign(id)) {
                if let Some(i) = index(t, id) {
                    if t.token[i] != 0 {
                        fault::fault(b"promise: another task is already waiting on this promise");
                    }
                    t.token[i] = token;
                }
            }
            let remaining = deadline.map_or(-1, |d| (d - crate::sys::monotonic_ns()).max(0));
            let mut value = 0;
            // SAFETY: single scheduler per isolate; the token is ours.
            let woke = unsafe { task::msrt_token_park(token, remaining, &mut value) };
            let t = table();
            for &id in list.iter().filter(|&&id| !is_foreign(id)) {
                if let Some(i) = index(t, id)
                    && t.token[i] == token
                {
                    t.token[i] = 0;
                }
            }
            timed_out = woke == task::WAIT_TIMEOUT;
            if woke == task::WAIT_CANCELLED {
                finished = Some(usize::MAX);
            }
        }
        for id in watched {
            ask(id, move || unwatch(id, token));
        }
        // SAFETY: no owner holds a registration of it any more.
        unsafe { task::msrt_token_free(token) };
        match finished {
            Some(usize::MAX) => fault::msrt_cancelled(),
            Some(at) => return at as i64,
            None if timed_out => return -1,
            None => {}
        }
    }
}

/// Inspects readiness without running callbacks. Optionally collects deferred inputs for the
/// initial work phase, avoiding a second remote request for every eager input.
fn first_done_mixed(list: &[i64], mut deferred: Option<&mut Vec<i64>>) -> Option<usize> {
    for (at, &id) in list.iter().enumerate() {
        let inspect = move || {
            let t = table();
            let i = index(t, id);
            Answer::Readiness {
                done: i.is_none_or(|i| t.state[i] != State::Pending),
                deferred: i.is_some_and(|i| t.flags[i] & DEFERRED != 0),
            }
        };
        let answer = if is_foreign(id) {
            ask(id, inspect)
        } else {
            inspect()
        };
        match answer {
            Answer::Readiness {
                done: false,
                deferred: work,
            } => {
                if work && let Some(ref mut deferred) = deferred {
                    deferred.push(id);
                }
            }
            _ => return Some(at),
        }
    }
    // A query of a foreign input parks, so earlier local inputs may have finished meanwhile.
    list.iter().position(|&id| {
        !is_foreign(id) && index(table(), id).is_none_or(|i| table().state[i] != State::Pending)
    })
}

/// The report of a fault that ended `id` (empty otherwise).
///
/// # Safety
/// `out` is writable memory for a string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_fault_report(id: i64, out: *mut ms_rt_abi::StrVal) {
    let foreign;
    let t = table();
    let report = if is_foreign(id) {
        foreign = match ask(id, move || {
            let t = table();
            Answer::Bytes(
                index(t, id)
                    .map(|i| t.report[i].clone())
                    .unwrap_or_default(),
            )
        }) {
            Answer::Bytes(bytes) => bytes,
            _ => Vec::new(),
        };
        foreign.as_slice()
    } else {
        index(t, id).map(|i| t.report[i].as_slice()).unwrap_or(&[])
    };
    // SAFETY: `out` is uninitialised memory for a string.
    unsafe { *out = crate::string::from_bytes(report) };
}

/// Drops `id`: an unfinished promise is cancelled and joined first, then its slot and any
/// result not taken are released. An id that no longer exists does nothing.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_drop(id: i64) {
    if is_foreign(id) {
        ask(id, move || {
            msrt_promise_drop(id);
            Answer::Unit
        });
        return;
    }
    let t = table();
    let Some(i) = index(t, id) else { return };
    if t.cancel[i] != 0 {
        crate::cancel::unregister(core::mem::take(&mut t.cancel[i]), id);
    }
    if t.fd[i] >= 0 && t.state[i] == State::Pending {
        // SAFETY: single scheduler per isolate.
        unsafe { task::unwatch_fd_for_promise(t.fd[i], id) };
        t.fd[i] = -1;
    }
    if t.flags[i] & DEFERRED != 0 {
        t.flags[i] &= !DEFERRED;
        let closure = core::mem::take(&mut t.retry_state[i]);
        // SAFETY: the closure handed over to `msrt_promise_defer`, never used.
        unsafe { crate::obj::drop_obj(closure as *mut ms_rt_abi::Obj) };
    }
    if t.state[i] == State::Pending
        && let Some(retry) = core::mem::take(&mut t.retry[i])
    {
        retry(id, t.retry_state[i], task::WAIT_CANCELLED);
    }
    if t.closure[i] != 0 {
        if t.state[i] == State::Pending {
            request_cancel(id);
        }
        // Join: the task is over when the runner has told us so. Cleanup is not interrupted.
        fault::msrt_shield_enter();
        loop {
            let t = table();
            match index(t, id) {
                Some(i) if t.closure[i] != 0 => {
                    park_on(id, -1);
                }
                _ => break,
            }
        }
        fault::msrt_shield_exit();
    }
    let t = table();
    let Some(i) = index(t, id) else { return };
    release_result(t, i);
    t.watchers.retain(|&(slot, _)| slot != i);
    t.state[i] = State::Free;
    t.free.push(i);
}

#[cfg(test)]
mod tests {
    #[test]
    fn a_promise_that_runs_here_wakes_its_waiter_locally() {
        let mut t = super::Table::empty();
        t.flags.push(0);
        t.closure.push(1);
        assert!(super::needs_remote_token(&t, 0));
        t.flags[0] |= super::HERE;
        assert!(!super::needs_remote_token(&t, 0));
        t.flags[0] |= super::REMOTE_WAKE;
        assert!(super::needs_remote_token(&t, 0));
    }

    use super::*;
    use crate::desc::msrt_desc_int;
    use crate::testutil::lock;
    use ms_rt_abi::Closure;

    // The test closures carry the promise id in a static: they have no captures.
    static ID: crate::global::Process<i64> = crate::global::Process::new(0);

    unsafe extern "C" fn drop_closure(obj: *mut ms_rt_abi::Obj) {
        // SAFETY: the test closure has no captures and owns this allocation.
        unsafe { crate::alloc::free(obj.cast()) };
    }

    fn start(id: i64, code: unsafe extern "C-unwind" fn(*mut Closure)) {
        // SAFETY: the capture-free closure is handed to the promise, which drops it when the task ends.
        unsafe {
            *ID.ptr() = id;
            let closure =
                crate::obj::new_obj(size_of::<Closure>(), None, drop_closure).cast::<Closure>();
            (*closure).code = code as *const u8;
            msrt_promise_start(id, closure);
        }
    }

    unsafe extern "C-unwind" fn answer(_: *mut Closure) {
        // SAFETY: stores a stack Int the callee takes.
        unsafe {
            let mut v = 42i64;
            msrt_promise_put(*ID.ptr(), (&raw mut v).cast(), &msrt_desc_int, 0);
        }
    }

    unsafe extern "C-unwind" fn fails(_: *mut Closure) {
        crate::fault::fault(b"boom");
    }

    unsafe extern "C-unwind" fn hangs(_: *mut Closure) {
        // SAFETY: called from a running task.
        unsafe { task::msrt_task_sleep(3_600_000_000_000) };
    }

    fn take_int(id: i64) -> i64 {
        let mut v = 0i64;
        // SAFETY: `v` is an Int slot.
        assert_eq!(
            unsafe { msrt_promise_take(id, &msrt_desc_int, (&raw mut v).cast()) },
            1
        );
        v
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn wait_any_handles_a_large_eager_pending_list() {
        let _g = lock();
        let mut ids: Vec<i64> = (0..40_000).map(|_| msrt_promise_new()).collect();
        assert_eq!(wait_any_probe(&mut ids, 0), -1);
        for id in ids {
            msrt_promise_drop(id);
        }
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_promise_task_delivers_its_result_once() {
        let _g = lock();
        let id = msrt_promise_new();
        start(id, answer);
        assert_eq!(msrt_promise_wait(id, -1), OK);
        assert_eq!(msrt_promise_done(id), 1);
        assert_eq!(take_int(id), 42);
        assert_eq!(msrt_promise_wait(id, -1), CLOSED);
        msrt_promise_drop(id);
        // A dropped id is stale: done reads as finished and the slot's next promise is distinct.
        assert_eq!(msrt_promise_done(id), 1);
        task::teardown();
    }

    crate::isolate_static! {
        static RAN_IN: u64 = 0;
    }

    unsafe extern "C-unwind" fn note_task(_: *mut Closure) {
        // SAFETY: called from a running task; stores a stack Int the callee takes.
        unsafe {
            *RAN_IN.ptr() = task::msrt_task_current();
            let mut v = 1i64;
            msrt_promise_put(*ID.ptr(), (&raw mut v).cast(), &msrt_desc_int, 0);
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn waiting_on_a_promise_nobody_took_runs_it_in_the_waiters_task() {
        let _g = lock();
        // Starting a promise offers it to a new scheduler thread when the limit allows one, and
        // that thread can take it before the waiter does; one thread leaves nobody to take it.
        let limit = sched::msrt_runtime_limit();
        sched::msrt_runtime_set_threads(1);
        let id = msrt_promise_new();
        start(id, note_task);
        // SAFETY: the test runs as a task.
        let me = unsafe { task::msrt_task_current() };
        assert_eq!(msrt_promise_wait(id, -1), OK);
        // SAFETY: this isolate's state.
        assert_eq!(unsafe { *RAN_IN.ptr() }, me);
        assert_eq!(take_int(id), 1);
        msrt_promise_drop(id);
        task::teardown();
        sched::msrt_runtime_set_threads(limit);
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_fault_inside_ends_only_that_promise() {
        let _g = lock();
        let id = msrt_promise_new();
        start(id, fails);
        assert_eq!(msrt_promise_wait(id, -1), FAILED);
        let mut report = crate::string::NO_STR;
        // SAFETY: `report` is writable, and the string the call makes is ours.
        unsafe {
            msrt_promise_fault_report(id, &mut report);
            assert!(crate::string::bytes(&report).starts_with(b"boom"));
            crate::string::release_opt(&report);
        }
        msrt_promise_drop(id);
        task::teardown();
    }

    unsafe extern "C-unwind" fn nap(arg: *mut u8) {
        // SAFETY: called from a running task.
        unsafe { task::msrt_task_sleep(arg as usize as i64 * 1_000_000) };
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn native_promises_end_alone_or_are_cancelled_and_joined() {
        let _g = lock();
        // SAFETY: tests hold the runtime lock; `nap` takes no ownership of its argument.
        unsafe {
            let before = task::msrt_task_count();
            let short = start_native(nap, 2usize as *mut u8);
            let long = start_native(nap, 3_600_000usize as *mut u8);
            assert!(!work_over(long));
            while !work_over(short) {
                task::msrt_task_sleep(1_000_000);
            }
            msrt_promise_drop(short);
            cancel(long);
            msrt_promise_drop(long);
            assert!(work_over(long));
            assert_eq!(task::msrt_task_count(), before);
        }
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_timeout_cancels_the_work_and_drop_joins_it() {
        let _g = lock();
        // SAFETY: tests hold the runtime lock.
        let before = unsafe { task::msrt_task_count() };
        let id = msrt_promise_new();
        start(id, hangs);
        assert_eq!(msrt_promise_wait(id, 5_000_000), TIMEOUT);
        msrt_promise_drop(id);
        // SAFETY: as above.
        assert_eq!(unsafe { task::msrt_task_count() }, before);
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_limit_ends_the_work_without_a_waiter() {
        let _g = lock();
        // SAFETY: tests hold the runtime lock.
        let before = unsafe { task::msrt_task_count() };
        let id = msrt_promise_new();
        msrt_promise_limit(id, 5_000_000);
        start(id, hangs);
        // Nobody waits: other tasks run until the limit passes and the work ends.
        // SAFETY: tests hold the runtime lock.
        unsafe { task::msrt_task_sleep(60_000_000) };
        assert!(msrt_promise_done(id) != 0);
        assert_eq!(msrt_promise_wait(id, -1), TIMEOUT);
        msrt_promise_drop(id);
        // SAFETY: as above.
        assert_eq!(unsafe { task::msrt_task_count() }, before);
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn cancelling_a_promise_ends_it_as_cancelled() {
        let _g = lock();
        let id = msrt_promise_new();
        start(id, hangs);
        msrt_promise_cancel(id);
        assert_eq!(msrt_promise_wait(id, -1), CANCELLED);
        msrt_promise_drop(id);
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn dropping_an_unfinished_promise_cancels_it() {
        let _g = lock();
        let id = msrt_promise_new();
        start(id, hangs);
        msrt_promise_drop(id);
        assert_eq!(msrt_promise_done(id), 1);
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn teardown_releases_the_promise_table() {
        let _g = lock();
        let id = msrt_promise_sleep(1_000_000);
        assert_eq!(msrt_promise_wait(id, -1), OK);
        assert!(table().state.capacity() > 0);
        task::teardown();
        let t = table();
        assert_eq!(t.state.capacity(), 0);
        assert_eq!(t.result.capacity(), 0);
        assert_eq!(t.free.capacity(), 0);
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_sleep_promise_has_no_task_and_ends_on_time() {
        let _g = lock();
        // SAFETY: tests hold the runtime lock.
        let before = unsafe { task::msrt_task_count() };
        let id = msrt_promise_sleep(5_000_000);
        // SAFETY: as above.
        assert_eq!(unsafe { task::msrt_task_count() }, before);
        assert_eq!(msrt_promise_done(id), 0);
        let start = crate::sys::monotonic_ns();
        assert_eq!(msrt_promise_wait(id, -1), OK);
        assert!(crate::sys::monotonic_ns() - start >= 4_000_000);
        msrt_promise_drop(id);
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn waiting_with_a_timeout_on_a_longer_sleep_times_out() {
        let _g = lock();
        let id = msrt_promise_sleep(3_600_000_000_000);
        assert_eq!(msrt_promise_wait(id, 5_000_000), TIMEOUT);
        // Dropping a sleep that never finished leaves a stale timer, which nothing waits for.
        msrt_promise_drop(id);
        assert_eq!(next_deadline(), None);
        task::teardown();
    }

    fn raw(stream: &std::net::TcpStream) -> i32 {
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
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_readiness_promise_completes_when_the_descriptor_is() {
        use std::io::{Read, Write};
        let _g = lock();
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let mut client = std::net::TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let (mut server, _) = listener.accept().unwrap();
        server.set_nonblocking(true).unwrap();
        let fd = raw(&server);
        let id = msrt_promise_ready(i64::from(fd), i64::from(task::WAIT_READ), -1);
        assert!(id > 0);
        assert_eq!(msrt_promise_done(id), 0);
        client.write_all(b"x").unwrap();
        assert_eq!(msrt_promise_wait(id, -1), OK);
        assert_eq!(take_int(id) & i64::from(task::WAIT_READ), 1);
        msrt_promise_drop(id);
        // A wait nothing satisfies times out and leaves no registration behind.
        let mut byte = [0u8; 1];
        assert_eq!(server.read(&mut byte).unwrap(), 1);
        let late = msrt_promise_ready(i64::from(fd), i64::from(task::WAIT_READ), 5_000_000);
        assert_eq!(msrt_promise_wait(late, -1), OK);
        assert_eq!(take_int(late), i64::from(task::WAIT_TIMEOUT));
        msrt_promise_drop(late);
        let dropped = msrt_promise_ready(i64::from(fd), i64::from(task::WAIT_READ), -1);
        msrt_promise_drop(dropped);
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn wait_any_answers_the_first_to_finish() {
        let _g = lock();
        let slow = msrt_promise_sleep(3_600_000_000_000);
        let fast = msrt_promise_sleep(5_000_000);
        let mut ids = vec![slow, fast];
        let list = ms_rt_abi::VecVal {
            ptr: ids.as_mut_ptr().cast(),
            len: ids.len(),
            cap: ids.len(),
        };
        // SAFETY: `list` borrows `ids`, which outlives the calls.
        unsafe {
            assert_eq!(msrt_promise_wait_any(&list, -1), 1);
            assert_eq!(msrt_promise_wait_any(&list, -1), 1);
            msrt_promise_drop(fast);
            // Only the slow one is left, and a short limit passes first.
            let only = ms_rt_abi::VecVal {
                ptr: ids.as_mut_ptr().cast(),
                len: 1,
                cap: 1,
            };
            assert_eq!(msrt_promise_wait_any(&only, 5_000_000), -1);
        }
        msrt_promise_drop(slow);
        task::teardown();
    }

    static DEFERRED_CALLS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    static DEFERRED_DROPS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    static DEFERRED_DEADLINE: std::sync::atomic::AtomicI64 = std::sync::atomic::AtomicI64::new(0);

    unsafe extern "C" fn drop_deferred_probe(obj: *mut ms_rt_abi::Obj) {
        DEFERRED_DROPS.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        // SAFETY: the test closure owns its allocation.
        unsafe { drop_closure(obj) };
    }

    fn deferred_probe() -> i64 {
        let id = msrt_promise_new();
        // SAFETY: the closure owns its captured id and is handed to the deferred promise.
        unsafe {
            let closure = crate::obj::new_obj(size_of::<Closure>() + 8, None, drop_deferred_probe)
                .cast::<Closure>();
            (*closure).code = probe_deferred as *const u8;
            closure.add(1).cast::<i64>().write(id);
            msrt_promise_defer(id, closure);
        }
        id
    }

    unsafe extern "C-unwind" fn probe_deferred(closure: *mut Closure) {
        use std::sync::atomic::Ordering::SeqCst;
        DEFERRED_CALLS.fetch_add(1, SeqCst);
        DEFERRED_DEADLINE.store(task::defer_deadline(), SeqCst);
        // SAFETY: `deferred_probe` stored the id after the header; the value is a live Int slot.
        unsafe {
            let mut value = 42i64;
            msrt_promise_put(id_of(closure), (&raw mut value).cast(), &msrt_desc_int, 0);
        }
    }

    fn wait_any_probe(ids: &mut [i64], timeout_ns: i64) -> i64 {
        let list = ms_rt_abi::VecVal {
            ptr: ids.as_mut_ptr().cast(),
            len: ids.len(),
            cap: ids.len(),
        };
        // SAFETY: `list` borrows `ids`, which outlives the call.
        unsafe { msrt_promise_wait_any(&list, timeout_ns) }
    }

    #[test]
    fn wait_any_does_not_run_deferred_work_when_an_input_is_done() {
        let _g = lock();
        use std::sync::atomic::Ordering::SeqCst;
        DEFERRED_CALLS.store(0, SeqCst);
        DEFERRED_DROPS.store(0, SeqCst);
        let pending = deferred_probe();
        let ready = msrt_promise_finished();
        let winner = wait_any_probe(&mut [pending, ready], -1);
        let calls = DEFERRED_CALLS.load(SeqCst);
        msrt_promise_drop(pending);
        msrt_promise_drop(ready);
        task::teardown();
        assert_eq!(winner, 1);
        assert_eq!(calls, 0);
        assert_eq!(DEFERRED_DROPS.load(SeqCst), 1);
    }

    #[test]
    fn wait_any_stops_deferred_work_when_a_callback_finishes_another_input() {
        let _g = lock();
        use std::sync::atomic::Ordering::SeqCst;
        DEFERRED_CALLS.store(0, SeqCst);
        DEFERRED_DROPS.store(0, SeqCst);
        let completed = msrt_promise_new();
        let first = msrt_promise_new();
        // SAFETY: the closure owns the target id after its header; running it completes the
        // third input rather than its own promise. The first promise owns the closure.
        unsafe {
            let closure = crate::obj::new_obj(size_of::<Closure>() + 8, None, drop_deferred_probe)
                .cast::<Closure>();
            (*closure).code = probe_deferred as *const u8;
            closure.add(1).cast::<i64>().write(completed);
            msrt_promise_defer(first, closure);
        }
        let second = deferred_probe();
        assert_eq!(wait_any_probe(&mut [first, second, completed], -1), 2);
        assert_eq!(DEFERRED_CALLS.load(SeqCst), 1);
        assert_eq!(take_int(completed), 42);
        for id in [first, second, completed] {
            msrt_promise_drop(id);
        }
        task::teardown();
        assert_eq!(DEFERRED_DROPS.load(SeqCst), 2);
    }

    #[test]
    fn wait_any_deferred_work_observes_the_earlier_promise_and_inherited_limit() {
        let _g = lock();
        use std::sync::atomic::Ordering::SeqCst;
        let hour = 3_600_000_000_000;
        for (own, inherited) in [
            (Some(hour), None),
            (None, Some(hour / 2)),
            (Some(hour), Some(hour / 2)),
            (Some(hour / 2), Some(hour)),
        ] {
            let id = deferred_probe();
            if let Some(duration) = own {
                msrt_promise_limit(id, duration);
            }
            let outer = inherited.map_or(i64::MAX, |d| crate::sys::monotonic_ns() + d);
            let expected = table().limit[find(id)].min(outer);
            let previous = task::set_defer_deadline(outer);
            let winner = wait_any_probe(&mut [id], -1);
            let observed = DEFERRED_DEADLINE.load(SeqCst);
            let restored = task::defer_deadline();
            task::set_defer_deadline(previous);
            msrt_promise_drop(id);
            task::teardown();
            assert_eq!(winner, 0);
            assert_eq!(observed, expected);
            assert_eq!(restored, outer);
        }
    }

    #[test]
    fn wait_any_deferred_work_observes_an_earlier_explicit_wait_limit() {
        let _g = lock();
        use std::sync::atomic::Ordering::SeqCst;
        let id = deferred_probe();
        msrt_promise_limit(id, 3_600_000_000_000);
        let outer = crate::sys::monotonic_ns() + 1_800_000_000_000;
        let previous = task::set_defer_deadline(outer);
        let before = crate::sys::monotonic_ns();
        let winner = wait_any_probe(&mut [id], 1_000_000_000);
        let after = crate::sys::monotonic_ns();
        let observed = DEFERRED_DEADLINE.load(SeqCst);
        let restored = task::defer_deadline();
        task::set_defer_deadline(previous);
        msrt_promise_drop(id);
        task::teardown();
        assert_eq!(winner, 0);
        assert!((before + 1_000_000_000..=after + 1_000_000_000).contains(&observed));
        assert_eq!(restored, outer);
    }

    // Closures that carry the id of their promise after the header.
    fn start_with_id(id: i64, code: unsafe extern "C-unwind" fn(*mut Closure)) {
        // SAFETY: the closure is handed to the promise, which drops it when its task has ended.
        unsafe {
            let size = size_of::<Closure>() + 8;
            let closure = crate::obj::new_obj(size, None, drop_closure).cast::<Closure>();
            (*closure).code = code as *const u8;
            closure.add(1).cast::<i64>().write(id);
            msrt_promise_start(id, closure);
        }
    }

    unsafe fn id_of(closure: *mut Closure) -> i64 {
        // SAFETY: `start_with_id` stored the id after the header.
        unsafe { closure.add(1).cast::<i64>().read() }
    }

    static SEEN: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

    /// Waits for a second thread to join in, then answers the number of its own thread.
    unsafe extern "C-unwind" fn answer_thread(closure: *mut Closure) {
        // SAFETY: called from a running task with the closure `start_with_id` made.
        unsafe {
            // Stay until a second thread has joined in, so a slow operating system cannot hand
            // every promise to the first thread that gets to run.
            SEEN.fetch_or(1 << sched::current(), std::sync::atomic::Ordering::SeqCst);
            let end = crate::sys::monotonic_ns() + 3_000_000_000;
            while SEEN.load(std::sync::atomic::Ordering::SeqCst).count_ones() < 2
                && crate::sys::monotonic_ns() < end
            {
                // Busy, not asleep: an idle thread takes work that has not started, and a thread
                // full of sleepers still counts as idle.
                std::hint::spin_loop();
            }
            let mut v = sched::current() as i64;
            msrt_promise_put(id_of(closure), (&raw mut v).cast(), &msrt_desc_int, 0);
        }
    }

    unsafe extern "C-unwind" fn hang_with_id(_: *mut Closure) {
        // SAFETY: called from a running task.
        unsafe { task::msrt_task_sleep(3_600_000_000_000) };
    }

    unsafe extern "C-unwind" fn fail_with_id(_: *mut Closure) {
        crate::fault::fault(b"remote boom");
    }

    /// Runs until `ms` milliseconds have passed, without ever waiting.
    unsafe extern "C-unwind" fn spin_thread(closure: *mut Closure) {
        let end = crate::sys::monotonic_ns() + 40_000_000;
        while crate::sys::monotonic_ns() < end {
            std::hint::spin_loop();
        }
        // SAFETY: called from a running task with the closure `start_with_id` made.
        unsafe {
            let mut v = sched::current() as i64;
            msrt_promise_put(id_of(closure), (&raw mut v).cast(), &msrt_desc_int, 0);
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn promises_spread_over_threads_and_deliver_by_event() {
        let _g = lock();
        sched::msrt_runtime_set_threads(4);
        SEEN.store(0, std::sync::atomic::Ordering::SeqCst);
        sched::warm(4);
        let ids: Vec<i64> = (0..8).map(|_| msrt_promise_new()).collect();
        for &id in &ids {
            start_with_id(id, answer_thread);
        }
        let mut threads = std::collections::BTreeSet::new();
        for &id in &ids {
            assert_eq!(msrt_promise_wait(id, -1), OK);
            threads.insert(take_int(id));
        }
        assert!(threads.len() >= 2, "ran on {threads:?}");
        for id in ids {
            msrt_promise_drop(id);
        }
        sched::shutdown();
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn ends_from_other_threads_drain_through_a_few_tasks() {
        let _g = lock();
        sched::msrt_runtime_set_threads(4);
        sched::warm(4);
        let ids: Vec<i64> = (0..2000).map(|_| msrt_promise_new()).collect();
        for &id in &ids {
            start_with_id(id, answer_thread);
        }
        for &id in &ids {
            assert_eq!(msrt_promise_wait(id, -1), OK);
        }
        assert!(ends().enders <= ENDERS + 1, "{} enders", ends().enders);
        for id in ids {
            msrt_promise_drop(id);
        }
        sched::shutdown();
        task::teardown();
        assert!(ends().jobs.is_empty());
    }

    fn slow_job(ms: &u64) -> u64 {
        std::thread::sleep(std::time::Duration::from_millis(*ms));
        *ms
    }

    /// Hands a blocking job to the pool and answers its result, from whichever thread runs it.
    unsafe extern "C-unwind" fn pool_job(closure: *mut Closure) {
        let got = crate::glue::pool::run(crate::glue::pool::Lane::General, 40u64, slow_job, -1);
        // SAFETY: called from a running task with the closure `start_with_id` made.
        unsafe {
            let mut v = got.unwrap_or(0) as i64;
            msrt_promise_put(id_of(closure), (&raw mut v).cast(), &msrt_desc_int, 0);
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn promises_on_scheduler_threads_hand_blocking_work_to_the_pool() {
        let _g = lock();
        sched::msrt_runtime_set_threads(4);
        let ids: Vec<i64> = (0..6).map(|_| msrt_promise_new()).collect();
        for &id in &ids {
            start_with_id(id, pool_job);
        }
        for &id in &ids {
            assert_eq!(msrt_promise_wait(id, -1), OK);
            assert_eq!(take_int(id), 40);
        }
        for id in ids {
            msrt_promise_drop(id);
        }
        sched::shutdown();
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn idle_threads_take_promises_that_have_not_started() {
        let _g = lock();
        sched::msrt_runtime_set_threads(4);
        sched::warm(4);
        let ids: Vec<i64> = (0..3).map(|_| msrt_promise_new()).collect();
        let began = crate::sys::monotonic_ns();
        for &id in &ids {
            start_with_id(id, spin_thread);
        }
        let mut threads = std::collections::BTreeSet::new();
        for &id in &ids {
            assert_eq!(msrt_promise_wait(id, -1), OK);
            threads.insert(take_int(id));
        }
        // Three 40 ms spins on one thread would take 120 ms.
        let took = crate::sys::monotonic_ns() - began;
        assert!(threads.len() >= 2, "ran on {threads:?} in {took} ns");
        for id in ids {
            msrt_promise_drop(id);
        }
        sched::shutdown();
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn touching_main_thread_state_keeps_the_mains_promises_on_it() {
        let _g = lock();
        // `Global` holds main-thread-only state (the terminal); a promise that reaches it from
        // another thread faults, so once the main thread has used one, its promises stay put.
        static CELL: crate::ffi::Global<core::cell::Cell<u8>> =
            crate::ffi::Global::new(core::cell::Cell::new(0));
        CELL.get().set(1);
        assert!(sched::pinned_here());
        sched::unpin_main();
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn promises_started_beside_a_used_native_stream_stay_on_its_thread() {
        let _g = lock();
        sched::msrt_runtime_set_threads(4);
        sched::warm(4);
        let pin = sched::Pin::new();
        pin.touch();
        let ids: Vec<i64> = (0..4).map(|_| msrt_promise_new()).collect();
        for &id in &ids {
            start_with_id(id, spin_thread);
        }
        let mut threads = std::collections::BTreeSet::new();
        for &id in &ids {
            assert_eq!(msrt_promise_wait(id, -1), OK);
            threads.insert(take_int(id));
        }
        assert_eq!(threads.len(), 1, "ran on {threads:?}");
        for id in ids {
            msrt_promise_drop(id);
        }
        drop(pin);
        sched::shutdown();
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn spread_promises_land_on_distinct_threads_even_beside_a_pinned_stream() {
        let _g = lock();
        sched::msrt_runtime_set_threads(4);
        sched::warm(4);
        // A pinned stream keeps ordinary promises here; a spread one is placed on purpose.
        let pin = sched::Pin::new();
        pin.touch();
        let ids: Vec<i64> = (0..3).map(|_| msrt_promise_new()).collect();
        for &id in &ids {
            // SAFETY: the closure is handed to the promise, which drops it when its task ended.
            unsafe {
                let size = size_of::<Closure>() + 8;
                let closure = crate::obj::new_obj(size, None, drop_closure).cast::<Closure>();
                (*closure).code = spin_thread as *const u8;
                closure.add(1).cast::<i64>().write(id);
                msrt_promise_start_spread(id, closure);
            }
        }
        let mut threads = std::collections::BTreeSet::new();
        for &id in &ids {
            assert_eq!(msrt_promise_wait(id, -1), OK);
            threads.insert(take_int(id));
        }
        assert!(threads.len() >= 2, "ran on {threads:?}");
        for id in ids {
            msrt_promise_drop(id);
        }
        drop(pin);
        sched::shutdown();
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn dropping_running_promises_cancels_them_on_their_threads() {
        let _g = lock();
        sched::msrt_runtime_set_threads(4);
        let ids: Vec<i64> = (0..6).map(|_| msrt_promise_new()).collect();
        for &id in &ids {
            start_with_id(id, hang_with_id);
        }
        // Let some of them start.
        let nap = msrt_promise_sleep(20_000_000);
        assert_eq!(msrt_promise_wait(nap, -1), OK);
        msrt_promise_drop(nap);
        let began = crate::sys::monotonic_ns();
        for id in ids {
            msrt_promise_drop(id);
        }
        assert!(crate::sys::monotonic_ns() - began < 2_000_000_000);
        sched::shutdown();
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_fault_on_another_thread_ends_only_that_promise() {
        let _g = lock();
        sched::msrt_runtime_set_threads(4);
        let ids: Vec<i64> = (0..4).map(|_| msrt_promise_new()).collect();
        for &id in &ids {
            start_with_id(id, fail_with_id);
        }
        for &id in &ids {
            assert_eq!(msrt_promise_wait(id, -1), FAILED);
            let mut report = crate::string::NO_STR;
            // SAFETY: `report` is writable, and the string the call makes is ours.
            unsafe {
                msrt_promise_fault_report(id, &mut report);
                assert!(crate::string::bytes(&report).starts_with(b"remote boom"));
                crate::string::release_opt(&report);
            }
        }
        for id in ids {
            msrt_promise_drop(id);
        }
        sched::shutdown();
        task::teardown();
    }

    static RETRIES: crate::global::Process<[usize; 3]> = crate::global::Process::new([0; 3]);

    /// Reads one byte when the descriptor is ready, as a native read would.
    fn read_one(id: i64, state: usize, bits: u32) -> bool {
        use std::io::Read;
        // SAFETY: the test holds the runtime lock; `state` is the address of a live stream.
        unsafe {
            let counts = &mut *RETRIES.ptr();
            if bits == task::WAIT_CANCELLED {
                counts[2] += 1;
                return false;
            }
            counts[0] += 1;
            let stream = &mut *(state as *mut std::net::TcpStream);
            let mut byte = [0u8; 1];
            match stream.read(&mut byte) {
                Ok(1) => {
                    let mut v = i64::from(byte[0]);
                    io_put(id, (&raw mut v).cast(), &msrt_desc_int, false);
                    true
                }
                _ => {
                    // Not ready after all, or the wait timed out.
                    if bits & task::WAIT_TIMEOUT != 0 {
                        counts[1] += 1;
                        let mut v = -1i64;
                        io_put(id, (&raw mut v).cast(), &msrt_desc_int, false);
                    }
                    false
                }
            }
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_native_continuation_finishes_an_io_promise_without_a_task() {
        use std::io::Write;
        let _g = lock();
        *unsafe { &mut *RETRIES.ptr() } = [0; 3];
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let mut client = std::net::TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let (mut server, _) = listener.accept().unwrap();
        server.set_nonblocking(true).unwrap();
        let fd = raw(&server);
        let state = (&raw mut server) as usize;
        // SAFETY: tests hold the runtime lock.
        let before = unsafe { task::msrt_task_count() };
        let id = io_new();
        assert!(io_on_ready(id, fd, task::WAIT_READ, -1, read_one, state));
        // SAFETY: as above.
        assert_eq!(unsafe { task::msrt_task_count() }, before);
        client.write_all(b"z").unwrap();
        assert_eq!(msrt_promise_wait(id, -1), OK);
        assert_eq!(take_int(id), i64::from(b'z'));
        msrt_promise_drop(id);
        // A wait that nothing satisfies times out through the continuation.
        let late = io_new();
        assert!(io_on_ready(
            late,
            fd,
            task::WAIT_READ,
            5_000_000,
            read_one,
            state
        ));
        assert_eq!(msrt_promise_wait(late, -1), OK);
        assert_eq!(take_int(late), -1);
        msrt_promise_drop(late);
        // Dropping a pending one tells the continuation to release its state.
        let dropped = io_new();
        assert!(io_on_ready(
            dropped,
            fd,
            task::WAIT_READ,
            -1,
            read_one,
            state
        ));
        msrt_promise_drop(dropped);
        // SAFETY: as above.
        let counts = unsafe { *RETRIES.ptr() };
        assert_eq!((counts[1], counts[2]), (1, 1));
        task::teardown();
    }

    /// The sleep promise the cross-thread tests wait on from the promise's work, set by the test.
    static TARGET: crate::global::Process<i64> = crate::global::Process::new(0);

    /// Waits for `TARGET` (a promise of the main thread) and answers `10 * thread + outcome`; the
    /// thread number tells the test where the work ran.
    unsafe extern "C-unwind" fn wait_target(closure: *mut Closure) {
        // SAFETY: called from a running task with the closure `start_with_id` made.
        unsafe {
            let code = msrt_promise_wait(*TARGET.ptr(), -1);
            let mut v = sched::current() as i64 * 10 + code;
            msrt_promise_put(id_of(closure), (&raw mut v).cast(), &msrt_desc_int, 0);
        }
    }

    /// Waits for `TARGET` with a limit that passes first.
    unsafe extern "C-unwind" fn wait_target_briefly(closure: *mut Closure) {
        // SAFETY: called from a running task with the closure `start_with_id` made.
        unsafe {
            let code = msrt_promise_wait(*TARGET.ptr(), 5_000_000);
            let mut v = sched::current() as i64 * 10 + code;
            msrt_promise_put(id_of(closure), (&raw mut v).cast(), &msrt_desc_int, 0);
        }
    }

    /// Waits for `TARGET` and a promise of its own thread together: answers
    /// `100 * thread + 10 * index + done`.
    unsafe extern "C-unwind" fn wait_any_target(closure: *mut Closure) {
        // SAFETY: called from a running task with the closure `start_with_id` made.
        unsafe {
            let own = msrt_promise_sleep(3_600_000_000_000);
            let ids = [own, *TARGET.ptr()];
            let list = ms_rt_abi::VecVal {
                ptr: ids.as_ptr() as *mut u8,
                len: 2,
                cap: 2,
            };
            let at = msrt_promise_wait_any(&list, -1);
            let done = msrt_promise_done(*TARGET.ptr());
            msrt_promise_drop(own);
            let mut v = sched::current() as i64 * 100 + at * 10 + i64::from(done);
            msrt_promise_put(id_of(closure), (&raw mut v).cast(), &msrt_desc_int, 0);
        }
    }

    /// Runs `work` as a promise that waits on a sleep promise of the main thread, until an idle
    /// thread has taken it; returns the work's answer, whose thread number is the answer divided
    /// by `scale`. The placement is up to the scheduler, so it tries again.
    fn run_away(work: unsafe extern "C-unwind" fn(*mut Closure), sleep_ns: i64, scale: i64) -> i64 {
        run_away_with_target(work, || msrt_promise_sleep(sleep_ns), scale)
    }

    fn run_away_with_target(
        work: unsafe extern "C-unwind" fn(*mut Closure),
        target: impl Fn() -> i64,
        scale: i64,
    ) -> i64 {
        sched::msrt_runtime_set_threads(4);
        sched::warm(4);
        for _ in 0..40 {
            // SAFETY: a plain Int slot.
            let target = unsafe {
                *TARGET.ptr() = target();
                *TARGET.ptr()
            };
            // The work is the oldest start, so an idle thread takes it once it has waited a beat
            // while the main thread runs the spinner itself.
            let id = msrt_promise_new();
            start_with_id(id, work);
            let spinner = msrt_promise_new();
            start_with_id(spinner, spin_thread);
            assert_eq!(msrt_promise_wait(spinner, -1), OK);
            assert_eq!(msrt_promise_wait(id, -1), OK);
            let got = take_int(id);
            msrt_promise_drop(id);
            msrt_promise_drop(spinner);
            msrt_promise_drop(target);
            if got / scale != 0 {
                return got;
            }
        }
        panic!("the work never ran off the main thread");
    }

    unsafe extern "C-unwind" fn wait_any_local_deferred(closure: *mut Closure) {
        // SAFETY: the running task owns its local promise and output slot.
        unsafe {
            let own = deferred_probe();
            let at = wait_any_probe(&mut [own, *TARGET.ptr()], 1_000_000_000);
            msrt_promise_drop(own);
            let other = deferred_probe();
            let reversed = wait_any_probe(&mut [*TARGET.ptr(), other], 1_000_000_000);
            msrt_promise_drop(other);
            let mut value = sched::current() as i64 * 100 + (at + 1) * 10 + reversed + 1;
            msrt_promise_put(id_of(closure), (&raw mut value).cast(), &msrt_desc_int, 0);
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn mixed_wait_any_runs_local_deferred_work() {
        let _g = lock();
        let got = run_away(wait_any_local_deferred, 3_600_000_000_000, 100);
        sched::shutdown();
        task::teardown();
        assert_eq!(got % 100, 12, "result {got}");
    }

    unsafe extern "C-unwind" fn complete_local(arg: *mut u8) {
        io_done(arg as i64);
    }

    unsafe extern "C-unwind" fn wait_any_completing_local(closure: *mut Closure) {
        // SAFETY: the running task owns the promises, and the detached task only completes `own`.
        unsafe {
            let own = io_new();
            task::msrt_task_spawn(complete_local, own as *mut u8, task::SPAWN_DETACHED, 0);
            let at = wait_any_probe(&mut [own, *TARGET.ptr()], 1_000_000_000);
            msrt_promise_drop(own);
            let mut value = sched::current() as i64 * 100 + at + 1;
            msrt_promise_put(id_of(closure), (&raw mut value).cast(), &msrt_desc_int, 0);
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn mixed_wait_any_observes_local_completion_during_foreign_registration() {
        let _g = lock();
        let got = run_away(wait_any_completing_local, 3_600_000_000_000, 100);
        sched::shutdown();
        task::teardown();
        assert_eq!(got % 100, 1, "result {got}");
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn mixed_wait_any_runs_foreign_deferred_work() {
        let _g = lock();
        let got = run_away_with_target(wait_any_target, deferred_probe, 100);
        sched::shutdown();
        task::teardown();
        assert_eq!(got % 100, 11, "result {got}");
    }

    unsafe extern "C-unwind" fn wait_any_local_becomes_ready(closure: *mut Closure) {
        // SAFETY: the running task owns its local promises and output slot.
        unsafe {
            let own = io_new();
            let later = deferred_probe();
            let before = DEFERRED_CALLS.load(std::sync::atomic::Ordering::SeqCst);
            task::msrt_task_spawn(complete_local, own as *mut u8, task::SPAWN_DETACHED, 0);
            let at = wait_any_probe(&mut [own, *TARGET.ptr(), later], 1_000_000_000);
            let calls = DEFERRED_CALLS.load(std::sync::atomic::Ordering::SeqCst) - before;
            msrt_promise_drop(own);
            msrt_promise_drop(later);
            let mut value = sched::current() as i64 * 100 + (at + 1) * 10 + calls as i64;
            msrt_promise_put(id_of(closure), (&raw mut value).cast(), &msrt_desc_int, 0);
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn mixed_wait_any_rechecks_local_readiness_before_deferred_work() {
        let _g = lock();
        let got = run_away(wait_any_local_becomes_ready, 3_600_000_000_000, 100);
        sched::shutdown();
        task::teardown();
        assert_eq!(got % 100, 10, "result {got}");
    }

    unsafe extern "C-unwind" fn wait_any_inherited_deadline(closure: *mut Closure) {
        // SAFETY: the running task owns its local promise and output slot.
        unsafe {
            let own = msrt_promise_sleep(3_600_000_000_000);
            let inherited = crate::sys::monotonic_ns() + 500_000_000;
            let previous = task::set_defer_deadline(inherited);
            let at = wait_any_probe(&mut [own, *TARGET.ptr()], 1_000_000_000);
            task::set_defer_deadline(previous);
            let observed = DEFERRED_DEADLINE.load(std::sync::atomic::Ordering::SeqCst);
            msrt_promise_drop(own);
            let mut value =
                sched::current() as i64 * 100 + at * 10 + i64::from(observed == inherited);
            msrt_promise_put(id_of(closure), (&raw mut value).cast(), &msrt_desc_int, 0);
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn mixed_wait_any_passes_the_inherited_deadline_to_foreign_deferred_work() {
        let _g = lock();
        let got = run_away_with_target(wait_any_inherited_deadline, deferred_probe, 100);
        sched::shutdown();
        task::teardown();
        assert_eq!(got % 100, 11, "result {got}");
    }

    unsafe extern "C-unwind" fn wait_any_ready_local(closure: *mut Closure) {
        // SAFETY: the running task owns its local promise and output slot.
        unsafe {
            let own = msrt_promise_finished();
            let at = wait_any_probe(&mut [*TARGET.ptr(), own], 50_000_000);
            msrt_promise_drop(own);
            let mut value = sched::current() as i64 * 100 + at;
            msrt_promise_put(id_of(closure), (&raw mut value).cast(), &msrt_desc_int, 0);
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn mixed_wait_any_prefers_ready_inputs_to_foreign_deferred_work() {
        let _g = lock();
        DEFERRED_CALLS.store(0, std::sync::atomic::Ordering::SeqCst);
        let got = run_away_with_target(wait_any_ready_local, deferred_probe, 100);
        sched::shutdown();
        task::teardown();
        assert_eq!(got % 100, 1, "result {got}");
        assert_eq!(DEFERRED_CALLS.load(std::sync::atomic::Ordering::SeqCst), 0);
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_promise_of_another_thread_can_be_waited_and_taken() {
        let _g = lock();
        let got = run_away(wait_target, 60_000_000, 10);
        assert_eq!(got % 10, OK, "outcome {got}");
        sched::shutdown();
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn waiting_on_a_promise_of_another_thread_honors_the_timeout() {
        let _g = lock();
        let got = run_away(wait_target_briefly, 3_600_000_000_000, 10);
        assert_eq!(got % 10, TIMEOUT, "outcome {got}");
        sched::shutdown();
        task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn wait_any_over_promises_of_several_threads_finds_the_foreign_one() {
        let _g = lock();
        let got = run_away(wait_any_target, 60_000_000, 100);
        assert_eq!(got % 100, 11, "result {got}");
        sched::shutdown();
        task::teardown();
    }

    unsafe extern "C-unwind" fn duplicate_answer(_: *mut Closure) {
        // SAFETY: the test holds the runtime lock and hands over two live Int values.
        unsafe {
            let id = *ID.ptr();
            let mut first = 42i64;
            msrt_promise_put(id, (&raw mut first).cast(), &msrt_desc_int, 0);
            let mut second = 99i64;
            msrt_promise_put(id, (&raw mut second).cast(), &msrt_desc_int, 1);
        }
    }

    #[test]
    fn duplicate_completion_preserves_first_value() {
        let _g = lock();
        let previous = sched::msrt_runtime_limit();
        sched::msrt_runtime_set_threads(1);
        let id = msrt_promise_new();
        start(id, duplicate_answer);
        assert_eq!(msrt_promise_wait(id, -1), OK);
        let value = take_int(id);
        msrt_promise_drop(id);
        task::teardown();
        sched::msrt_runtime_set_threads(previous);
        assert_eq!(value, 42);
    }
}
