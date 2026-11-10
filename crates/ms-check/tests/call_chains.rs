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
    let syms = ms_syntax::Names::global();
    // Each link used to spell the whole chain before it as text for a diagnostic that is almost
    // never reported: 1600 links took 1.7 s, 4800 about 15 s.
    let links = 4_800;
    let source = format!(
        "fn f() Int:\n    x := [1]{}\n    return x[0]\n",
        ".map(fn v: v + 1)".repeat(links)
    );
    let file: Arc<str> = Arc::from("chain.ms");
    let module = ms_syntax::parser::parse(&file, &source).expect("parses");
    let start = std::time::Instant::now();
    let result = ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(start.elapsed().as_secs() < 10, "took {:?}", start.elapsed());
    assert!(result.diagnostics.is_empty(), "{:?}", result.diagnostics);
}

#[test]
fn a_match_over_many_cases_checks_in_linear_time() {
    let syms = ms_syntax::Names::global();
    // Naming a case used to substitute the type arguments of every case of the alternative, so
    // each arm cost the number of cases: 4000 arms took 1.2 s and 16 000 about 20 s.
    let cases = 8_000;
    let mut source = String::from("enum E:\n");
    for i in 0..cases {
        source.push_str(&format!("    C{i}(x: Int)\n"));
    }
    source.push_str("\nfn g(e: E) Int:\n    match e:\n");
    for i in 0..cases {
        source.push_str(&format!("        C{i}(x): return x + {i}\n"));
    }
    let file: Arc<str> = Arc::from("cases.ms");
    let module = ms_syntax::parser::parse(&file, &source).expect("parses");
    let start = std::time::Instant::now();
    let result = ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(start.elapsed().as_secs() < 10, "took {:?}", start.elapsed());
    assert!(result.diagnostics.is_empty(), "{:?}", result.diagnostics);
}

#[test]
fn many_implementations_of_one_interface_check_in_linear_time() {
    let syms = ms_syntax::Names::global();
    // Finding the implementations of an interface for a type used to compare against every
    // implementation of it, in the checker and again at each conversion in the ownership
    // pass: 8000 types took 4.4 s and 16 000 about 18 s.
    let types = 16_000;
    let mut source = String::from("interface Shape:\n    fn area() Int\n\n");
    for i in 0..types {
        source.push_str(&format!(
            "type S{i}:\n    a: Int\n\nimpl Shape for S{i}:\n    fn area() Int: self.a + {i}\n\n"
        ));
    }
    source
        .push_str("fn total(s: Shape) Int:\n    return s.area()\n\nfn run() Int:\n    var t = 0\n");
    for i in 0..types {
        source.push_str(&format!("    t += total(S{i}(1))\n"));
    }
    source.push_str("    return t\n");
    let file: Arc<str> = Arc::from("shapes.ms");
    let module = ms_syntax::parser::parse(&file, &source).expect("parses");
    let start = std::time::Instant::now();
    let result = ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(start.elapsed().as_secs() < 8, "took {:?}", start.elapsed());
    assert!(result.diagnostics.is_empty(), "{:?}", result.diagnostics);
}

#[test]
fn many_assigned_locals_check_in_linear_time() {
    let syms = ms_syntax::Names::global();
    // The liveness pass kept an "assigned again" mark for every binding past its definition, so
    // each loop copied a set that grew with the function: 4000 loops took 1.6 s, 16 000 about 25 s.
    let loops = 16_000;
    let mut source = String::from("fn run() Int:\n    var s = 0\n");
    for i in 0..loops {
        source.push_str(&format!(
            "    var i{i} = 0\n    while i{i} < 3:\n        i{i} += 1\n        s += i{i}\n"
        ));
    }
    source.push_str("    return s\n");
    let file: Arc<str> = Arc::from("loops.ms");
    let module = ms_syntax::parser::parse(&file, &source).expect("parses");
    let start = std::time::Instant::now();
    let result = ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(start.elapsed().as_secs() < 8, "took {:?}", start.elapsed());
    assert!(result.diagnostics.is_empty(), "{:?}", result.diagnostics);
}
