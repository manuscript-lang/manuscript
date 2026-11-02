use ms_std_json::{Limits, Writer};
use std::{hint::black_box, time::Instant};

fn payload(case: &str) -> Vec<f64> {
    let mut bits = 0x9e37_79b9_7f4a_7c15u64;
    let mut values = Vec::new();
    for i in 0..1024 {
        bits ^= bits << 13;
        bits ^= bits >> 7;
        bits ^= bits << 17;
        let fraction = (bits & ((1u64 << 52) - 1)) | (1023u64 << 52);
        let value = match case {
            "midrange" => (f64::from_bits(fraction) - 1.0) * 1e10 - 5e9,
            "whole" => (f64::from_bits(fraction) - 1.0) * 1e18 - 5e17,
            "halfway" => {
                let edges = [f64::from_bits(0x4317_9085_685d_83c9), 2f64.powi(-25), 0.125];
                let sign = if i % 2 == 0 { 1.0 } else { -1.0 };
                edges[i % edges.len()] * sign
            }
            "thresholds" => {
                let edges: [f64; 8] = [
                    1e-6,
                    1e-5,
                    1e15,
                    1e21,
                    f64::MIN_POSITIVE,
                    f64::from_bits(1),
                    f64::MAX,
                    1.0,
                ];
                let value = edges[i % edges.len()];
                let bits = value.to_bits();
                let delta = i / edges.len() % 3;
                if delta == 0 {
                    value
                } else if delta == 1 {
                    f64::from_bits(bits - 1)
                } else {
                    f64::from_bits(bits + 1).min(f64::MAX)
                }
            }
            _ => panic!("unknown case"),
        };
        values.push(value);
    }
    values
}
fn rust_write(value: &[f64]) -> String {
    serde_json::to_string(value).unwrap()
}

fn ms_write(value: &[f64]) -> String {
    let mut writer = Writer::new(None, None);
    writer.begin_array();
    for &v in value {
        writer.item();
        writer.float(v);
    }
    writer.end_array();
    writer.finish().unwrap()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let data = payload(&args[1]);
    let operation = &args[2];
    let count: usize = args[3].parse().unwrap();
    let text = rust_write(&data);
    let ms_expected = ms_write(&data);
    assert_eq!(
        serde_json::from_str::<Vec<f64>>(&ms_expected).unwrap(),
        data
    );
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
