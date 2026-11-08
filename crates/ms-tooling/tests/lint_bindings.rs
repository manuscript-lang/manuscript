//! Lint findings that need a checked program.

use ms_check::{CheckOptions, ImportMap};
use ms_tooling::lint::lint_program;
use std::sync::Arc;

fn codes(source: &str) -> Vec<String> {
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

#[test]
fn unused_import_fix_ignores_quotes_in_group_comments() {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("lint.ms");
    for comment in [
        "// The words \"square root\" do not delimit this import.",
        "// An unmatched \" does not open a string.",
        "/* An embedded \"@std/math/math.ms\" is not the path. */",
    ] {
        for newline in ["\n", "\r\n"] {
            let source = include_str!("lint_bindings/quoted-import-comment.ms")
                .replace(
                    "// The words \"square root\" do not delimit this import.",
                    comment,
                )
                .replace('\n', newline);
            let module = ms_syntax::parser::parse(&file, &source).unwrap();
            let program = ms_check::check(
                syms,
                vec![ms_check::load_module(syms, &module)],
                ImportMap::default(),
                CheckOptions::default(),
            );
            assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
            let findings = lint_program(syms, &program);
            let unused: Vec<_> = findings.iter().filter(|f| f.code == "MSL102").collect();
            assert_eq!(unused.len(), 2);
            for finding in unused {
                let fix = finding.fix.as_ref().unwrap();
                let mut fixed = source.clone();
                fixed.replace_range(
                    fix.pos.offset as usize..fix.end.offset as usize,
                    &fix.replacement,
                );
                let module = ms_syntax::parser::parse(&file, &fixed).expect(&fixed);
                assert_eq!(module.imports.len(), 1, "{fixed}");
                let program = ms_check::check(
                    syms,
                    vec![ms_check::load_module(syms, &module)],
                    ImportMap::default(),
                    CheckOptions::default(),
                );
                assert!(
                    program.diagnostics.is_empty(),
                    "{fixed}\n{:?}",
                    program.diagnostics
                );
                assert!(
                    !lint_program(syms, &program)
                        .iter()
                        .any(|f| f.code == "MSL102")
                );
            }
        }
    }
}
