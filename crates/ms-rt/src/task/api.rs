//! Switching between tasks, the exported task API and closure tasks.
//! ms: domain task

use super::*;

// ---- switching ----

pub(super) unsafe fn after_switch() {
    // SAFETY: running on a live task's stack.
    unsafe { reap() };
}

/// Task switches between non-blocking descriptor polls.
const POLL_EVERY: u32 = 32;

/// Runs the next runnable task; returns when the calling task is scheduled again.
/// The caller has already set its state (Ready and queued, Waiting, or Done).
pub(super) unsafe fn switch_away() {
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
        // A poll is a system call, so a busy queue polls once per POLL_EVERY switches (a server
        // handling a batch of requests would otherwise poll once per request); an empty queue
        // blocks in `reactor_wait`, which polls.
        s.switches_since_poll += 1;
        if s.fd_waiting != 0 && s.switches_since_poll >= POLL_EVERY {
            s.switches_since_poll = 0;
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
pub(super) extern "C" fn task_main() -> ! {
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
        let ctx = Ctx::new(lo, hi);
        let t = match sched().spares.pop() {
            Some(spares) => new_task(ctx.with_spares(spares)),
            None => new_task(ctx),
        };
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
        (*t).capture = capture();
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
        if cancel_flag().load(Ordering::Relaxed) != 0 || super::sweep::cancel_here() {
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
pub(super) unsafe fn rearm(fd: i32) {
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
pub(super) unsafe fn set_deadline(cur: *mut Task, timeout_ns: i64) {
    let mut s = sched();
    // SAFETY: `cur` is the running task; slots hold live records or null.
    unsafe {
        (*cur).deadline = NO_DEADLINE;
        let mut timeout_ns = timeout_ns;
        if (*cur).read_limit != NO_DEADLINE {
            // A bounded read: no park outlasts the limit, so the caller sees a timeout.
            let left = ((*cur).read_limit - clock_ns()).max(0);
            timeout_ns = if timeout_ns < 0 {
                left
            } else {
                timeout_ns.min(left)
            };
        }
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

/// Bounds every park of the running task until `msrt_task_read_limit_restore`: from now, no wait
/// lasts past `timeout_ns` nanoseconds in all, and one that reaches it reports a timeout. A bound
/// already in force stays when it ends sooner, so nested reads cannot outlast the outer one.
/// Returns the previous limit for `msrt_task_read_limit_restore`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_read_limit(timeout_ns: i64) -> i64 {
    // SAFETY: single threaded scheduler; the running task's record is live.
    unsafe {
        let task = ensure_init();
        let previous = (*task).read_limit;
        (*task).read_limit = clock_ns().saturating_add(timeout_ns.max(0)).min(previous);
        previous
    }
}

/// Puts back the limit `msrt_task_read_limit` returned (`i64::MAX` is no bound).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_read_limit_restore(previous: i64) {
    // SAFETY: single threaded scheduler; the running task's record is live.
    unsafe {
        (*ensure_init()).read_limit = previous;
    }
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

/// Whether no other task could run while the current one blocks its thread: each is parked on a
/// token with no deadline and not on a descriptor, and the token is posted only from this thread
/// (a join of a local task), so nothing can wake it before the call returns. A program that
/// waits for one local task at a time is in this state, and a blocking call then gains nothing
/// from a pool thread. A task parked on a token another thread may post is not stalled: an
/// inline call would delay that wake-up by the length of the call. Answers false past a handful
/// of tasks, so the check stays a few loads.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_task_others_stalled() -> bool {
    const LOOK: usize = 4;
    // SAFETY: single threaded scheduler.
    unsafe {
        let cur = ensure_init();
        let mut s = sched();
        if s.live - s.waiting_roots > LOOK {
            return false;
        }
        for i in 0..s.slots.len() {
            let t = s.slots[i].task;
            if t.is_null() || t == cur {
                continue;
            }
            let t = &*t;
            let stalled = match t.state {
                State::Done => true,
                State::Waiting => {
                    // A token another thread may post (a pool job, a promise completed
                    // elsewhere) could wake the task while this thread is blocked, so only a
                    // token posted from this thread counts.
                    t.wait_token != 0
                        && t.deadline == NO_DEADLINE
                        && t.kill_at == NO_DEADLINE
                        && token_mut(&mut s, t.wait_token).is_some_and(|k| !k.remote)
                }
                _ => false,
            };
            if !stalled {
                return false;
            }
        }
        true
    }
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
pub(super) unsafe fn join(handle: u64, msg_out: *mut StrVal, keep: bool) -> u8 {
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
pub(crate) unsafe extern "C-unwind" fn closure_entry(arg: *mut u8) {
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
pub(super) unsafe fn arm_kill(h: u64, limit_ns: i64) {
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
pub(crate) unsafe fn spawn_promise_task(
    closure: *mut ms_rt_abi::Closure,
    promise: i64,
    capture: u64,
) -> u64 {
    // SAFETY: single threaded scheduler; forwarded contract.
    unsafe {
        let h = msrt_task_spawn(closure_entry, closure.cast(), 0, 0);
        let t = lookup(h);
        (*t).promise = promise;
        (*t).capture = capture;
        if !crate::promise::is_native_work(closure) {
            (*t).started_by = fault::capture_frames();
        }
        h
    }
}

/// The output capture of the running task, or 0 (also on a thread with no task yet).
pub(crate) fn capture() -> u64 {
    let s = sched();
    if s.cur.is_null() {
        return 0;
    }
    // SAFETY: the running task's record is live.
    unsafe { (*s.cur).capture }
}

/// Sets the running task's output capture.
pub(crate) fn set_capture(capture: u64) {
    // SAFETY: single threaded scheduler; the running task's record is live.
    unsafe { (*ensure_init()).capture = capture };
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
