extern crate alloc;
#[allow(dead_code)]
#[path = "../../../crates/ms-std-url/src/parser.rs"]
mod parser;

use std::{hint::black_box, time::Instant};

fn main() {
    let args: Vec<_> = std::env::args().collect();
    let count: usize = args[1].parse().expect("parent count");
    let repeats: usize = args[2].parse().expect("repetitions");
    let mode = args[3].as_str();
    let (base, reference, expected) = match mode {
        "parents" => (
            format!("/{}leaf", "segment/".repeat(count)),
            "../".repeat(count),
            if count == 0 { "/leaf" } else { "/" },
        ),
        "plain" => ("/a/b/leaf".into(), "next/item".into(), "/a/b/next/item"),
        "normal" => ("/a/b/leaf".into(), "./next/item".into(), "/a/b/next/item"),
        _ => panic!("expected parents, plain or normal"),
    };
    let start = Instant::now();
    let mut checksum = 0;
    for _ in 0..repeats {
        let output =
            parser::resolve_path(black_box(base.as_bytes()), black_box(reference.as_bytes()));
        assert_eq!(output, expected.as_bytes());
        checksum += output.len();
    }
    println!("{} {}", start.elapsed().as_nanos(), black_box(checksum));
}
