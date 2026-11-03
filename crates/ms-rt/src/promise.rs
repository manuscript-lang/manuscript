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
    /// The task running the promise (`promise(fn)`), or 0.
    task: Vec<u64>,
    /// The report of the fault that ended the promise.
    report: Vec<Vec<u8>>,
    /// When a timer promise or a readiness wait times out, or `i64::MAX`.
    deadline: Vec<i64>,
    /// The descriptor a readiness wait watches, or -1.
    fd: Vec<i32>,
    /// What a readiness wait asks for.
    events: Vec<u32>,
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
        task: Vec::new(),
        report: Vec::new(),
        deadline: Vec::new(),
        fd: Vec::new(),
        events: Vec::new(),
        timers: BinaryHeap::new(),
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
            t.task.push(0);
            t.report.push(Vec::new());
            t.deadline.push(i64::MAX);
            t.fd.push(-1);
            t.events.push(0);
            t.state.len() - 1
        }
    };
    t.generation[i] = t.generation[i].wrapping_add(1) & 0x3fff_ffff;
    if t.generation[i] == 0 {
        t.generation[i] = 1;
    }
    t.state[i] = State::Pending;
    t.token[i] = 0;
    t.result[i] = NO_RESULT;
    t.task[i] = 0;
    t.report[i] = Vec::new();
    t.deadline[i] = i64::MAX;
    t.fd[i] = -1;
    t.events[i] = 0;
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
    wake(t, i);
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
pub unsafe extern "C-unwind" fn msrt_promise_take(id: i64, d: *const TypeDesc, out: *mut u8) -> u8 {
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
        Some(i) => u8::from(t.state[i] != State::Pending),
        None => 1,
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
            put_int(t, i, i64::from(task::WAIT_TIMEOUT));
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
    let i = find(id);
    if table().task[i] != 0 {
        fault::fault(b"promise: already started");
    }
    // SAFETY: forwarded contract.
    let handle = unsafe { task::spawn_promise(work, id) };
    table().task[i] = handle;
}

/// The promise's task ended with `status` (0 returned, 1 fault, 2 cancelled): a promise that has
/// no result by now was ended by the fault or the cancellation.
pub(crate) fn ended(id: i64, status: u8, msg: &ms_rt_abi::StrVal, started: &[usize]) {
    let t = table();
    let Some(i) = index(t, id) else { return };
    if t.state[i] == State::Pending {
        match status {
            1 => {
                t.report[i] = fault::fault_report(msg, started);
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

/// Waits until `id` finishes or `timeout_ns` passes (negative: no limit) and returns an outcome
/// code. A timeout cancels the work, which stops at its next wait. If the waiting task itself is
/// cancelled, it unwinds; dropping the promise then cancels and joins the work.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_promise_wait(id: i64, timeout_ns: i64) -> i64 {
    let i = find(id);
    if let Some(code) = outcome(table().state[i]) {
        return code;
    }
    // SAFETY: single scheduler per isolate; the token is ours until freed.
    unsafe {
        let token = task::msrt_token_new(0);
        table().token[i] = token;
        let mut value = 0;
        let woke = task::msrt_token_park(token, timeout_ns, &mut value);
        // The table may have moved while parked: look the slot up again.
        let t = table();
        if let Some(i) = index(t, id)
            && t.token[i] == token
        {
            t.token[i] = 0;
        }
        task::msrt_token_free(token);
        let t = table();
        let Some(i) = index(t, id) else {
            return CLOSED;
        };
        if woke == task::WAIT_CANCELLED {
            fault::msrt_cancelled();
        }
        if woke == task::WAIT_TIMEOUT {
            if t.task[i] != 0 {
                task::msrt_task_cancel(t.task[i]);
            }
            return TIMEOUT;
        }
        outcome(t.state[i]).unwrap_or(FAILED)
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
    let handle = t.task[i];
    if handle != 0 {
        // SAFETY: the handle names the promise's task, collected exactly once, here.
        unsafe {
            if t.state[i] == State::Pending {
                task::msrt_task_cancel(handle);
            }
            task::collect(handle);
        }
    }
    let t = table();
    let Some(i) = index(t, id) else { return };
    release_result(t, i);
    t.task[i] = 0;
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
        assert_eq!(msrt_promise_done(id), 0);
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
}
