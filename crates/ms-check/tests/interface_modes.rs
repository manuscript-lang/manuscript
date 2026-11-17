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

const HEAD: &str = "interface Sink:\n    fn put(var xs: List[Int]) Void\n\ntype A:\n    n: Int\n\nfn use_sink(s: Sink) Void:\n    return\n\nfn run(a: A) Void:\n    use_sink(a)\n\n";

#[test]
fn a_method_matching_the_interface_mode_is_accepted() {
    let got = diagnostics(&format!(
        "{HEAD}fn A.put(var xs: List[Int]) Void:\n    xs.append(1)\n"
    ));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn a_method_that_drops_the_var_mode_is_rejected() {
    let got = diagnostics(&format!(
        "{HEAD}fn A.put(xs: List[Int]) Void:\n    print(\"\")\n"
    ));
    assert!(
        got.iter().any(|d| d.contains("does not satisfy Sink")),
        "{got:?}"
    );
}

#[test]
fn a_method_that_adds_a_var_mode_is_rejected() {
    let got = diagnostics(
        "interface Sink:\n    fn put(xs: List[Int]) Void\n\ntype A:\n    n: Int\n\nfn A.put(var xs: List[Int]) Void:\n    xs.append(1)\n\nfn use_sink(s: Sink) Void:\n    return\n\nfn run(a: A) Void:\n    use_sink(a)\n",
    );
    assert!(
        got.iter().any(|d| d.contains("does not satisfy Sink")),
        "{got:?}"
    );
}

const MOVE_HEAD: &str = "type Item:\n    name: String\n\ninterface Sink:\n    fn put(move item: Item) Int\n\ntype A:\n    n: Int\n\nfn use_sink(s: Sink) Void:\n    return\n\nfn run(a: A) Void:\n    use_sink(a)\n\n";

#[test]
fn a_method_matching_the_interface_move_is_accepted() {
    let got = diagnostics(&format!(
        "{MOVE_HEAD}fn A.put(move item: Item) Int:\n    return item.name.length()\n"
    ));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn a_method_that_drops_the_move_mode_is_rejected() {
    let got = diagnostics(&format!(
        "{MOVE_HEAD}fn A.put(item: Item) Int:\n    return item.name.length()\n"
    ));
    assert!(
        got.iter().any(|d| d.contains("does not satisfy Sink")),
        "{got:?}"
    );
}

#[test]
fn a_method_that_adds_a_move_mode_is_rejected() {
    let got = diagnostics(
        "type Item:\n    name: String\n\ninterface Sink:\n    fn put(item: Item) Int\n\ntype A:\n    n: Int\n\nfn A.put(move item: Item) Int:\n    return item.name.length()\n\nfn use_sink(s: Sink) Void:\n    return\n\nfn run(a: A) Void:\n    use_sink(a)\n",
    );
    assert!(
        got.iter().any(|d| d.contains("does not satisfy Sink")),
        "{got:?}"
    );
}

#[test]
fn a_method_that_consumes_its_receiver_matches_only_a_move_operation() {
    let got = diagnostics(
        "interface Done:\n    move fn finish() Int\n\ntype A:\n    n: Int\n\nfn A.finish() Int:\n    return self.n\n\nfn use_done(d: Done) Void:\n    return\n\nfn run(a: A) Void:\n    use_done(a)\n",
    );
    assert!(
        got.iter()
            .any(|d| d.contains("must take its receiver with `move`")),
        "{got:?}"
    );
}

#[test]
fn one_method_meets_two_interfaces_only_when_their_move_markers_agree() {
    let head = "type Item:\n    name: String\n\ninterface Keep:\n    fn put(move item: Item) Int\n\ninterface Read:\n    fn put(item: Item) Int\n\ntype A:\n    n: Int\n\nfn A.put(move item: Item) Int:\n    return item.name.length()\n\nfn keep(k: Keep) Void:\n    return\n\nfn read(r: Read) Void:\n    return\n\n";
    let got = diagnostics(&format!("{head}fn run(a: A) Void:\n    keep(a)\n"));
    assert!(got.is_empty(), "{got:?}");
    let got = diagnostics(&format!("{head}fn run(a: A) Void:\n    read(a)\n"));
    assert!(
        got.iter().any(|d| d.contains("does not satisfy Read")),
        "{got:?}"
    );
}
