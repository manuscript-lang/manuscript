//! The effect and ownership analyses of the standard library run on demand. Asking for a callable
//! later gives what whole-program analysis gives for it.

use ms_check::{CheckOptions, ImportMap, Program, Session};
use std::collections::BTreeMap;
use std::sync::Arc;

const SOURCE: &str = include_str!("demand_analysis/program.ms");

fn check() -> Program {
    let syms = ms_syntax::Names::global();
    let file: Arc<str> = Arc::from("t.ms");
    let module = ms_syntax::parser::parse(&file, SOURCE).expect("parses");
    let program = ms_check::check_in(
        syms,
        &Session::new(),
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    program
}

/// Every callable id that has a body in a bundled module.
fn library_ids(program: &Program) -> Vec<ms_check::api::types::Name> {
    let mut ids: Vec<_> = program
        .methods
        .iter()
        .filter(|m| m.decl.is_some())
        .map(|m| m.id)
        .collect();
    ids.sort_by_key(|id| ms_syntax::Names::global().str(*id).to_string());
    ids
}

#[test]
fn effects_asked_later_equal_the_full_scan() {
    let full = check();
    full.scan_all_effects();
    let lazy = check();
    let ids = library_ids(&lazy);
    assert!(ids.len() > 20, "the program loads library methods");
    for id in ids {
        assert_eq!(
            lazy.effects_of(id),
            full.effects_of(id),
            "effects of {}",
            ms_syntax::Names::global().str(id)
        );
        assert_eq!(lazy.declared_effects_of(id), full.declared_effects_of(id));
    }
}

#[test]
fn ownership_extended_later_equals_the_whole_program_analysis() {
    let program = check();
    let whole = program.hir().ownership();
    // Ask for every callable one by one, in the order the hir lists them, after the project's.
    let mut added = (*program.ownership).clone();
    for c in program.hir().callables() {
        if let Some(extra) = program.ownership_shared.analyze(&c) {
            added.absorb(&extra);
        }
    }
    let summary = |t: &ms_check::api::ownership::OwnershipFacts| {
        t.moving_params
            .iter()
            .map(|(k, v)| (format!("{:?}", k), v.clone()))
            .collect::<BTreeMap<_, _>>()
    };
    assert_eq!(summary(&added), summary(&whole.tables));
    assert_eq!(added.moves.len(), whole.tables.moves.len());
    assert_eq!(added.close_moves.len(), whole.tables.close_moves.len());
}

/// Directive comments are read once per callable and cached; a new check of edited source starts from
/// a fresh scan, so the edit shows.
#[test]
fn an_edited_directive_shows_in_the_next_check() {
    let declared = |effect: &str| {
        let syms = ms_syntax::Names::global();
        let file: Arc<str> = Arc::from("d.ms");
        let source = format!("// ms: effect {effect}\nexport fn exec() Void:\n    return\n");
        let module = ms_syntax::parser::parse(&file, &source).expect("parses");
        let program = ms_check::check_in(
            syms,
            &Session::new(),
            vec![ms_check::load_module(syms, &module)],
            ImportMap::default(),
            CheckOptions::default(),
        );
        let id = program.symbols[&syms.intern("d.ms")]
            .borrow()
            .get(&syms.intern("exec"))
            .expect("exec")
            .id;
        // Twice: the second answer comes from the cache.
        assert_eq!(
            program.declared_effects_of(id),
            program.declared_effects_of(id)
        );
        program.declared_effects_of(id)
    };
    assert_eq!(declared("db.write"), ["db.write"]);
    assert_eq!(declared("db.read"), ["db.read"]);
}
