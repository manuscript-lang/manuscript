//! C ABI shims for `@std/encoding.ms`. Symbols are `msrt_encoding_<function>`;
//! fallible functions return a status byte and write the ok value through `out` only on success.
use alloc::string::String;
use alloc::vec::Vec;
use ms_std_core::{Fail, native};

native! {
    fn msrt_encoding_hex_encode(data: &[u8]) -> String {
        crate::hex_encode(data)
    }

    fn msrt_encoding_hex_decode(text: &str, has_max: bool, max: i64) -> Result<Vec<u8>, Fail> {
        crate::hex_decode(text, has_max.then_some(max))
    }

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

    fn msrt_encoding_utf16_encode(text: &str, little_endian: bool) -> out Vec<u8> {
        crate::utf16_encode(text, little_endian)
    }

    fn msrt_encoding_utf16_decode(
        data: &[u8],
        little_endian: bool,
        has_max: bool,
        max: i64,
    ) -> Result<String, Fail> {
        crate::utf16_decode(data, little_endian, has_max.then_some(max))
    }

    fn msrt_encoding_latin1_encode(text: &str) -> Result<Vec<u8>, Fail> {
        crate::latin1_encode(text)
    }

    fn msrt_encoding_latin1_decode(data: &[u8]) -> String {
        crate::latin1_decode(data)
    }

    fn msrt_encoding_ascii_encode(text: &str) -> Result<Vec<u8>, Fail> {
        crate::ascii_encode(text)
    }

    fn msrt_encoding_ascii_decode(data: &[u8]) -> Result<String, Fail> {
        crate::ascii_decode(data)
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_std_core::{VecVal, bytes_ref, new_string, str_ref};

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
