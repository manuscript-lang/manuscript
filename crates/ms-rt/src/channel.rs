//! Park and wake for the task channels of `@std/tasks.ms`. The queues live in Manuscript; a task
//! that finds its queue empty (or full) makes a token, records it beside the queue, and parks on
//! it until the other end posts it. A token lasts for one wait, so a post that arrives after the
//! wait ended, or a second post, finds no token and is dropped.
use crate::task;

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
