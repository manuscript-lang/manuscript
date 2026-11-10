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
    let source = "export fn main() Int:\n    m := Map[String, Int]()\n    a := m.get(\"a\").get(0)\n    return m.get(\"a\").get() + a\n";
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

#[test]
fn explicit_generic_recursion_without_base_case_is_reported() {
    assert_eq!(
        recursive(include_str!("lint_bindings/generic-recursion.ms")),
        1
    );
}

#[test]
fn explicit_generic_calls_with_base_cases_or_other_targets_are_clean() {
    assert_eq!(
        recursive(include_str!("lint_bindings/generic-recursion-controls.ms")),
        0
    );
}

/// Applies every MSL102 fix of `source` on its own and returns each reparsed
/// import's name list.
fn unused_import_fixes(source: &str) -> Vec<Vec<String>> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("lint.ms");
    let module = ms_syntax::parser::parse(&file, source).unwrap();
    let program = ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    let mut results = Vec::new();
    for finding in lint_program(syms, &program)
        .iter()
        .filter(|f| f.code == "MSL102")
    {
        let fix = finding.fix.as_ref().unwrap();
        let mut fixed = source.to_string();
        fixed.replace_range(
            fix.pos.offset as usize..fix.end.offset as usize,
            &fix.replacement,
        );
        let module = ms_syntax::parser::parse(&file, &fixed).expect(&fixed);
        results.push(
            module
                .imports
                .iter()
                .map(|i| syms.str(i.name).to_string())
                .collect(),
        );
    }
    results
}

#[test]
fn unused_import_fix_ignores_parens_and_from_in_import_comments() {
    for newline in ["\n", "\r\n"] {
        let grouped = include_str!("lint_bindings/import-comment-paren.ms").replace('\n', newline);
        assert_eq!(unused_import_fixes(&grouped), [["floor"]]);

        let single = include_str!("lint_bindings/import-comment-from.ms").replace('\n', newline);
        let fixed = unused_import_fixes(&single);
        assert_eq!(fixed.len(), 2);
        assert!(fixed.iter().all(|names| names.is_empty()), "{fixed:?}");
    }
}

#[test]
fn grouped_import_removal_ends_at_the_lexed_path_for_escaped_quotes() {
    let file: Arc<str> = Arc::from("lint.ms");
    for newline in ["\n", "\r\n"] {
        let source = include_str!("lint_bindings/escaped-quote-path.ms").replace('\n', newline);
        let module = ms_syntax::parser::parse(&file, &source).unwrap();
        let tokens = ms_syntax::lexer::lex(&file, &source).unwrap().tokens;
        let import = &module.imports[0];
        assert!(import.in_group(&source, &tokens));
        let (start, end) = import.group_removal(&source, &tokens, false).unwrap();
        let mut edited = source.clone();
        edited.replace_range(start..end, "");
        let module = ms_syntax::parser::parse(&file, &edited).expect(&edited);
        assert_eq!(module.imports.len(), 1, "{edited}");
        assert_eq!(&*module.imports[0].path, "@std/math/math.ms");
    }
}
