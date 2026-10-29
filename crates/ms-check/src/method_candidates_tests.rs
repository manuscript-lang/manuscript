//! Frontend-only candidate selection regressions; never invoke the ownership wrapper.
use super::*;
use crate::CheckOptions;
use std::sync::Arc;

fn module(file: &str, source: &str) -> ModRef {
    let file: Arc<str> = Arc::from(file);
    crate::load_module(&ms_syntax::parser::parse(&file, source).expect("valid fixture"))
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
        let mut checker = Checker::new(&CheckOptions::default());
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
    let p = Checker::new(&CheckOptions::default()).check_modules(
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
    let p = Checker::new(&CheckOptions::default()).check_modules(
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
fn ambiguity_preserves_declaration_order() {
    let source = include_str!("../tests/method_candidates/ambiguity.ms");
    let mut checker = Checker::new(&CheckOptions::default());
    checker.check_module(&module("ambiguity.ms", source));
    let receiver = checker.names.borrow()[&n("Item")]
        .ty
        .borrow()
        .clone()
        .unwrap();
    let methods = checker.implemented_methods(&receiver, n("read"));
    assert_eq!(
        methods
            .iter()
            .map(|m| m.contract.as_ref().unwrap().name)
            .collect::<Vec<_>>(),
        vec![n("Second"), n("First")]
    );
    assert_eq!(
        checker.p.diagnostics.len(),
        1,
        "{:?}",
        checker.p.diagnostics
    );
    assert!(checker.p.diagnostics[0].message.contains("ambiguous"));
}

#[test]
fn local_extensions_stay_local_and_owner_methods_travel() {
    let modules = vec![
        module(
            "owner.ms",
            include_str!("../tests/method_candidates/owner.ms"),
        ),
        module(
            "local.ms",
            include_str!("../tests/method_candidates/local.ms"),
        ),
        module(
            "other.ms",
            include_str!("../tests/method_candidates/other.ms"),
        ),
        module(
            "user.ms",
            include_str!("../tests/method_candidates/user.ms"),
        ),
    ];
    let mut checker = Checker::new(&CheckOptions::default());
    for m in &modules {
        for import in &m.imports {
            checker.imports.insert(m.file, import.id, n(&import.path));
        }
        checker.check_module(m);
        let receiver = checker.names.borrow()[&n("Item")]
            .ty
            .borrow()
            .clone()
            .unwrap();
        let read = checker.implemented_methods(&receiver, n("read"));
        if m.file == "local.ms" || m.file == "other.ms" {
            assert_eq!(read.len(), 1);
            assert_eq!(read[0].module, m.file);
        } else {
            assert!(read.is_empty());
        }
        assert_eq!(checker.implemented_methods(&receiver, n("owned")).len(), 1);
    }
    assert!(
        checker.p.diagnostics.is_empty(),
        "{:?}",
        checker.p.diagnostics
    );
}

#[test]
fn interface_bounds_still_restrict_generic_candidates() {
    let p = Checker::new(&CheckOptions::default()).check_modules(
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
    let p = Checker::new(&CheckOptions::default()).check_modules(
        vec![module(
            "invalid.ms",
            include_str!("../tests/method_candidates/invalid.ms"),
        )],
        None,
    );
    assert!(
        p.diagnostics.iter().any(|d| d
            .message
            .starts_with("implementation receiver must be nominal")),
        "{:?}",
        p.diagnostics
    );
    assert!(p.methods.iter().all(|m| m.module != "invalid.ms"));
}

#[test]
fn merged_inherent_blocks_keep_duplicate_diagnostic() {
    let p = Checker::new(&CheckOptions::default()).check_modules(
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
    let p = Checker::new(&CheckOptions::default()).check_modules(
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
        crate::editor::members(&p, &receiver, Some(n("editor.ms")))
            .iter()
            .any(|m| m.name == "read")
    );
}

#[test]
fn unmet_list_element_bound_names_the_bound() {
    let p = Checker::new(&CheckOptions::default()).check_modules(
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
