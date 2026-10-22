//! Hooks into the `ms-rt` runtime that the network modules need.
//!
//! Only the ms thread may call `msrt_*` (the allocator and counts are not
//! atomic); background threads of this crate never touch this module.

use crate::sys::{self, Borrowed};
use std::sync::atomic::{AtomicU8, Ordering};

unsafe extern "C" {
    static msrt_cancel_flag: AtomicU8;
    fn msrt_cancelled() -> !;
    fn msrt_shield_enter();
    fn msrt_shield_exit();
    fn msrt_task_current() -> u64;
    fn msrt_task_set_prepark(hook: Option<unsafe extern "C-unwind" fn()>);
    fn msrt_task_spawn(
        entry: unsafe extern "C-unwind" fn(*mut u8),
        arg: *mut u8,
        flags: u32,
        stack_bytes: usize,
    ) -> u64;
    // The first argument is the raw socket handle (`sys::Raw`: a file descriptor on Unix, the
    // `SOCKET` as `u64` on Windows).
    fn msrt_task_wait_fd(fd: sys::Raw, events: u32, timeout_ns: i64) -> u32;
    #[cfg(windows)]
    fn msrt_task_sleep(ns: i64) -> u32;
    fn msrt_token_new(flags: u32) -> u64;
    fn msrt_token_park(id: u64, timeout_ns: i64, value_out: *mut u64) -> u32;
    fn msrt_token_post(id: u64, value: u64);
    fn msrt_token_free(id: u64);
}

/// Whether SIGINT/SIGTERM asked the program to stop.
pub fn cancel_requested() -> bool {
    // SAFETY: the flag is a static `u8` the runtime updates from a signal handler; atomics
    // have the layout of the integer and relaxed loads are what the ABI prescribes.
    unsafe { msrt_cancel_flag.load(Ordering::Relaxed) != 0 }
}

/// Unwinds the program through the runtime's cancellation path when a stop was requested.
pub fn check_cancel() {
    if cancel_requested() {
        // SAFETY: runs cleanups and exits; never returns.
        unsafe { msrt_cancelled() }
    }
}

/// Runs the runtime's cancellation path (cleanups, then exit).
pub fn cancelled() -> ! {
    // SAFETY: runs cleanups and exits; never returns.
    unsafe { msrt_cancelled() }
}

/// Shields the running task from SIGINT/SIGTERM cancellation until `unshield`.
pub fn shield() {
    // SAFETY: plain counter update on the runtime thread.
    unsafe { msrt_shield_enter() }
}

/// Ends one `shield`.
pub fn unshield() {
    // SAFETY: plain counter update on the runtime thread.
    unsafe { msrt_shield_exit() }
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

/// Parks the running task until `sock` is ready for `events` (1 read, 2 write) or the
/// timeout (negative: none) passes. Returns the runtime's ready bits. The only caller of
/// `msrt_task_wait_fd`: a change of its handle type is confined to this function and `sys::Raw`.
pub fn wait_fd(sock: Borrowed<'_>, events: u32, timeout_ns: i64) -> u32 {
    // SAFETY: parks the current task; no Rust borrow is held across the call by contract.
    unsafe { msrt_task_wait_fd(sys::raw(sock), events, timeout_ns) }
}

/// Parks the running task for `ns` nanoseconds without watching a socket. Returns the
/// runtime's bits (8 timeout, 16 cancelled).
#[cfg(windows)]
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
    // SAFETY: `hook` follows the runtime's hook ABI and stays valid for the process lifetime.
    unsafe { msrt_task_set_prepark(Some(hook)) };
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
