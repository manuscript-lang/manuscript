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

#[test]
fn loop_borrow_remedy_clones_the_iterable_not_its_root() {
    let template = include_str!("diagnostic_wording/loop-clone-remedy.ms");
    for iterable in ["rows.get(0)", "rows[0]", "first(rows)"] {
        let source = template.replace("rows.get(0)", iterable);
        let got = messages(&source);
        assert_eq!(got.len(), 1, "{iterable}: {got:?}");
        assert!(
            got[0].contains("appending `.clone()` to the loop's iterable expression"),
            "{iterable}: {got:?}"
        );
        assert!(!got[0].contains("in rows.clone()"), "{iterable}: {got:?}");
        let fixed = template.replace("rows.get(0)", &format!("{iterable}.clone()"));
        assert!(messages(&fixed).is_empty(), "{iterable}");
    }
}

// A clone repairs the error but hides a design choice and costs time and memory, so ownership
// errors name it in prose and never offer it as a machine-applicable fix (`ms check --fix`).
#[test]
fn ownership_errors_never_carry_a_clone_fix() {
    let sources = [
        include_str!("diagnostic_wording/clone-fix-borrow-store.ms"),
        include_str!("diagnostic_wording/clone-fix-moved-again.ms"),
    ];
    for source in sources {
        let syms = ms_syntax::Names::global();
        let file: Arc<str> = Arc::from("wording.ms");
        let module = ms_syntax::parser::parse(&file, source).expect("parses");
        let diagnostics = ms_check::check(
            syms,
            vec![ms_check::load_module(syms, &module)],
            ImportMap::default(),
            CheckOptions::default(),
        )
        .diagnostics;
        assert!(!diagnostics.is_empty(), "{source}");
        for d in diagnostics {
            assert!(d.fix.is_none(), "{}: {:?}", d.message, d.fix);
        }
    }
}
