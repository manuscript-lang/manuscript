//! Park and wake for the task channels of `@std/tasks.ms`. The queues live in Manuscript; a task
//! that finds its queue empty (or full) makes a token, records it beside the queue, and parks on
//! it until the other end posts it. A token lasts for one wait, so a post that arrives after the
//! wait ended, or a second post, finds no token and is dropped.
use crate::task;
use std::collections::{HashMap, VecDeque};

crate::isolate_static! {
    /// Tokens of tasks waiting on a key (the identity of something they wait for), oldest first.
    static WAIT_QUEUES: Option<HashMap<usize, VecDeque<i64>>> = None;
}

fn queues() -> &'static mut HashMap<usize, VecDeque<i64>> {
    // SAFETY: only the scheduler thread of an isolate reaches its queues.
    unsafe { (*WAIT_QUEUES.ptr()).get_or_insert_with(HashMap::new) }
}

/// Drops every queue; part of the scheduler teardown.
pub(crate) fn reset_wait_queues() {
    // SAFETY: as in `queues`.
    unsafe { *WAIT_QUEUES.ptr() = None };
}

/// The address as an integer: the identity of a box for the wait queues below.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_addr_id(addr: *const u8) -> i64 {
    addr as usize as i64
}

/// Queues `token` (from `msrt_channel_token`) behind the tasks already waiting on `key`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_waitq_push(key: i64, token: i64) {
    queues().entry(key as usize).or_default().push_back(token);
}

/// Posts the oldest token queued on `key` and drops it from the queue. Returns 1 when there was
/// one, 0 when nobody waits.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_waitq_wake(key: i64) -> i64 {
    let q = queues();
    let Some(waiting) = q.get_mut(&(key as usize)) else {
        return 0;
    };
    let token = waiting.pop_front();
    if waiting.is_empty() {
        q.remove(&(key as usize));
    }
    match token {
        Some(token) => {
            msrt_channel_post(token);
            1
        }
        None => 0,
    }
}

/// Takes `token` out of the queue on `key`. Returns 1 when it was still queued, 0 when a wake
/// already took it.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_waitq_remove(key: i64, token: i64) -> i64 {
    let q = queues();
    let Some(waiting) = q.get_mut(&(key as usize)) else {
        return 0;
    };
    let found = waiting.iter().position(|t| *t == token);
    if let Some(at) = found {
        waiting.remove(at);
    }
    if waiting.is_empty() {
        q.remove(&(key as usize));
    }
    found.is_some() as i64
}

/// Makes a token for one wait and returns its id, never 0.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_channel_token() -> i64 {
    // SAFETY: single threaded scheduler.
    unsafe { task::msrt_token_new(0) as i64 }
}

/// Parks the current task until `token` is posted, then frees it. A post made before the park
/// returns at once. If the task is cancelled while it waits, the token is freed and the
/// cancellation unwinds the task.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_channel_park(token: i64) {
    // SAFETY: single threaded scheduler; a null `value_out` is allowed.
    let woke = unsafe { task::msrt_token_park(token as u64, -1, core::ptr::null_mut()) };
    // SAFETY: the park ended, so no task waits on the token.
    unsafe { task::msrt_token_free(token as u64) };
    if woke != 0 {
        crate::fault::msrt_cancelled();
    }
}

/// Wakes the task parked on `token`, or keeps the post for its park. A token that has already
/// been posted or freed is left alone.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_channel_post(token: i64) {
    // SAFETY: single threaded scheduler.
    unsafe { task::msrt_token_post(token as u64, 0) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::lock;

    #[test]
    fn wait_queues_wake_in_order_and_drop_removed_tokens() {
        let _g = lock();
        task::teardown();
        let (a, b, c) = (
            msrt_channel_token(),
            msrt_channel_token(),
            msrt_channel_token(),
        );
        msrt_waitq_push(7, a);
        msrt_waitq_push(7, b);
        msrt_waitq_push(7, c);
        assert_eq!(msrt_waitq_remove(7, b), 1);
        assert_eq!(msrt_waitq_remove(7, b), 0);
        assert_eq!(msrt_waitq_wake(8), 0);
        // The first wake posts `a`: its park returns at once.
        assert_eq!(msrt_waitq_wake(7), 1);
        msrt_channel_park(a);
        assert_eq!(msrt_waitq_wake(7), 1);
        msrt_channel_park(c);
        assert_eq!(msrt_waitq_wake(7), 0);
        assert!(queues().is_empty());
        task::teardown();
    }

    #[test]
    fn a_post_before_the_park_returns_at_once_and_frees_the_token() {
        let _g = lock();
        task::teardown();
        let token = msrt_channel_token();
        assert_ne!(token, 0);
        msrt_channel_post(token);
        msrt_channel_park(token);
        // A late post to the freed token is dropped, and the slot is reused under a new id.
        msrt_channel_post(token);
        assert_ne!(msrt_channel_token(), token);
        task::teardown();
    }
}
