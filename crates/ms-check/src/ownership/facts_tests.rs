use super::*;
use crate::{CheckOptions, ImportMap, Program, Session};
use std::sync::Arc;

const FACTS: [BindingFact; 6] = [
    BindingFact::SharedBorrow,
    BindingFact::ExclusiveBorrow,
    BindingFact::ImplicitClose,
    BindingFact::ExplicitClose,
    BindingFact::MovedPayload,
    BindingFact::ConditionalMove,
];

#[test]
fn binding_flags_preserve_all_combinations_and_exclusive_precedence() {
    for bits in 0..64 {
        let mut flags = BindingFlags::default();
        for fact in FACTS.into_iter().rev() {
            if bits & fact as u8 != 0 {
                flags.set(257, fact);
                flags.set(257, fact);
            }
        }
        for fact in FACTS {
            assert_eq!(flags.has(257, fact), bits & fact as u8 != 0);
            assert!(!flags.has(256, fact));
            assert!(!flags.has(258, fact));
        }
        let expected = if bits & BindingFact::ExclusiveBorrow as u8 != 0 {
            Some(crate::ownership::BorrowKind::Exclusive)
        } else if bits & BindingFact::SharedBorrow as u8 != 0 {
            Some(crate::ownership::BorrowKind::Shared)
        } else {
            None
        };
        assert_eq!(flags.borrow(257), expected);
        assert_eq!(flags.borrow(256), None);
    }
}

#[test]
fn binding_flags_storage_does_not_cover_unrepresented_id_gaps() {
    let mut flags = BindingFlags::default();
    flags.set(1_000_000, BindingFact::ImplicitClose);
    flags.set(0, BindingFact::SharedBorrow);
    flags.set(1_000_000, BindingFact::ExplicitClose);
    assert!(flags.has(1_000_000, BindingFact::ImplicitClose));
    assert!(flags.has(1_000_000, BindingFact::ExplicitClose));
    assert!(!flags.has(999_999, BindingFact::ImplicitClose));
    // A fixed number of facts must not allocate a prefix through their session IDs.
    assert!(
        flags.flags.capacity() <= 128,
        "{:?}",
        flags.flags.capacity()
    );
}

#[test]
fn binding_flags_accept_the_full_id_range_without_overflow() {
    let mut flags = BindingFlags::default();
    flags.set(usize::MAX, BindingFact::MovedPayload);
    flags.set(0, BindingFact::ConditionalMove);
    assert!(flags.has(usize::MAX, BindingFact::MovedPayload));
    assert!(!flags.has(usize::MAX - 1, BindingFact::MovedPayload));
    assert!(flags.has(0, BindingFact::ConditionalMove));
    assert!(!flags.has(0, BindingFact::MovedPayload));
}

fn check(session: &std::rc::Rc<Session>, file: &str, source: &str) -> Program {
    let syms = ms_syntax::Names::global();
    let parsed = ms_syntax::parser::parse(&Arc::from(file), source).expect("fixture parses");
    let program = crate::check_in(
        syms,
        session,
        vec![crate::load_module(syms, &parsed)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    program
}

fn alias_id(program: &Program) -> usize {
    let module = program
        .hir()
        .module(ms_syntax::Names::global(), "repeated.ms")
        .expect("user module");
    let sum = module
        .callables()
        .into_iter()
        .find(|c| c.name == crate::types::n("sum"))
        .expect("sum function");
    let crate::hir::Body::Block(body) = sum.body() else {
        panic!("function body");
    };
    let ms_syntax::ast::StmtKind::Bind { pattern, .. } = &body[0].kind else {
        panic!("alias binding");
    };
    module.pattern_binding(pattern).expect("alias identity").uid
}

#[test]
fn repeated_checks_keep_storage_bounded_and_live_program_facts_valid() {
    let session = Session::new();
    let source = include_str!("../../tests/binding_flags/repeated.ms");
    let first = check(&session, "repeated.ms", source);
    let first_facts = first.binding_facts.flags.clone();
    let storage_limit = first.binding_facts.flags.capacity() * 2;
    let first_alias = alias_id(&first);
    assert_eq!(
        first.binding_facts.borrow(first_alias),
        Some(crate::ownership::BorrowKind::Shared)
    );
    let csv = session
        .standard_source_module(crate::types::n("@std/data/csv.ms"))
        .expect("deferred source module loads");
    let loaded = session.ensure_source(&csv).expect("source module checks");
    assert!(std::rc::Rc::ptr_eq(
        &loaded,
        &session
            .ensure_source(&csv)
            .expect("source module stays cached")
    ));
    // This is a storage bound, not a speed deadline. Cached library IDs coexist with later
    // program IDs; retaining the first program must not make their facts overlap or mutate.
    for _ in 0..40 {
        let later = check(&session, "repeated.ms", source);
        assert!(later.binding_facts.flags.capacity() <= storage_limit);
        assert_eq!(first.binding_facts.flags, first_facts);
        // Fresh source gets fresh session identities; older programs retain their own facts.
        let later_alias = alias_id(&later);
        assert_ne!(later_alias, first_alias);
        assert_eq!(first.binding_facts.borrow(later_alias), None);
        assert_eq!(later.binding_facts.borrow(first_alias), None);
        assert_eq!(
            later.binding_facts.borrow(later_alias),
            Some(crate::ownership::BorrowKind::Shared)
        );
    }
}
