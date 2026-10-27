// Same workloads as ../ms/src/main.ms: a about 1 MB String built from pieces of each size, best of 40 runs in microseconds.
use std::hint::black_box;
use std::time::Instant;

fn run(piece: &str, count: usize) -> usize {
    let mut s = String::new();
    for _ in 0..count {
        s.push_str(black_box(piece));
    }
    black_box(s).len()
}

fn main() {
    for size in [4usize, 16, 64, 256, 1024, 8192] {
        let piece = "x".repeat(size);
        let count = 1000000 / size;
        let mut best = u128::MAX;
        let mut checksum = 0;
        for _ in 0..40 {
            let started = Instant::now();
            checksum += run(&piece, count);
            best = best.min(started.elapsed().as_nanos());
        }
        println!("append{}\t{}\t# {}", size, best / 1000, checksum);
    }
    for count in [10000usize, 100000, 1000000] {
        let mut best = u128::MAX;
        let mut checksum = 0;
        for _ in 0..40 {
            let started = Instant::now();
            let mut items: Vec<i64> = Vec::new();
            for i in 0..count {
                items.push(black_box(i as i64));
            }
            checksum += black_box(items).len();
            best = best.min(started.elapsed().as_nanos());
        }
        println!("list{}\t{}\t# {}", count, best / 1000, checksum);
    }
}
