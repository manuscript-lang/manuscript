use std::{hint::black_box, time::Instant};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let text = std::fs::read_to_string(&args[1]).unwrap();
    let count: usize = args[2].parse().unwrap();
    let mut fields = toml::map::Map::new();
    fields.insert("value".into(), toml::Value::String(text));
    let value = toml::Value::Table(fields);
    let expected = toml::to_string(&value).unwrap();
    if count == 0 {
        print!("{expected}");
        return;
    }
    let mut checksum = 0;
    let start = Instant::now();
    for _ in 0..count {
        let out = toml::to_string(black_box(&value)).unwrap();
        assert_eq!(black_box(&out), &expected);
        checksum += out.len();
    }
    println!(
        "{}\t{}\t{}",
        start.elapsed().as_nanos(),
        checksum,
        expected.len()
    );
}
