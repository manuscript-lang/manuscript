//! Interned type ids agree with the rendered keys they replace.
use crate::fxmap::HashSet;
use crate::type_keys::{lowering_key, type_key};
use crate::types::*;
use crate::tytable::TyTable;
use std::rc::Rc;

fn pair(syms: ms_syntax::Names, left: Ty, right: Ty) -> Ty {
    let mut t = Type::new(syms, n("Pair"), n("test/Pair"), Kind::Type);
    t.args = vec![left, right];
    Rc::new(t)
}

fn var_param(ty: Ty, mutable: bool) -> Param {
    Param {
        name: n("p"),
        ty,
        mutable,
        positional: false,
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

fn shared(mut t: Ty, depth: usize) -> Ty {
    let syms = ms_syntax::Names::global();
    for _ in 0..depth {
        t = pair(syms, t.clone(), t);
    }
    t
}

#[test]
fn shared_fibonacci_and_shallow_fanout_keep_ids_and_representatives() {
    let syms = ms_syntax::Names::global();
    let mut table = TyTable::new();
    let graph = shared(int(), 30);
    let id = table.intern(&graph);
    assert_eq!(table.len(), 31);
    assert!(Rc::ptr_eq(table.ty(id), &graph));
    assert_eq!(table.shape(&graph), id);
    assert_eq!(table.intern(&Rc::new((*graph).clone())), id);
    assert!(Rc::ptr_eq(table.ty(id), &graph));

    let mut left = int();
    let mut right = string();
    for _ in 0..30 {
        let next = pair(syms, left, right.clone());
        left = right;
        right = next;
    }
    let mut table = TyTable::new();
    let fibonacci = table.intern(&right);
    assert_eq!(table.len(), 32);
    assert_eq!(table.intern(&right), fibonacci);
    assert!(Rc::ptr_eq(table.ty(fibonacci), &right));

    let mut row = Type::new(syms, n("Row"), n("test/Row"), Kind::Type);
    row.args = vec![int(); 512];
    let row = Rc::new(row);
    let mut fanout = Type::new(syms, n("Fanout"), n("test/Fanout"), Kind::Type);
    fanout.args = vec![row; 512];
    let fanout = Rc::new(fanout);
    let mut table = TyTable::new();
    let id = table.intern(&fanout);
    assert_eq!(table.len(), 3);
    assert_eq!(table.shape(&fanout), id);
    assert!(Rc::ptr_eq(table.ty(id), &fanout));
}

#[test]
fn activated_queries_keep_identity_modes_and_function_metadata() {
    let syms = ms_syntax::Names::global();
    let mut permitted = (*function(syms, vec![var_param(int(), false)], int())).clone();
    permitted.defaults = Some(Rc::new(ParameterDefaults::new(VarSet::from_iter([n("p")]))));
    let permitted = Rc::new(permitted);
    let graph = shared(permitted.clone(), 30);
    let mut table = TyTable::new();
    let lifted = table.intern(&graph);
    let shape = table.shape(&graph);
    assert_ne!(lifted, shape);
    for _ in 0..3 {
        assert_eq!(table.intern(&graph), lifted);
        assert_eq!(table.shape(&graph), shape);
    }
    let mut ordinary = (*permitted).clone();
    ordinary.defaults = None;
    assert_eq!(table.intern(&shared(Rc::new(ordinary), 30)), shape);

    let mut mutable = (*permitted).clone();
    mutable.params[0].mutable = true;
    assert_ne!(table.intern(&shared(Rc::new(mutable), 30)), lifted);
    let mut incomplete = (*permitted).clone();
    incomplete.result = None;
    assert_ne!(table.intern(&shared(Rc::new(incomplete), 30)), lifted);
    let mut with_args = (*permitted).clone();
    with_args.args.push(string());
    assert_ne!(table.intern(&shared(Rc::new(with_args), 30)), lifted);
    assert_ne!(
        table.intern(&shared(pair(syms, int(), string()), 30)),
        table.intern(&shared(pair(syms, string(), int()), 30)),
    );
}

#[test]
fn cache_storage_reuse_keeps_large_tiny_and_fresh_queries_independent() {
    let syms = ms_syntax::Names::global();
    let chain = |depth| {
        let mut t = int();
        for _ in 0..depth {
            let mut node = Type::new(syms, n("Node"), n("test/Node"), Kind::Type);
            node.args.push(t);
            t = Rc::new(node);
        }
        t
    };
    let large = chain(1000);
    let mut table = TyTable::new();
    let id = table.intern(&large);
    let rows = table.len();
    assert_eq!(rows, 1001);
    assert_eq!(table.shape(&int()), table.intern(&int()));
    assert_eq!(table.intern(&chain(80)), table.shape(&chain(80)));
    assert_eq!(table.shape(&large), id);
    assert_eq!(table.intern(&chain(1000)), id);
    assert_eq!(table.len(), rows);
    assert!(Rc::ptr_eq(table.ty(id), &large));
}

#[test]
fn identity_still_ignores_nonfunction_callable_edges_and_variable_snapshots() {
    let syms = ms_syntax::Names::global();
    let variable = Rc::new(Type::new(syms, n("T"), n("test/T"), Kind::Variable));
    let graph = shared(variable.clone(), 30);
    let mut table = TyTable::new();
    let id = table.intern(&graph);
    variable.bounds.borrow_mut().push(invalid());
    *variable.default.borrow_mut() = Some(string());
    assert_eq!(table.intern(&graph), id);
    assert_eq!(table.shape(&graph), id);

    let mut user = Type::new(syms, n("Type"), n("test/Type"), Kind::Type);
    let plain = table.intern(&Rc::new(user.clone()));
    user.params.push(var_param(graph.clone(), true));
    user.result = Some(graph);
    assert_eq!(table.intern(&Rc::new(user)), plain);
}
