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
//!   values threaded through mutators. Element replacement preserves length, including
//!   through loop parameters whose incoming lists all have the same length origin.
//!   Length-changing operations and fresh memory reads start new origins.
//! * `idx < list.len l` is proved by a goal-directed search (`prove_le`) over those
//!   relations and the definitions of the values involved: constant and ranged offsets
//!   (`a[i + 1]` under `i < len - 1`, `a[len - 1 - i]`), division and scaling
//!   (`a[i * 3 + 2]` under `i < len / 3`), and loop parameters by induction (a binary
//!   search whose `hi` starts at `len - 1`).
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
use std::collections::{HashMap, HashSet};

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
    Int(usize, usize, i64),
    Term(usize, Term),
}

/// What a proved upper bound is measured against.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Goal {
    /// The length of lists with this length origin.
    Len(Value),
    /// An SSA value.
    Val(Value),
}

/// Proof-search budget per query.
const PROOF_FUEL: u32 = 200;

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
    lenof: LenOf,
    lengths: Vec<Value>,
    byte_lists: Vec<bool>,
    /// Block and index of the block parameter that defines a value.
    param_of: Vec<Option<(usize, usize)>>,
    /// Reverse-postorder position of the last block that reads each value, by [`Fa::class`].
    /// A fact about a value no block at or after a position reads is dropped from the
    /// environments built there, so they stay as large as what is live, not as large as the
    /// dominating code (a chain of many loops would otherwise make the pass quadratic).
    last_read: Vec<u32>,
    rpo_pos: Vec<u32>,
}

/// The length origin of each `list.len` result. Queried at every proof step, so a table
/// indexed by value, not a hash map.
struct LenOf(Vec<Option<Value>>);

impl LenOf {
    fn insert(&mut self, v: Value, origin: Value) {
        self.0[v.index()] = Some(origin);
    }

    fn get(&self, v: &Value) -> Option<&Value> {
        self.0[v.index()].as_ref()
    }
}

/// A list length can flow through replacement and block arguments without its
/// elements flowing with it. Each fact changes at most twice, so this worklist
/// also handles nested loops without rescanning the function to a fixpoint.
///
/// A list held in a record field is tracked the same way: a node for each list field of each
/// record value follows `rec.new`, `rec.fill`/`rec.set` (the written field takes the written list,
/// the other fields keep theirs), copies and block arguments, so reading the field of a record
/// that was updated in a loop yields lists of one length origin. Records of unknown provenance
/// (parameters, loads, call results) start each field at the first read of it, which is why
/// repeated reads of one record must already be one value (see `simplify::cse`).
fn length_origins(m: &Module, f: &Func) -> Vec<Value> {
    #[derive(Clone, Copy, PartialEq, Eq)]
    enum Origin {
        Unknown,
        One(Value),
        Mixed,
    }
    let nv = f.values.len();
    let is_list = |v: Value| matches!(m.types.kind(f.ty(v)), TyKind::List(_));
    let list_fields = |v: Value| -> Vec<u32> {
        let TyKind::Rec(rid) = m.types.kind(f.ty(v)) else {
            return Vec::new();
        };
        m.records[rid.0 as usize]
            .fields
            .iter()
            .enumerate()
            .filter(|(_, (_, t))| matches!(m.types.kind(*t), TyKind::List(_)))
            .map(|(k, _)| k as u32)
            .collect()
    };
    // One node per list value, then one per list field of each record value.
    let mut pair: HashMap<(Value, u32), usize> = HashMap::new();
    let mut total = nv;
    for i in 0..nv {
        let v = Value(i as u32);
        for k in list_fields(v) {
            pair.insert((v, k), total);
            total += 1;
        }
    }
    let mut facts = vec![Origin::Unknown; total];
    let mut users = vec![Vec::new(); total];
    let mut work = Vec::new();
    let mut reads: HashMap<(Value, Value), Value> = HashMap::new();
    // The first read of each record field, the origin of a field nothing else defines.
    let mut first_field_read: HashMap<(Value, u32), Value> = HashMap::new();
    // Record values whose list fields come from other nodes rather than starting fresh.
    let mut flows: Vec<bool> = vec![false; nv];
    let edge = |users: &mut Vec<Vec<usize>>, from: usize, to: usize| users[from].push(to);
    for b in f.blocks.iter().skip(1) {
        for p in &b.params {
            flows[p.value.index()] = true;
        }
    }
    for p in &f.blocks[0].params {
        if is_list(p.value) {
            facts[p.value.index()] = Origin::One(p.value);
            work.push(p.value.index());
        }
    }
    for b in &f.blocks {
        for i in &b.insts {
            let Some(r) = i.res else { continue };
            match i.op {
                Op::RecNew => {
                    flows[r.index()] = true;
                    let Imm::Rec(rid) = i.imm else { continue };
                    for (k, (_, t)) in m.records[rid.0 as usize].fields.iter().enumerate() {
                        if matches!(m.types.kind(*t), TyKind::List(_))
                            && let Some(&to) = pair.get(&(r, k as u32))
                        {
                            edge(&mut users, i.args[k].index(), to);
                        }
                    }
                    continue;
                }
                Op::RecFill | Op::RecSet => {
                    flows[r.index()] = true;
                    let Imm::Field(_, written) = i.imm else {
                        continue;
                    };
                    for k in list_fields(r) {
                        let Some(&to) = pair.get(&(r, k)) else {
                            continue;
                        };
                        if k == written {
                            edge(&mut users, i.args[1].index(), to);
                        } else if let Some(&from) = pair.get(&(i.args[0], k)) {
                            edge(&mut users, from, to);
                        }
                    }
                    continue;
                }
                Op::Copy if !list_fields(r).is_empty() => {
                    flows[r.index()] = true;
                    for k in list_fields(r) {
                        if let (Some(&to), Some(&from)) =
                            (pair.get(&(r, k)), pair.get(&(i.args[0], k)))
                        {
                            edge(&mut users, from, to);
                        }
                    }
                    continue;
                }
                Op::RecGet if is_list(r) => {
                    let Imm::Field(_, k) = i.imm else { continue };
                    first_field_read.entry((i.args[0], k)).or_insert(r);
                    if let Some(&from) = pair.get(&(i.args[0], k)) {
                        edge(&mut users, from, r.index());
                    }
                    continue;
                }
                _ => {}
            }
            if !is_list(r) {
                continue;
            }
            if matches!(
                i.op,
                Op::ListSet | Op::ListSetNn | Op::ListSetU | Op::ListFill | Op::MoveOut | Op::Copy
            ) {
                edge(&mut users, i.args[0].index(), r.index());
            } else {
                // Reading the same element of the same (immutable) list twice yields lists of
                // one length.
                let origin = match i.op {
                    Op::ListGet | Op::ListGetNn | Op::ListGetU => {
                        *reads.entry((i.args[0], i.args[1])).or_insert(r)
                    }
                    _ => r,
                };
                facts[r.index()] = Origin::One(origin);
                work.push(r.index());
            }
        }
        b.term.for_each_target(|t| {
            for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                if is_list(p.value) {
                    edge(&mut users, a.index(), p.value.index());
                }
                for k in list_fields(p.value) {
                    if let (Some(&from), Some(&to)) = (pair.get(&(*a, k)), pair.get(&(p.value, k)))
                    {
                        edge(&mut users, from, to);
                    }
                }
            }
        });
    }
    // Record values nothing flows into start every list field at its first read, or at the record
    // itself when the field is never read (a value no list shares an origin with).
    for (&(r, k), &node) in &pair {
        if !flows[r.index()] {
            facts[node] = Origin::One(first_field_read.get(&(r, k)).copied().unwrap_or(r));
            work.push(node);
        }
    }
    while let Some(v) = work.pop() {
        for &u in &users[v] {
            let old = facts[u];
            let new = match (old, facts[v]) {
                (Origin::Unknown, x) => x,
                (Origin::One(a), Origin::One(b)) if a == b => old,
                _ => Origin::Mixed,
            };
            if new != old {
                facts[u] = new;
                work.push(u);
            }
        }
    }
    facts
        .into_iter()
        .take(nv)
        .enumerate()
        .map(|(i, fact)| match fact {
            Origin::One(v) => v,
            _ => Value(i as u32),
        })
        .collect()
}

/// Lists whose elements all lie in `0..=255` because they came from `Bytes.values()`.
///
/// A list value is immutable: `list.set` and the other mutators return a new value, which
/// is not marked. A block parameter qualifies when every incoming argument does, so the
/// fact survives loops that thread the list around unchanged. The analysis starts
/// optimistic for non-entry parameters and removes the ones an edge disproves.
fn byte_lists(m: &Module, f: &Func) -> Vec<bool> {
    let mut facts = vec![false; f.values.len()];
    let is_list = |v: Value| matches!(m.types.kind(f.ty(v)), TyKind::List(_));
    for b in &f.blocks {
        for i in &b.insts {
            if let (Op::CallRt, Imm::Ext(e), Some(r)) = (i.op, i.imm, i.res)
                && m.externs[e.index()].name == "msrt_bytes_values"
            {
                facts[r.index()] = true;
            }
        }
    }
    for b in f.blocks.iter().skip(1) {
        for p in &b.params {
            if is_list(p.value) {
                facts[p.value.index()] = true;
            }
        }
    }
    let mut incoming = vec![0u32; f.blocks.len()];
    for b in &f.blocks {
        b.term.for_each_target(|t| incoming[t.block.index()] += 1);
    }
    for (bi, b) in f.blocks.iter().enumerate().skip(1) {
        if incoming[bi] == 0 {
            for p in &b.params {
                facts[p.value.index()] = false;
            }
        }
    }
    let mut changed = true;
    while changed {
        changed = false;
        for b in &f.blocks {
            b.term.for_each_target(|t| {
                for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                    if is_list(p.value) && facts[p.value.index()] && !facts[a.index()] {
                        facts[p.value.index()] = false;
                        changed = true;
                    }
                }
            });
        }
    }
    facts
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
                Edit::Int(b, i, v) => {
                    let inst = &mut f.blocks[b].insts[i];
                    inst.op = Op::IConst;
                    inst.args.clear();
                    inst.imm = Imm::Int(v);
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

/// `UInt64` values are tracked as the unsigned range they provably lie in when it stays within
/// `0..=i64::MAX`; any interval that dips below zero stands for "every `u64`" (see [`unsigned`]).
fn tracked(ty: Ty) -> bool {
    ty == Ty::INT || ty == Ty::BOOL || ty == Ty::UINT64
}

/// Reads an interval for a value of type `ty`: a `UInt64` interval with a negative bound is the
/// bit pattern of a value above `i64::MAX` and carries no information.
fn unsigned(ty: Ty, itv: Itv) -> Itv {
    if ty == Ty::UINT64 && itv.lo < 0 {
        Itv::TOP
    } else {
        itv
    }
}

fn type_top(ty: Ty) -> Itv {
    if ty == Ty::BOOL { Itv::BOOL } else { Itv::TOP }
}

impl<'a> Fa<'a> {
    fn new(m: &'a Module, f: &'a Func) -> Self {
        let n = f.blocks.len();
        let lengths = length_origins(m, f);
        let byte_lists = byte_lists(m, f);
        let mut defs = vec![None; f.values.len()];
        let mut lenof = LenOf(vec![None; f.values.len()]);
        for (bi, b) in f.blocks.iter().enumerate() {
            for (ii, i) in b.insts.iter().enumerate() {
                if let Some(r) = i.res {
                    defs[r.index()] = Some((bi, ii));
                    if i.op == Op::ListLen {
                        lenof.insert(r, lengths[i.args[0].index()]);
                    }
                }
            }
        }
        let mut param_of = vec![None; f.values.len()];
        for (bi, b) in f.blocks.iter().enumerate().skip(1) {
            for (pi, p) in b.params.iter().enumerate() {
                param_of[p.value.index()] = Some((bi, pi));
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
        let mut rpo_pos = vec![0u32; n];
        for (pos, b) in rpo.iter().enumerate() {
            rpo_pos[b.index()] = pos as u32;
        }
        let class = |v: Value| lenof.get(&v).map_or(v.index(), |o: &Value| o.index());
        let mut last_read = vec![0u32; f.values.len()];
        for &b in &rpo {
            let pos = rpo_pos[b.index()];
            let blk = &f.blocks[b.index()];
            let mut read = |v: Value| {
                let slot = &mut last_read[class(v)];
                *slot = (*slot).max(pos);
            };
            blk.insts
                .iter()
                .for_each(|i| i.args.iter().for_each(|&a| read(a)));
            blk.term.for_each_use(&mut read);
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
            lengths,
            byte_lists,
            param_of,
            last_read,
            rpo_pos,
        }
    }

    fn class(&self, v: Value) -> usize {
        self.lenof.get(&v).map_or(v.index(), |o| o.index())
    }

    /// Drops what `env` knows about values that no block from `bi` on reads.
    fn prune(&self, env: &mut Env, bi: usize) {
        let pos = self.rpo_pos[bi];
        let live = |v: &Value| self.last_read[self.class(*v)] >= pos;
        env.itv.retain(|v, _| live(v));
        // `a < b` serves a proof that reaches `b` from a live value and goes on from there, so it
        // stays when `b` is live or when `b` starts another kept relation. `0 < len` for every
        // earlier version of a list would otherwise outlive the lists.
        let starts: HashSet<usize> = env
            .rels
            .iter()
            .filter(|(_, b, _)| live(b))
            .map(|(a, ..)| self.class(*a))
            .collect();
        env.rels
            .retain(|(a, b, _)| live(b) || (live(a) && starts.contains(&self.class(*b))));
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

    fn list_length(&self, v: Value) -> Option<i64> {
        let d = self.def_inst(self.lengths[v.index()])?;
        match d.op {
            Op::ListLit => i64::try_from(d.args.len()).ok(),
            // Capacity does not change a new list's initially empty length.
            Op::ListNew => Some(0),
            _ => None,
        }
    }

    fn get(&self, v: Value, env: &Env) -> Option<Itv> {
        let ty = self.f.ty(v);
        let b = unsigned(ty, self.base[v.index()]?);
        Some(match env.itv.get(&v) {
            Some(r) => b.meet(unsigned(ty, *r)).unwrap_or(b),
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
        self.prune(&mut env, bi);
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
            Op::UICmp => {
                let Imm::Cc(cc) = inst.imm else { return };
                let cc = if truth { cc } else { cc.negated() };
                self.refine_ucmp(cc, inst.args[0], inst.args[1], env);
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

    /// Unsigned `a cc b`: the smaller side is bounded by the larger side's known upper bound.
    /// The larger side gains no usable lower bound, as its upper end may pass `i64::MAX`.
    fn refine_ucmp(&self, cc: Cc, a: Value, b: Value, env: &mut Env) {
        let (Some(ia), Some(ib)) = (self.get(a, env), self.get(b, env)) else {
            return;
        };
        let bound = |itv: Itv| (itv.lo >= 0).then_some(itv.hi as i128);
        match cc {
            Cc::Lt => bound(ib).map(|h| env.narrow(a, 0, h - 1)),
            Cc::Le => bound(ib).map(|h| env.narrow(a, 0, h)),
            Cc::Gt => bound(ia).map(|h| env.narrow(b, 0, h - 1)),
            Cc::Ge => bound(ia).map(|h| env.narrow(b, 0, h)),
            Cc::Eq | Cc::Ne => None,
        };
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
            // A conditional step (`if c { p += k }` after if-conversion) steps by `k` or not at all.
            Op::Select => {
                let arm = |v: Value| if v == p { Some(0) } else { self.step_of(v, p) };
                match (arm(i.args[1])?, arm(i.args[2])?) {
                    (0, s) | (s, 0) if s != 0 => Some(s),
                    (x, y) if x == y && x != 0 => Some(x),
                    _ => None,
                }
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
            Op::UAddChk | Op::USubChk | Op::UMulChk => {
                let (x, y) = (arg(0)?, arg(1)?);
                if x.lo < 0 || y.lo < 0 {
                    return Some(Itv::TOP);
                }
                let (lo, hi) = match inst.op {
                    Op::UAddChk => (x.lo as i128 + y.lo as i128, x.hi as i128 + y.hi as i128),
                    // A faulting subtraction leaves a difference between zero and `x`.
                    Op::USubChk => ((x.lo as i128 - y.hi as i128).max(0), x.hi as i128),
                    _ => corners(|a, b| a * b, x, y),
                };
                Itv::exact(lo, hi)
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
            Op::ListLen => self
                .list_length(inst.args[0])
                .map_or(Itv { lo: 0, hi: LEN_MAX }, Itv::point),
            Op::ListGet | Op::ListGetNn | Op::ListGetU if self.byte_lists[inst.args[0].index()] => {
                Itv { lo: 0, hi: 255 }
            }
            Op::StrLen => Itv { lo: 0, hi: LEN_MAX },
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
        let mut le = self.same_value(a, b);
        for &(x, y, strict) in &env.rels {
            if self.same_value(x, a) && self.same_value(y, b) {
                lt |= strict;
                le = true;
            }
        }
        (lt, le)
    }

    fn same_value(&self, a: Value, b: Value) -> bool {
        a == b
            || self
                .lenof
                .get(&a)
                .is_some_and(|l| self.lenof.get(&b) == Some(l))
    }

    fn decide(&self, cc: Cc, a: Value, b: Value, x: Itv, y: Itv, env: &Env) -> Option<bool> {
        let (lt, le) = self.rel_known(a, b, env);
        let (gt, ge) = self.rel_known(b, a, env);
        let (ilt, ile) = (x.hi < y.lo, x.hi <= y.lo);
        let (igt, ige) = (x.lo > y.hi, x.lo >= y.hi);
        let eq_true = (x.is_point() && y.is_point() && x.lo == y.lo) || self.same_value(a, b);
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

    /// Proves `idx < list.len l` from recorded relations.
    fn below_len(&self, idx: Value, l: Value, env: &Env) -> bool {
        if let (Some(i), Some(n)) = (self.get(idx, env), self.list_length(l))
            && i.hi < n
        {
            return true;
        }
        let goal = Goal::Len(self.lengths[l.index()]);
        self.prove_le(idx, goal, -1, env, &mut Vec::new(), &mut { PROOF_FUEL })
    }

    /// Proves `idx >= 0` where the interval alone cannot, for `idx = x - y` with `y <= x`.
    fn nonneg(&self, idx: Value, env: &Env) -> bool {
        if self.get(idx, env).is_some_and(|i| i.lo >= 0) {
            return true;
        }
        let Some(d) = self.def_inst(idx) else {
            return false;
        };
        match d.op {
            Op::ISub | Op::ISubChk if self.no_wrap(d, env) => self.prove_le(
                d.args[1],
                Goal::Val(d.args[0]),
                0,
                env,
                &mut Vec::new(),
                &mut { PROOF_FUEL },
            ),
            _ => false,
        }
    }

    /// Whether the add, subtract or multiply `d` computes the exact integer result.
    fn no_wrap(&self, d: &Inst, env: &Env) -> bool {
        if matches!(d.op, Op::IAddChk | Op::ISubChk | Op::IMulChk) {
            return true;
        }
        let (Some(x), Some(y)) = (self.get(d.args[0], env), self.get(d.args[1], env)) else {
            return false;
        };
        let (lo, hi) = match d.op {
            Op::IAdd => (x.lo as i128 + y.lo as i128, x.hi as i128 + y.hi as i128),
            Op::ISub => (x.lo as i128 - y.hi as i128, x.hi as i128 - y.lo as i128),
            Op::IMul => corners(|a, b| a * b, x, y),
            _ => return false,
        };
        fits(lo, hi)
    }

    fn goal_matches(&self, v: Value, goal: Goal) -> bool {
        match goal {
            Goal::Val(t) => v == t || self.same_value(v, t),
            Goal::Len(o) => self.lenof.get(&v) == Some(&o),
        }
    }

    /// Folds a constant offset in the goal value into `d`: `v <= (x + c) + d` is `v <= x + (c + d)`.
    fn normalize_goal(&self, goal: Goal, d: i128, env: &Env) -> (Goal, i128) {
        let (mut goal, mut d) = (goal, d);
        for _ in 0..4 {
            let Goal::Val(t) = goal else { break };
            let Some(def) = self.def_inst(t) else { break };
            let step = match def.op {
                Op::IAdd | Op::IAddChk | Op::ISub | Op::ISubChk if self.no_wrap(def, env) => {
                    let sub = matches!(def.op, Op::ISub | Op::ISubChk);
                    match (self.constant(def.args[1]), self.constant(def.args[0])) {
                        (Some(c), _) => {
                            Some((def.args[0], if sub { -(c as i128) } else { c as i128 }))
                        }
                        (None, Some(c)) if !sub => Some((def.args[1], c as i128)),
                        _ => None,
                    }
                }
                _ => None,
            };
            let Some((x, c)) = step else { break };
            goal = Goal::Val(x);
            d += c;
        }
        (goal, d)
    }

    /// Proves `v <= goal + d` from intervals, recorded relations and the definitions of
    /// the values involved. A loop parameter is proved by induction: assuming the bound,
    /// every incoming argument must meet it too.
    fn prove_le(
        &self,
        v: Value,
        goal: Goal,
        d: i128,
        env: &Env,
        assumed: &mut Vec<(Value, Goal, i128)>,
        fuel: &mut u32,
    ) -> bool {
        if *fuel == 0 {
            return false;
        }
        *fuel -= 1;
        let (goal, d) = self.normalize_goal(goal, d, env);
        if self.goal_matches(v, goal) && d >= 0 {
            return true;
        }
        if let Some(i) = self.get(v, env) {
            let floor = match goal {
                Goal::Val(t) => self.get(t, env).map(|g| g.lo as i128),
                Goal::Len(_) => Some(0),
            };
            if floor.is_some_and(|f| i.hi as i128 <= f + d) {
                return true;
            }
        }
        if assumed
            .iter()
            .any(|&(av, ag, ad)| av == v && ag == goal && ad <= d)
        {
            return true;
        }
        for &(a, b, strict) in &env.rels {
            if self.same_value(a, v)
                && self.prove_le(b, goal, d + strict as i128, env, assumed, fuel)
            {
                return true;
            }
        }
        if let Some((bi, pi)) = self.param_of[v.index()]
            && !self.incoming[bi].is_empty()
        {
            assumed.push((v, goal, d));
            let all = self.incoming[bi].iter().all(|(pred, kind, args)| {
                let edge = self.edge_env(*pred, *kind);
                self.prove_le(args[pi], goal, d, &edge, assumed, fuel)
            });
            assumed.pop();
            if all {
                return true;
            }
        }
        let Some(def) = self.def_inst(v) else {
            return false;
        };
        let hi_of = |x: Value| self.get(x, env).map(|i| i.hi as i128);
        let lo_of = |x: Value| self.get(x, env).map(|i| i.lo as i128);
        match def.op {
            Op::IAdd | Op::IAddChk if self.no_wrap(def, env) => {
                let (x, y) = (def.args[0], def.args[1]);
                hi_of(y).is_some_and(|h| self.prove_le(x, goal, d - h, env, assumed, fuel))
                    || hi_of(x).is_some_and(|h| self.prove_le(y, goal, d - h, env, assumed, fuel))
            }
            Op::ISub | Op::ISubChk if self.no_wrap(def, env) => {
                let (x, y) = (def.args[0], def.args[1]);
                lo_of(y).is_some_and(|l| self.prove_le(x, goal, d + l, env, assumed, fuel))
            }
            Op::SDiv | Op::SDivChk => {
                let (x, c) = (def.args[0], self.constant(def.args[1]));
                c.is_some_and(|c| c >= 1)
                    && lo_of(x).is_some_and(|l| l >= 0)
                    && self.prove_le(x, goal, d, env, assumed, fuel)
            }
            Op::SRem | Op::SRemChk => {
                let (x, y) = (def.args[0], def.args[1]);
                lo_of(x).is_some_and(|l| l >= 0)
                    && lo_of(y).is_some_and(|l| l >= 1)
                    && (self.prove_le(x, goal, d, env, assumed, fuel)
                        || self.prove_le(y, goal, d + 1, env, assumed, fuel))
            }
            Op::And => {
                let (x, y) = (def.args[0], def.args[1]);
                (lo_of(x).is_some_and(|l| l >= 0) && self.prove_le(x, goal, d, env, assumed, fuel))
                    || (lo_of(y).is_some_and(|l| l >= 0)
                        && self.prove_le(y, goal, d, env, assumed, fuel))
            }
            Op::Select => {
                self.prove_le(def.args[1], goal, d, env, assumed, fuel)
                    && self.prove_le(def.args[2], goal, d, env, assumed, fuel)
            }
            Op::IMul | Op::IMulChk if self.no_wrap(def, env) => {
                self.prove_scaled(def, goal, d, env)
            }
            _ => false,
        }
    }

    /// `u * c <= goal + d` from `u < goal / c` (or `<=`): `(goal / c) * c <= goal` for `goal >= 0`.
    fn prove_scaled(&self, def: &Inst, goal: Goal, d: i128, env: &Env) -> bool {
        let (u, c) = match (self.constant(def.args[1]), self.constant(def.args[0])) {
            (Some(c), _) => (def.args[0], c),
            (None, Some(c)) => (def.args[1], c),
            _ => return false,
        };
        if c < 1 {
            return false;
        }
        for &(a, b, strict) in &env.rels {
            if !self.same_value(a, u) {
                continue;
            }
            let Some(q) = self.def_inst(b) else { continue };
            if !matches!(q.op, Op::SDiv | Op::SDivChk) || self.constant(q.args[1]) != Some(c) {
                continue;
            }
            let x = q.args[0];
            let same = match goal {
                Goal::Val(t) => x == t,
                Goal::Len(o) => self.lenof.get(&x) == Some(&o),
            };
            if same
                && self.get(x, env).is_some_and(|i| i.lo >= 0)
                && -(strict as i128) * c as i128 <= d
            {
                return true;
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
                    Op::ListLen => {
                        if let Some(n) = self.list_length(inst.args[0]) {
                            out.push(Edit::Int(bi, ii, n));
                        }
                    }
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
                    Op::UAddChk | Op::USubChk | Op::UMulChk => {
                        let (Some(x), Some(y)) = (get(0), get(1)) else {
                            continue;
                        };
                        if x.lo < 0 || y.lo < 0 {
                            continue;
                        }
                        let (safe, op) = match inst.op {
                            Op::UAddChk => (
                                fits(x.lo as i128 + y.lo as i128, x.hi as i128 + y.hi as i128),
                                Op::IAdd,
                            ),
                            Op::USubChk => (x.lo >= y.hi, Op::ISub),
                            _ => {
                                let (lo, hi) = corners(|a, b| a * b, x, y);
                                (fits(lo, hi), Op::IMul)
                            }
                        };
                        if safe {
                            out.push(Edit::Op(bi, ii, op));
                        }
                    }
                    Op::IAddOverflow | Op::IMulOverflow => {
                        let (Some(x), Some(y)) = (get(0), get(1)) else {
                            continue;
                        };
                        let (lo, hi) = if inst.op == Op::IAddOverflow {
                            (x.lo as i128 + y.lo as i128, x.hi as i128 + y.hi as i128)
                        } else {
                            corners(|a, b| a * b, x, y)
                        };
                        if fits(lo, hi) {
                            out.push(Edit::Const(bi, ii, false));
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
                        if get(1).is_none() {
                            continue;
                        }
                        let nonneg = self.nonneg(inst.args[1], env);
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
                    Op::ListAddr => {
                        if self.get(inst.args[1], env).is_none() {
                            continue;
                        }
                        if self.nonneg(inst.args[1], env)
                            && self.below_len(inst.args[1], inst.args[0], env)
                        {
                            out.push(Edit::Op(bi, ii, Op::ListAddrU));
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
