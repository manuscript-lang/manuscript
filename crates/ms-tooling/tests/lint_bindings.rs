//! Lint findings that need a checked program.

use ms_check::{CheckOptions, ImportMap};
use ms_tooling::lint::lint_program;
use std::sync::Arc;

fn codes(source: &str) -> Vec<String> {
    let file: Arc<str> = Arc::from("lint.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    let program = ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    lint_program(&program)
        .iter()
        .map(|f| f.code.to_string())
        .collect()
}

#[test]
fn optional_get_without_default_is_reported() {
    let source = "export fn main() Int:\n    let m = Map[String, Int]()\n    let a = m.get(\"a\").get(0)\n    return m.get(\"a\").get() + a\n";
    let found = codes(source);
    assert_eq!(
        found.iter().filter(|c| *c == "MSL110").count(),
        1,
        "{found:?}"
    );
}

fn recursive(source: &str) -> usize {
    codes(source).iter().filter(|c| *c == "MSL112").count()
}

#[test]
fn recursion_without_a_base_case_is_reported() {
    assert_eq!(
        recursive(include_str!(
            "lint_bindings/recursion-without-a-base-case-is-reported.ms"
        )),
        2
    );
}

#[test]
fn recursion_with_a_base_case_is_clean() {
    assert_eq!(
        recursive(include_str!(
            "lint_bindings/recursion-with-a-base-case-is-clean.ms"
        )),
        0
    );
}
