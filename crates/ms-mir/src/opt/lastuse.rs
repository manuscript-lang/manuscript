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
use std::collections::HashSet;

/// Functions larger than this keep scope-end drops (the analysis is quadratic).
const MAX_INSTS: usize = 4000;

/// Runs the pass; returns whether any drop moved.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        if m.funcs[fi].inst_count() > MAX_INSTS || m.funcs[fi].blocks.is_empty() {
            continue;
        }
        let mut f = std::mem::replace(
            &mut m.funcs[fi],
            Func::new("", Vec::new(), crate::types::Ty::UNIT),
        );
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
    let mut changed = false;
    // Latest definitions first: a family member's own drop has moved before its source's is placed.
    for (v, db, di) in cands.into_iter().rev() {
        changed |= candidate(m, f, v, db, di);
    }
    changed
}

fn is_scalar(m: &Module, t: crate::types::Ty) -> bool {
    matches!(m.types.kind(t), TyKind::Unit) || m.types.is_scalar(t)
}

/// Moves the drops of `v`; false when the candidate is left as it was.
fn candidate(m: &Module, f: &mut Func, v: Value, db: usize, di: Option<usize>) -> bool {
    let nb = f.blocks.len();
    // The family, grown to a fixed point.
    let slots: HashSet<Value> = f
        .blocks
        .iter()
        .flat_map(|b| b.insts.iter())
        .filter(|i| i.op == Op::Slot)
        .filter_map(|i| i.res)
        .collect();
    let mut fam: HashSet<Value> = HashSet::new();
    fam.insert(v);
    loop {
        let before = fam.len();
        for b in &f.blocks {
            for i in &b.insts {
                let touches = i.args.iter().any(|a| fam.contains(a));
                if !touches {
                    continue;
                }
                match i.op {
                    Op::Drop | Op::Copy => continue,
                    Op::Call | Op::CallInd | Op::CallRt | Op::CallMethod => {
                        // Out-pointers may receive views.
                        for a in &i.args {
                            if slots.contains(a) {
                                fam.insert(*a);
                            }
                        }
                        if i.op == Op::CallRt
                            && let Some(r) = i.res
                            && !is_scalar(m, f.ty(r))
                        {
                            fam.insert(r);
                        }
                    }
                    _ => {
                        if let Some(r) = i.res
                            && !is_scalar(m, f.ty(r))
                        {
                            fam.insert(r);
                        }
                    }
                }
            }
            b.term.for_each_target(|t| {
                for (k, a) in t.args.iter().enumerate() {
                    if fam.contains(a) {
                        fam.insert(f.blocks[t.block.index()].params[k].value);
                    }
                }
            });
        }
        if fam.len() == before {
            break;
        }
    }
    // Leaks of the family into memory the pass cannot follow.
    for b in &f.blocks {
        for i in &b.insts {
            let hit = |k: usize| i.args.get(k).is_some_and(|a| fam.contains(a) && *a != v);
            match i.op {
                Op::Store | Op::Put
                    if hit(1) || (i.args.get(1) == Some(&v) && i.op == Op::Store) =>
                {
                    return false;
                }
                Op::GlobalSet | Op::CleanupPush | Op::DropIf | Op::ClosureNew | Op::IfaceNew
                    if i.args.iter().any(|a| fam.contains(a)) =>
                {
                    return false;
                }
                _ => {}
            }
        }
    }

    // Uses per block: instruction indices (family operands, other than the drops of `v`).
    // Where the original drop sits in each block: nothing after it counts, `v` was gone then.
    let drop_at: Vec<Option<usize>> = f
        .blocks
        .iter()
        .map(|b| {
            b.insts
                .iter()
                .position(|i| i.op == Op::Drop && i.args[0] == v)
        })
        .collect();
    let uses_in = |bi: usize| -> Vec<usize> {
        let b = &f.blocks[bi];
        let end = drop_at[bi].unwrap_or(b.insts.len());
        b.insts
            .iter()
            .enumerate()
            .filter(|(k, _)| *k < end)
            .filter(|(_, i)| {
                !(i.op == Op::Drop && i.args[0] == v) && i.args.iter().any(|a| fam.contains(a))
            })
            .map(|(k, _)| k)
            .collect()
    };
    // Blocks whose terminator passes a family member on (the drop must follow the edge).
    let passes = |bi: usize| -> bool {
        let mut hit = false;
        f.blocks[bi]
            .term
            .for_each_target(|t| hit |= t.args.iter().any(|a| fam.contains(a)));
        hit
    };
    let succs: Vec<Vec<Block>> = f.blocks.iter().map(|b| b.term.successors()).collect();
    // Backward liveness of the family.
    let mut live_in = vec![false; nb];
    let mut live_out = vec![false; nb];
    let mut has_use = vec![false; nb];
    for (bi, slot) in has_use.iter_mut().enumerate() {
        *slot =
            !uses_in(bi).is_empty() || matches!(&f.blocks[bi].term, Term::Ret(Some(x)) if *x == v);
    }
    loop {
        let mut again = false;
        for bi in (0..nb).rev() {
            let out = drop_at[bi].is_none()
                && (passes(bi) || succs[bi].iter().any(|s| live_in[s.index()]));
            // Nothing of the family is live before `v` is defined.
            let inn = bi != db && (out || has_use[bi]);
            if out != live_out[bi] || inn != live_in[bi] {
                live_out[bi] = out;
                live_in[bi] = inn;
                again = true;
            }
        }
        if !again {
            break;
        }
    }
    // Real consumption of `v` (not its drops) per block, with the instruction index.
    let consume_at = |bi: usize| -> Option<usize> {
        let b = &f.blocks[bi];
        for (k, i) in b.insts.iter().enumerate() {
            if i.op == Op::Drop {
                continue;
            }
            let modes = crate::verify::arg_modes(m, i);
            if i.args
                .iter()
                .zip(modes)
                .any(|(a, md)| *a == v && md == Mode::Own)
            {
                return Some(k);
            }
        }
        None
    };
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
    let consumed: Vec<bool> = (0..nb)
        .map(|bi| consume_at(bi).is_some() || ret_consumes(bi))
        .collect();
    owned_out[db] = !consumed[db] && drop_at[db].is_none();
    loop {
        let mut again = false;
        for bi in 0..nb {
            let inn = bi != db
                && (0..nb).any(|p| {
                    owned_out[p]
                        && succs[p]
                            .iter()
                            .enumerate()
                            .any(|(si, s)| s.index() == bi && !edge_consumes(p, si))
                });
            let out = (inn || bi == db) && !consumed[bi] && drop_at[bi].is_none();
            if inn != owned_in[bi] || out != owned_out[bi] {
                owned_in[bi] = inn;
                owned_out[bi] = out;
                again = true;
            }
        }
        if !again {
            break;
        }
    }

    // Placements: (block, after instruction index or None for the block start) and edges.
    let mut after_uses: Vec<(usize, Option<usize>)> = Vec::new();
    let mut edges: Vec<(usize, usize)> = Vec::new(); // (pred, succ-slot index in successors())
    for bi in 0..nb {
        let in_region = if bi == db {
            true
        } else {
            owned_in[bi] && live_in[bi]
        };
        if !in_region || consumed[bi] {
            continue;
        }
        let lo = if bi == db {
            di.map(|d| d + 1).unwrap_or(0)
        } else {
            0
        };
        let last = uses_in(bi).into_iter().filter(|k| *k >= lo).max();
        let out = live_out[bi];
        if !out {
            if matches!(f.blocks[bi].term, Term::Fault(_) | Term::Unreachable) {
                continue;
            }
            // After the last use (or the definition) in this block.
            let pos = match (last, bi == db, di) {
                (Some(k), _, _) => Some(k),
                (None, true, Some(d)) => Some(d),
                (None, _, _) => None,
            };
            // A block with no use and no definition is entered with `v` owned only from
            // predecessors that left it live; their edges place the drop.
            if pos.is_none() && bi != db {
                continue;
            }
            after_uses.push((bi, pos));
        } else {
            for (si, s) in succs[bi].iter().enumerate() {
                if !live_in[s.index()] && !edge_consumes(bi, si) {
                    edges.push((bi, si));
                }
            }
        }
    }
    let mut existing: Vec<(usize, usize)> = Vec::new();
    for (bi, b) in f.blocks.iter().enumerate() {
        for (k, i) in b.insts.iter().enumerate() {
            if i.op == Op::Drop && i.args[0] == v {
                existing.push((bi, k));
            }
        }
    }
    if existing.is_empty() {
        return false;
    }
    // Apply: remove old drops, insert new ones.
    for b in &mut f.blocks {
        b.insts.retain(|i| !(i.op == Op::Drop && i.args[0] == v));
    }
    // Insert in-block drops from the back so earlier indices stay valid. Positions were
    // computed with the old drops present; recompute by counting removed drops before them.
    let removed_before = |bi: usize, k: usize| {
        existing
            .iter()
            .filter(|(b, kk)| *b == bi && *kk < k)
            .count()
    };
    for (bi, pos) in after_uses.iter_mut() {
        if let Some(p) = pos {
            *p -= removed_before(*bi, *p);
        }
    }
    after_uses.sort_by(|a, b| b.cmp(a));
    for (bi, pos) in after_uses {
        let at = pos.map(|p| p + 1).unwrap_or(0);
        let loc = pos
            .and_then(|p| f.blocks[bi].insts.get(p).map(|i| i.loc))
            .unwrap_or(f.blocks[bi].term_loc);
        f.blocks[bi].insts.insert(
            at,
            Inst {
                op: Op::Drop,
                args: vec![v],
                imm: Imm::None,
                res: None,
                loc,
            },
        );
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
        let mut fwd = Vec::new();
        for (ty, mode) in params {
            let val = f.new_value(ty);
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
