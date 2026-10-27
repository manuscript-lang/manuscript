//! `MSL114`: a resource closed at scope end whose type has a fallible flush nothing calls.

use ms_check::{CheckOptions, ImportMap};
use ms_tooling::lint::{Finding, lint_program};
use std::sync::Arc;

fn findings(source: &str) -> Vec<Finding> {
    let file: Arc<str> = Arc::from("lint.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    let program = ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    lint_program(&program)
        .into_iter()
        .filter(|f| f.code == "MSL114")
        .collect()
}

#[test]
fn only_the_binding_that_is_never_flushed_is_reported() {
    let found = findings(include_str!("lint_flush/unflushed.ms"));
    assert_eq!(found.len(), 1, "{found:?}");
    assert!(found[0].message.starts_with("`journal` is closed"));
    assert_eq!(found[0].pos.line, 15);
}
