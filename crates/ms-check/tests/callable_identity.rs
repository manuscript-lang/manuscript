//! Function identity and generic inference depend on ordered types, not local names.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(body: &str) -> Vec<String> {
    let source = format!(
        "def first(amount: Int) -> Int: amount + 1\ndef second(value: Int) -> Int: value + 2\ndef choose[T](left: T, right: T) -> T: left\ntype Pair[T]:\n    left: T\n    right: T\ndef exercise() -> Unit:\n{body}\n"
    );
    let file: Arc<str> = Arc::from("identity.ms");
    let module = ms_syntax::parser::parse(&file, &source).expect("parses");
    ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
    .diagnostics
    .into_iter()
    .map(|d| d.message)
    .collect()
}

#[test]
fn generic_arguments_ignore_callable_parameter_names() {
    let got = diagnostics("    let selected = choose(first, second)\n    let answer = selected(3)");
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn inferred_collections_and_constructors_ignore_callable_parameter_names() {
    for body in [
        "    let callbacks = [first, second]\n    let answer = callbacks[1](3)",
        "    let callbacks = Pair(first, second)\n    let answer = callbacks.right(3)",
    ] {
        let got = diagnostics(body);
        assert!(got.is_empty(), "{body}: {got:?}");
    }
}

#[test]
fn callable_replacement_ignores_parameter_names() {
    let got = diagnostics(
        "    var callback = first\n    callback = second\n    let answer = callback(3)",
    );
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn callback_results_ignore_callable_parameter_names() {
    let got = diagnostics(
        "    let factory = lambda (flag: Bool):\n        if flag:\n            return first\n        return second\n    let answer = factory(False)(3)",
    );
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn callable_parameter_and_result_types_remain_invariant() {
    for body in [
        "    let bad = choose(first, lambda (value: String) -> Int: 1)",
        "    let bad = choose(first, lambda (value: Int) -> String: \"x\")",
        "    let bad = choose(first, lambda (value: Int, other: Int) -> Int: value)",
    ] {
        let got = diagnostics(body);
        assert!(
            got.iter()
                .any(|d| d.contains("expected Callable") || d.contains("callback mismatch")),
            "{body}: {got:?}"
        );
    }
}

#[test]
fn declared_call_labels_remain_checked() {
    assert!(diagnostics("    let answer = first(amount: 3)").is_empty());
    let got = diagnostics("    let answer = first(value: 3)");
    assert!(
        got.iter().any(|d| d.contains("unknown argument value")),
        "{got:?}"
    );
}
