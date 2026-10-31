use std::hint::black_box;
use std::time::Instant;

fn scientific(value: f64, digits: usize) -> String {
    let text = format!("{value:.digits$e}");
    let pos = text.find('e').unwrap();
    normalize_scientific(text, pos)
}

fn normalize_scientific(mut text: String, pos: usize) -> String {
    if text.as_bytes()[pos + 1] != b'-' {
        text.insert(pos + 1, '+');
    }
    text
}

fn precision(value: f64, digits: usize) -> String {
    let text = format!("{:.*e}", digits - 1, value);
    let (mantissa, exponent) = text.split_once('e').unwrap();
    let exponent: i32 = exponent.parse().unwrap();
    if exponent < -6 || exponent >= digits as i32 {
        let pos = text.find('e').unwrap();
        return normalize_scientific(text, pos);
    }
    let negative = value.is_sign_negative();
    let mantissa = mantissa.trim_start_matches('-');
    let point = exponent + 1;
    let mut out = String::with_capacity(digits + 10);
    if negative { out.push('-'); }
    if point <= 0 {
        out.push_str("0.");
        for _ in 0..-point { out.push('0'); }
    }
    for (index, digit) in mantissa.chars().filter(|&c| c != '.').enumerate() {
        if point > 0 && index == point as usize { out.push('.'); }
        out.push(digit);
    }
    out
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    assert_eq!(args.len(), 6);
    let operation = args[0].as_str();
    let dataset = args[1].as_str();
    let digits: usize = args[2].parse().unwrap();
    let count: usize = args[3].parse().unwrap();
    let expected_checksum: i64 = args[4].parse().unwrap();
    let expected_last = &args[5];
    if operation == "parse_zero" {
        let mut text = "0".repeat(4096);
        text.push('1');
        let mut checksum = 0i64;
        let mut last = 0i64;
        let start = Instant::now();
        for _ in 0..count {
            last = black_box(i64::from_str_radix(black_box(text.as_str()), digits as u32).unwrap());
            checksum += last;
        }
        let elapsed = start.elapsed().as_nanos();
        let final_text = last.to_string();
        println!("ns={elapsed} checksum={checksum} last={final_text}");
        assert_eq!(checksum, expected_checksum);
        assert_eq!(&final_text, expected_last);
        return;
    }
    if operation == "parse_error" {
        let len = if dataset == "overflow-short" { 32 } else { 4096 };
        let mut text = (b"0123456789abcdefghijklmnopqrstuvwxyz"[digits - 1] as char).to_string().repeat(len);
        if dataset == "late" { text.push('!'); }
        if dataset == "early" { text.insert(0, '!'); }
        let mut checksum = 0i64;
        let mut last = "";
        let start = Instant::now();
        for _ in 0..count {
            let input = black_box(text.as_str());
            // Manuscript prioritizes any malformed digit over overflow. Rust's
            // standard parser alone stops early at overflow; validate first.
            last = black_box(if input.bytes().any(|b| (b as char).to_digit(digits as u32).is_none()) {
                "number: invalid data"
            } else {
                assert!(i64::from_str_radix(input, digits as u32).is_err());
                "number: value out of range"
            });
            checksum += last.len() as i64;
        }
        let elapsed = start.elapsed().as_nanos();
        println!("ns={elapsed} checksum={checksum} last={last}");
        assert_eq!(checksum, expected_checksum);
        assert_eq!(last, expected_last);
        return;
    }
    if operation == "parse" {
        let inputs: Vec<String> = (0..1000i64).map(|i| {
            let value = match dataset {
                "wide" => 9223372036800000000 + i,
                "negative" => i64::MIN + i,
                _ => i,
            };
            let mut magnitude = value.unsigned_abs();
            let mut text = Vec::new();
            loop {
                let digit = (magnitude % digits as u64) as usize;
                text.push(b"0123456789abcdefghijklmnopqrstuvwxyz"[digit]);
                magnitude /= digits as u64;
                if magnitude == 0 { break; }
            }
            if value < 0 { text.push(b'-'); }
            text.reverse();
            String::from_utf8(text).unwrap()
        }).collect();
        for (i, text) in inputs.iter().enumerate() {
            let expected = match dataset {
                "wide" => 9223372036800000000 + i as i64,
                "negative" => i64::MIN + i as i64,
                _ => i as i64,
            };
            assert_eq!(i64::from_str_radix(text, digits as u32).unwrap(), expected);
        }
        let mut checksum = 0i64;
        let mut last = 0i64;
        let start = Instant::now();
        for i in 0..count {
            last = black_box(i64::from_str_radix(black_box(inputs[i % 1000].as_str()), digits as u32).unwrap());
            checksum += last % 997;
        }
        let elapsed = start.elapsed().as_nanos();
        let final_text = last.to_string();
        println!("ns={elapsed} checksum={checksum} last={final_text}");
        assert_eq!(checksum, expected_checksum);
        assert_eq!(&final_text, expected_last);
        return;
    }
    let mut checksum = 0usize;
    let mut last = String::new();
    let start = Instant::now();
    for i in 0..count {
        let mut value = (i % 1000) as f64 / 8.0;
        if dataset == "wide" {
            value = if i % 2 == 0 { f64::MAX } else { f64::from_bits(1) };
        } else if dataset == "zero" {
            value = if i % 2 == 0 { 0.0 } else { -0.0 };
        }
        last = black_box(match operation {
            "exponential" => scientific(value, digits),
            "precision" => precision(value, digits),
            "fixed" => format!("{value:.digits$}"),
            "shortest" => value.to_string(),
            _ => panic!("unsupported operation"),
        });
        checksum += last.len();
    }
    let elapsed = start.elapsed().as_nanos();
    println!("ns={elapsed} checksum={checksum} last={last}");
    assert_eq!(checksum as i64, expected_checksum);
    assert_eq!(&last, expected_last);
}
