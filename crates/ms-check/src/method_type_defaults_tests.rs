//! Method type defaults complete inference and recorded specialization arguments.

use crate::{CheckOptions, checker::Checker};
use std::sync::Arc;

#[test]
fn method_defaults_fill_only_missing_type_arguments() {
    crate::stdlib::ensure_standard();
    let file: Arc<str> = Arc::from("method_type_defaults.ms");
    let source = include_str!("../tests/method_type_defaults/accepted.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    let module = crate::load_module(&module);
    let program = Checker::new(&CheckOptions::default()).check_modules(vec![module.clone()], None);
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    let facts = module.facts();
    let mut calls = Vec::new();
    for info in facts.exprs.iter().flatten() {
        let Some(method) = &info.method else { continue };
        let Some(name) = method.name() else { continue };
        if info.arguments.is_none()
            || !matches!(name.as_str(), "read" | "choose" | "fallback" | "output")
        {
            continue;
        }
        let args: Vec<_> = info
            .type_args
            .iter()
            .map(|t| t.as_ref().map(ToString::to_string))
            .collect();
        calls.push((name.to_string(), args));
    }
    calls.sort();
    assert_eq!(
        calls,
        vec![
            (
                "choose".to_string(),
                vec![Some("Int".to_string()), Some("Int".to_string())]
            ),
            (
                "choose".to_string(),
                vec![Some("Int".to_string()), Some("String".to_string())]
            ),
            ("fallback".to_string(), vec![Some("Int".to_string())]),
            ("output".to_string(), vec![Some("String".to_string())]),
            ("read".to_string(), vec![Some("Int".to_string())]),
            ("read".to_string(), vec![Some("Int".to_string())]),
            ("read".to_string(), vec![Some("String".to_string())]),
        ]
    );
}

#[test]
fn bound_method_partial_specialization_records_completed_arguments() {
    crate::stdlib::ensure_standard();
    let file: Arc<str> = Arc::from("bound_method_defaults.ms");
    let source = include_str!("../tests/method_type_defaults/bound.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    let module = crate::load_module(&module);
    let program = Checker::new(&CheckOptions::default()).check_modules(vec![module.clone()], None);
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    let facts = module.facts();
    let applications: Vec<_> = facts
        .exprs
        .iter()
        .flatten()
        .filter(|i| !i.type_args.is_empty())
        .collect();
    assert!(
        !applications.is_empty(),
        "bound specialization has no recorded type arguments"
    );
    for info in applications {
        let args: Vec<_> = info
            .type_args
            .iter()
            .map(|t| t.as_ref().map(ToString::to_string))
            .collect();
        assert_eq!(args, vec![Some("Int".to_string()), Some("Int".to_string())]);
    }
}

#[test]
fn method_type_defaults_reject_unsatisfied_bounds_and_forward_references() {
    for (source, expected) in [
        (
            include_str!("../tests/method_type_defaults/bad_bound.ms"),
            "does not satisfy Hashable",
        ),
        (
            include_str!("../tests/method_type_defaults/forward.ms"),
            "unknown type U",
        ),
    ] {
        crate::stdlib::ensure_standard();
        let file: Arc<str> = Arc::from("bad_method_defaults.ms");
        let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
        let program = Checker::new(&CheckOptions::default())
            .check_modules(vec![crate::load_module(&module)], None);
        assert!(
            program
                .diagnostics
                .iter()
                .any(|d| d.message.contains(expected)),
            "{:?}",
            program.diagnostics
        );
    }
}
