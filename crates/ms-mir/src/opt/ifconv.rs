//! If-conversion: small pure diamonds and triangles become `select`.
//!
//! ```text
//! A: br_if c, B(), C()        A: ...B's insts, C's insts...
//! B: pure insts; br J(x)  =>     p = select c, x, y
//! C: pure insts; br J(y)         br J(p)
//! ```
//!
//! Branchy loops with unpredictable conditions (`if x % 2 == 0 { x / 2 } else { 3 * x + 1 }`)
//! pay a misprediction per iteration; the backend lowers `select` to a conditional move.
//! Only arms with at most [`MAX_ARM`] pure instructions and scalar join arguments are
//! converted, so the work added on the not-taken side stays below a misprediction.

use crate::ir::*;
use crate::types::TyKind;

/// Most instructions hoisted from one arm.
const MAX_ARM: usize = 4;

/// Runs the pass over every function.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for i in 0..m.funcs.len() {
        let mut f = m.funcs[i].clone();
        let mut any = false;
        while convert_one(m, &mut f) {
            any = true;
        }
        if any {
            f.compact_blocks();
            m.funcs[i] = f;
            changed = true;
        }
    }
    changed
}

/// An arm of the branch: either a real block hoisted into the head, or the join itself.
struct Arm {
    block: Option<usize>,
    args: Vec<Value>,
}

fn arm(
    m: &Module,
    f: &Func,
    edges: &[usize],
    head: usize,
    t: &Target,
    join: Option<usize>,
) -> Option<(Arm, usize)> {
    let b = t.block.index();
    if Some(b) == join {
        return Some((
            Arm {
                block: None,
                args: t.args.clone(),
            },
            b,
        ));
    }
    let bd = &f.blocks[b];
    if b == head || edges[b] != 1 || !bd.params.is_empty() || !t.args.is_empty() {
        return None;
    }
    if bd.insts.len() > MAX_ARM
        || !bd
            .insts
            .iter()
            .all(|i| i.op.info().effects.is_pure() && i.res.is_some())
    {
        return None;
    }
    let _ = m;
    let Term::Br(j) = &bd.term else { return None };
    Some((
        Arm {
            block: Some(b),
            args: j.args.clone(),
        },
        j.block.index(),
    ))
}

fn scalar(m: &Module, f: &Func, v: Value) -> bool {
    matches!(
        m.types.kind(f.values[v.index()]),
        TyKind::Int | TyKind::Bool | TyKind::Float
    )
}

fn convert_one(m: &Module, f: &mut Func) -> bool {
    let mut edges = vec![0usize; f.blocks.len()];
    for b in &f.blocks {
        b.term.for_each_target(|t| edges[t.block.index()] += 1);
    }
    for a in 0..f.blocks.len() {
        let Term::CondBr { cond, then, els } = f.blocks[a].term.clone() else {
            continue;
        };
        // The join is the common successor: either arm's target, or both arms' target.
        let join_of = |t: &Target| match &f.blocks[t.block.index()].term {
            Term::Br(j) => Some(j.block.index()),
            _ => None,
        };
        let candidates = [
            Some(then.block.index()),
            Some(els.block.index()),
            join_of(&then),
            join_of(&els),
        ];
        for j in candidates.into_iter().flatten() {
            if j == a || j == 0 {
                continue;
            }
            let Some((ta, jt)) = arm(m, f, &edges, a, &then, Some(j)) else {
                continue;
            };
            let Some((ea, je)) = arm(m, f, &edges, a, &els, Some(j)) else {
                continue;
            };
            if jt != j || je != j || (ta.block.is_none() && ea.block.is_none()) {
                continue;
            }
            let params = f.blocks[j].params.clone();
            if ta.args.len() != params.len() || ea.args.len() != params.len() {
                continue;
            }
            if !ta.args.iter().chain(&ea.args).all(|&v| scalar(m, f, v)) {
                continue;
            }
            let loc = f.blocks[a].term_loc;
            let mut insts = Vec::new();
            for blk in [ta.block, ea.block].into_iter().flatten() {
                insts.append(&mut f.blocks[blk].insts);
                f.blocks[blk].term = Term::Unreachable;
            }
            let mut args = Vec::new();
            for (x, y) in ta.args.iter().zip(&ea.args) {
                if x == y {
                    args.push(*x);
                    continue;
                }
                let r = f.new_value(f.values[x.index()]);
                insts.push(Inst {
                    op: Op::Select,
                    args: vec![cond, *x, *y],
                    imm: Imm::None,
                    res: Some(r),
                    loc,
                });
                args.push(r);
            }
            f.blocks[a].insts.append(&mut insts);
            f.blocks[a].term = Term::Br(Target {
                block: Block(j as u32),
                args,
            });
            return true;
        }
    }
    false
}
