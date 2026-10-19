//! C ABI shims for `@std/encoding.ms`. Symbols are `msrt_encoding_<function>`;
//! fallible functions return a status byte and write the ok value through `out` only on success.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use alloc::vec::Vec;
use ms_std_core::{
    Fail, StrObj, VecVal, bytes_ref, new_string, opt, status_of, str_ref, write_bytes,
};

unsafe fn bytes_result(r: Result<Vec<u8>, Fail>, out: *mut VecVal) -> u8 {
    if let Ok(b) = &r {
        // SAFETY: `out` is writable by the caller contract.
        unsafe { write_bytes(out, b) };
    }
    status_of(&r)
}

unsafe fn string_result(r: Result<alloc::string::String, Fail>, out: *mut *mut StrObj) -> u8 {
    if let Ok(s) = &r {
        // SAFETY: `out` is writable by the caller contract.
        unsafe { out.write(new_string(s)) };
    }
    status_of(&r)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_encoding_hex_encode(data: *const VecVal) -> *mut StrObj {
    // SAFETY: `data` is a live Bytes value.
    new_string(&crate::hex_encode(unsafe { bytes_ref(data) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_encoding_hex_decode(
    text: *const StrObj,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `text` is live; `out` is writable.
    unsafe { bytes_result(crate::hex_decode(str_ref(text), opt(has_max, max)), out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_encoding_base64_encode(
    data: *const VecVal,
    url_safe: u8,
) -> *mut StrObj {
    // SAFETY: `data` is a live Bytes value.
    new_string(&crate::base64_encode(
        unsafe { bytes_ref(data) },
        url_safe != 0,
    ))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_encoding_base64_decode(
    text: *const StrObj,
    url_safe: u8,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `text` is live; `out` is writable.
    unsafe {
        bytes_result(
            crate::base64_decode(str_ref(text), url_safe != 0, opt(has_max, max)),
            out,
        )
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_encoding_utf16_encode(
    text: *const StrObj,
    little_endian: u8,
    out: *mut VecVal,
) {
    // SAFETY: `text` is live; `out` is writable.
    unsafe { write_bytes(out, &crate::utf16_encode(str_ref(text), little_endian != 0)) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_encoding_utf16_decode(
    data: *const VecVal,
    little_endian: u8,
    has_max: u8,
    max: i64,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: `data` is a live Bytes value; `out` is writable.
    unsafe {
        string_result(
            crate::utf16_decode(bytes_ref(data), little_endian != 0, opt(has_max, max)),
            out,
        )
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_encoding_latin1_encode(text: *const StrObj, out: *mut VecVal) -> u8 {
    // SAFETY: `text` is live; `out` is writable.
    unsafe { bytes_result(crate::latin1_encode(str_ref(text)), out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_encoding_latin1_decode(data: *const VecVal) -> *mut StrObj {
    // SAFETY: `data` is a live Bytes value.
    new_string(&crate::latin1_decode(unsafe { bytes_ref(data) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_encoding_ascii_encode(text: *const StrObj, out: *mut VecVal) -> u8 {
    // SAFETY: `text` is live; `out` is writable.
    unsafe { bytes_result(crate::ascii_encode(str_ref(text)), out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_encoding_ascii_decode(
    data: *const VecVal,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: `data` is a live Bytes value; `out` is writable.
    unsafe { string_result(crate::ascii_decode(bytes_ref(data)), out) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;

    #[test]
    fn abi_roundtrip() {
        let t = new_string("Zm9v");
        let mut b = MaybeUninit::<VecVal>::uninit();
        // SAFETY: all pointers are live; the results are released below.
        unsafe {
            assert_eq!(msrt_encoding_base64_decode(t, 0, 0, 0, b.as_mut_ptr()), 0);
            assert_eq!(bytes_ref(b.as_ptr()), b"foo");
            let hex = msrt_encoding_hex_encode(b.as_ptr());
            assert_eq!(str_ref(hex), "666f6f");
            let bad = new_string("%");
            assert_eq!(
                msrt_encoding_base64_decode(bad, 0, 0, 0, b.as_mut_ptr()),
                ms_std_core::STATUS_INVALID_DATA
            );
            ms_rt::obj::msrt_release(hex.cast());
            ms_rt::obj::msrt_release(t.cast());
            ms_rt::obj::msrt_release(bad.cast());
        }
    }
}
