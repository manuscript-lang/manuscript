//! Whole-wrapper native passthroughs must not duplicate a unique receiver.
use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("passthrough.ms");
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
fn unique_wrapper_can_transfer_but_source_identity_still_borrows() {
    let got = diagnostics(include_str!("wrapper_passthrough/accept-transfer.ms"));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn unique_receiver_cannot_be_kept_beside_passthrough_result() {
    for body in [
        include_str!("wrapper_passthrough/reject-result-reuse.ms"),
        include_str!("wrapper_passthrough/reject-optional-reuse.ms"),
        include_str!("wrapper_passthrough/reject-collection-lend.ms"),
    ] {
        let got = diagnostics(body);
        assert!(!got.is_empty(), "unique receiver accepted: {body}");
        assert!(
            got.iter()
                .any(|d| d.contains("cannot") || d.contains("would take")),
            "{got:?}"
        );
    }
}

#[test]
fn reusable_passthrough_requires_clonable_receiver() {
    for body in [
        include_str!("wrapper_passthrough/reject-bound-result.ms"),
        include_str!("wrapper_passthrough/reject-bound-temporary.ms"),
        include_str!("wrapper_passthrough/reject-bound-optional.ms"),
        include_str!("wrapper_passthrough/reject-bound-unbounded.ms"),
        include_str!("wrapper_passthrough/reject-bound-function.ms"),
    ] {
        let got = diagnostics(body);
        assert!(
            got.iter()
                .any(|d| d.contains("method value keeps its receiver") && d.contains("clone")),
            "{body}: {got:?}"
        );
    }
}

#[test]
fn clonable_bound_methods_keep_reusable_semantics() {
    let got = diagnostics(include_str!("wrapper_passthrough/accept-clonable-bound.ms"));
    assert!(got.is_empty(), "{got:?}");
}
