//! Int and Float formatting and parsing with shortest round-trip output.
use core::fmt::Write as _;
use ms_rt_abi::{
    STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_OK, STATUS_OUT_OF_RANGE, StrVal,
};
use std::io::Write;

/// Formats `v` in decimal into `tmp`, returning the used tail.
pub fn format_i64(v: i64, tmp: &mut [u8; 20]) -> &[u8] {
    const PAIRS: &[u8; 200] = b"0001020304050607080910111213141516171819\
2021222324252627282930313233343536373839\
4041424344454647484950515253545556575859\
6061626364656667686970717273747576777879\
8081828384858687888990919293949596979899";
    let mut n = v.unsigned_abs();
    let mut i = tmp.len();
    while n >= 100 {
        let r = (n % 100) as usize * 2;
        n /= 100;
        i -= 2;
        tmp[i] = PAIRS[r];
        tmp[i + 1] = PAIRS[r + 1];
    }
    if n >= 10 {
        let r = n as usize * 2;
        i -= 2;
        tmp[i] = PAIRS[r];
        tmp[i + 1] = PAIRS[r + 1];
    } else {
        i -= 1;
        tmp[i] = b'0' + n as u8;
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
    core::str::from_utf8(text).ok()?.parse().ok()
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

/// `Numbers.parse_float` (decimal and exponent syntax only).
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

/// A positive finite binary64's shortest scientific form needs at most 17 digits, a decimal
/// point, `e`, an exponent sign and three exponent digits: 23 bytes. Binary32 is smaller.
#[derive(Default)]
struct Scientific {
    bytes: [u8; 32],
    len: usize,
}

impl Scientific {
    fn as_slice(&self) -> &[u8] {
        &self.bytes[..self.len]
    }
}

impl core::fmt::Write for Scientific {
    fn write_str(&mut self, text: &str) -> core::fmt::Result {
        let end = self.len + text.len();
        let target = self.bytes.get_mut(self.len..end).ok_or(core::fmt::Error)?;
        target.copy_from_slice(text.as_bytes());
        self.len = end;
        Ok(())
    }
}

/// Shortest round-trip digits and decimal exponent of a finite positive `v`.
fn shortest(v: f64) -> (Scientific, i32) {
    let mut s = Scientific::default();
    write!(s, "{v:e}").expect("shortest finite binary64 scientific form fits 32 bytes");
    split_scientific(s)
}

/// The same for a finite positive binary32 value.
fn shortest32(v: f32) -> (Scientific, i32) {
    let mut s = Scientific::default();
    write!(s, "{v:e}").expect("shortest finite binary32 scientific form fits 32 bytes");
    split_scientific(s)
}

fn split_scientific(mut s: Scientific) -> (Scientific, i32) {
    let text = s.as_slice();
    let epos = text.iter().position(|&c| c == b'e').unwrap_or(text.len());
    let exp = parse_int_decimal(&text[(epos + 1).min(text.len())..]).unwrap_or(0) as i32;
    let point = text[..epos].iter().position(|&c| c == b'.');
    s.len = epos;
    if let Some(point) = point {
        s.bytes.copy_within(point + 1..epos, point);
        s.len -= 1;
    }
    (s, exp)
}

/// Renders shortest decimal digits: plain notation for exponents in -6..=20, else scientific.
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

/// `Float32.to_string`: the shortest digits that round-trip through binary32.
pub fn float32_to_string(v: f64) -> Vec<u8> {
    let x = v as f32;
    if x.is_nan() || x.is_infinite() || x == 0.0 {
        return float_to_string(f64::from(x));
    }
    let mut out = Vec::new();
    let (digits, exp) = shortest32(x.abs());
    render_decimal(digits.as_slice(), exp, x < 0.0, &mut out);
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
        // Scientific formatting has already rounded all significant digits.
        // Move its decimal point without formatting the binary value again.
        let negative = t[0] == b'-';
        if negative {
            out.push(b'-');
        }
        let mantissa = &t[usize::from(negative)..epos];
        let point = e + 1;
        if point <= 0 {
            out.extend_from_slice(b"0.");
            out.resize(out.len() + (-point) as usize, b'0');
        }
        for (index, digit) in mantissa.iter().filter(|&&c| c != b'.').enumerate() {
            if point > 0 && index == point as usize {
                out.push(b'.');
            }
            out.push(*digit);
        }
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
// Exported natives: `@std/math` and the Int / Float receiver operations
// ---------------------------------------------------------------------------

/// `Numbers.parse_int(text, radix)`: status, with the value written to `out` only on success.
#[unsafe(no_mangle)]
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

/// `NumberError.message()` for a status code (`STATUS_INVALID_INPUT`, `_INVALID_DATA`, `_OUT_OF_RANGE`).
#[unsafe(no_mangle)]
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
pub unsafe extern "C-unwind" fn msrt_float_to_precision(v: f64, digits: i64, out: *mut StrVal) {
    // SAFETY: forwarded caller contract.
    unsafe { precision_out(v, b'g', digits, 1, "to_precision", out) }
}

/// `Float.to_exponential(digits)`: `digits` in `0..=100`, otherwise a fault.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_float_to_exponential(v: f64, digits: i64, out: *mut StrVal) {
    // SAFETY: forwarded caller contract.
    unsafe { precision_out(v, b'e', digits, 0, "to_exponential", out) }
}

/// `Float.to_fixed(digits)`: `digits` in `0..=100`, otherwise a fault.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_float_to_fixed(v: f64, digits: i64, out: *mut StrVal) {
    // SAFETY: forwarded caller contract.
    unsafe { precision_out(v, b'f', digits, 0, "to_fixed", out) }
}

/// The `Float` with this IEEE 754 binary64 bit pattern.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_float_from_bits(bits: i64) -> f64 {
    f64::from_bits(bits as u64)
}

/// The IEEE 754 binary64 bit pattern of a `Float`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_float_to_bits(value: f64) -> i64 {
    value.to_bits() as i64
}

/// The instruction-set level of this CPU for compiled loops: 3 when it has x86-64-v3's AVX2 and
/// FMA, else 1 (the architecture baseline). `MS_CPU_LEVEL=baseline` forces 1 so every copy can
/// be tested on one machine. Computed once.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cpu_level() -> i64 {
    use std::sync::atomic::{AtomicI64, Ordering};
    static LEVEL: AtomicI64 = AtomicI64::new(0);
    let known = LEVEL.load(Ordering::Relaxed);
    if known != 0 {
        return known;
    }
    #[cfg(target_arch = "x86_64")]
    let level = if std::env::var("MS_CPU_LEVEL").is_ok_and(|v| v == "baseline")
        || !std::arch::is_x86_feature_detected!("avx2")
        || !std::arch::is_x86_feature_detected!("fma")
    {
        1
    } else {
        3
    };
    #[cfg(not(target_arch = "x86_64"))]
    let level = 1;
    LEVEL.store(level, Ordering::Relaxed);
    level
}

/// The binary32 with this bit pattern (the low 32 bits), widened exactly to the `f64` a `Float32` register holds.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_float32_from_bits(bits: i64) -> f64 {
    f64::from(f32::from_bits(bits as u32))
}

/// The binary32 bit pattern of a value a `Float32` register holds as an `f64`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_float32_to_bits(value: f64) -> i64 {
    i64::from((value as f32).to_bits())
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

/// `Float.to_float32()`: present flag, value through `out` only when present. A finite value
/// too large for binary32 is absent (Float32 payloads are stored as 4 bytes); NaN and infinities convert unchanged.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_float_to_float32(v: f64, out: *mut f32) -> u8 {
    let narrowed = v as f32;
    if v.is_finite() && narrowed.is_infinite() {
        return 0;
    }
    // SAFETY: the caller passes a writable out.
    unsafe { *out = narrowed };
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

/// `UInt64.compare`: the operands are bit patterns.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_uint_compare(a: i64, b: i64) -> i64 {
    let (a, b) = (a as u64, b as u64);
    (a > b) as i64 - (a < b) as i64
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

/// `UInt64.to_float`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_uint_to_float(v: i64) -> f64 {
    v as u64 as f64
}

/// `UInt64` in decimal digits.
pub fn format_u64(v: u64, tmp: &mut [u8; 20]) -> &[u8] {
    let mut n = v;
    let mut i = tmp.len();
    loop {
        i -= 1;
        tmp[i] = b'0' + (n % 10) as u8;
        n /= 10;
        if n == 0 {
            break;
        }
    }
    &tmp[i..]
}

/// `UInt64.to_string_radix`.
pub fn format_radix_u64(v: u64, radix: u32, out: &mut Vec<u8>) {
    let mut tmp = [0u8; 64];
    let mut i = tmp.len();
    let mut n = v;
    loop {
        i -= 1;
        let d = (n % radix as u64) as u8;
        tmp[i] = if d < 10 { b'0' + d } else { b'a' + d - 10 };
        n /= radix as u64;
        if n == 0 {
            break;
        }
    }
    out.extend_from_slice(&tmp[i..]);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::string::{String, ToString};

    fn s(b: Vec<u8>) -> String {
        String::from_utf8(b.as_slice().to_vec()).unwrap()
    }

    #[test]
    fn uint64_helpers() {
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
    fn shortest_float_strings_match_the_previous_formatter() {
        let _g = crate::testutil::lock();
        // Independent storage/extraction oracle: the former implementation used
        // Rust's scientific formatter and collected a separate digit vector.
        let previous = |value: f64, binary32: bool| {
            let value = if binary32 {
                f64::from(value as f32)
            } else {
                value
            };
            if value.is_nan() {
                return b"NaN".to_vec();
            }
            if value.is_infinite() {
                return if value.is_sign_negative() {
                    b"-Infinity".to_vec()
                } else {
                    b"Infinity".to_vec()
                };
            }
            if value == 0.0 {
                return if value.is_sign_negative() {
                    b"-0".to_vec()
                } else {
                    b"0".to_vec()
                };
            }
            if !binary32 && value.abs() < 9.007_199_254_740_992e15 && value == (value as i64) as f64
            {
                return (value as i64).to_string().into_bytes();
            }
            let scientific = if binary32 {
                format!("{:e}", (value as f32).abs())
            } else {
                format!("{:e}", value.abs())
            };
            let (mantissa, exponent) = scientific.split_once('e').unwrap();
            let digits: Vec<u8> = mantissa.bytes().filter(|&c| c != b'.').collect();
            let mut out = Vec::new();
            render_decimal(
                &digits,
                exponent.parse().unwrap(),
                value.is_sign_negative(),
                &mut out,
            );
            out
        };
        let check = |value: f64| {
            assert_eq!(
                float_to_string(value),
                previous(value, false),
                "binary64 bits={:016x}",
                value.to_bits()
            );
            assert_eq!(
                float32_to_string(value),
                previous(value, true),
                "binary32 input bits={:016x}",
                value.to_bits()
            );
        };
        for exponent in 0..=0x7ffu64 {
            for fraction in [0, 1, 0x0007_ffff_ffff_ffff, 0x000f_ffff_ffff_ffff] {
                let value = f64::from_bits((exponent << 52) | fraction);
                check(value);
                check(-value);
            }
        }
        for exponent in 0..=0xffu32 {
            for fraction in [0, 1, 0x003f_ffff, 0x007f_ffff] {
                let value = f64::from(f32::from_bits((exponent << 23) | fraction));
                check(value);
                check(-value);
            }
        }
        let mut bits = 0x9e37_79b9_7f4a_7c15u64;
        for _ in 0..8192 {
            bits = bits.wrapping_mul(6364136223846793005).wrapping_add(1);
            check(f64::from_bits(bits));
            check(f64::from(f32::from_bits(bits as u32)));
        }
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
    fn exported_numbers_natives() {
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
