//! Tokens: one-shot slots a parked task waits on, and teardown.

use super::*;

// ---- tokens ----

pub(super) fn token_mut(s: &mut Sched, id: u64) -> Option<&mut Token> {
    let idx = (id & 0xffff_ffff) as usize;
    let k = s.tokens.get_mut(idx.checked_sub(1)?)?;
    (k.live
        && k.gen_ as u64 == (id >> 32) & GEN_MASK as u64
        && (id >> isolate::ID_SHIFT) as usize == isolate::id())
    .then_some(k)
}

/// Records a post to `id` and wakes its waiter. A post to a freed token, or to one that holds
/// a post nobody has taken yet, is dropped.
pub(super) unsafe fn post(id: u64, value: u64, remote: bool) {
    let mut s = sched();
    let Some(k) = token_mut(&mut s, id) else {
        return;
    };
    if remote && k.remote {
        k.remote = false;
        let peer = core::mem::take(&mut k.peer);
        s.remote_tokens -= 1;
        s.peer_tokens -= usize::from(peer);
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
pub(super) unsafe fn deliver_remote_posts() {
    for (id, value) in isolate::take_posts() {
        // SAFETY: runs on the runtime thread.
        unsafe { post(id, value, true) };
    }
    if crate::sched::signalled() {
        crate::promise::apply_events();
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
        if s.tokens.is_empty() {
            // Registry slots can be reused by later isolates. Resume their generation history,
            // but recreate only vacant slots, never another isolate's values or waiters.
            for gen_ in isolate::take_token_generations() {
                let idx = s.tokens.len();
                s.tokens.push(Token {
                    gen_,
                    live: false,
                    remote: false,
                    peer: false,
                    waiter: 0,
                    posted: None,
                });
                if gen_ < GEN_MASK {
                    s.free_tokens.push(idx);
                }
            }
        }
        let idx = match s.free_tokens.pop() {
            Some(i) => i,
            None => {
                s.tokens.push(Token {
                    gen_: 0,
                    live: false,
                    remote: false,
                    peer: false,
                    waiter: 0,
                    posted: None,
                });
                s.tokens.len() - 1
            }
        };
        let k = &mut s.tokens[idx];
        k.gen_ += 1;
        k.live = true;
        k.remote = remote;
        k.peer = remote && flags & TOKEN_PEER != 0;
        k.waiter = 0;
        k.posted = None;
        let id =
            (isolate::id() as u64) << isolate::ID_SHIFT | (k.gen_ as u64) << 32 | (idx as u64 + 1);
        if remote {
            s.remote_tokens += 1;
            s.peer_tokens += usize::from(flags & TOKEN_PEER != 0);
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
        if cancel_flag().load(Ordering::Relaxed) != 0 {
            return WAIT_CANCELLED;
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
/// A post to a token that already holds an untaken post is coalesced into it: a token carries a wake, not a
/// count, so a waiter re-checks its own state after waking (promise waits and pipes do; they never lose work).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_token_post_remote(id: u64, value: u64) {
    isolate::post_remote(id, value);
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
        let peer = core::mem::take(&mut k.peer);
        let reusable = k.gen_ < GEN_MASK;
        if remote {
            s.remote_tokens -= 1;
            s.peer_tokens -= usize::from(peer);
        }
        // Retire an exhausted slot instead of wrapping back to a still-stale id.
        if reusable {
            s.free_tokens.push((id & 0xffff_ffff) as usize - 1);
        }
    }
}

/// Drops all scheduler state: a worker isolate calls it as it ends; unit tests run several
/// scenarios in one process; the leak sweep calls it at exit so only real leaks remain in the
/// live-block count.
pub fn teardown() {
    crate::promise::teardown();
    fault::retire_hdr();
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
        // The isolate's pool owns mappings too. Its thread-local state has no destructor,
        // so a worker that exits must release the cached stacks as well as active ones.
        s.pool = Vec::new();
        s.pool_clean = 0;
        s.carve = (0, 0);
        for base in core::mem::take(&mut s.regions) {
            sys::unmap(base as *mut u8, REGION);
        }
        s.round = 0;
        s.scan = 0;
        s.cur = null_mut();
        s.main = null_mut();
        s.ready = VecDeque::new();
        s.slots = Vec::new();
        s.free_slots = Vec::new();
        s.timers = BinaryHeap::new();
        s.kills = BinaryHeap::new();
        s.timer_limit = MIN_TIMER_LIMIT;
        s.kill_limit = MIN_TIMER_LIMIT;
        s.fd_waiters = Vec::new();
        s.fd_waiting = 0;
        s.epfd = -1;
        s.zombie_stack = (0, 0);
        s.zombie_task = null_mut();
        s.live = 0;
        if !s.tokens.is_empty() {
            isolate::save_token_generations(s.tokens.iter().map(|token| token.gen_).collect());
        }
        s.tokens = Vec::new();
        s.free_tokens = Vec::new();
        s.remote_tokens = 0;
        s.peer_tokens = 0;
        isolate::clear_posts();
    }
}
