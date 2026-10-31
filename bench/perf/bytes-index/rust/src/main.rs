use std::{hint::black_box, time::Instant};

#[inline(never)]
fn search(data: &[u8], byte: u8, start: i64) -> Option<usize> {
    let start = start.max(0) as usize;
    if start > data.len() { return None; }
    memchr::memchr(byte, &data[start..]).map(|at| start + at)
}

fn main() {
    println!("case,input_bytes,iterations,elapsed_ns,checksum");
    for n in [0usize, 1, 7, 15, 31, 32, 64, 256, 4096, 1048576] {
        for kind in ["miss", "first", "middle", "last", "negative", "past", "equal", "offset"] {
            let mut data = vec![b'a'; n];
            let mut pos = -1i64;
            let mut start = 0i64;
            if ["first", "negative", "past"].contains(&kind) { pos = 0; }
            if kind == "middle" { pos = (n / 2) as i64; }
            if ["last", "offset"].contains(&kind) { pos = n as i64 - 1; }
            if kind == "negative" { start = -1; }
            if kind == "past" { start = n as i64 + 1; }
            if kind == "equal" { start = n as i64; }
            if kind == "offset" { start = (n / 2) as i64; }
            if (0..n as i64).contains(&pos) { data[pos as usize] = 255; }
            let expected = if (0..n as i64).contains(&pos) && start <= pos { pos as usize } else { n };
            let mut work = n as i64;
            if expected < n { work = expected as i64 + 1 - start; }
            if start < 0 { work = expected as i64 + 1; }
            if start >= n as i64 { work = 1; }
            let iterations = (67108864 / work.max(32) as usize).clamp(256, 1000000);
            assert_eq!(search(&data, 255, start).unwrap_or(n), expected);
            let now = Instant::now();
            let mut checksum = 0usize;
            for _ in 0..iterations {
                checksum += black_box(search(black_box(&data), black_box(255), black_box(start))).unwrap_or(n);
            }
            let elapsed = now.elapsed().as_nanos();
            assert_eq!(checksum, expected * iterations);
            println!("{kind}_{n},{n},{iterations},{elapsed},{checksum}");
        }
    }
}
