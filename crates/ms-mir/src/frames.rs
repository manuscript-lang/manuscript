//! Which interface borrows and closure objects of a function cannot outlive its frame, so a backend
//! can keep them in a stack slot instead of on the heap.

use crate::ir::{Func, Imm, Mode, Module, Op, Term};
use std::collections::HashSet;

/// The `iface.borrow` results of `f` whose only uses are arguments of calls to functions that
/// whose result is not a view of their arguments, and drops. Such an interface cannot outlive the
/// frame, so its leaves need no heap box.
pub fn framed_iface_borrows(m: &Module, f: &Func) -> HashSet<usize> {
    let mut framed = HashSet::new();
    for b in &f.blocks {
        for i in &b.insts {
            if i.op == Op::IfaceBorrow
                && let Some(r) = i.res
            {
                framed.insert(r.index());
            }
        }
    }
    if framed.is_empty() {
        return framed;
    }
    for b in &f.blocks {
        for i in &b.insts {
            let plain = match i.op {
                Op::Drop => true,
                Op::Call | Op::CallMethod => !m.result_views(f, i),
                _ => false,
            };
            if !plain {
                for a in &i.args {
                    framed.remove(&a.index());
                }
            }
        }
        if let Term::Ret(Some(v)) = &b.term {
            framed.remove(&v.index());
        }
        if let Term::CondBr { cond: v, .. } | Term::Switch { value: v, .. } = &b.term {
            framed.remove(&v.index());
        }
        b.term.for_each_target(|t| {
            for a in &t.args {
                framed.remove(&a.index());
            }
        });
    }
    framed
}

/// The `closure.new` results of `f` that cannot outlive the frame: their only uses are drops,
/// being called, and arguments a callee only borrows whose result does not point into them.
/// A closure that owns a resource (a capture closer) keeps its heap object, which the
/// unwinder releases.
pub fn framed_closure_objects(m: &Module, f: &Func) -> HashSet<usize> {
    let mut framed = HashSet::new();
    for b in &f.blocks {
        for i in &b.insts {
            if let (Op::ClosureNew, Imm::Func(c), Some(r)) = (i.op, i.imm, i.res)
                && m.funcs[c.index()].capture_closers.is_empty()
            {
                framed.insert(r.index());
            }
        }
    }
    if framed.is_empty() {
        return framed;
    }
    for b in &f.blocks {
        for i in &b.insts {
            let borrows = |k: usize| match (i.op, i.imm) {
                (Op::Call, Imm::Func(g)) => m.funcs[g.index()]
                    .params
                    .get(k)
                    .is_some_and(|p| p.mode == Mode::Borrow),
                (Op::CallRt, Imm::Ext(e)) => m.externs[e.index()]
                    .params
                    .get(k)
                    .is_some_and(|p| p.mode == Mode::Borrow),
                (Op::CallInd, _) => k == 0,
                _ => false,
            };
            let plain_call =
                matches!(i.op, Op::Call | Op::CallRt | Op::CallInd) && !m.result_views(f, i);
            for (k, a) in i.args.iter().enumerate() {
                let ok = i.op == Op::Drop || (plain_call && borrows(k));
                if !ok {
                    framed.remove(&a.index());
                }
            }
        }
        if let Term::Ret(Some(v)) = &b.term {
            framed.remove(&v.index());
        }
        if let Term::CondBr { cond: v, .. } | Term::Switch { value: v, .. } = &b.term {
            framed.remove(&v.index());
        }
        b.term.for_each_target(|t| {
            for a in &t.args {
                framed.remove(&a.index());
            }
        });
    }
    framed
}
