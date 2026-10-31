use ms_std_decimal::Dec;
use std::{hint::black_box, time::Instant};

fn reference(value: &Dec, other: &Dec) -> i64 {
    let a = (i128::from(value.hi) << 64) | i128::from(value.lo);
    let b = (i128::from(other.hi) << 64) | i128::from(other.lo);
    if value.exp == other.exp || a.signum() != b.signum() || a == 0 {
        return a.cmp(&b) as i64;
    }
    let negative = a < 0;
    let (a, b) = (a.unsigned_abs(), b.unsigned_abs());
    let (a_digits, b_digits) = (a.ilog10(), b.ilog10());
    let a_exponent = i128::from(value.exp) + i128::from(a_digits);
    let b_exponent = i128::from(other.exp) + i128::from(b_digits);
    let magnitude = if a_exponent != b_exponent {
        a_exponent.cmp(&b_exponent)
    } else if a_digits < b_digits {
        // Equal leading exponents need at most 33 places of alignment for Decimal.
        // Checked multiplication also handles arbitrary public i128 coefficient bits.
        a.checked_mul(10_u128.pow(b_digits - a_digits))
            .map_or(core::cmp::Ordering::Greater, |scaled| scaled.cmp(&b))
    } else {
        b.checked_mul(10_u128.pow(a_digits - b_digits))
            .map_or(core::cmp::Ordering::Less, |scaled| a.cmp(&scaled))
    };
    (if negative {
        magnitude.reverse()
    } else {
        magnitude
    }) as i64
}

fn main() {
    let args: Vec<_> = std::env::args().collect();
    let name = &args[1];
    let count: usize = args[2].parse().unwrap();
    let spellings: &[(&str, &str)] = match name.as_str() {
        "common" => &[
            ("0", "1"),
            ("1", "0"),
            ("-1", "1"),
            ("123456789", "123456788"),
            ("-123456789", "-123456788"),
            ("9223372036854775807", "9223372036854775806"),
            ("-9223372036854775808", "-9223372036854775807"),
            ("1", "1"),
        ],
        "signs" => &[
            ("1e-6176", "-1e6144"),
            ("-1e-6176", "1e6144"),
            ("0", "1e-6176"),
            ("-1e-6176", "0"),
            ("1e6144", "0"),
            ("0", "-1e6144"),
            ("0", "0"),
            ("-1", "1"),
        ],
        "gaps" => &[
            ("1e6144", "1e-6176"),
            ("-1e6144", "-1e-6176"),
            ("1e-6176", "1e6144"),
            ("-1e-6176", "-1e6144"),
            ("1e34", "9999999999999999999999999999999999"),
            ("-1e34", "-9999999999999999999999999999999999"),
            ("1e-33", "9999999999999999999999999999999999"),
            ("-1e-33", "-9999999999999999999999999999999999"),
        ],
        "align" => &[
            ("1.1", "1"),
            ("9.99", "10"),
            ("9999999999999999999999999999999999", "1e33"),
            ("9999999999999999999999999999999999", "9e33"),
            ("-1.1", "-1"),
            ("-9.99", "-10"),
            ("-9999999999999999999999999999999999", "-1e33"),
            ("-9999999999999999999999999999999999", "-9e33"),
        ],
        "large" => &[
            (
                "9999999999999999999999999999999999",
                "9999999999999999999999999999999998",
            ),
            (
                "-9999999999999999999999999999999999",
                "-9999999999999999999999999999999998",
            ),
            (
                "9.999999999999999999999999999999999e6144",
                "9.999999999999999999999999999999998e6144",
            ),
            (
                "-9.999999999999999999999999999999999e6144",
                "-9.999999999999999999999999999999998e6144",
            ),
            ("1e-6176", "2e-6176"),
            ("-1e-6176", "-2e-6176"),
            (
                "1234567890123456789012345678901234e-30",
                "123456789012345678901234567890123e-29",
            ),
            (
                "-1234567890123456789012345678901234e-30",
                "-123456789012345678901234567890123e-29",
            ),
        ],
        _ => panic!("unknown case"),
    };
    let values: Vec<_> = spellings
        .iter()
        .map(|(a, b)| (Dec::parse(a).unwrap(), Dec::parse(b).unwrap()))
        .collect();
    let expected: &[i64] = match name.as_str() {
        "common" => &[-1, 1, -1, 1, -1, 1, -1, 0],
        "signs" => &[1, -1, -1, -1, 1, 1, 0, -1],
        "gaps" => &[1, -1, -1, 1, 1, -1, -1, 1],
        "align" => &[1, -1, 1, 1, -1, 1, -1, -1],
        "large" => &[1, -1, 1, -1, -1, 1, 1, -1],
        _ => unreachable!(),
    };
    for ((a, b), expected) in values.iter().zip(expected) {
        assert_eq!(reference(a, b), *expected);
        assert_eq!(a.compare(b), *expected);
    }
    let start = Instant::now();
    let mut checksum = 0_i64;
    for i in 0..count {
        let (a, b) = black_box(&values[i % values.len()]);
        checksum += reference(a, b) * (i % 7 + 1) as i64;
    }
    let ns = start.elapsed().as_nanos();
    println!("case={name} count={count} ns={ns} checksum={checksum}");
}
