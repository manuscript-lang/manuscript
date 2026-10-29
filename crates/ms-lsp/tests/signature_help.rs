//! Signature help follows original argument boundaries and invocation slots.

use ms_lsp::analysis::{Document, Documents, analyze};
use ms_lsp::completion::signature_help;
use ms_lsp::text;
use ms_rt as _;

mod support;
use support::Workspace;

const SOURCE: &str = include_str!("signature_help/boundaries.ms");

fn check(expression: &str, expected_name: &str, expected: usize, valid: bool) {
    let offset = expression.find('|').expect("cursor");
    let expression = expression.replacen('|', "", 1);
    for newline in ["\n", "\r\n"] {
        let ws = Workspace::new("signature-help");
        let source = SOURCE.replace("combine(1, 2)", &expression);
        let cursor = source.rfind(&expression).expect("call") + offset;
        let cursor = source[..cursor].replace('\n', newline).len();
        let source = source.replace('\n', newline);
        let d = Document::new(ws.uri("signature.ms"), source.clone());
        if valid {
            let checked = analyze(&d, &Documents::new());
            assert!(
                checked.diagnostics.is_empty(),
                "{expression}: {:?}",
                checked.diagnostics
            );
            assert!(checked.program.is_some());
        }
        let help = signature_help(&d, &Documents::new(), text::position(&source, cursor))
            .expect("signature help");
        assert_eq!(
            help.get("activeParameter").and_then(|j| j.as_i64()),
            Some(expected as i64),
            "{expression:?} at {offset}, newline {newline:?}: {help:?}"
        );
        let label = help.get("signatures").and_then(|j| j.as_array()).unwrap()[0]
            .get("label")
            .and_then(|j| j.as_str())
            .unwrap();
        assert!(label.starts_with(expected_name), "{label}");
        assert_eq!(
            d.text, source,
            "private snapshot must not edit the document"
        );
    }
}

#[test]
fn positional_operand_comma_and_closing_boundaries() {
    for (expression, active) in [
        ("combine(|1, 2)", 0),
        ("combine(1|, 2)", 0),
        ("combine(1,| 2)", 1),
        ("combine(1, |2)", 1),
        ("combine(1, 2|)", 1),
        ("combine(|123, 456)", 0),
        ("combine(12|3, 456)", 0),
        ("combine(123, 45|6)", 1),
        ("combine(|right, left)", 0),
        ("combine(right, le|ft)", 1),
    ] {
        check(expression, "combine(", active, true);
    }
}

#[test]
fn explicit_labels_mixed_slots_and_defaults() {
    for (expression, name, active) in [
        ("combine(|right: 2, left: 1)", "combine(", 1),
        ("combine(right|: 2, left: 1)", "combine(", 1),
        ("combine(right:| 2, left: 1)", "combine(", 1),
        ("combine(right: 2,| left: 1)", "combine(", 0),
        ("combine(right: 2, 1|)", "combine(", 0),
        ("combine(|1, right: 2)", "combine(", 0),
        ("defaults(|)", "defaults(", 0),
        ("defaults(|2)", "defaults(", 0),
        ("defaults(right: 2|)", "defaults(", 1),
    ] {
        check(expression, name, active, true);
    }
}

#[test]
fn methods_constructors_generics_and_nested_delimiters() {
    for (expression, name, active) in [
        ("pair.combine(1,| 2)", "pair.combine(", 1),
        ("Pair(1, 2|).left", "Pair(", 1),
        ("Pair(right: 2,| 1).left", "Pair(", 0),
        ("first[Int](1,| 2)", "first[Int](", 1),
        ("callback(1,| 2)", "callback(", 1),
        ("combine(combine(1,| 2), 3)", "combine(", 1),
        ("combine(combine(1, 2),| 3)", "combine(", 1),
        ("combine((1 + 2), |3)", "combine(", 1),
        (
            "collections([1, 2],| {\"x\": 1, \"y\": 2})",
            "collections(",
            1,
        ),
        (
            "collections([1, 2], {\"😀,):\": 1, \"é\": 2}|)",
            "collections(",
            1,
        ),
        ("combine(\"😀\".length(),| 2)", "combine(", 1),
        ("combine(\"{combine(1,| 2)}\".length(), 3)", "combine(", 1),
        (
            "combine(\n        1, # ignored ,):\n        |2\n    )",
            "combine(",
            1,
        ),
        ("invoke(fn a,| b: a + b, 1)", "invoke(", 0),
        ("invoke(fn a, b: a + b,| 1)", "invoke(", 1),
        ("invoke_empty(fn: 1,| 2)", "invoke_empty(", 1),
        ("invoke_empty(fn: 1, 2|)", "invoke_empty(", 1),
        ("invoke_empty(callback: fn: 1,| 2)", "invoke_empty(", 1),
        ("invoke(fn(a: Int, b: Int) Int: a + b,| 1)", "invoke(", 1),
    ] {
        check(expression, name, active, true);
    }
}

#[test]
fn incomplete_calls_keep_the_current_slot() {
    for (expression, active) in [
        ("combine(|", 0),
        ("combine(1,|", 1),
        ("combine(1, |", 1),
        ("combine(right: 2, |", 0),
        ("combine(ri|", 0),
        ("combine(right:|", 1),
        ("combine(1,|)", 1),
        (
            "combine(1,|\n\nfn neighbor() Int:\n    return combine(3, 4)",
            1,
        ),
    ] {
        check(expression, "combine(", active, false);
    }
}

#[test]
fn signature_help_stays_suppressed_outside_calls_and_in_literals_or_comments() {
    for expression in [
        "combine(1, 2)|",
        "collections([], {\"tex|t\": 2})",
        "combine(1, 2) # com|ment",
    ] {
        let offset = expression.find('|').unwrap();
        let expression = expression.replace('|', "");
        let ws = Workspace::new("signature-suppression");
        let source = SOURCE.replace("combine(1, 2)", &expression);
        let cursor = source.rfind(&expression).unwrap() + offset;
        let d = Document::new(ws.uri("signature.ms"), source.clone());
        assert!(
            signature_help(&d, &Documents::new(), text::position(&source, cursor))
                .unwrap()
                .is_null()
        );
    }
}
