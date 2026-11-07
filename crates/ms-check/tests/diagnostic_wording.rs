//! Wording of diagnostics where the generic message used to mislead.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn messages(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("wording.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
    .diagnostics
    .into_iter()
    .map(|d| d.message.to_string())
    .collect()
}

#[test]
fn a_member_of_a_non_enum_type_name_does_not_list_empty_cases() {
    let got = messages("export fn main() Int:\n    return Int.max\n");
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(got[0].starts_with("Int has no member max"), "{got:?}");
    assert!(!got[0].contains("cases:"), "{got:?}");
}

#[test]
fn a_move_repeated_by_a_loop_says_so_instead_of_naming_its_own_position() {
    let got = messages(
        "fn f(root: String) Int:\n    var n = 0\n    for _i in 0..2:\n        let s = [root, \"x\"]\n        n += s.length()\n    return n\n",
    );
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(
        got[0].contains("used again on the next loop iteration"),
        "{got:?}"
    );
}
