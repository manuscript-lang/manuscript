use std::{hint::black_box, time::Instant};

fn roundtrip(text: String) -> String {
    let mut fields = toml::Table::new();
    fields.insert("value".into(), toml::Value::String(text));
    toml::to_string(&toml::Value::Table(fields)).unwrap()
}
fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args[1] == "--validate" {
        let input = std::fs::read_to_string(&args[2]).unwrap();
        let output = std::fs::read_to_string(&args[3]).unwrap();
        let mut fields = toml::Table::new();
        fields.insert("value".into(), toml::Value::String(input));
        assert_eq!(
            toml::Value::Table(fields),
            toml::from_str::<toml::Value>(&output).unwrap()
        );
        return;
    }
    let text = std::fs::read_to_string(&args[1]).unwrap();
    let count: usize = args[2].parse().unwrap();
    let expected = roundtrip(text);
    if count == 0 {
        print!("{expected}");
        return;
    }
    let mut checksum = 0usize;
    let start = Instant::now();
    for _ in 0..count {
        let text = std::fs::read_to_string(&args[1]).unwrap();
        let output = roundtrip(black_box(text));
        assert_eq!(black_box(&output), &expected);
        checksum += output.len();
    }
    println!(
        "{}\t{}\t{}",
        start.elapsed().as_nanos(),
        checksum,
        expected.len()
    );
}
