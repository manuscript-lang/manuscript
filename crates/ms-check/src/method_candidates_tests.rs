//! Frontend-only candidate selection regressions; never invoke the ownership wrapper.
use super::*;
use crate::CheckOptions;
use std::sync::Arc;

fn module(file: &str, source: &str) -> ModRef {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from(file);
    crate::load_module(
        syms,
        &ms_syntax::parser::parse(&file, source).expect("valid fixture"),
    )
}

#[test]
fn unrelated_methods_have_constant_size_candidate_buckets() {
    let template = include_str!("../tests/method_candidates/template.ms");
    for count in [128, 256, 512] {
        let source: String = (0..count)
            .map(|i| {
                template
                    .replace("R0", &format!("R{i}"))
                    .replace("get0", &format!("get{i}"))
            })
            .collect();
        let mut checker = Checker::new(&crate::Session::new(), &CheckOptions::default());
        checker.check_module(&module("candidates.ms", &source));
        assert!(
            checker.p.diagnostics.is_empty(),
            "{:?}",
            checker.p.diagnostics
        );
        assert_eq!(checker.p.methods.len(), count);
        assert_eq!(checker.methods_by_receiver.len(), count);
        assert_eq!(checker.methods_by_name.len(), count);
        assert!(checker.methods_by_receiver.values().all(|v| v.len() == 1));
        assert!(checker.methods_by_name.values().all(|v| v.len() == 1));
    }
}

#[test]
fn generic_receivers_bounds_and_operation_parameters() {
    let p = Checker::new(&crate::Session::new(), &CheckOptions::default()).check_modules(
        vec![module(
            "generics.ms",
            include_str!("../tests/method_candidates/generics.ms"),
        )],
        None,
    );
    assert!(p.diagnostics.is_empty(), "{:?}", p.diagnostics);
}

#[test]
fn generic_specialization_still_overlaps() {
    let p = Checker::new(&crate::Session::new(), &CheckOptions::default()).check_modules(
        vec![module(
            "overlap.ms",
            include_str!("../tests/method_candidates/overlap.ms"),
        )],
        None,
    );
    assert_eq!(p.diagnostics.len(), 1, "{:?}", p.diagnostics);
    assert!(
        p.diagnostics[0]
            .message
            .starts_with("duplicate or overlapping implementation")
    );
}

#[test]
fn receiver_methods_belong_to_the_declaring_module() {
    let p = Checker::new(&crate::Session::new(), &CheckOptions::default()).check_modules(
        vec![
            module(
                "owner.ms",
                include_str!("../tests/method_candidates/owner.ms"),
            ),
            module(
                "local.ms",
                include_str!("../tests/method_candidates/local.ms"),
            ),
        ],
        None,
    );
    assert!(
        p.diagnostics.iter().any(|d| d
            .message
            .starts_with("inherent methods belong in the module that declares Item")),
        "{:?}",
        p.diagnostics
    );
}

#[test]
fn interface_bounds_still_restrict_generic_candidates() {
    let p = Checker::new(&crate::Session::new(), &CheckOptions::default()).check_modules(
        vec![module(
            "restricted.ms",
            include_str!("../tests/method_candidates/restricted.ms"),
        )],
        None,
    );
    assert!(!p.diagnostics.is_empty());
    assert!(
        p.diagnostics
            .iter()
            .any(|d| d.message.starts_with("unknown or ambiguous member read")),
        "{:?}",
        p.diagnostics
    );
}

#[test]
fn invalid_receivers_do_not_register_methods() {
    let syms = ms_syntax::Names::global();
    let p = Checker::new(&crate::Session::new(), &CheckOptions::default()).check_modules(
        vec![module(
            "invalid.ms",
            include_str!("../tests/method_candidates/invalid.ms"),
        )],
        None,
    );
    assert!(
        p.diagnostics.iter().any(|d| d
            .message
            .starts_with("inherent methods belong in the module that declares")),
        "{:?}",
        p.diagnostics
    );
    assert!(p.methods.iter().all(|m| syms.str(m.module) != "invalid.ms"));
}

#[test]
fn merged_inherent_blocks_keep_duplicate_diagnostic() {
    let p = Checker::new(&crate::Session::new(), &CheckOptions::default()).check_modules(
        vec![module(
            "duplicates.ms",
            include_str!("../tests/method_candidates/duplicates.ms"),
        )],
        None,
    );
    assert!(
        p.diagnostics.iter().any(|d| d
            .message
            .starts_with("duplicate implementation operation read")),
        "{:?}",
        p.diagnostics
    );
}

#[test]
fn editor_queries_rebuild_candidate_indexes() {
    let syms = ms_syntax::Names::global();
    let p = Checker::new(&crate::Session::new(), &CheckOptions::default()).check_modules(
        vec![module(
            "editor.ms",
            include_str!("../tests/method_candidates/template.ms"),
        )],
        None,
    );
    assert!(p.diagnostics.is_empty(), "{:?}", p.diagnostics);
    let receiver = p.symbols[&n("editor.ms")].borrow()[&n("R0")]
        .ty
        .borrow()
        .clone()
        .unwrap();
    assert!(
        crate::editor::members(syms, &p, &receiver, Some(n("editor.ms")))
            .iter()
            .any(|m| syms.str(m.name) == "read")
    );
}

#[test]
fn unmet_list_element_bound_names_the_bound() {
    let p = Checker::new(&crate::Session::new(), &CheckOptions::default()).check_modules(
        vec![module(
            "bound.ms",
            "fn has[T](xs: List[T], x: T) Bool: xs.contains(x)\nexport fn main() Int: 0\n",
        )],
        None,
    );
    assert!(
        p.diagnostics.iter().any(|d| d
            .message
            .contains("contains requires T to be Equal; declare T: Equal")),
        "{:?}",
        p.diagnostics
    );
}

#[test]
fn self_referential_bound_is_not_an_arity_error() {
    let p = Checker::new(&crate::Session::new(), &CheckOptions::default()).check_modules(
        vec![module(
            "selfbound.ms",
            include_str!("../tests/method_candidates/selfbound.ms"),
        )],
        None,
    );
    assert!(
        p.diagnostics
            .iter()
            .all(|d| !d.message.contains("type arguments")),
        "{:?}",
        p.diagnostics
    );
    assert!(
        p.diagnostics
            .iter()
            .any(|d| d.message.starts_with("a bound must be an interface")),
        "{:?}",
        p.diagnostics
    );
}

#[test]
fn interface_parameter_inference_failure_is_one_clear_error() {
    let source = include_str!("../tests/method_candidates/iface_infer.ms");
    let p = Checker::new(&crate::Session::new(), &CheckOptions::default())
        .check_modules(vec![module("iface_infer.ms", source)], None);
    assert_eq!(p.diagnostics.len(), 1, "{:?}", p.diagnostics);
    assert!(
        p.diagnostics[0]
            .message
            .starts_with("cannot infer Get[T] from P[Int]"),
        "{:?}",
        p.diagnostics
    );
}

#[test]
fn generic_argument_conflict_is_reported_once() {
    let p = Checker::new(&crate::Session::new(), &CheckOptions::default()).check_modules(
        vec![module(
            "conflict.ms",
            include_str!("../tests/method_candidates/conflict.ms"),
        )],
        None,
    );
    assert_eq!(p.diagnostics.len(), 1, "{:?}", p.diagnostics);
    assert!(
        p.diagnostics[0]
            .message
            .starts_with("expected Int, found String (in argument 'b' of pair)"),
        "{:?}",
        p.diagnostics
    );
}

#[test]
fn source_method_chains_check_the_receiver_callback_once() {
    let template = include_str!("../tests/method_candidates/source_chain.ms");
    let session = crate::Session::new();
    let checked = |links| {
        let source = template.replace(
            "make(fn: 0)",
            &format!("make(fn: 0){}", ".next()".repeat(links)),
        );
        let program = Checker::new(&session, &CheckOptions::default())
            .check_modules(vec![module("source_chain.ms", &source)], None);
        assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
        program.serial
    };
    let baseline = checked(0);
    // A short chain exposes repeated callback checking before trying the large
    // control: the old fallback doubled that work for every source method.
    assert_eq!(checked(4), baseline);
    assert_eq!(checked(64), baseline);
}

#[test]
fn source_calls_keep_nested_member_scopes() {
    let input = module(
        "source_scope.ms",
        include_str!("../tests/method_candidates/source_scope.ms"),
    );
    let options = CheckOptions {
        scope_marker: Some("next".to_string()),
        ..CheckOptions::default()
    };
    let p = Checker::new(&crate::Session::new(), &options).check_modules(vec![input.clone()], None);
    assert!(p.diagnostics.is_empty(), "{:?}", p.diagnostics);
    let facts = input.facts();
    assert_eq!(facts.scopes.len(), 2);
    assert!(
        facts
            .scopes
            .values()
            .all(|scope| scope.bindings.contains_key(&n("seed")))
    );
    assert_eq!(
        facts
            .scopes
            .values()
            .filter(|scope| scope.bindings.contains_key(&n("nested")))
            .count(),
        1
    );
    for &id in facts.scopes.keys() {
        assert_eq!(
            facts.info(id).unwrap().method.as_ref().unwrap().name(),
            Some(n("next"))
        );
    }
}

#[test]
fn source_calls_keep_receiver_control_flow() {
    let input = module(
        "source_flow.ms",
        include_str!("../tests/method_candidates/source_flow.ms"),
    );
    let p = Checker::new(&crate::Session::new(), &CheckOptions::default())
        .check_modules(vec![input.clone()], None);
    assert!(p.diagnostics.is_empty(), "{:?}", p.diagnostics);
    let facts = input.facts();
    let members: Vec<_> = facts
        .exprs
        .iter()
        .flatten()
        .filter(|info| {
            info.method
                .as_ref()
                .is_some_and(|method| method.name() == Some(n("next")))
        })
        .collect();
    // Both the member callee and its call retain the receiver's control flow.
    assert_eq!(members.len(), 4);
    assert_eq!(members.iter().filter(|info| info.no_return).count(), 2);
    assert_eq!(members.iter().filter(|info| info.breaks).count(), 2);
}

#[test]
fn source_calls_keep_receiver_and_argument_diagnostics() {
    let p = Checker::new(&crate::Session::new(), &CheckOptions::default()).check_modules(
        vec![module(
            "source_errors.ms",
            include_str!("../tests/method_candidates/source_errors.ms"),
        )],
        None,
    );
    let got: Vec<_> = p
        .diagnostics
        .iter()
        .map(|d| (d.pos.line, d.pos.column, d.message.as_str()))
        .collect();
    assert_eq!(
        got,
        [
            (
                8,
                33,
                "expected Int, found String (in argument 'value' of make)"
            ),
            (
                10,
                41,
                "unknown argument mystery; parameters of next: amount"
            ),
            (
                12,
                44,
                "too many positional arguments; every parameter is already supplied, so remove this argument"
            ),
            (
                14,
                50,
                "type name requires a constructor call; write Int(field: value, ...) to build a value"
            ),
            (
                14,
                45,
                "indexing requires List[T], Map[K, V] or Bytes; use the receiver's lookup method for other types"
            ),
        ]
    );
}
