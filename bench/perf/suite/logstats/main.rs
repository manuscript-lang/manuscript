use std::collections::HashMap;
use std::io::Read;

fn main() {
    let mut data = String::new();
    std::io::stdin().read_to_string(&mut data).unwrap();
    let (mut rows, mut latency, mut classes) = (0u64, 0u64, [0u64; 4]);
    let mut paths: HashMap<&str, u64> = HashMap::new();
    for line in data.split('\n') {
        if line.is_empty() {
            continue;
        }
        let f: Vec<&str> = line.split(' ').collect();
        rows += 1;
        latency += f[5].parse::<u64>().unwrap_or(0);
        classes[(f[4].as_bytes()[0] - b'2') as usize] += 1;
        *paths.entry(f[3]).or_insert(0) += 1;
    }
    println!("lines: {rows}");
    println!("status: 2xx={} 3xx={} 4xx={} 5xx={}", classes[0], classes[1], classes[2], classes[3]);
    println!("latency: {latency}");
    let mut ranked: Vec<(&str, u64)> = paths.into_iter().collect();
    ranked.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    for (k, v) in ranked.iter().take(5) {
        println!("{k} {v}");
    }
}
