//! Faults, cancellation and guards of the C runtime (`runtime/core/fault.c`, `unwind.c`), as the Rust natives of
//! `ms-std-net` see them. Every function here is an import; the C runtime owns the behavior.
//! This crate goes away with `ms-std-net` (see the shim issue).
#![allow(unsafe_code)]

use ms_rt_abi::StrVal;
pub use ms_rt_abi::record::FaultKind;

/// `MsBytes`: a pointer and a length.
#[repr(C)]
#[derive(Clone, Copy)]
struct Bytes {
    ptr: *const u8,
    len: usize,
}

unsafe extern "C-unwind" {
    /// Raises a fault with this message; never returns.
    pub fn msrt_fault(msg: *const u8, len: usize) -> !;
    pub safe fn msrt_fault_int_overflow() -> !;
    /// Holds every cancel back from the running task until the matching exit.
    pub safe fn msrt_shield_enter();
    pub safe fn msrt_shield_exit();
    /// Runs `code(data)` guarded: a fault or cancel inside runs the cleanups since entry and returns nonzero.
    pub fn msrt_guard_call(
        code: unsafe extern "C-unwind" fn(*mut u8),
        data: *mut u8,
        message: *mut StrVal,
    ) -> u8;
    fn ms_stop_shield_enter();
    fn ms_stop_shield_exit();
    fn ms_cancel_flag() -> u8;
    fn ms_cancel_set_task(value: u8);
    fn ms_sched_cancel_return();
    fn ms_fault_out_of_memory(bytes: usize) -> !;
    fn ms_fault(kind: u32, message: Bytes) -> !;
    fn ms_fault_fatal(kind: u32, message: Bytes) -> !;
}

/// Whether the running task must stop at its next cancellation point.
pub fn cancel_pending() -> bool {
    // SAFETY: reads the running task's state.
    unsafe { ms_cancel_flag() != 0 }
}

/// Delivers a pending cancel by return: the caller releases what it holds and returns a zero result at once.
pub fn cancel_return() {
    // SAFETY: called by the running task.
    unsafe { ms_sched_cancel_return() }
}

/// Forgets a cancel aimed at the running task, which caught it and goes on.
pub fn acknowledge_cancel() {
    // SAFETY: the running task's own flag.
    unsafe { ms_cancel_set_task(0) }
}

/// Holds stop requests (SIGINT, SIGTERM) back from the running task; a cancel aimed at it still applies.
pub fn stop_shield_enter() {
    // SAFETY: the running task's shield count.
    unsafe { ms_stop_shield_enter() }
}

pub fn stop_shield_exit() {
    // SAFETY: pairs with `stop_shield_enter`.
    unsafe { ms_stop_shield_exit() }
}

/// Raises a fault with this message; never returns.
pub fn fault(msg: &[u8]) -> ! {
    // SAFETY: the runtime copies the message.
    unsafe { msrt_fault(msg.as_ptr(), msg.len()) }
}

/// A fault of a given family.
pub fn fault_kind(kind: FaultKind, msg: &[u8]) -> ! {
    // SAFETY: the runtime copies the message.
    unsafe {
        ms_fault(
            kind as u32,
            Bytes {
                ptr: msg.as_ptr(),
                len: msg.len(),
            },
        )
    }
}

/// Ends the process after a failure the runtime cannot report as a fault.
pub fn fatal(msg: &[u8]) -> ! {
    // SAFETY: the runtime copies the message.
    unsafe {
        ms_fault_fatal(
            FaultKind::Fault as u32,
            Bytes {
                ptr: msg.as_ptr(),
                len: msg.len(),
            },
        )
    }
}

pub fn out_of_memory(bytes: usize) -> ! {
    // SAFETY: reports and does not return.
    unsafe { ms_fault_out_of_memory(bytes) }
}
