//! C ABI shims for `@std/compress.ms` (`msrt_compress_*`). The format is passed by name
//! (`"gzip"`, `"zlib"`, `"deflate"`); `CompressionFormat` methods pass the matching constant.
//! Statuses: `STATUS_INVALID_INPUT`, `STATUS_INVALID_DATA`, `STATUS_LIMIT_EXCEEDED` and
//! `STATUS_UNSUPPORTED` (5); `Failed(message)` is never produced.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use ms_std_core::{StrObj, VecVal, bytes_ref, opt, status_of, str_ref, write_bytes};

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_compress(
    data: *const VecVal,
    format: *const StrObj,
    level: i64,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `data` is a live Bytes value; `format` is live; `out` is writable.
    unsafe {
        let r = crate::compress(bytes_ref(data), str_ref(format), level, opt(has_max, max));
        if let Ok(b) = &r {
            write_bytes(out, b);
        }
        status_of(&r)
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_decompress(
    data: *const VecVal,
    format: *const StrObj,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `data` is a live Bytes value; `format` is live; `out` is writable.
    unsafe {
        let r = crate::decompress_bytes(bytes_ref(data), str_ref(format), opt(has_max, max));
        if let Ok(b) = &r {
            write_bytes(out, b);
        }
        status_of(&r)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ms_std_core::new_string;

    #[test]
    fn abi_roundtrip() {
        let mut input = core::mem::MaybeUninit::<VecVal>::uninit();
        let (mut packed, mut plain) = (
            core::mem::MaybeUninit::<VecVal>::uninit(),
            core::mem::MaybeUninit::<VecVal>::uninit(),
        );
        let f = new_string("gzip");
        // SAFETY: all pointers are live; results are dropped below.
        unsafe {
            write_bytes(input.as_mut_ptr(), b"hello hello hello");
            assert_eq!(
                msrt_compress_compress(input.as_ptr(), f, 6, 0, 0, packed.as_mut_ptr()),
                0
            );
            assert_eq!(
                msrt_compress_decompress(packed.as_ptr(), f, 1, 16, plain.as_mut_ptr()),
                ms_std_core::STATUS_LIMIT_EXCEEDED
            );
            assert_eq!(
                msrt_compress_decompress(packed.as_ptr(), f, 0, 0, plain.as_mut_ptr()),
                0
            );
            assert_eq!(bytes_ref(plain.as_ptr()), b"hello hello hello");
            for v in [&mut input, &mut packed, &mut plain] {
                ms_rt::vec::msrt_bytes_drop(v.as_mut_ptr());
            }
            ms_rt::obj::msrt_release(f.cast());
        }
    }
}
