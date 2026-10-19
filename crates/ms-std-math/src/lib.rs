//! `@std/math` natives. Symbols are `msstd_math_<name>`; every function takes and returns
//! scalars by value (`Float` = `f64`, `Int` = `i64`, `Bool` = `u8`), so the ABI is plain C.
//!
//! The generic `max`, `min`, `max_of` and `min_of` are not natives: they are lowered by the
//! compiler through the element comparison.
#![no_std]
// The exports below are the C ABI compiled code links against.
#![allow(unsafe_code)]

pub mod go;

unsafe extern "C-unwind" {
    fn msrt_fault_int_overflow() -> !;
}

macro_rules! unary {
    ($($sym:ident => $f:path),* $(,)?) => {$(
        #[unsafe(no_mangle)]
        pub extern "C" fn $sym(v: f64) -> f64 { $f(v) }
    )*};
}

macro_rules! constant {
    ($($sym:ident: $t:ty = $v:expr),* $(,)?) => {$(
        #[unsafe(no_mangle)]
        pub extern "C" fn $sym() -> $t { $v }
    )*};
}

unary! {
    msstd_math_abs => go::abs,
    msstd_math_acos => go::acos,
    msstd_math_asin => go::asin,
    msstd_math_atan => go::atan,
    msstd_math_ceil => go::ceil_,
    msstd_math_cos => go::cos,
    msstd_math_cosh => go::cosh,
    msstd_math_exp => go::exp,
    msstd_math_floor => go::floor_,
    msstd_math_log => go::log,
    msstd_math_log10 => go::log10,
    msstd_math_log2 => go::log2,
    msstd_math_round => go::round,
    msstd_math_sin => go::sin,
    msstd_math_sinh => go::sinh,
    msstd_math_sqrt => go::sqrt_,
    msstd_math_tan => go::tan,
    msstd_math_tanh => go::tanh,
    msstd_math_truncate => go::trunc_,
    msstd_math_acosh => go::acosh,
    msstd_math_asinh => go::asinh,
    msstd_math_atanh => go::atanh,
    msstd_math_cbrt => go::cbrt,
    msstd_math_expm1 => go::expm1,
    msstd_math_log1p => go::log1p,
    msstd_math_sign => go::sign,
    msstd_math_to_float32 => to_float32,
}

fn to_float32(v: f64) -> f64 {
    v as f32 as f64
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_math_atan2(y: f64, x: f64) -> f64 {
    go::atan2(y, x)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_math_hypot(left: f64, right: f64) -> f64 {
    go::hypot(left, right)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_math_pow(base: f64, exponent: f64) -> f64 {
    go::pow(base, exponent)
}

/// `Math.remainder` is Go's `math.Mod` (C `fmod`), not the IEEE remainder.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_math_remainder(left: f64, right: f64) -> f64 {
    go::fmod(left, right)
}

/// Faults on the one value whose magnitude does not fit.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_math_abs_int(n: i64) -> i64 {
    match n.checked_abs() {
        Some(v) => v,
        // SAFETY: provided by `ms-rt`; never returns.
        None => unsafe { msrt_fault_int_overflow() },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_math_sign_int(n: i64) -> i64 {
    n.signum()
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_math_is_integer(v: f64) -> u8 {
    go::is_integer(v) as u8
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_math_is_safe_integer(v: f64) -> u8 {
    (go::is_integer(v) && go::abs(v) <= MAX_SAFE_INTEGER as f64) as u8
}

const MAX_SAFE_INTEGER: i64 = (1 << 53) - 1;

constant! {
    msstd_math_e: f64 = core::f64::consts::E,
    msstd_math_pi: f64 = core::f64::consts::PI,
    msstd_math_infinity: f64 = f64::INFINITY,
    msstd_math_nan: f64 = go::nan(),
    msstd_math_epsilon: f64 = 1.0 / (1u64 << 52) as f64,
    msstd_math_max_float: f64 = f64::MAX,
    msstd_math_min_float: f64 = 5e-324,
    msstd_math_max_int: i64 = i64::MAX,
    msstd_math_min_int: i64 = i64::MIN,
    msstd_math_max_safe_integer: i64 = MAX_SAFE_INTEGER,
    msstd_math_min_safe_integer: i64 = -MAX_SAFE_INTEGER,
    msstd_math_ln2: f64 = go::LN2,
    msstd_math_ln10: f64 = go::LN10,
    msstd_math_log2e: f64 = go::LOG2E,
    msstd_math_log10e: f64 = go::LOG10E,
    msstd_math_sqrt2: f64 = core::f64::consts::SQRT_2,
    msstd_math_sqrt_half: f64 = core::f64::consts::SQRT_2 / 2.0,
}
