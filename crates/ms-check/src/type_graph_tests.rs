//! Shared type graphs stay bounded without changing query edges or order.
use crate::types::*;
use std::{cell::Cell, rc::Rc};

fn pair(left: Ty, right: Ty) -> Ty {
    let mut t = Type::new(n("Pair"), n("test/Pair"), Kind::Record);
    t.args = vec![left, right];
    Rc::new(t)
}

fn shared(mut t: Ty, depth: usize) -> Ty {
    for _ in 0..depth {
        t = pair(t.clone(), t);
    }
    t
}

#[test]
fn shared_negative_search_visits_a_bounded_number_of_nodes() {
    let t = shared(int(), 30);
    let calls = Cell::new(0);
    assert!(!type_any::<true>(&t, |_| {
        calls.set(calls.get() + 1);
        false
    }));
    assert!(calls.get() < 300, "{} predicate calls", calls.get());
    assert!(!invalid_ty(&t));
    assert!(!mentions_variable(&t, &VarSet::from([n("absent")])));
}

#[test]
fn searches_keep_late_matches_and_do_not_cache_across_queries() {
    let variable = Rc::new(Type::new(n("T"), n("test/T"), Kind::Variable));
    let negative = shared(int(), 20);
    let t = pair(negative.clone(), variable.clone());
    let mut variables = VarSet::from([variable.id]);
    assert!(mentions_variable(&t, &variables));
    variables.clear();
    assert!(!mentions_variable(&t, &variables));
    assert!(type_any::<false>(&t, |t| t.kind == Kind::Variable));
    assert!(invalid_ty(&pair(negative, invalid())));
}

#[test]
fn callable_edges_remain_part_of_only_callable_queries() {
    let variable = Rc::new(Type::new(n("T"), n("test/T"), Kind::Variable));
    let mut function = Type::new(n("fn"), n("fn"), Kind::Function);
    function.params.push(Param {
        name: n("value"),
        ty: variable.clone(),
    });
    function.result = Some(invalid());
    let t = shared(Rc::new(function), 20);
    assert!(invalid_ty(&t));
    assert!(mentions_variable(&t, &VarSet::from([variable.id])));
    assert!(!type_any::<false>(&t, |t| t.kind == Kind::Variable));
    let calls = Cell::new(0);
    assert!(type_any::<true>(&pair(variable, invalid()), |_| {
        calls.set(calls.get() + 1);
        calls.get() == 2
    }));
    assert_eq!(calls.get(), 2, "left-to-right short circuit");
}

#[test]
fn structural_equality_keeps_missing_results_and_late_mismatches() {
    let left = shared(int(), 25);
    let right = shared(int(), 25);
    assert!(same(&left, &right));
    assert!(!same(&pair(left.clone(), int()), &pair(right, invalid())));
    let mut incomplete = Type::new(n("fn"), n("fn"), Kind::Function);
    incomplete.params.push(Param {
        name: n("value"),
        ty: left,
    });
    let incomplete = Rc::new(incomplete);
    assert!(
        !same(&incomplete, &incomplete),
        "a missing result remains unequal even after a large successful prefix"
    );
    let empty = Rc::new(Type::new(n("fn"), n("fn"), Kind::Function));
    assert!(
        same(&empty, &empty),
        "preserve the existing empty-pointer shortcut"
    );
    assert!(!same(&empty, &Rc::new((*empty).clone())));
}

#[test]
fn required_types_preserve_sharing_and_changed_variable_snapshots() {
    let concrete = shared(int(), 25);
    assert!(Rc::ptr_eq(&concrete, &required_type(&concrete)));
    let mut variable = Type::new(n("T"), n("test/T"), Kind::Variable);
    variable.defaults = Some(Rc::new(ParameterDefaults::new(Default::default())));
    *variable.default.borrow_mut() = Some(int());
    let variable = Rc::new(variable);
    let t = pair(variable.clone(), variable.clone());
    let required = required_type(&t);
    assert!(!Rc::ptr_eq(&t, &required));
    assert!(!Rc::ptr_eq(&required.args[0], &required.args[1]));
    for arg in &required.args {
        assert!(arg.defaults.is_none(), "Some(empty) is still erased");
        assert!(arg.bounds().is_empty());
        assert_eq!(arg.default_ty().unwrap().id, int().id);
    }
    variable.bounds.borrow_mut().push(invalid());
    *variable.default.borrow_mut() = Some(invalid());
    assert!(required.args.iter().all(|arg| arg.bounds().is_empty()));
    assert!(
        required
            .args
            .iter()
            .all(|arg| arg.default_ty().unwrap().id == int().id)
    );
}

#[test]
fn required_types_erase_permissions_in_every_original_child_position() {
    let mut permitted = Type::new(n("fn"), n("fn"), Kind::Function);
    permitted.defaults = Some(Rc::new(ParameterDefaults::new(VarSet::from([n("value")]))));
    permitted.params.push(Param {
        name: n("value"),
        ty: int(),
    });
    permitted.result = Some(int());
    let permitted = Rc::new(permitted);
    let mut container = Type::new(n("Container"), n("test/Container"), Kind::Record);
    container.args.push(permitted.clone());
    container.params.push(Param {
        name: n("unusual"),
        ty: permitted.clone(),
    });
    container.result = Some(permitted.clone());
    let required = required_type(&Rc::new(container));
    assert!(required.args[0].defaults.is_none());
    assert!(required.params[0].ty.defaults.is_none());
    assert!(required.result.as_ref().unwrap().defaults.is_none());
    assert!(permitted.defaults.is_some());
}
