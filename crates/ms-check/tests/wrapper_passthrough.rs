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

#[test]
fn preserved_payload_transfer_and_transform_controls() {
    let got = diagnostics(include_str!(
        "wrapper_passthrough/accept-preserved-transfers.ms"
    ));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn preserved_payloads_cannot_be_duplicated() {
    for body in [
        include_str!("wrapper_passthrough/reject-ok-or-preserved-reuse.ms"),
        include_str!("wrapper_passthrough/reject-ok-or-else-preserved-reuse.ms"),
        include_str!("wrapper_passthrough/reject-map-error-preserved-reuse.ms"),
        include_str!("wrapper_passthrough/reject-to-optional-preserved-reuse.ms"),
        include_str!("wrapper_passthrough/reject-map-preserved-reuse.ms"),
        include_str!("wrapper_passthrough/reject-and-then-preserved-reuse.ms"),
        include_str!("wrapper_passthrough/reject-ok-or-zero-collection.ms"),
        include_str!("wrapper_passthrough/reject-to-optional-zero-collection.ms"),
    ] {
        let got = diagnostics(body);
        assert!(
            got.iter()
                .any(|d| d.contains("cannot") || d.contains("would take")),
            "{body}: {got:?}"
        );
    }
}

#[test]
fn preserved_bound_payloads_require_clonable() {
    for body in [
        include_str!("wrapper_passthrough/reject-ok-or-bound-resource.ms"),
        include_str!("wrapper_passthrough/reject-ok-or-else-bound-resource.ms"),
        include_str!("wrapper_passthrough/reject-map-error-bound-resource.ms"),
        include_str!("wrapper_passthrough/reject-to-optional-bound-resource.ms"),
        include_str!("wrapper_passthrough/reject-map-bound-resource.ms"),
        include_str!("wrapper_passthrough/reject-and-then-bound-resource.ms"),
        include_str!("wrapper_passthrough/reject-bound-preserved-generic.ms"),
        include_str!("wrapper_passthrough/reject-bound-error-generic.ms"),
        include_str!("wrapper_passthrough/reject-bound-preserved-function.ms"),
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
fn specialized_source_receivers_preserve_borrow_and_overlap_checks() {
    for (source, expected) in [
        (
            include_str!("wrapper_passthrough/reject-specialized-source-borrow.ms"),
            "while `view` borrows it",
        ),
        (
            include_str!("wrapper_passthrough/reject-specialized-source-overlap.ms"),
            "overlaps argument",
        ),
    ] {
        let got = diagnostics(source);
        assert!(
            got.iter().any(|d| d.contains(expected)),
            "{source}: {got:?}"
        );
    }
}
