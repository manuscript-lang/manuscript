//! Task scopes for `@std/tasks.ms`: a scope owns the tasks started in it, so a group can wait for
//! them, or cancel and collect them, with one call.
//!
//! A task started in a scope may carry its own time limit; the scope may carry one for every task,
//! counted from the scope's creation. A task ends as returned (0), timed out (1) or cancelled (2); a task that no longer exists reads as 3.
use crate::global::Global;
use crate::task;
use ms_rt_abi::Closure;

struct Scope {
    /// Bumped each time the slot is reused, so an id from an earlier scope never matches.
    generation: i64,
    /// Handles of the tasks started in the scope and not yet collected by `msrt_scope_close`.
    tasks: Vec<u64>,
    /// Monotonic time the scope was created at, in nanoseconds.
    created: i64,
}

static SCOPES: Global<Vec<Option<Scope>>> = Global::new(Vec::new());
/// The generation each slot last had, kept when its scope is closed.
static GENERATIONS: Global<Vec<i64>> = Global::new(Vec::new());

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
    find(id).map(|s| s.tasks.clone()).unwrap_or_default()
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
        tasks: Vec::new(),
        created: crate::sys::monotonic_ns(),
    };
    if slot == all.len() {
        all.push(Some(scope));
    } else {
        all[slot] = Some(scope);
    }
    generation << 32 | (slot as i64 + 1)
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
    let handle = unsafe { task::spawn_closure(closure, limit) };
    s.tasks.push(handle);
    handle as i64
}

/// Waits for one task and returns how it ended; the task stays joinable until `msrt_scope_close`
/// or a second call collects it.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_scope_join(handle: i64, keep: i64) -> i64 {
    // SAFETY: single threaded scheduler.
    i64::from(unsafe { task::join_closure(handle as u64, keep != 0) })
}

/// Waits for every task of the scope and returns the worst outcome: timed out, else cancelled,
/// else returned. The tasks stay joinable.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_scope_wait(scope: i64) -> i64 {
    if find(scope).is_none() {
        return 3;
    }
    let mut worst = 0;
    for handle in tasks_of(scope) {
        // SAFETY: single threaded scheduler.
        let outcome = unsafe { task::join_closure(handle, true) };
        worst = match (worst, outcome) {
            (_, 3) => worst,
            (1, _) | (_, 1) => 1,
            (_, o) => worst.max(o),
        };
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
        unsafe { task::join_closure(handle, false) };
    }
    if find(scope).is_some() {
        scopes()[((scope & 0xffff_ffff) - 1) as usize] = None;
    }
}
