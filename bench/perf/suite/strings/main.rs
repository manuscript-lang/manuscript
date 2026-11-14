fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }

fn main() {
    let mut x = 21;
    let mut words: Vec<String> = Vec::new();
    for _ in 0..300000 {
        x = lcg(x);
        words.push(format!("  Item-{}_{} ", x % 100000, x / 3 % 977));
    }
    let (mut upper_len, mut replaced, mut found, mut padded) = (0usize, 0usize, 0usize, 0usize);
    for w in &words {
        let t = w.trim();
        upper_len += t.to_uppercase().len();
        replaced += t.replace('_', "--").replace("Item", "I").len();
        if t.contains("77") { found += 1; }
        if let Some(i) = t.find('-') { found += i; }
        padded += format!("{:.>20}", t).len() + format!("{:*<24}", t.to_lowercase()).len();
    }
    let mut joined: Vec<String> = words.iter().map(|w| w.trim().to_string()).collect();
    joined.sort();
    let mut sorted_sample = 0;
    for i in (0..joined.len()).step_by(1000) {
        sorted_sample += joined[i].len() + joined[i].as_bytes()[5] as usize;
    }
    let mut text = String::new();
    for w in &joined {
        if text.len() > 200000 { break; }
        text.push_str(w);
        text.push(',');
    }
    let parts = text.split(',').count();
    println!("upper {upper_len} replaced {replaced} found {found} padded {padded} sorted {sorted_sample} parts {parts}");
}
