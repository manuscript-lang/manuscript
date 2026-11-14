use std::time::Instant;

fn main() {
    let xs: Vec<String> = (0..2000).map(|i| format!("item-number-{i}")).collect();
    let t0 = Instant::now();
    let mut t = 0;
    for i in 0..20000 {
        let key = format!("item-number-{}", i % 2000);
        t += xs.iter().position(|s| *s == key).unwrap_or(0) as i64;
    }
    println!("index_of {} us {t}", t0.elapsed().as_micros());
}
