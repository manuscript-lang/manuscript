//! `@std/bigint.ms` natives. Symbols are `msstd_bigint_<name>`.
//!
//! A `BigInt` is an immutable refcounted [`Big`] handle; operations return fresh handles.
//! Fallible calls return a `STATUS_*` code and write `out` only on success; `to_int` returns
//! a presence flag (0 where the value does not fit an `Int`).
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

use alloc::string::String;
use ms_rt_abi::{STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED};
use ms_std_core::{ObjRef, Object, Out, Status, abi_handle, native};
use ms_std_rt::{fault_fmt, poll_cancel};
use num_bigint::{BigInt, Sign};
use num_traits::{Signed, ToPrimitive, Zero};

/// The value behind a `BigInt` runtime object.
pub struct Big(BigInt);
abi_handle!(Big);

/// A bare `STATUS_*` byte as an error.
pub struct Code(u8);

impl Status for Code {
    fn status(self) -> u8 {
        self.0
    }
}

/// Result size ceiling in bits for `pow` and `shift_left`.
const MAX_BITS: i64 = 1 << 24;

fn make(n: BigInt) -> Object<Big> {
    Object(Big(n))
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

fn n<'a>(a: &'a ObjRef<Big>) -> &'a BigInt {
    &a.0.0
}

native! {
    fn msstd_bigint_from_int(value: i64) -> Object<Big> {
        make(BigInt::from(value))
    }

    /// The unsigned integer with the bits of `value`.
    fn msstd_bigint_from_u64(value: i64) -> Object<Big> {
        make(BigInt::from(value as u64))
    }

    /// Nanoseconds since the Unix epoch for a seconds-and-nanoseconds pair.
    fn msstd_bigint_from_seconds_nanos(seconds: i64, nanoseconds: i64) -> Object<Big> {
        make(BigInt::from(seconds) * BigInt::from(1_000_000_000_i64) + BigInt::from(nanoseconds))
    }

    fn msstd_bigint_parse(
        text: &str,
        radix: i64,
        has_max: bool,
        max: i64,
    ) -> Result<Object<Big>, Code> {
        parse(text.as_bytes(), radix, has_max.then_some(max))
            .map(make)
            .map_err(Code)
    }

    fn msstd_bigint_add(a: ObjRef<Big>, other: ObjRef<Big>) -> Object<Big> {
        make(n(&a) + n(&other))
    }

    fn msstd_bigint_subtract(a: ObjRef<Big>, other: ObjRef<Big>) -> Object<Big> {
        make(n(&a) - n(&other))
    }

    fn msstd_bigint_multiply(a: ObjRef<Big>, other: ObjRef<Big>) -> Object<Big> {
        make(n(&a) * n(&other))
    }

    fn msstd_bigint_bit_and(a: ObjRef<Big>, other: ObjRef<Big>) -> Object<Big> {
        make(n(&a) & n(&other))
    }

    fn msstd_bigint_bit_or(a: ObjRef<Big>, other: ObjRef<Big>) -> Object<Big> {
        make(n(&a) | n(&other))
    }

    fn msstd_bigint_bit_xor(a: ObjRef<Big>, other: ObjRef<Big>) -> Object<Big> {
        make(n(&a) ^ n(&other))
    }

    /// Truncates toward zero.
    fn msstd_bigint_divide(a: ObjRef<Big>, other: ObjRef<Big>) -> Result<Object<Big>, Code> {
        if n(&other).is_zero() {
            return Err(Code(STATUS_INVALID_INPUT));
        }
        Ok(make(n(&a) / n(&other)))
    }

    /// Takes the sign of the dividend.
    fn msstd_bigint_remainder(a: ObjRef<Big>, other: ObjRef<Big>) -> Result<Object<Big>, Code> {
        if n(&other).is_zero() {
            return Err(Code(STATUS_INVALID_INPUT));
        }
        Ok(make(n(&a) % n(&other)))
    }

    fn msstd_bigint_compare(a: ObjRef<Big>, other: ObjRef<Big>) -> i64 {
        n(&a).cmp(n(&other)) as i64
    }

    fn msstd_bigint_bit_not(a: ObjRef<Big>) -> Object<Big> {
        make(!n(&a).clone())
    }

    fn msstd_bigint_negate(a: ObjRef<Big>) -> Object<Big> {
        make(-n(&a).clone())
    }

    fn msstd_bigint_abs(a: ObjRef<Big>) -> Object<Big> {
        make(n(&a).abs())
    }

    fn msstd_bigint_sign(a: ObjRef<Big>) -> i64 {
        match n(&a).sign() {
            Sign::Minus => -1,
            Sign::NoSign => 0,
            Sign::Plus => 1,
        }
    }

    fn msstd_bigint_pow(a: ObjRef<Big>, exponent: i64) -> Result<Object<Big>, Code> {
        if exponent < 0 {
            return Err(Code(STATUS_INVALID_INPUT));
        }
        let bits = i64::try_from(n(&a).bits()).unwrap_or(i64::MAX);
        if exponent > 1
            && bits > 1
            && (exponent > MAX_BITS || bits.saturating_mul(exponent) > MAX_BITS + exponent)
        {
            return Err(Code(STATUS_LIMIT_EXCEEDED));
        }
        poll_cancel();
        Ok(make(num_traits::pow::Pow::pow(n(&a), exponent as u64)))
    }

    fn msstd_bigint_shift_left(a: ObjRef<Big>, count: i64) -> Result<Object<Big>, Code> {
        if count < 0 {
            return Err(Code(STATUS_INVALID_INPUT));
        }
        let bits = i64::try_from(n(&a).bits()).unwrap_or(i64::MAX);
        if count > MAX_BITS || bits.saturating_add(count) > MAX_BITS {
            return Err(Code(STATUS_LIMIT_EXCEEDED));
        }
        Ok(make(n(&a) << count as usize))
    }

    fn msstd_bigint_shift_right(a: ObjRef<Big>, count: i64) -> Result<Object<Big>, Code> {
        if count < 0 {
            return Err(Code(STATUS_INVALID_INPUT));
        }
        let bits = i64::try_from(n(&a).bits()).unwrap_or(i64::MAX);
        // Shifting by more than the width gives 0 or -1 (floor semantics).
        let count = count.min(bits.saturating_add(1)) as usize;
        Ok(make(n(&a) >> count))
    }

    fn msstd_bigint_to_float(a: ObjRef<Big>) -> f64 {
        // Out of range: infinity of the same sign.
        n(&a).to_f64().unwrap_or(if n(&a).is_negative() {
            f64::NEG_INFINITY
        } else {
            f64::INFINITY
        })
    }

    /// Writes `out` and returns true when the value fits an `Int`.
    fn msstd_bigint_to_int(a: ObjRef<Big>, out: Out<i64>) -> bool {
        match n(&a).to_i64() {
            Some(v) => {
                out.write(v);
                true
            }
            None => false,
        }
    }

    fn msstd_bigint_to_string_radix(a: ObjRef<Big>, radix: i64) -> String {
        if !(2..=36).contains(&radix) {
            fault_fmt(format_args!(
                "BigInt.to_string_radix: radix must be between 2 and 36, found {radix}"
            ));
        }
        format(n(&a), radix as u32)
    }

    /// Whether two values hold the same integer.
    fn msstd_bigint_equal(a: ObjRef<Big>, other: ObjRef<Big>) -> bool {
        n(&a) == n(&other)
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use ms_rt as _; // links the msrt_* runtime symbols
    use ms_rt_abi::STATUS_OK;
    use ms_std_core::{FromAbi, ObjCell};

    fn big(text: &str) -> BigInt {
        parse(text.as_bytes(), 10, None).expect("parse")
    }

    /// # Safety
    /// `p` is a live handle.
    unsafe fn val<'a>(p: *const ObjCell<Big>) -> &'a BigInt {
        // SAFETY: caller contract.
        &unsafe { ObjRef::<Big>::from_raw(p) }.0.0
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
        let mut out: *mut ObjCell<Big> = core::ptr::null_mut();
        // SAFETY: handles are live until released by the process.
        unsafe {
            let a = msstd_bigint_from_int(-5);
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
