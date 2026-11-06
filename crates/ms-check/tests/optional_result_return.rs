//! Returning `ok(x)` where an `Optional` of a `Result` is expected must not loop the ownership walk.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

#[test]
fn ok_wrapped_into_an_optional_result_is_checked() {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("forward.ms");
    let source = include_str!("optional_result_return/forward.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    let result = ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(result.diagnostics.is_empty(), "{:?}", result.diagnostics);
}
