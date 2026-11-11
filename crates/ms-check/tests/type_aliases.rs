//! `type Name[T] = Type` is a transparent alias: any type expression, with arguments, and no new type.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("alias.ms");
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
fn aliases_and_targets_are_interchangeable() {
    let got = diagnostics(include_str!("type_aliases/accept.ms"));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn cycles_are_rejected() {
    let got = diagnostics(include_str!("type_aliases/cycle.ms"));
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(got[0].contains("refers to itself"), "{got:?}");
    let got = diagnostics(include_str!("type_aliases/self_cycle.ms"));
    assert!(got[0].contains("refers to itself"), "{got:?}");
}

#[test]
fn wrong_argument_count_is_rejected() {
    let got = diagnostics(include_str!("type_aliases/arity.ms"));
    assert!(
        got[0].contains("alias Bad takes 1 type arguments, found 0"),
        "{got:?}"
    );
}

#[test]
fn alias_of_a_private_type_cannot_be_exported() {
    let got = diagnostics(include_str!("type_aliases/private.ms"));
    assert!(got[0].contains("exposes private type Row"), "{got:?}");
}
