//! `MSL115`: a promise dropped as soon as it is made.

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

fn source(name: &str) -> String {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/lint_promises")
        .join(name);
    std::fs::read_to_string(path).expect("fixture")
}

#[test]
fn a_promise_statement_is_reported() {
    assert_eq!(codes(&source("statement.ms")), ["MSL115"]);
}

#[test]
fn a_discarded_binding_is_reported() {
    assert_eq!(codes(&source("discarded.ms")), ["MSL115"]);
}

#[test]
fn a_waited_promise_is_not_reported() {
    assert!(codes(&source("waited.ms")).is_empty());
    assert!(codes(&source("direct.ms")).is_empty());
}

#[test]
fn the_fix_waits_for_a_dropped_call() {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("lint.ms");
    let source = source("statement.ms");
    let module = ms_syntax::parser::parse(&file, &source).expect("parses");
    let program = ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    let findings = lint_program(syms, &program);
    let fix = findings[0].fix.as_ref().expect("a fix");
    let mut fixed = source.clone();
    fixed.replace_range(
        fix.pos.offset as usize..fix.end.offset as usize,
        &fix.replacement,
    );
    assert!(
        fixed.contains("let _ = promise(fn: work()).wait()\n"),
        "{fixed}"
    );
}
