//! Substitution preserves concrete sharing and snapshots unresolved variables.

use crate::fxmap::HashSet;
use crate::types::*;
use std::rc::Rc;

fn variable() -> Ty {
    let syms = ms_syntax::Names::global();
    Rc::new(Type::new(syms, n("T"), n("substitution/T"), Kind::Variable))
}

fn signature(children: &[Ty], result: Ty) -> Ty {
    let syms = ms_syntax::Names::global();
    let mut ty = Type::new(syms, n("callback"), n("callback"), Kind::Function);
    ty.params = children
        .iter()
        .enumerate()
        .map(|(i, ty)| Param {
            name: n(&format!("p{i}")),
            ty: ty.clone(),
            mutable: false,
            positional: false,
        })
        .collect();
    ty.result = Some(result);
    ty.defaults = Some(Rc::new(ParameterDefaults::new(HashSet::from_iter([n(
        "p0",
    )]))));
    Rc::new(ty)
}

#[test]
fn concrete_substitution_keeps_nested_types_and_callable_permissions() {
    let syms = ms_syntax::Names::global();
    let callback = signature(&[int(), string()], int());
    let mut outer = Type::new(syms, n("Box"), n("substitution/Box"), Kind::Type);
    outer.args = vec![callback];
    let outer = Rc::new(outer);
    for bindings in [
        Subst::default(),
        Subst::from_iter([(n("unused"), string())]),
    ] {
        assert!(Rc::ptr_eq(&outer, &sub(&outer, &bindings)));
    }
    assert!(outer.args[0].is_default(n("p0")));
}

#[test]
fn substitution_keeps_prefixes_suffixes_labels_and_result_at_each_changed_slot() {
    for indices in [&[0][..], &[1], &[2], &[0, 2], &[0, 1, 2]] {
        let var = variable();
        let mut children = vec![int(), string(), bool_()];
        for &index in indices {
            children[index] = var.clone();
        }
        let mut ty = (*signature(&children, int())).clone();
        ty.args = children.clone();
        let ty = Rc::new(ty);
        let replacement = string();
        let got = sub(&ty, &Subst::from_iter([(var.id, replacement.clone())]));
        assert!(!Rc::ptr_eq(&ty, &got));
        assert!(Rc::ptr_eq(&ty.result_ty(), &got.result_ty()));
        assert!(Rc::ptr_eq(
            ty.defaults.as_ref().unwrap(),
            got.defaults.as_ref().unwrap()
        ));
        for (i, original) in children.iter().enumerate() {
            let expected = if indices.contains(&i) {
                &replacement
            } else {
                original
            };
            assert!(Rc::ptr_eq(expected, &got.args[i]));
            assert!(Rc::ptr_eq(expected, &got.params[i].ty));
            assert_eq!(got.params[i].name, ty.params[i].name);
        }
    }
}

#[test]
fn unbound_nested_variables_snapshot_bounds_and_defaults_even_without_bindings() {
    let var = variable();
    let ty = signature(&[int(), var.clone(), string()], var.clone());
    let before = sub(&ty, &Subst::default());
    assert!(!Rc::ptr_eq(&before.params[1].ty, &var));
    assert!(!Rc::ptr_eq(&before.result_ty(), &var));
    var.bounds.borrow_mut().push(string());
    *var.default.borrow_mut() = Some(int());
    let after = sub(&ty, &Subst::default());
    for snapshot in [&before.params[1].ty, &before.result_ty()] {
        assert!(snapshot.bounds().is_empty());
        assert!(snapshot.default_ty().is_none());
    }
    for snapshot in [&after.params[1].ty, &after.result_ty()] {
        assert_eq!(
            ms_syntax::Names::global().str(snapshot.bounds()[0].id),
            "String"
        );
        assert_eq!(
            ms_syntax::Names::global().str(snapshot.default_ty().unwrap().id),
            "Int"
        );
    }
    assert!(Rc::ptr_eq(&ty.params[0].ty, &after.params[0].ty));
    assert!(Rc::ptr_eq(&ty.params[2].ty, &after.params[2].ty));
}

#[test]
fn result_only_substitution_keeps_concrete_arguments_and_parameters() {
    let var = variable();
    let mut ty = (*signature(&[int(), string()], var.clone())).clone();
    ty.args = vec![bool_()];
    let ty = Rc::new(ty);
    let result = string();
    let got = sub(&ty, &Subst::from_iter([(var.id, result.clone())]));
    assert!(Rc::ptr_eq(&result, &got.result_ty()));
    assert!(Rc::ptr_eq(&ty.args[0], &got.args[0]));
    for (old, new) in ty.params.iter().zip(&got.params) {
        assert!(Rc::ptr_eq(&old.ty, &new.ty));
        assert_eq!(old.name, new.name);
    }
    assert!(got.is_default(n("p0")));
}

#[test]
fn substitution_walks_a_shared_concrete_subtree_once() {
    // Each level repeats the previous node as both arguments, so a walk that revisits shared
    // nodes takes 2^60 steps.
    let syms = ms_syntax::Names::global();
    let mut node = int();
    for _ in 0..60 {
        let mut pair = Type::new(syms, n("Pair"), n("substitution/Pair"), Kind::Type);
        pair.args = vec![node.clone(), node];
        node = Rc::new(pair);
    }
    let bindings = Subst::from_iter([(n("substitution/C"), string())]);
    assert!(Rc::ptr_eq(&node, &sub(&node, &bindings)));
}
