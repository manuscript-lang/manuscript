use std::io::Read;

fn main() {
    let mut data = String::new();
    std::io::stdin().read_to_string(&mut data).unwrap();
    let mut recs: Vec<(&str, i64)> = Vec::new();
    for line in data.split('\n').filter(|l| !l.is_empty()) {
        let (name, score) = line.split_once(' ').unwrap();
        recs.push((name, score.parse().unwrap_or(0)));
    }
    recs.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    let mut check: i64 = 0;
    for (i, r) in recs.iter().enumerate() {
        check = (check * 31 + r.1 + i as i64) % 1000000007;
    }
    println!("records: {}", recs.len());
    println!("checksum: {check}");
    for i in [0, 1, 2, recs.len() - 1] {
        println!("{} {}", recs[i].0, recs[i].1);
    }
}
