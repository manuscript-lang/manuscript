fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut r: i64 = 1;
    let mut s: Vec<u8> = Vec::new(); let mut t: Vec<u8> = Vec::new();
    for _ in 0..n { r = (r * 1103515245 + 12345) % 2147483648; s.push((r % 4) as u8); }
    for _ in 0..n { r = (r * 1103515245 + 12345) % 2147483648; t.push(((r / 16) % 4) as u8); }
    let mut prev = vec![0i64; n + 1];
    let mut cur = vec![0i64; n + 1];
    for i in 1..=n {
        for j in 1..=n {
            cur[j] = if s[i - 1] == t[j - 1] { prev[j - 1] + 1 } else if prev[j] > cur[j - 1] { prev[j] } else { cur[j - 1] };
        }
        std::mem::swap(&mut prev, &mut cur);
    }
    println!("{}", prev[n]);
}
