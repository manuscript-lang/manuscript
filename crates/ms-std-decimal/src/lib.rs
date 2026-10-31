//! `@std/decimal.ms` natives.
//!
//! A `Decimal` is `coefficient * 10^exponent` with at most 34 significant digits and the
//! coefficient free of trailing zeros, so equal values have equal representations. Operators
//! compute exactly and round half-even to 34 digits; magnitudes beyond `9.99...e6144` fault.
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

#[cfg(feature = "ffi")]
pub mod ffi;

use alloc::format;
use alloc::string::{String, ToString};
use num_bigint::{BigInt, Sign};
use num_integer::Integer;
use num_traits::{Signed, ToPrimitive, Zero};

/// Significant digits of the format.
const DIGITS: i64 = 34;
/// Smallest exponent a coefficient can carry.
const MIN_QUANTUM: i64 = -6176;
/// Largest exponent of the leading digit.
const MAX_EXPONENT: i64 = 6144;

/// The runtime layout of a `Decimal`: the coefficient as a 128-bit integer split in two words, and
/// the exponent.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Dec {
    pub lo: u64,
    pub hi: i64,
    pub exp: i64,
}

/// An arithmetic fault.
#[derive(Debug, PartialEq, Eq)]
pub enum Overflow {
    /// The rounded magnitude exceeds the format.
    Magnitude,
}

/// How `round` and `to_fixed` break ties and discard digits (declaration order of `RoundingMode`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    HalfEven,
    HalfAwayFromZero,
    TowardZero,
    Floor,
    Ceil,
}

impl Mode {
    /// The mode named by a case index.
    pub fn from_index(i: i64) -> Option<Mode> {
        Some(match i {
            0 => Mode::HalfEven,
            1 => Mode::HalfAwayFromZero,
            2 => Mode::TowardZero,
            3 => Mode::Floor,
            4 => Mode::Ceil,
            _ => return None,
        })
    }
}

fn pow10(n: i64) -> BigInt {
    BigInt::from(10u32).pow(u32::try_from(n).unwrap_or(u32::MAX))
}

fn sign_of(negative: bool) -> Sign {
    if negative { Sign::Minus } else { Sign::Plus }
}

fn digit_count(n: &BigInt) -> i64 {
    n.magnitude().to_string().len() as i64
}

/// Strips trailing zeros of the coefficient; zero is `0e0`.
fn normalize(mut coef: BigInt, mut exp: i64) -> (BigInt, i64) {
    if coef.is_zero() {
        return (coef, 0);
    }
    let ten = BigInt::from(10u32);
    loop {
        let (q, r) = coef.div_rem(&ten);
        if !r.is_zero() {
            return (coef, exp);
        }
        coef = q;
        exp += 1;
    }
}

impl Dec {
    pub const ZERO: Dec = Dec {
        lo: 0,
        hi: 0,
        exp: 0,
    };

    /// Packs a normalized coefficient of at most 34 digits.
    fn pack(coef: &BigInt, exp: i64) -> Dec {
        Dec::pack_wide(coef.to_i128().unwrap_or(0), exp)
    }

    fn pack_wide(wide: i128, exp: i64) -> Dec {
        Dec {
            lo: wide as u64,
            hi: (wide >> 64) as i64,
            exp: if wide == 0 { 0 } else { exp },
        }
    }

    fn coefficient(&self) -> BigInt {
        BigInt::from((i128::from(self.hi) << 64) | i128::from(self.lo))
    }

    /// The decimal digits of a value `digits * 10^quantum`, with its sign.
    pub fn parts(text: &str) -> Option<(BigInt, i64)> {
        let raw = text.strip_suffix('d').unwrap_or(text);
        let negative = raw.starts_with('-');
        let raw = raw.strip_prefix(['-', '+']).unwrap_or(raw);
        let (mantissa, exponent_text) = match raw.find(['e', 'E']) {
            Some(at) => (&raw[..at], &raw[at + 1..]),
            None => (raw, "0"),
        };
        let exp_digits = exponent_text
            .strip_prefix(['-', '+'])
            .unwrap_or(exponent_text);
        if exp_digits.is_empty()
            || mantissa.is_empty()
            || !exp_digits.bytes().all(|c| c.is_ascii_digit())
        {
            return None;
        }
        let (coefficient, fraction) = match mantissa.find('.') {
            Some(at) => {
                if at == 0 || at == mantissa.len() - 1 {
                    return None;
                }
                let digits = alloc::format!("{}{}", &mantissa[..at], &mantissa[at + 1..]);
                (digits, (mantissa.len() - at - 1) as i64)
            }
            None => (mantissa.to_string(), 0),
        };
        if !coefficient.bytes().all(|c| c.is_ascii_digit()) {
            return None;
        }
        let coefficient = coefficient.trim_start_matches('0');
        if coefficient.is_empty() {
            return Some((BigInt::zero(), 0));
        }
        let exponent: i32 = exponent_text.parse().ok()?;
        let trimmed = coefficient.trim_end_matches('0');
        let quantum = i64::from(exponent) - fraction + (coefficient.len() - trimmed.len()) as i64;
        let valid = trimmed.len() as i64 <= DIGITS
            && quantum >= MIN_QUANTUM
            && quantum + trimmed.len() as i64 - 1 <= MAX_EXPONENT;
        if !valid {
            return None;
        }
        let mut n: BigInt = trimmed.parse().ok()?;
        if negative {
            n = -n;
        }
        Some((n, quantum))
    }

    /// The Decimal of a literal the checker accepted; `None` when it is not valid.
    pub fn parse(text: &str) -> Option<Dec> {
        let (coef, exp) = Dec::parts(text)?;
        Some(Dec::pack(&coef, exp))
    }

    pub fn from_int(n: i64) -> Dec {
        Dec::from_integer(n.unsigned_abs(), n < 0)
    }

    pub fn from_uint(n: u64) -> Dec {
        Dec::from_integer(n, false)
    }

    fn from_integer(mut magnitude: u64, negative: bool) -> Dec {
        if magnitude == 0 {
            return Dec::ZERO;
        }
        let mut exp = 0;
        while magnitude.is_multiple_of(10) {
            magnitude /= 10;
            exp += 1;
        }
        let coefficient = i128::from(magnitude);
        Dec::pack_wide(if negative { -coefficient } else { coefficient }, exp)
    }

    pub fn is_zero(&self) -> bool {
        self.lo == 0 && self.hi == 0
    }

    /// Rounds the exact value `coef * 10^exp` half-even to 34 digits.
    fn rounded(coef: BigInt, exp: i64) -> Result<Dec, Overflow> {
        if coef.is_zero() {
            return Ok(Dec::ZERO);
        }
        let digits = digit_count(&coef);
        let exponent = exp + digits - 1;
        let q = (exponent - (DIGITS - 1)).max(MIN_QUANTUM);
        let drop = q - exp;
        let (coef, exp) = if drop <= 0 {
            (coef, exp)
        } else {
            let negative = coef.is_negative();
            let denominator = pow10(drop).into_parts().1;
            let (mut c, rem) = coef.magnitude().div_rem(&denominator);
            let twice = &rem << 1usize;
            if twice > denominator || (twice == denominator && c.is_odd()) {
                c += 1u32;
            }
            (BigInt::from_biguint(sign_of(negative), c), q)
        };
        let (coef, exp) = normalize(coef, exp);
        if !coef.is_zero() && exp + digit_count(&coef) - 1 > MAX_EXPONENT {
            return Err(Overflow::Magnitude);
        }
        Ok(Dec::pack(&coef, exp))
    }

    pub fn negate(&self) -> Dec {
        // Every valid coefficient has at most 34 decimal digits, so its negation fits i128.
        let coefficient = (i128::from(self.hi) << 64) | i128::from(self.lo);
        Dec::pack_wide(-coefficient, self.exp)
    }

    /// The exact sum and difference share one alignment.
    fn combine(&self, other: &Dec, subtract: bool) -> Result<Dec, Overflow> {
        if other.is_zero() {
            return Ok(*self);
        }
        if self.is_zero() {
            return Ok(if subtract { other.negate() } else { *other });
        }
        let (a, b) = (self.coefficient(), other.coefficient());
        let b = if subtract { -b } else { b };
        let exp = self.exp.min(other.exp);
        let sum = a * pow10(self.exp - exp) + b * pow10(other.exp - exp);
        Dec::rounded(sum, exp)
    }

    pub fn add(&self, other: &Dec) -> Result<Dec, Overflow> {
        self.combine(other, false)
    }

    pub fn subtract(&self, other: &Dec) -> Result<Dec, Overflow> {
        self.combine(other, true)
    }

    pub fn multiply(&self, other: &Dec) -> Result<Dec, Overflow> {
        Dec::rounded(
            self.coefficient() * other.coefficient(),
            self.exp + other.exp,
        )
    }

    /// The quotient; `other` must not be zero.
    pub fn divide(&self, other: &Dec) -> Result<Dec, Overflow> {
        let (a, b) = (self.coefficient(), other.coefficient());
        if a.is_zero() {
            return Ok(Dec::ZERO);
        }
        let negative = a.is_negative() != b.is_negative();
        let (a, b) = (a.magnitude(), b.magnitude());
        let shift =
            (DIGITS + 2 + digit_count(&b.clone().into()) - digit_count(&a.clone().into())).max(0);
        let (mut q, r) = (a * pow10(shift).magnitude()).div_rem(b);
        let mut exp = self.exp - other.exp - shift;
        if !r.is_zero() {
            // A sticky digit: the quotient has at least 35 digits, so it only breaks ties.
            q = q * 10u32 + 1u32;
            exp -= 1;
        }
        Dec::rounded(BigInt::from_biguint(sign_of(negative), q), exp)
    }

    pub fn compare(&self, other: &Dec) -> i64 {
        let (a, b) = (self.coefficient(), other.coefficient());
        match (a.sign(), b.sign()) {
            (Sign::NoSign, Sign::NoSign) => return 0,
            (Sign::Minus, Sign::NoSign | Sign::Plus) | (Sign::NoSign, Sign::Plus) => return -1,
            (Sign::Plus, Sign::NoSign | Sign::Minus) | (Sign::NoSign, Sign::Minus) => return 1,
            _ => {}
        }
        let ordering = if self.exp == other.exp {
            a.cmp(&b)
        } else if (self.exp - other.exp).abs() >= DIGITS {
            // Nonzero coefficients have 1..=34 digits. Beyond that gap,
            // the higher quantum has the greater magnitude, regardless of digits.
            let magnitude = self.exp.cmp(&other.exp);
            if a.is_negative() {
                magnitude.reverse()
            } else {
                magnitude
            }
        } else {
            let exp = self.exp.min(other.exp);
            let (x, y) = (a * pow10(self.exp - exp), b * pow10(other.exp - exp));
            x.cmp(&y)
        };
        match ordering {
            core::cmp::Ordering::Less => -1,
            core::cmp::Ordering::Equal => 0,
            core::cmp::Ordering::Greater => 1,
        }
    }

    /// The text of interpolation: at most 34 significant digits.
    pub fn render(&self) -> String {
        if self.is_zero() {
            return "0".to_string();
        }
        let coef = self.coefficient();
        let digits = coef.magnitude().to_string();
        let exponent = self.exp + digits.len() as i64 - 1;
        let digits = digits.trim_end_matches('0');
        let sign = if coef.is_negative() { "-" } else { "" };
        if (-6..=20).contains(&exponent) {
            let point = exponent + 1;
            if point <= 0 {
                let zeros = "0".repeat((-point) as usize);
                return format!("{sign}0.{zeros}{digits}");
            }
            if point as usize >= digits.len() {
                let zeros = "0".repeat(point as usize - digits.len());
                return format!("{sign}{digits}{zeros}");
            }
            return format!(
                "{sign}{}.{}",
                &digits[..point as usize],
                &digits[point as usize..]
            );
        }
        let mut out = format!("{sign}{}", &digits[..1]);
        if digits.len() > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        let plus = if exponent >= 0 { "+" } else { "" };
        format!("{out}e{plus}{exponent}")
    }

    /// The nearest `f64`; beyond the range this is an infinity.
    pub fn to_float(&self) -> f64 {
        if self.is_zero() {
            return 0.0;
        }
        format!("{}e{}", self.coefficient(), self.exp)
            .parse()
            .unwrap_or(0.0)
    }

    /// The integer part toward zero, when it fits an `i64`.
    pub fn truncate_to_int(&self) -> Option<i64> {
        let coef = self.coefficient();
        if self.exp >= 0 {
            if coef.is_zero() {
                return Some(0);
            }
            if self.exp > 19 {
                return None;
            }
            return (coef * pow10(self.exp)).to_i64();
        }
        if -self.exp > 40 {
            return Some(0);
        }
        (coef / pow10(-self.exp)).to_i64()
    }

    /// The coefficient of `self` rounded to a multiple of `10^-places`.
    fn scaled_coefficient(&self, places: i64, mode: Mode) -> BigInt {
        let coef = self.coefficient();
        let shift = self.exp + places;
        if shift >= 0 {
            return coef * pow10(shift);
        }
        let denominator = pow10(-shift).into_parts().1;
        let negative = coef.is_negative();
        let (mut c, rem) = coef.magnitude().div_rem(&denominator);
        if !rem.is_zero() {
            let twice = &rem << 1usize;
            let cmp = twice.cmp(&denominator);
            let increment = match mode {
                Mode::HalfEven => cmp.is_gt() || (cmp.is_eq() && c.is_odd()),
                Mode::HalfAwayFromZero => cmp.is_ge(),
                Mode::TowardZero => false,
                Mode::Floor => negative,
                Mode::Ceil => !negative,
            };
            if increment {
                c += 1u32;
            }
        }
        BigInt::from_biguint(sign_of(negative), c)
    }

    /// `round(places, mode)`: `Err(false)` for invalid places, `Err(true)` when out of range.
    pub fn round(&self, places: i64, mode: Mode) -> Result<Dec, RoundFail> {
        if !(-6144..=6176).contains(&places) {
            return Err(RoundFail::InvalidInput);
        }
        // A normalized value is already an exact multiple of this quantum.
        if self.is_zero() || self.exp + places >= 0 {
            return Ok(*self);
        }
        let coefficient = self.scaled_coefficient(places, mode);
        let (coef, exp) = normalize(coefficient, -places);
        if !coef.is_zero() {
            let digits = digit_count(&coef);
            if digits > DIGITS || exp < MIN_QUANTUM || exp + digits - 1 > MAX_EXPONENT {
                return Err(RoundFail::OutOfRange);
            }
        }
        Ok(Dec::pack(&coef, exp))
    }

    /// `to_fixed(digits, mode)`: plain notation with exactly `digits` fractional digits.
    pub fn to_fixed(&self, digits: i64, mode: Mode) -> Result<String, RoundFail> {
        if !(0..=6176).contains(&digits) {
            return Err(RoundFail::InvalidInput);
        }
        let coefficient = self.scaled_coefficient(digits, mode);
        let negative = coefficient.is_negative();
        let mut text = coefficient.magnitude().to_string();
        let digits = digits as usize;
        if digits > 0 {
            if text.len() <= digits {
                text = format!("{}{text}", "0".repeat(digits + 1 - text.len()));
            }
            let point = text.len() - digits;
            text = format!("{}.{}", &text[..point], &text[point..]);
        }
        Ok(if negative { format!("-{text}") } else { text })
    }
}

/// Why `round` or `to_fixed` failed (`NumberError` cases).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RoundFail {
    InvalidInput,
    OutOfRange,
}

/// The message of an arithmetic overflow fault.
pub fn overflow_message(operation: &str, left: &Dec, right: &Dec) -> String {
    format!(
        "Decimal.{operation}: overflow; found left {} and right {}; rounded magnitude must be at most 9.999999999999999999999999999999999e6144 (34 significant digits)",
        left.render(),
        right.render()
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(text: &str) -> Dec {
        Dec::parse(text).expect("valid literal")
    }

    #[test]
    fn arithmetic_is_exact() {
        assert_eq!(d("0.1d").add(&d("0.2d")), Ok(d("0.3d")));
        assert_eq!(d("1.00d"), d("1d"));
        assert_eq!(
            d("1d").divide(&d("3d")).unwrap().render(),
            "0.3333333333333333333333333333333333"
        );
        assert_eq!(
            d("2d").divide(&d("3d")).unwrap().render(),
            "0.6666666666666666666666666666666667"
        );
        assert_eq!(
            d("-1d").divide(&d("3d")).unwrap().render(),
            "-0.3333333333333333333333333333333333"
        );
        assert_eq!(d("1d").divide(&d("8d")).unwrap().render(), "0.125");
        assert_eq!(Dec::parse("12345678901234567890123456789012345d"), None);
        assert_eq!(d("1e6144d").multiply(&d("10d")), Err(Overflow::Magnitude));
        assert_eq!(d("5d").subtract(&d("5d")), Ok(Dec::ZERO));
    }

    #[test]
    fn rendering() {
        assert_eq!(d("1.50d").render(), "1.5");
        assert_eq!(d("0.000001d").render(), "0.000001");
        assert_eq!(d("0.0000001d").render(), "1e-7");
        assert_eq!(
            d("100000000000000000000d").render(),
            "100000000000000000000"
        );
        assert_eq!(d("1e21d").render(), "1e+21");
        assert_eq!(d("-12.5d").render(), "-12.5");
        assert_eq!(Dec::ZERO.render(), "0");
    }

    #[test]
    fn conversions() {
        assert_eq!(d("-1.9d").truncate_to_int(), Some(-1));
        assert_eq!(d("1e30d").truncate_to_int(), None);
        assert_eq!(d("2d").to_float(), 2.0);
        assert_eq!(d("0.1d").to_float(), 0.1);
        assert_eq!(Dec::from_int(123), d("123d"));
    }

    #[test]
    fn integer_conversions_match_bigint_normalization() {
        let check = |signed: i64, unsigned: u64| {
            let (coefficient, exp) = normalize(BigInt::from(signed), 0);
            assert_eq!(Dec::from_int(signed), Dec::pack(&coefficient, exp));
            let (coefficient, exp) = normalize(BigInt::from(unsigned), 0);
            assert_eq!(Dec::from_uint(unsigned), Dec::pack(&coefficient, exp));
        };
        for n in [0, 1, 9, 10, 100, i64::MAX as u64, 1u64 << 63, u64::MAX] {
            check(n as i64, n);
        }
        let mut power = 1u64;
        for _ in 0..19 {
            for n in [power - 1, power, power + 1] {
                check(n as i64, n);
                check(-(n as i64), n);
            }
            power *= 10;
        }
        let mut sample = 0x9e3779b97f4a7c15u64;
        for _ in 0..10000 {
            sample = sample.wrapping_mul(6364136223846793005).wrapping_add(1);
            check(sample as i64, sample);
        }
    }

    #[test]
    fn negation_preserves_normalized_coefficients_and_quantum() {
        for text in [
            "0",
            "1",
            "-1",
            "1.25",
            "-1.25",
            "9223372036854775808",
            "9999999999999999999999999999999999",
            "1e-6176",
            "1e6144",
            "9.999999999999999999999999999999999e6144",
        ] {
            let value = d(text);
            let expected = Dec::pack(&-value.coefficient(), value.exp);
            assert_eq!(value.negate(), expected, "{text}");
            assert_eq!(expected.negate(), value, "{text}");
        }
    }

    #[test]
    fn rounding() {
        assert_eq!(d("2.5d").round(0, Mode::HalfEven), Ok(d("2d")));
        assert_eq!(d("2.5d").round(0, Mode::HalfAwayFromZero), Ok(d("3d")));
        assert_eq!(d("-2.5d").round(0, Mode::Floor), Ok(d("-3d")));
        assert_eq!(d("2.1d").round(0, Mode::Ceil), Ok(d("3d")));
        assert_eq!(d("1234d").round(-2, Mode::HalfEven), Ok(d("1200d")));
        assert_eq!(
            d("1d").round(7000, Mode::HalfEven),
            Err(RoundFail::InvalidInput)
        );
        assert_eq!(d("1.005d").to_fixed(2, Mode::HalfEven).unwrap(), "1.00");
        assert_eq!(d("-0.001d").to_fixed(2, Mode::HalfEven).unwrap(), "0.00");
        assert_eq!(d("5d").to_fixed(0, Mode::HalfEven).unwrap(), "5");
        assert_eq!(d("0.5d").to_fixed(3, Mode::HalfEven).unwrap(), "0.500");
    }

    #[test]
    fn comparison_matches_exact_alignment_at_precision_boundaries() {
        let texts = [
            "0",
            "1",
            "-1",
            "9",
            "11",
            "9999999999999999999999999999999999",
        ];
        for gap in [0, 1, 32, 33, 34, 35, 6144] {
            for left in texts {
                for right in texts {
                    let a = d(&format!("{left}e{}", gap - 6176));
                    let b = d(&format!("{right}e-6176"));
                    let exp = a.exp.min(b.exp);
                    let expected = (a.coefficient() * pow10(a.exp - exp))
                        .cmp(&(b.coefficient() * pow10(b.exp - exp)))
                        as i64;
                    assert_eq!(a.compare(&b), expected, "{left} {right} {gap}");
                    assert_eq!(b.compare(&a), -expected);
                    assert_eq!(a.negate().compare(&b.negate()), -expected);
                }
            }
        }
        assert_eq!(d("1e6144").compare(&d("1e-6176")), 1);
        assert_eq!(d("-1e6144").compare(&d("-1e-6176")), -1);
    }

    #[test]
    fn zero_addition_and_subtraction_preserve_values() {
        for text in [
            "0",
            "1.25",
            "-1.25",
            "1e6144",
            "-1e6144",
            "1e-6176",
            "-1e-6176",
            "9.999999999999999999999999999999999e6144",
        ] {
            let value = d(text);
            assert_eq!(value.add(&Dec::ZERO), Ok(value));
            assert_eq!(Dec::ZERO.add(&value), Ok(value));
            assert_eq!(value.subtract(&Dec::ZERO), Ok(value));
            assert_eq!(Dec::ZERO.subtract(&value), Ok(value.negate()));
        }
        assert_eq!(
            d("9.999999999999999999999999999999999e6144").add(&d("1e6144")),
            Err(Overflow::Magnitude)
        );
        assert_eq!(d("1.25").add(&d("-1.25")), Ok(Dec::ZERO));
    }

    #[test]
    fn rounding_exact_values_preserves_normalized_representation() {
        for mode in [
            Mode::HalfEven,
            Mode::HalfAwayFromZero,
            Mode::TowardZero,
            Mode::Floor,
            Mode::Ceil,
        ] {
            for text in [
                "0", "1.25", "-1.25", "1e6144", "-1e6144", "1e-6176", "-1e-6176",
            ] {
                let value = d(text);
                for places in [(-value.exp).max(-6144), 6176] {
                    assert_eq!(value.round(places, mode), Ok(value));
                }
                for places in [i64::MIN, -6145, 6177, i64::MAX] {
                    assert_eq!(value.round(places, mode), Err(RoundFail::InvalidInput));
                }
            }
            assert_eq!(
                d("9.999999999999999999999999999999999e6144").round(-6144, mode),
                if mode == Mode::TowardZero || mode == Mode::Floor {
                    Ok(d("9e6144"))
                } else {
                    Err(RoundFail::OutOfRange)
                }
            );
        }
    }

    #[test]
    fn comparison() {
        assert_eq!(d("1.0d").compare(&d("1d")), 0);
        assert_eq!(d("-2d").compare(&d("1d")), -1);
        assert_eq!(d("1e100d").compare(&d("1e-100d")), 1);
    }
}
