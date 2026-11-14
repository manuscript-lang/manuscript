use std::thread;

fn count_primes(lo: i64, hi: i64) -> i64 {
    let mut count = 0;
    for n in lo..hi {
        if n < 2 { continue; }
        let mut is_prime = true;
        let mut d = 2;
        while d * d <= n {
            if n % d == 0 { is_prime = false; break; }
            d += 1;
        }
        if is_prime { count += 1; }
    }
    count
}

fn small(i: i64) -> i64 {
    let mut t = 0;
    for k in 0..200 { t += (i + k) % 7; }
    t
}

fn main() {
    let handles: Vec<_> = (0..16).map(|chunk| {
        let lo = chunk * 250000;
        thread::spawn(move || count_primes(lo, lo + 250000))
    }).collect();
    let primes: i64 = handles.into_iter().map(|h| h.join().unwrap()).sum();

    // One OS thread per small task would measure thread creation, not the work; use a fixed pool of workers over a shared index.
    let workers = thread::available_parallelism().map(|n| n.get()).unwrap_or(4);
    let total: i64 = thread::scope(|s| {
        let handles: Vec<_> = (0..workers).map(|w| s.spawn(move || {
            let mut t = 0;
            let mut i = w as i64;
            while i < 100000 { t += small(i); i += workers as i64; }
            t
        })).collect();
        handles.into_iter().map(|h| h.join().unwrap()).sum()
    });
    println!("primes {primes} small {total}");
}
