//! `MSL113`: `some(x)` where a plain `x` is wrapped to the same Optional.

use ms_check::{CheckOptions, ImportMap};
use ms_tooling::lint::{Finding, lint_program};
use std::sync::Arc;

fn findings(source: &str) -> Vec<Finding> {
    let file: Arc<str> = Arc::from("lint.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    let program = ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    lint_program(&program)
        .into_iter()
        .filter(|f| f.code == "MSL113")
        .collect()
}

#[test]
fn wrapped_values_are_reported_with_a_fix() {
    let source = include_str!("lint_redundant_some/wrapped.ms");
    let found = findings(source);
    assert_eq!(found.len(), 4);
    let fix = found[1].fix.as_ref().expect("fix");
    assert_eq!(fix.replacement, "x.get(0) + 1");
}

#[test]
fn needed_somes_are_kept() {
    let source = include_str!("lint_redundant_some/kept.ms");
    let found = findings(source);
    // Only the inner `some(1)`: `some(none)` and the outer wrapper change the value.
    assert_eq!(found.len(), 1);
}
