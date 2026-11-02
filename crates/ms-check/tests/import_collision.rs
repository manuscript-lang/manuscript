//! Two imports of the same exported name get a diagnostic that says what to do.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

#[test]
fn same_named_std_imports_explain_the_wrapper_module() {
    let source = "import parse from \"@std/data/csv.ms\"\nimport parse from \"@std/data/toml.ms\"\nexport fn main() Int:\n    return 0\n";
    let file: Arc<str> = Arc::from("main.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    let got: Vec<String> = ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
    .diagnostics
    .into_iter()
    .map(|d| d.message)
    .collect();
    assert!(
        got.iter()
            .any(|d| d.contains("an import cannot be renamed") && d.contains("wrap the other")),
        "{got:?}"
    );
}
