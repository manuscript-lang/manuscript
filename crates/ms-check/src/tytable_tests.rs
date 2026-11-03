//! Interned type ids agree with the rendered keys they replace.
use crate::types::*;
use crate::tytable::TyTable;
use std::collections::HashSet;
use std::rc::Rc;

fn pair(left: Ty, right: Ty) -> Ty {
    let mut t = Type::new(n("Pair"), n("test/Pair"), Kind::Record);
    t.args = vec![left, right];
    Rc::new(t)
}

fn var_param(ty: Ty, mutable: bool) -> Param {
    Param {
        name: n("p"),
        ty,
        mutable,
    }
}

#[test]
fn equal_trees_share_an_id_and_argument_order_matters() {
    let mut table = TyTable::new();
    let a = table.intern(&pair(int(), string()));
    assert_eq!(a, table.intern(&pair(int(), string())));
    assert_ne!(a, table.intern(&pair(string(), int())));
    assert_ne!(a, table.intern(&int()));
    assert_eq!(table.ty(a).to_string(), "Pair[Int, String]");
}

#[test]
fn var_parameters_and_results_distinguish_functions() {
    let mut table = TyTable::new();
    let by_value = function(vec![var_param(int(), false)], int());
    let by_var = function(vec![var_param(int(), true)], int());
    let other_result = function(vec![var_param(int(), false)], string());
    let ids: HashSet<_> = [&by_value, &by_var, &other_result]
        .iter()
        .map(|t| table.intern(t))
        .collect();
    assert_eq!(ids.len(), 3);
    assert_eq!(
        table.intern(&by_value),
        table.intern(&function(vec![var_param(int(), false)], int()))
    );
}

#[test]
fn ids_match_rendered_keys_across_many_types() {
    let mut table = TyTable::new();
    let mut types: Vec<Ty> = vec![int(), string(), invalid()];
    for i in 0..200 {
        let a = types[i % types.len()].clone();
        let b = types[(i * 7 + 1) % types.len()].clone();
        types.push(pair(a.clone(), b.clone()));
        types.push(function(vec![var_param(a, i % 2 == 0)], b));
    }
    for x in &types {
        for y in types.iter().step_by(11) {
            assert_eq!(
                table.intern(x) == table.intern(y),
                lowering_key(x) == lowering_key(y)
            );
            assert_eq!(table.shape(x) == table.shape(y), type_key(x) == type_key(y));
        }
    }
}
