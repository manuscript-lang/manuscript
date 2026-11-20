//! Int and Float formatting and parsing with shortest round-trip output.
//! ms: domain number
use ms_rt_abi::{
    STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_OK, STATUS_OUT_OF_RANGE, StrVal,
};

// The moved symbols (runtime/symbols/num.txt) are defined by the C runtime; Rust callers and tests reach them here.
unsafe extern "C-unwind" {
    pub fn msrt_float_compare(a: f64, b: f64) -> i64;
    pub fn msrt_float_truncate_to_int(v: f64, out: *mut i64) -> u8;
    pub fn msrt_int_compare(a: i64, b: i64) -> i64;
    pub fn msrt_uint_compare(a: i64, b: i64) -> i64;
    pub fn msrt_uint_to_float(v: i64) -> f64;
    pub fn msrt_uint_to_float32(v: i64) -> f64;
}

// The formatting kernels live in runtime/core/fmt.c; the helpers below call them.
unsafe extern "C-unwind" {
    fn msrt_fmt_u64(value: u64, out: *mut u8, capacity: usize, length: *mut usize) -> bool;
    fn msrt_fmt_i64(value: i64, out: *mut u8, capacity: usize, length: *mut usize) -> bool;
    fn msrt_fmt_radix(
        magnitude: u64,
        radix: u32,
        negative: u8,
        out: *mut u8,
        capacity: usize,
        length: *mut usize,
    ) -> bool;
    fn msrt_fmt_float(value: f64, out: *mut u8, capacity: usize, length: *mut usize) -> bool;
    fn msrt_fmt_float32(value: f64, out: *mut u8, capacity: usize, length: *mut usize) -> bool;
    fn msrt_fmt_float_precision(
        value: f64,
        format: u8,
        digits: i64,
        out: *mut u8,
        capacity: usize,
        length: *mut usize,
    ) -> bool;
}

/// Runs a C formatter over `buffer` and returns the bytes it wrote. Every buffer is at least the capacity the
/// C header (`MS_FMT_*_CAPACITY`) documents for its argument, so a refusal is a bug in this file.
fn written(buffer: &mut [u8], call: impl FnOnce(*mut u8, usize, *mut usize) -> bool) -> usize {
    let mut length = 0;
    let fits = call(buffer.as_mut_ptr(), buffer.len(), &raw mut length);
    assert!(
        fits && length <= buffer.len(),
        "number formatting buffer too small"
    );
    length
}

/// Formats `v` in decimal into `tmp`, returning the used tail.
pub fn format_i64(v: i64, tmp: &mut [u8; 20]) -> &[u8] {
    // SAFETY: `written` passes the buffer's own pointer and length.
    let n = written(tmp, |out, capacity, length| unsafe {
        msrt_fmt_i64(v, out, capacity, length)
    });
    &tmp[..n]
}

/// Appends `v` in decimal.
pub fn push_i64(out: &mut Vec<u8>, v: i64) {
    out.extend_from_slice(format_i64(v, &mut [0; 20]));
}

/// Lowercase radix formatting (`radix` in 2..=36).
pub fn format_radix(v: i64, radix: u32, out: &mut Vec<u8>) {
    let mut tmp = [0u8; 65];
    // SAFETY: `written` passes the buffer's own pointer and length.
    let n = written(&mut tmp, |out, capacity, length| unsafe {
        msrt_fmt_radix(
            v.unsigned_abs(),
            radix,
            u8::from(v < 0),
            out,
            capacity,
            length,
        )
    });
    out.extend_from_slice(&tmp[..n]);
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

/// `Numbers.parse_int`: Err carries the status code. Radix 0 reads a `0x`, `0o` or `0b` prefix (any case) after
/// the sign and otherwise means 10.
pub fn parse_int_radix(text: &[u8], radix: i64) -> Result<i64, u8> {
    if radix != 0 && !(2..=36).contains(&radix) {
        return Err(STATUS_INVALID_INPUT);
    }
    let (neg, digits) = match text.first() {
        Some(b'+') => (false, &text[1..]),
        Some(b'-') => (true, &text[1..]),
        _ => (false, text),
    };
    let (radix, digits) = if radix != 0 {
        (radix as u64, digits)
    } else {
        match digits {
            [b'0', b'x' | b'X', rest @ ..] => (16, rest),
            [b'0', b'o' | b'O', rest @ ..] => (8, rest),
            [b'0', b'b' | b'B', rest @ ..] => (2, rest),
            _ => (10, digits),
        }
    };
    if digits.is_empty() {
        return Err(STATUS_INVALID_DATA);
    }
    for &c in digits {
        let d = match c {
            b'0'..=b'9' => (c - b'0') as u64,
            b'a'..=b'z' => (c - b'a') as u64 + 10,
            b'A'..=b'Z' => (c - b'A') as u64 + 10,
            _ => return Err(STATUS_INVALID_DATA),
        };
        if d >= radix {
            return Err(STATUS_INVALID_DATA);
        }
    }
    let mut acc: u128 = 0;
    let limit: u128 = if neg { 1u128 << 63 } else { (1u128 << 63) - 1 };
    for &c in digits {
        let d = match c {
            b'0'..=b'9' => (c - b'0') as u128,
            b'a'..=b'z' => (c - b'a') as u128 + 10,
            _ => (c - b'A') as u128 + 10,
        };
        acc = acc * radix as u128 + d;
        if acc > limit {
            return Err(STATUS_OUT_OF_RANGE);
        }
    }
    Ok(if neg {
        (acc as i128).wrapping_neg() as i64
    } else {
        acc as i64
    })
}

/// `Numbers.parse_float` (decimal and exponent syntax only).
pub fn parse_float(text: &[u8]) -> Result<f64, u8> {
    if let Some(v) = parse_float_exact(text) {
        return Ok(v);
    }
    match text {
        b"NaN" => return Ok(f64::NAN),
        b"Infinity" | b"+Infinity" => return Ok(f64::INFINITY),
        b"-Infinity" => return Ok(f64::NEG_INFINITY),
        _ => {}
    }
    if !float_syntax(text) {
        return Err(STATUS_INVALID_DATA);
    }
    // SAFETY: `float_syntax` accepted only ASCII digits, signs, `.` and `e`.
    let s = unsafe { core::str::from_utf8_unchecked(text) };
    match s.parse::<f64>() {
        Ok(v) if v.is_infinite() => Err(STATUS_OUT_OF_RANGE),
        Ok(v) => Ok(v),
        Err(_) => Err(STATUS_INVALID_DATA),
    }
}

/// The value of a decimal literal whose mantissa is at most 2^53 and whose power of ten is at
/// most 22 in magnitude, in one pass over the text: both operands are exact binary64 values, so
/// the one multiplication or division rounds correctly (Clinger's fast path). Any other text,
/// valid or not, is left to the general parser.
fn parse_float_exact(t: &[u8]) -> Option<f64> {
    const POW10: [f64; 23] = [
        1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16,
        1e17, 1e18, 1e19, 1e20, 1e21, 1e22,
    ];
    let mut i = 0;
    let negative = match t.first()? {
        b'-' => {
            i = 1;
            true
        }
        b'+' => {
            i = 1;
            false
        }
        _ => false,
    };
    let (mut mantissa, mut digits, mut exp) = (0u64, 0u32, 0i32);
    let start = i;
    while let Some(d) = t.get(i).filter(|c| c.is_ascii_digit()) {
        mantissa = mantissa * 10 + u64::from(d - b'0');
        digits += 1;
        i += 1;
        if digits > 19 {
            return None;
        }
    }
    if i == start {
        return None;
    }
    if t.get(i) == Some(&b'.') {
        i += 1;
        let fraction = i;
        while let Some(d) = t.get(i).filter(|c| c.is_ascii_digit()) {
            mantissa = mantissa * 10 + u64::from(d - b'0');
            digits += 1;
            exp -= 1;
            i += 1;
            if digits > 19 {
                return None;
            }
        }
        if i == fraction {
            return None;
        }
    }
    if matches!(t.get(i), Some(b'e' | b'E')) {
        i += 1;
        let down = t.get(i) == Some(&b'-');
        if down || t.get(i) == Some(&b'+') {
            i += 1;
        }
        let first = i;
        let mut e = 0i32;
        while let Some(d) = t.get(i).filter(|c| c.is_ascii_digit()) {
            e = e * 10 + i32::from(d - b'0');
            i += 1;
            if e > 999 {
                return None;
            }
        }
        if i == first {
            return None;
        }
        exp += if down { -e } else { e };
    }
    if i != t.len() || mantissa > 1 << 53 || !(-22..=22).contains(&exp) {
        return None;
    }
    let v = mantissa as f64;
    let v = if exp < 0 {
        v / POW10[(-exp) as usize]
    } else {
        v * POW10[exp as usize]
    };
    Some(if negative { -v } else { v })
}

/// `^[+-]?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$`
fn float_syntax(t: &[u8]) -> bool {
    let mut i = 0;
    if i < t.len() && (t[i] == b'+' || t[i] == b'-') {
        i += 1;
    }
    let digits = |i: &mut usize| {
        let s = *i;
        while *i < t.len() && t[*i].is_ascii_digit() {
            *i += 1;
        }
        *i > s
    };
    if !digits(&mut i) {
        return false;
    }
    if i < t.len() && t[i] == b'.' {
        i += 1;
        if !digits(&mut i) {
            return false;
        }
    }
    if i < t.len() && (t[i] == b'e' || t[i] == b'E') {
        i += 1;
        if i < t.len() && (t[i] == b'+' || t[i] == b'-') {
            i += 1;
        }
        if !digits(&mut i) {
            return false;
        }
    }
    i == t.len()
}

/// The text of one float: a sign, at most 17 digits, up to 20 zeros or six leading zeros, a point,
/// or `e`, a sign and three exponent digits all fit in 40 bytes.
pub struct FloatText {
    bytes: [u8; 40],
    len: usize,
}

impl FloatText {
    fn new() -> FloatText {
        FloatText {
            bytes: [0; 40],
            len: 0,
        }
    }

    pub fn as_slice(&self) -> &[u8] {
        &self.bytes[..self.len]
    }
}

/// `Float.to_string`.
pub fn float_to_string(v: f64) -> Vec<u8> {
    float_text(v).as_slice().to_vec()
}

/// `Float.to_string` without an allocation.
pub fn float_text(v: f64) -> FloatText {
    let mut out = FloatText::new();
    // SAFETY: `written` passes the buffer's own pointer and length.
    out.len = written(&mut out.bytes, |bytes, capacity, length| unsafe {
        msrt_fmt_float(v, bytes, capacity, length)
    });
    out
}

/// `Float32.to_string`: the shortest digits that round-trip through binary32.
pub fn float32_text(v: f64) -> FloatText {
    let mut out = FloatText::new();
    // SAFETY: as in `float_text`.
    out.len = written(&mut out.bytes, |bytes, capacity, length| unsafe {
        msrt_fmt_float32(v, bytes, capacity, length)
    });
    out
}

/// `Float32.to_string` as a vector.
pub fn float32_to_string(v: f64) -> Vec<u8> {
    float32_text(v).as_slice().to_vec()
}

/// `to_precision` (`'g'`, minimum 1), `to_exponential` (`'e'`), `to_fixed` (`'f'`).
/// Returns `None` when `digits` is outside `minimum..=100`.
pub fn float_precision(v: f64, format: u8, digits: i64, minimum: i64) -> Option<Vec<u8>> {
    if digits < minimum || digits > 100 {
        return None;
    }
    let mut buf = [0u8; 160];
    // SAFETY: `written` passes the buffer's own pointer and length.
    let n = written(&mut buf, |out, capacity, length| unsafe {
        msrt_fmt_float_precision(v, format, digits, out, capacity, length)
    });
    Some(buf[..n].to_vec())
}

// ---------------------------------------------------------------------------
// Exported natives: `@std/math` and the Int / Float receiver operations
// ---------------------------------------------------------------------------

/// `Numbers.parse_int(text, radix)`: status, with the value written to `out` only on success.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_numbers_parse_int(
    text: *const StrVal,
    radix: i64,
    out: *mut i64,
) -> u8 {
    // SAFETY: the caller passes a live string and a writable out.
    match parse_int_radix(unsafe { crate::string::bytes(text) }, radix) {
        Ok(v) => {
            // SAFETY: as above.
            unsafe { *out = v };
            STATUS_OK
        }
        Err(status) => status,
    }
}

/// `Numbers.parse_float(text)`.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_numbers_parse_float(text: *const StrVal, out: *mut f64) -> u8 {
    // SAFETY: the caller passes a live string and a writable out.
    match parse_float(unsafe { crate::string::bytes(text) }) {
        Ok(v) => {
            // SAFETY: as above.
            unsafe { *out = v };
            STATUS_OK
        }
        Err(status) => status,
    }
}

/// The error message for a number status code (`STATUS_INVALID_INPUT`, `_INVALID_DATA`, `_OUT_OF_RANGE`).
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_numbers_error_message(status: u8, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { out.write(msrt_numbers_error_message_val(status)) }
}

unsafe fn msrt_numbers_error_message_val(status: u8) -> StrVal {
    crate::string::from_bytes(match status {
        STATUS_INVALID_INPUT => b"number: invalid input",
        STATUS_INVALID_DATA => b"number: invalid data",
        STATUS_OUT_OF_RANGE => b"number: value out of range",
        _ => b"number: operation failed",
    })
}

unsafe fn precision_out(
    v: f64,
    format: u8,
    digits: i64,
    minimum: i64,
    name: &str,
    out: *mut StrVal,
) {
    let Some(text) = float_precision(v, format, digits, minimum) else {
        crate::fault::fault_fmt(format_args!(
            "{name}: digits must be at least {minimum} and at most 100, found {digits}"
        ));
    };
    // SAFETY: the caller passes a writable out.
    unsafe { *out = crate::string::from_buf(text) };
}

/// `Float.to_precision(digits)`: `digits` in `1..=100`, otherwise a fault.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_float_to_precision(v: f64, digits: i64, out: *mut StrVal) {
    // SAFETY: forwarded caller contract.
    unsafe { precision_out(v, b'g', digits, 1, "to_precision", out) }
}

/// `Float.to_exponential(digits)`: `digits` in `0..=100`, otherwise a fault.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_float_to_exponential(v: f64, digits: i64, out: *mut StrVal) {
    // SAFETY: forwarded caller contract.
    unsafe { precision_out(v, b'e', digits, 0, "to_exponential", out) }
}

/// `Float.to_fixed(digits)`: `digits` in `0..=100`, otherwise a fault.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_float_to_fixed(v: f64, digits: i64, out: *mut StrVal) {
    // SAFETY: forwarded caller contract.
    unsafe { precision_out(v, b'f', digits, 0, "to_fixed", out) }
}

/// `UInt64./`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_uint_div(a: i64, b: i64) -> i64 {
    if b == 0 {
        crate::fault::msrt_fault_div_zero();
    }
    ((a as u64) / (b as u64)) as i64
}

/// `UInt64.%`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_uint_rem(a: i64, b: i64) -> i64 {
    if b == 0 {
        crate::fault::msrt_fault_rem_zero();
    }
    ((a as u64) % (b as u64)) as i64
}

/// `UInt64` in decimal digits.
pub fn format_u64(v: u64, tmp: &mut [u8; 20]) -> &[u8] {
    // SAFETY: `written` passes the buffer's own pointer and length.
    let n = written(tmp, |out, capacity, length| unsafe {
        msrt_fmt_u64(v, out, capacity, length)
    });
    &tmp[..n]
}

/// `UInt64.to_string_radix`.
pub fn format_radix_u64(v: u64, radix: u32, out: &mut Vec<u8>) {
    let mut tmp = [0u8; 65];
    // SAFETY: `written` passes the buffer's own pointer and length.
    let n = written(&mut tmp, |out, capacity, length| unsafe {
        msrt_fmt_radix(v, radix, 0, out, capacity, length)
    });
    out.extend_from_slice(&tmp[..n]);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::string::{String, ToString};

    fn s(b: Vec<u8>) -> String {
        String::from_utf8(b.as_slice().to_vec()).unwrap()
    }

    #[test]
    #[allow(unused_unsafe)]
    fn uint64_helpers() {
        // SAFETY: the C numeric natives take and return plain values.
        unsafe {
            let big = u64::MAX as i64;
            assert_eq!(msrt_uint_compare(big, 1), 1);
            assert_eq!(msrt_uint_compare(1, big), -1);
            assert_eq!(msrt_uint_div(big, 2) as u64, u64::MAX / 2);
            assert_eq!(msrt_uint_rem(big, 10), 5);
            assert_eq!(msrt_uint_to_float(big), u64::MAX as f64);
            let mut tmp = [0u8; 20];
            assert_eq!(format_u64(u64::MAX, &mut tmp), b"18446744073709551615");
            let mut out = Vec::new();
            format_radix_u64(u64::MAX, 16, &mut out);
            assert_eq!(out, b"ffffffffffffffff");
        }
    }

    #[test]
    #[allow(unused_unsafe)]
    fn uint64_to_float32_rounds_once() {
        // SAFETY: the C numeric natives take and return plain values.
        unsafe {
            let cases = [
                (4_611_686_293_305_294_849u64, 4_611_686_568_183_201_792.0),
                (9_223_372_586_610_589_695, 9_223_372_036_854_775_808.0),
                (9_223_372_586_610_589_696, 9_223_372_036_854_775_808.0),
                (9_223_372_586_610_589_697, 9_223_373_136_366_403_584.0),
                (9_223_373_686_122_217_471, 9_223_373_136_366_403_584.0),
                (9_223_373_686_122_217_472, 9_223_374_235_878_031_360.0),
                (9_223_373_686_122_217_473, 9_223_374_235_878_031_360.0),
                (0, 0.0),
                (16_777_217, 16_777_216.0),
                (u64::MAX, 18_446_744_073_709_551_616.0),
            ];
            for (input, expected) in cases {
                assert_eq!(msrt_uint_to_float32(input as i64), expected, "{input}");
            }
        }
    }

    #[test]
    fn int_formatting_and_parsing() {
        let _g = crate::testutil::lock();
        let mut tmp = [0u8; 20];
        assert_eq!(format_i64(i64::MIN, &mut tmp), b"-9223372036854775808");
        assert_eq!(format_i64(0, &mut tmp), b"0");
        let mut b = Vec::new();
        format_radix(-255, 16, &mut b);
        format_radix(i64::MIN, 2, &mut b);
        assert_eq!(
            s(b),
            "-ff-1000000000000000000000000000000000000000000000000000000000000000"
        );
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
        assert_eq!(parse_int_radix(b"FF", 16), Ok(255));
        assert_eq!(parse_int_radix(b"-8000000000000000", 16), Ok(i64::MIN));
        assert_eq!(
            parse_int_radix(b"8000000000000000", 16),
            Err(STATUS_OUT_OF_RANGE)
        );
        assert_eq!(parse_int_radix(b"12", 2), Err(STATUS_INVALID_DATA));
        assert_eq!(parse_int_radix(b"1", 1), Err(STATUS_INVALID_INPUT));
        assert_eq!(parse_int_radix(b"-0x1f", 0), Ok(-31));
        assert_eq!(parse_int_radix(b"0B101", 0), Ok(5));
        assert_eq!(parse_int_radix(b"017", 0), Ok(17));
        assert_eq!(parse_int_radix(b"0x", 0), Err(STATUS_INVALID_DATA));
        assert_eq!(parse_int_radix(b"0x1f", 10), Err(STATUS_INVALID_DATA));
    }

    #[test]
    #[allow(clippy::excessive_precision)] // exactly representable tie values
    fn float_ties_choose_the_even_final_digit() {
        let _g = crate::testutil::lock();
        // 29501041598734.3125 sits exactly between two 17-digit decimals.
        assert_eq!(float_to_string(29501041598734.3125), b"29501041598734.312");
        assert_eq!(float_to_string(1313322917213848.25), b"1313322917213848.2");
        assert_eq!(float32_to_string(3423159.25), b"3423159.2");
        assert_eq!(float32_to_string(4311.78125), b"4311.7812");
        assert_eq!(float32_to_string(-4526.03125), b"-4526.0312");
    }

    #[test]
    fn float_strings_render_shortest() {
        let _g = crate::testutil::lock();
        let cases: [(f64, &str); 14] = [
            (0.0, "0"),
            (-0.0, "-0"),
            (1.0, "1"),
            (-2.5, "-2.5"),
            (0.1, "0.1"),
            (123456789.0, "123456789"),
            (1e20, "100000000000000000000"),
            (1e21, "1e+21"),
            (1.5e-7, "1.5e-7"),
            (0.000001, "0.000001"),
            (1e-7, "1e-7"),
            (f64::MAX, "1.7976931348623157e+308"),
            (5e-324, "5e-324"),
            (1.0 / 3.0, "0.3333333333333333"),
        ];
        for (v, want) in cases {
            assert_eq!(s(float_to_string(v)), want, "{v:e}");
        }
        assert_eq!(s(float_to_string(f64::NAN)), "NaN");
        assert_eq!(s(float_to_string(f64::NEG_INFINITY)), "-Infinity");
    }

    #[test]
    fn float_precision_forms() {
        let _g = crate::testutil::lock();
        let f = |v, k, d, m| float_precision(v, k, d, m).map(s);
        assert_eq!(f(3.14158, b'f', 2, 0).as_deref(), Some("3.14"));
        assert_eq!(f(2.5, b'f', 0, 0).as_deref(), Some("2"));
        assert_eq!(f(1234.5678, b'e', 2, 0).as_deref(), Some("1.23e+3"));
        assert_eq!(f(1234.5678, b'g', 6, 1).as_deref(), Some("1234.57"));
        assert_eq!(f(0.000012345, b'g', 3, 1).as_deref(), Some("0.0000123"));
        assert_eq!(f(1e10, b'g', 3, 1).as_deref(), Some("1.00e+10"));
        assert_eq!(f(1.0, b'g', 0, 1), None);
        assert_eq!(f(1.0, b'f', 101, 0), None);
        let _ = 1.to_string();
    }

    #[test]
    #[cfg_attr(
        miri,
        ignore = "an exhaustive sweep that takes over 200 s interpreted; native CI runs it"
    )]
    fn float_precision_matches_previous_formatting() {
        let _g = crate::testutil::lock();
        // Independent oracle: the old path formats the original binary value
        // again, using the exponent of its rounded scientific representation.
        let previous = |value: f64, digits: usize| {
            if !value.is_finite() {
                return float_to_string(value);
            }
            let scientific = format!("{:.*e}", digits - 1, value);
            let (mantissa, exponent) = scientific.split_once('e').unwrap();
            let exponent: i64 = exponent.parse().unwrap();
            if exponent >= -6 && exponent < digits as i64 {
                return format!("{:.*}", (digits as i64 - exponent - 1) as usize, value)
                    .into_bytes();
            }
            format!("{mantissa}e{exponent:+}").into_bytes()
        };
        let check = |value| {
            for digits in 1..=100 {
                assert_eq!(
                    float_precision(value, b'g', digits, 1).unwrap(),
                    previous(value, digits as usize),
                    "bits={:016x} digits={digits}",
                    value.to_bits()
                );
            }
        };
        for value in [
            0.0,
            -0.0,
            1.0,
            -1.0,
            9.5,
            9.95,
            99.5,
            999.5,
            1e-6,
            1e-7,
            1e20,
            1e21,
            f64::MIN_POSITIVE,
            f64::MAX,
            f64::from_bits(1),
            f64::NAN,
            f64::INFINITY,
            f64::NEG_INFINITY,
        ] {
            check(value);
            if value.is_finite() && value > 0.0 {
                check(f64::from_bits(value.to_bits() - 1));
                check(f64::from_bits(value.to_bits() + 1));
                check(-value);
            }
        }
        let mut bits = 0x32e5_81ac_092f_8bd7u64;
        for _ in 0..2048 {
            bits = bits.wrapping_mul(6364136223846793005).wrapping_add(1);
            check(f64::from_bits(bits));
        }
        for value in [0.0, -0.0, 1.25, f64::NAN, f64::INFINITY] {
            for digits in [i64::MIN, 0, 101, i64::MAX] {
                assert_eq!(float_precision(value, b'g', digits, 1), None);
            }
        }
    }

    #[test]
    #[allow(unused_unsafe)]
    fn exported_numbers_natives() {
        // SAFETY: the C numeric natives take and return plain values.
        unsafe {
            let _g = crate::testutil::lock();
            let st = |t: &[u8]| -> *const ms_rt_abi::StrVal {
                Box::leak(Box::new(crate::string::from_bytes(t)))
            };
            let mut n = 0i64;
            // SAFETY: live strings and writable outs.
            unsafe {
                assert_eq!(msrt_numbers_parse_int(st(b"-ff"), 16, &mut n), STATUS_OK);
                assert_eq!(n, -255);
                assert_eq!(
                    msrt_numbers_parse_int(st(b"1"), 40, &mut n),
                    STATUS_INVALID_INPUT
                );
                let mut f = 0f64;
                assert_eq!(msrt_numbers_parse_float(st(b"2.5e1"), &mut f), STATUS_OK);
                assert_eq!(f, 25.0);
                assert_eq!(
                    msrt_numbers_parse_float(st(b"1e999"), &mut f),
                    STATUS_OUT_OF_RANGE
                );
                let mut out = crate::string::NO_STR;
                msrt_float_to_fixed(1.005, 2, &mut out);
                assert_eq!(crate::string::bytes(&out), b"1.00");
                assert_eq!(msrt_float_truncate_to_int(-2.9, &mut n), 1);
                assert_eq!(n, -2);
                assert_eq!(msrt_float_truncate_to_int(9223372036854775808.0, &mut n), 0);
                assert_eq!(msrt_float_truncate_to_int(f64::NAN, &mut n), 0);
            }
            assert_eq!(msrt_float_compare(f64::NAN, 1.0), 1);
            assert_eq!(msrt_float_compare(1.0, f64::NAN), -1);
            assert_eq!(msrt_float_compare(f64::NAN, f64::NAN), 0);
            assert_eq!(msrt_float_compare(-0.0, 0.0), 0);
            assert_eq!(msrt_float_compare(2.0, 1.0), 1);
            assert_eq!(msrt_int_compare(1, 2), -1);
            let mut m = crate::string::NO_STR;
            // SAFETY: `m` is writable.
            unsafe { msrt_numbers_error_message(STATUS_OUT_OF_RANGE, &mut m) };
            // SAFETY: live string.
            assert_eq!(
                unsafe { crate::string::bytes(&m) },
                b"number: value out of range"
            );
        }
    }

    #[test]
    #[cfg_attr(
        miri,
        ignore = "an exhaustive sweep that takes over 200 s interpreted; native CI runs it"
    )]
    fn float_parsing() {
        let _g = crate::testutil::lock();
        // The exact fast path agrees with the standard parser wherever it answers.
        let mut x = 12345u64;
        let mut answered = 0;
        for _ in 0..20000 {
            x = x
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            let whole = (x >> 40) % 100_000_000_000;
            let frac = (x >> 8) % 1_000_000_000_000;
            let e = ((x >> 3) % 60) as i32 - 30;
            let sign = ["", "-", "+"][(x % 3) as usize];
            let texts = [
                std::format!("{sign}{whole}"),
                std::format!("{sign}{whole}.{frac}"),
                std::format!("{sign}{whole}.{frac}e{e}"),
                std::format!("{sign}{whole}E{e}"),
            ];
            for t in texts {
                if let Some(v) = parse_float_exact(t.as_bytes()) {
                    assert_eq!(v.to_bits(), t.parse::<f64>().unwrap().to_bits(), "{t}");
                    answered += 1;
                }
            }
        }
        assert!(answered > 20000, "{answered}");
        for t in [
            "-0",
            "-0.0",
            "0.1",
            "9007199254740992",
            "9007199254740993",
            "1e22",
            "1e23",
            "5e-22",
            "5e-23",
            "123456789012345678901",
        ] {
            if let Some(v) = parse_float_exact(t.as_bytes()) {
                assert_eq!(v.to_bits(), t.parse::<f64>().unwrap().to_bits(), "{t}");
            }
        }
        for t in [
            "", "+", "-", ".5", "5.", "1e", "1e+", "e5", "1.5x", " 1", "1 ", "0x10", "1_0",
        ] {
            assert_eq!(parse_float_exact(t.as_bytes()), None, "{t:?}");
        }
        assert_eq!(parse_float(b"1.5e3"), Ok(1500.0));
        assert_eq!(parse_float(b"-0"), Ok(-0.0));
        assert_eq!(parse_float(b"1e400"), Err(STATUS_OUT_OF_RANGE));
        assert_eq!(parse_float(b".5"), Err(STATUS_INVALID_DATA));
        assert_eq!(parse_float(b"1."), Err(STATUS_INVALID_DATA));
        assert_eq!(parse_float(b"inf"), Err(STATUS_INVALID_DATA));
        assert!(parse_float(b"NaN").unwrap().is_nan());
        assert_eq!(parse_float(b"+Infinity"), Ok(f64::INFINITY));
        assert_eq!(parse_float(b"+NaN"), Err(STATUS_INVALID_DATA));
        assert_eq!(parse_float(b"1e-400"), Ok(0.0));
    }
}
