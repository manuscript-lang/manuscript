use ms_std_decimal::Dec;
use std::{hint::black_box, time::Instant};

fn reference(value: &Dec) -> Option<i64> {
    let coefficient = (i128::from(value.hi) << 64) | i128::from(value.lo);
    if coefficient == 0 {
        return Some(0);
    }
    let scaled = if value.exp >= 0 {
        if value.exp > 18 {
            return None;
        }
        coefficient.checked_mul(10_i128.pow(value.exp as u32))?
    } else {
        if value.exp < -38 {
            return Some(0);
        }
        coefficient / 10_i128.pow((-value.exp) as u32)
    };
    i64::try_from(scaled).ok()
}

fn main() {
    let args: Vec<_> = std::env::args().collect();
    let name = &args[1];
    let count: usize = args[2].parse().unwrap();
    let operation = args.get(3).map(String::as_str).unwrap_or("reference");
    let spellings: &[&str] = match name.as_str() {
        "integer" => &[
            "0",
            "1",
            "-1",
            "123456789",
            "-123456789",
            "1000000000000000000",
            "9223372036854775807",
            "-9223372036854775808",
        ],
        "fraction" => &[
            "1.25",
            "-1.25",
            "123456.789",
            "-123456.789",
            "9223372036854775807.9",
            "-9223372036854775808.9",
            "0.9999999999999999999999999999999999",
            "-0.9999999999999999999999999999999999",
        ],
        "overflow" => &[
            "9223372036854775808",
            "-9223372036854775809",
            "1e19",
            "-1e19",
            "9999999999999999999999999999999999",
            "-9999999999999999999999999999999999",
            "1e6144",
            "-1e6144",
        ],
        "underflow" => &[
            "1e-6176",
            "-1e-6176",
            "1e-39",
            "-1e-39",
            "9999999999999999999999999999999999e-34",
            "-9999999999999999999999999999999999e-34",
            "1e-20",
            "-1e-20",
        ],
        "scale" => &[
            "1e18",
            "-1e18",
            "123e15",
            "-123e15",
            "1234567890123456789012345678901234e-16",
            "-1234567890123456789012345678901234e-16",
            "9999999999999999999999999999999999e-33",
            "-9999999999999999999999999999999999e-33",
        ],
        _ => panic!("unknown case"),
    };
    let values: Vec<_> = spellings.iter().map(|s| Dec::parse(s).unwrap()).collect();
    let expected: &[Option<i64>] = match name.as_str() {
        "integer" => &[
            Some(0),
            Some(1),
            Some(-1),
            Some(123456789),
            Some(-123456789),
            Some(1000000000000000000),
            Some(9223372036854775807),
            Some(-9223372036854775808),
        ],
        "fraction" => &[
            Some(1),
            Some(-1),
            Some(123456),
            Some(-123456),
            Some(9223372036854775807),
            Some(-9223372036854775808),
            Some(0),
            Some(0),
        ],
        "overflow" => &[None, None, None, None, None, None, None, None],
        "underflow" => &[
            Some(0),
            Some(0),
            Some(0),
            Some(0),
            Some(0),
            Some(0),
            Some(0),
            Some(0),
        ],
        "scale" => &[
            Some(1000000000000000000),
            Some(-1000000000000000000),
            Some(123000000000000000),
            Some(-123000000000000000),
            Some(123456789012345678),
            Some(-123456789012345678),
            Some(9),
            Some(-9),
        ],
        _ => unreachable!(),
    };
    for (value, expected) in values.iter().zip(expected) {
        assert_eq!(value.truncate_to_int(), *expected);
        assert_eq!(reference(value), *expected);
    }
    let (ns, checksum) = match operation {
        "reference" => measure(&values, count, reference),
        "library" => measure(&values, count, Dec::truncate_to_int),
        _ => panic!("unknown operation"),
    };
    println!("case={name} count={count} ns={ns} checksum={checksum}");
}

fn measure(values: &[Dec], count: usize, work: impl Fn(&Dec) -> Option<i64>) -> (u128, i64) {
    let mut checksum = 0_i64;
    let start = Instant::now();
    for i in 0..count {
        checksum += (work(black_box(&values[i % values.len()])).unwrap_or(97) % 1_000_003)
            * (i % 7 + 1) as i64;
    }
    (start.elapsed().as_nanos(), checksum)
}
