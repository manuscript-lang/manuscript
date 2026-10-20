//! Int and Float formatting and parsing with Go-identical results.
use ms_rt_abi::{
    STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_OK, STATUS_OUT_OF_RANGE, StrObj,
};
use std::io::Write;

/// Formats `v` in decimal into `tmp`, returning the used tail.
pub fn format_i64(v: i64, tmp: &mut [u8; 20]) -> &[u8] {
    let mut n = v.unsigned_abs();
    let mut i = tmp.len();
    loop {
        i -= 1;
        tmp[i] = b'0' + (n % 10) as u8;
        n /= 10;
        if n == 0 {
            break;
        }
    }
    if v < 0 {
        i -= 1;
        tmp[i] = b'-';
    }
    &tmp[i..]
}

/// Appends `v` in decimal.
pub fn push_i64(out: &mut Vec<u8>, v: i64) {
    out.extend_from_slice(format_i64(v, &mut [0; 20]));
}

/// Lowercase radix formatting (`radix` in 2..=36).
pub fn format_radix(v: i64, radix: u32, out: &mut Vec<u8>) {
    let mut tmp = [0u8; 65];
    let mut i = tmp.len();
    let mut n = v.unsigned_abs();
    loop {
        i -= 1;
        let d = (n % radix as u64) as u8;
        tmp[i] = if d < 10 { b'0' + d } else { b'a' + d - 10 };
        n /= radix as u64;
        if n == 0 {
            break;
        }
    }
    if v < 0 {
        i -= 1;
        tmp[i] = b'-';
    }
    out.extend_from_slice(&tmp[i..]);
}

/// `String.parse_int`: optional sign, ASCII digits only; overflow is `None`.
pub fn parse_int_decimal(text: &[u8]) -> Option<i64> {
    let (neg, digits) = match text.first() {
        Some(b'+') => (false, &text[1..]),
        Some(b'-') => (true, &text[1..]),
        _ => (false, text),
    };
    if digits.is_empty() {
        return None;
    }
    let mut acc: i64 = 0;
    for &c in digits {
        if !c.is_ascii_digit() {
            return None;
        }
        let d = (c - b'0') as i64;
        // Accumulate negatively so i64::MIN is representable.
        acc = acc.checked_mul(10)?.checked_sub(d)?;
    }
    if neg { Some(acc) } else { acc.checked_neg() }
}

/// `Numbers.parse_int`: Err carries the status code.
pub fn parse_int_radix(text: &[u8], radix: i64) -> Result<i64, u8> {
    if !(2..=36).contains(&radix) {
        return Err(STATUS_INVALID_INPUT);
    }
    let radix = radix as u64;
    let (neg, digits) = match text.first() {
        Some(b'+') => (false, &text[1..]),
        Some(b'-') => (true, &text[1..]),
        _ => (false, text),
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

/// `Numbers.parse_float` (Go's accepted syntax only).
pub fn parse_float(text: &[u8]) -> Result<f64, u8> {
    match text {
        b"NaN" => return Ok(f64::NAN),
        b"Infinity" => return Ok(f64::INFINITY),
        b"-Infinity" => return Ok(f64::NEG_INFINITY),
        _ => {}
    }
    if !float_syntax(text) {
        return Err(STATUS_INVALID_DATA);
    }
    let s = core::str::from_utf8(text).map_err(|_| STATUS_INVALID_DATA)?;
    match s.parse::<f64>() {
        Ok(v) if v.is_infinite() => Err(STATUS_OUT_OF_RANGE),
        Ok(v) => Ok(v),
        Err(_) => Err(STATUS_INVALID_DATA),
    }
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

/// Shortest round-trip digits and decimal exponent of a finite positive `v`.
fn shortest(v: f64) -> (Vec<u8>, i32) {
    let mut s = Vec::new();
    let _ = write!(s, "{v:e}");
    let text = s.as_slice();
    let epos = text.iter().position(|&c| c == b'e').unwrap_or(text.len());
    let mut digits = Vec::new();
    for &c in &text[..epos] {
        if c != b'.' {
            digits.push(c);
        }
    }
    let exp = parse_int_decimal(&text[(epos + 1).min(text.len())..]).unwrap_or(0) as i32;
    even_tie(v, &mut digits);
    (digits, exp)
}

/// Rust's shortest digits resolve an exact tie between two candidates upward; Go's resolve it to
/// the even digit. When `v` lies exactly halfway between `digits` and `digits` minus one in the
/// last place, and the lower candidate ends even, the lower one is the Go answer.
fn even_tie(v: f64, digits: &mut Vec<u8>) {
    let n = digits.len();
    let last = digits.as_slice()[n - 1];
    if n < 2 || last & 1 == 0 {
        return;
    }
    let mut exact = Vec::new();
    let _ = write!(exact, "{:.*e}", n + 30, v);
    let text = exact.as_slice();
    let epos = text.iter().position(|&c| c == b'e').unwrap_or(text.len());
    let mantissa: Vec<u8> = {
        let mut m = Vec::new();
        for &c in &text[..epos] {
            if c != b'.' {
                m.push(c);
            }
        }
        m
    };
    let m = mantissa.as_slice();
    // Digit n+1 is a 5 followed only by zeros: an exact tie, and `digits` rounded it up.
    let tie = m.len() > n && m[n] == b'5' && m[n + 1..].iter().all(|&c| c == b'0');
    if tie && m[..n - 1] == digits.as_slice()[..n - 1] && m[n - 1] == last - 1 {
        let mut lower = Vec::new();
        lower.extend_from_slice(&m[..n]);
        digits.clear();
        digits.extend_from_slice(lower.as_slice());
    }
}

/// Go-style rendering of decimal digits (see `renderDecimal` in numeric.go).
fn render_decimal(digits: &[u8], exponent: i32, negative: bool, out: &mut Vec<u8>) {
    let mut n = digits.len();
    while n > 1 && digits[n - 1] == b'0' {
        n -= 1;
    }
    let digits = &digits[..n];
    if negative {
        out.push(b'-');
    }
    if (-6..=20).contains(&exponent) {
        let point = exponent + 1;
        if point <= 0 {
            out.extend_from_slice(b"0.");
            for _ in 0..-point {
                out.push(b'0');
            }
            out.extend_from_slice(digits);
        } else if point as usize >= digits.len() {
            out.extend_from_slice(digits);
            for _ in 0..(point as usize - digits.len()) {
                out.push(b'0');
            }
        } else {
            out.extend_from_slice(&digits[..point as usize]);
            out.push(b'.');
            out.extend_from_slice(&digits[point as usize..]);
        }
        return;
    }
    out.push(digits[0]);
    if digits.len() > 1 {
        out.push(b'.');
        out.extend_from_slice(&digits[1..]);
    }
    out.push(b'e');
    if exponent >= 0 {
        out.push(b'+');
    }
    push_i64(out, exponent as i64);
}

/// `Float.to_string`.
pub fn float_to_string(v: f64) -> Vec<u8> {
    let mut out = Vec::new();
    if v.is_nan() {
        out.extend_from_slice(b"NaN");
    } else if v.is_infinite() {
        out.extend_from_slice(if v > 0.0 {
            b"Infinity".as_slice()
        } else {
            b"-Infinity".as_slice()
        });
    } else if v == 0.0 {
        out.extend_from_slice(if v.is_sign_negative() {
            b"-0".as_slice()
        } else {
            b"0".as_slice()
        });
    } else if v.abs() < 9.007_199_254_740_992e15 && v == (v as i64) as f64 {
        // Integral values below 2^53: the digits are the integer itself.
        let mut tmp = [0u8; 20];
        let digits = format_i64(v.abs() as i64, &mut tmp);
        render_decimal(digits, digits.len() as i32 - 1, v < 0.0, &mut out);
    } else {
        let (digits, exp) = shortest(v.abs());
        render_decimal(digits.as_slice(), exp, v < 0.0, &mut out);
    }
    out
}

/// `to_precision` (`'g'`, minimum 1), `to_exponential` (`'e'`), `to_fixed` (`'f'`).
/// Returns `None` when `digits` is outside `minimum..=100`.
pub fn float_precision(v: f64, format: u8, digits: i64, minimum: i64) -> Option<Vec<u8>> {
    if digits < minimum || digits > 100 {
        return None;
    }
    let digits = digits as usize;
    if v.is_nan() || v.is_infinite() {
        return Some(float_to_string(v));
    }
    let mut out = Vec::new();
    if format == b'f' {
        if v.abs() >= 1e21 {
            return Some(float_to_string(v));
        }
        let _ = write!(out, "{v:.digits$}");
        return Some(out);
    }
    let mdigits = if format == b'g' { digits - 1 } else { digits };
    let mut text = Vec::new();
    let _ = write!(text, "{v:.mdigits$e}");
    let t = text.as_slice();
    let epos = t.iter().position(|&c| c == b'e').unwrap_or(t.len());
    let e = parse_int_decimal(&t[epos + 1..]).unwrap_or(0);
    if format == b'g' && e >= -6 && e < digits as i64 {
        let frac = (digits as i64 - e - 1) as usize;
        let _ = write!(out, "{v:.frac$}");
        return Some(out);
    }
    out.extend_from_slice(&t[..epos]);
    out.push(b'e');
    if e >= 0 {
        out.push(b'+');
    }
    push_i64(&mut out, e);
    Some(out)
}

// ---------------------------------------------------------------------------
// Exported natives: `@std/numbers` and the Int / Float receiver operations
// ---------------------------------------------------------------------------

/// `Numbers.parse_int(text, radix)`: status, with the value written to `out` only on success.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_numbers_parse_int(
    text: *const StrObj,
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
pub unsafe extern "C-unwind" fn msrt_numbers_parse_float(text: *const StrObj, out: *mut f64) -> u8 {
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

/// `NumberError.message()` for a status code (`STATUS_INVALID_INPUT`, `_INVALID_DATA`, `_OUT_OF_RANGE`).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_numbers_error_message(status: u8) -> *mut StrObj {
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
    out: *mut *mut StrObj,
) -> u8 {
    match float_precision(v, format, digits, minimum) {
        Some(text) => {
            // SAFETY: the caller passes a writable out.
            unsafe { *out = crate::string::from_buf(text) };
            STATUS_OK
        }
        None => STATUS_INVALID_INPUT,
    }
}

/// `Float.to_precision(digits)`: `digits` in `1..=100`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_float_to_precision(
    v: f64,
    digits: i64,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: forwarded caller contract.
    unsafe { precision_out(v, b'g', digits, 1, out) }
}

/// `Float.to_exponential(digits)`: `digits` in `0..=100`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_float_to_exponential(
    v: f64,
    digits: i64,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: forwarded caller contract.
    unsafe { precision_out(v, b'e', digits, 0, out) }
}

/// `Float.to_fixed(digits)`: `digits` in `0..=100`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_float_to_fixed(
    v: f64,
    digits: i64,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: forwarded caller contract.
    unsafe { precision_out(v, b'f', digits, 0, out) }
}

/// `Float.truncate_to_int()`: present flag, value through `out` only when present.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_float_truncate_to_int(v: f64, out: *mut i64) -> u8 {
    const LIMIT: f64 = 9_223_372_036_854_775_808.0;
    if !(-LIMIT..LIMIT).contains(&v) {
        return 0;
    }
    // SAFETY: the caller passes a writable out.
    unsafe { *out = v as i64 };
    1
}

/// `Float.compare`: a total order in which `-0.0 == 0.0` and NaN is equal to itself and sorts last.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_float_compare(a: f64, b: f64) -> i64 {
    if a.is_nan() || b.is_nan() {
        return a.is_nan() as i64 - b.is_nan() as i64;
    }
    (a > b) as i64 - (a < b) as i64
}

/// `Int.compare`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_int_compare(a: i64, b: i64) -> i64 {
    (a > b) as i64 - (a < b) as i64
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::string::{String, ToString};

    fn s(b: Vec<u8>) -> String {
        String::from_utf8(b.as_slice().to_vec()).unwrap()
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
    }

    #[test]
    fn float_strings_follow_go_rules() {
        let _g = crate::testutil::lock();
        let cases: [(f64, &str); 16] = [
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
            // Exact ties between two shortest candidates go to the even digit, as in Go.
            (1_312_898_019_840_000.2, "1312898019840000.2"),
            (1_312_898_019_840_000.8, "1312898019840000.8"),
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
    fn exported_numbers_natives() {
        let _g = crate::testutil::lock();
        let st = crate::string::from_bytes;
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
            let mut out: *mut StrObj = core::ptr::null_mut();
            assert_eq!(msrt_float_to_fixed(1.005, 2, &mut out), STATUS_OK);
            assert_eq!(crate::string::bytes(out), b"1.00");
            assert_eq!(
                msrt_float_to_precision(1.0, 0, &mut out),
                STATUS_INVALID_INPUT
            );
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
        let m = msrt_numbers_error_message(STATUS_OUT_OF_RANGE);
        // SAFETY: live string.
        assert_eq!(
            unsafe { crate::string::bytes(m) },
            b"number: value out of range"
        );
    }

    #[test]
    fn float_parsing() {
        let _g = crate::testutil::lock();
        assert_eq!(parse_float(b"1.5e3"), Ok(1500.0));
        assert_eq!(parse_float(b"-0"), Ok(-0.0));
        assert_eq!(parse_float(b"1e400"), Err(STATUS_OUT_OF_RANGE));
        assert_eq!(parse_float(b".5"), Err(STATUS_INVALID_DATA));
        assert_eq!(parse_float(b"1."), Err(STATUS_INVALID_DATA));
        assert_eq!(parse_float(b"inf"), Err(STATUS_INVALID_DATA));
        assert!(parse_float(b"NaN").unwrap().is_nan());
        assert_eq!(parse_float(b"1e-400"), Ok(0.0));
    }
}
