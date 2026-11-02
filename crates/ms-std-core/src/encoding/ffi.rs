//! C ABI shims for `@std/data/encoding.ms`; JSON also calls the padded Base64 natives. Symbols are `msstd_encoding_<function>`;
//! fallible functions return a status byte and write the ok value through `out` only on success.
use alloc::string::String;
use alloc::vec::Vec;
use ms_rt::ffi::{Fail, native};

native! {
    fn msstd_encoding_ascii85_encode(data: &[u8]) -> String {
        super::ascii85_encode(data)
    }

    fn msstd_encoding_ascii85_decode(
        text: &str, has_max: bool, max: i64,
    ) -> Result<Vec<u8>, Fail> {
        super::ascii85_decode(text, has_max.then_some(max))
    }

    fn msstd_encoding_base64_encode_unpadded(data: &[u8], url_safe: bool) -> String {
        super::base64_encode_unpadded(data, url_safe)
    }

    fn msstd_encoding_base64_decode_unpadded(
        text: &str, url_safe: bool, has_max: bool, max: i64,
    ) -> Result<Vec<u8>, Fail> {
        super::base64_decode_unpadded(text, url_safe, has_max.then_some(max))
    }

    fn msstd_encoding_base32_encode(data: &[u8], hex_alphabet: bool, padded: bool) -> String {
        super::base32_encode(data, hex_alphabet, padded)
    }

    fn msstd_encoding_base32_decode(
        text: &str, hex_alphabet: bool, padded: bool, has_max: bool, max: i64,
    ) -> Result<Vec<u8>, Fail> {
        super::base32_decode(text, hex_alphabet, padded, has_max.then_some(max))
    }

    fn msstd_encoding_base64_encode(data: &[u8], url_safe: bool) -> String {
        super::base64_encode(data, url_safe)
    }

    fn msstd_encoding_base64_decode(
        text: &str,
        url_safe: bool,
        has_max: bool,
        max: i64,
    ) -> Result<Vec<u8>, Fail> {
        super::base64_decode(text, url_safe, has_max.then_some(max))
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
            assert_eq!(msstd_encoding_base64_decode(&t, 0, 0, 0, b.as_mut_ptr()), 0);
            assert_eq!(bytes_ref(b.as_ptr()), b"foo");
            let again = take_string(|o| msstd_encoding_base64_encode(b.as_ptr(), 0, o));
            assert_eq!(again, "Zm9v");
            let bad = new_string("%");
            assert_eq!(
                msstd_encoding_base64_decode(&bad, 0, 0, 0, b.as_mut_ptr()),
                ms_rt::ffi::STATUS_INVALID_DATA
            );
            ms_rt::ffi::str_release(&t);
            ms_rt::ffi::str_release(&bad);
        }
    }
}
