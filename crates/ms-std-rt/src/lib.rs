//! What the `ms-std-*` crates borrow from `ms-rt`: reading and building strings, raising faults and
//! polling cancellation. Everything resolves at the final link against `libms_rt.a`.
#![no_std]
// This crate is the C ABI boundary of the standard-library natives.
#![allow(unsafe_code)]

use core::fmt::{self, Write};
use ms_rt_abi::{STR_DATA_OFFSET, StrObj};

unsafe extern "C-unwind" {
    fn msrt_string_from_bytes(ptr: *const u8, len: usize) -> *mut StrObj;
    fn msrt_fault(msg: *const u8, len: usize) -> !;
    fn msrt_cancelled() -> !;
    static msrt_cancel_flag: u8;
}

/// The bytes of a live string.
///
/// # Safety
/// `s` must point to a live `StrObj` that outlives `'a`.
pub unsafe fn str_bytes<'a>(s: *const StrObj) -> &'a [u8] {
    // SAFETY: a `StrObj` is followed by `len` data bytes at `STR_DATA_OFFSET`.
    unsafe { core::slice::from_raw_parts((s as *const u8).add(STR_DATA_OFFSET), (*s).len) }
}

/// A new owned string (refcount 1) holding `bytes`.
pub fn new_string(bytes: &[u8]) -> *mut StrObj {
    // SAFETY: the slice is readable; the runtime copies it.
    unsafe { msrt_string_from_bytes(bytes.as_ptr(), bytes.len()) }
}

/// Raises a fault with this message; never returns.
pub fn fault(msg: &str) -> ! {
    // SAFETY: the runtime copies the message.
    unsafe { msrt_fault(msg.as_ptr(), msg.len()) }
}

struct Stack {
    buf: [u8; 512],
    len: usize,
}

impl Write for Stack {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        let n = s.len().min(self.buf.len() - self.len);
        self.buf[self.len..self.len + n].copy_from_slice(&s.as_bytes()[..n]);
        self.len += n;
        Ok(())
    }
}

/// Raises a fault with a formatted message (truncated at 512 bytes); never returns.
pub fn fault_fmt(args: fmt::Arguments<'_>) -> ! {
    let mut s = Stack {
        buf: [0; 512],
        len: 0,
    };
    let _ = s.write_fmt(args);
    // SAFETY: the buffer prefix is readable; the runtime copies it.
    unsafe { msrt_fault(s.buf.as_ptr(), s.len) }
}

/// Whether a stop request (SIGINT or SIGTERM) is pending.
pub fn cancel_pending() -> bool {
    // SAFETY: a plain byte load of the runtime's flag.
    unsafe { core::ptr::addr_of!(msrt_cancel_flag).read_volatile() != 0 }
}

/// Unwinds the program after a stop request; never returns.
pub fn cancelled() -> ! {
    // SAFETY: provided by `ms-rt`.
    unsafe { msrt_cancelled() }
}
