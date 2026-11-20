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
