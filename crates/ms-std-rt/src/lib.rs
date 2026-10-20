//! What the `ms-std-*` crates borrow from `ms-rt`: reading and building strings, raising faults and
//! polling cancellation. Everything resolves at the final link against `libms_rt.a`.
#![no_std]
// This crate is the C ABI boundary of the standard-library natives.
#![allow(unsafe_code)]

extern crate alloc;

use alloc::vec::Vec;
use core::cell::UnsafeCell;
use core::fmt::{self, Write};
use core::sync::atomic::{AtomicU8, Ordering};
use ms_rt_abi::{STR_DATA_OFFSET, StrObj};

unsafe extern "C-unwind" {
    fn msrt_string_from_bytes(ptr: *const u8, len: usize) -> *mut StrObj;
    fn msrt_retain(o: *mut ms_rt_abi::Obj);
    fn msrt_release(o: *mut ms_rt_abi::Obj);
    fn msrt_fault(msg: *const u8, len: usize) -> !;
    fn msrt_cancelled() -> !;
    static msrt_cancel_flag: AtomicU8;
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
    unsafe { msrt_cancel_flag.load(Ordering::Relaxed) != 0 }
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

unsafe extern "C-unwind" {
    fn msrt_map_new(out: *mut ms_rt_abi::MapVal);
    fn msrt_map_add(
        m: *mut ms_rt_abi::MapVal,
        kd: *const ms_rt_abi::TypeDesc,
        vd: *const ms_rt_abi::TypeDesc,
        key: *mut u8,
        val: *mut u8,
    );
    static msrt_desc_string: ms_rt_abi::TypeDesc;
    static msrt_desc_int: ms_rt_abi::TypeDesc;
}

/// A value of a `Map[String, _]` built by [`write_string_map`].
pub enum MapValue<'a> {
    /// A `String` value.
    Str(&'a [u8]),
    /// An `Int` value.
    Int(i64),
}

/// Initialises `*out` with a `Map[String, String]` (`ints` false) or `Map[String, Int]` (`ints`
/// true) holding `pairs`; the value kind must match `ints`.
///
/// # Safety
/// `out` must be writable.
pub unsafe fn write_string_map<'a>(
    pairs: impl IntoIterator<Item = (&'a [u8], MapValue<'a>)>,
    ints: bool,
    out: *mut ms_rt_abi::MapVal,
) {
    // SAFETY: `out` is writable; each slot holds one owned element for the runtime to take.
    unsafe {
        msrt_map_new(out);
        let vd: *const ms_rt_abi::TypeDesc = if ints {
            &raw const msrt_desc_int
        } else {
            &raw const msrt_desc_string
        };
        for (k, v) in pairs {
            let mut key = new_string(k);
            let kd = &raw const msrt_desc_string;
            match v {
                MapValue::Str(b) => {
                    let mut val = new_string(b);
                    msrt_map_add(out, kd, vd, (&raw mut key).cast(), (&raw mut val).cast());
                }
                MapValue::Int(mut i) => {
                    msrt_map_add(out, kd, vd, (&raw mut key).cast(), (&raw mut i).cast());
                }
            }
        }
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

/// Diagnostic text of the most recent `STATUS_FAILED` result (the runtime is single-threaded).
struct Failure(UnsafeCell<Vec<u8>>);
// SAFETY: the runtime runs Manuscript code on one thread.
unsafe impl Sync for Failure {}
static FAILURE: Failure = Failure(UnsafeCell::new(Vec::new()));

/// Records the text a later `failure_message` returns.
pub fn record_failure(message: Vec<u8>) {
    // SAFETY: single-threaded runtime; no reference into FAILURE outlives a call.
    unsafe { *FAILURE.0.get() = message };
}

/// A fresh string holding the most recently recorded failure text.
pub fn failure_message() -> *mut StrObj {
    // SAFETY: single-threaded runtime.
    new_string(unsafe { &*FAILURE.0.get() })
}

/// Adds a reference to a runtime object.
///
/// # Safety
/// `o` must point to a live object.
pub unsafe fn retain(o: *mut ms_rt_abi::Obj) {
    // SAFETY: provided by `ms-rt`.
    unsafe { msrt_retain(o) }
}

/// Drops a reference to a runtime object.
///
/// # Safety
/// `o` must point to a live object the caller holds a reference to.
pub unsafe fn release(o: *mut ms_rt_abi::Obj) {
    // SAFETY: provided by `ms-rt`.
    unsafe { msrt_release(o) }
}

/// The elements of a list of plain values (`Int`, `Float`, pointers).
///
/// # Safety
/// `v` must point to a live `VecVal` whose elements are `T`.
pub unsafe fn list_slice<'a, T>(v: *const ms_rt_abi::VecVal) -> &'a [T] {
    // SAFETY: a list is `len` initialised elements at `ptr` (null when empty).
    unsafe {
        let v = &*v;
        if v.len == 0 {
            &[]
        } else {
            core::slice::from_raw_parts(v.ptr as *const T, v.len)
        }
    }
}

/// Initialises `*out` with a fresh list holding a copy of `items`.
///
/// # Safety
/// `out` must be writable.
pub unsafe fn write_list<T: Copy>(items: &[T], out: *mut ms_rt_abi::VecVal) {
    // SAFETY: the allocation holds `items.len()` elements.
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
        core::ptr::copy_nonoverlapping(items.as_ptr(), ptr as *mut T, items.len());
        *out = ms_rt_abi::VecVal {
            ptr,
            len: items.len(),
            cap: items.len(),
        };
    }
}
