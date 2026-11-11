//! Sub-codes name the cause within a rule family: stable, unique, and found in real diagnostics.

use ms_syntax::diag::{KINDS, code_for, explain, kind_for};
use std::collections::HashSet;

/// The (phase, message) pairs of every diagnostic recorded in the conformance corpus.
fn corpus() -> Vec<(String, String)> {
    fn walk(dir: &std::path::Path, out: &mut Vec<(String, String)>) {
        let mut entries: Vec<_> = std::fs::read_dir(dir).unwrap().flatten().collect();
        entries.sort_by_key(|e| e.path());
        for entry in entries {
            let path = entry.path();
            if path.is_dir() {
                walk(&path, out);
            } else if path.to_string_lossy().ends_with(".json") {
                let text = std::fs::read_to_string(&path).unwrap_or_default();
                let mut phase = String::new();
                for line in text.lines().map(str::trim) {
                    if let Some(v) = line.strip_prefix("\"phase\": \"") {
                        phase = v.trim_end_matches(&['"', ','][..]).to_string();
                    } else if let Some(v) = line.strip_prefix("\"message\": \"")
                        && matches!(phase.as_str(), "parse" | "resolution" | "type" | "lowering")
                    {
                        let message = v.trim_end_matches(&['"', ','][..]);
                        let message = message.replace("\\\"", "\"").replace("\\\\", "\\");
                        out.push((phase.clone(), message));
                    }
                }
            }
        }
    }
    let root = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../tests/conformance/fixtures"
    );
    let mut out = Vec::new();
    walk(std::path::Path::new(root), &mut out);
    out
}

#[test]
fn sub_codes_are_unique_and_extend_a_family_code() {
    let mut seen = HashSet::new();
    for kind in KINDS {
        assert!(seen.insert(kind.info.code), "duplicate {}", kind.info.code);
        assert!(
            kind.info.code.starts_with(&format!("{}.", kind.family)),
            "{} is not under {}",
            kind.info.code,
            kind.family
        );
        assert!(
            explain(kind.family).is_some(),
            "{} has no family",
            kind.family
        );
        let found = explain(kind.info.code).expect("explain finds sub-codes");
        assert_eq!(found.code, kind.info.code);
        assert!(!kind.needle.is_empty());
    }
}

#[test]
fn every_sub_code_is_reached_by_a_real_diagnostic() {
    let mut reached = HashSet::new();
    for (phase, message) in corpus() {
        if let Some(kind) = kind_for(code_for(&phase, &message), &message) {
            reached.insert(kind.info.code);
        }
    }
    // Causes the conformance corpus does not exercise: message text taken from the checker.
    for (phase, message, expected) in [
        (
            "type",
            "`f` is a resource that is never closed: call `f.close()`, or return it so the caller owns it",
            "MS3000.10",
        ),
        (
            "type",
            "cannot move `x` out of `y`: only a whole variable can move",
            "MS3000.11",
        ),
        ("type", "Int does not satisfy Show", "MS3000.8"),
        (
            "type",
            "Show is an interface and cannot be constructed; pass a value that implements it",
            "MS3000.9",
        ),
        (
            "type",
            "duplicate or overlapping implementation; Show is already implemented",
            "MS3010.1",
        ),
        (
            "type",
            "extra operation g; Show declares: f (remove it or add it to the interface)",
            "MS3000.15",
        ),
        (
            "resolution",
            "fixture is available only in tests with a local make_fixture factory; declare it",
            "MS2001.6",
        ),
        ("type", "signature does not match contract", "MS3011.1"),
        (
            "type",
            "missing implementation operation f; add fn f to this impl",
            "MS3000.14",
        ),
        (
            "type",
            "duplicate implementation operation f; define each operation once per impl",
            "MS3000.16",
        ),
        (
            "type",
            "implementation receiver must be nominal source data; declare methods on a type",
            "MS3012.1",
        ),
        (
            "type",
            "implementation target must be an interface declared with 'interface'",
            "MS3000.17",
        ),
        (
            "type",
            "`x` is an immutable binding; declare it with var",
            "MS3060.2",
        ),
        (
            "type",
            "`f` does not change its receiver; declare it var fn",
            "MS3000.19",
        ),
        (
            "type",
            "non-exhaustive match; missing cases: A, or add a final 'case _:' arm",
            "MS3050.1",
        ),
    ] {
        let kind = kind_for(code_for(phase, message), message).expect(message);
        assert_eq!(kind.info.code, expected, "{message}");
        reached.insert(kind.info.code);
    }
    let missing: Vec<_> = KINDS
        .iter()
        .map(|k| k.info.code)
        .filter(|c| !reached.contains(c))
        .collect();
    assert!(
        missing.is_empty(),
        "no conformance diagnostic reaches {missing:?}"
    );
}
