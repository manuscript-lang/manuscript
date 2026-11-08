//! `MSL116`: a function reaches an effect no `// ms: allow_effect` line permits.

use ms_check::{CheckOptions, ImportMap};
use ms_tooling::lint::lint_program;
use std::sync::Arc;

/// The functions reported, by the name quoted at the start of each message.
fn flagged(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("lint.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    let program = ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    let mut names: Vec<String> = lint_program(syms, &program)
        .into_iter()
        .filter(|f| f.code == "MSL116")
        .map(|f| f.message.split('`').nth(1).unwrap_or_default().to_string())
        .collect();
    names.dedup();
    names
}

#[test]
fn function_values_and_closure_literals_are_charged() {
    let got = flagged(include_str!("lint_effects/value_refs.ms"));
    assert_eq!(got, vec!["shout", "report", "closure_prints"]);
}

#[test]
fn a_bound_method_value_is_charged_where_it_is_named() {
    let got = flagged(include_str!("lint_effects/method_value.ms"));
    assert_eq!(got, vec!["Logger.info", "stored_method"]);
}

#[test]
fn converting_to_an_interface_charges_the_converter_not_main() {
    let got = flagged(include_str!("lint_effects/capability.ms"));
    assert_eq!(got, vec!["ConsoleLogger.info", "wire"]);
}

#[test]
fn declared_effects_hide_the_body_and_allow_lines_scope_reach() {
    let got = flagged(include_str!("lint_effects/custom.ms"));
    assert_eq!(got, vec!["bad", "leaky"]);
}

#[test]
fn cycles_terminate_and_report_every_member() {
    let got = flagged(include_str!("lint_effects/cycle.ms"));
    assert_eq!(got, vec!["a", "b"]);
}

#[test]
fn a_function_line_only_tightens_the_file_header() {
    let got = flagged(include_str!("lint_effects/tighten.ms"));
    assert_eq!(got, vec!["narrow"]);
}

#[test]
fn last_segment_patterns_permit_reads_only() {
    let got = flagged(include_str!("lint_effects/patterns.ms"));
    assert_eq!(got, vec!["w"]);
}

#[test]
fn generic_calls_charge_the_concrete_type_argument() {
    let got = flagged(include_str!("lint_effects/generic.ms"));
    assert_eq!(got, vec!["Out.put", "caller"]);
}
