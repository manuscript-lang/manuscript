//! List operations written in Manuscript (`stdlib/collections.ms`) load with the standard library
//! and apply to a `List[T]` only when `T` meets the operation's bound (#1285).

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let file: Arc<str> = Arc::from("t.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
    .diagnostics
    .iter()
    .map(|d| d.message.clone())
    .collect()
}

#[test]
fn bounded_operations_apply_without_an_import() {
    let source = include_str!("list_methods/bounded-operations-apply-without-an-import.ms");
    assert_eq!(diagnostics(source), Vec::<String>::new());
}

#[test]
fn operations_need_their_element_bound() {
    let cases = [
        ("[\"a\"].sum()", "sum"),
        ("[Plain(1)].min()", "min"),
        ("[Plain(1)].sorted()", "sorted"),
    ];
    for (call, name) in cases {
        let source = format!(
            "type Plain:\n    n: Int\nexport def main() -> Int:\n    let x = {call}\n    return 0\n"
        );
        let found = diagnostics(&source);
        assert!(
            found.iter().any(|m| m.contains(name)),
            "{call}: expected a diagnostic naming {name}, got {found:?}"
        );
    }
}
