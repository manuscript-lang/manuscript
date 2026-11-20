//! Tasks, tokens and waits of the C scheduler (`runtime/core/task.c`, `token.c`), imported for `ms-std-net`.
#![allow(unsafe_code)]

use ms_rt_abi::StrVal;

unsafe extern "C-unwind" {
    pub fn msrt_task_spawn(
        entry: unsafe extern "C-unwind" fn(*mut u8),
        arg: *mut u8,
        flags: u32,
        stack_bytes: usize,
    ) -> u64;
    pub fn msrt_task_yield();
    pub fn msrt_task_current() -> u64;
    pub fn msrt_task_cancel(handle: u64);
    pub fn msrt_task_join(handle: u64, message: *mut StrVal) -> u8;
    pub fn msrt_task_wait_fd(fd: i32, events: u32, timeout_ns: i64) -> u32;
    pub fn msrt_task_wait_fd_at(fd: i32, events: u32, at_ns: i64) -> u32;
    pub fn msrt_task_sleep(ns: i64) -> u32;
    pub safe fn msrt_task_forget_fd(fd: i32);
    pub fn msrt_token_new(flags: u32) -> u64;
    pub fn msrt_token_park(id: u64, timeout_ns: i64, value_out: *mut u64) -> u32;
    pub fn msrt_token_park_at(id: u64, at_ns: i64, value_out: *mut u64) -> u32;
    pub fn msrt_token_post(id: u64, value: u64);
    pub fn msrt_token_free(id: u64);
    pub fn msrt_token_post_remote(id: u64, value: u64);
    fn ms_task_limit_current_at(at_ns: i64);
    fn ms_task_defer_deadline() -> i64;
}

/// Cancels the running task at `at_ns` on the monotonic clock (negative: never).
pub fn limit_current_at(at_ns: i64) {
    // SAFETY: the running task's own limit.
    unsafe { ms_task_limit_current_at(at_ns) }
}

/// The deadline of the deferred promise work running on this task (`i64::MAX`: none).
pub fn defer_deadline() -> i64 {
    // SAFETY: reads the running task's state.
    unsafe { ms_task_defer_deadline() }
}
