//! C ABI shims for the Base64 half of `@std/encoding.ms`, which JSON lowering also calls. Symbols are `msrt_encoding_<function>`;
//! fallible functions return a status byte and write the ok value through `out` only on success.
use alloc::string::String;
use alloc::vec::Vec;
use ms_rt::ffi::{Fail, native};

native! {
    fn msrt_encoding_base64_encode(data: &[u8], url_safe: bool) -> String {
        crate::base64_encode(data, url_safe)
    }

    fn msrt_encoding_base64_decode(
        text: &str,
        url_safe: bool,
        has_max: bool,
        max: i64,
    ) -> Result<Vec<u8>, Fail> {
        crate::base64_decode(text, url_safe, has_max.then_some(max))
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt::ffi::{VecVal, bytes_ref, new_string, take_string};

    #[test]
    fn abi_roundtrip() {
        let t = new_string("Zm9v");
        let mut b = MaybeUninit::<VecVal>::uninit();
        // SAFETY: all pointers are live; the results are released below.
        unsafe {
            assert_eq!(msrt_encoding_base64_decode(&t, 0, 0, 0, b.as_mut_ptr()), 0);
            assert_eq!(bytes_ref(b.as_ptr()), b"foo");
            let again = take_string(|o| msrt_encoding_base64_encode(b.as_ptr(), 0, o));
            assert_eq!(again, "Zm9v");
            let bad = new_string("%");
            assert_eq!(
                msrt_encoding_base64_decode(&bad, 0, 0, 0, b.as_mut_ptr()),
                ms_rt::ffi::STATUS_INVALID_DATA
            );
            ms_rt::ffi::str_release(&t);
            ms_rt::ffi::str_release(&bad);
        }
    }
}
