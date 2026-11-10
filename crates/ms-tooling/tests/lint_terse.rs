//! `MSL118` and `MSL119`: longer spellings of shorter forms, with machine fixes.

use ms_check::{CheckOptions, ImportMap};
use ms_tooling::lint::lint_program;
use std::sync::Arc;

fn findings(source: &str) -> Vec<(String, String)> {
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
    lint_program(syms, &program)
        .into_iter()
        .filter(|f| {
            [
                "MSL118", "MSL119", "MSL120", "MSL121", "MSL122", "MSL126", "MSL127",
            ]
            .contains(&f.code)
        })
        .map(|f| {
            let fix = f.fix.expect("carries a fix");
            let replaced = &source[fix.pos.offset as usize..fix.end.offset as usize];
            (replaced.to_string(), fix.replacement)
        })
        .collect()
}

#[test]
fn emptiness_checks_and_list_gets_carry_fixes() {
    let got = findings(include_str!("lint_terse/verbose.ms"));
    let expected: Vec<(&str, &str)> = vec![
        ("xs.length() == 0", "xs.is_empty()"),
        ("name.length() > 0", "not name.is_empty()"),
        ("xs.length() == 0", "xs.is_empty()"),
        (".get(0)", "[0]"),
        (".get(1 + 1)", "[1 + 1]"),
    ];
    let got: Vec<(&str, &str)> = got.iter().map(|(a, b)| (a.as_str(), b.as_str())).collect();
    assert_eq!(got, expected);
}

#[test]
fn the_terse_forms_are_clean() {
    assert!(findings(include_str!("lint_terse/terse.ms")).is_empty());
}

#[test]
fn statement_shapes_carry_fixes_or_findings() {
    let got = findings(include_str!("lint_terse/loops.ms"));
    let got: Vec<&str> = got.iter().map(|(_, b)| b.as_str()).collect();
    assert_eq!(
        got,
        [
            "let label = if flag: 5 else: 0",
            "    var total = 0\n    for i in 0..n:\n        total += xs[i]",
            ".get_or(\"a\", 0)",
        ]
    );
}

#[test]
fn shapes_that_change_meaning_are_left_alone() {
    assert_eq!(findings(include_str!("lint_terse/kept.ms")), []);
}

#[test]
fn a_binding_returned_next_is_inlined() {
    let got = findings(include_str!("lint_terse/temps.ms"));
    assert_eq!(
        got,
        [(
            "let sum = xs.sum()\n    return sum".to_string(),
            "return xs.sum()".to_string()
        )]
    );
}

#[test]
fn generic_bodies_keep_get_even_when_instantiated_with_a_copy_type() {
    assert!(findings(include_str!("lint_terse/generic.ms")).is_empty());
}

#[test]
fn a_map_entry_rebuilt_from_its_lookup_is_updated_in_place() {
    let got = findings(include_str!("lint_terse/entries.ms"));
    let got: Vec<&str> = got.iter().map(|(_, b)| b.as_str()).collect();
    assert_eq!(got, ["stock[item.sku] -= item.qty"]);
}
