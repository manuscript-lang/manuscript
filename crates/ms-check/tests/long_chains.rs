//! A long left-nested arithmetic chain is checked in time linear in its length. Constant folding
//! and literal typing once re-walked the whole left subtree at every operator, so a 9000-term sum
//! took seconds; with per-node memoized facts it takes milliseconds.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("chain.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
    .diagnostics
    .into_iter()
    .map(|d| d.message)
    .collect()
}

fn chain(terms: usize, tail: &str) -> String {
    let sum = vec!["1"; terms].join(" + ");
    format!("export fn main() Int:\n    return {sum}{tail}\n")
}

#[test]
fn long_literal_sum_checks_quickly() {
    // The compiler runs on a large stack (ms-cli's COMPILER_STACK); a test thread's is too small.
    let (got, elapsed) = std::thread::Builder::new()
        .stack_size(256 << 20)
        .spawn(|| {
            let start = std::time::Instant::now();
            (diagnostics(&chain(9_000, "")), start.elapsed())
        })
        .unwrap()
        .join()
        .unwrap();
    assert!(got.is_empty(), "{got:?}");
    assert!(elapsed < std::time::Duration::from_secs(2), "{elapsed:?}");
}

#[test]
fn constant_overflow_is_still_found_at_the_end_of_a_chain() {
    let got = diagnostics(&chain(50, " + 9223372036854775807"));
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(got[0].contains("overflows Int"), "{got:?}");
}
