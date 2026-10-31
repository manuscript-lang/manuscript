//! Compiler implementation benchmark; not a generated Manuscript/Rust comparison.
use ms_syntax::{dump::dump_module, lexer::lex, parser::parse};
use std::{
    hint::black_box,
    sync::Arc,
    time::{Duration, Instant},
};

fn main() {
    std::thread::Builder::new()
        .stack_size(64 << 20)
        .spawn(run)
        .unwrap()
        .join()
        .unwrap();
}

fn run() {
    let mut args = std::env::args().skip(1);
    let mode = args.next().expect("parse, lex, or validate");
    let sources: Vec<_> = args
        .map(|path| {
            let text = std::fs::read_to_string(&path).unwrap();
            (Arc::<str>::from(path), text)
        })
        .collect();
    assert!(!sources.is_empty());
    let mut expected = 0u64;
    for (file, text) in &sources {
        let module = parse(file, text).unwrap();
        if mode == "validate" {
            println!("{:?}\n{}", module, dump_module(&module));
        }
        expected += if mode == "lex" {
            lex(file, text).unwrap().tokens.len() as u64
        } else {
            u64::from(module.node_count)
        };
    }
    if mode == "validate" {
        return;
    }
    assert!(mode == "parse" || mode == "lex");
    let pass = || {
        let mut count = 0u64;
        for (file, text) in &sources {
            if mode == "parse" {
                count += u64::from(
                    black_box(parse(black_box(file), black_box(text)).unwrap()).node_count,
                );
            } else {
                count += black_box(lex(black_box(file), black_box(text)).unwrap())
                    .tokens
                    .len() as u64;
            }
        }
        assert_eq!(count, expected);
        black_box(count)
    };
    for _ in 0..3 {
        pass();
    }
    let mut passes = 0u64;
    let mut checksum = 0u64;
    let start = Instant::now();
    loop {
        for _ in 0..16 {
            checksum = checksum.wrapping_add(pass());
            passes += 1;
        }
        if start.elapsed() >= Duration::from_millis(100) {
            break;
        }
    }
    let ns = start.elapsed().as_nanos();
    assert_eq!(checksum, expected * passes);
    println!(
        "{{\"elapsed_ns\":{ns},\"passes\":{passes},\"units\":{expected},\"checksum\":{checksum}}}"
    );
}
