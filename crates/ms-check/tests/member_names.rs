//! A method may not share a name with a field of its type: `value.name` always reads the field.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("members.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
    .diagnostics
    .into_iter()
    .map(|d| d.message)
    .collect()
}

#[test]
fn method_named_like_a_field_is_rejected() {
    let got = diagnostics("type T:\n    n: Int\nimpl T:\n    fn n() Int: 3\n");
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(got[0].contains("same name as a field"), "{got:?}");
}

#[test]
fn interface_operation_named_like_a_field_is_accepted() {
    let got = diagnostics(
        "interface I:\n    fn n() Int\ntype T:\n    n: Int\nimpl I for T:\n    fn n() Int: 3\n",
    );
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn distinct_names_are_accepted() {
    let got = diagnostics("type T:\n    n: Int\nimpl T:\n    fn twice() Int: self.n * 2\n");
    assert!(got.is_empty(), "{got:?}");
}
