//! Match arms are rejected when they repeat a value or name another instantiation.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let file: Arc<str> = Arc::from("patterns.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
    .diagnostics
    .into_iter()
    .map(|d| d.message)
    .collect()
}

#[test]
fn negative_zero_repeats_zero() {
    for second in ["-0", "-0x0", "-0b0", "0x0"] {
        let source = format!(
            "def classify(x: Int) -> Int:\n    match x:\n        case 0: return 1\n        case {second}: return 2\n        case _: return 3\n"
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
        "def classify(x: Int) -> Int:\n    match x:\n        case 1: return 1\n        case -1: return 2\n        case -0x1: return 3\n        case _: return 4\n",
    );
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(
        got[0].starts_with("duplicate or unreachable pattern -1"),
        "{got:?}"
    );
}

const CHOICE: &str = "type Choice[T, V]:\n    case Value(value: T)\n    case Missing\n";

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
            "{CHOICE}def classify{params}(x: {scrutinee}) -> Int:\n    match x:\n        case {qualifier}.Value(_): return 1\n        case {qualifier}.Missing: return 0\n"
        );
        let got = diagnostics(&source);
        assert_eq!(got.is_empty(), ok, "{qualifier} on {scrutinee}: {got:?}");
    }
}
