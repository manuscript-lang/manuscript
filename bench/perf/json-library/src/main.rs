use ms_std_json::{Limits, Writer};
use std::{hint::black_box, time::Instant};

enum Payload {
    Strings(Vec<String>),
    Integers(Vec<i64>),
    Floats(Vec<f64>),
}

fn payload(case: &str) -> Payload {
    match case {
        "empty" => Payload::Strings(vec![]),
        "tiny" => Payload::Strings(vec!["Ada".into(), "bob".into(), "x".into()]),
        "ascii" => Payload::Strings((0..512).map(|i| format!("user{i:05}-plain-text")).collect()),
        "unicode" => Payload::Strings(vec!["é🙂日本語".repeat(16); 256]),
        "escapes" => Payload::Strings(vec!["a\"\\\n\r\t\0\u{1f}é🙂".repeat(8); 256]),
        "integers" => Payload::Integers((0..1024).map(|i| i * 7919 - 4_000_000).collect()),
        "decimals" => Payload::Floats(
            (0..512)
                .map(|i| (i as f64 - 256.0) * 0.25 + 0.125)
                .collect(),
        ),
        "hard-floats" => {
            let mut bits = 0x9e37_79b9_7f4a_7c15u64;
            let mut values = Vec::new();
            while values.len() < 512 {
                bits ^= bits << 13;
                bits ^= bits >> 7;
                bits ^= bits << 17;
                let v = f64::from_bits(bits);
                if v.is_finite() {
                    values.push(v);
                }
            }
            Payload::Floats(values)
        }
        _ => panic!("unknown case"),
    }
}

fn rust_write(value: &Payload) -> String {
    match value {
        Payload::Strings(v) => serde_json::to_string(v).unwrap(),
        Payload::Integers(v) => serde_json::to_string(v).unwrap(),
        Payload::Floats(v) => serde_json::to_string(v).unwrap(),
    }
}

fn ms_write(value: &Payload) -> String {
    let mut writer = Writer::new(None, None);
    writer.begin_array();
    match value {
        Payload::Strings(values) => {
            for value in values {
                writer.item();
                writer.string(value);
            }
        }
        Payload::Integers(values) => {
            for &value in values {
                writer.item();
                writer.int(value);
            }
        }
        Payload::Floats(values) => {
            for &value in values {
                writer.item();
                writer.float(value);
            }
        }
    }
    writer.end_array();
    writer.finish().unwrap()
}

fn float_oracle() {
    use std::io::Write;
    let mut out = std::io::BufWriter::new(std::io::stdout().lock());
    let mut bits = 0x9e37_79b9_7f4a_7c15u64;
    let edges = [
        0.0,
        -0.0,
        f64::INFINITY,
        f64::NEG_INFINITY,
        f64::NAN,
        f64::from_bits(1),
        f64::MAX,
        f64::MIN_POSITIVE,
        1e-6,
        1e21,
        1.0,
    ];
    for i in 0..1_000_000 {
        bits ^= bits << 13;
        bits ^= bits >> 7;
        bits ^= bits << 17;
        let value = if i % 5 == 0 {
            edges[bits as usize % edges.len()]
        } else if i % 5 == 1 {
            (bits % 1_000_000_000_000_000) as f64 / 10f64.powi((bits >> 32) as i32 % 22)
        } else {
            f64::from_bits(bits)
        };
        let text = ms_std_json::float_text(value);
        writeln!(
            out,
            "{:016x}\t{}",
            value.to_bits(),
            text.as_deref().unwrap_or("null")
        )
        .unwrap();
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args[1] == "float-oracle" {
        float_oracle();
        return;
    }
    let data = payload(&args[1]);
    let operation = &args[2];
    let count: usize = args[3].parse().unwrap();
    let text = rust_write(&data);
    let ms_expected = ms_write(&data);
    match &data {
        Payload::Strings(v) => assert_eq!(
            &serde_json::from_str::<Vec<String>>(&ms_expected).unwrap(),
            v
        ),
        Payload::Integers(v) => {
            assert_eq!(&serde_json::from_str::<Vec<i64>>(&ms_expected).unwrap(), v)
        }
        Payload::Floats(v) => {
            assert_eq!(&serde_json::from_str::<Vec<f64>>(&ms_expected).unwrap(), v)
        }
    }
    let (doc, root) = ms_std_json::parse(&text, Limits::default()).unwrap();
    let reencoded = doc.stringify(root, None, None).unwrap();
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&reencoded).unwrap(),
        serde_json::from_str::<serde_json::Value>(&text).unwrap()
    );
    let nodes = doc.nodes.len();
    if operation == "ms-output" {
        print!("{ms_expected}");
        return;
    }
    if operation == "rust-output" {
        print!("{text}");
        return;
    }
    let expected = if operation == "ms-write" {
        &ms_expected
    } else {
        &text
    };
    let mut checksum = 0usize;
    let start = Instant::now();
    for _ in 0..count {
        match operation.as_str() {
            "ms-write" => {
                let out = ms_write(black_box(&data));
                assert_eq!(black_box(&out), expected);
                checksum += out.len();
            }
            "rust-write" => {
                let out = rust_write(black_box(&data));
                assert_eq!(black_box(&out), expected);
                checksum += out.len();
            }
            "ms-parse" => {
                let (doc, root) = ms_std_json::parse(black_box(&text), Limits::default()).unwrap();
                black_box((&doc, root));
                assert_eq!(doc.nodes.len(), nodes);
                checksum += nodes;
            }
            "rust-parse" => {
                let value: serde_json::Value = serde_json::from_str(black_box(&text)).unwrap();
                black_box(&value);
                assert_eq!(value.as_array().unwrap().len() + 1, nodes);
                checksum += nodes;
            }
            _ => panic!("unknown operation"),
        }
    }
    let unit = if operation.ends_with("parse") {
        nodes
    } else {
        expected.len()
    };
    println!("{}\t{}\t{}", start.elapsed().as_nanos(), checksum, unit);
}
