//! Optional payload context must reach pure sized numeric literal expressions.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("optional_literals.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
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
fn optional_positions_preserve_sized_literal_context() {
    let got = diagnostics(include_str!("optional_literal_context/accept.ms"));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn optional_context_preserves_numeric_and_wrapping_restrictions() {
    for (source, expected) in [
        (
            include_str!("optional_literal_context/reject-named.ms"),
            "expected Int8?, found Int",
        ),
        (
            include_str!("optional_literal_context/reject-kind.ms"),
            "expected Float32?, found Int",
        ),
        (
            include_str!("optional_literal_context/reject-mixed.ms"),
            "same independently known type",
        ),
        (
            include_str!("optional_literal_context/reject-overflow.ms"),
            "overflows Int8",
        ),
        (
            include_str!("optional_literal_context/reject-division.ms"),
            "division by zero always faults",
        ),
        (
            include_str!("optional_literal_context/reject-unsigned.ms"),
            "overflows UInt8",
        ),
        (
            include_str!("optional_literal_context/reject-float_range.ms"),
            "outside finite binary32 range",
        ),
        (
            include_str!("optional_literal_context/reject-nested.ms"),
            "expected Int8??, found Int",
        ),
        (
            include_str!("optional_literal_context/reject-type_named.ms"),
            "expected Int8?, found Int",
        ),
        (
            include_str!("optional_literal_context/reject-type_overflow.ms"),
            "overflows Int8",
        ),
        (
            include_str!("optional_literal_context/reject-float_remainder.ms"),
            "remainder requires integer operands",
        ),
    ] {
        let got = diagnostics(source);
        assert!(
            got.iter().any(|d| d.contains(expected)),
            "{source}: {got:?}"
        );
    }
}
