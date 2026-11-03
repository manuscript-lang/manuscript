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
use crate::desc::slot_drop;
use crate::sched::{self, Event, Start};
use crate::{alloc, fault, task};
use core::cmp::Reverse;
use ms_rt_abi::TypeDesc;
use std::collections::BinaryHeap;

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
const DEFERRED: u8 = 4;

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
    /// `WANT_CANCEL`: cancel the work as soon as it has started.
    flags: Vec<u8>,
    /// The report of the fault that ended the promise.
    report: Vec<Vec<u8>>,
    /// When a timer promise or a readiness wait times out, or `i64::MAX`.
    deadline: Vec<i64>,
    /// The descriptor a readiness wait watches, or -1.
    fd: Vec<i32>,
    /// What a readiness wait asks for.
    events: Vec<u32>,
    /// The native continuation of an I/O promise (`io_on_ready`) and its state word.
    retry: Vec<Option<Retry>>,
    retry_state: Vec<usize>,
    /// (deadline, id) of the timers armed; an entry whose promise is gone or finished is stale.
    timers: BinaryHeap<Reverse<(i64, i64)>>,
    free: Vec<usize>,
}

crate::isolate_static! {
    static TABLE: Table = Table {
        state: Vec::new(),
        generation: Vec::new(),
        token: Vec::new(),
        result: Vec::new(),
        closure: Vec::new(),
        thread: Vec::new(),
        flags: Vec::new(),
        report: Vec::new(),
        deadline: Vec::new(),
        fd: Vec::new(),
        events: Vec::new(),
        retry: Vec::new(),
        retry_state: Vec::new(),
        timers: BinaryHeap::new(),
        free: Vec::new(),
    };
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
            t.flags.push(0);
            t.report.push(Vec::new());
            t.deadline.push(i64::MAX);
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
    t.flags[i] = 0;
    t.report[i] = Vec::new();
    t.deadline[i] = i64::MAX;
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
        apply(event);
    }
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
        Event::Started { id, thread } => {
            let t = table();
            let Some(i) = index(t, id) else { return };
            t.thread[i] = thread;
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
                Some(i) if t.state[i] == State::Pending => {
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
                // SAFETY: the reference taken at start; the task is over, so this is its last use.
                unsafe { crate::obj::release(closure as *mut ms_rt_abi::Obj) };
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
                    _ => {
                        t.report[i] = b"promise: the work ended without a result".to_vec();
                        t.state[i] = State::Failed;
                    }
                }
            }
            wake(t, i);
        }
        Event::Cancel { id } => {
            task::cancel_promise_task(id);
        }
    }
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
        if thread == sched::current() {
            apply(Event::Cancel { id });
        } else {
            sched::post(thread, Event::Cancel { id });
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
    unsafe { task::spawn_promise_task(start.closure as *mut ms_rt_abi::Closure, start.id) };
    deliver(
        start.id,
        Event::Started {
            id: start.id,
            thread: sched::current() as u8,
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
    sched::live_add(-1);
    deliver(id, Event::Ended { id, status, report });
}

/// Wakes the task waiting on slot `i`, if any.
fn wake(t: &mut Table, i: usize) {
    let token = core::mem::take(&mut t.token[i]);
    if token != 0 {
        // SAFETY: the waiter owns the token until it is woken or leaves.
        unsafe { task::msrt_token_post(token, 1) };
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
    let t = table();
    let Some(i) = index(t, id) else { return 0 };
    let r = core::mem::replace(&mut t.result[i], NO_RESULT);
    if r.ptr.is_null() {
        return 0;
    }
    // SAFETY: forwarded contract; the stored value is owned and moves out.
    unsafe {
        core::ptr::copy_nonoverlapping(r.ptr, out, (*d).size as usize);
        alloc::free(r.ptr);
    }
    t.state[i] = State::Taken;
    1
}

/// Whether `id` has finished (any outcome). A closed id reads as done.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_done(id: i64) -> u8 {
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

/// Completes `i` with no value (a finished sleep): `wait` answers 0 and nothing is left to take.
fn complete_unit(t: &mut Table, i: usize) {
    if t.state[i] == State::Pending {
        t.state[i] = State::Ok;
        wake(t, i);
    }
}

/// A promise that finishes after `ns` nanoseconds; it has no task and no result to take.
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

/// The earliest deadline of a live timer, dropping stale entries on the way.
pub(crate) fn next_deadline() -> Option<i64> {
    let t = table();
    while let Some(&Reverse((deadline, id))) = t.timers.peek() {
        if let Some(i) = index(t, id)
            && t.state[i] == State::Pending
            && t.deadline[i] == deadline
        {
            return Some(deadline);
        }
        t.timers.pop();
    }
    None
}

/// Whether any timer entry exists (live or stale).
pub(crate) fn has_timers() -> bool {
    !table().timers.is_empty()
}

/// Starts `work` as the task of promise `id`, on the thread the runtime picks. The closure
/// completes the promise itself with `msrt_promise_put`. A fault in it ends only this promise.
///
/// # Safety
/// `work` is a live closure object.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_start(id: i64, work: *mut ms_rt_abi::Closure) {
    // SAFETY: forwarded contract.
    unsafe { start_on(id, work, false) }
}

/// Starts `work` as the task of promise `id`, on this thread when `here` or when a live native
/// stream is pinned to it, else where the runtime picks.
///
/// # Safety
/// `work` is a live closure object.
unsafe fn start_on(id: i64, work: *mut ms_rt_abi::Closure, here: bool) {
    let i = find(id);
    let t = table();
    if t.closure[i] != 0 || t.thread[i] != NOT_STARTED {
        fault::fault(b"promise: already started");
    }
    // SAFETY: forwarded contract. The promise keeps a reference to the closure until the task has
    // ended, so no other thread ever changes its count.
    unsafe { crate::obj::msrt_retain(work.cast()) };
    t.closure[i] = work as usize;
    let start = Start {
        id,
        closure: work as usize,
    };
    if here || sched::current() == sched::NONE || sched::pinned_here() {
        execute(start);
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
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_defer(id: i64, work: *mut ms_rt_abi::Closure) {
    let i = find(id);
    let t = table();
    // SAFETY: the promise holds a reference until the work runs or the promise is dropped.
    unsafe { crate::obj::msrt_retain(work.cast()) };
    t.flags[i] |= DEFERRED;
    t.retry_state[i] = work as usize;
}

/// Runs the deferred work of `id` if it has not run: the caller is the waiter.
fn run_deferred(id: i64, deadline: Option<i64>) {
    let t = table();
    let Some(i) = index(t, id) else { return };
    if t.flags[i] & DEFERRED == 0 {
        return;
    }
    t.flags[i] &= !DEFERRED;
    let closure = core::mem::take(&mut t.retry_state[i]) as *mut ms_rt_abi::Closure;
    // Waits inside the work stop at the waiter's deadline: the work runs on this stack, so only
    // its own waits can notice the limit.
    let earlier =
        task::set_defer_deadline(deadline.map_or(i64::MAX, |d| d.min(task::defer_deadline())));
    // The reference is released when the work ends, and by the cleanup when a cancelled wait inside the
    // work jumps out of it, which skips Rust destructors.
    let release = || {
        // SAFETY: the reference taken in `msrt_promise_defer` is ours, released once.
        unsafe { crate::obj::release(closure.cast()) };
    };
    // SAFETY: the code is the closure's entry.
    fault::with_cleanup(&mut || release(), || unsafe {
        let code: unsafe extern "C-unwind" fn(*mut ms_rt_abi::Closure) =
            core::mem::transmute((*closure).code);
        code(closure);
    });
    release();
    task::set_defer_deadline(earlier);
}

/// A closure that calls a native entry with the argument it owns.
#[repr(C)]
struct Native {
    closure: ms_rt_abi::Closure,
    entry: unsafe extern "C-unwind" fn(*mut u8),
    arg: *mut u8,
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
    // SAFETY: a fresh object with no captures to drop; the promise retains it for the task.
    unsafe {
        let n = crate::obj::new_obj(size_of::<Native>(), native_drop).cast::<Native>();
        (*n).closure.code = native_code as *const u8;
        (*n).entry = entry;
        (*n).arg = arg;
        start_on(id, n.cast(), true);
        crate::obj::release(n.cast());
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

fn outcome(state: State) -> Option<i64> {
    match state {
        State::Ok => Some(OK),
        State::Error => Some(ERROR),
        State::Failed => Some(FAILED),
        State::Cancelled => Some(CANCELLED),
        State::Taken => Some(CLOSED),
        State::Pending | State::Free => None,
    }
}

/// Parks until promise `id` changes (an event, a completion, a timeout, a cancellation) and
/// returns how the park ended. The slot is looked up again afterwards, so the caller does too.
fn park_on(id: i64, timeout_ns: i64) -> u32 {
    let t = table();
    let Some(i) = index(t, id) else {
        return 0;
    };
    // The work may finish on another thread, so the scheduler must not call this a deadlock.
    let flags = if t.closure[i] != 0 || t.flags[i] & REMOTE_WAKE != 0 {
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
    let own = (timeout_ns >= 0).then(|| crate::sys::monotonic_ns().saturating_add(timeout_ns));
    // A wait inside deferred work also stops at the outer waiter's deadline.
    let inherited = task::defer_deadline();
    let deadline = match (own, inherited) {
        (o, i64::MAX) => o,
        (Some(o), i) => Some(o.min(i)),
        (None, i) => Some(i),
    };
    run_deferred(id, deadline);
    loop {
        let t = table();
        let i = find(id);
        if let Some(code) = outcome(t.state[i]) {
            return code;
        }
        let remaining = deadline.map_or(-1, |d| (d - crate::sys::monotonic_ns()).max(0));
        let woke = park_on(id, remaining);
        if woke == task::WAIT_CANCELLED {
            fault::msrt_cancelled();
        }
        let t = table();
        let Some(i) = index(t, id) else {
            return CLOSED;
        };
        if let Some(code) = outcome(t.state[i]) {
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
    let first_done = |list: &[i64]| {
        let t = table();
        list.iter()
            .position(|&id| index(t, id).is_none_or(|i| t.state[i] != State::Pending))
    };
    let deadline = (timeout_ns >= 0).then(|| crate::sys::monotonic_ns().saturating_add(timeout_ns));
    for &id in &list {
        run_deferred(id, deadline);
        if first_done(&list).is_some() {
            break;
        }
    }
    loop {
        if let Some(at) = first_done(&list) {
            return at as i64;
        }
        // SAFETY: single scheduler per isolate; the token is ours until freed.
        unsafe {
            let remote = list.iter().any(|&id| {
                index(table(), id)
                    .is_some_and(|i| table().closure[i] != 0 || table().flags[i] & REMOTE_WAKE != 0)
            });
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

/// The report of a fault that ended `id` (empty otherwise).
///
/// # Safety
/// `out` is writable memory for a string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_fault_report(id: i64, out: *mut ms_rt_abi::StrVal) {
    let t = table();
    let report = index(t, id).map(|i| t.report[i].as_slice()).unwrap_or(&[]);
    // SAFETY: `out` is uninitialised memory for a string.
    unsafe { *out = crate::string::from_bytes(report) };
}

/// Drops `id`: an unfinished promise is cancelled and joined first, then its slot and any
/// result not taken are released. An id that no longer exists does nothing.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_drop(id: i64) {
    let t = table();
    let Some(i) = index(t, id) else { return };
    if t.fd[i] >= 0 && t.state[i] == State::Pending {
        // SAFETY: single scheduler per isolate.
        unsafe { task::unwatch_fd_for_promise(t.fd[i], id) };
        t.fd[i] = -1;
    }
    if t.flags[i] & DEFERRED != 0 {
        t.flags[i] &= !DEFERRED;
        let closure = core::mem::take(&mut t.retry_state[i]);
        // SAFETY: the reference taken in `msrt_promise_defer`, never used.
        unsafe { crate::obj::release(closure as *mut ms_rt_abi::Obj) };
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
    t.state[i] = State::Free;
    t.free.push(i);
}

#[cfg(test)]
mod tests {
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
        // SAFETY: the task retains the capture-free closure until it ends.
        unsafe {
            *ID.ptr() = id;
            let closure = crate::obj::new_obj(size_of::<Closure>(), drop_closure).cast::<Closure>();
            (*closure).code = code as *const u8;
            msrt_promise_start(id, closure);
            crate::obj::release(closure.cast());
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

    // Closures that carry the id of their promise after the header.
    fn start_with_id(id: i64, code: unsafe extern "C-unwind" fn(*mut Closure)) {
        // SAFETY: the promise keeps a reference to the closure until its task has ended.
        unsafe {
            let size = size_of::<Closure>() + 8;
            let closure = crate::obj::new_obj(size, drop_closure).cast::<Closure>();
            (*closure).code = code as *const u8;
            closure.add(1).cast::<i64>().write(id);
            msrt_promise_start(id, closure);
            crate::obj::release(closure.cast());
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
}
