//! Checking a long chain of method calls must cost time linear in the chain.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

#[test]
fn a_long_call_chain_checks_in_linear_time() {
    // The checker recurses along the chain; the compiler runs it on a large stack too.
    std::thread::Builder::new()
        .stack_size(1 << 30)
        .spawn(chain)
        .unwrap()
        .join()
        .unwrap();
}

fn chain() {
    // Each link used to spell the whole chain before it as text for a diagnostic that is almost
    // never reported: 1600 links took 1.7 s, 4800 about 15 s.
    let links = 4_800;
    let source = format!(
        "def f() -> Int:\n    let x = [1]{}\n    return x[0]\n",
        ".map(lambda v: v + 1)".repeat(links)
    );
    let file: Arc<str> = Arc::from("chain.ms");
    let module = ms_syntax::parser::parse(&file, &source).expect("parses");
    let start = std::time::Instant::now();
    let result = ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(start.elapsed().as_secs() < 10, "took {:?}", start.elapsed());
    assert!(result.diagnostics.is_empty(), "{:?}", result.diagnostics);
}

#[test]
fn a_match_over_many_cases_checks_in_linear_time() {
    // Naming a case used to substitute the type arguments of every case of the alternative, so
    // each arm cost the number of cases: 4000 arms took 1.2 s and 16 000 about 20 s.
    let cases = 8_000;
    let mut source = String::from("type E:\n");
    for i in 0..cases {
        source.push_str(&format!("    case C{i}(x: Int)\n"));
    }
    source.push_str("\ndef g(e: E) -> Int:\n    match e:\n");
    for i in 0..cases {
        source.push_str(&format!("        case C{i}(x): return x + {i}\n"));
    }
    let file: Arc<str> = Arc::from("cases.ms");
    let module = ms_syntax::parser::parse(&file, &source).expect("parses");
    let start = std::time::Instant::now();
    let result = ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(start.elapsed().as_secs() < 10, "took {:?}", start.elapsed());
    assert!(result.diagnostics.is_empty(), "{:?}", result.diagnostics);
}
