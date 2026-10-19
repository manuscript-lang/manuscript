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

unsafe extern "C-unwind" {
    fn msrt_alloc(size: usize) -> *mut u8;
    fn msrt_free(ptr: *mut u8);
}

/// Aborts the program when a stop request is pending (call between blocking steps of long operations).
pub fn poll_cancel() {
    if cancel_pending() {
        cancelled();
    }
}

/// The bytes of a `Bytes` value.
///
/// # Safety
/// `v` must point to a live `VecVal` of bytes.
pub unsafe fn vec_bytes<'a>(v: *const ms_rt_abi::VecVal) -> &'a [u8] {
    // SAFETY: a byte vector is `len` initialised bytes at `ptr` (null when empty).
    unsafe {
        let v = &*v;
        if v.len == 0 {
            &[]
        } else {
            core::slice::from_raw_parts(v.ptr, v.len)
        }
    }
}

/// Initialises `*out` with a fresh `Bytes` copy of `data`.
///
/// # Safety
/// `out` must be writable.
pub unsafe fn write_bytes(data: &[u8], out: *mut ms_rt_abi::VecVal) {
    // SAFETY: the allocation holds `data.len()` bytes; the runtime frees it with `msrt_free`.
    unsafe {
        if data.is_empty() {
            *out = ms_rt_abi::VecVal {
                ptr: core::ptr::null_mut(),
                len: 0,
                cap: 0,
            };
            return;
        }
        let ptr = msrt_alloc(data.len());
        core::ptr::copy_nonoverlapping(data.as_ptr(), ptr, data.len());
        *out = ms_rt_abi::VecVal {
            ptr,
            len: data.len(),
            cap: data.len(),
        };
    }
}

/// Initialises `*out` with a `List[String]` that takes ownership of `items`.
///
/// # Safety
/// `out` must be writable.
pub unsafe fn write_string_list(items: &[*mut StrObj], out: *mut ms_rt_abi::VecVal) {
    // SAFETY: the allocation holds `items.len()` pointers.
    unsafe {
        if items.is_empty() {
            *out = ms_rt_abi::VecVal {
                ptr: core::ptr::null_mut(),
                len: 0,
                cap: 0,
            };
            return;
        }
        let ptr = msrt_alloc(core::mem::size_of_val(items));
        core::ptr::copy_nonoverlapping(items.as_ptr(), ptr as *mut *mut StrObj, items.len());
        *out = ms_rt_abi::VecVal {
            ptr,
            len: items.len(),
            cap: items.len(),
        };
    }
}

/// A refcounted runtime object (`Obj` header) wrapping a Rust value; used for handles such as open files.
#[repr(C)]
pub struct Handle<T> {
    pub hdr: ms_rt_abi::Obj,
    pub value: T,
}

unsafe extern "C" fn drop_handle<T>(obj: *mut ms_rt_abi::Obj) {
    // SAFETY: `obj` came from `new_handle::<T>`.
    unsafe {
        core::ptr::drop_in_place(&mut (*(obj as *mut Handle<T>)).value);
        msrt_free(obj as *mut u8);
    }
}

/// Allocates a handle with reference count 1; releasing the last reference drops `value`.
pub fn new_handle<T>(value: T) -> *mut Handle<T> {
    // SAFETY: the block is large and aligned enough for `Handle<T>` (16-byte alignment) and fully initialised.
    unsafe {
        let ptr = msrt_alloc(core::mem::size_of::<Handle<T>>()) as *mut Handle<T>;
        core::ptr::write(
            ptr,
            Handle {
                hdr: ms_rt_abi::Obj {
                    rc: 1,
                    drop: Some(drop_handle::<T>),
                },
                value,
            },
        );
        ptr
    }
}
