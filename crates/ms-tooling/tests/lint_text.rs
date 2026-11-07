//! `MSL117`: an integer literal interpolated into text.

use ms_check::{CheckOptions, ImportMap};
use ms_tooling::lint::lint_program;
use std::sync::Arc;

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
    lint_program(syms, &program)
        .into_iter()
        .filter(|f| f.code == "MSL117")
        .map(|f| f.message)
        .collect()
}

#[test]
fn a_regex_quantifier_written_in_a_plain_literal_is_flagged() {
    let got = flagged("export fn main() Int:\n    print(\"\\\\d{4}-\\\\d{2}\")\n    return 0\n");
    assert_eq!(got.len(), 2, "{got:?}");
    assert!(
        got[0].starts_with("`{4}` interpolates the number 4"),
        "{got:?}"
    );
}

#[test]
fn escaped_braces_names_and_expressions_are_not_flagged() {
    let got = flagged(
        "export fn main() Int:\n    let n = 4\n    print(\"\\\\d\\{4\\}\")\n    print(\"{n} {n + 1} {1 + 2}\")\n    return 0\n",
    );
    assert!(got.is_empty(), "{got:?}");
}
