//! Ports of the Go `math` package routines the Go runtime calls for `@std/math`.
//!
//! The algorithms are transcribed from Go 1.25 (`$GOROOT/src/math`, BSD-style license,
//! Copyright 2009 The Go Authors) with the same operation order, so results are bit-identical
//! to the oracle. `floor`, `ceil`, `trunc` and `sqrt` are exact operations and come from libm.

// The constants and expressions below are transcribed from Go so every rounding step stays identical.
#![allow(
    clippy::excessive_precision,
    clippy::manual_range_contains,
    clippy::approx_constant
)]

use core::f64::consts::{FRAC_PI_2, FRAC_PI_4, PI};

unsafe extern "C" {
    fn sqrt(x: f64) -> f64;
    fn floor(x: f64) -> f64;
    fn ceil(x: f64) -> f64;
    fn trunc(x: f64) -> f64;
}

pub const LN2: f64 = core::f64::consts::LN_2;
pub const LN10: f64 = core::f64::consts::LN_10;
/// `4 / Pi` rounded once, as Go's exact constant arithmetic does.
const FOUR_OVER_PI: f64 = 1.273_239_544_735_162_686_151_070_106_980_114_9;
/// `1 / Ln10` and `1 / Ln2`.
pub const LOG10E: f64 = 0.434_294_481_903_251_827_651_128_918_916_605_08;
pub const LOG2E: f64 = 1.442_695_040_888_963_407_359_924_681_001_892_1;
const THREE_PI_4: f64 = 2.356_194_490_192_344_928_846_982_537_459_627_2;

const UVNAN: u64 = 0x7FF8_0000_0000_0001;
const MASK: u64 = 0x7FF;
const SHIFT: u32 = 64 - 11 - 1;
const BIAS: i64 = 1023;

pub fn nan() -> f64 {
    f64::from_bits(UVNAN)
}

pub fn inf(sign: i32) -> f64 {
    if sign >= 0 {
        f64::INFINITY
    } else {
        f64::NEG_INFINITY
    }
}

pub fn is_inf(f: f64, sign: i32) -> bool {
    (sign >= 0 && f > f64::MAX) || (sign <= 0 && f < -f64::MAX)
}

pub fn abs(x: f64) -> f64 {
    f64::from_bits(x.to_bits() & !(1 << 63))
}

pub fn copysign(f: f64, sign: f64) -> f64 {
    f64::from_bits((f.to_bits() & !(1 << 63)) | (sign.to_bits() & (1 << 63)))
}

pub fn signbit(x: f64) -> bool {
    x.to_bits() & (1 << 63) != 0
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

fn normalize(x: f64) -> (f64, i64) {
    const SMALLEST_NORMAL: f64 = 2.225_073_858_507_201_4e-308;
    if abs(x) < SMALLEST_NORMAL {
        return (x * (1u64 << 52) as f64, -52);
    }
    (x, 0)
}

pub fn frexp(f: f64) -> (f64, i64) {
    if f == 0.0 || is_inf(f, 0) || f.is_nan() {
        return (f, 0);
    }
    let (f, mut exp) = normalize(f);
    let mut x = f.to_bits();
    exp += ((x >> SHIFT) & MASK) as i64 - BIAS + 1;
    x &= !(MASK << SHIFT);
    x |= ((-1 + BIAS) as u64) << SHIFT;
    (f64::from_bits(x), exp)
}

pub fn ldexp(frac: f64, exp: i64) -> f64 {
    if frac == 0.0 || is_inf(frac, 0) || frac.is_nan() {
        return frac;
    }
    let (frac, e) = normalize(frac);
    let mut exp = exp.saturating_add(e);
    let mut x = frac.to_bits();
    exp = exp.saturating_add(((x >> SHIFT) & MASK) as i64 - BIAS);
    if exp < -1075 {
        return copysign(0.0, frac);
    }
    if exp > 1023 {
        return if frac < 0.0 { inf(-1) } else { inf(1) };
    }
    let mut m = 1.0;
    if exp < -1022 {
        exp += 53;
        m = 1.0 / (1u64 << 53) as f64;
    }
    x &= !(MASK << SHIFT);
    x |= ((exp + BIAS) as u64) << SHIFT;
    m * f64::from_bits(x)
}

pub fn modf(f: f64) -> (f64, f64) {
    if f < 1.0 {
        if f < 0.0 {
            let (i, fr) = modf(-f);
            return (-i, -fr);
        }
        if f == 0.0 {
            return (f, f);
        }
        return (0.0, f);
    }
    let mut x = f.to_bits();
    let e = ((x >> SHIFT) & MASK).wrapping_sub(BIAS as u64);
    if e < 64 - 12 {
        x &= !((1u64 << (64 - 12 - e as u32)) - 1);
    }
    let i = f64::from_bits(x);
    (i, f - i)
}

/// Go's `math.Mod`; `Math.remainder` calls it.
pub fn fmod(x: f64, y: f64) -> f64 {
    if y == 0.0 || is_inf(x, 0) || x.is_nan() || y.is_nan() {
        return nan();
    }
    let y = abs(y);
    let (yfr, yexp) = frexp(y);
    let mut r = if x < 0.0 { -x } else { x };
    while r >= y {
        let (rfr, mut rexp) = frexp(r);
        if rfr < yfr {
            rexp -= 1;
        }
        r -= ldexp(y, rexp - yexp);
    }
    if x < 0.0 { -r } else { r }
}

const MP4: [u64; 20] = [
    0x0000000000000001,
    0x45f306dc9c882a53,
    0xf84eafa3ea69bb81,
    0xb6c52b3278872083,
    0xfca2c757bd778ac3,
    0x6e48dc74849ba5c0,
    0x0c925dd413a32439,
    0xfc3bd63962534e7d,
    0xd1046bea5d768909,
    0xd338e04d68befc82,
    0x7323ac7306a673e9,
    0x3908bf177bf25076,
    0x3ff12fffbc0b301f,
    0xde5e2316b414da3e,
    0xda6cfd9e4f96136e,
    0x9e8c7ecd3cbfd45a,
    0xea4f758fd7cbe2f6,
    0x7a0e73ef14a525d4,
    0xd7f6bf623f1aba10,
    0xac06608df8f6d757,
];

const REDUCE_THRESHOLD: f64 = (1u64 << 29) as f64;

fn mul64(x: u64, y: u64) -> (u64, u64) {
    let p = x as u128 * y as u128;
    ((p >> 64) as u64, p as u64)
}

fn trig_reduce(x: f64) -> (u64, f64) {
    if x < FRAC_PI_4 {
        return (0, x);
    }
    let mut ix = x.to_bits();
    let exp = ((ix >> SHIFT) & MASK) as i64 - BIAS - SHIFT as i64;
    ix &= !(MASK << SHIFT);
    ix |= 1 << SHIFT;
    let digit = ((exp + 61) as u64 / 64) as usize;
    let bitshift = ((exp + 61) as u64 % 64) as u32;
    // Go shifts by 64 yield zero; Rust panics, so spell that case out.
    let shl = |a: u64, s: u32| if s >= 64 { 0 } else { a << s };
    let shr = |a: u64, s: u32| if s >= 64 { 0 } else { a >> s };
    let z0 = shl(MP4[digit], bitshift) | shr(MP4[digit + 1], 64 - bitshift);
    let z1 = shl(MP4[digit + 1], bitshift) | shr(MP4[digit + 2], 64 - bitshift);
    let z2 = shl(MP4[digit + 2], bitshift) | shr(MP4[digit + 3], 64 - bitshift);
    let (z2hi, _) = mul64(z2, ix);
    let (z1hi, z1lo) = mul64(z1, ix);
    let z0lo = z0.wrapping_mul(ix);
    let (lo, c) = z1lo.overflowing_add(z2hi);
    let hi = z0lo.wrapping_add(z1hi).wrapping_add(c as u64);
    let mut j = hi >> 61;
    let mut hi = hi << 3 | lo >> 61;
    let lz = hi.leading_zeros();
    let e = (BIAS as u64).wrapping_sub(lz as u64 + 1);
    hi = shl(hi, lz + 1) | shr(lo, 64 - (lz + 1));
    hi >>= 64 - SHIFT;
    hi |= e << SHIFT;
    let mut z = f64::from_bits(hi);
    if j & 1 == 1 {
        j += 1;
        j &= 7;
        z -= 1.0;
    }
    (j, z * FRAC_PI_4)
}

const SIN: [f64; 6] = [
    1.58962301576546568060e-10,
    -2.50507477628578072866e-8,
    2.75573136213857245213e-6,
    -1.98412698295895385996e-4,
    8.33333333332211858878e-3,
    -1.66666666666666307295e-1,
];
const COS: [f64; 6] = [
    -1.13585365213876817300e-11,
    2.08757008419747316778e-9,
    -2.75573141792967388112e-7,
    2.48015872888517045348e-5,
    -1.38888888888730564116e-3,
    4.16666666666665929218e-2,
];
const PI4A: f64 = 7.85398125648498535156e-1;
const PI4B: f64 = 3.77489470793079817668e-8;
const PI4C: f64 = 2.69515142907905952645e-15;

/// Octant and reduced argument shared by `sin`, `cos` and `tan`; `x` is non-negative.
fn reduce(x: f64, fix_odd_octant_mod8: bool) -> (u64, f64) {
    if x >= REDUCE_THRESHOLD {
        return trig_reduce(x);
    }
    let mut j = (x * FOUR_OVER_PI) as u64;
    let mut y = j as f64;
    if j & 1 == 1 {
        j += 1;
        y += 1.0;
    }
    if fix_odd_octant_mod8 {
        j &= 7;
    }
    (j, ((x - y * PI4A) - y * PI4B) - y * PI4C)
}

fn sin_poly(z: f64, zz: f64) -> f64 {
    z + z
        * zz
        * ((((((SIN[0] * zz) + SIN[1]) * zz + SIN[2]) * zz + SIN[3]) * zz + SIN[4]) * zz + SIN[5])
}

fn cos_poly(zz: f64) -> f64 {
    1.0 - 0.5 * zz
        + zz * zz
            * ((((((COS[0] * zz) + COS[1]) * zz + COS[2]) * zz + COS[3]) * zz + COS[4]) * zz
                + COS[5])
}

pub fn cos(x: f64) -> f64 {
    if x.is_nan() || is_inf(x, 0) {
        return nan();
    }
    let mut sign = false;
    let (mut j, z) = reduce(abs(x), true);
    if j > 3 {
        j -= 4;
        sign = !sign;
    }
    if j > 1 {
        sign = !sign;
    }
    let zz = z * z;
    let y = if j == 1 || j == 2 {
        sin_poly(z, zz)
    } else {
        cos_poly(zz)
    };
    if sign { -y } else { y }
}

pub fn sin(x: f64) -> f64 {
    if x == 0.0 || x.is_nan() {
        return x;
    }
    if is_inf(x, 0) {
        return nan();
    }
    let mut sign = false;
    let mut x = x;
    if x < 0.0 {
        x = -x;
        sign = true;
    }
    let (mut j, z) = reduce(x, true);
    if j > 3 {
        sign = !sign;
        j -= 4;
    }
    let zz = z * z;
    let y = if j == 1 || j == 2 {
        cos_poly(zz)
    } else {
        sin_poly(z, zz)
    };
    if sign { -y } else { y }
}

const TAN_P: [f64; 3] = [
    -1.30936939181383777646e4,
    1.15351664838587416140e6,
    -1.79565251976484877988e7,
];
const TAN_Q: [f64; 5] = [
    1.0,
    1.36812963470692954678e4,
    -1.32089234440210967447e6,
    2.50083801823357915839e7,
    -5.38695755929454629881e7,
];

pub fn tan(x: f64) -> f64 {
    if x == 0.0 || x.is_nan() {
        return x;
    }
    if is_inf(x, 0) {
        return nan();
    }
    let mut sign = false;
    let mut x = x;
    if x < 0.0 {
        x = -x;
        sign = true;
    }
    let (j, z) = reduce(x, false);
    let zz = z * z;
    let mut y = if zz > 1e-14 {
        z + z
            * (zz * (((TAN_P[0] * zz) + TAN_P[1]) * zz + TAN_P[2])
                / ((((zz + TAN_Q[1]) * zz + TAN_Q[2]) * zz + TAN_Q[3]) * zz + TAN_Q[4]))
    } else {
        z
    };
    if j & 2 == 2 {
        y = -1.0 / y;
    }
    if sign { -y } else { y }
}

fn xatan(x: f64) -> f64 {
    const P0: f64 = -8.750608600031904122785e-01;
    const P1: f64 = -1.615753718733365076637e+01;
    const P2: f64 = -7.500855792314704667340e+01;
    const P3: f64 = -1.228866684490136173410e+02;
    const P4: f64 = -6.485021904942025371773e+01;
    const Q0: f64 = 2.485846490142306297962e+01;
    const Q1: f64 = 1.650270098316988542046e+02;
    const Q2: f64 = 4.328810604912902668951e+02;
    const Q3: f64 = 4.853903996359136964868e+02;
    const Q4: f64 = 1.945506571482613964425e+02;
    let mut z = x * x;
    z = z * ((((P0 * z + P1) * z + P2) * z + P3) * z + P4)
        / (((((z + Q0) * z + Q1) * z + Q2) * z + Q3) * z + Q4);
    x * z + x
}

fn satan(x: f64) -> f64 {
    const MOREBITS: f64 = 6.123233995736765886130e-17;
    const TAN3PIO8: f64 = 2.41421356237309504880;
    if x <= 0.66 {
        return xatan(x);
    }
    if x > TAN3PIO8 {
        return FRAC_PI_2 - xatan(1.0 / x) + MOREBITS;
    }
    FRAC_PI_4 + xatan((x - 1.0) / (x + 1.0)) + 0.5 * MOREBITS
}

pub fn atan(x: f64) -> f64 {
    if x == 0.0 {
        return x;
    }
    if x > 0.0 { satan(x) } else { -satan(-x) }
}

pub fn atan2(y: f64, x: f64) -> f64 {
    if y.is_nan() || x.is_nan() {
        return nan();
    }
    if y == 0.0 {
        if x >= 0.0 && !signbit(x) {
            return copysign(0.0, y);
        }
        return copysign(PI, y);
    }
    if x == 0.0 {
        return copysign(FRAC_PI_2, y);
    }
    if is_inf(x, 0) {
        if is_inf(x, 1) {
            return if is_inf(y, 0) {
                copysign(FRAC_PI_4, y)
            } else {
                copysign(0.0, y)
            };
        }
        return if is_inf(y, 0) {
            copysign(THREE_PI_4, y)
        } else {
            copysign(PI, y)
        };
    }
    if is_inf(y, 0) {
        return copysign(FRAC_PI_2, y);
    }
    let q = atan(y / x);
    if x < 0.0 {
        return if q <= 0.0 { q + PI } else { q - PI };
    }
    q
}

pub fn asin(x: f64) -> f64 {
    if x == 0.0 {
        return x;
    }
    let mut x = x;
    let mut sign = false;
    if x < 0.0 {
        x = -x;
        sign = true;
    }
    if x > 1.0 {
        return nan();
    }
    let mut temp = sqrt_(1.0 - x * x);
    if x > 0.7 {
        temp = FRAC_PI_2 - satan(temp / x);
    } else {
        temp = satan(x / temp);
    }
    if sign { -temp } else { temp }
}

pub fn acos(x: f64) -> f64 {
    FRAC_PI_2 - asin(x)
}

pub fn exp(x: f64) -> f64 {
    const LN2_HI: f64 = 6.93147180369123816490e-01;
    const LN2_LO: f64 = 1.90821492927058770002e-10;
    const LOG2E_: f64 = 1.44269504088896338700e+00;
    const OVERFLOW: f64 = 7.09782712893383973096e+02;
    const UNDERFLOW: f64 = -7.45133219101941108420e+02;
    const NEAR_ZERO: f64 = 1.0 / (1u64 << 28) as f64;
    if x.is_nan() || is_inf(x, 1) {
        return x;
    }
    if is_inf(x, -1) {
        return 0.0;
    }
    if x > OVERFLOW {
        return inf(1);
    }
    if x < UNDERFLOW {
        return 0.0;
    }
    if -NEAR_ZERO < x && x < NEAR_ZERO {
        return 1.0 + x;
    }
    let k: i64 = if x < 0.0 {
        (LOG2E_ * x - 0.5) as i64
    } else if x > 0.0 {
        (LOG2E_ * x + 0.5) as i64
    } else {
        0
    };
    let hi = x - k as f64 * LN2_HI;
    let lo = k as f64 * LN2_LO;
    expmulti(hi, lo, k)
}

fn expmulti(hi: f64, lo: f64, k: i64) -> f64 {
    const P1: f64 = 1.66666666666666657415e-01;
    const P2: f64 = -2.77777777770155933842e-03;
    const P3: f64 = 6.61375632143793436117e-05;
    const P4: f64 = -1.65339022054652515390e-06;
    const P5: f64 = 4.13813679705723846039e-08;
    let r = hi - lo;
    let t = r * r;
    let c = r - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))));
    let y = 1.0 - ((lo - (r * c) / (2.0 - c)) - hi);
    ldexp(y, k)
}

pub fn log(x: f64) -> f64 {
    const LN2_HI: f64 = 6.93147180369123816490e-01;
    const LN2_LO: f64 = 1.90821492927058770002e-10;
    const L1: f64 = 6.666666666666735130e-01;
    const L2: f64 = 3.999999999940941908e-01;
    const L3: f64 = 2.857142874366239149e-01;
    const L4: f64 = 2.222219843214978396e-01;
    const L5: f64 = 1.818357216161805012e-01;
    const L6: f64 = 1.531383769920937332e-01;
    const L7: f64 = 1.479819860511658591e-01;
    if x.is_nan() || is_inf(x, 1) {
        return x;
    }
    if x < 0.0 {
        return nan();
    }
    if x == 0.0 {
        return inf(-1);
    }
    let (mut f1, mut ki) = frexp(x);
    if f1 < core::f64::consts::SQRT_2 / 2.0 {
        f1 *= 2.0;
        ki -= 1;
    }
    let f = f1 - 1.0;
    let k = ki as f64;
    let s = f / (2.0 + f);
    let s2 = s * s;
    let s4 = s2 * s2;
    let t1 = s2 * (L1 + s4 * (L3 + s4 * (L5 + s4 * L7)));
    let t2 = s4 * (L2 + s4 * (L4 + s4 * L6));
    let r = t1 + t2;
    let hfsq = 0.5 * f * f;
    k * LN2_HI - ((hfsq - (s * (hfsq + r) + k * LN2_LO)) - f)
}

pub fn log10(x: f64) -> f64 {
    log(x) * LOG10E
}

pub fn log2(x: f64) -> f64 {
    let (frac, exp) = frexp(x);
    if frac == 0.5 {
        return (exp - 1) as f64;
    }
    log(frac) * LOG2E + exp as f64
}

fn is_odd_int(x: f64) -> bool {
    if abs(x) >= (1u64 << 53) as f64 {
        return false;
    }
    let (xi, xf) = modf(x);
    xf == 0.0 && (xi as i64) & 1 == 1
}

pub fn pow(x: f64, y: f64) -> f64 {
    if y == 0.0 || x == 1.0 {
        return 1.0;
    }
    if y == 1.0 {
        return x;
    }
    if x.is_nan() || y.is_nan() {
        return nan();
    }
    if x == 0.0 {
        if y < 0.0 {
            return if signbit(x) && is_odd_int(y) {
                inf(-1)
            } else {
                inf(1)
            };
        }
        if y > 0.0 {
            return if signbit(x) && is_odd_int(y) { x } else { 0.0 };
        }
    } else if is_inf(y, 0) {
        if x == -1.0 {
            return 1.0;
        }
        return if (abs(x) < 1.0) == is_inf(y, 1) {
            0.0
        } else {
            inf(1)
        };
    } else if is_inf(x, 0) {
        if is_inf(x, -1) {
            return pow(1.0 / x, -y);
        }
        if y < 0.0 {
            return 0.0;
        }
        if y > 0.0 {
            return inf(1);
        }
    } else if y == 0.5 {
        return sqrt_(x);
    } else if y == -0.5 {
        return 1.0 / sqrt_(x);
    }
    let (mut yi, mut yf) = modf(abs(y));
    if yf != 0.0 && x < 0.0 {
        return nan();
    }
    if yi >= 9.223372036854775808e18 {
        if x == -1.0 {
            return 1.0;
        }
        return if (abs(x) < 1.0) == (y > 0.0) {
            0.0
        } else {
            inf(1)
        };
    }
    let mut a1 = 1.0;
    let mut ae: i64 = 0;
    if yf != 0.0 {
        if yf > 0.5 {
            yf -= 1.0;
            yi += 1.0;
        }
        a1 = exp(yf * log(x));
    }
    let (mut x1, mut xe) = frexp(x);
    let mut i = yi as i64;
    while i != 0 {
        if xe < -(1 << 12) || (1 << 12) < xe {
            ae += xe;
            break;
        }
        if i & 1 == 1 {
            a1 *= x1;
            ae += xe;
        }
        x1 *= x1;
        xe <<= 1;
        if x1 < 0.5 {
            x1 += x1;
            xe -= 1;
        }
        i >>= 1;
    }
    if y < 0.0 {
        a1 = 1.0 / a1;
        ae = -ae;
    }
    ldexp(a1, ae)
}

pub fn hypot(p: f64, q: f64) -> f64 {
    let (mut p, mut q) = (abs(p), abs(q));
    if is_inf(p, 1) || is_inf(q, 1) {
        return inf(1);
    }
    if p.is_nan() || q.is_nan() {
        return nan();
    }
    if p < q {
        core::mem::swap(&mut p, &mut q);
    }
    if p == 0.0 {
        return 0.0;
    }
    q /= p;
    p * sqrt_(1.0 + q * q)
}

pub fn cbrt(x: f64) -> f64 {
    const B1: u64 = 715094163;
    const B2: u64 = 696219795;
    const C: f64 = 5.42857142857142815906e-01;
    const D: f64 = -7.05306122448979611050e-01;
    const E: f64 = 1.41428571428571436819e+00;
    const F: f64 = 1.60714285714285720630e+00;
    const G: f64 = 3.57142857142857150787e-01;
    const SMALLEST_NORMAL: f64 = 2.22507385850720138309e-308;
    if x == 0.0 || x.is_nan() || is_inf(x, 0) {
        return x;
    }
    let mut x = x;
    let mut sign = false;
    if x < 0.0 {
        x = -x;
        sign = true;
    }
    let mut t = f64::from_bits(x.to_bits() / 3 + (B1 << 32));
    if x < SMALLEST_NORMAL {
        t = (1u64 << 54) as f64;
        t *= x;
        t = f64::from_bits(t.to_bits() / 3 + (B2 << 32));
    }
    let mut r = t * t / x;
    let mut s = C + r * t;
    t *= G + F / (s + E + D / s);
    t = f64::from_bits((t.to_bits() & (0xFFFFFFFFC << 28)) + (1 << 30));
    s = t * t;
    r = x / s;
    let w = t + t;
    r = (r - t) / (w + r);
    t += t * r;
    if sign { -t } else { t }
}

pub fn sinh(x: f64) -> f64 {
    const P0: f64 = -0.6307673640497716991184787251e+6;
    const P1: f64 = -0.8991272022039509355398013511e+5;
    const P2: f64 = -0.2894211355989563807284660366e+4;
    const P3: f64 = -0.2630563213397497062819489e+2;
    const Q0: f64 = -0.6307673640497716991212077277e+6;
    const Q1: f64 = 0.1521517378790019070696485176e+5;
    const Q2: f64 = -0.173678953558233699533450911e+3;
    let mut x = x;
    let mut sign = false;
    if x < 0.0 {
        x = -x;
        sign = true;
    }
    let temp = if x > 21.0 {
        exp(x) * 0.5
    } else if x > 0.5 {
        let ex = exp(x);
        (ex - 1.0 / ex) * 0.5
    } else {
        let sq = x * x;
        let t = (((P3 * sq + P2) * sq + P1) * sq + P0) * x;
        t / (((sq + Q2) * sq + Q1) * sq + Q0)
    };
    if sign { -temp } else { temp }
}

pub fn cosh(x: f64) -> f64 {
    let x = abs(x);
    if x > 21.0 {
        return exp(x) * 0.5;
    }
    let ex = exp(x);
    (ex + 1.0 / ex) * 0.5
}

pub fn tanh(x: f64) -> f64 {
    const TANH_P: [f64; 3] = [
        -9.64399179425052238628e-1,
        -9.92877231001918586564e1,
        -1.61468768441708447952e3,
    ];
    const TANH_Q: [f64; 3] = [
        1.12811678491632931402e2,
        2.23548839060100448583e3,
        4.84406305325125486048e3,
    ];
    const MAXLOG: f64 = 8.8029691931113054295988e+01;
    let mut z = abs(x);
    if z > 0.5 * MAXLOG {
        return if x < 0.0 { -1.0 } else { 1.0 };
    }
    if z >= 0.625 {
        let s = exp(2.0 * z);
        z = 1.0 - 2.0 / (s + 1.0);
        if x < 0.0 {
            z = -z;
        }
    } else {
        if x == 0.0 {
            return x;
        }
        let s = x * x;
        z = x + x * s * ((TANH_P[0] * s + TANH_P[1]) * s + TANH_P[2])
            / (((s + TANH_Q[0]) * s + TANH_Q[1]) * s + TANH_Q[2]);
    }
    z
}

pub fn expm1(x: f64) -> f64 {
    const OTHRESHOLD: f64 = 7.09782712893383973096e+02;
    const LN2X56: f64 = 3.88162421113569373274e+01;
    const LN2HALFX3: f64 = 1.03972077083991796413e+00;
    const LN2HALF: f64 = 3.46573590279972654709e-01;
    const LN2HI: f64 = 6.93147180369123816490e-01;
    const LN2LO: f64 = 1.90821492927058770002e-10;
    const INVLN2: f64 = 1.44269504088896338700e+00;
    const TINY: f64 = 1.0 / (1u64 << 54) as f64;
    const Q1: f64 = -3.33333333333331316428e-02;
    const Q2: f64 = 1.58730158725481460165e-03;
    const Q3: f64 = -7.93650757867487942473e-05;
    const Q4: f64 = 4.00821782732936239552e-06;
    const Q5: f64 = -2.01099218183624371326e-07;
    if is_inf(x, 1) || x.is_nan() {
        return x;
    }
    if is_inf(x, -1) {
        return -1.0;
    }
    let mut x = x;
    let mut absx = x;
    let mut sign = false;
    if x < 0.0 {
        absx = -absx;
        sign = true;
    }
    if absx >= LN2X56 {
        if sign {
            return -1.0;
        }
        if absx >= OTHRESHOLD {
            return inf(1);
        }
    }
    let mut c = 0.0;
    let k: i64;
    if absx > LN2HALF {
        let (hi, lo);
        if absx < LN2HALFX3 {
            if !sign {
                hi = x - LN2HI;
                lo = LN2LO;
                k = 1;
            } else {
                hi = x + LN2HI;
                lo = -LN2LO;
                k = -1;
            }
        } else {
            k = if !sign {
                (INVLN2 * x + 0.5) as i64
            } else {
                (INVLN2 * x - 0.5) as i64
            };
            let t = k as f64;
            hi = x - t * LN2HI;
            lo = t * LN2LO;
        }
        x = hi - lo;
        c = (hi - x) - lo;
    } else if absx < TINY {
        return x;
    } else {
        k = 0;
    }
    let hfx = 0.5 * x;
    let hxs = x * hfx;
    let r1 = 1.0 + hxs * (Q1 + hxs * (Q2 + hxs * (Q3 + hxs * (Q4 + hxs * Q5))));
    let mut t = 3.0 - r1 * hfx;
    let mut e = hxs * ((r1 - t) / (6.0 - x * t));
    if k == 0 {
        return x - (x * e - hxs);
    }
    e = x * (e - c) - c;
    e -= hxs;
    if k == -1 {
        return 0.5 * (x - e) - 0.5;
    }
    if k == 1 {
        if x < -0.25 {
            return -2.0 * (e - (x + 0.5));
        }
        return 1.0 + 2.0 * (x - e);
    }
    if k <= -2 || k > 56 {
        let mut y = 1.0 - (e - x);
        y = f64::from_bits(y.to_bits().wrapping_add((k as u64) << 52));
        return y - 1.0;
    }
    if k < 20 {
        let t = f64::from_bits(0x3ff0000000000000 - (0x20000000000000u64 >> k as u32));
        let mut y = t - (e - x);
        y = f64::from_bits(y.to_bits().wrapping_add((k as u64) << 52));
        return y;
    }
    t = f64::from_bits(((0x3ff - k) as u64) << 52);
    let mut y = x - (e + t);
    y += 1.0;
    f64::from_bits(y.to_bits().wrapping_add((k as u64) << 52))
}

pub fn log1p(x: f64) -> f64 {
    const SQRT2M1: f64 = 4.142135623730950488017e-01;
    const SQRT2HALFM1: f64 = -2.928932188134524755992e-01;
    const SMALL: f64 = 1.0 / (1u64 << 29) as f64;
    const TINY: f64 = 1.0 / (1u64 << 54) as f64;
    const TWO53: f64 = (1u64 << 53) as f64;
    const LN2HI: f64 = 6.93147180369123816490e-01;
    const LN2LO: f64 = 1.90821492927058770002e-10;
    const LP1: f64 = 6.666666666666735130e-01;
    const LP2: f64 = 3.999999999940941908e-01;
    const LP3: f64 = 2.857142874366239149e-01;
    const LP4: f64 = 2.222219843214978396e-01;
    const LP5: f64 = 1.818357216161805012e-01;
    const LP6: f64 = 1.531383769920937332e-01;
    const LP7: f64 = 1.479819860511658591e-01;
    if x < -1.0 || x.is_nan() {
        return nan();
    }
    if x == -1.0 {
        return inf(-1);
    }
    if is_inf(x, 1) {
        return inf(1);
    }
    let absx = abs(x);
    let mut f = 0.0;
    let mut iu: u64 = 0;
    let mut k: i64 = 1;
    if absx < SQRT2M1 {
        if absx < SMALL {
            if absx < TINY {
                return x;
            }
            return x - x * x * 0.5;
        }
        if x > SQRT2HALFM1 {
            k = 0;
            f = x;
            iu = 1;
        }
    }
    let mut c = 0.0;
    if k != 0 {
        let mut u;
        if absx < TWO53 {
            u = 1.0 + x;
            iu = u.to_bits();
            k = (iu >> 52) as i64 - 1023;
            if k > 0 {
                c = 1.0 - (u - x);
            } else {
                c = x - (u - 1.0);
            }
            c /= u;
        } else {
            u = x;
            iu = u.to_bits();
            k = (iu >> 52) as i64 - 1023;
            c = 0.0;
        }
        iu &= 0x000fffffffffffff;
        if iu < 0x0006a09e667f3bcd {
            u = f64::from_bits(iu | 0x3ff0000000000000);
        } else {
            k += 1;
            u = f64::from_bits(iu | 0x3fe0000000000000);
            iu = (0x0010000000000000 - iu) >> 2;
        }
        f = u - 1.0;
    }
    let hfsq = 0.5 * f * f;
    let kf = k as f64;
    if iu == 0 {
        if f == 0.0 {
            if k == 0 {
                return 0.0;
            }
            c += kf * LN2LO;
            return kf * LN2HI + c;
        }
        let r = hfsq * (1.0 - 0.66666666666666666 * f);
        if k == 0 {
            return f - r;
        }
        return kf * LN2HI - ((r - (kf * LN2LO + c)) - f);
    }
    let s = f / (2.0 + f);
    let z = s * s;
    let r = z * (LP1 + z * (LP2 + z * (LP3 + z * (LP4 + z * (LP5 + z * (LP6 + z * LP7))))));
    if k == 0 {
        return f - (hfsq - s * (hfsq + r));
    }
    kf * LN2HI - ((hfsq - (s * (hfsq + r) + (kf * LN2LO + c))) - f)
}

pub fn acosh(x: f64) -> f64 {
    const LARGE: f64 = (1u64 << 28) as f64;
    if x < 1.0 || x.is_nan() {
        return nan();
    }
    if x == 1.0 {
        return 0.0;
    }
    if x >= LARGE {
        return log(x) + LN2;
    }
    if x > 2.0 {
        return log(2.0 * x - 1.0 / (x + sqrt_(x * x - 1.0)));
    }
    let t = x - 1.0;
    log1p(t + sqrt_(2.0 * t + t * t))
}

pub fn asinh(x: f64) -> f64 {
    const NEAR_ZERO: f64 = 1.0 / (1u64 << 28) as f64;
    const LARGE: f64 = (1u64 << 28) as f64;
    if x.is_nan() || is_inf(x, 0) {
        return x;
    }
    let mut x = x;
    let mut sign = false;
    if x < 0.0 {
        x = -x;
        sign = true;
    }
    let temp = if x > LARGE {
        log(x) + LN2
    } else if x > 2.0 {
        log(2.0 * x + 1.0 / (sqrt_(x * x + 1.0) + x))
    } else if x < NEAR_ZERO {
        x
    } else {
        log1p(x + x * x / (1.0 + sqrt_(1.0 + x * x)))
    };
    if sign { -temp } else { temp }
}

pub fn atanh(x: f64) -> f64 {
    const NEAR_ZERO: f64 = 1.0 / (1u64 << 28) as f64;
    if x < -1.0 || x > 1.0 || x.is_nan() {
        return nan();
    }
    if x == 1.0 {
        return inf(1);
    }
    if x == -1.0 {
        return inf(-1);
    }
    let mut x = x;
    let mut sign = false;
    if x < 0.0 {
        x = -x;
        sign = true;
    }
    let temp = if x < NEAR_ZERO {
        x
    } else if x < 0.5 {
        let t = x + x;
        0.5 * log1p(t + t * x / (1.0 - x))
    } else {
        0.5 * log1p((x + x) / (1.0 - x))
    };
    if sign { -temp } else { temp }
}

/// `Math.round`: ties toward positive infinity, signed zero preserved.
pub fn round(value: f64) -> f64 {
    if value.is_nan() || is_inf(value, 0) || value == 0.0 {
        return value;
    }
    let mut lower = floor_(value);
    if value - lower >= 0.5 {
        lower += 1.0;
    }
    if lower == 0.0 {
        return copysign(0.0, value);
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
    !is_inf(v, 0) && !v.is_nan() && v == trunc_(v)
}
