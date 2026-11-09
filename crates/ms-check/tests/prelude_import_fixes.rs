//! Each redundant prelude import carries a fix that leaves parseable source on its own,
//! because an editor applies the fix of one diagnostic at a time.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn fixes_applied_alone(source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("t.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    let program = ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    program
        .diagnostics
        .iter()
        .filter_map(|d| d.fix.clone())
        .map(|fix| {
            let mut text = source.to_string();
            text.replace_range(
                fix.pos.offset as usize..fix.end.offset as usize,
                &fix.replacement,
            );
            text
        })
        .collect()
}

#[test]
fn a_flat_import_loses_one_name_and_keeps_its_spacing() {
    let got = fixes_applied_alone(include_str!("prelude_import_fixes/flat.ms"));
    assert_eq!(got.len(), 2);
    for text in &got {
        assert!(
            ms_syntax::parser::parse(&Arc::from("t.ms"), text).is_ok(),
            "{text}"
        );
    }
    assert!(got[1].starts_with("import ListEntry from "), "{}", got[1]);
}

#[test]
fn a_trailing_comma_group_stays_parseable_after_each_fix() {
    for text in fixes_applied_alone(include_str!("prelude_import_fixes/grouped.ms")) {
        assert!(
            ms_syntax::parser::parse(&Arc::from("t.ms"), &text).is_ok(),
            "{text}"
        );
    }
}
