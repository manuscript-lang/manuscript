//! A reported fault in an argument must not also be blamed on the call.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn messages(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("follow.ms");
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
fn an_unknown_name_in_interpolation_is_the_only_error() {
    let found = messages(include_str!("follow_on_errors/interpolation.ms"));
    assert_eq!(found.len(), 1, "{found:?}");
    assert!(found[0].starts_with("unknown binding totl"), "{found:?}");
}

#[test]
fn a_mismatched_operator_in_an_argument_does_not_also_ask_for_type_arguments() {
    let found = messages("fn main() Int:\n    let n = 1\n    print(n + \"x\")\n    return 0\n");
    assert_eq!(found.len(), 1, "{found:?}");
    assert!(found[0].starts_with("operator operands"), "{found:?}");
}

#[test]
fn a_promise_used_as_its_payload_explains_what_wait_returns() {
    let found = messages(
        "import Promise, promise from \"@std/concurrency/promise.ms\"\n\nfn load() Promise[Int]:\n    return promise(fn: ok(1))\n\nfn f() Int:\n    return load()\n",
    );
    assert_eq!(found.len(), 1, "{found:?}");
    assert!(
        found[0].contains("wait() gives its result, Int!"),
        "{found:?}"
    );
}

#[test]
fn a_field_read_through_an_optional_or_result_names_the_unwrap() {
    let found = messages(
        "type P:\n    id: Int\n\nfn find() P?:\n    return none\n\nfn load() P!:\n    return ok(P(id: 1))\n\nfn main() Int:\n    let a = find()\n    let b = load()\n    return a.id + b.id\n",
    );
    assert_eq!(found.len(), 2, "{found:?}");
    assert!(
        found[0].contains("an Optional of P, which has id"),
        "{found:?}"
    );
    assert!(
        found[1].contains("a Result of P, which has id"),
        "{found:?}"
    );
}
