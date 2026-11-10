//! Call sites written for waiting calls become `.wait()` calls through the fixes of the diagnostics
//! a `Promise` used as its result produces (`ms check --fix`).

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn fixed(source: &str) -> String {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("t.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    let program = ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    let mut fixes: Vec<_> = program
        .diagnostics
        .iter()
        .filter_map(|d| d.fix.clone())
        .collect();
    fixes.sort_by_key(|f| std::cmp::Reverse(f.pos.offset));
    let mut text = source.to_string();
    for fix in fixes {
        text.replace_range(
            fix.pos.offset as usize..fix.end.offset as usize,
            &fix.replacement,
        );
    }
    text
}

const HEAD: &str = "import Promise, promise from \"@std/concurrency/promise.ms\"\n\nfn load() Promise[Int]:\n    return promise(fn: ok(1))\n\n";

#[test]
fn try_of_a_promise_waits() {
    let got = fixed(&format!(
        "{HEAD}fn f() Int!:\n    n := try load()\n    return ok(n)\n"
    ));
    assert!(got.contains("n := try load().wait()\n"), "{got}");
}

#[test]
fn a_promise_returned_as_its_result_waits() {
    let got = fixed(&format!("{HEAD}fn f() Int!:\n    return load()\n"));
    assert!(got.contains("return load().wait()\n"), "{got}");
}

#[test]
fn a_member_of_the_result_waits_first() {
    let got = fixed(&format!("{HEAD}fn f() Bool:\n    return load().is_ok()\n"));
    assert!(got.contains("return load().wait().is_ok()\n"), "{got}");
}

#[test]
fn a_bound_promise_waits_where_its_result_is_used() {
    let got = fixed(&format!(
        "{HEAD}fn f() Int!:\n    r := load()\n    n := try r\n    return ok(n)\n"
    ));
    assert!(got.contains("n := try r.wait()\n"), "{got}");
}

#[test]
fn a_promise_waited_already_is_unchanged() {
    let source = format!("{HEAD}fn f() Int!:\n    n := try load().wait()\n    return ok(n)\n");
    assert_eq!(fixed(&source), source);
}
