//! Interface defaults use the operation's resolved generic parameters.

use crate::{CheckOptions, checker::Checker};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    crate::stdlib::ensure_standard();
    let file: Arc<str> = Arc::from("generic_defaults.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    Checker::new(&CheckOptions::default())
        .check_modules(vec![crate::load_module(&module)], None)
        .diagnostics
        .into_iter()
        .map(|d| d.message)
        .collect()
}

#[test]
fn generic_interface_defaults_resolve_receiver_and_operation_parameters() {
    let got = diagnostics(include_str!("../tests/generic_defaults/accepted.ms"));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn generic_interface_defaults_still_reject_non_none_values() {
    let got = diagnostics(include_str!("../tests/generic_defaults/rejected.ms"));
    assert!(
        got.iter().any(|d| d.starts_with("expected T?, found Int")),
        "{got:?}"
    );
    assert!(
        got.iter()
            .any(|d| d.starts_with("interface defaults must be Optional.none")),
        "{got:?}"
    );
    assert!(
        !got.iter().any(|d| d.starts_with("unknown type")),
        "{got:?}"
    );
}

#[test]
fn operation_type_parameters_do_not_leak_into_other_defaults() {
    let got = diagnostics(include_str!("../tests/generic_defaults/unrelated.ms"));
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(got[0].starts_with("unknown type T"), "{got:?}");
}
