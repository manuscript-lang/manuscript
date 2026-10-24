//! `MSL101` (unread bindings) for the borrow forms of `if var`.

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
fn if_var_borrow_that_is_only_written_is_not_unread() {
    let source = "export def main() -> Int:
    var m = Map[String, Int]()
    m.add(\"a\", 1)
    if var n = m.get(\"a\"):
        n += 1
    return m.get(\"a\").get(0)
";
    assert!(!codes(source).contains(&"MSL101".to_string()));
}

#[test]
fn if_let_binding_that_is_never_read_is_still_reported() {
    let source = "export def main() -> Int:
    let m = Map[String, Int]()
    if let n = m.get(\"a\"):
        return 1
    return 0
";
    assert!(codes(source).contains(&"MSL101".to_string()));
}
