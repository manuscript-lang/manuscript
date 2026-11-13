//! Default type arguments resolve in lexical scope against complete declarations.

use crate::{CheckOptions, checker::Checker};
use ms_syntax::Diagnostic;
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<Diagnostic> {
    let syms = ms_syntax::Names::global();
    let session = crate::Session::new();
    session.ensure_standard();
    let file: Arc<str> = Arc::from("type_argument_defaults.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    Checker::new(&session, &CheckOptions::default())
        .check_modules(vec![crate::load_module(syms, &module)], None)
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
fn type_default_bounds_see_complete_type_fields_in_either_order() {
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

#[test]
fn nontrailing_type_defaults_report_errors_without_panicking() {
    let got = diagnostics(include_str!(
        "../tests/type_argument_defaults/missing_trailing.ms"
    ));
    assert!(
        got.iter()
            .any(|d| d.message.starts_with("type parameter B needs a default")),
        "{got:?}"
    );
    assert_eq!(
        got.iter()
            .filter(|d| d.message.starts_with("Broken requires 2 type arguments"))
            .count(),
        2,
        "{got:?}"
    );
}

#[test]
fn invalid_trailing_type_defaults_report_errors_without_panicking() {
    let got = diagnostics(include_str!(
        "../tests/type_argument_defaults/invalid_trailing.ms"
    ));
    assert!(
        got.iter()
            .any(|d| d.message.starts_with("unknown type Missing;")),
        "{got:?}"
    );
    assert_eq!(
        got.iter()
            .filter(|d| d.message.starts_with("Broken requires 2 type arguments"))
            .count(),
        2,
        "{got:?}"
    );
}

#[test]
fn nontrailing_type_defaults_keep_type_and_function_application_diagnostics() {
    let got = diagnostics(include_str!(
        "../tests/type_argument_defaults/application_gap.ms"
    ));
    assert_eq!(
        got.iter()
            .filter(|d| d.message.starts_with("type parameter B needs a default"))
            .count(),
        2,
        "{got:?}"
    );
    assert!(
        got.iter()
            .any(|d| d.message.starts_with("generic type arity mismatch;")),
        "{got:?}"
    );
    assert!(
        got.iter()
            .any(|d| d.message.starts_with("generic arity mismatch;")),
        "{got:?}"
    );
}

#[test]
fn recovered_type_defaults_still_complete_a_fully_defaulted_suffix() {
    let got = diagnostics(include_str!(
        "../tests/type_argument_defaults/recovered_suffix.ms"
    ));
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(
        got[0]
            .message
            .starts_with("type parameter B needs a default"),
        "{got:?}"
    );
}

#[test]
fn required_type_arity_omits_only_a_fully_defaulted_suffix() {
    use crate::types::*;
    use std::rc::Rc;

    let syms = ms_syntax::Names::global();
    for len in 0..=6 {
        for mask in 0..1usize << len {
            let vars: Vec<Ty> = (0..len)
                .map(|index| {
                    let id = n(&format!("test/T{index}"));
                    let variable = Type::new(syms, id, id, Kind::Variable);
                    if mask & (1 << index) != 0 {
                        *variable.default.borrow_mut() = Some(int());
                    }
                    Rc::new(variable)
                })
                .collect();
            let expected = (0..len)
                .rfind(|index| mask & (1 << index) == 0)
                .map_or(0, |index| index + 1);
            assert_eq!(
                required_type_arguments(&vars),
                expected,
                "len {len}, mask {mask}"
            );
            for supplied in expected..=len {
                let args = vec![string(); supplied];
                let completed = with_default_arguments(&vars, &args);
                assert_eq!(completed.len(), len);
                assert!(completed[..supplied].iter().all(|t| same(t, &string())));
                assert!(completed[supplied..].iter().all(|t| same(t, &int())));
            }
        }
    }
}

#[test]
fn exported_generic_defaults_cannot_expose_private_types() {
    let got = diagnostics(include_str!(
        "../tests/type_argument_defaults/visibility.ms"
    ));
    assert_eq!(got.len(), 4, "{got:?}");
    assert_eq!(
        got.iter().map(|d| d.pos.line).collect::<Vec<_>>(),
        [7, 10, 13, 16]
    );
    assert!(
        got.iter().all(|d| d
            .message
            .starts_with("public signature exposes private type Secret;")),
        "{got:?}"
    );
}

#[test]
fn bounds_may_omit_defaulted_interface_arguments_in_either_order() {
    for source in [
        include_str!("../tests/type_argument_defaults/bound_before.ms"),
        include_str!("../tests/type_argument_defaults/bound_after.ms"),
    ] {
        let got = diagnostics(source);
        assert!(got.is_empty(), "{got:?}");
    }
}

#[test]
fn defaulted_bound_arguments_still_reject_mismatching_implementations() {
    let got = diagnostics(include_str!(
        "../tests/type_argument_defaults/bound_mismatch.ms"
    ));
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(got[0].message.contains("Named"), "{got:?}");
}

#[test]
fn defaults_naming_an_earlier_bounded_parameter_keep_its_bounds() {
    let got = diagnostics(include_str!(
        "../tests/type_argument_defaults/earlier_bounds.ms"
    ));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn defaults_naming_an_earlier_unbounded_parameter_are_still_rejected() {
    let got = diagnostics(include_str!(
        "../tests/type_argument_defaults/earlier_unbounded.ms"
    ));
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(
        got[0].message.contains("does not satisfy Hashable"),
        "{got:?}"
    );
}
