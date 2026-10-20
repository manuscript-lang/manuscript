//! `@std/math` natives. Symbols are `msstd_math_<name>`; every function takes and returns
//! scalars by value (`Float` = `f64`, `Int` = `i64`, `Bool` = `u8`), so the ABI is plain C.
//!
//! The generic `max`, `min`, `max_of` and `min_of` are not natives: they are lowered by the
//! compiler through the element comparison.
#![no_std]
// The exports below are the C ABI compiled code links against.
#![allow(unsafe_code)]

mod libm;

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
    msstd_math_abs => f64::abs,
    msstd_math_acos => libm::acos_,
    msstd_math_asin => libm::asin_,
    msstd_math_atan => libm::atan_,
    msstd_math_ceil => libm::ceil_,
    msstd_math_cos => libm::cos_,
    msstd_math_cosh => libm::cosh_,
    msstd_math_exp => libm::exp_,
    msstd_math_floor => libm::floor_,
    msstd_math_log => libm::log_,
    msstd_math_log10 => libm::log10_,
    msstd_math_log2 => libm::log2_,
    msstd_math_round => libm::round,
    msstd_math_sin => libm::sin_,
    msstd_math_sinh => libm::sinh_,
    msstd_math_sqrt => libm::sqrt_,
    msstd_math_tan => libm::tan_,
    msstd_math_tanh => libm::tanh_,
    msstd_math_truncate => libm::trunc_,
    msstd_math_acosh => libm::acosh_,
    msstd_math_asinh => libm::asinh_,
    msstd_math_atanh => libm::atanh_,
    msstd_math_cbrt => libm::cbrt_,
    msstd_math_expm1 => libm::expm1_,
    msstd_math_log1p => libm::log1p_,
    msstd_math_sign => libm::sign,
    msstd_math_to_float32 => to_float32,
}

fn to_float32(v: f64) -> f64 {
    v as f32 as f64
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_math_atan2(y: f64, x: f64) -> f64 {
    libm::atan2_(y, x)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_math_hypot(left: f64, right: f64) -> f64 {
    libm::hypot_(left, right)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_math_pow(base: f64, exponent: f64) -> f64 {
    libm::pow_(base, exponent)
}

/// `Math.remainder` is C `fmod`, not the IEEE remainder.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_math_remainder(left: f64, right: f64) -> f64 {
    libm::fmod_(left, right)
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
    libm::is_integer(v) as u8
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_math_is_safe_integer(v: f64) -> u8 {
    (libm::is_integer(v) && v.abs() <= MAX_SAFE_INTEGER as f64) as u8
}

const MAX_SAFE_INTEGER: i64 = (1 << 53) - 1;

constant! {
    msstd_math_e: f64 = core::f64::consts::E,
    msstd_math_pi: f64 = core::f64::consts::PI,
    msstd_math_infinity: f64 = f64::INFINITY,
    msstd_math_nan: f64 = f64::NAN,
    msstd_math_epsilon: f64 = 1.0 / (1u64 << 52) as f64,
    msstd_math_max_float: f64 = f64::MAX,
    msstd_math_min_float: f64 = 5e-324,
    msstd_math_max_int: i64 = i64::MAX,
    msstd_math_min_int: i64 = i64::MIN,
    msstd_math_max_safe_integer: i64 = MAX_SAFE_INTEGER,
    msstd_math_min_safe_integer: i64 = -MAX_SAFE_INTEGER,
    msstd_math_ln2: f64 = core::f64::consts::LN_2,
    msstd_math_ln10: f64 = core::f64::consts::LN_10,
    msstd_math_log2e: f64 = core::f64::consts::LOG2_E,
    msstd_math_log10e: f64 = core::f64::consts::LOG10_E,
    msstd_math_sqrt2: f64 = core::f64::consts::SQRT_2,
    msstd_math_sqrt_half: f64 = core::f64::consts::SQRT_2 / 2.0,
}
