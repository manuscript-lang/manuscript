use std::hint::black_box;
use std::time::Instant;

fn strict_float(text: &str) -> Option<f64> {
    match text {
        "NaN" => return Some(f64::NAN),
        "Infinity" => return Some(f64::INFINITY),
        "-Infinity" => return Some(f64::NEG_INFINITY),
        _ => {}
    }
    let bytes = text.as_bytes();
    let mut i = usize::from(matches!(bytes.first(), Some(b'+' | b'-')));
    let digits = |i: &mut usize| {
        let begin = *i;
        while *i < bytes.len() && bytes[*i].is_ascii_digit() { *i += 1; }
        *i > begin
    };
    if !digits(&mut i) { return None; }
    if bytes.get(i) == Some(&b'.') {
        i += 1;
        if !digits(&mut i) { return None; }
    }
    if matches!(bytes.get(i), Some(b'e' | b'E')) {
        i += 1;
        if matches!(bytes.get(i), Some(b'+' | b'-')) { i += 1; }
        if !digits(&mut i) { return None; }
    }
    if i != bytes.len() { return None; }
    text.parse::<f64>().ok().filter(|v| !v.is_infinite())
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    assert_eq!(args.len(), 6);
    let operation = args[0].as_str();
    let dataset = args[1].as_str();
    let count: usize = args[3].parse().unwrap();
    let expected_checksum: i64 = args[4].parse().unwrap();
    let expected_last = &args[5];
    let mut checksum = 0i64;
    let mut last = String::new();
    if operation == "signed" || operation == "parse_int" {
        let values: Vec<i64> = (0..1000i64).map(|i| match dataset {
            "wide" => 9223372036800000000 + i, "negative" => i64::MIN + i, _ => i,
        }).collect();
        let texts: Vec<String> = values.iter().map(ToString::to_string).collect();
        for (value, text) in values.iter().zip(&texts) { assert_eq!(text.parse::<i64>().unwrap(), *value); }
        if operation == "signed" {
            let start = Instant::now();
            for i in 0..count {
                last = black_box(black_box(values[i % 1000]).to_string());
                checksum += last.len() as i64;
            }
            let elapsed = start.elapsed().as_nanos();
            println!("ns={elapsed} checksum={checksum} last={last}");
        } else {
            let mut value = 0i64;
            let start = Instant::now();
            for i in 0..count {
                value = black_box(black_box(texts[i % 1000].as_str()).parse::<i64>().unwrap());
                checksum += value % 997;
            }
            let elapsed = start.elapsed().as_nanos();
            last = value.to_string();
            println!("ns={elapsed} checksum={checksum} last={last}");
        }
    } else if operation == "parse_float" {
        let (texts, values): (Vec<String>, Vec<f64>) = match dataset {
            "long" => (vec![format!("0.{}1", "0".repeat(4096))], vec![0.0]),
            "wide" => (["1.7976931348623157e308", "5e-324", "1e20", "-1e20", "-0", "0"].iter().map(|s| s.to_string()).collect(),
                       vec![f64::MAX, f64::from_bits(1), 1e20, -1e20, -0.0, 0.0]),
            "scientific" => (vec!["1.5e-7".to_string(), "-1.5e-7".to_string()], vec![1.5e-7, -1.5e-7]),
            _ => {
                let values: Vec<f64> = (0..1000).map(|i| i as f64 / 8.0).collect();
                (values.iter().map(ToString::to_string).collect(), values)
            }
        };
        for (text, value) in texts.iter().zip(&values) { assert_eq!(strict_float(text).unwrap().to_bits(), value.to_bits()); }
        let start = Instant::now();
        for i in 0..count {
            let index = i % texts.len();
            let actual = black_box(strict_float(black_box(texts[index].as_str())).unwrap());
            if actual == values[index] { checksum += 1; }
        }
        let elapsed = start.elapsed().as_nanos();
        last = "ok".to_string();
        println!("ns={elapsed} checksum={checksum} last={last}");
    } else if operation == "float_special" {
        let texts = ["Infinity", "-Infinity", "NaN"];
        let values = [f64::INFINITY, f64::NEG_INFINITY, f64::NAN];
        let start = Instant::now();
        for i in 0..count {
            let index = i % 3;
            let actual = black_box(strict_float(black_box(texts[index])).unwrap());
            let matched = if index == 2 { actual.is_nan() } else { actual == values[index] };
            if matched { checksum += 1; }
        }
        let elapsed = start.elapsed().as_nanos();
        last = "ok".to_string();
        println!("ns={elapsed} checksum={checksum} last={last}");
    } else if operation == "float_error" {
        let text = match dataset {
            "late" => format!("{}!", "9".repeat(4096)),
            "range" => "1e400".to_string(),
            "range-long" => "9".repeat(4096),
            "unicode" => "١".to_string(),
            _ => "!".to_string(),
        };
        assert!(strict_float(&text).is_none());
        let start = Instant::now();
        for _ in 0..count {
            if black_box(strict_float(black_box(text.as_str())).is_none()) { checksum += 1; }
        }
        let elapsed = start.elapsed().as_nanos();
        last = "none".to_string();
        println!("ns={elapsed} checksum={checksum} last={last}");
    } else { panic!("unknown operation"); }
    assert_eq!(checksum, expected_checksum);
    assert_eq!(&last, expected_last);
}
