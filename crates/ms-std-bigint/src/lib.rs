//! `@std/bigint.ms` natives. Symbols are `msstd_bigint_<name>`.
//!
//! A `BigInt` is an immutable refcounted [`BigObj`] handle; operations return fresh handles.
//! Fallible calls return a `STATUS_*` code and write `out` only on success; `to_int` returns
//! a presence flag (0 where the value does not fit an `Int`).
#![no_std]
// The exports below are the C ABI compiled code links against.
#![allow(unsafe_code)]
#![allow(clippy::missing_safety_doc)]

extern crate alloc;

use alloc::string::String;
use ms_rt_abi::{
    STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED, STATUS_OK, StrObj,
};
use ms_std_rt::{Handle, fault_fmt, new_handle, new_string, str_bytes};
use num_bigint::{BigInt, Sign};
use num_traits::{Signed, ToPrimitive, Zero};

/// The runtime object behind a `BigInt` value.
pub type BigObj = Handle<BigInt>;

/// Result size ceiling in bits for `pow` and `shift_left`.
const MAX_BITS: i64 = 1 << 24;

fn make(n: BigInt) -> *mut BigObj {
    new_handle(n)
}

/// # Safety
/// `p` must point to a live `BigObj` that outlives `'a`.
unsafe fn val<'a>(p: *const BigObj) -> &'a BigInt {
    // SAFETY: guaranteed by the caller.
    unsafe { &(*p).value }
}

fn digit(b: u8) -> Option<u32> {
    match b {
        b'0'..=b'9' => Some(u32::from(b - b'0')),
        b'a'..=b'z' => Some(u32::from(b - b'a') + 10),
        b'A'..=b'Z' => Some(u32::from(b - b'A') + 10),
        _ => None,
    }
}

/// Parses `text` as an optionally signed run of digits valid in `radix`.
pub fn parse(text: &[u8], radix: i64, max_digits: Option<i64>) -> Result<BigInt, u8> {
    let limit = max_digits.unwrap_or(i64::MAX);
    if !(2..=36).contains(&radix) || limit < 0 {
        return Err(STATUS_INVALID_INPUT);
    }
    let signed = matches!(text.first(), Some(b'+' | b'-'));
    let digits = &text[usize::from(signed)..];
    if i64::try_from(text.len() - usize::from(signed)).map_or(true, |n| n > limit) {
        return Err(STATUS_LIMIT_EXCEEDED);
    }
    if digits.is_empty()
        || digits
            .iter()
            .any(|&b| digit(b).is_none_or(|d| i64::from(d) >= radix))
    {
        return Err(STATUS_INVALID_DATA);
    }
    let values: alloc::vec::Vec<u8> = digits
        .iter()
        .map(|&b| digit(b).unwrap_or(0) as u8)
        .collect();
    let magnitude =
        num_bigint::BigUint::from_radix_be(&values, radix as u32).ok_or(STATUS_INVALID_DATA)?;
    let sign = if text.first() == Some(&b'-') {
        Sign::Minus
    } else {
        Sign::Plus
    };
    Ok(BigInt::from_biguint(sign, magnitude))
}

/// Formats `n` in `radix` with lowercase digits and a leading `-` for negatives.
pub fn format(n: &BigInt, radix: u32) -> String {
    n.to_str_radix(radix)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_bigint_from_int(value: i64) -> *mut BigObj {
    make(BigInt::from(value))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_parse(
    text: *const StrObj,
    radix: i64,
    has_max: u8,
    max: i64,
    out: *mut *mut BigObj,
) -> u8 {
    // SAFETY: `text` is a live string; `out` is writable.
    unsafe {
        match parse(str_bytes(text), radix, (has_max != 0).then_some(max)) {
            Ok(n) => {
                out.write(make(n));
                STATUS_OK
            }
            Err(status) => status,
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_add(a: *const BigObj, other: *const BigObj) -> *mut BigObj {
    // SAFETY: both are live BigInts.
    let (a, b) = unsafe { (val(a), val(other)) };
    make(a + b)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_subtract(
    a: *const BigObj,
    other: *const BigObj,
) -> *mut BigObj {
    // SAFETY: both are live BigInts.
    let (a, b) = unsafe { (val(a), val(other)) };
    make(a - b)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_multiply(
    a: *const BigObj,
    other: *const BigObj,
) -> *mut BigObj {
    // SAFETY: both are live BigInts.
    let (a, b) = unsafe { (val(a), val(other)) };
    make(a * b)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_bit_and(
    a: *const BigObj,
    other: *const BigObj,
) -> *mut BigObj {
    // SAFETY: both are live BigInts.
    let (a, b) = unsafe { (val(a), val(other)) };
    make(a & b)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_bit_or(
    a: *const BigObj,
    other: *const BigObj,
) -> *mut BigObj {
    // SAFETY: both are live BigInts.
    let (a, b) = unsafe { (val(a), val(other)) };
    make(a | b)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_bit_xor(
    a: *const BigObj,
    other: *const BigObj,
) -> *mut BigObj {
    // SAFETY: both are live BigInts.
    let (a, b) = unsafe { (val(a), val(other)) };
    make(a ^ b)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_divide(
    a: *const BigObj,
    other: *const BigObj,
    out: *mut *mut BigObj,
) -> u8 {
    // SAFETY: both are live BigInts; `out` is writable.
    unsafe {
        let (a, b) = (val(a), val(other));
        if b.is_zero() {
            return STATUS_INVALID_INPUT;
        }
        // Truncates toward zero.
        out.write(make(a / b));
        STATUS_OK
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_remainder(
    a: *const BigObj,
    other: *const BigObj,
    out: *mut *mut BigObj,
) -> u8 {
    // SAFETY: both are live BigInts; `out` is writable.
    unsafe {
        let (a, b) = (val(a), val(other));
        if b.is_zero() {
            return STATUS_INVALID_INPUT;
        }
        // Takes the sign of the dividend.
        out.write(make(a % b));
        STATUS_OK
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_compare(a: *const BigObj, other: *const BigObj) -> i64 {
    // SAFETY: both are live BigInts.
    unsafe { val(a).cmp(val(other)) as i64 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_bit_not(a: *const BigObj) -> *mut BigObj {
    // SAFETY: `a` is a live BigInt.
    make(!unsafe { val(a) }.clone())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_negate(a: *const BigObj) -> *mut BigObj {
    // SAFETY: `a` is a live BigInt.
    make(-unsafe { val(a) }.clone())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_abs(a: *const BigObj) -> *mut BigObj {
    // SAFETY: `a` is a live BigInt.
    make(unsafe { val(a) }.abs())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_sign(a: *const BigObj) -> i64 {
    // SAFETY: `a` is a live BigInt.
    match unsafe { val(a) }.sign() {
        Sign::Minus => -1,
        Sign::NoSign => 0,
        Sign::Plus => 1,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_pow(
    a: *const BigObj,
    exponent: i64,
    out: *mut *mut BigObj,
) -> u8 {
    // SAFETY: `a` is a live BigInt; `out` is writable.
    unsafe {
        let a = val(a);
        if exponent < 0 {
            return STATUS_INVALID_INPUT;
        }
        let bits = i64::try_from(a.bits()).unwrap_or(i64::MAX);
        if exponent > 1
            && bits > 1
            && (exponent > MAX_BITS || bits.saturating_mul(exponent) > MAX_BITS + exponent)
        {
            return STATUS_LIMIT_EXCEEDED;
        }
        ms_std_rt::poll_cancel();
        out.write(make(num_traits::pow::Pow::pow(a, exponent as u64)));
        STATUS_OK
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_shift_left(
    a: *const BigObj,
    count: i64,
    out: *mut *mut BigObj,
) -> u8 {
    // SAFETY: `a` is a live BigInt; `out` is writable.
    unsafe {
        let a = val(a);
        if count < 0 {
            return STATUS_INVALID_INPUT;
        }
        let bits = i64::try_from(a.bits()).unwrap_or(i64::MAX);
        if count > MAX_BITS || bits.saturating_add(count) > MAX_BITS {
            return STATUS_LIMIT_EXCEEDED;
        }
        out.write(make(a << count as usize));
        STATUS_OK
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_shift_right(
    a: *const BigObj,
    count: i64,
    out: *mut *mut BigObj,
) -> u8 {
    // SAFETY: `a` is a live BigInt; `out` is writable.
    unsafe {
        let a = val(a);
        if count < 0 {
            return STATUS_INVALID_INPUT;
        }
        let bits = i64::try_from(a.bits()).unwrap_or(i64::MAX);
        // Shifting by more than the width gives 0 or -1 (floor semantics).
        let count = count.min(bits.saturating_add(1)) as usize;
        out.write(make(a >> count));
        STATUS_OK
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_to_float(a: *const BigObj) -> f64 {
    // SAFETY: `a` is a live BigInt.
    let n = unsafe { val(a) };
    // Out of range: infinity of the same sign.
    n.to_f64().unwrap_or(if n.is_negative() {
        f64::NEG_INFINITY
    } else {
        f64::INFINITY
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_to_int(a: *const BigObj, out: *mut i64) -> u8 {
    // SAFETY: `a` is a live BigInt; `out` is writable.
    unsafe {
        match val(a).to_i64() {
            Some(v) => {
                out.write(v);
                1
            }
            None => 0,
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_to_string_radix(a: *const BigObj, radix: i64) -> *mut StrObj {
    if !(2..=36).contains(&radix) {
        fault_fmt(format_args!(
            "BigInt.to_string_radix: radix must be between 2 and 36, found {radix}"
        ));
    }
    // SAFETY: `a` is a live BigInt.
    new_string(format(unsafe { val(a) }, radix as u32).as_bytes())
}

/// Whether two values hold the same integer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_bigint_equal(a: *const BigObj, other: *const BigObj) -> u8 {
    // SAFETY: both are live BigInts.
    u8::from(unsafe { val(a) == val(other) })
}

#[cfg(test)]
mod tests {
    use super::*;
    use ms_rt as _; // links the msrt_* runtime symbols

    fn big(text: &str) -> BigInt {
        parse(text.as_bytes(), 10, None).expect("parse")
    }

    #[test]
    fn parse_matches_go() {
        assert_eq!(parse(b"+-1", 10, Some(2)), Err(STATUS_INVALID_DATA));
        assert_eq!(parse(b"+-1", 10, Some(1)), Err(STATUS_LIMIT_EXCEEDED));
        assert_eq!(parse(b"1_0", 10, None), Err(STATUS_INVALID_DATA));
        assert_eq!(parse(b"", 10, None), Err(STATUS_INVALID_DATA));
        assert_eq!(parse(b"-", 10, None), Err(STATUS_INVALID_DATA));
        assert_eq!(parse(b"1", 1, None), Err(STATUS_INVALID_INPUT));
        assert_eq!(parse(b"1", 10, Some(-1)), Err(STATUS_INVALID_INPUT));
        assert_eq!(parse(b"1", 10, Some(0)), Err(STATUS_LIMIT_EXCEEDED));
        assert_eq!(parse(b"zZ", 36, None).unwrap(), BigInt::from(35 * 36 + 35));
        assert_eq!(parse(b"-ff", 16, None).unwrap(), BigInt::from(-255));
    }

    #[test]
    fn division_truncates_toward_zero() {
        let (a, b) = (BigInt::from(-7), BigInt::from(3));
        assert_eq!(&a / &b, BigInt::from(-2));
        assert_eq!(&a % &b, BigInt::from(-1));
    }

    #[test]
    fn handles_roundtrip() {
        let a = msstd_bigint_from_int(-5);
        let mut out = core::ptr::null_mut();
        // SAFETY: handles are live until released by the process.
        unsafe {
            assert_eq!(msstd_bigint_shift_right(a, 1, &mut out), STATUS_OK);
            assert_eq!(val(out), &BigInt::from(-3));
            assert_eq!(msstd_bigint_shift_right(a, 1000, &mut out), STATUS_OK);
            assert_eq!(val(out), &BigInt::from(-1));
            assert_eq!(
                msstd_bigint_shift_left(a, 100_000_000, &mut out),
                STATUS_LIMIT_EXCEEDED
            );
            assert_eq!(msstd_bigint_pow(a, -1, &mut out), STATUS_INVALID_INPUT);
            let two = msstd_bigint_from_int(2);
            assert_eq!(msstd_bigint_pow(two, 100, &mut out), STATUS_OK);
            assert_eq!(format(val(out), 10), "1267650600228229401496703205376");
            assert_eq!(
                msstd_bigint_pow(two, 100_000_000, &mut out),
                STATUS_LIMIT_EXCEEDED
            );
        }
    }

    #[test]
    fn conversions() {
        let big_one = big("9223372036854775808");
        assert!(big_one.to_i64().is_none());
        assert_eq!(
            format(&big("123456789012345678901234567890"), 10),
            "123456789012345678901234567890"
        );
        let huge = BigInt::from(1) << 2000usize;
        assert_eq!(huge.to_f64().unwrap_or(f64::INFINITY), f64::INFINITY);
        assert_eq!(
            (BigInt::from(1) << 70usize).to_f64(),
            Some(1180591620717411303424.0)
        );
        assert_eq!(format(&BigInt::from(-255), 16), "-ff");
    }
}
