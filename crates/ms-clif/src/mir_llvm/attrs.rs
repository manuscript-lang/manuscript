//! Function attributes proven from MIR: which functions are pure and which always return.

use super::{AREAS, Module, supports};
use crate::layout::Layouts;
use ms_mir::ir::{Imm, Op};
use std::collections::HashMap;

/// Attributes LLVM cannot always infer, for a function with no memory access or fault: its result
/// depends on its arguments alone. A function across a unit boundary is only a `declare`, so the
/// call site would otherwise know nothing. `willreturn` needs the body and its callees to be
/// loop-free and acyclic; `None` when `f` is not such a scalar function at all.
pub(super) fn pure_attrs(
    m: &Module,
    lay: &Layouts,
    idx: usize,
    memo: &mut HashMap<usize, Option<bool>>,
) -> Option<&'static str> {
    let terminates = pure_terminates(m, lay, idx, memo)?;
    Some(if terminates {
        " nounwind willreturn nofree nosync norecurse memory(none)"
    } else {
        " nounwind nofree nosync memory(none)"
    })
}

/// `Some(true)` when `idx` is a scalar function that is pure and always returns, `Some(false)`
/// when it is pure but may loop or recurse for ever, `None` when it is not pure.
fn pure_terminates(
    m: &Module,
    lay: &Layouts,
    idx: usize,
    memo: &mut HashMap<usize, Option<bool>>,
) -> Option<bool> {
    if let Some(v) = memo.get(&idx) {
        return *v;
    }
    // A call back into a function being analysed is recursion: pure, but it may not return.
    memo.insert(idx, Some(false));
    let f = &m.funcs[idx];
    let verdict = if supports(m, lay, f) {
        let rpo = f.rpo();
        let mut order = vec![usize::MAX; f.blocks.len()];
        for (k, b) in rpo.iter().enumerate() {
            order[b.index()] = k;
        }
        let mut terminates = true;
        let mut pure = true;
        for b in &rpo {
            let bd = &f.blocks[b.index()];
            bd.term
                .for_each_target(|t| terminates &= order[t.block.index()] > order[b.index()]);
            for i in &bd.insts {
                // Every op `supports` accepts today is register-only; a memory op added later must
                // not inherit `memory(none)`, so the list is explicit.
                pure &= matches!(i.op, Op::Call) || !touches_memory(i.op);
                if i.op != Op::Call {
                    continue;
                }
                let Imm::Func(c) = i.imm else { continue };
                match pure_terminates(m, lay, c.index(), memo) {
                    Some(t) => terminates &= t,
                    None => pure = false,
                }
            }
        }
        pure.then_some(terminates)
    } else {
        None
    };
    memo.insert(idx, verdict);
    verdict
}

/// Whether a supported op may read or write memory: any op no area declares pure. A function with
/// one is not `memory(none)`.
fn touches_memory(op: Op) -> bool {
    !AREAS.iter().any(|a| (a.pure_op)(op))
}
