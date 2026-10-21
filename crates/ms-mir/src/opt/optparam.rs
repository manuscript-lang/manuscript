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
use std::collections::HashMap;

/// Runs the pass; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        while split_one(m, fi) {
            changed = true;
        }
    }
    changed
}

fn scalar_inner(m: &Module, f: &Func, v: Value) -> Option<Ty> {
    let TyKind::Opt(inner) = m.types.kind(f.ty(v)) else {
        return None;
    };
    matches!(
        m.types.kind(*inner),
        TyKind::Int | TyKind::Bool | TyKind::Float
    )
    .then_some(*inner)
}

fn const_of(m: &Module, ty: Ty, loc: crate::ir::Loc, f: &mut Func) -> Inst {
    let res = f.new_value(ty);
    let (op, imm) = match m.types.kind(ty) {
        TyKind::Bool => (Op::BConst, Imm::Bool(false)),
        TyKind::Float => (Op::FConst, Imm::Float(0f64.to_bits())),
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

fn split_one(m: &mut Module, fi: usize) -> bool {
    let f = &m.funcs[fi];
    let mut defs: HashMap<Value, (Op, Vec<Value>)> = HashMap::new();
    let mut other_uses: HashMap<Value, u32> = HashMap::new();
    for b in &f.blocks {
        for i in &b.insts {
            if let Some(r) = i.res {
                defs.insert(r, (i.op, i.args.clone()));
            }
            if !matches!(i.op, Op::OptIsSome | Op::OptGet) {
                for a in &i.args {
                    *other_uses.entry(*a).or_default() += 1;
                }
            }
        }
        // Block arguments and conditions count as other uses of their values.
        b.term
            .for_each_use(|v| *other_uses.entry(v).or_default() += 1);
    }
    for bi in 1..f.blocks.len() {
        for (k, p) in f.blocks[bi].params.iter().enumerate() {
            let Some(inner) = scalar_inner(m, f, p.value) else {
                continue;
            };
            if other_uses.contains_key(&p.value) {
                continue;
            }
            let mut ok = true;
            let mut any = false;
            for src in &f.blocks {
                src.term.for_each_target(|t| {
                    if t.block.index() == bi {
                        any = true;
                        ok &= matches!(defs.get(&t.args[k]), Some((Op::OptNone | Op::OptSome, _)));
                    }
                });
            }
            if !(ok && any) {
                continue;
            }
            apply(m, fi, bi, k, inner);
            return true;
        }
    }
    false
}

fn apply(m: &mut Module, fi: usize, bi: usize, k: usize, inner: Ty) {
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
    for si in 0..f.blocks.len() {
        let loc = f.blocks[si].term_loc;
        let mut new_insts: Vec<Inst> = Vec::new();
        let mut term = std::mem::replace(&mut f.blocks[si].term, crate::ir::Term::Unreachable);
        term.for_each_target_mut(|t| {
            if t.block.index() != bi {
                return;
            }
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
        });
        f.blocks[si].term = term;
        f.blocks[si].insts.append(&mut new_insts);
    }
    // Readers: `opt.is_some p` is the flag, `opt.get p` the value.
    let mut subst: HashMap<Value, Value> = HashMap::new();
    for b in &mut f.blocks {
        b.insts.retain(|i| {
            if i.args.first() != Some(&p) {
                return true;
            }
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
