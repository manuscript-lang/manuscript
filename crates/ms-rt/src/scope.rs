//! Task scopes for the HTTP server's request tasks (`ms-std-net`): a scope owns the tasks started in it, so closing the
//! scope cancels and joins them. A task started with `spawn_native` may carry its own time limit.
//! Temporary: the server rebuilt on promises needs no scope, and this module goes with its last user.
use crate::task;
use std::collections::VecDeque;

struct Scope {
    /// Bumped each time the slot is reused, so an id from an earlier scope never matches.
    generation: i64,
    /// Handles of the tasks started in the scope and not yet collected by `msrt_scope_close`.
    tasks: VecDeque<u64>,
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
