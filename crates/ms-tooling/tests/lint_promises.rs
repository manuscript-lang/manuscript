//! `MSL115`: a promise dropped as soon as it is made.

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

const HEAD: &str =
    "import promise from \"@std/concurrency/promise.ms\"\nfn work() Int!:\n    return ok(1)\n";

#[test]
fn a_promise_statement_is_reported() {
    let source = format!("{HEAD}export fn main() Int:\n    promise(fn: work())\n    return 0\n");
    assert_eq!(codes(&source), ["MSL115"]);
}

#[test]
fn a_discarded_binding_is_reported() {
    let source =
        format!("{HEAD}export fn main() Int:\n    let _ = promise(fn: work())\n    return 0\n");
    assert_eq!(codes(&source), ["MSL115"]);
}

#[test]
fn a_waited_promise_is_not_reported() {
    let source = format!(
        "{HEAD}export fn main() Int:\n    let p = promise(fn: work())\n    let n = p.wait().get(0)\n    return n\n"
    );
    assert!(codes(&source).is_empty());
    let direct =
        format!("{HEAD}export fn main() Int:\n    return promise(fn: work()).wait().get(0)\n");
    assert!(codes(&direct).is_empty());
}
