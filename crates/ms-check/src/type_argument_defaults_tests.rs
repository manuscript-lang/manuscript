//! Default type arguments resolve in lexical scope against complete declarations.

use crate::{CheckOptions, checker::Checker};
use ms_syntax::Diagnostic;
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<Diagnostic> {
    crate::stdlib::ensure_standard();
    let file: Arc<str> = Arc::from("type_argument_defaults.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    Checker::new(&CheckOptions::default())
        .check_modules(vec![crate::load_module(&module)], None)
        .diagnostics
}

#[test]
fn method_type_defaults_preserve_receiver_parameters_and_self() {
    let got = diagnostics(include_str!("../tests/type_argument_defaults/receiver.ms"));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn type_defaults_see_later_local_implementations() {
    let got = diagnostics(include_str!(
        "../tests/type_argument_defaults/local_impl.ms"
    ));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn type_default_bounds_see_complete_record_fields_in_either_order() {
    for source in [
        include_str!("../tests/type_argument_defaults/invalid_fields.ms"),
        include_str!("../tests/type_argument_defaults/incomplete_fields.ms"),
    ] {
        let got = diagnostics(source);
        assert_eq!(got.len(), 4, "{got:?}");
        assert!(
            got.iter()
                .all(|d| d.message.starts_with("Callback does not satisfy Equal;")),
            "{got:?}"
        );
        assert_eq!(
            got[0].pos.line,
            if source.starts_with("type") { 4 } else { 1 }
        );
    }
}

#[test]
fn type_defaults_keep_self_forward_and_other_method_parameters_out_of_scope() {
    let got = diagnostics(include_str!("../tests/type_argument_defaults/isolation.ms"));
    assert_eq!(got.len(), 5, "{got:?}");
    for (diagnostic, name) in got.iter().zip(["B", "A", "C", "B", "B"]) {
        assert!(
            diagnostic
                .message
                .starts_with(&format!("unknown type {name};")),
            "{got:?}"
        );
    }
}

#[test]
fn type_defaults_validate_nested_applications_without_explicit_bounds() {
    let got = diagnostics(include_str!(
        "../tests/type_argument_defaults/nested_bounds.ms"
    ));
    assert_eq!(got.len(), 4, "{got:?}");
    assert!(
        got.iter()
            .all(|d| d.message.contains("does not satisfy Hashable;")),
        "{got:?}"
    );
}
