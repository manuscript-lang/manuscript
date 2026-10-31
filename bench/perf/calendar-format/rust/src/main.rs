use ms_std_time::core_time::{self, Ts};
use std::fmt::Write;
use std::hint::black_box;
use std::time::Instant;

// The same calendar conversion, first-token-wins scan and memoized token output
// as Manuscript; ordinary Rust formats only tokens encountered in the pattern.
fn rust_format(ts: Ts, pattern: &[u8]) -> Vec<u8> {
    let c = core_time::calendar(ts, "UTC").unwrap();
    let v = c.civil;
    let mut out = Vec::with_capacity(pattern.len() + 16);
    let keys: [&[u8]; 9] = [
        b"YYYY", b"MM", b"DD", b"HH", b"mm", b"ss", b"SSS", b"ZZ", b"zone",
    ];
    let mut values: [Option<String>; 8] = std::array::from_fn(|_| None);
    let mut rest = pattern;
    'scan: while !rest.is_empty() {
        for (index, key) in keys.iter().enumerate() {
            let Some(tail) = rest.strip_prefix(*key) else {
                continue;
            };
            if index == 8 {
                out.extend_from_slice(c.zone.as_bytes());
            } else {
                let value = values[index].get_or_insert_with(|| {
                    let mut value = String::new();
                    match index {
                        0 => write!(value, "{:04}", v.year),
                        1 => write!(value, "{:02}", v.month),
                        2 => write!(value, "{:02}", v.day),
                        3 => write!(value, "{:02}", v.hour),
                        4 => write!(value, "{:02}", v.minute),
                        5 => write!(value, "{:02}", v.second),
                        6 => write!(value, "{:03}", v.nanosecond / 1_000_000),
                        7 => {
                            let sign = if c.offset_seconds < 0 { '-' } else { '+' };
                            let abs = c.offset_seconds.abs();
                            write!(value, "{sign}{:02}:{:02}", abs / 3600, abs % 3600 / 60)
                        }
                        _ => unreachable!(),
                    }
                    .unwrap();
                    value
                });
                out.extend_from_slice(value.as_bytes());
            }
            rest = tail;
            continue 'scan;
        }
        out.push(rest[0]);
        rest = &rest[1..];
    }
    out
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mode = &args[0];
    let count: usize = args[1].parse().unwrap();
    let pattern = &args[2];
    let expected = [&args[3], &args[4]];
    let mut checksum = 0usize;
    let mut last = Vec::new();
    let moments = [
        Ts {
            seconds: 1_710_073_815,
            nanos: 250_000_000,
        },
        Ts {
            seconds: 1_710_073_816,
            nanos: 250_000_000,
        },
    ];
    let started = Instant::now();
    for i in 0..count {
        let ts = moments[i % 2];
        last = if mode == "rust" {
            rust_format(black_box(ts), black_box(pattern.as_bytes()))
        } else {
            core_time::format(black_box(ts), black_box(pattern.as_bytes()), "UTC").unwrap()
        };
        checksum += black_box(last.len());
        assert_eq!(last, expected[i % 2].as_bytes());
    }
    let elapsed = started.elapsed().as_nanos();
    assert_eq!(checksum, expected[0].len() * count);
    assert_eq!(last, expected[1].as_bytes());
    let last = String::from_utf8(last).unwrap();
    println!("{count}\t{elapsed}\t{checksum}\t{last}");
}
