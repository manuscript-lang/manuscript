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

#[test]
fn same_binding_locked_twice_is_rejected() {
    let got = diagnostics(include_str!("lock_places/same_binding.ms"));
    assert!(got.iter().any(|m| m.contains("already locked")), "{got:?}");
}

#[test]
fn shadowing_name_is_a_different_place() {
    let got = diagnostics(include_str!("lock_places/shadowed.ms"));
    assert!(!got.iter().any(|m| m.contains("already locked")), "{got:?}");
}
