//! Sub-codes name the cause within a rule family: stable, unique, and found in real diagnostics.

use ms_syntax::diag::{KINDS, code_for, explain, kind_for};
use std::collections::HashSet;

/// The (phase, message) pairs of the golden corpus.
fn corpus() -> Vec<(String, String)> {
    include_str!("golden.txt")
        .lines()
        .filter_map(|line| {
            let mut cols = line.split('\t');
            let phase = cols.next()?;
            let message = cols.nth(3)?;
            matches!(phase, "parse" | "resolution" | "type" | "lowering")
                .then(|| (phase.to_string(), message.to_string()))
        })
        .collect()
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
    // Causes the golden corpus does not exercise: message text taken from the checker.
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
        (
            "type",
            "duplicate or overlapping implementation; Show is already implemented",
            "MS3010.1",
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
        "no golden diagnostic reaches {missing:?}"
    );
}
