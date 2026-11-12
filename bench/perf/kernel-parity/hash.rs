// open addressing, linear probing, Int keys, power-of-two table
fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let cap = (n * 2).next_power_of_two();
    let mask = cap - 1;
    let mut keys = vec![-1i64; cap];
    let mut vals = vec![0i64; cap];
    let mut r: i64 = 1;
    for _ in 0..n {
        r = (r * 1103515245 + 12345) % 2147483648;
        let k = r % 1000003;
        let mut h = ((k as usize).wrapping_mul(2654435761)) & mask;
        while keys[h] != -1 && keys[h] != k { h = (h + 1) & mask; }
        keys[h] = k;
        vals[h] += 1;
    }
    let mut sum: i64 = 0;
    for k in 0..n as i64 {
        let mut h = ((k as usize).wrapping_mul(2654435761)) & mask;
        while keys[h] != -1 && keys[h] != k { h = (h + 1) & mask; }
        if keys[h] == k { sum += vals[h] * (k + 1); }
    }
    println!("{}", sum);
}
