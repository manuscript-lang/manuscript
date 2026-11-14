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
//!   same comparisons type relations `a < b` / `a <= b` between SSA values, used to
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

mod prove;

/// Whether bounded loop counters are assumed not to overflow (see the module docs).
pub const ASSUME_BOUNDED_COUNTERS: bool = true;

const COUNTER_STEP_MAX: i64 = 1 << 16;
const COUNTER_INIT_MAX: i64 = 1 << 40;
const LEN_MAX: i64 = 1 << 47;
const WIDEN_AFTER: u32 = 3;
/// The bound a growing interval widens to before the type bound (`2^56`).
const WIDEN_LIMIT: i64 = 1 << 56;
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

fn cmp_holds(cc: Cc, a: i64, b: i64) -> bool {
    match cc {
        Cc::Lt => a < b,
        Cc::Le => a <= b,
        Cc::Gt => a > b,
        Cc::Ge => a >= b,
        Cc::Eq => a == b,
        Cc::Ne => a != b,
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
        // Disjoint intervals mean the path is dead, or that `cur` is still an early approximation
        // that will grow: take the refinement, not a stale interval it contradicts.
        self.itv.insert(v, cur.meet(new).unwrap_or(new));
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
    /// `y -> positions` of the checked squares `y * y`: each fits in an `i64` on every path
    /// through it, which bounds `x * y + j` for `x, j < y`.
    squares: HashMap<Value, Vec<(usize, usize)>>,
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
/// A list held in a type field is tracked the same way: a node for each list field of each
/// type value follows `type.new`, `type.fill`/`type.set` (the written field takes the written list,
/// the other fields keep theirs), copies and block arguments, so reading the field of a type
/// that was updated in a loop yields lists of one length origin. Types of unknown provenance
/// (parameters, loads, call results) start each field at the first read of it, which is why
/// repeated reads of one type must already be one value (see `simplify::cse`).
fn length_origins(m: &Module, f: &Func) -> Vec<Value> {
    #[derive(Clone, Copy, PartialEq, Eq)]
    enum Origin {
        Unknown,
        One(Value),
        Mixed,
    }
    let nv = f.values.len();
    // An optional list (a `var` list that is moved out and put back) carries its list's length.
    let is_list = |v: Value| match m.types.kind(f.ty(v)) {
        TyKind::List(_) => true,
        TyKind::Opt(inner) => matches!(m.types.kind(*inner), TyKind::List(_)),
        _ => false,
    };
    let list_fields = |v: Value| -> Vec<u32> {
        let TyKind::Type(rid) = m.types.kind(f.ty(v)) else {
            return Vec::new();
        };
        m.type_defs[rid.0 as usize]
            .fields
            .iter()
            .enumerate()
            .filter(|(_, (_, t))| matches!(m.types.kind(*t), TyKind::List(_)))
            .map(|(k, _)| k as u32)
            .collect()
    };
    // One node per list value, then one per list field of each type value.
    let mut pair: HashMap<(Value, u32), usize> = HashMap::new();
    let mut total = nv;
    for i in 0..nv {
        let v = Value(i as u32);
        for k in list_fields(v) {
            pair.insert((v, k), total);
            total += 1;
        }
    }
    // Slot memory: a pointer parameter or `slot` that is only loaded from, taken from and
    // stored into as a whole type is one variable. Every type loaded from it shares its
    // list fields' origins, which are the join of the field origins of the types stored.
    let mut slots: HashSet<Value> = f.blocks[0].params.iter().map(|p| p.value).collect();
    let mut loaded_from: HashMap<Value, Value> = HashMap::new();
    let mut candidates: HashSet<Value> = HashSet::new();
    for b in &f.blocks {
        for i in &b.insts {
            if let (Op::Slot, Some(r)) = (i.op, i.res) {
                slots.insert(r);
            }
        }
    }
    for b in &f.blocks {
        for i in &b.insts {
            if let (Op::Load | Op::Take, Some(r)) = (i.op, i.res)
                && slots.contains(&i.args[0])
                && !list_fields(r).is_empty()
            {
                candidates.insert(i.args[0]);
                loaded_from.insert(r, i.args[0]);
            }
        }
    }
    let mut escaped: HashSet<Value> = HashSet::new();
    for b in &f.blocks {
        let returns = matches!(b.term, Term::Ret(_));
        for (ii, i) in b.insts.iter().enumerate() {
            let whole = matches!(i.op, Op::Load | Op::Take | Op::Put | Op::Store);
            for (n, a) in i.args.iter().enumerate() {
                if !candidates.contains(a) || (whole && n == 0) {
                    continue;
                }
                // A call that ends the function may rewrite the slot: nothing reads it after.
                let last = i.op == Op::Call
                    && returns
                    && b.insts[ii + 1..].iter().all(|j| !j.args.contains(a));
                if !last {
                    escaped.insert(*a);
                }
            }
        }
        b.term.for_each_use(&mut |v: Value| {
            if candidates.contains(&v) {
                escaped.insert(v);
            }
        });
    }
    candidates.retain(|p| !escaped.contains(p));
    for (&r, p) in &loaded_from {
        if !candidates.contains(p) {
            continue;
        }
        for k in list_fields(r) {
            pair.entry((*p, k)).or_insert_with(|| {
                total += 1;
                total - 1
            });
        }
    }
    let mut facts = vec![Origin::Unknown; total];
    let mut users = vec![Vec::new(); total];
    let mut work = Vec::new();
    let mut reads: HashMap<(Value, Value), Value> = HashMap::new();
    // The first read of each type field, the origin of a field nothing else defines.
    let mut first_field_read: HashMap<(Value, u32), Value> = HashMap::new();
    // Type values whose list fields come from other nodes rather than starting fresh.
    let mut flows: Vec<bool> = vec![false; nv];
    let edge = |users: &mut Vec<Vec<usize>>, from: usize, to: usize| users[from].push(to);
    for b in f.blocks.iter().skip(1) {
        for p in &b.params {
            flows[p.value.index()] = true;
        }
    }
    for p in &candidates {
        flows[p.index()] = true;
    }
    let mut first_slot_read: HashMap<(Value, u32), Value> = HashMap::new();
    for p in &f.blocks[0].params {
        if is_list(p.value) {
            facts[p.value.index()] = Origin::One(p.value);
            work.push(p.value.index());
        }
    }
    for b in &f.blocks {
        for i in &b.insts {
            if matches!(i.op, Op::Put | Op::Store) && candidates.contains(&i.args[0]) {
                for k in list_fields(i.args[1]) {
                    if let (Some(&to), Some(&from)) =
                        (pair.get(&(i.args[0], k)), pair.get(&(i.args[1], k)))
                    {
                        edge(&mut users, from, to);
                    }
                }
                continue;
            }
            let Some(r) = i.res else { continue };
            match i.op {
                Op::Load | Op::Take
                    if loaded_from.get(&r).is_some_and(|p| candidates.contains(p)) =>
                {
                    flows[r.index()] = true;
                    let p = loaded_from[&r];
                    for k in list_fields(r) {
                        if let (Some(&from), Some(&to)) = (pair.get(&(p, k)), pair.get(&(r, k))) {
                            edge(&mut users, from, to);
                        }
                    }
                    continue;
                }
                Op::TypeNew => {
                    flows[r.index()] = true;
                    let Imm::Type(rid) = i.imm else { continue };
                    for (k, (_, t)) in m.type_defs[rid.0 as usize].fields.iter().enumerate() {
                        if matches!(m.types.kind(*t), TyKind::List(_))
                            && let Some(&to) = pair.get(&(r, k as u32))
                        {
                            edge(&mut users, i.args[k].index(), to);
                        }
                    }
                    continue;
                }
                Op::TypeFill | Op::TypeSet => {
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
                Op::Clone if !list_fields(r).is_empty() => {
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
                Op::TypeGet if is_list(r) => {
                    let Imm::Field(_, k) = i.imm else { continue };
                    first_field_read.entry((i.args[0], k)).or_insert(r);
                    if let Some(&p) = loaded_from.get(&i.args[0]) {
                        first_slot_read.entry((p, k)).or_insert(r);
                    }
                    if let Some(&from) = pair.get(&(i.args[0], k)) {
                        edge(&mut users, from, r.index());
                    }
                    continue;
                }
                _ => {}
            }
            // `none` holds no list, so no length to share.
            if !is_list(r) || i.op == Op::OptNone {
                continue;
            }
            if matches!(
                i.op,
                Op::ListSet
                    | Op::ListSetNn
                    | Op::ListSetU
                    | Op::ListFill
                    | Op::MoveOut
                    | Op::Clone
                    | Op::OptSome
                    | Op::OptView
                    | Op::OptGet
                    | Op::OptUnwrap
                    | Op::OptUnbox
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
    // A pointer parameter's contents start every list field at its first read.
    for p in &f.blocks[0].params {
        if !candidates.contains(&p.value) {
            continue;
        }
        for (&(q, k), &node) in &pair {
            if q == p.value
                && let Some(&r) = first_slot_read.get(&(q, k))
            {
                facts[node] = Origin::One(r);
                work.push(node);
            }
        }
    }
    // Type values nothing flows into start every list field at its first read, or at the type
    // itself when the field is never read (a value no list shares an origin with).
    for (&(r, k), &node) in &pair {
        if !flows[r.index()] {
            facts[node] = Origin::One(first_field_read.get(&(r, k)).copied().unwrap_or(r));
            work.push(node);
        }
    }
    // A block parameter that joins lists of different origins is a fresh origin of its own:
    // every list derived from it by element replacement has its length. Without this the
    // join poisons everything downstream (`Mixed`) and a loop that updates the list in place
    // cannot share an origin with the list it started as. Pinning can expose a further join
    // downstream, so repeat a few rounds.
    let params: Vec<usize> = f
        .blocks
        .iter()
        .skip(1)
        .flat_map(|b| b.params.iter().map(|p| p.value))
        .filter(|&v| is_list(v))
        .map(|v| v.index())
        .collect();
    let mut sources: Vec<Vec<usize>> = vec![Vec::new(); total];
    for (v, us) in users.iter().enumerate() {
        for &u in us {
            sources[u].push(v);
        }
    }
    let (seeded, seeds) = (facts, work);
    let mut pinned: HashSet<usize> = HashSet::new();
    let mut facts = seeded.clone();
    for round in 0..6 {
        facts = seeded.clone();
        let mut work = seeds.clone();
        for &p in &pinned {
            facts[p] = Origin::One(Value(p as u32));
            work.push(p);
        }
        while let Some(v) = work.pop() {
            for &u in &users[v] {
                if pinned.contains(&u) {
                    continue;
                }
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
        // Pin only a join with a source that is not itself mixed: a parameter that is `Mixed`
        // merely downstream of a join (a loop that threads the joined list through
        // element replacement) takes that join's origin once the join is pinned.
        let before = pinned.len();
        pinned.extend(params.iter().copied().filter(|&p| {
            facts[p] == Origin::Mixed && sources[p].iter().any(|&s| facts[s] != Origin::Mixed)
        }));
        if round == 5 || pinned.len() == before {
            break;
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
                && m.externs[e.index()].role == ExternRole::BytesValues
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
                Edit::Op(b, i, op) => {
                    f.blocks[b].insts[i].op = op;
                    if matches!(op, Op::IAdd | Op::ISub | Op::IMul | Op::INeg)
                        && let Some(r) = f.blocks[b].insts[i].res
                    {
                        f.exact.insert(r);
                    }
                }
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

/// A block parameter that only ever receives one other value (or itself, around a loop) is
/// that value: a list threaded unchanged through a loop keeps the origin of the list it
/// started as, even when that list's own origin is mixed.
fn alias_loop_lists(m: &Module, f: &Func, lengths: &mut [Value]) {
    let mut source: HashMap<Value, Option<Value>> = HashMap::new();
    let mut note = |t: &Target| {
        let params = &f.blocks[t.block.index()].params;
        for (p, &a) in params.iter().zip(&t.args) {
            if a == p.value
                || f.ty(a) != f.ty(p.value)
                || !matches!(m.types.kind(f.ty(a)), TyKind::List(_))
            {
                continue;
            }
            source
                .entry(p.value)
                .and_modify(|s| {
                    if *s != Some(a) {
                        *s = None;
                    }
                })
                .or_insert(Some(a));
        }
    };
    for b in &f.blocks {
        match &b.term {
            Term::Br(t) => note(t),
            Term::CondBr { then, els, .. } => {
                note(then);
                note(els);
            }
            Term::Switch { cases, default, .. } => {
                cases.iter().for_each(|(_, t)| note(t));
                note(default);
            }
            _ => {}
        }
    }
    // Only lists matter; `lengths` is the identity for everything else.
    for _ in 0..8 {
        let mut changed = false;
        for (&p, &s) in &source {
            let Some(a) = s else { continue };
            if lengths[p.index()] == p
                && lengths[a.index()] != p
                && lengths[p.index()] != lengths[a.index()]
            {
                lengths[p.index()] = lengths[a.index()];
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
}

/// A loop that starts with an empty list and a counter at zero and pushes one element while
/// adding one to the counter keeps the counter equal to the list's length: the counter parameter
/// takes the list parameter's length origin.
fn counted_lists(
    m: &Module,
    f: &Func,
    defs: &[Option<(usize, usize)>],
    incoming: &[Vec<(usize, Edge, Vec<Value>)>],
    lengths: &[Value],
    lenof: &mut LenOf,
) {
    let def = |v: Value| defs[v.index()].map(|(b, i)| &f.blocks[b].insts[i]);
    let konst = |v: Value| match def(v).map(|d| (d.op, d.imm)) {
        Some((Op::IConst, Imm::Int(c))) => Some(c),
        _ => None,
    };
    for (bi, blk) in f.blocks.iter().enumerate().skip(1) {
        if incoming[bi].is_empty() {
            continue;
        }
        for (li, l) in blk.params.iter().enumerate() {
            if !matches!(m.types.kind(f.ty(l.value)), TyKind::List(_)) {
                continue;
            }
            for (ci, c) in blk.params.iter().enumerate() {
                if f.ty(c.value) != Ty::INT {
                    continue;
                }
                let paired = incoming[bi].iter().all(|(_, _, args)| {
                    let (al, ac) = (args[li], args[ci]);
                    let fresh = def(al).is_some_and(|d| {
                        d.op == Op::ListNew || (d.op == Op::ListLit && d.args.is_empty())
                    }) && konst(ac) == Some(0);
                    let step = def(al)
                        .is_some_and(|d| d.op == Op::ListPush && d.args[0] == l.value)
                        && def(ac).is_some_and(|d| {
                            matches!(d.op, Op::IAdd | Op::IAddChk)
                                && d.args[0] == c.value
                                && konst(d.args[1]) == Some(1)
                        });
                    fresh || step
                });
                if paired {
                    lenof.insert(c.value, lengths[l.value.index()]);
                }
            }
        }
    }
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
        let mut lengths = length_origins(m, f);
        alias_loop_lists(m, f, &mut lengths);
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
        counted_lists(m, f, &defs, &incoming, &lengths, &mut lenof);
        let class = |v: Value| {
            lenof
                .get(&v)
                .map_or(lengths[v.index()].index(), |o: &Value| o.index())
        };
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
        let mut squares: HashMap<Value, Vec<(usize, usize)>> = HashMap::new();
        for (bi, b) in f.blocks.iter().enumerate() {
            for (ii, i) in b.insts.iter().enumerate() {
                if i.op == Op::IMulChk && i.args[0] == i.args[1] {
                    squares.entry(i.args[0]).or_default().push((bi, ii));
                }
            }
        }
        Fa {
            m,
            f,
            defs,
            rpo,
            idom,
            squares,
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
        self.lenof
            .get(&v)
            .map_or(self.lengths[v.index()].index(), |o| o.index())
    }

    /// Drops what `env` knows about values that no block from `bi` on reads.
    fn prune(&self, env: &mut Env, bi: usize) {
        let pos = self.rpo_pos[bi];
        let live = |v: &Value| self.last_read[self.class(*v)] >= pos;
        env.itv.retain(|v, _| live(v));
        // `a < b` serves a proof that reaches `b` from a live value and goes on from there, so it
        // stays when `b` is live or when `b` starts another kept relation. `0 < len` for every
        // earlier version of a list would otherwise outlive the lists.
        // `b = x - c` (or `x + c`) with `x` live also counts as live: the proof steps through
        // the offset to `x` (`i <= len - 2` is how a child index is known to be in range).
        let reach = |v: &Value| {
            live(v)
                || self.def_inst(*v).is_some_and(|d| {
                    matches!(d.op, Op::IAdd | Op::IAddChk | Op::ISub | Op::ISubChk)
                        && self.constant(d.args[1]).is_some()
                        && live(&d.args[0])
                })
        };
        let starts: HashSet<usize> = env
            .rels
            .iter()
            .filter(|(_, b, _)| reach(b))
            .map(|(a, ..)| self.class(*a))
            .collect();
        env.rels
            .retain(|(a, b, _)| reach(b) || (live(a) && starts.contains(&self.class(*b))));
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
            Op::ListConst => match d.imm {
                Imm::Int(i) => i64::try_from(self.m.list_consts[i as usize].len()).ok(),
                _ => None,
            },
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
        // A bound that keeps growing jumps to a large threshold that arithmetic on it cannot
        // wrap (`2 * x + 1`), and only to the type bound if it outgrows that. Jumping straight to
        // the type bound makes such a step wrap to top, and the other bound is lost with it in a
        // cycle that narrowing cannot repair.
        Itv {
            lo: if joined.lo >= old.lo {
                old.lo
            } else if joined.lo >= -WIDEN_LIMIT {
                -WIDEN_LIMIT
            } else {
                i64::MIN
            },
            hi: if joined.hi <= old.hi {
                old.hi
            } else if joined.hi <= WIDEN_LIMIT {
                WIDEN_LIMIT
            } else {
                i64::MAX
            },
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
        } else if let Some((p, kind)) = self.entry_edge(bi) {
            self.apply_edge(&mut env, p, kind);
        }
        env
    }

    /// The single edge that enters the loop headed by `bi` from outside, when every other
    /// incoming edge comes from inside it. Every path to the header runs through that edge
    /// first, and values are immutable, so what it refines about earlier values holds in
    /// the whole loop.
    fn entry_edge(&self, bi: usize) -> Option<(usize, Edge)> {
        let inside = |mut b: usize| {
            while b != bi && b != 0 {
                b = self.idom[b];
            }
            b == bi
        };
        let mut entry = None;
        for (p, kind, _) in &self.incoming[bi] {
            if inside(*p) {
                continue;
            }
            if entry.replace((*p, *kind)).is_some() {
                return None;
            }
        }
        entry
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

    /// A Boolean block parameter (the merge of a short-circuit `and`/`or`) that is `truth`
    /// only on one forward incoming edge: that edge's facts hold.
    fn refine_param(&self, cond: Value, truth: bool, env: &mut Env) -> bool {
        let Some((bi, pi)) = self.param_of[cond.index()] else {
            return false;
        };
        let incoming = &self.incoming[bi];
        if incoming.is_empty()
            || incoming
                .iter()
                .any(|(p, ..)| self.rpo_pos[*p] >= self.rpo_pos[bi])
        {
            return true;
        }
        let possible = |arg: Value| match self.def_inst(arg).map(|d| (d.op, d.imm)) {
            Some((Op::BConst, Imm::Bool(b))) => b == truth,
            _ => true,
        };
        let mut viable = incoming.iter().filter(|(_, _, args)| possible(args[pi]));
        if let (Some((pred, kind, args)), None) = (viable.next(), viable.next()) {
            let mut e = self.edge_env(*pred, *kind);
            self.refine_cond(args[pi], truth, &mut e);
            for (v, itv) in e.itv {
                env.narrow(v, itv.lo as i128, itv.hi as i128);
            }
            for r in e.rels {
                if !env.rels.contains(&r) {
                    env.rels.push(r);
                }
            }
        }
        true
    }

    fn refine_cond(&self, cond: Value, truth: bool, env: &mut Env) {
        if self.refine_param(cond, truth, env) {
            return;
        }
        let Some(inst) = self.def_inst(cond) else {
            return;
        };
        match inst.op {
            Op::ICmp => {
                let Imm::Cc(cc) = inst.imm else { return };
                if let Some(k) = self.constant(inst.args[1]) {
                    self.refine_select(inst.args[0], cc, k, truth, env, 4);
                }
                let cc = if truth { cc } else { cc.negated() };
                self.refine_cmp(cc, inst.args[0], inst.args[1], env);
            }
            // `a or b` and `a and b` lower to a select with a constant arm.
            Op::Select => {
                let (c, x, y) = (inst.args[0], inst.args[1], inst.args[2]);
                let bconst = |v: Value| match self.def_inst(v).map(|d| (d.op, d.imm)) {
                    Some((Op::BConst, Imm::Bool(b))) => Some(b),
                    _ => None,
                };
                match (bconst(x), bconst(y), truth) {
                    (Some(true), _, false) => {
                        self.refine_cond(c, false, env);
                        self.refine_cond(y, false, env);
                    }
                    (_, Some(false), true) => {
                        self.refine_cond(c, true, env);
                        self.refine_cond(x, true, env);
                    }
                    (Some(false), _, true) => {
                        self.refine_cond(c, false, env);
                        self.refine_cond(y, true, env);
                    }
                    (_, Some(true), false) => {
                        self.refine_cond(c, true, env);
                        self.refine_cond(x, false, env);
                    }
                    _ => {}
                }
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

    /// Whether the select tree `v` can yield a value `r` with `(r cc k) == truth`.
    fn arm_can(&self, v: Value, cc: Cc, k: i64, truth: bool, depth: u32) -> bool {
        if let Some(c) = self.constant(v) {
            return cmp_holds(cc, c, k) == truth;
        }
        match self.def_inst(v) {
            Some(d) if d.op == Op::Select && depth > 0 => {
                self.arm_can(d.args[1], cc, k, truth, depth - 1)
                    || self.arm_can(d.args[2], cc, k, truth, depth - 1)
            }
            _ => true,
        }
    }

    /// `v cc k` is `truth` where `v` selects between constants (the three-way compare of
    /// `min`/`max`/`compare`): a condition whose arm cannot satisfy it is known to be false.
    fn refine_select(&self, v: Value, cc: Cc, k: i64, truth: bool, env: &mut Env, depth: u32) {
        let Some(d) = self.def_inst(v) else { return };
        if d.op != Op::Select || depth == 0 {
            return;
        }
        let (c, x, y) = (d.args[0], d.args[1], d.args[2]);
        let (cx, cy) = (
            self.arm_can(x, cc, k, truth, 3),
            self.arm_can(y, cc, k, truth, 3),
        );
        if cx && !cy {
            self.refine_cond(c, true, env);
            self.refine_select(x, cc, k, truth, env, depth - 1);
        } else if cy && !cx {
            self.refine_cond(c, false, env);
            self.refine_select(y, cc, k, truth, env, depth - 1);
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

    /// The interval of the amount `a` adds to or subtracts from `p`, when `a` is `p + q` or
    /// `p - q` with `q` a value whose range is known (a widened byte, a bounded index).
    fn step_range(&self, a: Value, p: Value, env: &Env) -> Option<Itv> {
        let i = self.def_inst(a)?;
        let (q, neg) = match i.op {
            Op::IAdd | Op::IAddChk if i.args[0] == p => (i.args[1], false),
            Op::IAdd | Op::IAddChk if i.args[1] == p => (i.args[0], false),
            Op::ISub | Op::ISubChk if i.args[0] == p => (i.args[1], true),
            _ => return None,
        };
        let q = self.get(q, env)?;
        if neg {
            Some(Itv {
                lo: q.hi.checked_neg()?,
                hi: q.lo.checked_neg()?,
            })
        } else {
            Some(q)
        }
    }

    fn param_itv(&self, bi: usize, pi: usize) -> Option<Itv> {
        let p = self.f.blocks[bi].params[pi].value;
        let mut acc: Option<Itv> = None;
        let mut others: Option<Itv> = None;
        let (mut ups, mut downs, mut mixed, mut counter_ok) = (0, 0, 0, true);
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
            let step = self
                .step_of(a, p)
                .map(Itv::point)
                .or_else(|| self.step_range(a, p, &env));
            match step {
                Some(s)
                    if (s.lo, s.hi) != (0, 0)
                        && s.lo.unsigned_abs() <= COUNTER_STEP_MAX as u64
                        && s.hi.unsigned_abs() <= COUNTER_STEP_MAX as u64 =>
                {
                    if s.lo >= 0 {
                        ups += 1;
                    } else if s.hi <= 0 {
                        downs += 1;
                    } else {
                        mixed += 1;
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
            && ups + downs + mixed > 0
            && let (Some(o), Some(a)) = (others, acc)
        {
            let bound = if mixed > 0 || (ups > 0 && downs > 0) {
                Itv {
                    lo: i64::MIN / 2,
                    hi: i64::MAX / 2,
                }
            } else if ups > 0 {
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
        match inst.op {
            Op::IConst
            | Op::BConst
            | Op::IAdd
            | Op::IAddChk
            | Op::ISub
            | Op::ISubChk
            | Op::IMul
            | Op::IMulChk
            | Op::INeg
            | Op::INegChk
            | Op::UAddChk
            | Op::USubChk
            | Op::UMulChk
            | Op::SDiv
            | Op::SDivChk
            | Op::SRem
            | Op::SRemChk => self.arithmetic(inst, env, ty, top),
            Op::And | Op::Or | Op::Xor | Op::Not | Op::Shl | Op::Sshr => {
                self.bitwise(inst, env, ty, top)
            }
            Op::ICmp
            | Op::B2I
            | Op::Select
            | Op::ListLen
            | Op::ListGet
            | Op::ListGetNn
            | Op::ListGetU
            | Op::StrLen
            | Op::StrAsciiLen
            | Op::Conv
            | Op::AltTag => self.other_ops(inst, env, ty, top),
            _ => Some(top),
        }
    }

    /// Constants, additions, multiplications and divisions.
    fn arithmetic(&self, inst: &Inst, env: &Env, _ty: Ty, top: Itv) -> Option<Itv> {
        let arg = |i: usize| self.get(inst.args[i], env);
        let exact = inst.res.is_some_and(|r| self.f.exact.contains(&r));
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
                if inst.op == Op::IAddChk || exact {
                    Itv::clamp(lo, hi)
                } else {
                    Itv::exact(lo, hi)
                }
            }
            Op::ISub | Op::ISubChk => {
                let (x, y) = (arg(0)?, arg(1)?);
                let (lo, hi) = (x.lo as i128 - y.hi as i128, x.hi as i128 - y.lo as i128);
                if inst.op == Op::ISubChk || exact {
                    Itv::clamp(lo, hi)
                } else {
                    Itv::exact(lo, hi)
                }
            }
            Op::IMul | Op::IMulChk => {
                let (x, y) = (arg(0)?, arg(1)?);
                let (lo, hi) = corners(|a, b| a * b, x, y);
                if inst.op == Op::IMulChk || exact {
                    Itv::clamp(lo, hi)
                } else {
                    Itv::exact(lo, hi)
                }
            }
            Op::INeg | Op::INegChk => {
                let x = arg(0)?;
                let (lo, hi) = (-(x.hi as i128), -(x.lo as i128));
                if inst.op == Op::INegChk || exact {
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
            _ => top,
        })
    }

    /// Boolean and bitwise operations and shifts.
    fn bitwise(&self, inst: &Inst, env: &Env, ty: Ty, top: Itv) -> Option<Itv> {
        let arg = |i: usize| self.get(inst.args[i], env);
        Some(match inst.op {
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
            Op::Shl => {
                let (x, y) = (arg(0)?, arg(1)?);
                if y.is_point() && (0..63).contains(&y.lo) {
                    let (lo, hi) = ((x.lo as i128) << y.lo, (x.hi as i128) << y.lo);
                    if inst.res.is_some_and(|r| self.f.exact.contains(&r)) {
                        Itv::clamp(lo, hi)
                    } else {
                        Itv::exact(lo, hi)
                    }
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
            _ => top,
        })
    }

    /// Comparisons, `select`, lengths, bytes and alternative tags.
    fn other_ops(&self, inst: &Inst, env: &Env, _ty: Ty, top: Itv) -> Option<Itv> {
        let arg = |i: usize| self.get(inst.args[i], env);
        Some(match inst.op {
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
            // A narrow integer widened to `Int` keeps the range of its type.
            Op::Conv if _ty == Ty::INT => match self.m.types.int_range(self.f.ty(inst.args[0])) {
                Some((lo, hi)) if lo >= i64::MIN.into() && hi <= i64::MAX.into() => Itv {
                    lo: lo as i64,
                    hi: hi as i64,
                },
                _ => top,
            },
            Op::StrLen => Itv { lo: 0, hi: LEN_MAX },
            Op::StrAsciiLen => Itv {
                lo: -1,
                hi: LEN_MAX,
            },
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
}
