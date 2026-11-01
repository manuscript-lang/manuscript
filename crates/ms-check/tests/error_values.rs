//! Failure values need no reporting interface; inference and Error boundaries remain explicit.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let file: Arc<str> = Arc::from("errors.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
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
fn named_and_primitive_errors_need_no_interface() {
    let got = diagnostics(include_str!(
        "../../../tests/e2e/testdata/accept/result-error-values.ms"
    ));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn reportless_failures_do_not_widen_or_cross_unrelated_boundaries() {
    let got = diagnostics(include_str!(
        "../../../tests/e2e/testdata/reject/reportless-error-boundary.ms"
    ));
    assert!(
        got.iter()
            .any(|d| d.contains("expected Result[Int, Error], found Result[Int, DomainError]")),
        "{got:?}"
    );
    for returned in ["Error", "OtherError"] {
        assert!(
            got.iter().any(|d| {
                d.contains("try requires the same error type")
                    && d.contains(&format!("returns Result[Int, {returned}]"))
                    && d.contains("operand fails with DomainError")
            }),
            "{got:?}"
        );
    }
    assert!(
        got.iter().any(|d| d.contains("expected String, found Int")),
        "{got:?}"
    );
}

#[test]
fn context_free_string_error_still_needs_a_success_type() {
    let got = diagnostics(include_str!(
        "../../../tests/e2e/testdata/reject/uninferred-error-success.ms"
    ));
    assert!(
        got.iter()
            .any(|d| d.contains("cannot infer constructor type argument T")),
        "{got:?}"
    );
    assert!(
        got.iter().all(|d| !d.contains("implements Error")),
        "{got:?}"
    );
}
