fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut a = vec![0i64; n * n];
    let mut b = vec![0i64; n * n];
    let mut c = vec![0i64; n * n];
    for i in 0..n * n { a[i] = (i % 7) as i64; b[i] = (i % 5) as i64; }
    for i in 0..n { for k in 0..n { let x = a[i * n + k]; for j in 0..n { c[i * n + j] += x * b[k * n + j]; } } }
    let mut sum: i64 = 0;
    for i in 0..n * n { sum += c[i] * (i as i64 % 13 + 1); }
    println!("{}", sum);
}
