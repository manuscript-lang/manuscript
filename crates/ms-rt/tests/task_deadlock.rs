//! Deadlock recovery through the production guard and cleanup path.
#![allow(unsafe_code)]

use ms_rt::{fault, task};
use std::ptr::null_mut;
use std::sync::Mutex;

static LOCK: Mutex<()> = Mutex::new(());

unsafe extern "C-unwind" fn park_channel(arg: *mut u8) {
    ms_rt::channel::msrt_channel_park(arg as i64);
}

#[test]
fn repeated_deadlocked_channel_waits_reuse_their_token_storage() {
    let _lock = LOCK.lock().unwrap_or_else(|error| error.into_inner());
    task::teardown();
    // SAFETY: each guard owns its single-use channel token; no completion is provided.
    unsafe {
        let mut token = ms_rt::channel::msrt_channel_token() as u64;
        let slot = token as u32;
        let mut reused = true;
        for _ in 0..64 {
            let status = fault::msrt_guard_call(park_channel, token as *mut u8, null_mut());
            assert_eq!(status, 1);
            let next = ms_rt::channel::msrt_channel_token() as u64;
            reused &= next as u32 == slot && next != token;
            token = next;
        }
        task::msrt_token_free(token);
        task::teardown();
        assert!(
            reused,
            "faulted channel waits must release their token slots"
        );
    }
}

struct Recovery {
    token: u64,
    target: u64,
    cleaned: bool,
}

unsafe extern "C-unwind" fn release_token(arg: *mut u8) {
    // SAFETY: the guarded call keeps this state alive throughout cleanup.
    unsafe {
        let state = &mut *arg.cast::<Recovery>();
        task::msrt_token_free(state.token);
        state.cleaned = true;
    }
}

unsafe extern "C-unwind" fn park_with_cleanup(arg: *mut u8) {
    // SAFETY: the test owns the token and deliberately provides no completion.
    unsafe {
        let token = (*arg.cast::<Recovery>()).token;
        fault::msrt_cleanup_push(release_token, arg);
        task::msrt_token_park(token, -1, null_mut());
    }
}

#[test]
fn deadlock_cleanup_can_free_the_token_and_park_again() {
    let _lock = LOCK.lock().unwrap_or_else(|error| error.into_inner());
    task::teardown();
    // SAFETY: the guard contains the deliberate deadlock; state outlives its cleanup.
    unsafe {
        let mut state = Recovery {
            token: task::msrt_token_new(0),
            target: 0,
            cleaned: false,
        };
        let status = fault::msrt_guard_call(park_with_cleanup, (&raw mut state).cast(), null_mut());
        // A normal timed park after recovery must remain usable.
        let token = task::msrt_token_new(0);
        let resumed = task::msrt_token_park(token, 0, null_mut());
        task::msrt_token_free(token);
        task::teardown();
        assert_eq!(status, 1);
        assert!(state.cleaned, "cleanup could not free its deadlocked token");
        assert_eq!(resumed, task::WAIT_TIMEOUT);
    }
}

unsafe extern "C-unwind" fn park_target(arg: *mut u8) {
    // SAFETY: the test keeps the token alive until the target is joined.
    unsafe { task::msrt_token_park(arg as u64, -1, null_mut()) };
}

unsafe extern "C-unwind" fn finish_target(arg: *mut u8) {
    // SAFETY: state and target outlive this cleanup; posting lets the target return.
    unsafe {
        let state = &mut *arg.cast::<Recovery>();
        task::msrt_token_post(state.token, 42);
        state.cleaned = task::msrt_task_join(state.target, null_mut()) == 0;
    }
}

unsafe extern "C-unwind" fn join_with_cleanup(arg: *mut u8) {
    // SAFETY: the test owns the target; cleanup will retry the interrupted join.
    unsafe {
        let target = (*arg.cast::<Recovery>()).target;
        fault::msrt_cleanup_push(finish_target, arg);
        task::msrt_task_join(target, null_mut());
    }
}

#[test]
fn deadlock_cleanup_can_finish_and_join_the_original_target() {
    let _lock = LOCK.lock().unwrap_or_else(|error| error.into_inner());
    task::teardown();
    // SAFETY: the guard contains the deliberate deadlock; state and token stay live.
    unsafe {
        let token = task::msrt_token_new(0);
        let target = task::msrt_task_spawn(park_target, token as *mut u8, 0, 0);
        task::msrt_task_yield();
        let mut state = Recovery {
            token,
            target,
            cleaned: false,
        };
        let status = fault::msrt_guard_call(join_with_cleanup, (&raw mut state).cast(), null_mut());
        let remaining = task::msrt_task_count();
        task::msrt_token_free(token);
        task::teardown();
        assert_eq!(status, 1);
        assert!(
            state.cleaned,
            "cleanup could not collect its original target"
        );
        assert_eq!(remaining, 1, "the recovered target must release its record");
    }
}
