//! An implementation names its parameters like the interface: calls through the interface label arguments by those names.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let file: Arc<str> = Arc::from("names.ms");
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

const SHAPE: &str =
    "interface Shape:\n    fn scaled(factor: Int) Int\ntype S:\n    n: Int\nimpl Shape for S:\n";

#[test]
fn renamed_parameter_is_rejected() {
    let got = diagnostics(&format!("{SHAPE}    fn scaled(k: Int) Int: self.n * k\n"));
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(
        got[0].contains("parameter names do not match contract"),
        "{got:?}"
    );
    assert!(got[0].contains("(factor)"), "{got:?}");
}

#[test]
fn matching_parameter_is_accepted() {
    let got = diagnostics(&format!(
        "{SHAPE}    fn scaled(factor: Int) Int: self.n * factor\n"
    ));
    assert!(got.is_empty(), "{got:?}");
}

#[test]
fn standard_contract_names_are_checked() {
    let got = diagnostics(
        "type P:\n    x: Int\nimpl Equal for P:\n    fn equals(o: P) Bool: self.x == o.x\n",
    );
    assert_eq!(got.len(), 1, "{got:?}");
}
