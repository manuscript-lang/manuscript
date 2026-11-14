//! Unicode properties and UTF-8 validation, using Rust's character tables and validator.
//! ms: domain unicode
use alloc::vec::Vec;
use ms_rt::ffi::native;

fn scalar(value: i64) -> Option<char> {
    u32::try_from(value).ok().and_then(char::from_u32)
}

native! {
    // ms: domain=utf8
    fn msstd_utf8_is_valid(data: &[u8]) -> bool {
        core::str::from_utf8(data).is_ok()
    }

    fn msstd_unicode_fields(text: &str) -> out Vec<&str> {
        text.split_whitespace().collect()
    }

    fn msstd_unicode_is_alphabetic(value: i64) -> bool {
        scalar(value).is_some_and(char::is_alphabetic)
    }

    fn msstd_unicode_is_alphanumeric(value: i64) -> bool {
        scalar(value).is_some_and(char::is_alphanumeric)
    }

    fn msstd_unicode_is_numeric(value: i64) -> bool {
        scalar(value).is_some_and(char::is_numeric)
    }

    fn msstd_unicode_is_lowercase(value: i64) -> bool {
        scalar(value).is_some_and(char::is_lowercase)
    }

    fn msstd_unicode_is_uppercase(value: i64) -> bool {
        scalar(value).is_some_and(char::is_uppercase)
    }

    fn msstd_unicode_is_whitespace(value: i64) -> bool {
        scalar(value).is_some_and(char::is_whitespace)
    }

    fn msstd_unicode_is_control(value: i64) -> bool {
        scalar(value).is_some_and(char::is_control)
    }

    fn msstd_unicode_is_ascii(value: i64) -> bool {
        scalar(value).is_some_and(|value| value.is_ascii())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scalar_validation_rejects_non_scalars_without_truncating() {
        for value in [-1, i64::MIN, 0xd800, 0xdfff, 0x110000, i64::MAX] {
            assert_eq!(scalar(value), None);
        }
        assert_eq!(scalar(0), Some('\0'));
        assert_eq!(scalar(0x10ffff), Some('\u{10ffff}'));
    }
}
