//! The `loopslot` pass: keeps a loop-carried owned value in one stack slot.
//!
//! A runtime mutator works on a value in memory, so a loop that threads an owned buffer
//! through a block parameter moves it into a slot, calls, and moves it back on every pass:
//!
//! ```text
//! b1(%p: own T):  ..  s = slot T;  put s, %p;  call.rt f(s, ..);  t = take T s;  br b1(t)
//! ```
//!
//! When every use of the parameter is such a `put` into a slot of its own block, the value can
//! live in one slot made at function entry: the entry edges put into it, the calls use it
//! directly, and the parameter, the per-pass `put` and the `take` go away.

use crate::ir::{Block, Func, Imm, Inst, Mode, Module, Op, Term, Value};
use crate::types::Ty;

/// Runs the pass; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for f in &mut m.funcs {
        while carry_one(f) {
            changed = true;
        }
    }
    changed
}

/// One `put`/`take` pair in a block: indexes of the `slot`, the `put` and the optional `take`.
struct Pair {
    block: Block,
    slot: usize,
    put: usize,
    take: Option<usize>,
}

fn carry_one(f: &mut Func) -> bool {
    let mut uses = vec![0u32; f.values.len()];
    for b in &f.blocks {
        for i in &b.insts {
            for a in &i.args {
                uses[a.index()] += 1;
            }
        }
        b.term.for_each_use(|v| uses[v.index()] += 1);
    }
    for l in 1..f.blocks.len() {
        for k in 0..f.blocks[l].params.len() {
            if f.blocks[l].params[k].mode != Mode::Own {
                continue;
            }
            if let Some(pairs) = plan(f, Block(l as u32), k, &uses) {
                apply(f, Block(l as u32), k, &pairs);
                return true;
            }
        }
    }
    false
}

/// The pairs that use parameter `k` of `l`, when the parameter qualifies.
fn plan(f: &Func, l: Block, k: usize, uses: &[u32]) -> Option<Vec<Pair>> {
    let p = f.blocks[l.index()].params[k].value;
    let ty = f.values[p.index()];
    let mut pairs = Vec::new();
    let mut seen = 0;
    for (bi, b) in f.blocks.iter().enumerate() {
        for (pi, put) in b.insts.iter().enumerate() {
            if put.op != Op::Put || put.args[1] != p {
                continue;
            }
            seen += 1;
            let s = put.args[0];
            let slot = b.insts[..pi]
                .iter()
                .position(|i| i.op == Op::Slot && i.res == Some(s))?;
            if b.insts[slot].imm != Imm::Ty(ty) {
                return None;
            }
            let take = b.insts[pi + 1..]
                .iter()
                .position(|i| i.op == Op::Take && i.args[0] == s)
                .map(|x| x + pi + 1);
            // The slot is only put into, called on and taken from, inside this block.
            let takes = usize::from(take.is_some());
            let calls = b.insts[pi + 1..]
                .iter()
                .filter(|i| i.op == Op::CallRt)
                .map(|i| i.args.iter().filter(|&&a| a == s).count())
                .sum::<usize>();
            if uses[s.index()] as usize != 1 + takes + calls {
                return None;
            }
            if let Some(ti) = take {
                let t = b.insts[ti].res?;
                let calls_between = b.insts[pi + 1..ti].iter().all(|i| i.op == Op::CallRt);
                let Term::Br(tg) = &b.term else {
                    return None;
                };
                if !calls_between
                    || b.insts[ti].imm != Imm::Ty(ty)
                    || uses[t.index()] != 1
                    || tg.block != l
                    || tg.args[k] != t
                {
                    return None;
                }
            }
            pairs.push(Pair {
                block: Block(bi as u32),
                slot,
                put: pi,
                take,
            });
        }
    }
    // Every use of the parameter is one of the puts, and the loop really carries it.
    if seen == 0 || uses[p.index()] != seen || pairs.iter().all(|x| x.take.is_none()) {
        return None;
    }
    // An edge that does not carry the value back is an entry edge; it must be a plain `br`.
    for (bi, b) in f.blocks.iter().enumerate() {
        let mut ok = true;
        let back = pairs
            .iter()
            .any(|x| x.block.index() == bi && x.take.is_some());
        b.term.for_each_target(|t| {
            if t.block == l && !back && !matches!(b.term, Term::Br(_)) {
                ok = false;
            }
        });
        if !ok {
            return None;
        }
    }
    Some(pairs)
}

fn apply(f: &mut Func, l: Block, k: usize, pairs: &[Pair]) {
    let p = f.blocks[l.index()].params[k].value;
    let ty = f.values[p.index()];
    let slot_imm = f.blocks[pairs[0].block.index()].insts[pairs[0].slot].imm;
    let s = f.new_value(Ty::PTR);
    let loc = f.blocks[l.index()].term_loc;
    // Entry edges put into the shared slot; back edges are the pairs' own blocks.
    for bi in 0..f.blocks.len() {
        let back = pairs
            .iter()
            .any(|x| x.block.index() == bi && x.take.is_some());
        let mut arg: Option<Value> = None;
        let b = &mut f.blocks[bi];
        b.term.for_each_target_mut(|t| {
            if t.block == l {
                let a = t.args.remove(k);
                if !back {
                    arg = Some(a);
                }
            }
        });
        if let Some(a) = arg {
            f.blocks[bi].insts.push(Inst {
                op: Op::Put,
                args: vec![s, a],
                imm: Imm::None,
                res: None,
                loc,
            });
        }
    }
    // Rewrite each pair to use the shared slot.
    for x in pairs {
        let b = &mut f.blocks[x.block.index()];
        let old = b.insts[x.slot].res.expect("slot result");
        for i in &mut b.insts {
            for a in &mut i.args {
                if *a == old {
                    *a = s;
                }
            }
        }
        let mut dead = vec![x.slot, x.put];
        dead.extend(x.take);
        dead.sort_unstable();
        for d in dead.into_iter().rev() {
            b.insts.remove(d);
        }
    }
    f.blocks[l.index()].params.remove(k);
    f.blocks[0].insts.insert(
        0,
        Inst {
            op: Op::Slot,
            args: Vec::new(),
            imm: slot_imm,
            res: Some(s),
            loc,
        },
    );
    let _ = ty;
}
