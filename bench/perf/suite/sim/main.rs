fn heat(n: usize, steps: usize) -> i64 {
    let mut a = vec![0.0f64; n * n];
    let mut b = vec![0.0f64; n * n];
    for i in 0..n * n { if i % 97 == 0 { a[i] = 100.0; } }
    for _ in 0..steps {
        for y in 1..n - 1 {
            for x in 1..n - 1 {
                let i = y * n + x;
                b[i] = a[i] + 0.2 * (a[i - 1] + a[i + 1] + a[i - n] + a[i + n] - 4.0 * a[i]);
            }
        }
        a.copy_from_slice(&b);
    }
    let mut total = 0.0;
    for v in &a { total += v; }
    (total * 1000.0) as i64
}

fn mandelbrot(size: i64, limit: i64) -> i64 {
    let (mut inside, mut work) = (0i64, 0i64);
    for py in 0..size {
        for px in 0..size {
            let cr = px as f64 * 3.0 / size as f64 - 2.0;
            let ci = py as f64 * 2.0 / size as f64 - 1.0;
            let (mut zr, mut zi, mut k) = (0.0f64, 0.0f64, 0i64);
            while k < limit && zr * zr + zi * zi <= 4.0 {
                let t = zr * zr - zi * zi + cr;
                zi = 2.0 * zr * zi + ci;
                zr = t;
                k += 1;
            }
            work += k;
            if k == limit { inside += 1; }
        }
    }
    inside * 1000003 + work % 1000003
}

fn norms(count: i64) -> i64 {
    let mut total = 0.0f64;
    for i in 1..count {
        let f = i as f64;
        total += (f * f + 3.0).sqrt();
    }
    total as i64
}

fn main() {
    println!("heat {}", heat(500, 120));
    println!("mandelbrot {}", mandelbrot(700, 200));
    println!("norms {}", norms(20000000));
}
