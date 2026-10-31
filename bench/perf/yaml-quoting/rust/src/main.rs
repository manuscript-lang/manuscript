use std::{collections::BTreeMap, hint::black_box, time::Instant};
fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args[1] == "--validate" {
        let text = std::fs::read_to_string(&args[2]).unwrap();
        let encoded = std::fs::read_to_string(&args[3]).unwrap();
        let decoded: BTreeMap<String, String> = serde_yaml_ng::from_str(&encoded).unwrap();
        assert_eq!(decoded, BTreeMap::from([("value".into(), text)]));
        return;
    }
    let text = std::fs::read_to_string(&args[1]).unwrap();
    let count: usize = args[2].parse().unwrap();
    let mut fields = serde_yaml_ng::Mapping::new();
    fields.insert(
        serde_yaml_ng::Value::String("value".into()),
        serde_yaml_ng::Value::String(text),
    );
    let value = serde_yaml_ng::Value::Mapping(fields);
    let expected = serde_yaml_ng::to_string(&value).unwrap();
    if count == 0 {
        print!("{expected}");
        return;
    }
    let mut checksum = 0;
    let start = Instant::now();
    for _ in 0..count {
        let out = serde_yaml_ng::to_string(black_box(&value)).unwrap();
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
