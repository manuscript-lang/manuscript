//! `inspect::collect` is `inspect` without the digest: same document, empty `build_id`.

use ms_tooling::inspect::{collect, inspect};
use std::sync::Arc;

#[test]
fn collect_matches_inspect_except_for_the_digest() {
    let names = ms_syntax::Names::global();
    let source = include_str!("inspect_rows/sample.ms");
    let module = ms_syntax::parser::parse(&Arc::from("sample.ms"), source).unwrap();
    let program = ms_check::check(
        names,
        vec![ms_check::load_module(names, &module)],
        ms_check::ImportMap::default(),
        ms_check::CheckOptions::default(),
    );
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    let full = inspect(names, &program);
    let mut rows_only = collect(names, &program);
    assert!(!full.build_id.is_empty());
    assert!(rows_only.build_id.is_empty());
    assert_eq!(rows_only.rows().entities.len(), full.rows().entities.len());
    assert_eq!(rows_only.rows().calls.len(), full.rows().calls.len());
    assert!(!full.rows().calls.is_empty());
    rows_only.build_id = full.build_id.clone();
    let esc = ms_json::Escape::HtmlSafe;
    assert_eq!(
        rows_only.to_json().compact(esc),
        full.to_json().compact(esc)
    );
}
