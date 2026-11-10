//! Long inputs are checked in time linear in their size: left-nested arithmetic chains (constant
//! folding and literal typing once re-walked the whole left subtree at every operator, so a
//! 9000-term sum took seconds) and functions holding thousands of live borrows.

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

#[test]
fn many_live_borrows_check_quickly() {
    // N bindings borrow one owner and are all read afterwards. The ownership walk and the
    // liveness pass once visited every live borrow or place per access, so this took N^2 steps.
    let n = 8_000;
    let lets: String = (0..n).map(|i| format!("    b{i} := u.n\n")).collect();
    let reads: String = (0..n).map(|i| format!("    print(b{i})\n")).collect();
    let source = include_str!("long_chains/borrows.ms")
        .replace("// LETS\n", &lets)
        .replace("// READS\n", &reads);
    let start = std::time::Instant::now();
    let got = diagnostics(&source);
    assert!(got.is_empty(), "{got:?}");
    assert!(
        start.elapsed() < std::time::Duration::from_secs(2),
        "{:?}",
        start.elapsed()
    );
}
