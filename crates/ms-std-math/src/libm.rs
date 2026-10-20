//! The C math library routines behind `@std/math`. Results follow the host libm and can differ
//! from other implementations in the last bit.
// Calls into the host libm: the one FFI edge of this crate.
#![allow(unsafe_code)]

unsafe extern "C" {
    fn acos(x: f64) -> f64;
    fn asin(x: f64) -> f64;
    fn atan(x: f64) -> f64;
    fn cos(x: f64) -> f64;
    fn cosh(x: f64) -> f64;
    fn exp(x: f64) -> f64;
    fn log(x: f64) -> f64;
    fn log10(x: f64) -> f64;
    fn log2(x: f64) -> f64;
    fn sin(x: f64) -> f64;
    fn sinh(x: f64) -> f64;
    fn tan(x: f64) -> f64;
    fn tanh(x: f64) -> f64;
    fn acosh(x: f64) -> f64;
    fn asinh(x: f64) -> f64;
    fn atanh(x: f64) -> f64;
    fn cbrt(x: f64) -> f64;
    fn expm1(x: f64) -> f64;
    fn log1p(x: f64) -> f64;
    fn sqrt(x: f64) -> f64;
    fn floor(x: f64) -> f64;
    fn ceil(x: f64) -> f64;
    fn trunc(x: f64) -> f64;
    fn atan2(x: f64, y: f64) -> f64;
    fn hypot(x: f64, y: f64) -> f64;
    fn pow(x: f64, y: f64) -> f64;
    fn fmod(x: f64, y: f64) -> f64;
}

pub fn acos_(x: f64) -> f64 {
    // SAFETY: libm `acos` is a pure function.
    unsafe { acos(x) }
}

pub fn asin_(x: f64) -> f64 {
    // SAFETY: libm `asin` is a pure function.
    unsafe { asin(x) }
}

pub fn atan_(x: f64) -> f64 {
    // SAFETY: libm `atan` is a pure function.
    unsafe { atan(x) }
}

pub fn cos_(x: f64) -> f64 {
    // SAFETY: libm `cos` is a pure function.
    unsafe { cos(x) }
}

pub fn cosh_(x: f64) -> f64 {
    // SAFETY: libm `cosh` is a pure function.
    unsafe { cosh(x) }
}

pub fn exp_(x: f64) -> f64 {
    // SAFETY: libm `exp` is a pure function.
    unsafe { exp(x) }
}

pub fn log_(x: f64) -> f64 {
    // SAFETY: libm `log` is a pure function.
    unsafe { log(x) }
}

pub fn log10_(x: f64) -> f64 {
    // SAFETY: libm `log10` is a pure function.
    unsafe { log10(x) }
}

pub fn log2_(x: f64) -> f64 {
    // SAFETY: libm `log2` is a pure function.
    unsafe { log2(x) }
}

pub fn sin_(x: f64) -> f64 {
    // SAFETY: libm `sin` is a pure function.
    unsafe { sin(x) }
}

pub fn sinh_(x: f64) -> f64 {
    // SAFETY: libm `sinh` is a pure function.
    unsafe { sinh(x) }
}

pub fn tan_(x: f64) -> f64 {
    // SAFETY: libm `tan` is a pure function.
    unsafe { tan(x) }
}

pub fn tanh_(x: f64) -> f64 {
    // SAFETY: libm `tanh` is a pure function.
    unsafe { tanh(x) }
}

pub fn acosh_(x: f64) -> f64 {
    // SAFETY: libm `acosh` is a pure function.
    unsafe { acosh(x) }
}

pub fn asinh_(x: f64) -> f64 {
    // SAFETY: libm `asinh` is a pure function.
    unsafe { asinh(x) }
}

pub fn atanh_(x: f64) -> f64 {
    // SAFETY: libm `atanh` is a pure function.
    unsafe { atanh(x) }
}

pub fn cbrt_(x: f64) -> f64 {
    // SAFETY: libm `cbrt` is a pure function.
    unsafe { cbrt(x) }
}

pub fn expm1_(x: f64) -> f64 {
    // SAFETY: libm `expm1` is a pure function.
    unsafe { expm1(x) }
}

pub fn log1p_(x: f64) -> f64 {
    // SAFETY: libm `log1p` is a pure function.
    unsafe { log1p(x) }
}

pub fn sqrt_(x: f64) -> f64 {
    // SAFETY: libm `sqrt` is a pure function.
    unsafe { sqrt(x) }
}

pub fn floor_(x: f64) -> f64 {
    // SAFETY: libm `floor` is a pure function.
    unsafe { floor(x) }
}

pub fn ceil_(x: f64) -> f64 {
    // SAFETY: libm `ceil` is a pure function.
    unsafe { ceil(x) }
}

pub fn trunc_(x: f64) -> f64 {
    // SAFETY: libm `trunc` is a pure function.
    unsafe { trunc(x) }
}

pub fn atan2_(x: f64, y: f64) -> f64 {
    // SAFETY: libm `atan2` is a pure function.
    unsafe { atan2(x, y) }
}

pub fn hypot_(x: f64, y: f64) -> f64 {
    // SAFETY: libm `hypot` is a pure function.
    unsafe { hypot(x, y) }
}

pub fn pow_(x: f64, y: f64) -> f64 {
    // SAFETY: libm `pow` is a pure function.
    unsafe { pow(x, y) }
}

pub fn fmod_(x: f64, y: f64) -> f64 {
    // SAFETY: libm `fmod` is a pure function.
    unsafe { fmod(x, y) }
}

/// `Math.round`: ties toward positive infinity, signed zero preserved.
pub fn round(value: f64) -> f64 {
    if value.is_nan() || value.is_infinite() || value == 0.0 {
        return value;
    }
    let mut lower = floor_(value);
    if value - lower >= 0.5 {
        lower += 1.0;
    }
    if lower == 0.0 {
        return 0.0f64.copysign(value);
    }
    lower
}

/// `Math.sign`: -1, 0 or 1, keeping signed zero and NaN.
pub fn sign(v: f64) -> f64 {
    if v.is_nan() || v == 0.0 {
        v
    } else if v < 0.0 {
        -1.0
    } else {
        1.0
    }
}

pub fn is_integer(v: f64) -> bool {
    v.is_finite() && v == trunc_(v)
}
