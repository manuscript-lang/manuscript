//! The `lastuse` pass: drops a plain-memory owned value right after its last use instead of
//! where lowering put the drop (the end of the enclosing scope).
//!
//! A candidate `v` is a value of a type whose drop only frees memory (strings, lists, maps,
//! sets and records, alternatives and optionals of those) that is dropped with `drop v`.
//! Everything that may point into `v` forms its *family*: results of instructions that take a
//! family member (string views, interior pointers, projections, runtime calls), out-pointers
//! of calls that take one, and block parameters that receive one. `v` lives until the last
//! use of any family member on every path; the drop moves there (a new block on an edge that
//! leaves the family's live range, e.g. a loop exit).
//!
//! The family only ever extends `v`'s life, never past its original drop. A candidate is left
//! alone when a family member is stored to memory, captured, kept by a cleanup, or when `v`
//! takes part in a conditional drop.

use crate::ir::*;
use crate::types::TyKind;
use std::collections::{HashMap, HashSet};

/// Runs the pass; returns whether any drop moved.
pub fn run(m: &mut Module) -> bool {
    run_where(m, |_| true)
}

/// Runs the pass on the functions `select` accepts.
pub fn run_where(m: &mut Module, select: impl Fn(&Func) -> bool) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        if m.funcs[fi].blocks.is_empty() || !select(&m.funcs[fi]) {
            continue;
        }
        // The stand-in keeps `ret_borrowed`, so a recursive call still reads as lending.
        let mut stand_in = Func::new("", Vec::new(), crate::types::Ty::UNIT);
        stand_in.ret_borrowed = m.funcs[fi].ret_borrowed;
        let mut f = std::mem::replace(&mut m.funcs[fi], stand_in);
        changed |= function(m, &mut f);
        m.funcs[fi] = f;
    }
    changed
}

/// Whether dropping a value of `t` only frees memory.
fn plain(m: &Module, t: crate::types::Ty, seen: &mut Vec<crate::types::Ty>) -> bool {
    match m.types.kind(t) {
        TyKind::Unit
        | TyKind::Bool
        | TyKind::Int
        | TyKind::Int8
        | TyKind::Int16
        | TyKind::Int32
        | TyKind::UInt8
        | TyKind::UInt16
        | TyKind::UInt32
        | TyKind::UInt64
        | TyKind::Float
        | TyKind::Float32
        | TyKind::Str
        | TyKind::Bytes => true,
        TyKind::Ptr | TyKind::Fn(..) | TyKind::Iface(_) => false,
        TyKind::List(e) | TyKind::Opt(e) => plain(m, *e, seen),
        TyKind::Obj(n, args) => {
            (n == "Map" || n == "Set") && args.iter().all(|a| plain(m, *a, seen))
        }
        TyKind::Rec(r) => {
            if seen.contains(&t) {
                return true;
            }
            seen.push(t);
            let ok = m.records[r.index()]
                .fields
                .iter()
                .all(|f| plain(m, f.1, seen));
            seen.pop();
            ok
        }
        TyKind::Alt(a) => {
            if seen.contains(&t) {
                return true;
            }
            seen.push(t);
            let ok = m.alts[a.index()]
                .cases
                .iter()
                .all(|c| c.fields.iter().all(|f| plain(m, f.1, seen)));
            seen.pop();
            ok
        }
    }
}

/// A position inside a block: an original instruction (`idx`, `None` for the block start),
/// or the `after`-th drop this pass has appended behind it (`after == 0` is the instruction).
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
struct Pos {
    idx: Option<usize>,
    after: usize,
}

impl Pos {
    fn at(idx: usize) -> Pos {
        Pos {
            idx: Some(idx),
            after: 0,
        }
    }
    const START: Pos = Pos {
        idx: None,
        after: 0,
    };
    const END: Pos = Pos {
        idx: Some(usize::MAX),
        after: usize::MAX,
    };
}

/// Where a value is read, built once per function so each candidate costs its own footprint
/// rather than a scan of the function. Instruction indices are those of the original function:
/// the pass never inserts or removes instructions while it analyses, it records the drops it
/// removes (`removed`) and the drops it adds (`pending`) and rewrites every block at the end.
/// New edge blocks are added to the function at once, so terminators are always current.
struct Index {
    /// Operand uses of each value: (block, instruction), including drops.
    uses: Vec<Vec<(usize, usize)>>,
    /// Blocks whose terminator passes the value to a target or returns it.
    term_uses: Vec<Vec<usize>>,
    /// Values defined by `slot`.
    slots: Vec<bool>,
    /// Original drops deleted so far, per block and instruction index.
    removed: Vec<Vec<bool>>,
    /// Drops to insert, per block: (after instruction or block start, value), in emission order.
    pending: Vec<Vec<(Option<usize>, Value)>>,
    /// Blocks holding a pending drop of each value.
    pending_blocks: HashMap<Value, Vec<usize>>,
}

impl Index {
    fn new(f: &Func) -> Index {
        let n = f.values.len();
        let mut ix = Index {
            uses: vec![Vec::new(); n],
            term_uses: vec![Vec::new(); n],
            slots: vec![false; n],
            removed: f
                .blocks
                .iter()
                .map(|b| vec![false; b.insts.len()])
                .collect(),
            pending: vec![Vec::new(); f.blocks.len()],
            pending_blocks: HashMap::new(),
        };
        for (bi, b) in f.blocks.iter().enumerate() {
            for (ii, i) in b.insts.iter().enumerate() {
                if i.op == Op::Slot
                    && let Some(r) = i.res
                {
                    ix.slots[r.index()] = true;
                }
                for a in &i.args {
                    ix.uses[a.index()].push((bi, ii));
                }
            }
            b.term.for_each_use(|v| ix.term_uses[v.index()].push(bi));
        }
        ix
    }

    fn add_block(&mut self) {
        self.removed.push(Vec::new());
        self.pending.push(Vec::new());
    }

    /// Whether the use at `(bi, ii)` still exists.
    fn live(&self, bi: usize, ii: usize) -> bool {
        !self.removed[bi][ii]
    }

    /// Positions in `bi` of the pending drops of `v`.
    fn pending_drops(&self, bi: usize, v: Value) -> impl Iterator<Item = Pos> + '_ {
        let pending = &self.pending[bi];
        pending
            .iter()
            .enumerate()
            .filter(move |(_, (_, w))| *w == v)
            .map(move |(n, (anchor, _))| Pos {
                idx: *anchor,
                after: 1 + pending[..n].iter().filter(|(a, _)| a == anchor).count(),
            })
    }

    /// Records a drop of `v` directly behind `pos`: behind the instruction, ahead of the drops
    /// already placed there, or behind the pending drop `pos` names.
    fn insert_pending(&mut self, bi: usize, pos: Pos, v: Value) {
        let group: Vec<usize> = (0..self.pending[bi].len())
            .filter(|&n| self.pending[bi][n].0 == pos.idx)
            .collect();
        let at = if pos.after == 0 {
            group.first().copied().unwrap_or(self.pending[bi].len())
        } else {
            group[pos.after - 1] + 1
        };
        self.pending[bi].insert(at, (pos.idx, v));
        let blocks = self.pending_blocks.entry(v).or_default();
        if !blocks.contains(&bi) {
            blocks.push(bi);
        }
    }

    /// Writes the recorded removals and insertions into the function.
    fn apply(self, f: &mut Func) {
        for (bi, b) in f.blocks.iter_mut().enumerate() {
            let pending = &self.pending[bi];
            if pending.is_empty() && !self.removed[bi].iter().any(|r| *r) {
                continue;
            }
            let drop_inst = |v: Value, loc: Loc| Inst {
                op: Op::Drop,
                args: vec![v],
                imm: Imm::None,
                res: None,
                loc,
            };
            let old = std::mem::take(&mut b.insts);
            let mut out = Vec::with_capacity(old.len() + pending.len());
            // Group by anchor once so a block costs its instructions plus its pending drops.
            let mut by_anchor: HashMap<Option<usize>, Vec<Value>> = HashMap::new();
            for (anchor, v) in pending {
                by_anchor.entry(*anchor).or_default().push(*v);
            }
            for v in by_anchor.get(&None).into_iter().flatten() {
                out.push(drop_inst(*v, b.term_loc));
            }
            for (k, inst) in old.into_iter().enumerate() {
                let loc = inst.loc;
                if !self.removed[bi][k] {
                    out.push(inst);
                }
                for v in by_anchor.get(&Some(k)).into_iter().flatten() {
                    out.push(drop_inst(*v, loc));
                }
            }
            b.insts = out;
        }
    }
}

fn function(m: &Module, f: &mut Func) -> bool {
    // Candidates: value -> defining (block, index or None for a block parameter).
    let mut cands: Vec<(Value, usize, Option<usize>)> = Vec::new();
    let mut dropped: HashSet<Value> = HashSet::new();
    for b in &f.blocks {
        for i in &b.insts {
            if i.op == Op::Drop {
                dropped.insert(i.args[0]);
            }
        }
    }
    for (bi, b) in f.blocks.iter().enumerate() {
        for p in &b.params {
            if p.mode == Mode::Own && dropped.contains(&p.value) {
                cands.push((p.value, bi, None));
            }
        }
        for (ii, i) in b.insts.iter().enumerate() {
            if let Some(r) = i.res
                && dropped.contains(&r)
                && m.result_mode(f, i) == Some(Mode::Own)
            {
                cands.push((r, bi, Some(ii)));
            }
        }
    }
    cands.retain(|(v, _, _)| plain(m, f.ty(*v), &mut Vec::new()) && m.needs_drop(f.ty(*v)));
    if cands.is_empty() {
        return false;
    }
    let mut ix = Index::new(f);
    let mut changed = false;
    // Latest definitions first: a family member's own drop has moved before its source's is placed.
    for (v, db, di) in cands.into_iter().rev() {
        changed |= candidate(m, f, &mut ix, v, db, di);
    }
    ix.apply(f);
    changed
}

fn is_scalar(m: &Module, t: crate::types::Ty) -> bool {
    matches!(m.types.kind(t), TyKind::Unit) || m.types.is_scalar(t)
}

/// Grows the family of `v` (everything that may point into it) to a fixed point over the
/// use index.
fn family(m: &Module, f: &Func, ix: &Index, v: Value) -> HashSet<Value> {
    let mut fam: HashSet<Value> = HashSet::new();
    fam.insert(v);
    let mut work = vec![v];
    while let Some(w) = work.pop() {
        for &(bi, ii) in &ix.uses[w.index()] {
            if !ix.live(bi, ii) {
                continue;
            }
            let i = &f.blocks[bi].insts[ii];
            let mut add = |r: Value, fam: &mut HashSet<Value>| {
                if fam.insert(r) {
                    work.push(r);
                }
            };
            match i.op {
                Op::Drop | Op::Copy => {}
                Op::Call | Op::CallInd | Op::CallRt | Op::CallMethod => {
                    // Out-pointers may receive views.
                    for a in &i.args {
                        if ix.slots[a.index()] {
                            add(*a, &mut fam);
                        }
                    }
                    // A fresh result points into no borrowed argument, so it does not
                    // extend the family (a concat chain would otherwise keep every
                    // intermediate alive until the end of the scope).
                    let fresh = matches!(i.imm, Imm::Ext(e) if m.externs[e.index()].fresh);
                    // A lending function's result is a borrow of its arguments.
                    let lent = m.result_mode(f, i) == Some(Mode::Borrow)
                        && matches!(i.op, Op::Call | Op::CallMethod);
                    if (i.op == Op::CallRt && !fresh || lent)
                        && let Some(r) = i.res
                        && !is_scalar(m, f.ty(r))
                    {
                        add(r, &mut fam);
                    }
                }
                _ => {
                    if let Some(r) = i.res
                        && !is_scalar(m, f.ty(r))
                    {
                        add(r, &mut fam);
                    }
                }
            }
        }
        for &bi in &ix.term_uses[w.index()] {
            f.blocks[bi].term.for_each_target(|t| {
                for (k, a) in t.args.iter().enumerate() {
                    if *a == w {
                        let p = f.blocks[t.block.index()].params[k].value;
                        if fam.insert(p) {
                            work.push(p);
                        }
                    }
                }
            });
        }
    }
    fam
}

/// Moves the drops of `v`; false when the candidate is left as it was.
fn candidate(
    m: &Module,
    f: &mut Func,
    ix: &mut Index,
    v: Value,
    db: usize,
    di: Option<usize>,
) -> bool {
    let fam = family(m, f, ix, v);
    // Leaks of the family into memory the pass cannot follow.
    for &w in &fam {
        for &(bi, ii) in &ix.uses[w.index()] {
            if !ix.live(bi, ii) {
                continue;
            }
            let i = &f.blocks[bi].insts[ii];
            match i.op {
                Op::Store | Op::Put => {
                    if i.args.get(1) == Some(&w) && (w != v || i.op == Op::Store) {
                        return false;
                    }
                }
                Op::GlobalSet | Op::CleanupPush | Op::DropIf | Op::ClosureNew | Op::IfaceNew => {
                    return false;
                }
                _ => {}
            }
        }
    }
    // Where the original drop of `v` sits in each block: nothing after it counts, `v` was gone then.
    let mut drop_at: HashMap<usize, usize> = HashMap::new();
    let mut existing: Vec<(usize, usize)> = Vec::new();
    // Earliest real consumption of `v` (not its drops) per block.
    let mut consume_at: HashMap<usize, usize> = HashMap::new();
    for &(bi, ii) in &ix.uses[v.index()] {
        if !ix.live(bi, ii) {
            continue;
        }
        let i = &f.blocks[bi].insts[ii];
        if i.op == Op::Drop {
            existing.push((bi, ii));
            let e = drop_at.entry(bi).or_insert(ii);
            *e = (*e).min(ii);
            continue;
        }
        let modes = crate::verify::arg_modes(m, i);
        if i.args
            .iter()
            .zip(modes)
            .any(|(a, md)| *a == v && md == Mode::Own)
        {
            let e = consume_at.entry(bi).or_insert(ii);
            *e = (*e).min(ii);
        }
    }
    if existing.is_empty() {
        return false;
    }
    // The region the analysis needs: blocks reachable from the definition, not past a block that
    // holds the original drop (liveness ends there and `v` is not owned beyond it). Everything
    // below is indexed by position in `order`, so a candidate costs its region, not the function.
    let mut order: Vec<usize> = vec![db];
    {
        let mut seen: HashSet<usize> = HashSet::from([db]);
        let mut work = vec![db];
        while let Some(b) = work.pop() {
            if drop_at.contains_key(&b) {
                continue;
            }
            for s in f.blocks[b].term.successors() {
                if seen.insert(s.index()) {
                    order.push(s.index());
                    work.push(s.index());
                }
            }
        }
    }
    order.sort_unstable();
    let nb = order.len();
    let lid: HashMap<usize, usize> = order.iter().enumerate().map(|(l, &b)| (b, l)).collect();
    let dl = lid[&db];
    // Uses per block: positions of family operands (other than the drops of `v`), including
    // drops of family members already placed by this pass.
    let mut uses: Vec<Vec<Pos>> = vec![Vec::new(); nb];
    for &w in &fam {
        for &(bi, ii) in &ix.uses[w.index()] {
            if !ix.live(bi, ii) {
                continue;
            }
            let Some(&l) = lid.get(&bi) else { continue };
            let i = &f.blocks[bi].insts[ii];
            if i.op == Op::Drop && i.args[0] == v {
                continue;
            }
            uses[l].push(Pos::at(ii));
        }
        for &bi in ix.pending_blocks.get(&w).into_iter().flatten() {
            if let Some(&l) = lid.get(&bi) {
                uses[l].extend(ix.pending_drops(bi, w));
            }
        }
    }
    let end = |l: usize| drop_at.get(&order[l]).map_or(Pos::END, |&k| Pos::at(k));
    let uses_in = |l: usize| uses[l].iter().copied().filter(move |p| *p < end(l));
    // Blocks whose terminator passes a family member on (the drop must follow the edge).
    let passes = |bi: usize| -> bool {
        let mut hit = false;
        f.blocks[bi]
            .term
            .for_each_target(|t| hit |= t.args.iter().any(|a| fam.contains(a)));
        hit
    };
    let succs: Vec<Vec<Block>> = order
        .iter()
        .map(|&b| f.blocks[b].term.successors())
        .collect();
    // Backward liveness of the family.
    let mut live_in = vec![false; nb];
    let mut live_out = vec![false; nb];
    let mut has_use = vec![false; nb];
    for (l, slot) in has_use.iter_mut().enumerate() {
        *slot = uses_in(l).next().is_some()
            || matches!(&f.blocks[order[l]].term, Term::Ret(Some(x)) if *x == v);
    }
    loop {
        let mut again = false;
        for l in (0..nb).rev() {
            let out = !drop_at.contains_key(&order[l])
                && (passes(order[l])
                    || succs[l]
                        .iter()
                        .any(|s| lid.get(&s.index()).is_some_and(|&sl| live_in[sl])));
            // Nothing of the family is live before `v` is defined.
            let inn = l != dl && (out || has_use[l]);
            if out != live_out[l] || inn != live_in[l] {
                live_out[l] = out;
                live_in[l] = inn;
                again = true;
            }
        }
        if !again {
            break;
        }
    }
    // Whether the `slot`-th edge of `bi` hands `v` to an owning block parameter.
    let edge_consumes = |bi: usize, slot: usize| -> bool {
        let mut n = 0usize;
        let mut hit = false;
        f.blocks[bi].term.for_each_target(|tg| {
            if n == slot {
                for (k, a) in tg.args.iter().enumerate() {
                    if *a == v && f.blocks[tg.block.index()].params[k].mode == Mode::Own {
                        hit = true;
                    }
                }
            }
            n += 1;
        });
        hit
    };
    let ret_consumes = |bi: usize| matches!(&f.blocks[bi].term, Term::Ret(Some(x)) if *x == v);
    // Forward: blocks where `v` is owned on entry and not consumed.
    let mut owned_in = vec![false; nb];
    let mut owned_out = vec![false; nb];
    let consumed: Vec<bool> = order
        .iter()
        .map(|&bi| consume_at.contains_key(&bi) || ret_consumes(bi))
        .collect();
    owned_out[dl] = !consumed[dl] && !drop_at.contains_key(&db);
    // Incoming edges per block as (predecessor, successor slot), so a pass costs the edge count.
    let mut preds: Vec<Vec<(usize, usize)>> = vec![Vec::new(); nb];
    for (p, ss) in succs.iter().enumerate() {
        for (si, s) in ss.iter().enumerate() {
            if let Some(&sl) = lid.get(&s.index()) {
                preds[sl].push((p, si));
            }
        }
    }
    loop {
        let mut again = false;
        for l in 0..nb {
            let inn = l != dl
                && preds[l]
                    .iter()
                    .any(|&(p, si)| owned_out[p] && !edge_consumes(order[p], si));
            let out = (inn || l == dl) && !consumed[l] && !drop_at.contains_key(&order[l]);
            if inn != owned_in[l] || out != owned_out[l] {
                owned_in[l] = inn;
                owned_out[l] = out;
                again = true;
            }
        }
        if !again {
            break;
        }
    }

    // Placements: (block, position the drop follows) and edges.
    let mut after_uses: Vec<(usize, Pos)> = Vec::new();
    let mut edges: Vec<(usize, usize)> = Vec::new(); // (pred, succ-slot index in successors())
    for l in 0..nb {
        let bi = order[l];
        let in_region = if l == dl {
            true
        } else {
            owned_in[l] && live_in[l]
        };
        if !in_region || consumed[l] {
            continue;
        }
        let lo = if bi == db {
            Pos::at(di.map(|d| d + 1).unwrap_or(0))
        } else {
            Pos::at(0)
        };
        let last = uses_in(l).filter(|p| *p >= lo).max();
        let out = live_out[l];
        if !out {
            if matches!(f.blocks[bi].term, Term::Fault(_) | Term::Unreachable) {
                continue;
            }
            // After the last use (or the definition) in this block.
            let pos = match (last, bi == db, di) {
                (Some(p), _, _) => Some(p),
                (None, true, Some(d)) => Some(Pos::at(d)),
                (None, _, _) => None,
            };
            // A block with no use and no definition is entered with `v` owned only from
            // predecessors that left it live; their edges place the drop.
            let Some(pos) = pos else {
                if bi != db {
                    continue;
                }
                after_uses.push((bi, Pos::START));
                continue;
            };
            after_uses.push((bi, pos));
        } else {
            for (si, s) in succs[l].iter().enumerate() {
                let sl = lid[&s.index()];
                if !live_in[sl] && !edge_consumes(bi, si) {
                    edges.push((bi, si));
                }
            }
        }
    }
    // Apply: record the removed drops and the new ones.
    for (bi, k) in existing {
        ix.removed[bi][k] = true;
    }
    for (bi, pos) in after_uses {
        ix.insert_pending(bi, pos, v);
    }
    // Edges: a new block holding the drop, forwarding the edge's arguments.
    for (pred, slot) in edges {
        let mut n = 0usize;
        let mut target_info: Option<(Block, Vec<Value>)> = None;
        f.blocks[pred].term.for_each_target(|t| {
            if n == slot {
                target_info = Some((t.block, t.args.clone()));
            }
            n += 1;
        });
        let (dest, args) = target_info.expect("edge");
        let loc = f.blocks[pred].term_loc;
        let params: Vec<(crate::types::Ty, Mode)> = f.blocks[dest.index()]
            .params
            .iter()
            .map(|p| (f.ty(p.value), p.mode))
            .collect();
        let nbk = f.new_block();
        ix.add_block();
        let mut fwd = Vec::new();
        for (ty, mode) in params {
            let val = f.new_value(ty);
            ix.uses.push(Vec::new());
            ix.term_uses.push(vec![nbk.index()]);
            ix.slots.push(false);
            f.blocks[nbk.index()]
                .params
                .push(BlockParam { value: val, mode });
            fwd.push(val);
        }
        f.blocks[nbk.index()].insts.push(Inst {
            op: Op::Drop,
            args: vec![v],
            imm: Imm::None,
            res: None,
            loc,
        });
        ix.removed[nbk.index()].push(false);
        ix.uses[v.index()].push((nbk.index(), 0));
        f.blocks[nbk.index()].term = Term::Br(Target {
            block: dest,
            args: fwd,
        });
        f.blocks[nbk.index()].term_loc = loc;
        let mut n = 0usize;
        f.blocks[pred].term.for_each_target_mut(|t| {
            if n == slot {
                t.block = nbk;
                t.args = args.clone();
            }
            n += 1;
        });
    }
    true
}
