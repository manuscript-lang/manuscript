//! Return completeness counts only breaks whose branch can be reached.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("flow.ms");
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
fn nonreturning_conditions_cannot_reach_branch_breaks() {
    let got = diagnostics(include_str!("control_flow/unreachable_breaks.ms"));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn reachable_breaks_and_unreachable_type_errors_remain_checked() {
    let got = diagnostics(include_str!("control_flow/reachable_breaks.ms"));
    assert_eq!(got.len(), 6, "{got:?}");
    assert_eq!(
        got.iter()
            .filter(|d| d.contains("reachable fallthrough"))
            .count(),
        5,
        "{got:?}"
    );
    assert!(
        got.iter().any(|d| d.contains("unknown binding missing")),
        "{got:?}"
    );
}
