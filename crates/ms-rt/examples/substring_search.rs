//! Bounded substring-search benchmark; run with `cargo run --release -p ms-rt --example substring_search`.
use std::{hint::black_box, time::Instant};

fn measure(label: &str, hay: &[u8], needle: &[u8], iterations: usize) {
    for (direction, search) in [
        (
            "forward",
            ms_rt::string::find as fn(&[u8], &[u8]) -> Option<usize>,
        ),
        ("reverse", ms_rt::string::rfind),
    ] {
        let expected = if needle.is_empty() {
            Some(if direction == "forward" { 0 } else { hay.len() })
        } else if direction == "forward" {
            hay.windows(needle.len()).position(|w| w == needle)
        } else {
            hay.windows(needle.len()).rposition(|w| w == needle)
        };
        assert_eq!(search(hay, needle), expected);
        let start = Instant::now();
        let mut checksum = 0usize;
        for _ in 0..iterations {
            checksum = checksum.wrapping_add(
                black_box(search(black_box(hay), black_box(needle))).unwrap_or(hay.len()),
            );
        }
        let elapsed = start.elapsed().as_nanos();
        assert_eq!(
            checksum,
            expected.unwrap_or(hay.len()).wrapping_mul(iterations)
        );
        println!(
            "{label},{direction},{},{},{iterations},{elapsed},{checksum}",
            hay.len(),
            needle.len()
        );
    }
}

fn main() {
    println!("case,direction,hay_bytes,needle_bytes,iterations,elapsed_ns,checksum");
    for n in [65_536, 131_072, 262_144] {
        let hay = vec![b'a'; n];
        let mut needle = vec![b'a'; n / 16];
        needle[n / 32] = b'b';
        measure("near_miss", &hay, &needle, 20);
    }
    let prose = b"the quick brown fox jumps over the lazy dog. ".repeat(128);
    for needle in [b"brown".as_slice(), b"absent", b".", b""] {
        measure("prose", &prose, needle, 20_000);
    }
    let mut end = vec![b'a'; 8192];
    end.extend_from_slice(b"needle");
    measure("end_hit", &end, b"needle", 20_000);
}
