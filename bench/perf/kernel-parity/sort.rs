fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut a: Vec<i64> = Vec::with_capacity(n);
    let mut r: i64 = 1;
    for _ in 0..n { r = (r * 1103515245 + 12345) % 2147483648; a.push(r % 100003); }
    // insertion sort blocks of 16 then bottom-up merge
    let mut i = 0;
    while i < n {
        let end = (i + 16).min(n);
        for j in i + 1..end {
            let x = a[j];
            let mut k = j;
            while k > i && a[k - 1] > x { a[k] = a[k - 1]; k -= 1; }
            a[k] = x;
        }
        i += 16;
    }
    let mut b = vec![0i64; n];
    let mut w = 16;
    while w < n {
        let mut lo = 0;
        while lo < n {
            let mid = (lo + w).min(n);
            let hi = (lo + 2 * w).min(n);
            let (mut p, mut q, mut o) = (lo, mid, lo);
            while p < mid && q < hi {
                if a[q] < a[p] { b[o] = a[q]; q += 1; } else { b[o] = a[p]; p += 1; }
                o += 1;
            }
            while p < mid { b[o] = a[p]; p += 1; o += 1; }
            while q < hi { b[o] = a[q]; q += 1; o += 1; }
            lo += 2 * w;
        }
        std::mem::swap(&mut a, &mut b);
        w *= 2;
    }
    let mut sum: i64 = 0;
    for (i, v) in a.iter().enumerate() { sum += (v + 1) * (i as i64 + 1); }
    println!("{}", sum);
}
