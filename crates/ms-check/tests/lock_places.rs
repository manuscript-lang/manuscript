//! Lock tracking compares binding identity, not spelling.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let file: Arc<str> = Arc::from("locks.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
    .diagnostics
    .into_iter()
    .map(|d| d.message)
    .collect()
}

const HEAD: &str = "import Shared, share from \"@std/concurrency/shared.ms\"\nimport lock from \"@std/concurrency/sync.ms\"\n\n";

#[test]
fn same_binding_locked_twice_is_rejected() {
    let got = diagnostics(&format!(
        "{HEAD}export fn main() Int:\n    let box = share(1)\n    var outer = lock(box)\n    var inner = lock(box)\n    inner.value += 1\n    outer.value += 1\n    return 0\n"
    ));
    assert!(got.iter().any(|m| m.contains("already locked")), "{got:?}");
}

#[test]
fn shadowing_name_is_a_different_place() {
    let got = diagnostics(&format!(
        "{HEAD}export fn main() Int:\n    let box = share(1)\n    var outer = lock(box)\n    if true:\n        let box = share(2)\n        var inner = lock(box)\n        inner.value += 1\n    outer.value += 1\n    return 0\n"
    ));
    assert!(!got.iter().any(|m| m.contains("already locked")), "{got:?}");
}
