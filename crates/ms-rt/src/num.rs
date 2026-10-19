//! Int and Float formatting and parsing with Go-identical results.
use crate::buf::ByteBuf;
use core::fmt::Write;
use ms_rt_abi::{STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_OUT_OF_RANGE};

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

/// Lowercase radix formatting (`radix` in 2..=36).
pub fn format_radix(v: i64, radix: u32, out: &mut ByteBuf) {
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
    out.extend(&tmp[i..]);
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
fn shortest(v: f64) -> (ByteBuf, i32) {
    let mut s = ByteBuf::new();
    let _ = write!(s, "{v:e}");
    let text = s.as_slice();
    let epos = text.iter().position(|&c| c == b'e').unwrap_or(text.len());
    let mut digits = ByteBuf::new();
    for &c in &text[..epos] {
        if c != b'.' {
            digits.push(c);
        }
    }
    let exp = parse_int_decimal(&text[(epos + 1).min(text.len())..]).unwrap_or(0) as i32;
    (digits, exp)
}

/// Go-style rendering of decimal digits (see `renderDecimal` in numeric.go).
fn render_decimal(digits: &[u8], exponent: i32, negative: bool, out: &mut ByteBuf) {
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
            out.extend(b"0.");
            for _ in 0..-point {
                out.push(b'0');
            }
            out.extend(digits);
        } else if point as usize >= digits.len() {
            out.extend(digits);
            for _ in 0..(point as usize - digits.len()) {
                out.push(b'0');
            }
        } else {
            out.extend(&digits[..point as usize]);
            out.push(b'.');
            out.extend(&digits[point as usize..]);
        }
        return;
    }
    out.push(digits[0]);
    if digits.len() > 1 {
        out.push(b'.');
        out.extend(&digits[1..]);
    }
    out.push(b'e');
    if exponent >= 0 {
        out.push(b'+');
    }
    out.push_i64(exponent as i64);
}

/// `Float.to_string`.
pub fn float_to_string(v: f64) -> ByteBuf {
    let mut out = ByteBuf::new();
    if v.is_nan() {
        out.extend(b"NaN");
    } else if v.is_infinite() {
        out.extend(if v > 0.0 {
            b"Infinity".as_slice()
        } else {
            b"-Infinity".as_slice()
        });
    } else if v == 0.0 {
        out.extend(if v.is_sign_negative() {
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
pub fn float_precision(v: f64, format: u8, digits: i64, minimum: i64) -> Option<ByteBuf> {
    if digits < minimum || digits > 100 {
        return None;
    }
    let digits = digits as usize;
    if v.is_nan() || v.is_infinite() {
        return Some(float_to_string(v));
    }
    let mut out = ByteBuf::new();
    if format == b'f' {
        if v.abs() >= 1e21 {
            return Some(float_to_string(v));
        }
        let _ = write!(out, "{v:.digits$}");
        return Some(out);
    }
    let mdigits = if format == b'g' { digits - 1 } else { digits };
    let mut text = ByteBuf::new();
    let _ = write!(text, "{v:.mdigits$e}");
    let t = text.as_slice();
    let epos = t.iter().position(|&c| c == b'e').unwrap_or(t.len());
    let e = parse_int_decimal(&t[epos + 1..]).unwrap_or(0);
    if format == b'g' && e >= -6 && e < digits as i64 {
        let frac = (digits as i64 - e - 1) as usize;
        let _ = write!(out, "{v:.frac$}");
        return Some(out);
    }
    out.extend(&t[..epos]);
    out.push(b'e');
    if e >= 0 {
        out.push(b'+');
    }
    out.push_i64(e);
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::string::{String, ToString};

    fn s(b: ByteBuf) -> String {
        String::from_utf8(b.as_slice().to_vec()).unwrap()
    }

    #[test]
    fn int_formatting_and_parsing() {
        let _g = crate::testutil::lock();
        let mut tmp = [0u8; 20];
        assert_eq!(format_i64(i64::MIN, &mut tmp), b"-9223372036854775808");
        assert_eq!(format_i64(0, &mut tmp), b"0");
        let mut b = ByteBuf::new();
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
