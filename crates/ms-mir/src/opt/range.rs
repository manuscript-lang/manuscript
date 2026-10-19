//! Range analysis and check elimination.
//!
//! A sparse interval analysis over `Int` and `Bool` SSA values (i64 intervals, Booleans
//! as `0..=1`) followed by rewrites that remove checks the analysis proves redundant:
//!
//! * `iadd.chk`/`isub.chk`/`imul.chk`/`ineg.chk` become the unchecked forms when the
//!   exact result interval fits in `i64`;
//! * `sdiv.chk`/`srem.chk` become `sdiv`/`srem` when the divisor is provably nonzero
//!   and not `-1` (or the dividend is provably not `i64::MIN`);
//! * `list.get`/`list.set` become their `.nn` forms when the index is provably
//!   non-negative, and the `.u` forms when it is also provably below the length;
//! * `icmp` with a decided result becomes `bconst`, a `br_if` on a decided condition
//!   becomes `br`, and `switch` cases outside the scrutinee's interval are dropped
//!   (this also removes impossible `alt.tag` cases).
//!
//! # How facts are found
//!
//! * Block parameters join the intervals passed on every incoming edge. At loop headers
//!   the join widens to the type bound after a few growing rounds, then a few narrowing
//!   rounds recover precision.
//! * A conditional edge into a block with a single incoming edge refines the compared
//!   values (`br_if (icmp.lt a, b)` gives `a < hi(b)` in the taken block). Refinements are
//!   inherited down the dominator tree, which is sound because values are immutable. The
//!   same comparisons record relations `a < b` / `a <= b` between SSA values, used to
//!   prove `i < list.len l` for the *same* list value `l`: list values are immutable SSA
//!   values threaded through mutators, so one value has one length. The length of a
//!   `list.set` result is not related to its operand's here, and `list.push` results
//!   are new values, so a changed length never reuses a stale fact.
//! * An induction variable (`i` stepping by `i + c`, `c > 0`, guarded by `i < n`) is
//!   bounded by the upper bound of `n` because the guard refines the value that feeds
//!   the back edge.
//! * `list.len` results lie in `0..=2^47` (no address space holds more elements).
//!
//! # Bounded counters
//!
//! With [`ASSUME_BOUNDED_COUNTERS`] a loop-carried `Int` that starts in a small range
//! (`|v| <= 2^40`) and otherwise changes only by one constant step of size at most `2^16`
//! in one direction per iteration is assumed to stay within `i64::MAX/2` (or
//! `i64::MIN/2`). Reaching that bound takes more than `2^46` iterations, so no
//! physically possible run overflows such a counter. This is the one assumption beyond
//! a pure proof; set the constant to `false` to disable it.

use crate::ir::*;
use crate::types::{Ty, TyKind};
use std::collections::HashMap;

/// Whether bounded loop counters are assumed not to overflow (see the module docs).
pub const ASSUME_BOUNDED_COUNTERS: bool = true;

const COUNTER_STEP_MAX: i64 = 1 << 16;
const COUNTER_INIT_MAX: i64 = 1 << 40;
const LEN_MAX: i64 = 1 << 47;
const WIDEN_AFTER: u32 = 3;
const MAX_ROUNDS: usize = 60;
const NARROW_ROUNDS: usize = 3;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
struct Itv {
    lo: i64,
    hi: i64,
}

impl Itv {
    const TOP: Itv = Itv {
        lo: i64::MIN,
        hi: i64::MAX,
    };
    const BOOL: Itv = Itv { lo: 0, hi: 1 };

    fn point(v: i64) -> Itv {
        Itv { lo: v, hi: v }
    }

    fn join(self, o: Itv) -> Itv {
        Itv {
            lo: self.lo.min(o.lo),
            hi: self.hi.max(o.hi),
        }
    }

    fn meet(self, o: Itv) -> Option<Itv> {
        let (lo, hi) = (self.lo.max(o.lo), self.hi.min(o.hi));
        (lo <= hi).then_some(Itv { lo, hi })
    }

    fn is_point(self) -> bool {
        self.lo == self.hi
    }

    /// Clamps an exact range to `i64` (checked operations fault outside it).
    fn clamp(lo: i128, hi: i128) -> Itv {
        let (min, max) = (i64::MIN as i128, i64::MAX as i128);
        let (lo, hi) = (lo.max(min), hi.min(max));
        if lo > hi {
            Itv::TOP
        } else {
            Itv {
                lo: lo as i64,
                hi: hi as i64,
            }
        }
    }

    /// An exact range, or top when it leaves `i64` (wrapping operations).
    fn exact(lo: i128, hi: i128) -> Itv {
        if fits(lo, hi) {
            Itv {
                lo: lo as i64,
                hi: hi as i64,
            }
        } else {
            Itv::TOP
        }
    }
}

fn fits(lo: i128, hi: i128) -> bool {
    lo >= i64::MIN as i128 && hi <= i64::MAX as i128
}

fn corners(f: impl Fn(i128, i128) -> i128, x: Itv, y: Itv) -> (i128, i128) {
    let (xl, xh, yl, yh) = (x.lo as i128, x.hi as i128, y.lo as i128, y.hi as i128);
    let c = [f(xl, yl), f(xl, yh), f(xh, yl), f(xh, yh)];
    let lo = c.iter().copied().min().unwrap_or(0);
    let hi = c.iter().copied().max().unwrap_or(0);
    (lo, hi)
}

#[derive(Clone, Default)]
struct Env {
    itv: HashMap<Value, Itv>,
    /// `(a, b, strict)`: `a < b` when strict, else `a <= b`.
    rels: Vec<(Value, Value, bool)>,
}

impl Env {
    fn narrow(&mut self, v: Value, lo: i128, hi: i128) {
        let new = Itv::clamp(lo, hi);
        let cur = self.itv.get(&v).copied().unwrap_or(Itv::TOP);
        if let Some(m) = cur.meet(new) {
            self.itv.insert(v, m);
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Edge {
    Plain,
    Then,
    Else,
    Case(i64),
    Default,
}

enum Edit {
    Op(usize, usize, Op),
    Const(usize, usize, bool),
    Term(usize, Term),
}

struct Fa<'a> {
    m: &'a Module,
    f: &'a Func,
    defs: Vec<Option<(usize, usize)>>,
    rpo: Vec<Block>,
    idom: Vec<usize>,
    incoming: Vec<Vec<(usize, Edge, Vec<Value>)>>,
    base: Vec<Option<Itv>>,
    envs: Vec<Env>,
    widen: Vec<u32>,
    lenof: HashMap<Value, Value>,
}

/// Runs the pass over every function; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        let edits = {
            let mut fa = Fa::new(m, &m.funcs[fi]);
            if fa.solve() { fa.edits() } else { Vec::new() }
        };
        if edits.is_empty() {
            continue;
        }
        changed = true;
        let f = &mut m.funcs[fi];
        let mut terms = false;
        for e in edits {
            match e {
                Edit::Op(b, i, op) => f.blocks[b].insts[i].op = op,
                Edit::Const(b, i, v) => {
                    let inst = &mut f.blocks[b].insts[i];
                    inst.op = Op::BConst;
                    inst.args.clear();
                    inst.imm = Imm::Bool(v);
                }
                Edit::Term(b, t) => {
                    f.blocks[b].term = t;
                    terms = true;
                }
            }
        }
        if terms {
            f.compact_blocks();
        }
    }
    changed
}

fn tracked(ty: Ty) -> bool {
    ty == Ty::INT || ty == Ty::BOOL
}

fn type_top(ty: Ty) -> Itv {
    if ty == Ty::BOOL { Itv::BOOL } else { Itv::TOP }
}

impl<'a> Fa<'a> {
    fn new(m: &'a Module, f: &'a Func) -> Self {
        let n = f.blocks.len();
        let mut defs = vec![None; f.values.len()];
        let mut lenof = HashMap::new();
        for (bi, b) in f.blocks.iter().enumerate() {
            for (ii, i) in b.insts.iter().enumerate() {
                if let Some(r) = i.res {
                    defs[r.index()] = Some((bi, ii));
                    if i.op == Op::ListLen {
                        lenof.insert(r, i.args[0]);
                    }
                }
            }
        }
        let rpo = f.rpo();
        let preds = f.predecessors();
        let idom = crate::verify::dominators(f, &rpo, &preds);
        let mut incoming: Vec<Vec<(usize, Edge, Vec<Value>)>> = vec![Vec::new(); n];
        for &b in &rpo {
            let bi = b.index();
            match &f.blocks[bi].term {
                Term::Br(t) => incoming[t.block.index()].push((bi, Edge::Plain, t.args.clone())),
                Term::CondBr { then, els, .. } => {
                    incoming[then.block.index()].push((bi, Edge::Then, then.args.clone()));
                    incoming[els.block.index()].push((bi, Edge::Else, els.args.clone()));
                }
                Term::Switch { cases, default, .. } => {
                    for (k, t) in cases {
                        incoming[t.block.index()].push((bi, Edge::Case(*k), t.args.clone()));
                    }
                    incoming[default.block.index()].push((bi, Edge::Default, default.args.clone()));
                }
                _ => {}
            }
        }
        let mut base = vec![None; f.values.len()];
        for p in &f.blocks[0].params {
            let t = f.ty(p.value);
            if tracked(t) {
                base[p.value.index()] = Some(type_top(t));
            }
        }
        Fa {
            m,
            f,
            defs,
            rpo,
            idom,
            incoming,
            base,
            envs: vec![Env::default(); n],
            widen: vec![0; f.values.len()],
            lenof,
        }
    }

    fn def_inst(&self, v: Value) -> Option<&'a Inst> {
        let (b, i) = self.defs[v.index()]?;
        Some(&self.f.blocks[b].insts[i])
    }

    fn constant(&self, v: Value) -> Option<i64> {
        let i = self.def_inst(v)?;
        match (i.op, i.imm) {
            (Op::IConst, Imm::Int(c)) => Some(c),
            _ => None,
        }
    }

    fn get(&self, v: Value, env: &Env) -> Option<Itv> {
        let b = self.base[v.index()]?;
        Some(match env.itv.get(&v) {
            Some(r) => b.meet(*r).unwrap_or(b),
            None => b,
        })
    }

    // ---- fixpoint -------------------------------------------------------

    /// Computes the fixpoint; false when it did not converge (no facts may be used).
    fn solve(&mut self) -> bool {
        let mut converged = false;
        for _ in 0..MAX_ROUNDS {
            if !self.pass(false) {
                converged = true;
                break;
            }
        }
        if !converged {
            return false;
        }
        for _ in 0..NARROW_ROUNDS {
            if !self.pass(true) {
                break;
            }
        }
        // Make envs and bases mutually consistent after the last narrowing round.
        self.pass(true);
        true
    }

    fn pass(&mut self, narrow: bool) -> bool {
        let mut changed = false;
        let rpo = self.rpo.clone();
        let f = self.f;
        for &b in &rpo {
            let bi = b.index();
            let env = self.build_env(bi);
            self.envs[bi] = env.clone();
            if bi != 0 {
                for (pi, bp) in f.blocks[bi].params.iter().enumerate() {
                    let v = bp.value;
                    if !tracked(f.ty(v)) {
                        continue;
                    }
                    let Some(new) = self.param_itv(bi, pi) else {
                        continue;
                    };
                    let old = self.base[v.index()];
                    let next = match old {
                        None => new,
                        Some(o) if narrow => o.meet(new).unwrap_or(new),
                        Some(o) => self.widen_step(v, o, new),
                    };
                    if old != Some(next) {
                        self.base[v.index()] = Some(next);
                        changed = true;
                    }
                }
            }
            for inst in &f.blocks[bi].insts {
                let Some(r) = inst.res else { continue };
                if !tracked(f.ty(r)) {
                    continue;
                }
                let Some(new) = self.eval(inst, &env) else {
                    continue;
                };
                if self.base[r.index()] != Some(new) {
                    self.base[r.index()] = Some(new);
                    changed = true;
                }
            }
        }
        changed
    }

    fn widen_step(&mut self, v: Value, old: Itv, new: Itv) -> Itv {
        let joined = old.join(new);
        if joined == old {
            return old;
        }
        let cnt = &mut self.widen[v.index()];
        *cnt += 1;
        if *cnt <= WIDEN_AFTER {
            return joined;
        }
        Itv {
            lo: if joined.lo < old.lo { i64::MIN } else { old.lo },
            hi: if joined.hi > old.hi { i64::MAX } else { old.hi },
        }
    }

    fn build_env(&self, bi: usize) -> Env {
        if bi == 0 {
            return Env::default();
        }
        let mut env = self.envs[self.idom[bi]].clone();
        if let [(p, kind, _)] = self.incoming[bi].as_slice() {
            self.apply_edge(&mut env, *p, *kind);
        }
        env
    }

    fn edge_env(&self, p: usize, kind: Edge) -> Env {
        let mut env = self.envs[p].clone();
        self.apply_edge(&mut env, p, kind);
        env
    }

    fn apply_edge(&self, env: &mut Env, p: usize, kind: Edge) {
        match (&self.f.blocks[p].term, kind) {
            (Term::CondBr { cond, .. }, Edge::Then) => self.refine_cond(*cond, true, env),
            (Term::CondBr { cond, .. }, Edge::Else) => self.refine_cond(*cond, false, env),
            (Term::Switch { value, .. }, Edge::Case(k)) if self.f.ty(*value) == Ty::INT => {
                env.narrow(*value, k as i128, k as i128)
            }
            _ => {}
        }
    }

    fn refine_cond(&self, cond: Value, truth: bool, env: &mut Env) {
        let Some(inst) = self.def_inst(cond) else {
            return;
        };
        match inst.op {
            Op::ICmp => {
                let Imm::Cc(cc) = inst.imm else { return };
                let cc = if truth { cc } else { cc.negated() };
                self.refine_cmp(cc, inst.args[0], inst.args[1], env);
            }
            Op::Not => self.refine_cond(inst.args[0], !truth, env),
            Op::And if truth => {
                self.refine_cond(inst.args[0], true, env);
                self.refine_cond(inst.args[1], true, env);
            }
            Op::Or if !truth => {
                self.refine_cond(inst.args[0], false, env);
                self.refine_cond(inst.args[1], false, env);
            }
            _ => {}
        }
    }

    fn refine_cmp(&self, cc: Cc, a: Value, b: Value, env: &mut Env) {
        let (Some(ia), Some(ib)) = (self.get(a, env), self.get(b, env)) else {
            return;
        };
        let (al, ah, bl, bh) = (ia.lo as i128, ia.hi as i128, ib.lo as i128, ib.hi as i128);
        let (min, max) = (i64::MIN as i128, i64::MAX as i128);
        match cc {
            Cc::Lt => {
                env.narrow(a, min, bh - 1);
                env.narrow(b, al + 1, max);
                env.rels.push((a, b, true));
            }
            Cc::Le => {
                env.narrow(a, min, bh);
                env.narrow(b, al, max);
                env.rels.push((a, b, false));
            }
            Cc::Gt => {
                env.narrow(a, bl + 1, max);
                env.narrow(b, min, ah - 1);
                env.rels.push((b, a, true));
            }
            Cc::Ge => {
                env.narrow(a, bl, max);
                env.narrow(b, min, ah);
                env.rels.push((b, a, false));
            }
            Cc::Eq => {
                env.narrow(a, bl, bh);
                env.narrow(b, al, ah);
                env.rels.push((a, b, false));
                env.rels.push((b, a, false));
            }
            Cc::Ne => {
                if ib.is_point() {
                    if ia.lo == ib.lo {
                        env.narrow(a, al + 1, max);
                    } else if ia.hi == ib.lo {
                        env.narrow(a, min, ah - 1);
                    }
                }
                if ia.is_point() {
                    if ib.lo == ia.lo {
                        env.narrow(b, bl + 1, max);
                    } else if ib.hi == ia.lo {
                        env.narrow(b, min, bh - 1);
                    }
                }
            }
        }
    }

    /// The constant `c` for which `a = p + c`, if `a` is such an add or subtract.
    fn step_of(&self, a: Value, p: Value) -> Option<i64> {
        let i = self.def_inst(a)?;
        match i.op {
            Op::IAdd | Op::IAddChk => {
                if i.args[0] == p {
                    self.constant(i.args[1])
                } else if i.args[1] == p {
                    self.constant(i.args[0])
                } else {
                    None
                }
            }
            Op::ISub | Op::ISubChk if i.args[0] == p => {
                self.constant(i.args[1]).and_then(|c| c.checked_neg())
            }
            _ => None,
        }
    }

    fn param_itv(&self, bi: usize, pi: usize) -> Option<Itv> {
        let p = self.f.blocks[bi].params[pi].value;
        let mut acc: Option<Itv> = None;
        let mut others: Option<Itv> = None;
        let (mut ups, mut downs, mut counter_ok) = (0, 0, true);
        for (pred, kind, args) in &self.incoming[bi] {
            let a = args[pi];
            let env = self.edge_env(*pred, *kind);
            let itv = self.get(a, &env);
            if let Some(i) = itv {
                acc = Some(acc.map_or(i, |x| x.join(i)));
            }
            if a == p {
                continue;
            }
            match self.step_of(a, p) {
                Some(s) if s != 0 && s.unsigned_abs() <= COUNTER_STEP_MAX as u64 => {
                    if s > 0 {
                        ups += 1;
                    } else {
                        downs += 1;
                    }
                }
                Some(_) => counter_ok = false,
                None => match itv {
                    Some(i) if i.lo >= -COUNTER_INIT_MAX && i.hi <= COUNTER_INIT_MAX => {
                        others = Some(others.map_or(i, |x| x.join(i)));
                    }
                    _ => counter_ok = false,
                },
            }
        }
        if ASSUME_BOUNDED_COUNTERS
            && counter_ok
            && (ups == 0) != (downs == 0)
            && let (Some(o), Some(a)) = (others, acc)
        {
            let bound = if ups > 0 {
                Itv {
                    lo: o.lo,
                    hi: i64::MAX / 2,
                }
            } else {
                Itv {
                    lo: i64::MIN / 2,
                    hi: o.hi,
                }
            };
            return Some(a.meet(bound).unwrap_or(bound));
        }
        acc
    }

    // ---- transfer function ---------------------------------------------

    fn eval(&self, inst: &Inst, env: &Env) -> Option<Itv> {
        let res = inst.res?;
        let ty = self.f.ty(res);
        if !tracked(ty) {
            return None;
        }
        let top = type_top(ty);
        let arg = |i: usize| self.get(inst.args[i], env);
        Some(match inst.op {
            Op::IConst => match inst.imm {
                Imm::Int(v) => Itv::point(v),
                _ => top,
            },
            Op::BConst => match inst.imm {
                Imm::Bool(v) => Itv::point(v as i64),
                _ => top,
            },
            Op::IAdd | Op::IAddChk => {
                let (x, y) = (arg(0)?, arg(1)?);
                let (lo, hi) = (x.lo as i128 + y.lo as i128, x.hi as i128 + y.hi as i128);
                if inst.op == Op::IAddChk {
                    Itv::clamp(lo, hi)
                } else {
                    Itv::exact(lo, hi)
                }
            }
            Op::ISub | Op::ISubChk => {
                let (x, y) = (arg(0)?, arg(1)?);
                let (lo, hi) = (x.lo as i128 - y.hi as i128, x.hi as i128 - y.lo as i128);
                if inst.op == Op::ISubChk {
                    Itv::clamp(lo, hi)
                } else {
                    Itv::exact(lo, hi)
                }
            }
            Op::IMul | Op::IMulChk => {
                let (x, y) = (arg(0)?, arg(1)?);
                let (lo, hi) = corners(|a, b| a * b, x, y);
                if inst.op == Op::IMulChk {
                    Itv::clamp(lo, hi)
                } else {
                    Itv::exact(lo, hi)
                }
            }
            Op::INeg | Op::INegChk => {
                let x = arg(0)?;
                let (lo, hi) = (-(x.hi as i128), -(x.lo as i128));
                if inst.op == Op::INegChk {
                    Itv::clamp(lo, hi)
                } else {
                    Itv::exact(lo, hi)
                }
            }
            Op::SDiv | Op::SDivChk => {
                let (x, y) = (arg(0)?, arg(1)?);
                if y.lo > 0 || y.hi < 0 {
                    let (lo, hi) = corners(|a, b| a / b, x, y);
                    Itv::clamp(lo, hi)
                } else {
                    Itv::TOP
                }
            }
            Op::SRem | Op::SRemChk => {
                let (x, y) = (arg(0)?, arg(1)?);
                let m = (y.lo as i128).abs().max((y.hi as i128).abs());
                if m == 0 {
                    return Some(Itv::TOP);
                }
                let (mut lo, mut hi) = (-(m - 1), m - 1);
                if x.lo >= 0 {
                    lo = 0;
                    hi = hi.min(x.hi as i128);
                } else if x.hi <= 0 {
                    hi = 0;
                    lo = lo.max(x.lo as i128);
                }
                Itv::clamp(lo, hi)
            }
            Op::And if ty == Ty::BOOL => {
                let (x, y) = (arg(0)?, arg(1)?);
                if x.is_point() && y.is_point() {
                    Itv::point(x.lo & y.lo)
                } else if x.hi == 0 || y.hi == 0 {
                    Itv::point(0)
                } else {
                    Itv::BOOL
                }
            }
            Op::Or if ty == Ty::BOOL => {
                let (x, y) = (arg(0)?, arg(1)?);
                if x.is_point() && y.is_point() {
                    Itv::point(x.lo | y.lo)
                } else if x.lo == 1 || y.lo == 1 {
                    Itv::point(1)
                } else {
                    Itv::BOOL
                }
            }
            Op::Xor if ty == Ty::BOOL => {
                let (x, y) = (arg(0)?, arg(1)?);
                if x.is_point() && y.is_point() {
                    Itv::point(x.lo ^ y.lo)
                } else {
                    Itv::BOOL
                }
            }
            Op::Not => {
                let x = arg(0)?;
                if x.is_point() {
                    Itv::point(1 - x.lo)
                } else {
                    Itv::BOOL
                }
            }
            Op::And => {
                let (x, y) = (arg(0)?, arg(1)?);
                match (x.lo >= 0, y.lo >= 0) {
                    (true, true) => Itv {
                        lo: 0,
                        hi: x.hi.min(y.hi),
                    },
                    (true, false) => Itv { lo: 0, hi: x.hi },
                    (false, true) => Itv { lo: 0, hi: y.hi },
                    _ => Itv::TOP,
                }
            }
            Op::Or | Op::Xor => {
                let (x, y) = (arg(0)?, arg(1)?);
                if x.lo >= 0 && y.lo >= 0 {
                    let m = x.hi.max(y.hi) as u64;
                    let hi = if m == 0 {
                        0
                    } else {
                        (u64::MAX >> m.leading_zeros()) as i64
                    };
                    Itv { lo: 0, hi }
                } else {
                    Itv::TOP
                }
            }
            Op::Sshr => {
                let (x, y) = (arg(0)?, arg(1)?);
                if y.is_point() && (0..64).contains(&y.lo) {
                    Itv {
                        lo: x.lo >> y.lo,
                        hi: x.hi >> y.lo,
                    }
                } else {
                    Itv::TOP
                }
            }
            Op::ICmp => {
                let Imm::Cc(cc) = inst.imm else {
                    return Some(top);
                };
                if !tracked(self.f.ty(inst.args[0])) || !tracked(self.f.ty(inst.args[1])) {
                    return Some(top);
                }
                let (x, y) = (arg(0)?, arg(1)?);
                match self.decide(cc, inst.args[0], inst.args[1], x, y, env) {
                    Some(b) => Itv::point(b as i64),
                    None => Itv::BOOL,
                }
            }
            // A runtime status is a `u8` typed `bool`: the widened value is not limited to 0 or 1.
            Op::B2I => Itv { lo: 0, hi: 255 },
            Op::Select => {
                let (c, x, y) = (arg(0)?, arg(1)?, arg(2)?);
                if c.is_point() {
                    if c.lo != 0 { x } else { y }
                } else {
                    x.join(y)
                }
            }
            Op::ListLen | Op::StrLen => Itv { lo: 0, hi: LEN_MAX },
            Op::AltTag => match self.m.types.kind(self.f.ty(inst.args[0])) {
                TyKind::Alt(a) => {
                    let n = self.m.alts[a.index()].cases.len() as i64;
                    Itv {
                        lo: 0,
                        hi: (n - 1).max(0),
                    }
                }
                _ => top,
            },
            _ => top,
        })
    }

    /// `(a < b, a <= b)` as far as recorded relations and identity prove.
    fn rel_known(&self, a: Value, b: Value, env: &Env) -> (bool, bool) {
        let mut lt = false;
        let mut le = a == b;
        for &(x, y, strict) in &env.rels {
            if x == a && y == b {
                lt |= strict;
                le = true;
            }
        }
        (lt, le)
    }

    fn decide(&self, cc: Cc, a: Value, b: Value, x: Itv, y: Itv, env: &Env) -> Option<bool> {
        let (lt, le) = self.rel_known(a, b, env);
        let (gt, ge) = self.rel_known(b, a, env);
        let (ilt, ile) = (x.hi < y.lo, x.hi <= y.lo);
        let (igt, ige) = (x.lo > y.hi, x.lo >= y.hi);
        let eq_true = (x.is_point() && y.is_point() && x.lo == y.lo) || a == b;
        let ne_true = ilt || igt || lt || gt;
        match cc {
            Cc::Lt if ilt || lt => Some(true),
            Cc::Lt if ige || ge => Some(false),
            Cc::Le if ile || le => Some(true),
            Cc::Le if igt || gt => Some(false),
            Cc::Gt if igt || gt => Some(true),
            Cc::Gt if ile || le => Some(false),
            Cc::Ge if ige || ge => Some(true),
            Cc::Ge if ilt || lt => Some(false),
            Cc::Eq if eq_true => Some(true),
            Cc::Eq if ne_true => Some(false),
            Cc::Ne if ne_true => Some(true),
            Cc::Ne if eq_true => Some(false),
            _ => None,
        }
    }

    // ---- rewrites -------------------------------------------------------

    /// Proves `idx < list.len l` from recorded relations, following `<=`/`<` chains
    /// and `x - c` (c > 0) definitions.
    fn below_len(&self, idx: Value, l: Value, env: &Env) -> bool {
        let mut seen: Vec<(Value, bool)> = vec![(idx, false)];
        let mut i = 0;
        while i < seen.len() {
            let (v, strict) = seen[i];
            i += 1;
            if strict && self.lenof.get(&v) == Some(&l) {
                return true;
            }
            let mut next: Vec<(Value, bool)> = Vec::new();
            for &(a, b, s) in &env.rels {
                if a == v {
                    next.push((b, strict || s));
                }
            }
            if let Some(d) = self.def_inst(v)
                && matches!(d.op, Op::ISub | Op::ISubChk)
                && let Some(c) = self.constant(d.args[1]).filter(|c| *c > 0)
            {
                let safe = d.op == Op::ISubChk
                    || self
                        .get(d.args[0], env)
                        .is_some_and(|x| x.lo >= i64::MIN + c);
                if safe {
                    next.push((d.args[0], true));
                }
            }
            for n in next {
                if !seen.contains(&n) {
                    seen.push(n);
                }
            }
        }
        false
    }

    fn edits(&self) -> Vec<Edit> {
        let mut out = Vec::new();
        let f = self.f;
        for &b in &self.rpo {
            let bi = b.index();
            let env = &self.envs[bi];
            for (ii, inst) in f.blocks[bi].insts.iter().enumerate() {
                let get = |k: usize| self.get(inst.args[k], env);
                match inst.op {
                    Op::IAddChk | Op::ISubChk | Op::IMulChk => {
                        let (Some(x), Some(y)) = (get(0), get(1)) else {
                            continue;
                        };
                        let (lo, hi) = match inst.op {
                            Op::IAddChk => {
                                (x.lo as i128 + y.lo as i128, x.hi as i128 + y.hi as i128)
                            }
                            Op::ISubChk => {
                                (x.lo as i128 - y.hi as i128, x.hi as i128 - y.lo as i128)
                            }
                            _ => corners(|a, b| a * b, x, y),
                        };
                        if fits(lo, hi) {
                            let op = match inst.op {
                                Op::IAddChk => Op::IAdd,
                                Op::ISubChk => Op::ISub,
                                _ => Op::IMul,
                            };
                            out.push(Edit::Op(bi, ii, op));
                        }
                    }
                    Op::INegChk => {
                        if get(0).is_some_and(|x| x.lo != i64::MIN) {
                            out.push(Edit::Op(bi, ii, Op::INeg));
                        }
                    }
                    Op::SDivChk | Op::SRemChk => {
                        let (Some(x), Some(y)) = (get(0), get(1)) else {
                            continue;
                        };
                        let nonzero = y.lo > 0 || y.hi < 0;
                        let minus_one = y.lo <= -1 && -1 <= y.hi;
                        if nonzero && (!minus_one || x.lo > i64::MIN) {
                            let op = if inst.op == Op::SDivChk {
                                Op::SDiv
                            } else {
                                Op::SRem
                            };
                            out.push(Edit::Op(bi, ii, op));
                        }
                    }
                    Op::ListGet | Op::ListGetNn | Op::ListSet | Op::ListSetNn => {
                        let Some(idx) = get(1) else { continue };
                        let nonneg = idx.lo >= 0;
                        let inside = nonneg && self.below_len(inst.args[1], inst.args[0], env);
                        let set = matches!(inst.op, Op::ListSet | Op::ListSetNn);
                        let target = if inside {
                            Some(if set { Op::ListSetU } else { Op::ListGetU })
                        } else if nonneg && matches!(inst.op, Op::ListGet | Op::ListSet) {
                            Some(if set { Op::ListSetNn } else { Op::ListGetNn })
                        } else {
                            None
                        };
                        if let Some(op) = target {
                            out.push(Edit::Op(bi, ii, op));
                        }
                    }
                    Op::ICmp => {
                        let decided = inst
                            .res
                            .and_then(|r| self.base[r.index()])
                            .filter(|r| r.is_point());
                        if let Some(r) = decided {
                            out.push(Edit::Const(bi, ii, r.lo != 0));
                        }
                    }
                    _ => {}
                }
            }
            if let Some(t) = self.fold_term(&f.blocks[bi].term, env) {
                out.push(Edit::Term(bi, t));
            }
        }
        out
    }

    fn fold_term(&self, term: &Term, env: &Env) -> Option<Term> {
        match term {
            Term::CondBr { cond, then, els } => {
                let c = self.get(*cond, env)?;
                if !c.is_point() {
                    return None;
                }
                Some(Term::Br(if c.lo != 0 { then.clone() } else { els.clone() }))
            }
            Term::Switch {
                value,
                cases,
                default,
            } => {
                let v = self.get(*value, env)?;
                if v.is_point() {
                    let t = cases
                        .iter()
                        .find(|(k, _)| *k == v.lo)
                        .map_or(default, |(_, t)| t);
                    return Some(Term::Br(t.clone()));
                }
                let kept: Vec<(i64, Target)> = cases
                    .iter()
                    .filter(|(k, _)| v.lo <= *k && *k <= v.hi)
                    .cloned()
                    .collect();
                if kept.len() == cases.len() {
                    return None;
                }
                Some(if kept.is_empty() {
                    Term::Br(default.clone())
                } else {
                    Term::Switch {
                        value: *value,
                        cases: kept,
                        default: default.clone(),
                    }
                })
            }
            _ => None,
        }
    }
}
