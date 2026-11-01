//! `@std/math` natives. Symbols are `msstd_math_<name>`; every function takes and returns
//! scalars by value or writes ordinary result records through the existing record mechanism.
//!
//! The generic `max` and `min` are not natives: they are lowered by the
//! compiler through the element comparison.
use ms_rt::ffi::{STATUS_INVALID_INPUT, STATUS_OUT_OF_RANGE, StatusCode, abi_record, native};

abi_record! {
    /// `WordSum`, in declaration order.
    pub struct WordSumOut {
        pub sum: u64,
        pub carry: u8,
    }
}

abi_record! {
    /// `WordDifference`, in declaration order.
    pub struct WordDifferenceOut {
        pub difference: u64,
        pub borrow: u8,
    }
}

abi_record! {
    /// `WideProduct`, in declaration order.
    pub struct WideProductOut {
        pub high: u64,
        pub low: u64,
    }
}

abi_record! {
    /// `WordDivision`, in declaration order.
    pub struct WordDivisionOut {
        pub quotient: u64,
        pub remainder: u64,
    }
}

abi_record! {
    /// `BinaryFloatParts`, in declaration order.
    pub struct BinaryFloatPartsOut {
        pub fraction: f64,
        pub exponent: i64,
    }
}

abi_record! {
    /// `FloatParts`, in declaration order.
    pub struct FloatPartsOut {
        pub integer: f64,
        pub fraction: f64,
    }
}

macro_rules! unary {
    ($($sym:ident => $f:path),* $(,)?) => {$(
        native! { safe fn $sym(v: f64) -> f64 { $f(v) } }
    )*};
}

unary! {
    msstd_math_acos => f64::acos,
    msstd_math_asin => f64::asin,
    msstd_math_atan => f64::atan,
    msstd_math_ceil => f64::ceil,
    msstd_math_cos => f64::cos,
    msstd_math_cosh => f64::cosh,
    msstd_math_exp => f64::exp,
    msstd_math_floor => f64::floor,
    msstd_math_log => f64::ln,
    msstd_math_log10 => f64::log10,
    msstd_math_log2 => f64::log2,
    msstd_math_round => round,
    msstd_math_sin => f64::sin,
    msstd_math_sinh => f64::sinh,
    msstd_math_sqrt => f64::sqrt,
    msstd_math_tan => f64::tan,
    msstd_math_tanh => f64::tanh,
    msstd_math_truncate => f64::trunc,
    msstd_math_acosh => f64::acosh,
    msstd_math_asinh => f64::asinh,
    msstd_math_atanh => f64::atanh,
    msstd_math_cbrt => f64::cbrt,
    msstd_math_expm1 => f64::exp_m1,
    msstd_math_log1p => f64::ln_1p,
    msstd_math_exp2 => f64::exp2,
    msstd_math_round_to_even => f64::round_ties_even,
    msstd_math_sign => sign,
}

native! {
    fn msstd_math_add_with_carry(left: u64, right: u64, carry: bool) -> out WordSumOut {
        let (sum, carry) = left.carrying_add(right, carry);
        WordSumOut { sum, carry: u8::from(carry) }
    }

    fn msstd_math_subtract_with_borrow(left: u64, right: u64, borrow: bool) -> out WordDifferenceOut {
        let (difference, borrow) = left.borrowing_sub(right, borrow);
        WordDifferenceOut { difference, borrow: u8::from(borrow) }
    }

    fn msstd_math_multiply_wide(left: u64, right: u64) -> out WideProductOut {
        let product = u128::from(left) * u128::from(right);
        WideProductOut { high: (product >> 64) as u64, low: product as u64 }
    }

    fn msstd_math_divide_wide(high: u64, low: u64, divisor: u64) -> Result<WordDivisionOut, StatusCode> {
        if divisor == 0 {
            return Err(StatusCode(STATUS_INVALID_INPUT));
        }
        if high >= divisor {
            return Err(StatusCode(STATUS_OUT_OF_RANGE));
        }
        let dividend = (u128::from(high) << 64) | u128::from(low);
        let divisor = u128::from(divisor);
        Ok(WordDivisionOut { quotient: (dividend / divisor) as u64, remainder: (dividend % divisor) as u64 })
    }

    fn msstd_math_remainder_wide(high: u64, low: u64, divisor: u64) -> Result<u64, StatusCode> {
        if divisor == 0 {
            return Err(StatusCode(STATUS_INVALID_INPUT));
        }
        let dividend = (u128::from(high) << 64) | u128::from(low);
        Ok((dividend % u128::from(divisor)) as u64)
    }

    fn msstd_math_frexp(value: f64) -> out BinaryFloatPartsOut {
        let (fraction, exponent) = libm::frexp(value);
        BinaryFloatPartsOut { fraction, exponent: i64::from(exponent) }
    }

    fn msstd_math_modf(value: f64) -> out FloatPartsOut {
        let (fraction, integer) = libm::modf(value);
        FloatPartsOut { integer, fraction }
    }

    safe fn msstd_math_ldexp(fraction: f64, exponent: i64) -> f64 {
        // Beyond i32's range every nonzero finite binary64 overflows or underflows.
        // Clamping preserves that result and all zero, infinity and NaN cases.
        libm::ldexp(fraction, exponent.clamp(i64::from(i32::MIN), i64::from(i32::MAX)) as i32)
    }

    safe fn msstd_math_ieee_remainder(left: f64, right: f64) -> f64 {
        libm::remainder(left, right)
    }

    safe fn msstd_math_reverse_bits(value: i64) -> i64 {
        value.reverse_bits()
    }

    safe fn msstd_math_reverse_bytes(value: i64) -> i64 {
        value.swap_bytes()
    }

    safe fn msstd_math_copy_sign(value: f64, sign: f64) -> f64 {
        value.copysign(sign)
    }

    safe fn msstd_math_sign_bit(value: f64) -> bool {
        value.is_sign_negative()
    }

    safe fn msstd_math_next_after(value: f64, toward: f64) -> f64 {
        if value.is_nan() || toward.is_nan() {
            f64::NAN
        } else if value == toward {
            toward
        } else if value < toward {
            value.next_up()
        } else {
            value.next_down()
        }
    }

    safe fn msstd_math_fma(left: f64, right: f64, addend: f64) -> f64 {
        left.mul_add(right, addend)
    }

    safe fn msstd_math_atan2(y: f64, x: f64) -> f64 {
        y.atan2(x)
    }

    safe fn msstd_math_hypot(left: f64, right: f64) -> f64 {
        left.hypot(right)
    }

    safe fn msstd_math_pow(base: f64, exponent: f64) -> f64 {
        base.powf(exponent)
    }

    /// `Math.remainder` is C `fmod`, not the IEEE remainder.
    safe fn msstd_math_remainder(left: f64, right: f64) -> f64 {
        left % right
    }

    safe fn msstd_math_is_integer(v: f64) -> bool {
        is_integer(v)
    }

    safe fn msstd_math_is_safe_integer(v: f64) -> bool {
        is_integer(v) && v.abs() <= MAX_SAFE_INTEGER as f64
    }
}

/// `Math.round`: ties toward positive infinity, signed zero preserved.
fn round(value: f64) -> f64 {
    if value.is_nan() || value.is_infinite() || value == 0.0 {
        return value;
    }
    let mut lower = value.floor();
    if value - lower >= 0.5 {
        lower += 1.0;
    }
    if lower == 0.0 {
        return 0.0f64.copysign(value);
    }
    lower
}

/// `Math.sign`: -1, 0 or 1, keeping signed zero and NaN.
fn sign(v: f64) -> f64 {
    if v.is_nan() || v == 0.0 {
        v
    } else {
        v.signum()
    }
}

fn is_integer(v: f64) -> bool {
    v.is_finite() && v == v.trunc()
}

const MAX_SAFE_INTEGER: i64 = (1 << 53) - 1;
