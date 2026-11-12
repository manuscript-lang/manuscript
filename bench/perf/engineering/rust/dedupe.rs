use std::collections::HashMap;
use std::io::Read;

fn main() {
    let mut data = String::new();
    std::io::stdin().read_to_string(&mut data).unwrap();
    let mut lines: HashMap<&str, u64> = HashMap::new();
    let mut names: HashMap<&str, u64> = HashMap::new();
    let mut total = 0;
    for line in data.split('\n').filter(|l| !l.is_empty()) {
        total += 1;
        *lines.entry(line).or_insert(0) += 1;
        *names.entry(line.split(' ').next().unwrap()).or_insert(0) += 1;
    }
    let (most, count) = lines
        .iter()
        .map(|(k, v)| (*k, *v))
        .max_by(|a, b| a.1.cmp(&b.1).then(b.0.cmp(a.0)))
        .unwrap();
    println!("lines: {total}");
    println!("distinct lines: {}", lines.len());
    println!("distinct names: {}", names.len());
    println!("most repeated: {most} x{count}");
}
