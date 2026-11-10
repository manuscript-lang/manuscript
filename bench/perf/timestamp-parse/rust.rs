//! Standalone timing producer for the production native timestamp parser.
use ms_std_time::logic as parser;
use std::hint::black_box;

fn main() {
    let args: Vec<_> = std::env::args().collect();
    let case = &args[1];
    let reps: usize = args[2].parse().unwrap();
    let text: Vec<u8> = match case.as_str() {
        "valid_z" => b"2026-03-01T12:30:45.123Z".to_vec(),
        "valid_nofrac" => b"2026-03-01T12:30:45Z".to_vec(),
        "valid_max" => b"2026-03-01T12:30:45.123456789+05:30".to_vec(),
        "short" => b"bad".to_vec(),
        "bad_early" => b"X026-03-01T12:30:45.123Z".to_vec(),
        "bad_date" => b"2026-02-30T12:30:45.123Z".to_vec(),
        "bad_frac10" => b"2026-03-01T12:30:45.1234567890Z".to_vec(),
        "bad_len36" => b"2026-03-01T12:30:45.1234567890+05:30".to_vec(),
        "range" => b"0001-01-01T00:00:00.123456789+00:01".to_vec(),
        "nul" => b"2026-03-01T12:30:45.123\0".to_vec(),
        _ => {
            let n: usize = case.parse().unwrap();
            let mut x = b"2026-03-01T12:30:45.".to_vec();
            x.resize(x.len() + n, b'0');
            x.push(b'Z');
            x
        }
    };
    let expected = match case.as_str() {
        "valid_z" => Ok(parser::Ts {
            seconds: 1772368245,
            nanos: 123000000,
        }),
        "valid_nofrac" => Ok(parser::Ts {
            seconds: 1772368245,
            nanos: 0,
        }),
        "valid_max" => Ok(parser::Ts {
            seconds: 1772348445,
            nanos: 123456789,
        }),
        "range" => Err(ms_rt_abi::STATUS_OUT_OF_RANGE),
        _ => Err(ms_rt_abi::STATUS_INVALID_DATA),
    };
    assert_eq!(parser::parse_timestamp(&text), expected);
    let t = std::time::Instant::now();
    for _ in 0..reps {
        assert_eq!(
            black_box(parser::parse_timestamp(black_box(&text))),
            expected
        );
    }
    println!("{} {} {}", case, reps, t.elapsed().as_nanos());
}
