//! `@std/math` natives. Symbols are `msstd_math_<name>`; every function takes and returns
//! scalars by value (`Float` = `f64`, `Int` = `i64`, `Bool` = `u8`), so the ABI is plain C.
//!
//! The generic `max` and `min` are not natives: they are lowered by the
//! compiler through the element comparison.
// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

use ms_rt::ffi::native;

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
    msstd_math_sign => sign,
}

native! {
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
