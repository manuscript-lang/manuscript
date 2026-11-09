//! A diagnostic points at the written type or expression at fault, and one mistake is one diagnostic.

use crate::{CheckOptions, checker::Checker};
use ms_syntax::Diagnostic;
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<Diagnostic> {
    let syms = ms_syntax::Names::global();
    let session = crate::Session::new();
    session.ensure_standard();
    let file: Arc<str> = Arc::from("diagnostic_cascade.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    Checker::new(&session, &CheckOptions::default())
        .check_modules(vec![crate::load_module(syms, &module)], None)
        .diagnostics
}

#[test]
fn bound_violation_in_a_signature_points_at_the_written_type() {
    let got = diagnostics(include_str!("../tests/diagnostic_cascade/map_bound.ms"));
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(got[0].message.starts_with("K does not satisfy Hashable"));
    assert_eq!((got[0].pos.line, got[0].pos.column), (1, 15), "{got:?}");
}

#[test]
fn bound_violation_in_fields_and_results_points_at_the_written_type() {
    let got = diagnostics(include_str!(
        "../tests/diagnostic_cascade/field_result_bound.ms"
    ));
    let at: Vec<(u32, u32)> = got.iter().map(|d| (d.pos.line, d.pos.column)).collect();
    assert!(at.contains(&(2, 12u32)), "{got:?}");
    assert!(at.contains(&(4, 18)), "{got:?}");
    assert!(!at.iter().any(|&(_, column)| column == 1), "{got:?}");
}

#[test]
fn an_argument_error_replaces_the_undetermined_type_argument_error() {
    let got = diagnostics(include_str!(
        "../tests/diagnostic_cascade/argument_error.ms"
    ));
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(got[0].message.starts_with("cannot infer list element type"));
}

#[test]
fn an_undetermined_type_argument_alone_is_still_reported() {
    let got = diagnostics(include_str!(
        "../tests/diagnostic_cascade/undetermined_alone.ms"
    ));
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(
        got[0]
            .message
            .starts_with("cannot infer type argument T for mk")
    );
}

#[test]
fn none_without_a_target_names_none() {
    let got = diagnostics(include_str!("../tests/diagnostic_cascade/none_target.ms"));
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(
        got[0].message.starts_with("cannot infer the type of none"),
        "{got:?}"
    );
}
