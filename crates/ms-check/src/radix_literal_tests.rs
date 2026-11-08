//! Radix digits are not decimal suffixes or exponent markers.

use crate::{CheckOptions, checker::Checker};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let session = crate::Session::new();
    session.ensure_standard();
    let file: Arc<str> = Arc::from("radix_literals.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    Checker::new(&session, &CheckOptions::default())
        .check_modules(vec![crate::load_module(syms, &module)], None)
        .diagnostics
        .into_iter()
        .map(|d| d.message)
        .collect()
}

#[test]
fn hex_zero_divisors_and_out_of_bounds_indices_are_constant_faults() {
    for literal in ["0xdead", "0xDEAD", "0x1e", "0x1E", "0x1d", "0b11101", "29"] {
        for op in ["/", "%"] {
            let got = diagnostics(&format!("fn f() Int: 1 {op} ({literal} - {literal})\n"));
            assert!(
                got.iter()
                    .any(|d| d.contains("division by zero always faults")),
                "{literal}: {got:?}"
            );
        }
        let got = diagnostics(&format!("fn f() Int: [1, 2][{literal}]\n"));
        assert!(
            got.iter().any(|d| d.contains("outside this list literal")),
            "{literal}: {got:?}"
        );
    }
}

#[test]
fn hexadecimal_overflow_is_diagnosed() {
    let got = diagnostics("fn f() Int: 0x7fff_ffff_ffff_fffe + 2\n");
    assert!(got.iter().any(|d| d.contains("overflows Int")), "{got:?}");
}

#[test]
fn sized_integer_context_accepts_hex_letters() {
    for source in [
        "fn f() Int8: -0x7d\n",
        "fn f() Int8: -0x80\n",
        "fn f(x: Int8) Int8: x + 0x1_D\n",
        "fn f(x: Int8) Int8: x + 0x1d\n",
        "fn f(x: Int8) Int8: x + (0x1e - 0x1d)\n",
        "fn f(x: Int8) Int8: x + 0x1E\n",
        "fn f(x: List[Int8]) Bool: x == [0x1d, 0x1e]\n",
        "fn f() Int8: -0b1111101\n",
    ] {
        let got = diagnostics(source);
        assert!(got.is_empty(), "{source}: {got:?}");
    }
}

#[test]
fn decimal_and_fractional_spelling_keep_their_kind() {
    for source in [
        "import Decimal from \"@std/math/decimal.ms\"\nfn f() Decimal: -1d\n",
        "fn f(x: Float32) Float32: x + 1e2\n",
    ] {
        let got = diagnostics(source);
        assert!(got.is_empty(), "{source}: {got:?}");
    }
    for source in [
        "fn f() Int8: -1d\n",
        "fn f(x: Int8) Int8: x + 1e2\n",
        "fn f() Int8: -0xdd\n",
        "fn f() Int8: -0x81\n",
        "fn f() Int: 0xffffffffffffffffffffffffffffffffd\n",
        "fn f() Int: 0xffffffffffffffffffffffffffffffffe\n",
        "fn f(x: Int8) Int8: x + (0x1e + 1.0)\n",
    ] {
        let got = diagnostics(source);
        assert!(!got.is_empty(), "{source} must remain rejected");
    }
}
