//! The `simplify` pass (see [`crate::opt`] for the pass contract): constant folding,
//! algebraic identities, strength reduction, trivial block-parameter elimination,
//! branch folding, block merging, jump threading, dominator-scoped value numbering
//! and dead code elimination.
//!
//! Checked operations are only weakened when the pass proves they cannot fault
//! (constant operands that do not overflow, a constant divisor other than 0 and -1).
//! Owned droppable values are never merged or deleted, so ownership stays linear.

use crate::ir::*;
use crate::types::Ty;
use crate::verify::dominators;
use std::collections::HashMap;

/// Runs the pass over every function; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for i in 0..m.funcs.len() {
        let mut f = m.funcs[i].clone();
        if simplify_func(m, &mut f) {
            changed = true;
            m.funcs[i] = f;
        }
    }
    changed
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum K {
    I(i64),
    F(u64),
    B(bool),
}

fn simplify_func(m: &Module, f: &mut Func) -> bool {
    let mut any = false;
    for _ in 0..24 {
        let mut c = false;
        c |= fold(f);
        c |= known_alts(m, f);
        c |= known_lists(m, f);
        c |= phis(m, f);
        c |= roundtrips(f);
        c |= branches(f);
        c |= cse(m, f);
        c |= dce(m, f);
        if !c {
            break;
        }
        any = true;
    }
    any
}

fn resolve(subst: &HashMap<Value, Value>, mut v: Value) -> Value {
    while let Some(n) = subst.get(&v) {
        v = *n;
    }
    v
}

/// Rewrites every use through `subst`.
fn apply_subst(f: &mut Func, subst: &HashMap<Value, Value>) {
    if subst.is_empty() {
        return;
    }
    for b in &mut f.blocks {
        for i in &mut b.insts {
            for a in &mut i.args {
                *a = resolve(subst, *a);
            }
        }
        b.term.for_each_use_mut(|v| *v = resolve(subst, *v));
    }
}

/// Folds operations on an alternative built in the same function by `alt.new` with a case
/// whose payload needs no drop: `alt.tag` becomes the case index, `alt.get` of the same
/// case becomes the payload operand, and when only drops remain the construction and the
/// drops are deleted (a plain-data case owns nothing, so ownership stays linear).
fn known_alts(m: &Module, f: &mut Func) -> bool {
    let mut known: HashMap<Value, (u32, Vec<Value>)> = HashMap::new();
    for b in &f.blocks {
        for i in &b.insts {
            let (Op::AltNew, Imm::Case(_, case), Some(r)) = (i.op, i.imm, i.res) else {
                continue;
            };
            if i.args.iter().all(|a| !m.needs_drop(f.ty(*a))) {
                known.insert(r, (case, i.args.clone()));
            }
        }
    }
    if known.is_empty() {
        return false;
    }
    let mut changed = false;
    let mut subst: HashMap<Value, Value> = HashMap::new();
    let mut blocks = std::mem::take(&mut f.blocks);
    for b in &mut blocks {
        for i in &mut b.insts {
            let Some((case, args)) = i.args.first().and_then(|a| known.get(a)) else {
                continue;
            };
            match (i.op, i.imm) {
                (Op::AltTag, _) => {
                    i.op = Op::IConst;
                    i.imm = Imm::Int(i64::from(*case));
                    i.args.clear();
                    changed = true;
                }
                (Op::AltGet, Imm::AltField(_, c, field)) if c == *case => {
                    if let (Some(r), Some(v)) = (i.res, args.get(field as usize)) {
                        subst.insert(r, *v);
                    }
                }
                _ => {}
            }
        }
    }
    f.blocks = blocks;
    if !subst.is_empty() {
        for b in &mut f.blocks {
            b.insts
                .retain(|i| i.res.is_none_or(|r| !subst.contains_key(&r)));
        }
        apply_subst(f, &subst);
        changed = true;
    }
    // A value left with only its drop is never observed: delete both.
    let uses = f.use_counts();
    let dead: Vec<Value> = known
        .keys()
        .copied()
        .filter(|v| {
            let drops = f
                .blocks
                .iter()
                .flat_map(|b| &b.insts)
                .filter(|i| i.op == Op::Drop && i.args[0] == *v)
                .count();
            uses[v.index()] > 0 && uses[v.index()] as usize == drops
        })
        .collect();
    if !dead.is_empty() {
        for b in &mut f.blocks {
            b.insts.retain(|i| {
                let is_drop = i.op == Op::Drop && dead.contains(&i.args[0]);
                let is_def = i.res.is_some_and(|r| dead.contains(&r));
                !(is_drop || is_def)
            });
        }
        changed = true;
    }
    changed
}

/// Folds reads of a `list.lit` whose elements need no drop and that is only read: `list.len`
/// becomes the element count and a read at a constant index in range becomes that element,
/// so a function returning `[y, m, d]` that the caller reads back by index allocates nothing
/// once inlined. With every read folded, the literal and its drops are deleted.
fn known_lists(m: &Module, f: &mut Func) -> bool {
    let mut consts: HashMap<Value, i64> = HashMap::new();
    let mut known: HashMap<Value, Vec<Value>> = HashMap::new();
    for i in f.blocks.iter().flat_map(|b| &b.insts) {
        match (i.op, i.imm, i.res) {
            (Op::IConst, Imm::Int(c), Some(r)) => {
                consts.insert(r, c);
            }
            (Op::ListLit, _, Some(r)) if i.args.iter().all(|a| !m.needs_drop(f.ty(*a))) => {
                known.insert(r, i.args.clone());
            }
            _ => {}
        }
    }
    if known.is_empty() {
        return false;
    }
    // Only literals nothing but these reads, `list.len` and drops touch.
    let uses = f.use_counts();
    let mut folded: HashMap<Value, u32> = HashMap::new();
    for i in f.blocks.iter().flat_map(|b| &b.insts) {
        let Some(list) = i.args.first().filter(|a| known.contains_key(*a)) else {
            continue;
        };
        let plain = (i.op == Op::ListLen && i.args.len() == 1)
            || (i.op == Op::Drop && i.args.len() == 1)
            || list_element(&known, &consts, i).is_some();
        if plain {
            *folded.entry(*list).or_default() += 1;
        }
    }
    known.retain(|v, _| folded.get(v) == Some(&uses[v.index()]));
    if known.is_empty() {
        return false;
    }
    let mut subst: HashMap<Value, Value> = HashMap::new();
    let mut blocks = std::mem::take(&mut f.blocks);
    for i in blocks.iter_mut().flat_map(|b| &mut b.insts) {
        if let (Some(r), Some(v)) = (i.res, list_element(&known, &consts, i)) {
            subst.insert(r, v);
        } else if i.op == Op::ListLen
            && let Some(items) = i.args.first().and_then(|a| known.get(a))
        {
            i.op = Op::IConst;
            i.imm = Imm::Int(items.len() as i64);
            i.args.clear();
        }
    }
    for b in &mut blocks {
        b.insts.retain(|i| {
            let read = i.res.is_some_and(|r| subst.contains_key(&r));
            let drop = i.op == Op::Drop && known.contains_key(&i.args[0]);
            let def = i.res.is_some_and(|r| known.contains_key(&r));
            !(read || drop || def)
        });
    }
    f.blocks = blocks;
    apply_subst(f, &subst);
    true
}

/// The element of a known list literal that `i`, a read at a constant index in range, yields.
fn list_element(
    known: &HashMap<Value, Vec<Value>>,
    consts: &HashMap<Value, i64>,
    i: &Inst,
) -> Option<Value> {
    let [list, at] = i.args.as_slice() else {
        return None;
    };
    if !matches!(i.op, Op::ListGet | Op::ListGetU) {
        return None;
    }
    let at = usize::try_from(*consts.get(at)?).ok()?;
    known.get(list)?.get(at).copied()
}

// ---- folding ---------------------------------------------------------------

enum Act {
    Keep,
    Const(K),
    Alias(Value),
    Rewrite(Op, Vec<Value>, Imm),
}

#[derive(Default)]
struct Env {
    consts: HashMap<Value, K>,
    defs: HashMap<Value, (Op, Vec<Value>, Imm)>,
}

impl Env {
    fn ci(&self, v: Value) -> Option<i64> {
        match self.consts.get(&v) {
            Some(K::I(x)) => Some(*x),
            Some(K::B(b)) => Some(*b as i64),
            _ => None,
        }
    }
    fn cf(&self, v: Value) -> Option<f64> {
        match self.consts.get(&v) {
            Some(K::F(x)) => Some(f64::from_bits(*x)),
            _ => None,
        }
    }
}

fn is_pow2(x: i64) -> bool {
    x > 1 && x & (x - 1) == 0
}

fn mk_const(f: &mut Func, env: &mut Env, out: &mut Vec<Inst>, ty: Ty, v: i64, loc: Loc) -> Value {
    let r = f.new_value(ty);
    out.push(Inst {
        op: Op::IConst,
        args: vec![],
        imm: Imm::Int(v),
        res: Some(r),
        loc,
    });
    env.consts.insert(r, K::I(v));
    env.defs.insert(r, (Op::IConst, vec![], Imm::Int(v)));
    r
}

fn commutative(op: Op, imm: Imm) -> bool {
    match op {
        Op::IAdd
        | Op::IMul
        | Op::IAddChk
        | Op::IMulChk
        | Op::IAddOverflow
        | Op::IMulOverflow
        | Op::And
        | Op::Or
        | Op::Xor => true,
        Op::ICmp => matches!(imm, Imm::Cc(Cc::Eq | Cc::Ne)),
        _ => false,
    }
}

/// Evaluates an integer operation when it cannot fault.
fn int_op(op: Op, x: i64, y: i64) -> Option<i64> {
    Some(match op {
        Op::IAdd => x.wrapping_add(y),
        Op::ISub => x.wrapping_sub(y),
        Op::IMul => x.wrapping_mul(y),
        Op::IAddChk => x.checked_add(y)?,
        Op::ISubChk => x.checked_sub(y)?,
        Op::IMulChk => x.checked_mul(y)?,
        Op::SDiv | Op::SDivChk => x.checked_div(y)?,
        Op::SRemChk if y != 0 => x.wrapping_rem(y),
        Op::SRem => x.checked_rem(y)?,
        Op::Shl => x.wrapping_shl(y as u32),
        Op::Sshr => x.wrapping_shr(y as u32),
        _ => return None,
    })
}

fn zero_of(is_bool: bool) -> K {
    if is_bool { K::B(false) } else { K::I(0) }
}

fn rule(f: &mut Func, env: &mut Env, out: &mut Vec<Inst>, inst: &Inst) -> Act {
    let a = |i: usize| inst.args[i];
    let is_bool = inst.res.is_some_and(|r| f.ty(r) == Ty::BOOL);
    match inst.op {
        Op::IAdd | Op::ISub | Op::IMul | Op::IAddChk | Op::ISubChk | Op::IMulChk => {
            let (x, y) = (a(0), a(1));
            if let (Some(p), Some(q)) = (env.ci(x), env.ci(y)) {
                return int_op(inst.op, p, q).map_or(Act::Keep, |r| Act::Const(K::I(r)));
            }
            match inst.op {
                Op::IAdd | Op::IAddChk => {
                    if env.ci(y) == Some(0) {
                        return Act::Alias(x);
                    }
                    if env.ci(x) == Some(0) {
                        return Act::Alias(y);
                    }
                }
                Op::ISub | Op::ISubChk => {
                    if env.ci(y) == Some(0) {
                        return Act::Alias(x);
                    }
                    if x == y {
                        return Act::Const(K::I(0));
                    }
                }
                _ => {
                    if env.ci(y) == Some(1) {
                        return Act::Alias(x);
                    }
                    if env.ci(x) == Some(1) {
                        return Act::Alias(y);
                    }
                    if env.ci(y) == Some(0) || env.ci(x) == Some(0) {
                        return Act::Const(K::I(0));
                    }
                    if inst.op == Op::IMul
                        && let Some(c) = env.ci(y).filter(|c| is_pow2(*c))
                    {
                        let k = mk_const(f, env, out, f.ty(x), c.trailing_zeros() as i64, inst.loc);
                        return Act::Rewrite(Op::Shl, vec![x, k], Imm::None);
                    }
                }
            }
            Act::Keep
        }
        Op::INeg | Op::INegChk => {
            let x = a(0);
            if let Some(p) = env.ci(x) {
                let r = if inst.op == Op::INeg {
                    Some(p.wrapping_neg())
                } else {
                    p.checked_neg()
                };
                return r.map_or(Act::Keep, |r| Act::Const(K::I(r)));
            }
            if inst.op == Op::INeg
                && let Some((Op::INeg, args, _)) = env.defs.get(&x)
            {
                return Act::Alias(args[0]);
            }
            Act::Keep
        }
        Op::SDiv | Op::SRem | Op::SDivChk | Op::SRemChk => {
            let (x, y) = (a(0), a(1));
            let div = matches!(inst.op, Op::SDiv | Op::SDivChk);
            let chk = matches!(inst.op, Op::SDivChk | Op::SRemChk);
            if let (Some(p), Some(q)) = (env.ci(x), env.ci(y)) {
                return int_op(inst.op, p, q).map_or(Act::Keep, |r| Act::Const(K::I(r)));
            }
            match env.ci(y) {
                // Checked remainder defines MIN % -1 as zero, like the backend's
                // safe-divisor sequence; unlike division it cannot overflow.
                Some(-1) if inst.op == Op::SRemChk => Act::Const(K::I(0)),
                Some(1) => {
                    if div {
                        Act::Alias(x)
                    } else {
                        Act::Const(K::I(0))
                    }
                }
                Some(c) if c != 0 && c != -1 && chk => {
                    Act::Rewrite(if div { Op::SDiv } else { Op::SRem }, vec![x, y], Imm::None)
                }
                _ => Act::Keep,
            }
        }
        Op::And | Op::Or | Op::Xor => {
            let (x, y) = (a(0), a(1));
            if let (Some(p), Some(q)) = (env.ci(x), env.ci(y)) {
                let r = match inst.op {
                    Op::And => p & q,
                    Op::Or => p | q,
                    _ => p ^ q,
                };
                return Act::Const(if is_bool { K::B(r & 1 == 1) } else { K::I(r) });
            }
            if x == y {
                return match inst.op {
                    Op::Xor => Act::Const(zero_of(is_bool)),
                    _ => Act::Alias(x),
                };
            }
            let ones = if is_bool { 1 } else { -1 };
            match (inst.op, env.ci(y)) {
                (Op::And, Some(0)) => Act::Const(zero_of(is_bool)),
                (Op::And, Some(q)) if q == ones => Act::Alias(x),
                (Op::Or | Op::Xor, Some(0)) => Act::Alias(x),
                (Op::Xor, Some(1)) if is_bool => Act::Rewrite(Op::Not, vec![x], Imm::None),
                (Op::Or, Some(q)) if q == ones => {
                    Act::Const(if is_bool { K::B(true) } else { K::I(-1) })
                }
                _ => Act::Keep,
            }
        }
        Op::Shl | Op::Sshr => {
            let (x, y) = (a(0), a(1));
            if let (Some(p), Some(q)) = (env.ci(x), env.ci(y)) {
                return int_op(inst.op, p, q).map_or(Act::Keep, |r| Act::Const(K::I(r)));
            }
            if env.ci(y).is_some_and(|q| q & 63 == 0) {
                return Act::Alias(x);
            }
            Act::Keep
        }
        Op::Not => {
            let x = a(0);
            if let Some(p) = env.ci(x) {
                return Act::Const(K::B(p == 0));
            }
            if let Some((Op::Not, args, _)) = env.defs.get(&x) {
                return Act::Alias(args[0]);
            }
            Act::Keep
        }
        Op::ICmp => {
            let Imm::Cc(cc) = inst.imm else {
                return Act::Keep;
            };
            let (x, y) = (a(0), a(1));
            if let (Some(p), Some(q)) = (env.ci(x), env.ci(y)) {
                return Act::Const(K::B(cc.eval_int(p, q)));
            }
            if x == y {
                return Act::Const(K::B(matches!(cc, Cc::Eq | Cc::Le | Cc::Ge)));
            }
            // `(x % 2^k) ==/!= 0` tests the low bits of x.
            if matches!(cc, Cc::Eq | Cc::Ne)
                && env.ci(y) == Some(0)
                && let Some((Op::SRem | Op::SRemChk, rargs, _)) = env.defs.get(&x).cloned()
                && let Some(c) = env.ci(rargs[1]).filter(|c| is_pow2(*c))
            {
                let ty = f.ty(rargs[0]);
                let mask = mk_const(f, env, out, ty, c - 1, inst.loc);
                let r = f.new_value(ty);
                out.push(Inst {
                    op: Op::And,
                    args: vec![rargs[0], mask],
                    imm: Imm::None,
                    res: Some(r),
                    loc: inst.loc,
                });
                env.defs
                    .insert(r, (Op::And, vec![rargs[0], mask], Imm::None));
                return Act::Rewrite(Op::ICmp, vec![r, y], inst.imm);
            }
            Act::Keep
        }
        Op::FCmp => {
            let Imm::Cc(cc) = inst.imm else {
                return Act::Keep;
            };
            match (env.cf(a(0)), env.cf(a(1))) {
                (Some(p), Some(q)) => Act::Const(K::B(cc.eval_float(p, q))),
                _ => Act::Keep,
            }
        }
        Op::FAdd | Op::FSub | Op::FMul | Op::FDiv => match (env.cf(a(0)), env.cf(a(1))) {
            (Some(p), Some(q)) => {
                let r = match inst.op {
                    Op::FAdd => p + q,
                    Op::FSub => p - q,
                    Op::FMul => p * q,
                    _ => p / q,
                };
                Act::Const(K::F(r.to_bits()))
            }
            _ => Act::Keep,
        },
        Op::FNeg | Op::FSqrt | Op::FAbs => match env.cf(a(0)) {
            Some(p) => {
                let r = match inst.op {
                    Op::FNeg => -p,
                    Op::FSqrt => p.sqrt(),
                    _ => p.abs(),
                };
                Act::Const(K::F(r.to_bits()))
            }
            None => Act::Keep,
        },
        Op::I2F => env
            .ci(a(0))
            .map_or(Act::Keep, |p| Act::Const(K::F((p as f64).to_bits()))),
        Op::B2I => env.ci(a(0)).map_or(Act::Keep, |p| Act::Const(K::I(p))),
        Op::OptIsSome => match env.defs.get(&a(0)) {
            Some((Op::OptSome | Op::OptView, _, _)) => Act::Const(K::B(true)),
            Some((Op::OptNone, _, _)) => Act::Const(K::B(false)),
            _ => Act::Keep,
        },
        Op::OptGet | Op::OptUnwrap => {
            // A lent optional borrows its payload, so `opt.get` of it is the payload itself.
            // `opt.unwrap` owns its result, so it keeps copying.
            if let (Op::OptGet, Some((Op::OptView, args, _))) = (inst.op, env.defs.get(&a(0))) {
                return Act::Alias(args[0]);
            }
            let Some((Op::OptSome, args, _)) = env.defs.get(&a(0)) else {
                return Act::Keep;
            };
            // A scalar has no ownership to transfer or copy. For an owned payload,
            // the constructor consumed it, so aliasing it here would revive a move.
            if matches!(
                f.ty(args[0]),
                Ty::INT | Ty::BOOL | Ty::FLOAT | Ty::UNIT | Ty::PTR
            ) {
                Act::Alias(args[0])
            } else {
                Act::Keep
            }
        }
        Op::Select => {
            let (c, t, e) = (a(0), a(1), a(2));
            if let Some(p) = env.ci(c) {
                return Act::Alias(if p != 0 { t } else { e });
            }
            if t == e {
                return Act::Alias(t);
            }
            if is_bool && env.ci(t) == Some(1) && env.ci(e) == Some(0) {
                return Act::Alias(c);
            }
            if is_bool && env.ci(t) == Some(0) && env.ci(e) == Some(1) {
                return Act::Rewrite(Op::Not, vec![c], Imm::None);
            }
            Act::Keep
        }
        _ => Act::Keep,
    }
}

fn fold(f: &mut Func) -> bool {
    let mut changed = false;
    let mut env = Env::default();
    for b in &f.blocks {
        for i in &b.insts {
            let Some(r) = i.res else { continue };
            match (i.op, i.imm) {
                (Op::IConst, Imm::Int(x)) => {
                    env.consts.insert(r, K::I(x));
                }
                (Op::FConst, Imm::Float(x)) => {
                    env.consts.insert(r, K::F(x));
                }
                (Op::BConst, Imm::Bool(x)) => {
                    env.consts.insert(r, K::B(x));
                }
                _ => {}
            }
            env.defs.insert(r, (i.op, i.args.clone(), i.imm));
        }
    }
    let mut subst: HashMap<Value, Value> = HashMap::new();
    let mut blocks = std::mem::take(&mut f.blocks);
    for b in blocks.iter_mut() {
        let old = std::mem::take(&mut b.insts);
        let mut out: Vec<Inst> = Vec::with_capacity(old.len());
        for mut inst in old {
            for a in &mut inst.args {
                *a = resolve(&subst, *a);
            }
            // Constants go on the right of commutative operations.
            if inst.args.len() == 2
                && env.consts.contains_key(&inst.args[0])
                && !env.consts.contains_key(&inst.args[1])
            {
                if commutative(inst.op, inst.imm) {
                    inst.args.swap(0, 1);
                    changed = true;
                } else if let (Op::ICmp, Imm::Cc(cc)) = (inst.op, inst.imm) {
                    inst.args.swap(0, 1);
                    inst.imm = Imm::Cc(cc.swapped());
                    changed = true;
                }
            }
            // A fault guard whose condition is known false never fires.
            if inst.op == Op::IntOverflowIf
                && matches!(env.consts.get(&inst.args[0]), Some(K::B(false)))
            {
                changed = true;
                continue;
            }
            match rule(f, &mut env, &mut out, &inst) {
                Act::Keep => {}
                Act::Alias(v) => {
                    let r = inst.res.expect("aliased op has a result");
                    subst.insert(r, resolve(&subst, v));
                    changed = true;
                    continue;
                }
                Act::Const(k) => {
                    let (op, imm) = match k {
                        K::I(x) => (Op::IConst, Imm::Int(x)),
                        K::F(x) => (Op::FConst, Imm::Float(x)),
                        K::B(x) => (Op::BConst, Imm::Bool(x)),
                    };
                    let unchanged = inst.op == op && inst.imm == imm;
                    inst.op = op;
                    inst.imm = imm;
                    inst.args.clear();
                    env.consts
                        .insert(inst.res.expect("folded op has a result"), k);
                    changed |= !unchanged;
                }
                Act::Rewrite(op, args, imm) => {
                    inst.op = op;
                    inst.args = args;
                    inst.imm = imm;
                    changed = true;
                }
            }
            if let Some(r) = inst.res {
                env.defs.insert(r, (inst.op, inst.args.clone(), inst.imm));
            }
            out.push(inst);
        }
        b.insts = out;
        b.term.for_each_use_mut(|v| *v = resolve(&subst, *v));
        let folded = match &b.term {
            Term::CondBr { cond, then, els } => match env.ci(*cond) {
                Some(c) => Some(Term::Br(if c != 0 { then.clone() } else { els.clone() })),
                None if then == els => Some(Term::Br(then.clone())),
                None => None,
            },
            Term::Switch {
                value,
                cases,
                default,
            } => env.ci(*value).map(|v| {
                Term::Br(
                    cases
                        .iter()
                        .find(|c| c.0 == v)
                        .map_or(default.clone(), |c| c.1.clone()),
                )
            }),
            _ => None,
        };
        if let Some(t) = folded {
            b.term = t;
            changed = true;
        }
    }
    f.blocks = blocks;
    apply_subst(f, &subst);
    changed
}

// ---- block parameters ------------------------------------------------------

fn def_blocks(f: &Func) -> Vec<usize> {
    let mut d = vec![usize::MAX; f.values.len()];
    for (bi, b) in f.blocks.iter().enumerate() {
        for p in &b.params {
            d[p.value.index()] = bi;
        }
        for i in &b.insts {
            if let Some(r) = i.res {
                d[r.index()] = bi;
            }
        }
    }
    d
}

/// Removes block parameters that always receive one value (or themselves), and
/// parameters nobody reads. Droppable parameters are only removed when borrowed.
fn phis(m: &Module, f: &mut Func) -> bool {
    f.compact_blocks();
    let n = f.blocks.len();
    let defb = def_blocks(f);
    let mut inc: Vec<Vec<Vec<Value>>> = vec![Vec::new(); n];
    for b in &f.blocks {
        b.term
            .for_each_target(|t| inc[t.block.index()].push(t.args.clone()));
    }
    let uses = f.use_counts();
    let mut drop_param: Vec<Vec<usize>> = vec![Vec::new(); n];
    let mut subst: HashMap<Value, Value> = HashMap::new();
    for bi in 1..n {
        for (pi, p) in f.blocks[bi].params.iter().enumerate() {
            let droppable = m.needs_drop(f.ty(p.value));
            if uses[p.value.index()] == 0 && (p.mode != Mode::Own || !droppable) {
                drop_param[bi].push(pi);
                continue;
            }
            if inc[bi].is_empty() {
                continue;
            }
            let mut single: Option<Value> = None;
            let mut ok = true;
            for args in &inc[bi] {
                let a = args[pi];
                if a == p.value {
                    continue;
                }
                match single {
                    None => single = Some(a),
                    Some(s) if s == a => {}
                    Some(_) => {
                        ok = false;
                        break;
                    }
                }
            }
            if let (true, Some(v)) = (ok, single)
                && defb[v.index()] != bi
            {
                subst.insert(p.value, v);
                drop_param[bi].push(pi);
            }
        }
    }
    if drop_param.iter().all(|d| d.is_empty()) {
        return false;
    }
    for b in &mut f.blocks {
        b.term.for_each_target_mut(|t| {
            for &pi in drop_param[t.block.index()].iter().rev() {
                t.args.remove(pi);
            }
        });
    }
    for (bi, d) in drop_param.iter().enumerate() {
        for &pi in d.iter().rev() {
            f.blocks[bi].params.remove(pi);
        }
    }
    apply_subst(f, &subst);
    true
}

// ---- control flow ----------------------------------------------------------

fn incoming_edges(f: &Func) -> Vec<usize> {
    let mut c = vec![0usize; f.blocks.len()];
    for b in &f.blocks {
        b.term.for_each_target(|t| c[t.block.index()] += 1);
    }
    c
}

fn branches(f: &mut Func) -> bool {
    let mut changed = false;
    let before = f.blocks.len();
    f.compact_blocks();
    changed |= f.blocks.len() != before;
    // Merge a block into its unique predecessor when that predecessor falls into it.
    loop {
        let edges = incoming_edges(f);
        let mut subst: HashMap<Value, Value> = HashMap::new();
        let mut merged = false;
        for p in 0..f.blocks.len() {
            // A consumed block was emptied and ends in `Unreachable`, so it is skipped.
            while let Term::Br(t) = &f.blocks[p].term {
                let b = t.block.index();
                if b == 0 || b == p || edges[b] != 1 {
                    break;
                }
                let t = t.clone();
                merged = true;
                let bd = std::mem::take(&mut f.blocks[b]);
                f.blocks[p].insts.extend(bd.insts);
                f.blocks[p].term = bd.term;
                f.blocks[p].term_loc = bd.term_loc;
                for (bp, a) in bd.params.iter().zip(&t.args) {
                    subst.insert(bp.value, *a);
                }
            }
        }
        if !merged {
            break;
        }
        changed = true;
        apply_subst(f, &subst);
        f.compact_blocks();
    }
    // Thread edges through empty blocks that only forward their arguments.
    let uses = f.use_counts();
    for b in 1..f.blocks.len() {
        if !f.blocks[b].insts.is_empty() {
            continue;
        }
        let Term::Br(t) = f.blocks[b].term.clone() else {
            continue;
        };
        if t.block.index() == b {
            continue;
        }
        let params: Vec<Value> = f.blocks[b].params.iter().map(|p| p.value).collect();
        let in_args = |p: Value| t.args.iter().filter(|a| **a == p).count();
        if params
            .iter()
            .any(|p| uses[p.index()] as usize != in_args(*p))
        {
            continue;
        }
        let bb = Block(b as u32);
        let mut did = false;
        for pb in 0..f.blocks.len() {
            if pb == b {
                continue;
            }
            f.blocks[pb].term.for_each_target_mut(|e| {
                if e.block != bb {
                    return;
                }
                let new_args: Vec<Value> = t
                    .args
                    .iter()
                    .map(|a| match params.iter().position(|p| p == a) {
                        Some(i) => e.args[i],
                        None => *a,
                    })
                    .collect();
                e.block = t.block;
                e.args = new_args;
                did = true;
            });
        }
        changed |= did;
    }
    let before = f.blocks.len();
    f.compact_blocks();
    changed || f.blocks.len() != before
}

// ---- value numbering -------------------------------------------------------

type Key = (Op, Vec<Value>, Imm, Ty);

fn cse(m: &Module, f: &mut Func) -> bool {
    let rpo = f.rpo();
    let preds = f.predecessors();
    let idom = dominators(f, &rpo, &preds);
    let mut children: Vec<Vec<usize>> = vec![Vec::new(); f.blocks.len()];
    for b in &rpo {
        let i = b.index();
        if i != 0 && idom[i] != usize::MAX {
            children[idom[i]].push(i);
        }
    }
    let mut table: HashMap<Key, Value> = HashMap::new();
    let mut subst: HashMap<Value, Value> = HashMap::new();
    let mut removed: Vec<(usize, usize)> = Vec::new();
    // Explicit walk of the dominator tree; `Exit` unwinds a block's table entries.
    enum Step {
        Enter(usize),
        Exit(Vec<Key>),
    }
    let mut stack = vec![Step::Enter(0)];
    while let Some(s) = stack.pop() {
        let b = match s {
            Step::Exit(keys) => {
                for k in keys {
                    table.remove(&k);
                }
                continue;
            }
            Step::Enter(b) => b,
        };
        let mut log = Vec::new();
        for (ii, inst) in f.blocks[b].insts.iter().enumerate() {
            let Some(r) = inst.res else { continue };
            let ty = f.ty(r);
            // Reaching an identical dominated integer check proves the first one
            // succeeded. Its scalar operands cannot change across calls or I/O.
            // Keep the first check, including when its result is otherwise dead.
            let checked_int = matches!(
                inst.op,
                Op::IAddChk | Op::ISubChk | Op::IMulChk | Op::INegChk | Op::SDivChk | Op::SRemChk
            );
            if !(inst.op.is_numberable() || inst.op == Op::AltTag || checked_int)
                || m.needs_drop(ty)
            {
                continue;
            }
            let mut args: Vec<Value> = inst.args.iter().map(|a| resolve(&subst, *a)).collect();
            if commutative(inst.op, inst.imm) {
                args.sort_by_key(|v| v.0);
            }
            let key = (inst.op, args, inst.imm, ty);
            if let Some(prev) = table.get(&key) {
                subst.insert(r, *prev);
                removed.push((b, ii));
            } else {
                table.insert(key.clone(), r);
                log.push(key);
            }
        }
        stack.push(Step::Exit(log));
        for &c in children[b].iter().rev() {
            stack.push(Step::Enter(c));
        }
    }
    if removed.is_empty() {
        return false;
    }
    // One sweep per block: removing each instruction in place shifts the rest of the
    // block, quadratic in a block with many repeated computations.
    let mut dead: Vec<Vec<bool>> = f
        .blocks
        .iter()
        .map(|b| vec![false; b.insts.len()])
        .collect();
    for (b, ii) in removed {
        dead[b][ii] = true;
    }
    for (b, blk) in f.blocks.iter_mut().enumerate() {
        let mut ii = 0;
        blk.insts.retain(|_| {
            ii += 1;
            !dead[b][ii - 1]
        });
    }
    apply_subst(f, &subst);
    true
}

// ---- in-place mutators -----------------------------------------------------

/// Turns the move-out, call, move-back sequence lowering emits around a runtime mutator
/// of a value held in memory (`a = take P; put S, a; call f(S); b = take S; put P, b`) into
/// a call that mutates `P` directly. The temporary slot `S` exists only to hand the callee a
/// pointer, and `P` is not touched in between, so the callee sees and leaves the same state.
fn roundtrips(f: &mut Func) -> bool {
    let uses = f.use_counts();
    let mut changed = false;
    for b in &mut f.blocks {
        // Removed instructions are marked and swept once at the end: removing each one in
        // place shifts the rest of the block, quadratic in a block with many roundtrips.
        let mut removed = vec![false; b.insts.len()];
        let mut any = false;
        for i in 0..b.insts.len() {
            if removed[i] {
                continue;
            }
            let Some(found) = find_roundtrip(&b.insts, &removed, i, &uses) else {
                continue;
            };
            let (put_in, call, take_out, put_back, slot) = found;
            let p = b.insts[i].args[0];
            for arg in &mut b.insts[call].args {
                if *arg == slot {
                    *arg = p;
                }
            }
            for k in [put_back, take_out, put_in, i] {
                removed[k] = true;
            }
            any = true;
        }
        if any {
            let mut k = 0;
            b.insts.retain(|_| {
                k += 1;
                !removed[k - 1]
            });
            changed = true;
        }
    }
    changed
}

/// The instruction indexes of the sequence starting with the `take` at `at`:
/// `(put into slot, call, take from slot, put back, slot)`. Instructions marked in `removed`
/// are no longer part of the block.
fn find_roundtrip(
    insts: &[Inst],
    removed: &[bool],
    at: usize,
    uses: &[u32],
) -> Option<(usize, usize, usize, usize, Value)> {
    let first = &insts[at];
    let (Op::Take, Some(a)) = (first.op, first.res) else {
        return None;
    };
    let p = first.args[0];
    if uses[a.index()] != 1 {
        return None;
    }
    let live = |k: &usize| !removed[*k];
    let put_in = (at + 1..insts.len())
        .filter(live)
        .find(|&k| insts[k].op == Op::Put && insts[k].args[1] == a)?;
    let slot = insts[put_in].args[0];
    let ty = first.imm;
    // The slot's one definition usually sits right before the put.
    let def = (0..put_in)
        .rev()
        .filter(live)
        .map(|k| &insts[k])
        .find(|d| d.res == Some(slot) && d.op == Op::Slot && d.imm == ty)?;
    debug_assert!(def.args.is_empty());
    if uses[slot.index()] != 3 {
        return None;
    }
    let call = (put_in + 1..insts.len())
        .filter(live)
        .find(|&k| insts[k].args.contains(&slot))?;
    if !matches!(insts[call].op, Op::CallRt)
        || insts[call].args.iter().filter(|x| **x == slot).count() != 1
    {
        return None;
    }
    let take_out = (call + 1..insts.len())
        .filter(live)
        .find(|&k| insts[k].args.contains(&slot))?;
    let (Op::Take, Some(b)) = (insts[take_out].op, insts[take_out].res) else {
        return None;
    };
    if uses[b.index()] != 1 || insts[take_out].imm != ty {
        return None;
    }
    let put_back = (take_out + 1..insts.len())
        .filter(live)
        .find(|&k| insts[k].args.contains(&b))?;
    if insts[put_back].op != Op::Put || insts[put_back].args != [p, b] {
        return None;
    }
    // The memory at `p` is touched by nothing else in the window, and nothing else
    // in it can read or write through another pointer.
    for k in at + 1..put_back {
        if removed[k] || k == put_in || k == call || k == take_out {
            continue;
        }
        let w = &insts[k];
        if w.args.contains(&p) || !w.op.info().effects.is_pure() {
            return None;
        }
    }
    Some((put_in, call, take_out, put_back, slot))
}

// ---- dead code -------------------------------------------------------------

fn dce(m: &Module, f: &mut Func) -> bool {
    let mut uses = f.use_counts();
    let mut removable = vec![None; f.values.len()];
    let mut dead: Vec<Vec<bool>> = f
        .blocks
        .iter()
        .map(|b| vec![false; b.insts.len()])
        .collect();
    let mut work = Vec::new();
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate() {
            let Some(r) = inst.res else { continue };
            if inst.op.info().effects.removable() && m.result_mode(f, inst) != Some(Mode::Own) {
                removable[r.index()] = Some((bi, ii));
                if uses[r.index()] == 0 {
                    work.push(r);
                }
            }
        }
    }
    // Deleting a user may make its operands dead. Each instruction and operand
    // is visited once, including a long chain whose only live value is its input.
    let mut changed = false;
    while let Some(r) = work.pop() {
        let Some((bi, ii)) = removable[r.index()] else {
            continue;
        };
        dead[bi][ii] = true;
        changed = true;
        for a in &f.blocks[bi].insts[ii].args {
            uses[a.index()] -= 1;
            if uses[a.index()] == 0 {
                work.push(*a);
            }
        }
    }
    if changed {
        for (bi, b) in f.blocks.iter_mut().enumerate() {
            let mut ii = 0;
            b.insts.retain(|_| {
                let keep = !dead[bi][ii];
                ii += 1;
                keep
            });
        }
    }
    changed
}
