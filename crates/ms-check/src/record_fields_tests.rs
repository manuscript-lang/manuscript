//! Record member lookup indexes source positions and substitutes only the selected field.

use crate::checker::{CheckOptions, Checker, Program};
use crate::types::*;
use std::rc::Rc;
use std::sync::Arc;

fn check(source: &str) -> Program {
    crate::stdlib::ensure_standard();
    let file: Arc<str> = Arc::from("record_fields.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("valid fixture");
    Checker::new(&CheckOptions::default()).check_modules(vec![crate::load_module(&module)], None)
}

fn access() -> Program {
    let p = check(include_str!("../tests/record_fields/access.ms"));
    assert!(p.diagnostics.is_empty(), "{:?}", p.diagnostics);
    p
}

fn named(p: &Program, name: &str) -> Ty {
    p.symbols[&n("record_fields.ms")].borrow()[&n(name)].ty()
}

#[test]
fn record_fields_members_keep_generic_types_and_method_fallbacks() {
    let p = access();
    assert!(crate::unused::check(&p).is_empty());
    let row = with_args(&named(&p, "Row"), vec![int(), string()]);
    let all = fields(&row);
    for field in &all {
        let selected = field_of(&row, field.name).expect("declared field");
        assert_eq!(selected.name, field.name);
        assert!(same(&selected.ty, &field.ty), "{}", field.name);
    }
    assert_eq!(
        all.iter().map(|p| p.name.as_str()).collect::<Vec<_>>(),
        ["first", "middle", "last", "nested", "to_string"]
    );
    assert_eq!(field_of(&row, n("to_string")).unwrap().ty.id, "Int");
    assert!(field_of(&row, n("count")).is_none());
    assert!(field_of(&row, n("absent")).is_none());
}

#[test]
fn record_fields_empty_primitive_and_monomorphic_lookups() {
    let p = access();
    for ty in [named(&p, "Empty"), int()] {
        assert!(field_of(&ty, n("value")).is_none());
    }
    let plain = named(&p, "Plain");
    assert_eq!(field_of(&plain, n("first")).unwrap().ty.id, "Int");
    assert_eq!(field_of(&plain, n("last")).unwrap().ty.id, "String");
}

#[test]
fn record_fields_partial_substitution_takes_fresh_variable_snapshots() {
    let p = access();
    let row = named(&p, "Row");
    let b = row.def.as_ref().unwrap().fields.borrow()[2].ty.result_ty();
    let partial = with_args(&row, vec![int()]);
    let before = field_of(&partial, n("last")).unwrap().ty;
    let old_result = before.result_ty();
    assert!(!Rc::ptr_eq(&old_result, &b));
    assert!(old_result.bounds().is_empty());
    assert!(old_result.default_ty().is_none());
    b.bounds.borrow_mut().push(string());
    *b.default.borrow_mut() = Some(int());
    let after = field_of(&partial, n("last")).unwrap().ty;
    let new_result = after.result_ty();
    assert!(!Rc::ptr_eq(&new_result, &old_result));
    assert_eq!(new_result.bounds()[0].id, "String");
    assert_eq!(new_result.default_ty().unwrap().id, "Int");
    assert!(old_result.bounds().is_empty());
    assert!(old_result.default_ty().is_none());
    assert!(Rc::ptr_eq(&after.params[0].ty, &partial.args[0]));
    assert_eq!(b.bounds().len(), 1);
}

#[test]
fn record_fields_lookup_does_not_substitute_unselected_fields() {
    let p = access();
    let row = named(&p, "Row");
    let b = row.def.as_ref().unwrap().fields.borrow()[1].ty.args[0].clone();
    let partial = with_args(&row, vec![int()]);
    // Substituting an unrelated B field would try to snapshot these cells and panic.
    let _bounds = b.bounds.borrow_mut();
    let _default = b.default.borrow_mut();
    assert_eq!(field_of(&partial, n("first")).unwrap().ty.id, "Int");
    assert!(field_of(&partial, n("absent")).is_none());
}

#[test]
fn record_fields_duplicate_names_keep_the_first_declared_field() {
    let p = check(include_str!("../tests/record_fields/diagnostics.ms"));
    let duplicate = named(&p, "Duplicate");
    assert_eq!(field_of(&duplicate, n("value")).unwrap().ty.id, "Int");
    assert_eq!(fields(&duplicate).len(), 2);
}

#[test]
fn record_fields_bundled_and_source_standard_records_have_indices() {
    let p = check(include_str!("../tests/record_fields/standard.ms"));
    assert!(p.diagnostics.is_empty(), "{:?}", p.diagnostics);
    let pair = standard("Pair", vec![int(), string()]);
    assert_eq!(field_of(&pair, n("first")).unwrap().ty.id, "Int");
    assert_eq!(field_of(&pair, n("second")).unwrap().ty.id, "String");
    let deque = crate::stdlib::source_type(n("@std/deque.ms"), n("Deque")).unwrap();
    let deque = with_args(&deque.ty(), vec![int()]);
    assert_eq!(field_of(&deque, n("size")).unwrap().ty.id, "Int");
    assert_eq!(
        field_of(&deque, n("slots")).unwrap().ty.to_string(),
        "List[Int?]"
    );
}

#[test]
fn record_fields_recovered_declarations_keep_source_positions() {
    crate::stdlib::ensure_standard();
    let file = Arc::from("record_fields.ms");
    let (module, errors) = ms_syntax::partial::parse_partial(
        &file,
        include_str!("../tests/record_fields/recovery.ms"),
    );
    assert!(!errors.is_empty());
    let p = Checker::new(&CheckOptions::default())
        .check_modules(vec![crate::load_module(&module)], None);
    assert!(p.diagnostics.is_empty(), "{:?}", p.diagnostics);
    assert_eq!(
        field_of(&named(&p, "Plain"), n("last")).unwrap().ty.id,
        "String"
    );
}

#[test]
fn record_fields_diagnostics_remain_stable() {
    let p = check(include_str!("../tests/record_fields/diagnostics.ms"));
    let actual = p
        .diagnostics
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    assert_eq!(
        actual,
        include_str!("../tests/record_fields/diagnostics.txt")
            .lines()
            .collect::<Vec<_>>()
    );
}
