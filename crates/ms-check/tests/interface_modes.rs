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

const HEAD: &str = "interface Sink:\n    fn put(var xs: List[Int]) Unit\n\ntype A:\n    n: Int\n\nfn use_sink(s: Sink) Unit:\n    return\n\nfn run(a: A) Unit:\n    use_sink(a)\n\n";

#[test]
fn a_method_matching_the_interface_mode_is_accepted() {
    let got = diagnostics(&format!(
        "{HEAD}fn A.put(var xs: List[Int]) Unit:\n    xs.append(1)\n"
    ));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn a_method_that_drops_the_var_mode_is_rejected() {
    let got = diagnostics(&format!(
        "{HEAD}fn A.put(xs: List[Int]) Unit:\n    print(\"\")\n"
    ));
    assert!(
        got.iter().any(|d| d.contains("does not satisfy Sink")),
        "{got:?}"
    );
}

#[test]
fn a_method_that_adds_a_var_mode_is_rejected() {
    let got = diagnostics(
        "interface Sink:\n    fn put(xs: List[Int]) Unit\n\ntype A:\n    n: Int\n\nfn A.put(var xs: List[Int]) Unit:\n    xs.append(1)\n\nfn use_sink(s: Sink) Unit:\n    return\n\nfn run(a: A) Unit:\n    use_sink(a)\n",
    );
    assert!(
        got.iter().any(|d| d.contains("does not satisfy Sink")),
        "{got:?}"
    );
}
