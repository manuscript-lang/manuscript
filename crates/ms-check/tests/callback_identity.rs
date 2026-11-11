//! Callback adaptation applies to callable values, never to nominal type arguments.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("callback_identity.ms");
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

#[test]
fn implementation_receivers_distinguish_callback_mutability() {
    let got = diagnostics(include_str!("callback_identity/distinct_receivers.ms"));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn implementation_methods_require_invariant_callback_arguments() {
    let got = diagnostics(include_str!("callback_identity/wrong_receiver.ms"));
    assert_eq!(
        got,
        ["unknown or ambiguous member read on Box[fn(Int) Int]; available: value"]
    );
}

#[test]
fn receiver_callbacks_remain_distinct_inside_parameters_and_results() {
    for (plain, changing) in [
        ("List[fn(Int) Int]", "List[fn(var Int) Int]"),
        ("fn(fn(Int) Int) Int", "fn(fn(var Int) Int) Int"),
        ("fn() fn(Int) Int", "fn() fn(var Int) Int"),
    ] {
        let source = format!(
            "interface Read:\n    fn read() Int\ntype Box[T]:\n    value: T\nfn Box[{changing}].read() Int: 1\nfn exercise(value: Box[{plain}]) Int: value.read()\n"
        );
        let got = diagnostics(&source);
        assert_eq!(got.len(), 1, "{source}: {got:?}");
        assert!(
            got[0].starts_with("unknown or ambiguous member read"),
            "{got:?}"
        );
    }
}

#[test]
fn generic_receiver_patterns_still_detect_overlapping_callbacks() {
    let source = "interface Read:\n    fn read() Int\ntype Box[T]:\n    value: T\nfn Box[fn(T) T].read() Int: 1\nfn Box[fn(Int) Int].read() Int: 2\n";
    let got = diagnostics(source);
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(
        got[0].starts_with("duplicate or overlapping implementation"),
        "{got:?}"
    );
}
