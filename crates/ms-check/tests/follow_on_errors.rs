//! A reported fault in an argument must not also be blamed on the call.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn messages(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("follow.ms");
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
fn an_unknown_name_in_interpolation_is_the_only_error() {
    let found = messages(include_str!("follow_on_errors/interpolation.ms"));
    assert_eq!(found.len(), 1, "{found:?}");
    assert!(found[0].starts_with("unknown binding totl"), "{found:?}");
}
