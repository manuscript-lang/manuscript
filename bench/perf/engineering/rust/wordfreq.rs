use std::collections::HashMap;
use std::io::Read;

fn main() {
    let mut data = String::new();
    std::io::stdin().read_to_string(&mut data).unwrap();
    let data = data.to_lowercase();
    let mut counts: HashMap<&str, u64> = HashMap::new();
    let mut total = 0;
    for w in data.split(|c| c == ' ' || c == '.' || c == '\n').filter(|w| !w.is_empty()) {
        total += 1;
        *counts.entry(w).or_insert(0) += 1;
    }
    println!("words: {total}");
    println!("distinct: {}", counts.len());
    let mut ranked: Vec<_> = counts.into_iter().collect();
    ranked.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    for (k, v) in ranked.iter().take(10) {
        println!("{k} {v}");
    }
}
