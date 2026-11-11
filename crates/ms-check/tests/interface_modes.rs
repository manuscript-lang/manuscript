//! An implementation declares each parameter's `var` mode exactly as its interface does, so a
//! call through the interface changes (or lends) what the implementation changes (or lends).

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("modes.ms");
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

const HEAD: &str = "interface Sink:\n    fn put(var xs: List[Int]) Unit\n\ntype A:\n    n: Int\n\nimpl Sink for A:\n";

#[test]
fn an_implementation_matching_the_interface_mode_is_accepted() {
    let got = diagnostics(&format!(
        "{HEAD}    fn put(var xs: List[Int]) Unit:\n        xs.append(1)\n"
    ));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn an_implementation_that_drops_the_var_mode_is_rejected() {
    let got = diagnostics(&format!(
        "{HEAD}    fn put(xs: List[Int]) Unit:\n        print(\"\")\n"
    ));
    assert!(
        got.iter().any(|d| d.contains("does not match contract")),
        "{got:?}"
    );
}

#[test]
fn an_implementation_that_adds_a_var_mode_is_rejected() {
    let got = diagnostics(
        "interface Sink:\n    fn put(xs: List[Int]) Unit\n\ntype A:\n    n: Int\n\nimpl Sink for A:\n    fn put(var xs: List[Int]) Unit:\n        xs.append(1)\n",
    );
    assert!(
        got.iter().any(|d| d.contains("does not match contract")),
        "{got:?}"
    );
}
