//! Hooks into the `ms-rt` runtime that the network modules need.
//!
//! Only the ms thread may call `msrt_*` (the allocator and counts are not
//! atomic); background threads of this crate never touch this module.

use crate::sys::{self, Borrowed};
use std::sync::atomic::Ordering;

use ms_rt::fault::{
    msrt_cancel_flag, msrt_cancelled, msrt_cleanup_discard, msrt_cleanup_push, msrt_shield_enter,
    msrt_shield_exit,
};
#[cfg(unix)]
use ms_rt::task::msrt_task_forget_fd;
use ms_rt::task::{
    msrt_task_current, msrt_task_set_prepark, msrt_task_sleep, msrt_task_spawn, msrt_task_wait_fd,
    msrt_token_free, msrt_token_new, msrt_token_park, msrt_token_post,
};

/// Registers `f(arg)` on the running task's cleanup stack: it runs if a fault or cancellation
/// leaves the task's guard, which skips destructors. Call [`cleanup_discard`] on normal exit.
///
/// # Safety
/// `arg` must stay valid for `f` until the action is discarded or the task's guard is left.
pub unsafe fn cleanup_push(f: unsafe extern "C-unwind" fn(*mut u8), arg: *mut u8) -> usize {
    // SAFETY: plain call on the runtime thread; validity of `arg` is the caller's contract.
    unsafe { msrt_cleanup_push(f, arg) }
}

/// Drops the action behind `handle` (and newer pending ones) without running it.
pub fn cleanup_discard(handle: usize) {
    msrt_cleanup_discard(handle)
}

/// Whether SIGINT/SIGTERM asked the program to stop.
pub fn cancel_requested() -> bool {
    // The flag is a static `u8` the runtime updates from a signal handler; atomics have the
    // layout of the integer and relaxed loads are what the ABI prescribes.
    msrt_cancel_flag.load(Ordering::Relaxed) != 0
}

/// Unwinds the program through the runtime's cancellation path when a stop was requested.
pub fn check_cancel() {
    if cancel_requested() {
        msrt_cancelled()
    }
}

/// Runs the runtime's cancellation path (cleanups, then exit).
pub fn cancelled() -> ! {
    msrt_cancelled()
}

/// Shields the running task from SIGINT/SIGTERM cancellation until `unshield`.
pub fn shield() {
    msrt_shield_enter()
}

/// Ends one `shield`.
pub fn unshield() {
    msrt_shield_exit()
}

/// Id of the running task.
pub fn current_task() -> u64 {
    // SAFETY: plain query of the runtime thread's scheduler.
    unsafe { msrt_task_current() }
}

/// Starts a detached task running `entry(arg)`; it first runs when the caller parks.
///
/// # Safety
/// `arg` must be valid for `entry`, which owns it.
pub unsafe fn spawn_detached(entry: unsafe extern "C-unwind" fn(*mut u8), arg: *mut u8) {
    // SAFETY: `entry` and `arg` follow the task ABI; ownership of `arg` moves to the task.
    unsafe { msrt_task_spawn(entry, arg, 1, 0) };
}

/// Request bit for [`wait_fd`]: keep the registration between waits (the runtime's `WAIT_KEEP`).
pub const WAIT_KEEP: u32 = 32;

/// Ends the registration a [`WAIT_KEEP`] wait left on `fd`; call it before `fd` closes.
#[cfg(unix)]
pub fn forget_fd(fd: i32) {
    msrt_task_forget_fd(fd)
}

/// Parks the running task until `sock` is ready for `events` (1 read, 2 write) or the
/// timeout (negative: none) passes. Returns the runtime's ready bits. The only caller of
/// `msrt_task_wait_fd`: a change of its handle type is confined to this function and `sys::Raw`. (The
/// runtime reads the low 32 bits, as it always has on Windows.)
pub fn wait_fd(sock: Borrowed<'_>, events: u32, timeout_ns: i64) -> u32 {
    // SAFETY: parks the current task; no Rust borrow is held across the call by contract.
    unsafe { msrt_task_wait_fd(sys::raw(sock) as _, events, timeout_ns) }
}

/// Parks the running task for `ns` nanoseconds without watching a socket. Returns the
/// runtime's bits (8 timeout, 16 cancelled).
pub fn sleep(ns: i64) -> u32 {
    // SAFETY: parks the current task; no Rust borrow is held across the call by contract.
    unsafe { msrt_task_sleep(ns) }
}

/// Makes every park of a task (including `time.sleep` and other natives' waits) first hand the
/// server reactor role on, so a request handler that waits does not stall the other requests.
pub fn install_prepark_hook() {
    unsafe extern "C-unwind" fn hook() {
        crate::http::server::give_up_reactor_role();
    }
    msrt_task_set_prepark(Some(hook));
}

/// A runtime park token (`msrt_token_*`) posted from the runtime thread; freed on drop.
pub struct Token(u64);

impl Token {
    pub fn new() -> Token {
        // SAFETY: plain scheduler call on the runtime thread.
        Token(unsafe { msrt_token_new(0) })
    }

    pub fn id(&self) -> u64 {
        self.0
    }

    /// Parks the running task until the token is posted or the timeout (negative: none)
    /// passes. Returns 0 when posted, else the runtime's bits (8 timeout, 16 cancelled).
    pub fn park(&self, timeout_ns: i64) -> u32 {
        // SAFETY: parks the current task on a live token; no Rust borrow is held across the
        // call by contract.
        unsafe { msrt_token_park(self.0, timeout_ns, core::ptr::null_mut()) }
    }
}

impl Default for Token {
    fn default() -> Token {
        Token::new()
    }
}

impl Drop for Token {
    fn drop(&mut self) {
        // SAFETY: the token is live and nobody waits on it once its owner is dropped.
        unsafe { msrt_token_free(self.0) }
    }
}

/// Wakes the task parked on token `id`, or makes its next park return at once. A token that
/// was freed ignores the post.
pub fn post(id: u64) {
    // SAFETY: plain scheduler call on the runtime thread; stale ids are ignored.
    unsafe { msrt_token_post(id, 0) }
}
