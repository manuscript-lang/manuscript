//! Decimal formatting and parsing of Int for the Rust runtime that remains (faults and the profiler). The number
//! natives are C (runtime/core/num.c, fmt.c).
//! ms: domain number

// The formatting kernel lives in runtime/core/fmt.c.
unsafe extern "C-unwind" {
    fn msrt_fmt_i64(value: i64, out: *mut u8, capacity: usize, length: *mut usize) -> bool;
}

/// Formats `v` in decimal into `tmp`, returning the used tail.
pub fn format_i64(v: i64, tmp: &mut [u8; 20]) -> &[u8] {
    let mut length = 0;
    // SAFETY: the pointer and capacity are the buffer's own, and 20 bytes hold every Int.
    let fits = unsafe { msrt_fmt_i64(v, tmp.as_mut_ptr(), tmp.len(), &raw mut length) };
    assert!(
        fits && length <= tmp.len(),
        "number formatting buffer too small"
    );
    &tmp[..length]
}

/// Appends `v` in decimal.
pub fn push_i64(out: &mut Vec<u8>, v: i64) {
    out.extend_from_slice(format_i64(v, &mut [0; 20]));
}

/// `String.parse_int`: optional sign, ASCII digits only; overflow is `None`.
pub fn parse_int_decimal(text: &[u8]) -> Option<i64> {
    let (neg, digits) = match text.first()? {
        b'-' => (true, &text[1..]),
        b'+' => (false, &text[1..]),
        _ => (false, text),
    };
    if digits.is_empty() {
        return None;
    }
    // Up to eighteen digits cannot overflow, so skip the per-digit checks.
    if digits.len() <= 18 {
        let mut acc = 0i64;
        for &c in digits {
            let d = c.wrapping_sub(b'0');
            if d > 9 {
                return None;
            }
            acc = acc * 10 + d as i64;
        }
        return Some(if neg { -acc } else { acc });
    }
    // Longer text is valid only with leading zeros; at most nineteen significant digits can fit, so the
    // untouched suffix of an overlong input is never scanned.
    let zeros = digits.iter().take_while(|&&c| c == b'0').count();
    let significant = &digits[zeros..];
    if significant.len() > 19 {
        return None;
    }
    let mut acc = 0u64;
    for &c in significant {
        let d = c.wrapping_sub(b'0');
        if d > 9 {
            return None;
        }
        acc = acc * 10 + d as u64;
    }
    if neg {
        0i64.checked_sub_unsigned(acc)
    } else {
        i64::try_from(acc).ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::string::ToString;

    #[test]
    fn int_formatting_and_parsing() {
        let _g = crate::testutil::lock();
        let mut tmp = [0u8; 20];
        assert_eq!(format_i64(i64::MIN, &mut tmp), b"-9223372036854775808");
        assert_eq!(format_i64(0, &mut tmp), b"0");
        assert_eq!(parse_int_decimal(b"-9223372036854775808"), Some(i64::MIN));
        assert_eq!(parse_int_decimal(b"9223372036854775808"), None);
        assert_eq!(parse_int_decimal(b"+12"), Some(12));
        assert_eq!(
            parse_int_decimal(b"999999999999999999"),
            Some(999_999_999_999_999_999)
        );
        assert_eq!(
            parse_int_decimal(b"-999999999999999999"),
            Some(-999_999_999_999_999_999)
        );
        assert_eq!(parse_int_decimal(b"9223372036854775807"), Some(i64::MAX));
        assert_eq!(parse_int_decimal(b"-"), None);
        assert_eq!(parse_int_decimal(b"+-1"), None);
        assert_eq!(parse_int_decimal(b"1 "), None);
        let zeros = "0".repeat(40);
        let long =
            |sign: &str, tail: &str| parse_int_decimal(format!("{sign}{zeros}{tail}").as_bytes());
        assert_eq!(long("", "9223372036854775807"), Some(i64::MAX));
        assert_eq!(long("-", "9223372036854775808"), Some(i64::MIN));
        assert_eq!(long("", "9223372036854775808"), None);
        assert_eq!(long("-", "9223372036854775809"), None);
        assert_eq!(long("+", ""), Some(0));
        assert_eq!(long("-", "7"), Some(-7));
        assert_eq!(long("", "-1"), None);
        assert_eq!(long("", "1x"), None);
        assert_eq!(long("", "\u{e9}"), None);
        assert_eq!(parse_int_decimal(b"99999999999999999999"), None);
        assert_eq!(parse_int_decimal(b"18446744073709551616"), None);
        assert_eq!(parse_int_decimal(b"!0000000000000000000000"), None);
        let mut tmp = [0u8; 20];
        for v in [
            0,
            9,
            10,
            99,
            100,
            101,
            12345,
            -1,
            -10,
            -100,
            1_000_000,
            i64::MAX,
            i64::MIN + 1,
        ] {
            assert_eq!(format_i64(v, &mut tmp), v.to_string().as_bytes(), "{v}");
        }
        assert_eq!(parse_int_decimal(b"1_0"), None);
        assert_eq!(parse_int_decimal(b""), None);
    }
}
