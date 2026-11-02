//! Task scopes for `@std/tasks.ms`: a scope owns the tasks started in it, so a group can wait for
//! them, or cancel and collect them, with one call.
//!
//! A task started in a scope may carry its own time limit; the scope may carry one for every task,
//! counted from the scope's creation. A task ends as returned (0), timed out (1), cancelled (2) or faulted (4, only in a scope that contains faults); a task that no longer exists reads as 3.
use crate::task;
use ms_rt_abi::Closure;
use std::collections::VecDeque;

struct Scope {
    /// Bumped each time the slot is reused, so an id from an earlier scope never matches.
    generation: i64,
    /// Handles of the tasks started in the scope and not yet collected by `msrt_scope_close`.
    tasks: VecDeque<u64>,
    /// Monotonic time the scope was created at, in nanoseconds.
    created: i64,
    /// Whether a fault in a task of the scope is returned by join instead of ending the process.
    contain: bool,
}

crate::isolate_static! {
    static SCOPES: Vec<Option<Scope>> = Vec::new();
}
crate::isolate_static! {
    /// The generation each slot last had, kept when its scope is closed.
    static GENERATIONS: Vec<i64> = Vec::new();
}

fn scopes() -> &'static mut Vec<Option<Scope>> {
    // SAFETY: every task runs on the one runtime thread.
    unsafe { &mut *SCOPES.ptr() }
}

/// The live scope an id names. An id is `generation << 32 | slot + 1`.
fn find(id: i64) -> Option<&'static mut Scope> {
    let slot = usize::try_from((id & 0xffff_ffff) - 1).ok()?;
    let scope = scopes().get_mut(slot)?.as_mut()?;
    (scope.generation == id >> 32).then_some(scope)
}

fn tasks_of(id: i64) -> Vec<u64> {
    find(id)
        .map(|s| s.tasks.iter().copied().collect())
        .unwrap_or_default()
}

/// Releases this isolate's scope tables after the scheduler and its tasks have retired.
/// Runtime TLS has no destructor, so closing the groups alone leaves their table storage behind.
pub(crate) fn teardown() {
    // SAFETY: the scheduler's teardown runs on the isolate thread after its tasks are gone.
    unsafe {
        *SCOPES.ptr() = Vec::new();
        *GENERATIONS.ptr() = Vec::new();
    }
}

/// Creates a scope and returns its id.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_scope_new() -> i64 {
    let all = scopes();
    let slot = all.iter().position(Option::is_none).unwrap_or(all.len());
    // SAFETY: every task runs on the one runtime thread.
    let generations = unsafe { &mut *GENERATIONS.ptr() };
    if generations.len() <= slot {
        generations.resize(slot + 1, 0);
    }
    generations[slot] += 1;
    let generation = generations[slot];
    let scope = Scope {
        generation,
        tasks: VecDeque::new(),
        created: crate::sys::monotonic_ns(),
        contain: false,
    };
    if slot == all.len() {
        all.push(Some(scope));
    } else {
        all[slot] = Some(scope);
    }
    generation << 32 | (slot as i64 + 1)
}

/// Makes a fault in the scope's tasks end only that task: its join then reads as faulted (4).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_scope_contain(scope: i64) {
    if let Some(s) = find(scope) {
        s.contain = true;
    }
}

/// Takes the report of the fault the last join or wait of a scope returned as 4.
///
/// # Safety
/// `out` must be valid for writing a string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_scope_fault_message(out: *mut ms_rt_abi::StrVal) {
    let report = task::take_fault_report();
    // SAFETY: forwarded contract.
    unsafe { *out = crate::string::from_bytes(&report) };
}

/// Whether the running task was cancelled (its group closed, its time limit passed, or the program
/// was asked to stop). Unlike the cancel flag, it stays true inside cleanups.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_task_cancel_requested() -> i64 {
    i64::from(crate::fault::unshielded_cancel_flag() != 0)
}

/// Starts `closure` as a task of `scope`. A negative limit means none. `task_limit_ns` counts from
/// now and `scope_limit_ns` from the scope's creation; the task ends at the earlier one.
/// Returns the task handle, or -1 when the scope is closed.
///
/// # Safety
/// `closure` must be a live closure object.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_scope_spawn(
    scope: i64,
    closure: *mut Closure,
    task_limit_ns: i64,
    scope_limit_ns: i64,
) -> i64 {
    let now = crate::sys::monotonic_ns();
    let Some(s) = find(scope) else {
        // The group was closed: the handle -1 reads back as closed.
        return -1;
    };
    let mut limit = task_limit_ns;
    if scope_limit_ns >= 0 {
        let left = (s.created.saturating_add(scope_limit_ns) - now).max(0);
        limit = if limit < 0 { left } else { limit.min(left) };
    }
    // SAFETY: forwarded contract.
    let handle = unsafe { task::spawn_closure(closure, limit, !s.contain) };
    s.tasks.push_back(handle);
    handle as i64
}

/// Starts `entry(arg)` as a task of `scope` for a native caller (the HTTP server's requests). It
/// leaves the scope and frees itself when it ends, so a scope can serve unboundedly many; the
/// scope's close still cancels and joins the ones running. `limit_ns` counts from now (negative:
/// none). Returns the task handle, or `None` when the scope is closed.
///
/// # Safety
/// `arg` must be valid for `entry`, which owns it.
pub unsafe fn spawn_native(
    scope: i64,
    entry: unsafe extern "C-unwind" fn(*mut u8),
    arg: *mut u8,
    limit_ns: i64,
) -> Option<u64> {
    let s = find(scope)?;
    // SAFETY: forwarded contract.
    let handle = unsafe { task::spawn_scoped(entry, arg, limit_ns, scope) };
    s.tasks.push_back(handle);
    Some(handle)
}

/// Changes the running task's time limit: cancelled `limit_ns` from now, never when negative.
pub fn limit_current(limit_ns: i64) {
    task::limit_current(limit_ns)
}

/// Forgets a cancel aimed at the running task, for a task that caught it with a guard and goes on.
/// A stop request (SIGINT/SIGTERM) is not affected.
pub fn acknowledge_cancel() {
    crate::fault::set_live_task_cancel(0)
}

/// The scope the running task was started in by [`spawn_native`], or 0.
pub fn current() -> i64 {
    task::current_scope()
}

/// Called when a task started by [`spawn_native`] ends: the scope forgets it.
pub(crate) fn task_ended(scope: i64, handle: u64) {
    if let Some(s) = find(scope)
        && let Some(at) = s.tasks.iter().position(|&h| h == handle)
    {
        s.tasks.remove(at);
    }
}

/// Called by a task's closure once its cleanup is registered: a task cancelled before it first ran
/// unwinds here, so its work never starts but its cleanup runs.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_scope_started() {
    // SAFETY: single threaded scheduler.
    unsafe { task::unwind_if_cancelled() }
}

/// Waits for one task of `scope` and returns how it ended. Without `keep` the task is collected:
/// the scope forgets it and it reads as gone afterwards.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_scope_join(scope: i64, handle: i64, keep: i64) -> i64 {
    // SAFETY: single threaded scheduler.
    let outcome = i64::from(unsafe { task::join_closure(handle as u64, keep != 0) });
    if keep == 0
        && let Some(s) = find(scope)
        && let Some(at) = s.tasks.iter().position(|&h| h == handle as u64)
    {
        s.tasks.remove(at);
    }
    outcome
}

/// Waits for every task of the scope and returns the worst outcome: timed out, else cancelled,
/// else returned. The tasks stay joinable.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_scope_wait(scope: i64) -> i64 {
    if find(scope).is_none() {
        return 3;
    }
    let mut worst = 0;
    let mut first_fault = None;
    for handle in tasks_of(scope) {
        // SAFETY: single threaded scheduler.
        let outcome = unsafe { task::join_closure(handle, true) };
        if outcome == 4 {
            // A later join may switch to another scope's waiter. Keep our report on this
            // stack until all our tasks have ended, rather than in the shared delivery slot.
            let report = task::take_fault_report();
            first_fault.get_or_insert(report);
        }
        worst = match (worst, outcome) {
            (_, 3) => worst,
            (4, _) => 4,
            (_, 4) => 4,
            (1, _) | (_, 1) => 1,
            (_, o) => worst.max(o),
        };
    }
    if let Some(report) = first_fault {
        task::set_fault_report(report);
    }
    i64::from(worst)
}

/// Cancels the scope's tasks, waits for them, and releases the scope. Safe to call again.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_scope_close(scope: i64) {
    let handles = tasks_of(scope);
    for handle in &handles {
        // SAFETY: single threaded scheduler.
        unsafe { task::cancel_closure(*handle) };
    }
    for handle in handles {
        // SAFETY: single threaded scheduler.
        if unsafe { task::join_closure(handle, false) } == 4 {
            // Close discards uncollected faults instead of publishing them to a later wait.
            task::take_fault_report();
        }
    }
    if find(scope).is_some() {
        scopes()[((scope & 0xffff_ffff) - 1) as usize] = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::lock;

    unsafe extern "C-unwind" fn first_fault(_: *mut Closure) {
        crate::fault::fault(b"first scope fault");
    }

    unsafe extern "C-unwind" fn second_fault(_: *mut Closure) {
        crate::fault::fault(b"second scope fault");
    }

    unsafe extern "C" fn drop_closure(obj: *mut ms_rt_abi::Obj) {
        // SAFETY: the test closure has no captures and owns this allocation.
        unsafe { crate::alloc::free(obj.cast()) };
    }

    fn spawn_entry(scope: i64, code: unsafe extern "C-unwind" fn(*mut Closure)) {
        // SAFETY: the scope retains the capture-free closure until the task ends.
        unsafe {
            let closure = crate::obj::new_obj(size_of::<Closure>(), drop_closure).cast::<Closure>();
            (*closure).code = code as *const u8;
            assert!(msrt_scope_spawn(scope, closure, -1, -1) > 0);
            crate::obj::release(closure.cast());
        }
    }

    #[test]
    fn a_closed_scopes_fault_does_not_replace_a_later_wait_report() {
        let _g = lock();
        task::teardown();
        let first = msrt_scope_new();
        msrt_scope_contain(first);
        spawn_entry(first, first_fault);
        assert_eq!(msrt_scope_wait(first), 4);
        assert_eq!(task::take_fault_report(), b"first scope fault");
        // Closing collects the uncollected fault; its discarded report must not escape.
        msrt_scope_close(first);
        assert!(task::take_fault_report().is_empty());

        let second = msrt_scope_new();
        msrt_scope_contain(second);
        spawn_entry(second, second_fault);
        assert_eq!(msrt_scope_wait(second), 4);
        let report = task::take_fault_report();
        msrt_scope_close(second);
        task::teardown();
        assert_eq!(report, b"second scope fault");
    }

    static OTHER_SCOPE: crate::global::Process<i64> = crate::global::Process::new(0);
    static OTHER_REPORT: crate::global::Process<Vec<u8>> = crate::global::Process::new(Vec::new());

    unsafe extern "C-unwind" fn wait_other_scope(_: *mut Closure) {
        // SAFETY: the test holds the runtime lock and keeps the other scope open.
        unsafe {
            assert_eq!(msrt_scope_wait(*OTHER_SCOPE.ptr()), 4);
            *OTHER_REPORT.ptr() = task::take_fault_report();
        }
    }

    #[test]
    fn interleaved_scope_waits_keep_their_own_first_fault() {
        let _g = lock();
        task::teardown();
        let first = msrt_scope_new();
        let second = msrt_scope_new();
        msrt_scope_contain(first);
        msrt_scope_contain(second);
        // The first wait sees its first fault, then switches to a task waiting on the other scope.
        spawn_entry(first, first_fault);
        spawn_entry(first, wait_other_scope);
        spawn_entry(second, second_fault);
        // SAFETY: tests hold the runtime lock; the nested waiter runs before these scopes close.
        unsafe { *OTHER_SCOPE.ptr() = second };
        assert_eq!(msrt_scope_wait(first), 4);
        let first_report = task::take_fault_report();
        // SAFETY: the nested waiter has finished, under the runtime lock.
        let second_report = unsafe { core::mem::take(&mut *OTHER_REPORT.ptr()) };
        msrt_scope_close(first);
        msrt_scope_close(second);
        task::teardown();
        assert_eq!(first_report, b"first scope fault");
        assert_eq!(second_report, b"second scope fault");
    }

    unsafe extern "C-unwind" fn nap(arg: *mut u8) {
        // SAFETY: called from a running task.
        unsafe { task::msrt_task_sleep(arg as usize as i64 * 1_000_000) };
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn native_tasks_leave_the_scope_and_close_cancels_the_rest() {
        let _g = lock();
        let scope = msrt_scope_new();
        // SAFETY: `nap` takes no ownership of its argument.
        unsafe {
            for _ in 0..8 {
                spawn_native(scope, nap, std::ptr::dangling_mut::<u8>(), -1).unwrap();
            }
            // Cancelled by its own limit long before its hour is up.
            spawn_native(scope, nap, 3_600_000usize as *mut u8, 5_000_000).unwrap();
            let long = spawn_native(scope, nap, 3_600_000usize as *mut u8, -1).unwrap();
            assert_eq!(tasks_of(scope).len(), 10);
            while tasks_of(scope).len() > 1 {
                task::msrt_task_sleep(2_000_000);
            }
            assert_eq!(tasks_of(scope), vec![long]);
        }
        msrt_scope_close(scope);
        assert!(find(scope).is_none());
        assert!(spawn_native_closed(scope).is_none());
        task::teardown();
    }

    fn spawn_native_closed(scope: i64) -> Option<u64> {
        // SAFETY: `nap` takes no ownership of its argument.
        unsafe { spawn_native(scope, nap, std::ptr::dangling_mut::<u8>(), -1) }
    }
}
