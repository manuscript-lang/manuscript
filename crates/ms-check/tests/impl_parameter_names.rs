//! An implementation names its parameters like the interface: calls through the interface label arguments by those names.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("names.ms");
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

const SHAPE: &str = "interface Shape:\n    fn scaled(factor: Int) Int\ntype S:\n    n: Int\nfn use_shape(s: Shape) Unit:\n    return\nfn run(s: S) Unit:\n    use_shape(s)\n";

#[test]
fn renamed_parameter_is_rejected() {
    let got = diagnostics(&format!("{SHAPE}fn S.scaled(k: Int) Int: self.n * k\n"));
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(
        got[0].contains("must name its parameters like the interface"),
        "{got:?}"
    );
}

#[test]
fn matching_parameter_is_accepted() {
    let got = diagnostics(&format!(
        "{SHAPE}fn S.scaled(factor: Int) Int: self.n * factor\n"
    ));
    assert!(got.is_empty(), "{got:?}");
}
