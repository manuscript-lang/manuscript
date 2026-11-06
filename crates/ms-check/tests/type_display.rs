//! A mismatch on a shared generic type prints a bounded type, not its full expansion.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn messages(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("display.ms");
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
fn a_shared_generic_type_mismatch_stays_small() {
    let found = messages(include_str!("type_display/shared_pairs.ms"));
    assert_eq!(found.len(), 1, "{found:?}");
    assert!(
        found[0].starts_with("expected Int, found Pair["),
        "{found:?}"
    );
    assert!(found[0].contains('…'), "{found:?}");
    assert!(found[0].len() < 1024, "{} bytes", found[0].len());
}
