//! Shared type graphs stay bounded without changing query edges or order.
use crate::types::*;
use std::{cell::Cell, rc::Rc};

fn pair(syms: ms_syntax::Names, left: Ty, right: Ty) -> Ty {
    let mut t = Type::new(syms, n("Pair"), n("test/Pair"), Kind::Type);
    t.args = vec![left, right];
    Rc::new(t)
}

fn shared(mut t: Ty, depth: usize) -> Ty {
    let syms = ms_syntax::Names::global();
    for _ in 0..depth {
        t = pair(syms, t.clone(), t);
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
    assert!(!mentions_variable(&t, &VarSet::from_iter([n("absent")])));
}

#[test]
fn searches_keep_late_matches_and_do_not_cache_across_queries() {
    let syms = ms_syntax::Names::global();
    let variable = Rc::new(Type::new(syms, n("T"), n("test/T"), Kind::Variable));
    let negative = shared(int(), 20);
    let t = pair(syms, negative.clone(), variable.clone());
    let mut variables = VarSet::from_iter([variable.id]);
    assert!(mentions_variable(&t, &variables));
    variables.clear();
    assert!(!mentions_variable(&t, &variables));
    assert!(type_any::<false>(&t, |t| t.kind == Kind::Variable));
    assert!(invalid_ty(&pair(syms, negative, invalid())));
}

#[test]
fn callable_edges_remain_part_of_only_callable_queries() {
    let syms = ms_syntax::Names::global();
    let variable = Rc::new(Type::new(syms, n("T"), n("test/T"), Kind::Variable));
    let mut function = Type::new(syms, n("fn"), n("fn"), Kind::Function);
    function.params.push(Param {
        name: n("value"),
        ty: variable.clone(),
        mutable: false,
        positional: false,
    });
    function.result = Some(invalid());
    let t = shared(Rc::new(function), 20);
    assert!(invalid_ty(&t));
    assert!(mentions_variable(&t, &VarSet::from_iter([variable.id])));
    assert!(!type_any::<false>(&t, |t| t.kind == Kind::Variable));
    let calls = Cell::new(0);
    assert!(type_any::<true>(&pair(syms, variable, invalid()), |_| {
        calls.set(calls.get() + 1);
        calls.get() == 2
    }));
    assert_eq!(calls.get(), 2, "left-to-right short circuit");
}

#[test]
fn structural_equality_keeps_missing_results_and_late_mismatches() {
    let syms = ms_syntax::Names::global();
    let left = shared(int(), 25);
    let right = shared(int(), 25);
    assert!(same(&left, &right));
    assert!(!same(
        &pair(syms, left.clone(), int()),
        &pair(syms, right, invalid())
    ));
    let mut incomplete = Type::new(syms, n("fn"), n("fn"), Kind::Function);
    incomplete.params.push(Param {
        name: n("value"),
        ty: left,
        mutable: false,
        positional: false,
    });
    let incomplete = Rc::new(incomplete);
    assert!(
        !same(&incomplete, &incomplete),
        "a missing result remains unequal even after a large successful prefix"
    );
    let empty = Rc::new(Type::new(syms, n("fn"), n("fn"), Kind::Function));
    assert!(
        same(&empty, &empty),
        "preserve the existing empty-pointer shortcut"
    );
    assert!(!same(&empty, &Rc::new((*empty).clone())));
}

#[test]
fn required_types_preserve_sharing_and_changed_variable_snapshots() {
    let syms = ms_syntax::Names::global();
    let concrete = shared(int(), 25);
    assert!(Rc::ptr_eq(&concrete, &required_type(&concrete)));
    let mut variable = Type::new(syms, n("T"), n("test/T"), Kind::Variable);
    variable.defaults = Some(Rc::new(ParameterDefaults::new(Default::default())));
    *variable.default.borrow_mut() = Some(int());
    let variable = Rc::new(variable);
    let t = pair(syms, variable.clone(), variable.clone());
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
    let syms = ms_syntax::Names::global();
    let mut permitted = Type::new(syms, n("fn"), n("fn"), Kind::Function);
    permitted.defaults = Some(Rc::new(ParameterDefaults::new(VarSet::from_iter([n(
        "value",
    )]))));
    permitted.params.push(Param {
        name: n("value"),
        ty: int(),
        mutable: false,
        positional: false,
    });
    permitted.result = Some(int());
    let permitted = Rc::new(permitted);
    let mut container = Type::new(syms, n("Container"), n("test/Container"), Kind::Type);
    container.args.push(permitted.clone());
    container.params.push(Param {
        name: n("unusual"),
        ty: permitted.clone(),
        mutable: false,
        positional: false,
    });
    container.result = Some(permitted.clone());
    let required = required_type(&Rc::new(container));
    assert!(required.args[0].defaults.is_none());
    assert!(required.params[0].ty.defaults.is_none());
    assert!(required.result.as_ref().unwrap().defaults.is_none());
    assert!(permitted.defaults.is_some());
}

#[test]
fn inference_resolution_bounds_shared_graphs_and_keeps_late_failures() {
    use crate::inference::inference_type_resolved;
    let syms = ms_syntax::Names::global();
    let concrete = shared(int(), 30);
    let variable = Rc::new(Type::new(syms, n("T"), n("test/T"), Kind::Variable));
    let mut variables = VarSet::from_iter([variable.id]);
    for allow_invalid in [false, true] {
        assert!(inference_type_resolved(
            &concrete,
            &variables,
            allow_invalid
        ));
        assert!(!inference_type_resolved(
            &pair(syms, concrete.clone(), variable.clone()),
            &variables,
            allow_invalid,
        ));
    }
    let mut wide = Type::new(syms, n("Wide"), n("test/Wide"), Kind::Type);
    wide.args = vec![concrete.clone(); 16];
    assert!(inference_type_resolved(&Rc::new(wide), &variables, false));
    let t = pair(syms, concrete, variable);
    variables.clear();
    assert!(inference_type_resolved(&t, &variables, false));
    variables.insert(n("test/T"));
    assert!(!inference_type_resolved(&t, &variables, false));
}

#[test]
fn inference_resolution_preserves_all_edges_and_invalid_policy() {
    use crate::inference::inference_type_resolved;
    let syms = ms_syntax::Names::global();
    let variable = Rc::new(Type::new(syms, n("T"), n("test/T"), Kind::Variable));
    for leaf in [invalid(), variable.clone()] {
        for edge in 0..3 {
            let mut t = Type::new(syms, n("Container"), n("test/Container"), Kind::Type);
            match edge {
                0 => t.args.push(leaf.clone()),
                1 => t.params.push(Param::new(n("value"), leaf.clone())),
                _ => t.result = Some(leaf.clone()),
            }
            let t = shared(Rc::new(t), 30);
            let variables = VarSet::from_iter([variable.id]);
            assert!(!inference_type_resolved(&t, &variables, false));
            assert_eq!(
                inference_type_resolved(&t, &variables, true),
                leaf.is_invalid()
            );
            assert!(inference_type_resolved(&t, &VarSet::default(), true));
        }
    }
    let missing_result = Rc::new(Type::new(syms, n("fn"), n("fn"), Kind::Function));
    assert!(inference_type_resolved(
        &missing_result,
        &VarSet::default(),
        false
    ));
    let inferred = Rc::new(Type::new(syms, n("?"), n("test/inferred"), Kind::Inferred));
    assert!(inference_type_resolved(
        &inferred,
        &VarSet::default(),
        false
    ));
    // Bounds and type defaults are not inference-resolution edges.
    variable.bounds.borrow_mut().push(invalid());
    *variable.default.borrow_mut() = Some(invalid());
    assert!(inference_type_resolved(
        &variable,
        &VarSet::default(),
        false
    ));
    assert!(!inference_type_resolved(
        &invalid(),
        &VarSet::from_iter([invalid().id]),
        true
    ));
}
