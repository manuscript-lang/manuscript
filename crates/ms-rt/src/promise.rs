//! Promise slots for `@std/concurrency/promise.ms`.
//!
//! A promise is one entry of a flat per-isolate table, named by an id `(generation << 32) | (index + 1)`;
//! a stale id never matches. The columns are separate arrays (state, generation, park token, result
//! slot), so the scheduler touches only what it needs. An I/O promise has no task or stack: the
//! operation tries its system call at once and registers with the poller only when it would block.
//! Only `promise(fn)` runs a task.
//!
//! Outcome codes returned by [`msrt_promise_wait`]:
//! `0` ok (the result is in the slot), `1` the operation's own error (the error value is in the slot),
//! `2` timed out, `3` cancelled, `4` closed (the result was already taken), `5` failed (a fault inside).
use crate::desc::slot_drop;
use crate::{alloc, fault};
use ms_rt_abi::TypeDesc;

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
    free: Vec<usize>,
}

crate::isolate_static! {
    static TABLE: Table = Table {
        state: Vec::new(),
        generation: Vec::new(),
        token: Vec::new(),
        result: Vec::new(),
        free: Vec::new(),
    };
}

fn table() -> &'static mut Table {
    // SAFETY: the table belongs to the calling isolate.
    unsafe { &mut *TABLE.ptr() }
}

fn index(t: &Table, id: i64) -> Option<usize> {
    let i = usize::try_from((id & 0xffff_ffff) - 1).ok()?;
    (*t.generation.get(i)? == (id >> 32) as u32 && t.state[i] != State::Free).then_some(i)
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
            t.state.len() - 1
        }
    };
    t.generation[i] = t.generation[i].wrapping_add(1).max(1);
    t.state[i] = State::Pending;
    t.token[i] = 0;
    t.result[i] = NO_RESULT;
    (i64::from(t.generation[i]) << 32) | (i as i64 + 1)
}

/// Completes `id` with the value in `value`, which moves into the promise: `failed` 0 for the
/// result, 1 for the operation's error value. A promise completes once; later calls drop the value.
///
/// # Safety
/// `value` holds an owned value of `d`, which the callee takes.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_put(
    id: i64,
    value: *mut u8,
    d: *const TypeDesc,
    failed: i64,
) {
    let t = table();
    let Some(i) = index(t, id) else {
        // SAFETY: forwarded contract; the promise is gone, so the value has no owner.
        unsafe { slot_drop(&*d, value) };
        return;
    };
    if t.state[i] != State::Pending {
        // SAFETY: as above.
        unsafe { slot_drop(&*d, value) };
        return;
    }
    // SAFETY: forwarded contract.
    unsafe {
        let dd = &*d;
        let ptr = alloc::alloc((dd.size as usize).max(1));
        core::ptr::copy_nonoverlapping(value, ptr, dd.size as usize);
        t.result[i] = Result { ptr, desc: d };
    }
    t.state[i] = if failed == 0 { State::Ok } else { State::Error };
}

/// Moves the result of a promise whose `wait` returned 0 or 1 into `out`; the promise reads as closed afterwards.
///
/// # Safety
/// `out` is writable memory for a value of `d`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_take(id: i64, d: *const TypeDesc, out: *mut u8) {
    let t = table();
    let i = find(id);
    let r = core::mem::replace(&mut t.result[i], NO_RESULT);
    if r.ptr.is_null() {
        fault::fault(b"promise: the result is not available");
    }
    // SAFETY: forwarded contract; the stored value is owned and moves out.
    unsafe {
        core::ptr::copy_nonoverlapping(r.ptr, out, (*d).size as usize);
        alloc::free(r.ptr);
    }
    t.state[i] = State::Taken;
}

/// Whether `id` has finished (any outcome). A closed id reads as done.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_done(id: i64) -> u8 {
    let t = table();
    match index(t, id) {
        Some(i) => u8::from(t.state[i] != State::Pending),
        None => 1,
    }
}

/// Starts `work` as the task of promise `id`, on the thread the runtime picks. The closure
/// completes the promise itself with `msrt_promise_put`. Stub: not yet scheduled.
///
/// # Safety
/// `work` is a live closure object.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_promise_start(_id: i64, _work: *mut ms_rt_abi::Closure) {
    fault::fault(b"promise: start is not implemented yet");
}

/// Waits until `id` finishes or `timeout_ns` passes (negative: no limit) and returns an outcome
/// code. A timeout cancels the work. Stub: only finished promises can be waited on.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_wait(id: i64, timeout_ns: i64) -> i64 {
    let _ = timeout_ns;
    let t = table();
    let i = find(id);
    match t.state[i] {
        State::Ok => OK,
        State::Error => ERROR,
        State::Failed => FAILED,
        State::Cancelled => CANCELLED,
        State::Taken => CLOSED,
        State::Pending | State::Free => fault::fault(b"promise: wait is not implemented yet"),
    }
}

/// The report of a fault that ended `id` (empty otherwise).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_fault_report(_id: i64, out: *mut ms_rt_abi::StrVal) {
    // SAFETY: `out` is uninitialised memory for a string.
    unsafe { *out = crate::string::NO_STR };
}

/// Drops `id`: an unfinished promise is cancelled and joined first, then its slot and any
/// result not taken are released. An id that no longer exists does nothing.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_drop(id: i64) {
    let t = table();
    let Some(i) = index(t, id) else { return };
    release_result(t, i);
    t.state[i] = State::Free;
    t.free.push(i);
}
