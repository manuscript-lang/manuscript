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
        .filter(|f| f.code == "MSL118" || f.code == "MSL119")
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
