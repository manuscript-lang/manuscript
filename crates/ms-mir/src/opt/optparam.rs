//! The `optparam` pass: splits an `Optional` of a scalar that only reaches its readers through a
//! block parameter into a flag and a value.
//!
//! ```text
//! b2: o = opt.none      br b4(o)          b2: br b4(false, 0)
//! b3: o = opt.some x    br b4(o)    =>    b3: br b4(true, x)
//! b4(p): opt.is_some p / opt.get p        b4(flag, val): flag / val
//! ```
//!
//! The merge of two constructors then looks like any other scalar merge, so `if o != none`
//! style code (`var o = none; if c { o = some(x) }; if let v = o { .. }`) becomes flag tests
//! the other passes already fold and if-convert. Only parameters whose every incoming value is
//! a constructor, and whose every use is `opt.is_some` or `opt.get`, are split.

use crate::ir::{BlockParam, Func, Imm, Inst, Mode, Module, Op, Value};
use crate::types::{Ty, TyKind};
use std::collections::{HashMap, HashSet};

/// Runs the pass; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        // One sweep splits every eligible parameter; a second confirms none is left.
        while split_all(m, fi) {
            changed = true;
        }
    }
    changed
}

fn scalar_inner(m: &Module, f: &Func, v: Value) -> Option<Ty> {
    let TyKind::Opt(inner) = m.types.kind(f.ty(v)) else {
        return None;
    };
    (matches!(m.types.kind(*inner), TyKind::Bool) || m.types.is_scalar(*inner)).then_some(*inner)
}

fn const_of(m: &Module, ty: Ty, loc: crate::ir::Loc, f: &mut Func) -> Inst {
    let res = f.new_value(ty);
    let (op, imm) = match m.types.kind(ty) {
        TyKind::Bool => (Op::BConst, Imm::Bool(false)),
        TyKind::Float | TyKind::Float32 => (Op::FConst, Imm::Float(0f64.to_bits())),
        _ => (Op::IConst, Imm::Int(0)),
    };
    Inst {
        op,
        args: Vec::new(),
        imm,
        res: Some(res),
        loc,
    }
}

/// Splits every eligible parameter of function `fi` in one analysis and one rewrite, so the cost
/// is linear in the function rather than per split.
fn split_all(m: &mut Module, fi: usize) -> bool {
    let f = &m.funcs[fi];
    let mut defs: HashMap<Value, Op> = HashMap::new();
    let mut other_uses: HashSet<Value> = HashSet::new();
    for b in &f.blocks {
        for i in &b.insts {
            if let Some(r) = i.res {
                defs.insert(r, i.op);
            }
            if !matches!(i.op, Op::OptIsSome | Op::OptGet) {
                other_uses.extend(i.args.iter().copied());
            }
        }
        // Block arguments and conditions count as other uses of their values.
        b.term.for_each_use(|v| {
            other_uses.insert(v);
        });
    }
    // Per block: every incoming edge's argument list.
    let mut incoming: Vec<Vec<Vec<Value>>> = vec![Vec::new(); f.blocks.len()];
    for src in &f.blocks {
        src.term
            .for_each_target(|t| incoming[t.block.index()].push(t.args.clone()));
    }
    // (block, parameter index, scalar type), per block in increasing index.
    let mut splits: Vec<(usize, usize, Ty)> = Vec::new();
    for bi in 1..f.blocks.len() {
        if incoming[bi].is_empty() {
            continue;
        }
        for (k, p) in f.blocks[bi].params.iter().enumerate() {
            let Some(inner) = scalar_inner(m, f, p.value) else {
                continue;
            };
            if other_uses.contains(&p.value) {
                continue;
            }
            if incoming[bi]
                .iter()
                .all(|args| matches!(defs.get(&args[k]), Some(Op::OptNone | Op::OptSome)))
            {
                splits.push((bi, k, inner));
            }
        }
    }
    if splits.is_empty() {
        return false;
    }
    apply(m, fi, &splits);
    true
}

fn apply(m: &mut Module, fi: usize, splits: &[(usize, usize, Ty)]) {
    // Snapshot constructors; the function is rewritten edge by edge.
    let mut f = std::mem::replace(
        &mut m.funcs[fi],
        crate::ir::Func::new("", Vec::new(), Ty::UNIT),
    );
    let mut defs: HashMap<Value, (Op, Vec<Value>)> = HashMap::new();
    for b in &f.blocks {
        for i in &b.insts {
            if let Some(r) = i.res {
                defs.insert(r, (i.op, i.args.clone()));
            }
        }
    }
    // Per block, the split parameters from the highest index down, so earlier indices stay valid.
    let mut by_block: HashMap<usize, Vec<(usize, Ty)>> = HashMap::new();
    for &(bi, k, inner) in splits {
        by_block.entry(bi).or_default().push((k, inner));
    }
    for v in by_block.values_mut() {
        v.reverse();
    }
    // Reader substitution: `opt.is_some p` is the flag, `opt.get p` the value.
    let mut flags: HashMap<Value, (Value, Value)> = HashMap::new();
    for (&bi, ks) in &by_block {
        for &(k, inner) in ks {
            let p = f.blocks[bi].params[k].value;
            let flag = f.new_value(Ty::BOOL);
            let val = f.new_value(inner);
            f.blocks[bi].params.splice(
                k..=k,
                [
                    BlockParam {
                        value: flag,
                        mode: Mode::Borrow,
                    },
                    BlockParam {
                        value: val,
                        mode: Mode::Borrow,
                    },
                ],
            );
            flags.insert(p, (flag, val));
        }
    }
    for si in 0..f.blocks.len() {
        let loc = f.blocks[si].term_loc;
        let mut new_insts: Vec<Inst> = Vec::new();
        let mut term = std::mem::replace(&mut f.blocks[si].term, crate::ir::Term::Unreachable);
        term.for_each_target_mut(|t| {
            let Some(ks) = by_block.get(&t.block.index()) else {
                return;
            };
            for &(k, inner) in ks {
                let a = t.args[k];
                let (flag_v, val_v) = match defs.get(&a) {
                    Some((Op::OptSome, args)) => {
                        let c = f.new_value(Ty::BOOL);
                        new_insts.push(Inst {
                            op: Op::BConst,
                            args: Vec::new(),
                            imm: Imm::Bool(true),
                            res: Some(c),
                            loc,
                        });
                        (c, args[0])
                    }
                    _ => {
                        let c = f.new_value(Ty::BOOL);
                        new_insts.push(Inst {
                            op: Op::BConst,
                            args: Vec::new(),
                            imm: Imm::Bool(false),
                            res: Some(c),
                            loc,
                        });
                        let z = const_of(m, inner, loc, &mut f);
                        let zv = z.res.expect("const result");
                        new_insts.push(z);
                        (c, zv)
                    }
                };
                t.args.splice(k..=k, [flag_v, val_v]);
            }
        });
        f.blocks[si].term = term;
        f.blocks[si].insts.append(&mut new_insts);
    }
    let mut subst: HashMap<Value, Value> = HashMap::new();
    for b in &mut f.blocks {
        b.insts.retain(|i| {
            let Some(&(flag, val)) = i.args.first().and_then(|a| flags.get(a)) else {
                return true;
            };
            let r = i.res.expect("reader defines a result");
            match i.op {
                Op::OptIsSome => subst.insert(r, flag),
                _ => subst.insert(r, val),
            };
            false
        });
    }
    for b in &mut f.blocks {
        for i in &mut b.insts {
            for a in &mut i.args {
                if let Some(s) = subst.get(a) {
                    *a = *s;
                }
            }
        }
        b.term.for_each_use_mut(|a| {
            if let Some(s) = subst.get(a) {
                *a = *s;
            }
        });
    }
    m.funcs[fi] = f;
}
