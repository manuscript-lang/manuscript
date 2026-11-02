//! The `unroll` pass: fully unrolls innermost counted loops whose trip count is a small constant.
//!
//! ```text
//! h(i, a): br_if (icmp.lt i, 3), body, exit(a)      e: br h(0, a0)
//! body:    a' = f(a, i); br h(i + 1, a')
//! ```
//!
//! becomes one copy of the loop per iteration. Copy `s` is entered with the values the previous
//! copy's back edge passed, so the constants flow through block parameters and the next
//! `simplify` round folds each copy's header test, merges the copies into straight-line code and
//! deletes the original loop. The pass itself never relies on that folding for correctness: the
//! last copy's back edge still reaches the original header, which exits at once.
//!
//! A loop qualifies when it has one entry edge, exits only through the
//! header's false edge, contains no other loop and no `ret`, compares a header parameter with a
//! constant (`icmp.lt` or `icmp.le`), starts from a constant and adds a positive constant on every
//! back edge. The loop must define no owned value. Loop values used after it are routed through new parameters of the exit block, which must have the header as its only
//! predecessor.

use crate::ir::*;
use crate::verify::dominators;
use std::collections::HashMap;

/// Most iterations unrolled.
pub const MAX_TRIPS: i64 = 16;
/// Largest instruction count of the unrolled loop.
pub const MAX_UNROLLED: usize = 300;

/// Runs the pass; returns whether any loop was unrolled.
pub fn run(m: &mut Module) -> bool {
    if std::env::var_os("MS_NO_UNROLL").is_some() {
        return false;
    }
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        // One loop per function and run: the `simplify` round in between removes the dead
        // original, so a nest unrolls from the inside out over the pipeline's rounds.
        if let Some(plan) = find(m, &m.funcs[fi]) {
            apply(&mut m.funcs[fi], plan);
            changed = true;
        }
    }
    changed
}

struct Plan {
    header: usize,
    exit: usize,
    entry: usize,
    body: Vec<usize>,
    trips: usize,
    /// Loop-defined values used outside it.
    escaping: Vec<Value>,
}

fn find(m: &Module, f: &Func) -> Option<Plan> {
    if f.blocks.len() < 3 {
        return None;
    }
    let rpo = f.rpo();
    let preds = f.predecessors();
    let idom = dominators(f, &rpo, &preds);
    let dominates = |a: usize, mut b: usize| -> bool {
        if idom[b] == usize::MAX {
            return false;
        }
        while b != a {
            if b == 0 {
                return false;
            }
            b = idom[b];
        }
        true
    };
    let mut consts: HashMap<Value, i64> = HashMap::new();
    let mut defs: HashMap<Value, &Inst> = HashMap::new();
    for i in f.blocks.iter().flat_map(|b| b.insts.iter()) {
        if let Some(r) = i.res {
            defs.insert(r, i);
            if let (Op::IConst, Imm::Int(c)) = (i.op, i.imm) {
                consts.insert(r, c);
            }
        }
    }
    'next: for h in 1..f.blocks.len() {
        let head = &f.blocks[h];
        let Term::CondBr { cond, then, els } = &head.term else {
            continue;
        };
        let latches: Vec<usize> = preds[h]
            .iter()
            .map(|b| b.index())
            .filter(|&p| dominates(h, p))
            .collect();
        if latches.is_empty() {
            continue;
        }
        // The natural loop.
        let mut body = vec![h];
        let mut work = latches.clone();
        while let Some(b) = work.pop() {
            if body.contains(&b) {
                continue;
            }
            body.push(b);
            work.extend(preds[b].iter().map(|p| p.index()));
        }
        let (x, t) = (els.block.index(), then.block.index());
        if body.contains(&x) || !body.contains(&t) {
            continue;
        }
        let size: usize = body.iter().map(|&b| f.blocks[b].insts.len() + 1).sum();
        for &b in &body {
            let term = &f.blocks[b].term;
            if matches!(term, Term::Ret(_)) {
                continue 'next;
            }
            if b != h && term.successors().iter().any(|s| !body.contains(&s.index())) {
                continue 'next;
            }
            // Innermost only: an edge back to a block other than the header is a nested loop.
            let mut nested = false;
            term.for_each_target(|tg| {
                let tb = tg.block.index();
                if tb != h && body.contains(&tb) && dominates(tb, b) {
                    nested = true;
                }
            });
            if nested {
                continue 'next;
            }
        }
        // Exactly one edge enters the loop; it may be one arm of a conditional branch.
        let mut entry_edges: Vec<(usize, Vec<Value>)> = Vec::new();
        for p in preds[h]
            .iter()
            .map(|b| b.index())
            .filter(|p| !body.contains(p))
        {
            f.blocks[p].term.for_each_target(|tg| {
                if tg.block.index() == h {
                    entry_edges.push((p, tg.args.clone()));
                }
            });
        }
        let [(entry, enter_args)] = &entry_edges[..] else {
            continue;
        };
        let entry = *entry;
        // The counter and its bound.
        let Some(test) = defs.get(cond) else { continue };
        let (Op::ICmp, Imm::Cc(cc @ (Cc::Lt | Cc::Le))) = (test.op, test.imm) else {
            continue;
        };
        let (i, n) = (test.args[0], test.args[1]);
        let Some(ip) = head.params.iter().position(|p| p.value == i) else {
            continue;
        };
        let (Some(&n), Some(&i0)) = (consts.get(&n), consts.get(&enter_args[ip])) else {
            continue;
        };
        let mut step = None;
        for &l in &latches {
            let mut arg = None;
            f.blocks[l].term.for_each_target(|tg| {
                if tg.block.index() == h {
                    arg = Some(tg.args[ip]);
                }
            });
            let Some(add) = arg.and_then(|a| defs.get(&a)) else {
                continue 'next;
            };
            let s = match (add.op, consts.get(&add.args[1])) {
                (Op::IAdd | Op::IAddChk, Some(&s)) if add.args[0] == i && s > 0 => s,
                _ => continue 'next,
            };
            if step.replace(s).is_some_and(|p| p != s) {
                continue 'next;
            }
        }
        let step = step?;
        let mut trips = 0usize;
        let mut v = i0;
        while if cc == Cc::Lt { v < n } else { v <= n } {
            trips += 1;
            if trips as i64 > MAX_TRIPS {
                continue 'next;
            }
            let Some(next) = v.checked_add(step) else {
                continue 'next;
            };
            v = next;
        }
        if trips == 0 || size * trips > MAX_UNROLLED {
            continue;
        }
        // Loop-defined values: none may be owned (a drop would run once per copy and the
        // ownership checks assume one); borrowed ones are fine. Note those used outside.
        let mut inside: Vec<Value> = Vec::new();
        for &b in &body {
            let blk = &f.blocks[b];
            if blk.params.iter().any(|p| p.mode == Mode::Own)
                || blk
                    .insts
                    .iter()
                    .any(|i| m.result_mode(f, i) == Some(Mode::Own))
            {
                continue 'next;
            }
            inside.extend(blk.params.iter().map(|p| p.value));
            inside.extend(blk.insts.iter().filter_map(|i| i.res));
        }
        let is_inside: std::collections::HashSet<Value> = inside.iter().copied().collect();
        let mut escaping: Vec<Value> = Vec::new();
        let mut bad = false;
        for (bi, b) in f.blocks.iter().enumerate() {
            if body.contains(&bi) {
                continue;
            }
            let mut note = |v: Value| {
                if is_inside.contains(&v) {
                    if !dominates(x, bi) {
                        bad = true;
                    }
                    if !escaping.contains(&v) {
                        escaping.push(v);
                    }
                }
            };
            b.insts
                .iter()
                .for_each(|i| i.args.iter().for_each(|&a| note(a)));
            b.term.for_each_use(&mut note);
        }
        if bad || (!escaping.is_empty() && preds[x].len() != 1) {
            continue;
        }
        return Some(Plan {
            header: h,
            exit: x,
            entry,
            body,
            trips,
            escaping,
        });
    }
    None
}

fn apply(f: &mut Func, plan: Plan) {
    let Plan {
        header: h,
        exit: x,
        entry,
        body,
        trips,
        escaping,
    } = plan;
    // Route escaping values through the exit block's parameters.
    if !escaping.is_empty() {
        let mut subst: HashMap<Value, Value> = HashMap::new();
        for &v in &escaping {
            let p = f.new_value(f.ty(v));
            f.blocks[x].params.push(BlockParam {
                value: p,
                mode: Mode::Borrow,
            });
            subst.insert(v, p);
        }
        if let Term::CondBr { els, .. } = &mut f.blocks[h].term {
            els.args.extend(escaping.iter().copied());
        }
        for (bi, b) in f.blocks.iter_mut().enumerate() {
            if body.contains(&bi) {
                continue;
            }
            for i in &mut b.insts {
                for a in &mut i.args {
                    if let Some(&p) = subst.get(a) {
                        *a = p;
                    }
                }
            }
            b.term.for_each_use_mut(|v| {
                if let Some(&p) = subst.get(v) {
                    *v = p;
                }
            });
        }
    }
    let mut prev: Vec<Block> = Vec::new();
    for stage in 0..trips {
        let vmap: HashMap<Value, Value> = body
            .iter()
            .flat_map(|&b| {
                let blk = &f.blocks[b];
                blk.params
                    .iter()
                    .map(|p| p.value)
                    .chain(blk.insts.iter().filter_map(|i| i.res))
                    .collect::<Vec<_>>()
            })
            .collect::<Vec<_>>()
            .into_iter()
            .map(|v| (v, f.new_value(f.ty(v))))
            .collect();
        let bmap: HashMap<usize, Block> = body.iter().map(|&b| (b, f.new_block())).collect();
        let mv = |v: Value| vmap.get(&v).copied().unwrap_or(v);
        for &b in &body {
            let src = f.blocks[b].clone();
            let mt = |t: &Target| Target {
                block: bmap
                    .get(&t.block.index())
                    .copied()
                    .filter(|_| t.block.index() != h)
                    .unwrap_or(t.block),
                args: t.args.iter().map(|&a| mv(a)).collect(),
            };
            let term = match &src.term {
                Term::Br(t) => Term::Br(mt(t)),
                Term::CondBr { cond, then, els } => Term::CondBr {
                    cond: mv(*cond),
                    then: mt(then),
                    els: mt(els),
                },
                Term::Switch {
                    value,
                    cases,
                    default,
                } => Term::Switch {
                    value: mv(*value),
                    cases: cases.iter().map(|(c, t)| (*c, mt(t))).collect(),
                    default: mt(default),
                },
                other => other.clone(),
            };
            f.blocks[bmap[&b].index()] = BlockData {
                params: src
                    .params
                    .iter()
                    .map(|p| BlockParam {
                        value: mv(p.value),
                        mode: p.mode,
                    })
                    .collect(),
                insts: src
                    .insts
                    .iter()
                    .map(|i| Inst {
                        op: i.op,
                        args: i.args.iter().map(|&a| mv(a)).collect(),
                        imm: i.imm,
                        res: i.res.map(mv),
                        loc: i.loc,
                    })
                    .collect(),
                term,
                term_loc: src.term_loc,
            };
        }
        let head = bmap[&h];
        // Enter this copy: from the entry edge, or from the previous copy's back edges.
        if stage == 0 {
            f.blocks[entry].term.for_each_target_mut(|t| {
                if t.block.index() == h {
                    t.block = head;
                }
            });
        } else {
            for &p in &prev {
                f.blocks[p.index()].term.for_each_target_mut(|t| {
                    if t.block.index() == h {
                        t.block = head;
                    }
                });
            }
        }
        prev = body.iter().map(|b| bmap[b]).collect();
    }
}
