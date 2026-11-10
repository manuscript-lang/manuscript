//! Match arms are rejected when they repeat a value or name another instantiation.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    checked_diagnostics(source)
        .into_iter()
        .map(|d| d.message)
        .collect()
}

fn checked_diagnostics(source: &str) -> Vec<ms_syntax::Diagnostic> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("patterns.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
    .diagnostics
}

#[test]
fn negative_zero_repeats_zero() {
    for second in ["-0", "-0x0", "-0b0", "0x0"] {
        let source = format!(
            "fn classify(x: Int) Int:\n    match x:\n        0: return 1\n        {second}: return 2\n        _: return 3\n"
        );
        let got = diagnostics(&source);
        assert!(
            got.iter()
                .any(|m| m.starts_with("duplicate or unreachable pattern")),
            "{second}: {got:?}"
        );
    }
}

#[test]
fn negative_and_positive_values_stay_distinct() {
    let got = diagnostics(
        "fn classify(x: Int) Int:\n    match x:\n        1: return 1\n        -1: return 2\n        -0x1: return 3\n        _: return 4\n",
    );
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(
        got[0].starts_with("duplicate or unreachable pattern -1"),
        "{got:?}"
    );
}

const CHOICE: &str = "enum Choice[T, V]:\n    Value(value: T)\n    Missing\n";

#[test]
fn explicit_qualifier_must_be_the_matched_application() {
    for (params, scrutinee, qualifier, ok) in [
        ("[T, U]", "Choice[T, U]", "Choice[T, U]", true),
        ("[T, U]", "Choice[T, U]", "Choice", true),
        ("[T, U]", "Choice[T, U]", "Choice[U, T]", false),
        ("[T, U]", "Choice[T, T]", "Choice[U, U]", false),
        ("[T]", "Choice[Int, Int]", "Choice[T, T]", false),
    ] {
        let source = format!(
            "{CHOICE}fn classify{params}(x: {scrutinee}) Int:\n    match x:\n        {qualifier}.Value(_): return 1\n        {qualifier}.Missing: return 0\n"
        );
        let got = diagnostics(&source);
        assert_eq!(got.is_empty(), ok, "{qualifier} on {scrutinee}: {got:?}");
    }
}

#[test]
fn failed_chain_link_does_not_add_an_inference_error() {
    let got = diagnostics(
        "type R:\n    name: String\n\nfn use(o: R?) Int:\n    n := o?.name.length().get(0)\n    return n.get(0)\n",
    );
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(
        got[0].contains("unknown or ambiguous member get"),
        "{got:?}"
    );
}

#[test]
fn missing_arm_values_explain_the_required_type_at_the_arm() {
    for (source, line) in [
        (include_str!("match_patterns/annotated_arm_value.ms"), 3),
        (include_str!("match_patterns/inferred_arm_value.ms"), 4),
        (include_str!("match_patterns/returned_arm_value.ms"), 3),
    ] {
        let got = checked_diagnostics(source);
        assert_eq!(got.len(), 1, "{got:?}");
        assert_eq!(got[0].pos.line, line);
        assert_eq!(got[0].pos.column, 9);
        assert_eq!(
            got[0].message,
            "match arm requires a final value of type Int; this arm produces Unit; end the arm with a value of the required type"
        );
        // Apply the suggested repair to the offending arm, preserving its statements.
        let repaired = source.replace("_marker := 1", "_marker := 1\n\t\t\t_marker");
        assert!(diagnostics(&repaired).is_empty(), "{repaired}");
    }
}

#[test]
fn statement_unit_and_exiting_arms_keep_their_existing_rules() {
    let got = diagnostics(include_str!("match_patterns/arm_value_controls.ms"));
    assert!(got.is_empty(), "{got:?}");
}
