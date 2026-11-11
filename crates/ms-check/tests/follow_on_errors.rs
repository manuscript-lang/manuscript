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
    let found = messages(include_str!("follow_on_errors/operator_in_argument.ms"));
    assert_eq!(found.len(), 1, "{found:?}");
    assert!(found[0].starts_with("operator operands"), "{found:?}");
}

#[test]
fn a_promise_used_as_its_payload_explains_what_wait_returns() {
    let found = messages(include_str!("follow_on_errors/promise_payload.ms"));
    assert_eq!(found.len(), 1, "{found:?}");
    assert!(
        found[0].contains("wait() gives its result, Int!"),
        "{found:?}"
    );
}

#[test]
fn a_field_read_through_an_optional_or_result_names_the_unwrap() {
    let found = messages(include_str!("follow_on_errors/field_through_wrapper.ms"));
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

#[test]
fn an_import_from_the_wrong_standard_module_names_the_right_one() {
    let found = messages(include_str!("follow_on_errors/wrong_module_import.ms"));
    assert_eq!(found.len(), 1, "{found:?}");
    assert!(
        found[0].contains("replace this import with: import serve from \"@std/net/net.ms\""),
        "{found:?}"
    );
}

#[test]
fn any_fault_in_an_argument_is_the_only_error() {
    let found = messages(include_str!("follow_on_errors/failed_call_in_argument.ms"));
    assert_eq!(found.len(), 1, "{found:?}");
    assert!(found[0].starts_with("indexing a String"), "{found:?}");
}
