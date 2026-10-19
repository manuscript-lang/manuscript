//! Shared helpers for `ms-std-*` crates: reading borrowed runtime values and
//! building owned results through the `ms-rt` ABI (`crates/ms-rt/ABI.md`).
//!
//! A std crate keeps its logic in safe Rust over `&str`, `&[u8]` and owned Rust
//! values, and confines the `extern "C"` shims to one `ffi` module that uses these helpers.
//! The crate is `no_std` + `alloc`: allocation of Rust values goes through the global allocator
//! of the final program (`ms-rt` installs its own); values handed back to generated code are
//! allocated with `msrt_alloc` so that the runtime can free them.
#![no_std]
#![allow(unsafe_code)]
// Unit tests drive the C ABI directly.
#![cfg_attr(test, allow(clippy::undocumented_unsafe_blocks))]

extern crate alloc;

use alloc::vec::Vec;
use ms_rt_abi::KIND_LIST;
pub use ms_rt_abi::{
    STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED, STATUS_OK,
    STATUS_OUT_OF_RANGE, STATUS_UNSUPPORTED, StrObj, TypeDesc, VecVal,
};

unsafe extern "C" {
    fn msrt_alloc(size: usize) -> *mut u8;
    fn msrt_string_from_bytes(ptr: *const u8, len: usize) -> *mut StrObj;
    fn msrt_list_new(out: *mut VecVal);
    fn msrt_list_push(v: *mut VecVal, d: *const TypeDesc, e: *const u8);
    fn msrt_fault(msg: *const u8, len: usize) -> !;
    static msrt_desc_string: TypeDesc;
    static msrt_desc_bytes: TypeDesc;
}

/// Error cases shared by the std error types (`InvalidInput`, `InvalidData`, `LimitExceeded`).
///
/// The numeric codes are the `STATUS_*` constants of `ms-rt-abi`; `Ok` is [`STATUS_OK`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Fail {
    InvalidInput,
    InvalidData,
    LimitExceeded,
    /// `Unsupported` (compression and archive formats).
    Unsupported,
}

impl Fail {
    /// The status byte returned across the C ABI.
    pub fn status(self) -> u8 {
        match self {
            Fail::InvalidInput => STATUS_INVALID_INPUT,
            Fail::InvalidData => STATUS_INVALID_DATA,
            Fail::LimitExceeded => STATUS_LIMIT_EXCEEDED,
            Fail::Unsupported => STATUS_UNSUPPORTED,
        }
    }
}

/// Status byte of a fallible native's result.
pub fn status_of<T>(r: &Result<T, Fail>) -> u8 {
    match r {
        Ok(_) => STATUS_OK,
        Err(e) => e.status(),
    }
}

/// Decodes a flattened optional scalar parameter (`has: u8, value`).
pub fn opt(has: u8, value: i64) -> Option<i64> {
    (has != 0).then_some(value)
}

/// Raises a runtime fault with `msg`; never returns.
pub fn fault(msg: &str) -> ! {
    // SAFETY: the runtime copies the message bytes.
    unsafe { msrt_fault(msg.as_ptr(), msg.len()) }
}

/// Borrows the text of a runtime string.
///
/// # Safety
/// `p` is a live, non-null `StrObj` that outlives `'a`.
pub unsafe fn str_ref<'a>(p: *const StrObj) -> &'a str {
    // SAFETY: caller contract; the runtime guarantees valid UTF-8 and a trailing NUL after `len`.
    unsafe {
        let len = (*p).len;
        let data = (p as *const u8).add(ms_rt_abi::STR_DATA_OFFSET);
        core::str::from_utf8_unchecked(core::slice::from_raw_parts(data, len))
    }
}

/// Creates an owned runtime string (+1).
pub fn new_string(s: &str) -> *mut StrObj {
    // SAFETY: pointer and length describe `s`.
    unsafe { msrt_string_from_bytes(s.as_ptr(), s.len()) }
}

/// Borrows the contents of a `Bytes` value.
///
/// # Safety
/// `v` is a live `VecVal` of bytes that outlives `'a`.
pub unsafe fn bytes_ref<'a>(v: *const VecVal) -> &'a [u8] {
    // SAFETY: caller contract; an empty value may carry a null pointer.
    unsafe {
        let v = &*v;
        if v.len == 0 {
            &[]
        } else {
            core::slice::from_raw_parts(v.ptr, v.len)
        }
    }
}

/// Writes an owned `Bytes` value holding a copy of `data` into uninitialised `out`.
///
/// # Safety
/// `out` is writable memory for a `VecVal`.
pub unsafe fn write_bytes(out: *mut VecVal, data: &[u8]) {
    // SAFETY: the buffer is `data.len()` bytes from the runtime allocator.
    unsafe {
        if data.is_empty() {
            out.write(VecVal {
                ptr: core::ptr::null_mut(),
                len: 0,
                cap: 0,
            });
            return;
        }
        let ptr = msrt_alloc(data.len());
        core::ptr::copy_nonoverlapping(data.as_ptr(), ptr, data.len());
        out.write(VecVal {
            ptr,
            len: data.len(),
            cap: data.len(),
        });
    }
}

/// A `List[String]` descriptor (`List` of `msrt_desc_string`), for lists of lists of strings.
static DESC_LIST_STRING: TypeDesc = TypeDesc {
    size: 24,
    align: 8,
    kind: KIND_LIST,
    reserved: 0,
    inner0: core::ptr::addr_of!(msrt_desc_string),
    inner1: core::ptr::null(),
    drop: None,
    copy: None,
    eq: None,
    hash: None,
};

/// Writes a `List[String]` of fresh strings into uninitialised `out`.
///
/// # Safety
/// `out` is writable memory for a `VecVal`.
pub unsafe fn write_string_list<S: AsRef<str>>(
    out: *mut VecVal,
    items: impl IntoIterator<Item = S>,
) {
    // SAFETY: `out` is initialised by `msrt_list_new` before use; each pushed slot holds a
    // string pointer whose ownership moves into the list.
    unsafe {
        msrt_list_new(out);
        for item in items {
            let s = new_string(item.as_ref());
            msrt_list_push(out, &raw const msrt_desc_string, (&raw const s).cast());
        }
    }
}

/// Writes a `List[List[String]]` of fresh strings into uninitialised `out`.
///
/// # Safety
/// `out` is writable memory for a `VecVal`.
pub unsafe fn write_string_matrix<S: AsRef<str>, R: IntoIterator<Item = S>>(
    out: *mut VecVal,
    rows: impl IntoIterator<Item = R>,
) {
    // SAFETY: as `write_string_list`; each row slot is consumed by the push.
    unsafe {
        msrt_list_new(out);
        for row in rows {
            let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
            write_string_list(v.as_mut_ptr(), row);
            msrt_list_push(out, &DESC_LIST_STRING, v.as_ptr().cast());
        }
    }
}

/// Reads a `List[String]` into Rust strings.
///
/// # Safety
/// `v` is a live `List[String]`.
pub unsafe fn read_string_list<'a>(v: *const VecVal) -> Vec<&'a str> {
    // SAFETY: elements are non-null `StrObj` pointers stored inline, 8 bytes apart.
    unsafe {
        let v = &*v;
        (0..v.len)
            .map(|i| str_ref(*(v.ptr as *const *const StrObj).add(i)))
            .collect()
    }
}

/// Reads a `List[List[String]]`.
///
/// # Safety
/// `v` is a live `List[List[String]]`.
pub unsafe fn read_string_matrix<'a>(v: *const VecVal) -> Vec<Vec<&'a str>> {
    // SAFETY: elements are `VecVal`s stored inline, 24 bytes apart.
    unsafe {
        let v = &*v;
        (0..v.len)
            .map(|i| read_string_list((v.ptr as *const VecVal).add(i)))
            .collect()
    }
}

/// The `Bytes` descriptor, for lists of bytes values.
pub fn desc_bytes() -> *const TypeDesc {
    &raw const msrt_desc_bytes
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strings_and_bytes_roundtrip() {
        let s = new_string("héllo");
        // SAFETY: `s` is a fresh live string.
        assert_eq!(unsafe { str_ref(s) }, "héllo");
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `v` is writable; the value is dropped at the end.
        unsafe {
            write_bytes(v.as_mut_ptr(), b"abc");
            assert_eq!(bytes_ref(v.as_ptr()), b"abc");
            ms_rt::vec::msrt_bytes_drop(v.as_mut_ptr());
            write_bytes(v.as_mut_ptr(), b"");
            assert_eq!(bytes_ref(v.as_ptr()), b"");
        }
    }

    #[test]
    fn string_matrix_roundtrip() {
        let mut v = core::mem::MaybeUninit::<VecVal>::uninit();
        // SAFETY: `v` is writable; every read borrows the live value.
        unsafe {
            write_string_matrix(
                v.as_mut_ptr(),
                alloc::vec![alloc::vec!["a", "b"], alloc::vec![]],
            );
            assert_eq!(
                read_string_matrix(v.as_ptr()),
                alloc::vec![alloc::vec!["a", "b"], alloc::vec![]]
            );
            ms_rt::vec::msrt_list_drop(v.as_mut_ptr(), &DESC_LIST_STRING);
        }
    }

    #[test]
    fn status_codes() {
        assert_eq!(status_of(&Ok::<(), Fail>(())), STATUS_OK);
        assert_eq!(Fail::LimitExceeded.status(), STATUS_LIMIT_EXCEEDED);
        assert_eq!(opt(0, 5), None);
        assert_eq!(opt(1, 5), Some(5));
    }
}
