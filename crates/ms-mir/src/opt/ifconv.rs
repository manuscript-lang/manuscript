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
//! Arms hold at most [`MAX_ARM`] total scalar instructions, including checked
//! add/mul. Those checks become pure overflow flags and wrapping results with
//! ordered, predicated fault guards at each original source position. This bounds
//! expanded work to seventeen instructions per arm; profitability is workload-specific.

use crate::ir::*;
use crate::types::{Ty, TyKind};
use std::collections::HashSet;

/// Most instructions hoisted from one arm.
const MAX_ARM: usize = 4;

/// Runs the pass over every function.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for i in 0..m.funcs.len() {
        let mut f = m.funcs[i].clone();
        let positive: HashSet<Value> = f
            .blocks
            .iter()
            .flat_map(|b| &b.insts)
            .filter(|i| i.op == Op::IConst && matches!(i.imm, Imm::Int(n) if n > 0))
            .filter_map(|i| i.res)
            .collect();
        let mut any = false;
        if let Some(merged) = merge_returns(m, &f, &positive) {
            f = merged;
            any = true;
        }
        while convert_one(m, &mut f, &positive) {
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

/// Early returns of scalars (`if a < b { return -1 } if a > b { return 1 } return 0`) become one
/// join with a block parameter so the diamonds above can turn into selects. Kept only when
/// every return is absorbed: a partly converted function would just gain a jump.
fn merge_returns(m: &Module, f: &Func, positive: &HashSet<Value>) -> Option<Func> {
    let rets: Vec<usize> = f
        .blocks
        .iter()
        .enumerate()
        .filter(|(_, b)| matches!(b.term, Term::Ret(Some(v)) if scalar(m, f, v)))
        .map(|(i, _)| i)
        .collect();
    if rets.len() < 2 {
        return None;
    }
    let condbrs = |g: &Func| {
        g.blocks
            .iter()
            .filter(|b| matches!(b.term, Term::CondBr { .. }))
            .count()
    };
    let mut g = f.clone();
    let first = rets[0];
    let ty = g.ty(match g.blocks[first].term {
        Term::Ret(Some(v)) => v,
        _ => return None,
    });
    let exit = g.new_block();
    let p = g.new_value(ty);
    g.blocks[exit.index()].params.push(BlockParam {
        value: p,
        mode: Mode::Borrow,
    });
    g.blocks[exit.index()].term = Term::Ret(Some(p));
    g.blocks[exit.index()].term_loc = g.blocks[first].term_loc;
    for &r in &rets {
        let Term::Ret(Some(v)) = g.blocks[r].term else {
            return None;
        };
        g.blocks[r].term = Term::Br(Target {
            block: exit,
            args: vec![v],
        });
    }
    let before = condbrs(&g);
    let mut any = false;
    while convert_one(m, &mut g, positive) {
        any = true;
    }
    (any && condbrs(&g) + rets.len() - 1 <= before).then_some(g)
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
    positive: &HashSet<Value>,
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
    // Effect-free is not enough: unchecked division can still trap, and a pure
    // aggregate projection may borrow memory. Only total scalar operations move.
    if bd.insts.len() > MAX_ARM || !bd.insts.iter().all(|i| speculatable(m, f, i, positive)) {
        return None;
    }
    let Term::Br(j) = &bd.term else { return None };
    Some((
        Arm {
            block: Some(b),
            args: j.args.clone(),
        },
        j.block.index(),
    ))
}

/// Total scalar operations, plus the two checks expanded to predicated guards.
fn speculatable(m: &Module, f: &Func, i: &Inst, positive: &HashSet<Value>) -> bool {
    if !i.res.is_some_and(|v| scalar(m, f, v)) {
        return false;
    }
    match i.op {
        Op::IConst
        | Op::FConst
        | Op::BConst
        | Op::IAdd
        | Op::ISub
        | Op::IMul
        | Op::INeg
        | Op::IAddChk
        | Op::IMulChk
        | Op::IAddOverflow
        | Op::IMulOverflow
        | Op::And
        | Op::Or
        | Op::Xor
        | Op::Shl
        | Op::Sshr
        | Op::Not
        | Op::ICmp
        | Op::FCmp
        | Op::FAdd
        | Op::FSub
        | Op::FMul
        | Op::FDiv
        | Op::FNeg
        | Op::FSqrt
        | Op::FAbs
        | Op::I2F
        | Op::B2I
        | Op::Select => true,
        // Positive literals exclude both zero and MIN / -1.
        Op::SDiv | Op::SRem => positive.contains(&i.args[1]),
        _ => false,
    }
}

/// Move an arm, replacing each faulting operation with a flag and wrapping
/// result. Guards keep the original location (including inline scope), are
/// masked by the arm condition, and retain their order within that arm.
fn hoist(f: &mut Func, arm: &Arm, cond: Value, inverted: bool, out: &mut Vec<Inst>) {
    let Some(blk) = arm.block else {
        return;
    };
    let original = std::mem::take(&mut f.blocks[blk].insts);
    let mut guards = Vec::new();
    let mut active = cond;
    if inverted
        && original
            .iter()
            .any(|i| matches!(i.op, Op::IAddChk | Op::IMulChk))
    {
        active = f.new_value(Ty::BOOL);
        out.push(Inst {
            op: Op::Not,
            args: vec![cond],
            imm: Imm::None,
            res: Some(active),
            loc: f.blocks[blk].term_loc,
        });
    }
    for mut i in original {
        if matches!(i.op, Op::IAddChk | Op::IMulChk) {
            let flag = f.new_value(Ty::BOOL);
            let masked = f.new_value(Ty::BOOL);
            out.push(Inst {
                op: if i.op == Op::IAddChk {
                    Op::IAddOverflow
                } else {
                    Op::IMulOverflow
                },
                args: i.args.clone(),
                imm: Imm::None,
                res: Some(flag),
                loc: i.loc,
            });
            i.op = if i.op == Op::IAddChk {
                Op::IAdd
            } else {
                Op::IMul
            };
            out.push(i.clone());
            out.push(Inst {
                op: Op::And,
                args: vec![active, flag],
                imm: Imm::None,
                res: Some(masked),
                loc: i.loc,
            });
            guards.push(Inst {
                op: Op::IntOverflowIf,
                args: vec![masked],
                imm: Imm::None,
                res: None,
                loc: i.loc,
            });
        } else {
            out.push(i);
        }
    }
    out.append(&mut guards);
    f.blocks[blk].term = Term::Unreachable;
}

fn scalar(m: &Module, f: &Func, v: Value) -> bool {
    matches!(
        m.types.kind(f.values[v.index()]),
        TyKind::Int | TyKind::Bool | TyKind::Float
    )
}

fn convert_one(m: &Module, f: &mut Func, positive: &HashSet<Value>) -> bool {
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
            let Some((ta, jt)) = arm(m, f, &edges, a, &then, Some(j), positive) else {
                continue;
            };
            let Some((ea, je)) = arm(m, f, &edges, a, &els, Some(j), positive) else {
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
            hoist(f, &ta, cond, false, &mut insts);
            hoist(f, &ea, cond, true, &mut insts);
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
