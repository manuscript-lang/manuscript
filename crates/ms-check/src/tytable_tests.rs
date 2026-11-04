//! Interned type ids agree with the rendered keys they replace.
use crate::types::*;
use crate::tytable::TyTable;
use std::collections::HashSet;
use std::rc::Rc;

fn pair(syms: ms_syntax::Names, left: Ty, right: Ty) -> Ty {
    let mut t = Type::new(syms, n("Pair"), n("test/Pair"), Kind::Record);
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
    let syms = ms_syntax::Names::global();
    let mut table = TyTable::new();
    let a = table.intern(&pair(syms, int(), string()));
    assert_eq!(a, table.intern(&pair(syms, int(), string())));
    assert_ne!(a, table.intern(&pair(syms, string(), int())));
    assert_ne!(a, table.intern(&int()));
    assert_eq!(table.ty(a).display(syms).to_string(), "Pair[Int, String]");
}

#[test]
fn var_parameters_and_results_distinguish_functions() {
    let syms = ms_syntax::Names::global();
    let mut table = TyTable::new();
    let by_value = function(syms, vec![var_param(int(), false)], int());
    let by_var = function(syms, vec![var_param(int(), true)], int());
    let other_result = function(syms, vec![var_param(int(), false)], string());
    let ids: HashSet<_> = [&by_value, &by_var, &other_result]
        .iter()
        .map(|t| table.intern(t))
        .collect();
    assert_eq!(ids.len(), 3);
    assert_eq!(
        table.intern(&by_value),
        table.intern(&function(syms, vec![var_param(int(), false)], int()))
    );
}

#[test]
fn ids_match_rendered_keys_across_many_types() {
    let syms = ms_syntax::Names::global();
    let mut table = TyTable::new();
    let mut types: Vec<Ty> = vec![int(), string(), invalid()];
    for i in 0..200 {
        let a = types[i % types.len()].clone();
        let b = types[(i * 7 + 1) % types.len()].clone();
        types.push(pair(syms, a.clone(), b.clone()));
        types.push(function(syms, vec![var_param(a, i % 2 == 0)], b));
    }
    for x in &types {
        for y in types.iter().step_by(11) {
            assert_eq!(
                table.intern(x) == table.intern(y),
                lowering_key(syms, x) == lowering_key(syms, y)
            );
            assert_eq!(
                table.shape(x) == table.shape(y),
                type_key(syms, x) == type_key(syms, y)
            );
        }
    }
}
