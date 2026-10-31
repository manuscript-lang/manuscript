//! Generic operations reject non-interface bounds just like named functions.

use crate::{CheckOptions, Program, checker::Checker, types::n};
use std::sync::Arc;

fn check(source: &str) -> Program {
    crate::stdlib::ensure_standard();
    let file: Arc<str> = Arc::from("operation_bounds.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    Checker::new(&CheckOptions::default()).check_modules(vec![crate::load_module(&module)], None)
}

fn diagnostics(source: &str) -> Vec<String> {
    check(source)
        .diagnostics
        .into_iter()
        .map(|d| d.message)
        .collect()
}

#[test]
fn operations_reject_non_interface_bounds() {
    for source in [
        include_str!("../tests/operation_bounds/interface.ms"),
        include_str!("../tests/operation_bounds/implementation.ms"),
        include_str!("../tests/operation_bounds/inherent.ms"),
    ] {
        let got = diagnostics(source);
        assert!(!got.is_empty(), "accepted non-interface bound: {source}");
        assert!(
            got.iter()
                .all(|d| d.starts_with("a bound must be an interface")),
            "{got:?}"
        );
    }
}

#[test]
fn operations_reject_type_variable_bounds_without_recording_them() {
    let program = check(include_str!("../tests/operation_bounds/variable.ms"));
    assert_eq!(program.diagnostics.len(), 1, "{:?}", program.diagnostics);
    assert!(
        program.diagnostics[0]
            .message
            .contains("resolves to a type parameter")
    );
    let reader = program.symbols[&n("operation_bounds.ms")].borrow()[&n("Reader")].ty();
    let variables = crate::stdlib::operation_variables(&format!("{}/read", reader.id));
    assert_eq!(variables.len(), 1);
    assert!(variables[0].bounds().is_empty());
}

#[test]
fn operations_keep_recursive_and_receiver_dependent_interface_bounds() {
    let got = diagnostics(include_str!("../tests/operation_bounds/valid.ms"));
    assert!(got.is_empty(), "{got:?}");
}
