//! The shortest decimal digits that read back as a given binary64: Schubfach (Giulietti, "The
//! Schubfach way to render doubles", 2020), the algorithm of Java's `Double.toString`.
//!
//! Of the decimals inside a value's rounding interval it picks the fewest digits and, among
//! those, the one nearest the value (an exact tie takes the even digit). Two multiplications by
//! a 126-bit power of ten from `float_table.rs` find the interval's ends and the value in units
//! of the final digit, so the work is a fixed handful of integer operations with no table
//! search, no big numbers and no fallback.

use crate::float_table::{G, K_MIN};

const Q_MIN: i32 = -1074;
const C_MIN: u64 = 1 << 52;
const MASK63: u64 = (1 << 63) - 1;

/// `floor(log10(2^e))` for `e` in `-1074..=971`.
fn flog10_pow2(e: i32) -> i32 {
    ((i64::from(e) * 677_859_288_149_821) >> 51) as i32
}

/// `floor(log10(3/4 * 2^e))` for `e` in `-1074..=971`.
fn flog10_three_quarters_pow2(e: i32) -> i32 {
    ((i64::from(e) * 677_859_288_149_821 - 281_337_023_816_645) >> 51) as i32
}

/// `floor(log2(10^e))` for `e` in `-292..=324`.
fn flog2_pow10(e: i32) -> i32 {
    ((i64::from(e) * 935_039_633_142_891) >> 48) as i32
}

/// `g * cp / 2^127` rounded to odd (the low bit is set when anything was dropped), where `g` is
/// `g1 * 2^63 + g0`.
fn round_to_odd(g1: u64, g0: u64, cp: u64) -> u64 {
    let x1 = ((u128::from(g0) * u128::from(cp)) >> 64) as u64;
    let y = u128::from(g1) * u128::from(cp);
    let (y1, y0) = ((y >> 64) as u64, y as u64);
    let z = (y0 >> 1) + x1;
    let high = y1 + (z >> 63);
    high | (((z & MASK63) + MASK63) >> 63)
}

/// The digits `d` and exponent `e` of the shortest decimal `d * 10^e` that rounds to the finite
/// positive `v`, with no trailing zero in `d`.
pub fn shortest(v: f64) -> (u64, i32) {
    let bits = v.to_bits();
    let biased = (bits >> 52) as i32 & 0x7ff;
    let fraction = bits & (C_MIN - 1);
    let (q, c) = if biased != 0 {
        (biased - 1075, fraction | C_MIN)
    } else {
        (Q_MIN, fraction)
    };
    let (d, e) = to_decimal(q, c);
    strip_zeros(d, e)
}

fn strip_zeros(mut d: u64, mut e: i32) -> (u64, i32) {
    while d.is_multiple_of(10) {
        d /= 10;
        e += 1;
    }
    (d, e)
}

pub fn to_decimal(q: i32, c: u64) -> (u64, i32) {
    let out = c & 1;
    let cb = c << 2;
    let cbr = cb + 2;
    let (cbl, k) = if c != C_MIN || q == Q_MIN {
        // The gap below the value is the gap above it.
        (cb - 2, flog10_pow2(q))
    } else {
        // A power of two: the gap below is half the gap above.
        (cb - 1, flog10_three_quarters_pow2(q))
    };
    let h = (q + flog2_pow10(-k) + 2) as u32;
    let (g1, g0) = G[(k - K_MIN) as usize];
    let vb = round_to_odd(g1, g0, cb << h);
    let vbl = round_to_odd(g1, g0, cbl << h);
    let vbr = round_to_odd(g1, g0, cbr << h);

    let s = vb >> 2;
    #[cfg(test)]
    eprintln!("DBG q={q} c={c} k={k} h={h} g={:#x},{:#x} vb={vb} vbl={vbl} vbr={vbr} s={s} out={out}", g1, g0);
    if s >= 10 {
        // A multiple of ten inside the interval gives one digit fewer than `s` does. (Java's
        // `Double.toString` starts at 100 because it always prints two digits; the shortest
        // form of a small subnormal such as 5e-323 has one.)
        let sp10 = 10 * (s / 10);
        let tp10 = sp10 + 10;
        let up_in = vbl + out <= sp10 << 2;
        let wp_in = (tp10 << 2) + out <= vbr;
        if up_in != wp_in {
            return (if up_in { sp10 } else { tp10 }, k);
        }
    }
    let t = s + 1;
    let u_in = vbl + out <= s << 2;
    let w_in = (t << 2) + out <= vbr;
    if u_in != w_in {
        return (if u_in { s } else { t }, k);
    }
    // Both or neither of `s` and `t` is inside: take the nearer to the value, an exact tie going
    // to the even one.
    let cmp = vb as i64 - ((s + t) << 1) as i64;
    let pick_s = cmp < 0 || (cmp == 0 && s & 1 == 0);
    (if pick_s { s } else { t }, k)
}

#[cfg(test)]
mod dbg {
    #[test]
    fn dbg_five_e_minus_323() {
        for c in [10u64, 11, 20, 49] {
            let r = super::to_decimal(super::Q_MIN, c);
            eprintln!("DBG result c={c} {r:?} flog10={} flog2={}", super::flog10_pow2(-1074), super::flog2_pow10(324));
        }
    }
}
