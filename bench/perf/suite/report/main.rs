use std::io::{Read, Write};

fn main() {
    let mut data = String::new();
    std::io::stdin().read_to_string(&mut data).unwrap();
    let mut out = String::new();
    let mut total = 0i64;
    for line in data.split('\n').filter(|l| !l.is_empty()) {
        let (name, score) = line.split_once(' ').unwrap();
        let score: i64 = score.parse().unwrap_or(0);
        total += score;
        use std::fmt::Write as _;
        writeln!(out, "{:<12} {:>8} {}", name, score, score * 3 / 7).unwrap();
    }
    out.push_str(&format!("total {total}\n"));
    std::io::stdout().write_all(out.as_bytes()).unwrap();
}
