//! Hooks into the `ms-rt` runtime that the network modules need.
//!
//! Only the ms thread may call `msrt_*` (the allocator and counts are not
//! atomic); background threads of this crate never touch this module.

use crate::sys::{self, Borrowed};
use std::sync::atomic::Ordering;

use ms_rt::fault::{
    cancel_flag, msrt_cancelled, msrt_cleanup_discard, msrt_cleanup_push, msrt_shield_enter,
    msrt_shield_exit,
};
#[cfg(unix)]
use ms_rt::task::msrt_task_forget_fd;
use ms_rt::task::{
    msrt_task_current, msrt_task_sleep, msrt_task_spawn, msrt_task_wait_fd, msrt_token_free,
    msrt_token_new, msrt_token_park, msrt_token_post,
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

/// A value held across a call that can park. A cancellation or fault leaves the task with a jump
/// that skips destructors, so a plain local on the frame would leak (64 KiB per cancelled request
/// for the client's read buffer, a few hundred bytes for the request itself); the box belongs to a
/// runtime cleanup that drops it on that path. [`Parked::finish`] hands the value back.
pub struct Parked<T> {
    value: *mut T,
    /// The cleanup handle; none on a test thread without tasks, where nothing can cancel.
    cleanup: Option<usize>,
}

/// A reusable buffer taken out of its slot for a read that can park.
pub type ParkedBuf = Parked<Vec<u8>>;

unsafe extern "C-unwind" fn drop_box<T>(arg: *mut u8) {
    // SAFETY: the runtime runs this once, only on the path that skips `Parked::drop`, and
    // `arg` is the allocation `Parked::new` leaked.
    drop(unsafe { Box::from_raw(arg.cast::<T>()) });
}

impl<T> Parked<T> {
    pub fn new(value: T) -> Parked<T> {
        let value = Box::into_raw(Box::new(value));
        // SAFETY: the allocation stays live until the action runs or `finish`/`drop` discards it.
        let cleanup =
            crate::wait::parks().then(|| unsafe { cleanup_push(drop_box::<T>, value.cast()) });
        Parked { value, cleanup }
    }

    pub fn get(&mut self) -> &mut T {
        // SAFETY: this value owns the allocation until it ends or the cleanup takes it, and the
        // cleanup only runs when this frame is abandoned.
        unsafe { &mut *self.value }
    }

    /// The value, for the slot it came from.
    pub fn finish(self) -> T {
        let this = core::mem::ManuallyDrop::new(self);
        if let Some(handle) = this.cleanup {
            cleanup_discard(handle);
        }
        // SAFETY: the cleanup was discarded, so this is the allocation's sole owner.
        *unsafe { Box::from_raw(this.value) }
    }
}

impl<T> Drop for Parked<T> {
    fn drop(&mut self) {
        if let Some(handle) = self.cleanup {
            cleanup_discard(handle);
        }
        // SAFETY: as in `finish`.
        drop(unsafe { Box::from_raw(self.value) });
    }
}

/// Whether SIGINT/SIGTERM asked the program to stop.
pub fn cancel_requested() -> bool {
    // The flag is a static `u8` the runtime updates from a signal handler; atomics have the
    // layout of the integer and relaxed loads are what the ABI prescribes.
    cancel_flag().load(Ordering::Relaxed) != 0
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

/// A park that ended because the task was cancelled. Code that parks returns it as an error, so
/// the frames above unwind with ordinary returns and run their destructors; the FFI boundary
/// ([`take_cancelled`]) then runs the runtime's cancellation path once.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cancelled;

/// Whether the error a native call returns means cancellation: a cancelled park leaves the
/// task's cancel flag set (a shield holds it back), so the boundary asks the flag. It then calls
/// [`cancelled`].
pub fn cancel_pending() -> bool {
    cancel_requested()
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
    unsafe { msrt_task_wait_fd(sys::raw(sock) as _, events, within_waiter(timeout_ns)) }
}

/// Narrows `timeout_ns` (negative: none) to the deadline of the wait (or promise limit) whose deferred
/// work is running on this task, as `msrt_promise_wait` does for its own waits. Without it a
/// `stream.read().with(options: PromiseOptions(timeout: d)).wait()` on a silent socket blocks past `d`, because a deferred read
/// runs on the waiter's stack and only its own waits can notice the limit. The wait then ends
/// with the runtime's timeout bits, which every caller reports as its timeout.
pub fn within_waiter(timeout_ns: i64) -> i64 {
    let at = ms_rt::task::defer_deadline();
    if at == i64::MAX {
        return timeout_ns;
    }
    let left = at.saturating_sub(ms_rt::sys::monotonic_ns()).max(0);
    if timeout_ns < 0 || left < timeout_ns {
        left
    } else {
        timeout_ns
    }
}

/// Parks the running task for `ns` nanoseconds without watching a socket. Returns the
/// runtime's bits (8 timeout, 16 cancelled).
pub fn sleep(ns: i64) -> u32 {
    // SAFETY: parks the current task; no Rust borrow is held across the call by contract.
    unsafe { msrt_task_sleep(within_waiter(ns).max(0)) }
}

/// Holds SIGINT/SIGTERM back from the running task until [`stop_unshield`]. A cancel aimed at
/// the task itself (its scope closed, its time limit passed) still applies.
pub fn stop_shield() {
    ms_rt::fault::stop_shield_enter()
}

/// Ends one [`stop_shield`].
pub fn stop_unshield() {
    ms_rt::fault::stop_shield_exit()
}

/// Cancels the running task at `deadline` (none: never), replacing any earlier limit.
pub fn limit_current_until(deadline: Option<std::time::Instant>) {
    let ns = deadline.map_or(-1, |at| {
        at.saturating_duration_since(std::time::Instant::now())
            .as_nanos()
            .min(i64::MAX as u128) as i64
    });
    ms_rt::task::limit_current(ns)
}

/// Cancels task `handle` (a handle that no longer exists is ignored). The running task is not
/// cancelled: it is the one asking, and finishes its own work.
pub fn cancel_task(handle: u64) {
    if handle != 0 && handle != current_task() {
        // SAFETY: plain scheduler call on the runtime thread.
        unsafe { ms_rt::task::msrt_task_cancel(handle) }
    }
}

/// Forgets a cancel aimed at the running task, which caught it and goes on.
pub fn acknowledge_cancel() {
    ms_rt::fault::acknowledge_cancel()
}

/// Starts `entry(arg)` as a promise task on this thread and returns its id. `entry` owns `arg`.
/// A fault or cancellation in it ends only that promise; [`promise_drop`] releases it.
///
/// # Safety
/// `arg` must be valid for `entry`, which owns it.
pub unsafe fn promise_start(entry: unsafe extern "C-unwind" fn(*mut u8), arg: *mut u8) -> i64 {
    // SAFETY: forwarded contract.
    unsafe { ms_rt::promise::start_native(entry, arg) }
}

/// Asks the promise `id` to stop at its next wait.
pub fn promise_cancel(id: i64) {
    ms_rt::promise::cancel(id)
}

/// Cancels the promise `id` if unfinished, joins its task, and frees it.
pub fn promise_drop(id: i64) {
    ms_rt::promise::msrt_promise_drop(id)
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
        unsafe { msrt_token_park(self.0, within_waiter(timeout_ns), core::ptr::null_mut()) }
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
