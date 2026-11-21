//! What the cancel-exit context of `elaborate` needs from the old `unwind` pass: which functions
//! start tasks or park, and which parameters a callee only borrows from a stack slot. The pass
//! itself (cleanup registration around every park or fault point) is
//! `compiler/src/mir/mir_unwind*.c`.

use crate::ir::*;
use crate::types::Ty;
use std::collections::BTreeSet;

pub fn starts_tasks(m: &Module) -> bool {
    m.externs.iter().any(|e| e.role == ExternRole::SpawnsTask)
}

fn leaf_extern(m: &Module, e: ExtId) -> bool {
    let d = &m.externs[e.index()];
    d.noreturn || d.leaf
}

/// Which functions can reach a cancellation point: a poll, an indirect call or a runtime call
/// that is not a known leaf, directly or through a callee.
pub(crate) fn parking_funcs(m: &Module) -> Vec<bool> {
    let n = m.funcs.len();
    let mut parks = vec![false; n];
    let mut callees: Vec<Vec<usize>> = vec![Vec::new(); n];
    for (i, f) in m.funcs.iter().enumerate() {
        for inst in f.blocks.iter().flat_map(|b| &b.insts) {
            match (inst.op, inst.imm) {
                (Op::Poll | Op::CallInd | Op::CallMethod, _) => parks[i] = true,
                (Op::CallRt, Imm::Ext(e)) if !leaf_extern(m, e) => parks[i] = true,
                (Op::Call, Imm::Func(g)) => callees[i].push(g.index()),
                _ => {}
            }
        }
    }
    let mut changed = true;
    while changed {
        changed = false;
        for i in 0..n {
            if !parks[i] && callees[i].iter().any(|&g| parks[g]) {
                parks[i] = true;
                changed = true;
            }
        }
    }
    parks
}

/// Per function and parameter, whether the parameter is a pointer to a slot whose contents the
/// function only borrows: it `take`s them, uses them as borrows, and `put`s the same value back.
pub(crate) fn slot_safe_params(m: &Module) -> Vec<Vec<bool>> {
    let mut safe: Vec<Vec<bool>> = m
        .funcs
        .iter()
        .map(|f| f.params.iter().map(|p| p.ty == Ty::PTR).collect())
        .collect();
    let mut changed = true;
    while changed {
        changed = false;
        for (fi, f) in m.funcs.iter().enumerate() {
            for k in 0..f.params.len() {
                if safe[fi][k] && !borrows_slot_param(m, &safe, f, k) {
                    safe[fi][k] = false;
                    changed = true;
                }
            }
        }
    }
    safe
}

fn borrows_slot_param(m: &Module, safe: &[Vec<bool>], f: &Func, k: usize) -> bool {
    let Some(p) = f
        .blocks
        .first()
        .and_then(|b| b.params.get(k))
        .map(|p| p.value)
    else {
        return false;
    };
    borrows_slot_value(m, safe, &[], f, p)
}

/// Whether closure `g` only borrows the slot it captured by reference as its capture `idx`: every
/// read of that capture (`closure.cap`) satisfies [`borrows_slot_value`].
pub(crate) fn closure_borrows_capture(
    m: &Module,
    safe: &[Vec<bool>],
    parks: &[bool],
    g: FuncId,
    idx: u32,
) -> bool {
    // A closure that never parks cannot be cancelled while it holds the slot's value out.
    if parks.get(g.index()) == Some(&false) {
        return true;
    }
    let Some(f) = m.funcs.get(g.index()) else {
        return false;
    };
    let mut any = false;
    for inst in f.blocks.iter().flat_map(|b| &b.insts) {
        if let (Op::ClosureCap, Imm::Idx(i), Some(r)) = (inst.op, inst.imm, inst.res)
            && i == idx
        {
            any = true;
            if !borrows_slot_value(m, safe, parks, f, r) {
                return false;
            }
        }
    }
    any
}

/// Whether `f` only borrows the contents of the slot that the pointer `p` names (a parameter or a
/// capture): it `take`s them, uses them as borrows, and `put`s the same value back.
fn borrows_slot_value(m: &Module, safe: &[Vec<bool>], parks: &[bool], f: &Func, p: Value) -> bool {
    // What `p` holds (taken, or passed on to a block parameter), and the borrows derived from it.
    let mut taken: BTreeSet<u32> = BTreeSet::new();
    let mut derived: BTreeSet<u32> = BTreeSet::new();
    // Local slots that only ever hold the taken value: it is parked there while a callee that
    // only borrows it runs, then taken back (`serve_buffered` hands the exchange to `read_body`).
    let mut fwd: BTreeSet<u32> = BTreeSet::new();
    let local_slots: BTreeSet<u32> = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter(|i| i.op == Op::Slot)
        .filter_map(|i| i.res.map(|r| r.0))
        .collect();
    for inst in f.blocks.iter().flat_map(|b| &b.insts) {
        if let (Op::Take, Some(r)) = (inst.op, inst.res)
            && inst.args.first() == Some(&p)
        {
            taken.insert(r.0);
        }
    }
    let mut grew = true;
    while grew {
        grew = false;
        for inst in f.blocks.iter().flat_map(|b| &b.insts) {
            match (inst.op, inst.res) {
                (Op::Put, _)
                    if inst.args.len() == 2
                        && local_slots.contains(&inst.args[0].0)
                        && taken.contains(&inst.args[1].0)
                        && fwd.insert(inst.args[0].0) =>
                {
                    grew = true;
                }
                (Op::Take, Some(r))
                    if inst.args.first().is_some_and(|a| fwd.contains(&a.0))
                        && taken.insert(r.0) =>
                {
                    grew = true;
                }
                _ => {}
            }
        }
        for inst in f.blocks.iter().flat_map(|b| &b.insts) {
            let Some(r) = inst.res else { continue };
            let from_held = inst
                .args
                .iter()
                .any(|a| taken.contains(&a.0) || derived.contains(&a.0));
            let view = inst.op == Op::Load && inst.args.first() == Some(&p);
            // A value that owns nothing and is no address (a promise handle, a number) is no
            // borrow of the slot's contents.
            let holds = m.needs_drop(f.ty(r)) || f.ty(r) == Ty::PTR;
            if (from_held || view)
                && holds
                && !taken.contains(&r.0)
                && m.result_mode(f, inst) != Some(Mode::Move)
                && derived.insert(r.0)
            {
                grew = true;
            }
        }
        for blk in &f.blocks {
            blk.term.for_each_target(|t| {
                for (a, bp) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                    if taken.contains(&a.0) && taken.insert(bp.value.0) {
                        grew = true;
                    }
                }
            });
        }
    }
    // A parameter that takes the value on some edges takes it on all, or it could swap values.
    for blk in &f.blocks {
        let mut mixed = false;
        blk.term.for_each_target(|t| {
            for (a, bp) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                mixed |= taken.contains(&bp.value.0) && !taken.contains(&a.0);
            }
        });
        if mixed {
            return false;
        }
    }
    for blk in &f.blocks {
        for inst in &blk.insts {
            let modes = crate::verify::arg_modes(m, f, inst);
            for (i, a) in inst.args.iter().enumerate() {
                if fwd.contains(&a.0) {
                    let ok = match (inst.op, inst.imm) {
                        (Op::Take, _) => i == 0,
                        (Op::Put, _) => i == 0 && taken.contains(&inst.args[1].0),
                        (Op::Call, Imm::Func(g)) => {
                            safe.get(g.index()).and_then(|s| s.get(i)).copied() == Some(true)
                        }
                        _ => false,
                    };
                    if !ok {
                        return false;
                    }
                } else if *a == p {
                    let ok = match (inst.op, inst.imm) {
                        // A closure made here that captures the slot by reference only borrows it.
                        (Op::ClosureNew, Imm::Func(g)) => {
                            closure_borrows_capture(m, safe, parks, g, i as u32)
                        }
                        (Op::Take | Op::Load, _) => i == 0,
                        (Op::Put, _) => i == 0 && taken.contains(&inst.args[1].0),
                        (Op::Call, Imm::Func(g)) => {
                            safe.get(g.index()).and_then(|s| s.get(i)).copied() == Some(true)
                        }
                        _ => false,
                    };
                    if !ok {
                        return false;
                    }
                } else if taken.contains(&a.0) || derived.contains(&a.0) {
                    let putback = inst.op == Op::Put
                        && i == 1
                        && (inst.args[0] == p || fwd.contains(&inst.args[0].0));
                    // A method call hands its receiver to every implementation of the method,
                    // which may take the payload out of its slot.
                    let method = match (inst.op, inst.imm) {
                        (Op::CallMethod, Imm::Method(iface, slot)) if i == 0 => {
                            m.vtables.iter().filter(|v| v.iface == iface).all(|v| {
                                v.methods.get(slot as usize).is_some_and(|g| {
                                    safe.get(g.index()).and_then(|s| s.first()).copied()
                                        == Some(true)
                                })
                            })
                        }
                        _ => true,
                    };
                    // Writing a scalar through a derived address changes no owned value.
                    let scalar_write = inst.op == Op::Store
                        && i == 0
                        && inst.args.get(1).is_some_and(|v| !m.needs_drop(f.ty(*v)));
                    let borrowed = modes.get(i) == Some(&Mode::Borrow)
                        && method
                        && (scalar_write
                            || !matches!(
                                inst.op,
                                Op::MoveOut
                                    | Op::Store
                                    | Op::Put
                                    | Op::CleanupPush
                                    | Op::TypeFill
                                    | Op::ListFill
                                    | Op::CallInd
                            ));
                    if !putback && !borrowed {
                        return false;
                    }
                }
            }
        }
        let mut leaves = false;
        if let Term::Ret(Some(v)) = &blk.term {
            leaves |= *v == p || taken.contains(&v.0) || derived.contains(&v.0);
        }
        // An edge may pass only the value itself on, never a borrow of it or the slot.
        blk.term.for_each_target(|t| {
            for a in &t.args {
                leaves |= *a == p || derived.contains(&a.0);
            }
        });
        if leaves {
            return false;
        }
    }
    true
}
