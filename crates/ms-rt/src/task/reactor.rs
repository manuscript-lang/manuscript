//! The reactor: the poller thread, timers and wakeups.

use super::*;

// ---- reactor ----

pub use crate::poller::kick;

/// Opens the poller if no wait has yet (the Windows pipe registry lives in it).
#[cfg(windows)]
pub(crate) fn ensure_poller() {
    // SAFETY: single threaded scheduler.
    unsafe { poller_fd() };
}

pub(super) unsafe fn poller_fd() -> i32 {
    let mut s = sched();
    if s.epfd < 0 {
        // SAFETY: creates the poller descriptors.
        s.epfd = unsafe { crate::poller::create() };
    }
    s.epfd
}

/// Marks `t` runnable with the given park result.
pub(super) unsafe fn wake(t: *mut Task, result: u32) {
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
pub(super) unsafe fn expire_kills(now: i64) {
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
pub(super) unsafe fn expire_timers(now: i64) {
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
pub(super) unsafe fn stop_shielded(t: *mut Task) -> bool {
    // SAFETY: `t` is a live record; the running task's state is in the live globals.
    unsafe {
        if t == sched().cur {
            (*fault::cur_hdr()).stop_shield.load(Ordering::Relaxed) > 0
        } else {
            (*t).ctx.stop_shielded()
        }
    }
}

pub(super) unsafe fn shielded(t: *mut Task) -> bool {
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
pub(super) unsafe fn cancel_all_waiters() -> bool {
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
pub(super) unsafe fn poll_ready(timeout_ns: i64) {
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
pub(super) unsafe fn abandon_wait() {
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

pub(super) const CROSS_ISOLATE_DEADLOCK: &[u8] = b"deadlock: every isolate is waiting on another (a worker channel or worker result) and nothing can wake them";

/// Blocks until at least one task is runnable.
pub(super) unsafe fn reactor_wait() {
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
            let steal = crate::sched::steal_wait_ns();
            if steal >= 0 {
                timeout_ns = if timeout_ns < 0 {
                    steal
                } else {
                    timeout_ns.min(steal)
                };
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
            if crate::promise::rescue_ends() {
                continue;
            }
            crate::sched::set_idle(true);
            spin_for_work();
            // Posters interrupt the poller only while this says it may block, so look for work
            // once more after saying so.
            crate::isolate::set_sleeping(true);
            if crate::sched::work_available()
                || crate::sched::signalled()
                || crate::isolate::has_posts()
                || crate::isolate::pending_cancel() != 0
            {
                crate::isolate::set_sleeping(false);
                crate::sched::set_idle(false);
                continue;
            }
            trim_idle_stacks();
            hibernate_idle();
            // Output buffered for a pipe or file must be visible before the program blocks.
            crate::io::flush_stdout();
            poll_ready(timeout_ns);
            crate::isolate::set_sleeping(false);
            crate::sched::set_idle(false);
            if parked && crate::isolate::leave_idle() {
                abandon_wait();
                fault::fault_kind(FaultKind::Deadlock, CROSS_ISOLATE_DEADLOCK);
            }
        }
    }
}

/// How long a thread that has nothing to run waits for mail before it sleeps. A sleep costs the
/// system calls of a wake-up on both sides (an eventfd write, an `epoll_wait` return), several
/// microseconds, which is longer than a short promise's whole life; a promise that arrives
/// within this window finds its thread awake.
pub(super) const SPIN_NS: i64 = 20_000;

/// Spins briefly for work before the thread sleeps. Only a program with several scheduler threads
/// has anyone to send mail, so a single-threaded program never spins.
pub(super) unsafe fn spin_for_work() {
    if crate::sched::started() <= 1 {
        return;
    }
    let end = clock_ns() + SPIN_NS;
    loop {
        if crate::sched::work_available()
            || crate::sched::signalled()
            || crate::isolate::has_posts()
            || crate::isolate::pending_cancel() != 0
            || clock_ns() >= end
        {
            return;
        }
        std::hint::spin_loop();
    }
}
