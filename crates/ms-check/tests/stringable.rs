//! A type's text form is its `Stringable` operation: found through the interface, exact signature.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("text.ms");
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

const TYPE: &str = "type P:\n    n: Int\n";

#[test]
fn own_to_string_returning_string_is_accepted() {
    let got = diagnostics(&format!(
        "{TYPE}fn P.to_string() String: \"p\"\nfn run(p: P) String: \"{{p}}\"\n"
    ));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn own_to_string_with_another_result_is_rejected() {
    let got = diagnostics(&format!("{TYPE}fn P.to_string() Int: self.n\n"));
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(got[0].contains("Stringable"), "{got:?}");
}

#[test]
fn to_string_with_a_parameter_is_its_own_method() {
    let got = diagnostics(&format!(
        "{TYPE}fn P.to_string(prefix: String) String: prefix\n"
    ));
    assert!(got.is_empty(), "{got:?}");
}
