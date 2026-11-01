//! Unicode properties and bounded UTF-8 scalar decoding, using Rust's character tables and validator.
use alloc::string::String;
use alloc::vec::Vec;
use ms_rt::ffi::native;

// Private scalar-result codes. A Unicode scalar is nonnegative, so these cannot collide.
const INCOMPLETE: i64 = -1;
const INVALID: i64 = -2;

fn scalar(value: i64) -> Option<char> {
    u32::try_from(value).ok().and_then(char::from_u32)
}

fn decode_first(data: &[u8]) -> i64 {
    let window = &data[..data.len().min(4)];
    let text = match core::str::from_utf8(window) {
        Ok(text) => text,
        Err(error) if error.valid_up_to() > 0 => {
            // Only the first scalar is requested; malformed or partial later text is irrelevant.
            core::str::from_utf8(&window[..error.valid_up_to()]).expect("validated UTF-8 prefix")
        }
        Err(error) => {
            return if error.error_len().is_none() {
                INCOMPLETE
            } else {
                INVALID
            };
        }
    };
    text.chars().next().map_or(INCOMPLETE, |value| value as i64)
}

fn decode_last(data: &[u8]) -> i64 {
    let mut incomplete = data.is_empty();
    // A suffix window may begin inside the preceding scalar, so try each possible start.
    for width in 1..=data.len().min(4) {
        match core::str::from_utf8(&data[data.len() - width..]) {
            Ok(text) => return text.chars().next_back().expect("nonempty suffix") as i64,
            Err(error) if error.valid_up_to() == 0 && error.error_len().is_none() => {
                incomplete = true;
            }
            Err(_) => {}
        }
    }
    if incomplete { INCOMPLETE } else { INVALID }
}

native! {
    fn msstd_utf8_is_valid(data: &[u8]) -> bool {
        core::str::from_utf8(data).is_ok()
    }

    fn msstd_unicode_fields(text: &str) -> out Vec<String> {
        text.split_whitespace().map(String::from).collect()
    }

    fn msstd_utf8_decode_first(data: &[u8], at: i64) -> i64 {
        usize::try_from(at).ok().and_then(|at| data.get(at..)).map_or(INVALID, decode_first)
    }

    fn msstd_utf8_decode_last(data: &[u8], end: i64) -> i64 {
        usize::try_from(end).ok().and_then(|end| data.get(..end)).map_or(INVALID, decode_last)
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
    fn bounded_decoders_ignore_unrelated_bytes() {
        assert_eq!(decode_first(&[b'a', 0xff]), 'a' as i64);
        assert_eq!(decode_first(&[0xc2, 0xa2, 0xff]), '¢' as i64);
        assert_eq!(decode_first(&[0xf0, 0x9f, 0x99, 0x82, 0xff]), '🙂' as i64);
        assert_eq!(decode_last(&[0xff, b'a']), 'a' as i64);
        assert_eq!(decode_last("🙂é".as_bytes()), 'é' as i64);
        assert_eq!(decode_last(&[0xff, 0xf0, 0x9f, 0x99, 0x82]), '🙂' as i64);
    }

    #[test]
    fn malformed_and_incomplete_are_distinct() {
        for data in [b"".as_slice(), &[0xc2], &[0xe2, 0x82], &[0xf0, 0x90, 0x80]] {
            assert_eq!(decode_first(data), INCOMPLETE);
            assert_eq!(decode_last(data), INCOMPLETE);
        }
        for data in [
            &[0x80][..],
            &[0xc0, 0x80],
            &[0xed, 0xa0, 0x80],
            &[0xe0, 0x80],
            &[0xf4, 0x90],
            &[0xf5, 0x80, 0x80, 0x80],
            &[0xff],
        ] {
            assert_eq!(decode_first(data), INVALID, "{data:x?}");
            assert_eq!(decode_last(data), INVALID, "{data:x?}");
        }
        assert_eq!(decode_first(&[0xef, 0xbf, 0xbd]), 0xfffd);
        assert_eq!(decode_last(&[0xc2, 0xa2, 0x80]), INVALID);
    }

    #[test]
    fn scalar_validation_rejects_non_scalars_without_truncating() {
        for value in [-1, i64::MIN, 0xd800, 0xdfff, 0x110000, i64::MAX] {
            assert_eq!(scalar(value), None);
        }
        assert_eq!(scalar(0), Some('\0'));
        assert_eq!(scalar(0x10ffff), Some('\u{10ffff}'));
    }
}
