//! Int and Float formatting and parsing with shortest round-trip output.
//! ms: domain number
// The Rust formatting bodies are compiled out of the archive once the C kernels are linked (runtime/core/fmt.c).
#![cfg_attr(ms_c = "msrt_fmt_float_precision", allow(dead_code, unused_imports))]
use core::fmt::Write as _;
use ms_rt_abi::{
    STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_OK, STATUS_OUT_OF_RANGE, StrVal,
};
use std::io::Write;

// The formatting kernels live in runtime/core/fmt.c. `cargo xtask runtime` links them (the symbols are listed in
// runtime/symbols/fmt.txt) and the helpers below call them; plain `cargo test` keeps the Rust bodies.
#[cfg(ms_c = "msrt_fmt_u64")]
unsafe extern "C-unwind" {
    fn msrt_fmt_u64(n: u64, out: *mut u8) -> usize;
}
#[cfg(ms_c = "msrt_fmt_i64")]
unsafe extern "C-unwind" {
    fn msrt_fmt_i64(v: i64, out: *mut u8) -> usize;
}
#[cfg(ms_c = "msrt_fmt_radix")]
unsafe extern "C-unwind" {
    fn msrt_fmt_radix(n: u64, radix: u32, negative: u8, out: *mut u8) -> usize;
}
#[cfg(ms_c = "msrt_fmt_float")]
unsafe extern "C-unwind" {
    fn msrt_fmt_float(v: f64, out: *mut u8) -> usize;
}
#[cfg(ms_c = "msrt_fmt_float32")]
unsafe extern "C-unwind" {
    fn msrt_fmt_float32(v: f64, out: *mut u8) -> usize;
}
#[cfg(ms_c = "msrt_fmt_float_precision")]
unsafe extern "C-unwind" {
    fn msrt_fmt_float_precision(v: f64, format: u8, digits: i64, out: *mut u8) -> usize;
}

/// Formats `v` in decimal into `tmp`, returning the used tail.
pub fn format_i64(v: i64, tmp: &mut [u8; 20]) -> &[u8] {
    #[cfg(ms_c = "msrt_fmt_i64")]
    {
        // SAFETY: `tmp` holds the 20 bytes the longest Int needs.
        let n = unsafe { msrt_fmt_i64(v, tmp.as_mut_ptr()) };
        return &tmp[..n];
    }
    #[cfg(not(ms_c = "msrt_fmt_i64"))]
    {
        format_i64_rust(v, tmp)
    }
}

#[cfg(not(ms_c = "msrt_fmt_i64"))]
fn format_i64_rust(v: i64, tmp: &mut [u8; 20]) -> &[u8] {
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
    #[cfg(ms_c = "msrt_fmt_radix")]
    {
        let mut tmp = [0u8; 65];
        // SAFETY: 65 bytes hold a binary Int with its sign.
        let n =
            unsafe { msrt_fmt_radix(v.unsigned_abs(), radix, u8::from(v < 0), tmp.as_mut_ptr()) };
        return out.extend_from_slice(&tmp[..n]);
    }
    #[cfg(not(ms_c = "msrt_fmt_radix"))]
    {
        format_radix_rust(v, radix, out)
    }
}

#[cfg(not(ms_c = "msrt_fmt_radix"))]
fn format_radix_rust(v: i64, radix: u32, out: &mut Vec<u8>) {
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
    let (digits, exp10) = crate::float_digits::shortest(v);
    let mut s = Scientific::default();
    let mut tmp = [0u8; 20];
    let text = format_u64(digits, &mut tmp);
    s.bytes[..text.len()].copy_from_slice(text);
    s.len = text.len();
    (s, exp10 + text.len() as i32 - 1)
}

/// The same through the standard formatter, which the tests compare `shortest` with.
#[cfg(test)]
fn shortest_via_core(v: f64) -> (Scientific, i32) {
    let mut s = Scientific::default();
    write!(s, "{v:e}").expect("shortest finite binary64 scientific form fits 32 bytes");
    let (digits, exp) = split_scientific(s);
    let mut exact = Scientific::default();
    let precision = digits.len - 1;
    if is_odd_tail(&digits) && may_tie(&digits, exp, v.to_bits(), 52, 1075) {
        write!(exact, "{v:.precision$e}").expect("exact binary64 scientific form fits 32 bytes");
    }
    prefer_even(digits, exp, exact, |text| {
        text.parse::<f64>().is_ok_and(|b| b == v)
    })
}

/// The shortest round-trip digits of a finite positive `v` copied into `buf`, with the decimal
/// exponent of the first digit.
pub fn shortest_digits(v: f64, buf: &mut [u8; 24]) -> (usize, i32) {
    let (digits, exp) = shortest(v);
    let n = digits.len.min(buf.len());
    buf[..n].copy_from_slice(&digits.as_slice()[..n]);
    (n, exp)
}

/// The same for a finite positive binary32 value.
fn shortest32(v: f32) -> (Scientific, i32) {
    let mut s = Scientific::default();
    write!(s, "{v:e}").expect("shortest finite binary32 scientific form fits 32 bytes");
    let (digits, exp) = split_scientific(s);
    let mut exact = Scientific::default();
    let precision = digits.len - 1;
    if is_odd_tail(&digits) && may_tie(&digits, exp, u64::from(v.to_bits()), 23, 150) {
        write!(exact, "{v:.precision$e}").expect("exact binary32 scientific form fits 32 bytes");
    }
    prefer_even(digits, exp, exact, |text| {
        text.parse::<f32>().is_ok_and(|b| b == v)
    })
}

/// Whether the exact value can sit halfway between two decimals of the shortest length: its
/// exact decimal expansion then has one more significant digit than the shortest form. A value
/// with `fraction_bits` binary places after the point has exactly that many decimal places, so a
/// fractional value is a candidate only when its exact length matches. An integer is exact in
/// full, so only the large ones, whose shortest form drops digits, are candidates.
fn may_tie(digits: &Scientific, exp: i32, bits: u64, mantissa_bits: u32, bias: i32) -> bool {
    // `shortest` takes positive values, so the sign bit is clear.
    let field = (bits >> mantissa_bits) as i32;
    let mut mantissa = bits & ((1 << mantissa_bits) - 1);
    if field > 0 {
        mantissa |= 1 << mantissa_bits;
    }
    let binary_exponent = field.max(1) - bias + mantissa.trailing_zeros() as i32;
    if binary_exponent >= 0 {
        return exp >= 15;
    }
    -binary_exponent == digits.len as i32 - exp
}

fn is_odd_tail(digits: &Scientific) -> bool {
    digits.as_slice().last().is_some_and(|d| d % 2 == 1)
}

/// The shortest digits when two candidates of that length are equally close to the exact value
/// are the one with an even final digit, but the shortest-digits formatter rounds such a tie
/// up. The exact formatter rounds half to even, so its answer replaces an odd tail whenever it
/// has the same length and exponent and still reads back as the same value.
fn prefer_even(
    digits: Scientific,
    exp: i32,
    exact: Scientific,
    reads_back: impl Fn(&str) -> bool,
) -> (Scientific, i32) {
    if exact.len == 0 {
        return (digits, exp);
    }
    let (rounded, rounded_exp) = split_scientific(exact);
    if rounded_exp != exp || rounded.as_slice() == digits.as_slice() {
        return (digits, exp);
    }
    let mut text = String::with_capacity(rounded.len + 8);
    let digits_text = core::str::from_utf8(rounded.as_slice()).unwrap_or("0");
    text.push_str(&digits_text[..1]);
    text.push('.');
    text.push_str(&digits_text[1..]);
    text.push('e');
    text.push_str(&exp.to_string());
    if reads_back(&text) {
        (rounded, exp)
    } else {
        (digits, exp)
    }
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

/// A growing byte sink: a `Vec`, or a fixed buffer for text that has a known bound.
trait Put {
    fn put(&mut self, bytes: &[u8]);
}

impl Put for Vec<u8> {
    fn put(&mut self, bytes: &[u8]) {
        self.extend_from_slice(bytes);
    }
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

impl Put for FloatText {
    fn put(&mut self, bytes: &[u8]) {
        self.bytes[self.len..self.len + bytes.len()].copy_from_slice(bytes);
        self.len += bytes.len();
    }
}

/// Renders shortest decimal digits: plain notation for exponents in -6..=20, else scientific.
fn render_decimal(digits: &[u8], exponent: i32, negative: bool, out: &mut impl Put) {
    let mut n = digits.len();
    while n > 1 && digits[n - 1] == b'0' {
        n -= 1;
    }
    let digits = &digits[..n];
    const ZEROS: [u8; 24] = [b'0'; 24];
    if negative {
        out.put(b"-");
    }
    if (-6..=20).contains(&exponent) {
        let point = exponent + 1;
        if point <= 0 {
            out.put(b"0.");
            out.put(&ZEROS[..(-point) as usize]);
            out.put(digits);
        } else if point as usize >= digits.len() {
            out.put(digits);
            out.put(&ZEROS[..point as usize - digits.len()]);
        } else {
            out.put(&digits[..point as usize]);
            out.put(b".");
            out.put(&digits[point as usize..]);
        }
        return;
    }
    out.put(&digits[..1]);
    if digits.len() > 1 {
        out.put(b".");
        out.put(&digits[1..]);
    }
    out.put(b"e");
    if exponent >= 0 {
        out.put(b"+");
    }
    out.put(format_i64(exponent as i64, &mut [0; 20]));
}

/// `Float.to_string`.
pub fn float_to_string(v: f64) -> Vec<u8> {
    float_text(v).as_slice().to_vec()
}

/// `Float.to_string` without an allocation.
pub fn float_text(v: f64) -> FloatText {
    #[cfg(ms_c = "msrt_fmt_float")]
    {
        let mut out = FloatText::new();
        // SAFETY: `FloatText` holds the 40 bytes the longest Float text needs.
        out.len = unsafe { msrt_fmt_float(v, out.bytes.as_mut_ptr()) };
        return out;
    }
    #[cfg(not(ms_c = "msrt_fmt_float"))]
    {
        float_text_rust(v)
    }
}

#[cfg(not(ms_c = "msrt_fmt_float"))]
fn float_text_rust(v: f64) -> FloatText {
    let mut out = FloatText::new();
    if v.is_nan() {
        out.put(b"NaN");
    } else if v.is_infinite() {
        out.put(if v > 0.0 { b"Infinity" } else { b"-Infinity" });
    } else if v == 0.0 {
        out.put(if v.is_sign_negative() { b"-0" } else { b"0" });
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
pub fn float32_text(v: f64) -> FloatText {
    #[cfg(ms_c = "msrt_fmt_float32")]
    {
        let mut out = FloatText::new();
        // SAFETY: as in `float_text`.
        out.len = unsafe { msrt_fmt_float32(v, out.bytes.as_mut_ptr()) };
        return out;
    }
    #[cfg(not(ms_c = "msrt_fmt_float32"))]
    {
        float32_text_rust(v)
    }
}

#[cfg(not(ms_c = "msrt_fmt_float32"))]
fn float32_text_rust(v: f64) -> FloatText {
    let x = v as f32;
    if x.is_nan() || x.is_infinite() || x == 0.0 {
        return float_text(f64::from(x));
    }
    let mut out = FloatText::new();
    let (digits, exp) = shortest32(x.abs());
    render_decimal(digits.as_slice(), exp, x < 0.0, &mut out);
    out
}

/// `Float32.to_string` as a vector.
pub fn float32_to_string(v: f64) -> Vec<u8> {
    float32_text(v).as_slice().to_vec()
}

/// `{v:.digits$}` for a finite `v` below 2^53 in magnitude and up to 15 fractional digits, exactly:
/// the scaled value `c * 2^q * 10^digits` of the binary64 `c * 2^q` is an integer product that
/// fits 128 bits, so it is divided by a power of two with the remainder deciding the rounding (a
/// tie goes to the even last digit, as in the standard formatter). Returns false, writing
/// nothing, for any other value.
fn push_fixed(v: f64, digits: usize, out: &mut Vec<u8>) -> bool {
    const POW10: [u64; 16] = {
        let mut t = [1u64; 16];
        let mut i = 1;
        while i < 16 {
            t[i] = t[i - 1] * 10;
            i += 1;
        }
        t
    };
    let bits = v.to_bits();
    let biased = (bits >> 52) as i32 & 0x7ff;
    let fraction = bits & ((1 << 52) - 1);
    let (c, q) = if biased == 0 {
        (fraction, -1074)
    } else {
        (fraction | 1 << 52, biased - 1075)
    };
    if digits > 15 || q > 0 {
        return false;
    }
    let scale = POW10[digits];
    let product = u128::from(c) * u128::from(scale);
    let shift = (-q) as u32;
    let scaled = if shift >= 128 {
        0
    } else if shift == 0 {
        product
    } else {
        let whole = product >> shift;
        let rest = product & ((1u128 << shift) - 1);
        let half = 1u128 << (shift - 1);
        whole + u128::from(rest > half || (rest == half && whole & 1 == 1))
    };
    let Ok(scaled) = u64::try_from(scaled) else {
        return false;
    };
    if bits >> 63 != 0 {
        out.push(b'-');
    }
    let mut tmp = [0u8; 20];
    out.extend_from_slice(format_u64(scaled / scale, &mut tmp));
    if digits > 0 {
        out.push(b'.');
        let fraction = format_u64(scaled % scale, &mut tmp);
        out.extend(core::iter::repeat_n(b'0', digits - fraction.len()));
        out.extend_from_slice(fraction);
    }
    true
}

/// `to_precision` (`'g'`, minimum 1), `to_exponential` (`'e'`), `to_fixed` (`'f'`).
/// Returns `None` when `digits` is outside `minimum..=100`.
pub fn float_precision(v: f64, format: u8, digits: i64, minimum: i64) -> Option<Vec<u8>> {
    if digits < minimum || digits > 100 {
        return None;
    }
    #[cfg(ms_c = "msrt_fmt_float_precision")]
    {
        let mut buf = [0u8; 160];
        // SAFETY: 160 bytes hold the longest precision form (a value below 1e21 with 100 fractional digits).
        let n = unsafe { msrt_fmt_float_precision(v, format, digits, buf.as_mut_ptr()) };
        return Some(buf[..n].to_vec());
    }
    #[cfg(not(ms_c = "msrt_fmt_float_precision"))]
    {
        float_precision_rust(v, format, digits)
    }
}

#[cfg(not(ms_c = "msrt_fmt_float_precision"))]
fn float_precision_rust(v: f64, format: u8, digits: i64) -> Option<Vec<u8>> {
    let digits = digits as usize;
    if v.is_nan() || v.is_infinite() {
        return Some(float_to_string(v));
    }
    let mut out = Vec::new();
    if format == b'f' {
        if v.abs() >= 1e21 {
            return Some(float_to_string(v));
        }
        if !push_fixed(v, digits, &mut out) {
            let _ = write!(out, "{v:.digits$}");
        }
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

/// The `Float` with this IEEE 754 binary64 bit pattern.
#[cfg(not(ms_c = "msrt_float_from_bits"))]
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_float_from_bits(bits: i64) -> f64 {
    f64::from_bits(bits as u64)
}

/// The IEEE 754 binary64 bit pattern of a `Float`.
#[cfg(not(ms_c = "msrt_float_to_bits"))]
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_float_to_bits(value: f64) -> i64 {
    value.to_bits() as i64
}

/// The binary32 with this bit pattern (the low 32 bits), widened exactly to the `f64` a `Float32` register holds.
#[cfg(not(ms_c = "msrt_float32_from_bits"))]
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_float32_from_bits(bits: i64) -> f64 {
    f64::from(f32::from_bits(bits as u32))
}

/// The binary32 bit pattern of a value a `Float32` register holds as an `f64`.
#[cfg(not(ms_c = "msrt_float32_to_bits"))]
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_float32_to_bits(value: f64) -> i64 {
    i64::from((value as f32).to_bits())
}

/// `Float.truncate_to_int()`: present flag, value through `out` only when present.
#[cfg(not(ms_c = "msrt_float_truncate_to_int"))]
#[unsafe(no_mangle)]
// ms: leaf
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
#[cfg(not(ms_c = "msrt_float_to_float32"))]
#[unsafe(no_mangle)]
// ms: leaf
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
#[cfg(not(ms_c = "msrt_float_compare"))]
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_float_compare(a: f64, b: f64) -> i64 {
    if a.is_nan() || b.is_nan() {
        return a.is_nan() as i64 - b.is_nan() as i64;
    }
    (a > b) as i64 - (a < b) as i64
}

/// `Int.compare`.
#[cfg(not(ms_c = "msrt_int_compare"))]
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_int_compare(a: i64, b: i64) -> i64 {
    (a > b) as i64 - (a < b) as i64
}

/// `UInt64.compare`: the operands are bit patterns.
#[cfg(not(ms_c = "msrt_uint_compare"))]
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
#[cfg(not(ms_c = "msrt_uint_to_float"))]
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_uint_to_float(v: i64) -> f64 {
    v as u64 as f64
}

/// `UInt64.to_float32`: round once to binary32, then widen for the runtime ABI.
#[cfg(not(ms_c = "msrt_uint_to_float32"))]
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_uint_to_float32(v: i64) -> f64 {
    f64::from(v as u64 as f32)
}

/// `UInt64` in decimal digits.
pub fn format_u64(v: u64, tmp: &mut [u8; 20]) -> &[u8] {
    #[cfg(ms_c = "msrt_fmt_u64")]
    {
        // SAFETY: `tmp` holds the 20 bytes the longest UInt64 needs.
        let n = unsafe { msrt_fmt_u64(v, tmp.as_mut_ptr()) };
        return &tmp[..n];
    }
    #[cfg(not(ms_c = "msrt_fmt_u64"))]
    {
        format_u64_rust(v, tmp)
    }
}

#[cfg(not(ms_c = "msrt_fmt_u64"))]
fn format_u64_rust(v: u64, tmp: &mut [u8; 20]) -> &[u8] {
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
    #[cfg(ms_c = "msrt_fmt_radix")]
    {
        let mut tmp = [0u8; 65];
        // SAFETY: 65 bytes hold a binary UInt64.
        let n = unsafe { msrt_fmt_radix(v, radix, 0, tmp.as_mut_ptr()) };
        return out.extend_from_slice(&tmp[..n]);
    }
    #[cfg(not(ms_c = "msrt_fmt_radix"))]
    {
        format_radix_u64_rust(v, radix, out)
    }
}

#[cfg(not(ms_c = "msrt_fmt_radix"))]
fn format_radix_u64_rust(v: u64, radix: u32, out: &mut Vec<u8>) {
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

// The runtime-internal formatting entry points, defined in C when the archive is built (runtime/core/fmt.c); these
// Rust definitions keep `cargo test` and the symbol table whole.
/// # Safety
/// `out` holds at least 20 bytes.
#[cfg(not(ms_c = "msrt_fmt_u64"))]
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_fmt_u64(n: u64, out: *mut u8) -> usize {
    let mut tmp = [0u8; 20];
    let text = format_u64(n, &mut tmp);
    // SAFETY: caller contract.
    unsafe { core::ptr::copy_nonoverlapping(text.as_ptr(), out, text.len()) };
    text.len()
}

/// # Safety
/// `out` holds at least 20 bytes.
#[cfg(not(ms_c = "msrt_fmt_i64"))]
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_fmt_i64(v: i64, out: *mut u8) -> usize {
    let mut tmp = [0u8; 20];
    let text = format_i64(v, &mut tmp);
    // SAFETY: caller contract.
    unsafe { core::ptr::copy_nonoverlapping(text.as_ptr(), out, text.len()) };
    text.len()
}

/// # Safety
/// `out` holds at least 65 bytes.
#[cfg(not(ms_c = "msrt_fmt_radix"))]
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_fmt_radix(
    n: u64,
    radix: u32,
    negative: u8,
    out: *mut u8,
) -> usize {
    let mut text = Vec::new();
    if negative != 0 {
        format_radix(-(n as i64), radix, &mut text);
    } else {
        format_radix_u64(n, radix, &mut text);
    }
    // SAFETY: caller contract.
    unsafe { core::ptr::copy_nonoverlapping(text.as_ptr(), out, text.len()) };
    text.len()
}

/// # Safety
/// `out` holds at least 40 bytes.
#[cfg(not(ms_c = "msrt_fmt_float"))]
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_fmt_float(v: f64, out: *mut u8) -> usize {
    let text = float_text(v);
    // SAFETY: caller contract.
    unsafe { core::ptr::copy_nonoverlapping(text.as_slice().as_ptr(), out, text.as_slice().len()) };
    text.as_slice().len()
}

/// # Safety
/// `out` holds at least 40 bytes.
#[cfg(not(ms_c = "msrt_fmt_float32"))]
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_fmt_float32(v: f64, out: *mut u8) -> usize {
    let text = float32_text(v);
    // SAFETY: caller contract.
    unsafe { core::ptr::copy_nonoverlapping(text.as_slice().as_ptr(), out, text.as_slice().len()) };
    text.as_slice().len()
}

/// # Safety
/// `out` holds at least 160 bytes.
#[cfg(not(ms_c = "msrt_fmt_float_precision"))]
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_fmt_float_precision(
    v: f64,
    format: u8,
    digits: i64,
    out: *mut u8,
) -> usize {
    let text = float_precision(v, format, digits, 0).unwrap_or_default();
    // SAFETY: caller contract.
    unsafe { core::ptr::copy_nonoverlapping(text.as_ptr(), out, text.len()) };
    text.len()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::string::{String, ToString};

    fn s(b: Vec<u8>) -> String {
        String::from_utf8(b.as_slice().to_vec()).unwrap()
    }

    /// The Schubfach digits agree with the standard formatter's, tie rule included, over every
    /// binary exponent, the edges of each binade, random bit patterns and decimal literals.
    #[test]
    #[cfg_attr(
        miri,
        ignore = "an exhaustive sweep that takes over 200 s interpreted; native CI runs it"
    )]
    fn fixed_notation_matches_the_standard_formatter() {
        let mut x = 0x2545_f491_4f6c_dd1du64;
        let mut next = || {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            x
        };
        let mut values: std::vec::Vec<f64> = std::vec![
            0.0,
            -0.0,
            0.5,
            1.5,
            2.5,
            0.125,
            0.375,
            -0.001,
            1e-320,
            9007199254740991.0,
            1e15,
            123456.789
        ];
        for i in 0..4000 {
            values.push(f64::from(i) / 8.0);
            values.push(f64::from(i) * 0.005);
            values.push(-f64::from(i) * 1.37);
        }
        for _ in 0..60_000 {
            let bits = next();
            values.push(
                f64::from_bits(bits & 0x7fff_ffff_ffff_ffff)
                    * if bits >> 63 != 0 { -1.0 } else { 1.0 },
            );
            values.push(
                (next() % 1_000_000_000_000) as f64 / 1000.0
                    * if bits & 1 != 0 { -1.0 } else { 1.0 },
            );
        }
        for v in values {
            if !v.is_finite() || v.abs() >= 1e21 {
                continue;
            }
            for digits in [0usize, 1, 2, 3, 6, 9, 15, 16, 20] {
                let mut fast = Vec::new();
                if push_fixed(v, digits, &mut fast) {
                    assert_eq!(
                        core::str::from_utf8(&fast).unwrap(),
                        std::format!("{v:.digits$}"),
                        "{v:e} {digits}"
                    );
                }
            }
        }
    }

    #[test]
    #[cfg_attr(
        miri,
        ignore = "an exhaustive sweep that takes over 200 s interpreted; native CI runs it"
    )]
    fn shortest_digits_match_the_standard_formatter() {
        let check = |v: f64| {
            if !(v.is_finite() && v > 0.0) {
                return;
            }
            let (a, ea) = shortest(v);
            let (b, eb) = shortest_via_core(v);
            assert_eq!(
                (a.as_slice(), ea),
                (b.as_slice(), eb),
                "{v:e} {:#x}",
                v.to_bits()
            );
        };
        // Every small subnormal: its integer significand is under 100 digits' worth, where a
        // one-digit form (5e-323, not 4.9e-323) can exist.
        for bits in 1u64..5000 {
            check(f64::from_bits(bits));
        }
        let mut x = 0x9e37_79b9_7f4a_7c15u64;
        let mut next = || {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            x
        };
        for exp in 0u64..2047 {
            for mantissa in [
                0,
                1,
                2,
                3,
                (1 << 52) - 1,
                (1 << 52) - 2,
                1 << 51,
                0x0005_5555_5555_5555,
                0x000a_aaaa_aaaa_aaaa,
            ] {
                check(f64::from_bits(exp << 52 | mantissa));
            }
            for _ in 0..300 {
                check(f64::from_bits(exp << 52 | next() & ((1 << 52) - 1)));
            }
        }
        for _ in 0..300_000 {
            check(f64::from_bits(next() & 0x7fff_ffff_ffff_ffff));
        }
        for i in 1..200_000u64 {
            check(i as f64 * 0.1);
            check(i as f64 * 1.37);
            check(i as f64 / 7.0);
            check(i as f64 * 1e-7);
            check((i * i * i) as f64 * 1e15);
            check(f64::from(i as u32) * 0.5 + 0.25);
        }
        for e in -330..320 {
            for m in [
                1.0,
                1.5,
                2.5,
                5.0,
                9.999999999999999,
                4.35,
                1.0000000000000002,
            ] {
                check(m * 10f64.powi(e));
            }
        }
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
    fn uint64_to_float32_rounds_once() {
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
    #[cfg_attr(
        miri,
        ignore = "an exhaustive sweep that takes over 200 s interpreted; native CI runs it"
    )]
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
        // The previous formatter rounded an exact tie up; the current one keeps the even digit,
        // so a single differing digit that is one lower and even is the same answer.
        let same = |ours: Vec<u8>, old: Vec<u8>| {
            let differing: Vec<usize> = (0..ours.len().min(old.len()))
                .filter(|&i| ours[i] != old[i])
                .collect();
            ours == old
                || (ours.len() == old.len()
                    && differing.len() == 1
                    && ours[differing[0]].is_multiple_of(2)
                    && ours[differing[0]] + 1 == old[differing[0]])
        };
        let check = |value: f64| {
            assert!(
                same(float_to_string(value), previous(value, false)),
                "binary64 bits={:016x}",
                value.to_bits()
            );
            assert!(
                same(float32_to_string(value), previous(value, true)),
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
