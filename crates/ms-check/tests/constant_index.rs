//! `table[i]` on a module-level constant indexes its value instead of applying type arguments (#3231).

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("t.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
    .diagnostics
    .iter()
    .map(|d| d.message.clone())
    .collect()
}

#[test]
fn a_constant_list_and_map_index_like_locals() {
    let source = "let table = [1, 2, 3]\nlet names = {\"a\": 1}\nfn at(i: Int) Int:\n    return table[i] + names[\"a\"]\nexport fn main() Int:\n    return at(1)\n";
    assert_eq!(diagnostics(source), Vec::<String>::new());
}
