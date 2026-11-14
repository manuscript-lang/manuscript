use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;

fn chunk_checksum(chunk: i64) -> i64 {
    let mut hist = [0i64; 256];
    let mut x = chunk * 7919 + 1;
    let mut h = 0i64;
    for _ in 0..200000 {
        x = (x * 48271) % 2147483647;
        hist[(x % 256) as usize] += 1;
        h = (h * 31 + x) % 1000000007;
    }
    for b in 0..256 {
        h = (h * 131 + hist[b]) % 1000000007;
    }
    h
}

fn main() {
    // A fixed pool of one worker per core pulling chunk numbers, the usual shape without a task runtime.
    let workers = thread::available_parallelism().map(|n| n.get()).unwrap_or(4);
    let next = AtomicUsize::new(0);
    let total: i64 = thread::scope(|s| {
        let handles: Vec<_> = (0..workers)
            .map(|_| {
                s.spawn(|| {
                    let mut t = 0;
                    loop {
                        let c = next.fetch_add(1, Ordering::Relaxed);
                        if c >= 128 {
                            return t;
                        }
                        t += chunk_checksum(c as i64);
                    }
                })
            })
            .collect();
        handles.into_iter().map(|h| h.join().unwrap()).sum()
    });
    println!("chunks 128 checksum {total}");
}
