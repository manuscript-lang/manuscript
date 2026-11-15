//! The `unwind` pass: lets a cancelled or faulted task release the values its frames own.
//!
//! Cancellation and a guarded fault leave a task by a jump, so no `drop` after the park or
//! fault point runs. Around every instruction that can reach a cancellation point or fault the
//! pass registers one runtime cleanup per owned value that is live across it, and discards
//! them when it completes; a run of such instructions with the same live values shares one
//! registration:
//!
//! ```text
//! h = cleanup.push v, drop_if_unwinding;  ..;  call f(..);  call.rt msrt_cleanup_discard(h)
//! ```
//!
//! `cleanup.push` keeps a bitwise copy of `v`, which is sound because `v` is owned, live and
//! not consumed by the call. The cleanup drops `v` only when `msrt_unwind_drops` says a
//! cancellation or a fault is leaving a guarded task; a fault outside any guard or a process
//! exit frees nothing.
//!
//! A value a function parks while it sits in a stack slot (`put` into a slot, a call that takes it
//! out and puts it back, `take`) is registered the same way when every callee that receives the
//! slot only borrows what it takes from it (a "cell"). The registration keeps a bitwise copy of
//! the slot's contents, which stays valid because no such callee moving_params or moves a part out of
//! them. Any other use of the slot leaves its contents to leak.
//!
//! Only programs that start tasks or workers, or catch a fault with `expect_fault`, are rewritten.
//! A value moved out of a field and not yet filled back leaves a hole in its owner, so calls inside that window are skipped, as
//! are values held in stack slots that a callee may consume or rearrange; both only leak.

use crate::builder::FuncBuilder;
use crate::ir::*;
use crate::types::Ty;
use std::collections::{BTreeMap, BTreeSet, HashMap};

/// Rewrites `m` so cancellation releases owned locals; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    if !starts_tasks(m) {
        return false;
    }
    let parks = parking_funcs(m);
    let faults = faulting_funcs(m, &parks);
    let count = m.funcs.len();
    let discard = m.add_extern(ExternDef {
        name: "msrt_cleanup_discard".into(),
        params: vec![Param {
            ty: Ty::INT,
            mode: Mode::Borrow,
        }],
        ret: Ty::UNIT,
        noreturn: false,
        pure_: false,
        fresh: false,
        role: ExternRole::CleanupDiscard,
        leaf: true,
        reads: false,
    });
    let mut cx = Cx {
        parks,
        faults,
        safe: slot_safe_params(m),
        pointer_params: m
            .funcs
            .iter()
            .map(|f| f.params.iter().map(|p| p.ty == Ty::PTR).collect())
            .collect(),
        closure_targets: closure_targets(m),
        cells: BTreeMap::new(),
        discard,
        closers: HashMap::new(),
        with_closers: HashMap::new(),
        slot_droppers: HashMap::new(),
        raw_closers: HashMap::new(),
        raw_values: BTreeSet::new(),
    };
    let mut changed = false;
    for fi in 0..count {
        // The stand-in keeps the signature, so a recursive call still reads which arguments
        // it consumes.
        let stand_in = m.funcs[fi].signature_stand_in();
        let mut f = std::mem::replace(&mut m.funcs[fi], stand_in);
        changed |= function(m, &mut cx, &mut f);
        m.funcs[fi] = f;
    }
    changed
}

struct Cx {
    parks: Vec<bool>,
    /// Which functions can fault, directly or through a callee.
    faults: Vec<bool>,
    /// Per function and parameter: whether the parameter is a slot pointer whose contents the
    /// function only borrows while it runs, so the caller may keep covering them.
    safe: Vec<Vec<bool>>,
    /// Per function and parameter: whether it is a pointer. Taken before any function is
    /// swapped out for rewriting, since the one being rewritten has no parameters meanwhile.
    pointer_params: Vec<Vec<bool>>,
    /// The functions a `closure.new` can make callable through `call.ind`.
    closure_targets: Vec<FuncId>,
    /// The slots of the function being rewritten that hold an owned value between a `put` and a
    /// `take`, with the type held.
    cells: BTreeMap<u32, Ty>,
    discard: ExtId,
    /// The cleanup that drops a value of a type while a cancellation unwinds.
    closers: HashMap<Ty, FuncId>,
    /// A scope close followed by the drop of the value it closed, per close function.
    with_closers: HashMap<FuncId, FuncId>,
    /// The cleanup that drops what a slot holds, per type held.
    slot_droppers: HashMap<Ty, FuncId>,
    raw_closers: HashMap<Ty, FuncId>,
    /// The values of the function being rewritten that are raw slot copies.
    raw_values: BTreeSet<u32>,
}

pub fn starts_tasks(m: &Module) -> bool {
    m.externs.iter().any(|e| e.role == ExternRole::SpawnsTask)
}

fn leaf_extern(m: &Module, e: ExtId) -> bool {
    let d = &m.externs[e.index()];
    d.noreturn || d.leaf
}

/// Which functions can reach a cancellation point: a poll, an indirect call or a runtime call
/// that is not a known leaf, directly or through a callee.
fn parking_funcs(m: &Module) -> Vec<bool> {
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

/// Which functions can fault: a checked operation, an explicit fault, an indirect call or a
/// runtime call, directly or through a callee. A function that parks can also fault.
fn faulting_funcs(m: &Module, parks: &[bool]) -> Vec<bool> {
    let n = m.funcs.len();
    let mut faults = parks.to_vec();
    let mut callees: Vec<Vec<usize>> = vec![Vec::new(); n];
    for (i, f) in m.funcs.iter().enumerate() {
        if f.blocks.iter().any(|b| matches!(b.term, Term::Fault(_))) {
            faults[i] = true;
        }
        for inst in f.blocks.iter().flat_map(|b| &b.insts) {
            match (inst.op, inst.imm) {
                (Op::Call, Imm::Func(g)) => callees[i].push(g.index()),
                (Op::Call, _) => {}
                (Op::CallRt | Op::CallInd | Op::CallMethod, _) => faults[i] = true,
                (op, _) if op.info().effects.faults => faults[i] = true,
                _ => {}
            }
        }
    }
    let mut changed = true;
    while changed {
        changed = false;
        for i in 0..n {
            if !faults[i] && callees[i].iter().any(|&g| faults[g]) {
                faults[i] = true;
                changed = true;
            }
        }
    }
    faults
}

/// Whether `inst` can reach a cancellation point or fault.
fn exits_at(m: &Module, cx: &Cx, inst: &Inst) -> bool {
    if parks_at(m, cx, inst) {
        return true;
    }
    match (inst.op, inst.imm) {
        (Op::Call, Imm::Func(g)) => cx.faults.get(g.index()).copied().unwrap_or(true),
        (Op::Call, _) => true,
        (op, _) => op.info().effects.faults,
    }
}

/// Whether `inst` can reach a cancellation point.
fn parks_at(m: &Module, cx: &Cx, inst: &Inst) -> bool {
    match (inst.op, inst.imm) {
        (Op::Poll | Op::CallInd | Op::CallMethod, _) => true,
        (Op::CallRt, Imm::Ext(e)) => !leaf_extern(m, e),
        (Op::Call, Imm::Func(g)) => cx.parks.get(g.index()).copied().unwrap_or(true),
        _ => false,
    }
}

/// The values of `f` that are raw slot copies: they own nothing, so an unwind frees their buffer
/// and leaves the elements to the list they were copied from.
fn raw_slots(m: &Module, f: &Func) -> BTreeSet<u32> {
    f.blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter(|i| {
            (f.raw_scratch && i.op == Op::ListNew)
                || matches!((i.op, i.imm), (Op::CallRt, Imm::Ext(e)) if m.externs[e.index()].role == ExternRole::RawSlots)
        })
        .filter_map(|i| i.res.map(|r| r.0))
        .collect()
}

/// The function that frees the buffer of a raw slot copy while an unwind runs.
fn raw_closer(m: &mut Module, cx: &mut Cx, ty: Ty) -> FuncId {
    if let Some(f) = cx.raw_closers.get(&ty) {
        return *f;
    }
    let free = m.add_extern(ExternDef {
        name: "msrt_list_free_raw".into(),
        params: vec![Param {
            ty,
            mode: Mode::Move,
        }],
        ret: Ty::UNIT,
        noreturn: false,
        pure_: false,
        fresh: false,
        role: ExternRole::RawFree,
        leaf: true,
        reads: false,
    });
    let mut b = FuncBuilder::new(
        m,
        "unwind.free_raw",
        vec![Param {
            ty,
            mode: Mode::Move,
        }],
        Ty::UNIT,
    );
    b.func_mut().linkage = Linkage::Internal;
    b.func_mut().unwind_only = true;
    let v = b.params()[0];
    b.call_rt(free, &[v]);
    let u = b.unit();
    b.ret(Some(u));
    let f = b.into_func();
    let id = m.add_func(f);
    cx.raw_closers.insert(ty, id);
    id
}

/// The function that drops its argument when a cancellation is unwinding.
fn closer(m: &mut Module, cx: &mut Cx, ty: Ty) -> FuncId {
    if let Some(f) = cx.closers.get(&ty) {
        return *f;
    }
    let gate = m.add_extern(ExternDef {
        name: "msrt_unwind_drops".into(),
        params: Vec::new(),
        ret: Ty::BOOL,
        noreturn: false,
        pure_: false,
        fresh: false,
        role: ExternRole::None,
        leaf: true,
        reads: false,
    });
    let mut b = FuncBuilder::new(
        m,
        "unwind.drop",
        vec![Param {
            ty,
            mode: Mode::Move,
        }],
        Ty::UNIT,
    );
    b.func_mut().linkage = Linkage::Internal;
    b.func_mut().unwind_only = true;
    let v = b.params()[0];
    let on = b.call_rt(gate, &[]);
    b.emit(Op::DropIf, &[on, v], Imm::None, None);
    let u = b.unit();
    b.ret(Some(u));
    let f = b.into_func();
    let id = m.add_func(f);
    cx.closers.insert(ty, id);
    id
}

/// The cleanup that runs `close` on a scope-closed value and then drops it while a cancellation
/// unwinds. A cancelled task never reaches the drop after the block, and the per-call drops
/// leave this value to its close so that nothing closes a freed value.
fn with_closer(m: &mut Module, cx: &mut Cx, close: FuncId) -> Option<FuncId> {
    if let Some(f) = cx.with_closers.get(&close) {
        return Some(*f);
    }
    let callee = m.funcs.get(close.index())?;
    let [param] = callee.params.as_slice() else {
        return None;
    };
    if let Some(ty) = slot_close_value(m, close) {
        return slot_with_closer(m, cx, close, ty);
    }
    // Closing that moving_params the value, or yields one that needs a drop, leaves nothing to add.
    if param.mode == Mode::Move || callee.ret != Ty::UNIT {
        return None;
    }
    let ty = param.ty;
    if !m.needs_drop(ty) {
        return None;
    }
    let gate = m.add_extern(ExternDef {
        name: "msrt_unwind_drops".into(),
        params: Vec::new(),
        ret: Ty::BOOL,
        noreturn: false,
        pure_: false,
        fresh: false,
        role: ExternRole::None,
        leaf: true,
        reads: false,
    });
    let mut b = FuncBuilder::new(
        m,
        "unwind.close_drop",
        vec![Param {
            ty,
            mode: Mode::Move,
        }],
        Ty::UNIT,
    );
    b.func_mut().linkage = Linkage::Internal;
    let v = b.params()[0];
    b.call(close, &[v]);
    let on = b.call_rt(gate, &[]);
    b.emit(Op::DropIf, &[on, v], Imm::None, None);
    let u = b.unit();
    b.ret(Some(u));
    let f = b.into_func();
    let id = m.add_func(f);
    cx.with_closers.insert(close, id);
    Some(id)
}

/// The type of the value a scope close works on in place, when `close` is the thunk of a
/// binding that lives in memory: it takes the slot's address and leaves the value there.
fn slot_close_value(m: &Module, close: FuncId) -> Option<Ty> {
    m.funcs.get(close.index())?.slot_close
}

/// [`with_closer`] for a slot-held value: runs the thunk, then drops what the slot still holds.
/// The thunk closes the value in place, so it is still there for this drop.
fn slot_with_closer(m: &mut Module, cx: &mut Cx, close: FuncId, ty: Ty) -> Option<FuncId> {
    let dropper = slot_dropper(m, cx, ty);
    let discard = cx.discard;
    let covers = !takes_from_slot(m, close, &mut HashMap::new());
    let gate = m.add_extern(ExternDef {
        name: "msrt_unwind_drops".into(),
        params: Vec::new(),
        ret: Ty::BOOL,
        noreturn: false,
        pure_: false,
        fresh: false,
        role: ExternRole::None,
        leaf: true,
        reads: false,
    });
    let mut b = FuncBuilder::new(
        m,
        "unwind.close_drop_slot",
        vec![Param {
            ty: Ty::PTR,
            mode: Mode::Borrow,
        }],
        Ty::UNIT,
    );
    b.func_mut().linkage = Linkage::Internal;
    let p = b.params()[0];
    // A fault inside the close ends this cleanup, so the slot is registered for its duration
    // unless the close takes parts out of it.
    let covering = covers.then(|| {
        b.emit(Op::CleanupPush, &[p], Imm::Func(dropper), Some(Ty::INT))
            .expect("push")
    });
    b.call(close, &[p]);
    if let Some(covering) = covering {
        b.call_rt(discard, &[covering]);
    }
    let on = b.call_rt(gate, &[]);
    let held = b.emit(Op::Take, &[p], Imm::Ty(ty), Some(ty)).expect("take");
    b.emit(Op::DropIf, &[on, held], Imm::None, None);
    let u = b.unit();
    b.ret(Some(u));
    let f = b.into_func();
    let id = m.add_func(f);
    cx.with_closers.insert(close, id);
    Some(id)
}

/// Points every scope close registered in `f` at its closing-then-dropping variant.
fn wrap_with_closers(m: &mut Module, cx: &mut Cx, f: &mut Func) -> bool {
    let mut changed = false;
    for bi in 0..f.blocks.len() {
        for ii in 0..f.blocks[bi].insts.len() {
            let inst = &f.blocks[bi].insts[ii];
            let (Op::CleanupPush, Imm::Func(g)) = (inst.op, inst.imm) else {
                continue;
            };
            if let Some(w) = with_closer(m, cx, g) {
                f.blocks[bi].insts[ii].imm = Imm::Func(w);
                changed = true;
            }
        }
    }
    changed
}

/// The function that drops what the slot at its argument holds when a cancellation or fault is
/// unwinding.
fn slot_dropper(m: &mut Module, cx: &mut Cx, ty: Ty) -> FuncId {
    if let Some(f) = cx.slot_droppers.get(&ty) {
        return *f;
    }
    let gate = m.add_extern(ExternDef {
        name: "msrt_unwind_drops".into(),
        params: Vec::new(),
        ret: Ty::BOOL,
        noreturn: false,
        pure_: false,
        fresh: false,
        role: ExternRole::None,
        leaf: true,
        reads: false,
    });
    let mut b = FuncBuilder::new(
        m,
        "unwind.drop_slot",
        vec![Param {
            ty: Ty::PTR,
            mode: Mode::Borrow,
        }],
        Ty::UNIT,
    );
    b.func_mut().linkage = Linkage::Internal;
    let p = b.params()[0];
    let on = b.call_rt(gate, &[]);
    let held = b.emit(Op::Take, &[p], Imm::Ty(ty), Some(ty)).expect("take");
    b.emit(Op::DropIf, &[on, held], Imm::None, None);
    let u = b.unit();
    b.ret(Some(u));
    let f = b.into_func();
    let id = m.add_func(f);
    cx.slot_droppers.insert(ty, id);
    id
}

/// Whether `callee` can take a value out of the slot it is given, or out of a part of it, leaving
/// a hole that dropping the whole slot would free twice. Only a close that leaves the slot's
/// value in place can be covered by a drop of that slot.
fn takes_from_slot(m: &Module, callee: FuncId, memo: &mut HashMap<FuncId, bool>) -> bool {
    if let Some(r) = memo.get(&callee) {
        return *r;
    }
    // A cycle is assumed to take nothing; the other paths decide.
    memo.insert(callee, false);
    let f = &m.funcs[callee.index()];
    let mut derived: BTreeSet<u32> = f
        .params
        .iter()
        .zip(f.param_values())
        .filter(|(p, _)| p.ty == Ty::PTR)
        .map(|(_, v)| v.0)
        .collect();
    let mut found = false;
    for inst in f.blocks.iter().flat_map(|b| &b.insts) {
        let from_slot = inst.args.iter().any(|a| derived.contains(&a.0));
        match inst.op {
            Op::Take if from_slot => found = true,
            Op::Call if from_slot => match inst.imm {
                Imm::Func(g) => {
                    let touches_slot = inst.args.iter().any(|a| derived.contains(&a.0));
                    found |= touches_slot && takes_from_slot(m, g, memo);
                }
                _ => found = true,
            },
            Op::CallInd | Op::CallMethod if from_slot => found = true,
            _ => {}
        }
        if let Some(r) = inst.res
            && inst.args.first().is_some_and(|a| derived.contains(&a.0))
            && f.ty(r) == Ty::PTR
        {
            derived.insert(r.0);
        }
    }
    memo.insert(callee, found);
    found
}

/// Covers a slot-held value while a shielded close works on it in place. A fault inside the
/// close never returns to its caller, and the entry the scope registered for the value is gone
/// by then, so a drop is registered around the close call.
fn cover_shielded_slots(m: &mut Module, cx: &mut Cx, f: &mut Func) -> bool {
    let slots: HashMap<u32, Ty> = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter_map(|i| match (i.op, i.imm, i.res) {
            (Op::Slot, Imm::Ty(ty), Some(r)) if m.needs_drop(ty) => Some((r.0, ty)),
            _ => None,
        })
        .collect();
    if slots.is_empty() {
        return false;
    }
    let ext = |m: &Module, inst: &Inst, name: &str| matches!((inst.op, inst.imm), (Op::CallRt, Imm::Ext(e)) if m.externs[e.index()].name == name);
    let mut memo = HashMap::new();
    let mut changed = false;
    for bi in 0..f.blocks.len() {
        let mut ii = 0;
        while ii < f.blocks[bi].insts.len() {
            if !ext(m, &f.blocks[bi].insts[ii], "msrt_shield_enter") {
                ii += 1;
                continue;
            }
            let Some(exit) = (ii + 1..f.blocks[bi].insts.len())
                .find(|&j| ext(m, &f.blocks[bi].insts[j], "msrt_shield_exit"))
            else {
                ii += 1;
                continue;
            };
            // The calls inside the window that close a slot in place.
            let mut calls: Vec<(usize, Value, Ty)> = Vec::new();
            for (k, inst) in f.blocks[bi]
                .insts
                .iter()
                .enumerate()
                .take(exit)
                .skip(ii + 1)
            {
                if inst.op != Op::Call {
                    continue;
                }
                if let Some(slot) = inst.args.first()
                    && let Some(ty) = slots.get(&slot.0)
                    && let Imm::Func(g) = inst.imm
                    && !takes_from_slot(m, g, &mut memo)
                {
                    calls.push((k, *slot, *ty));
                }
            }
            // A slot with an entry still registered here is covered by that entry.
            let registered = |slot: Value, upto: usize, f: &Func| {
                f.blocks
                    .iter()
                    .enumerate()
                    .flat_map(|(b, blk)| blk.insts.iter().enumerate().map(move |(k, i)| (b, k, i)))
                    .filter(|(_, _, i)| i.op == Op::CleanupPush && i.args.first() == Some(&slot))
                    .any(|(b, k, push)| {
                        !(b == bi
                            && k < upto
                            && f.blocks[bi].insts[k + 1..upto]
                                .iter()
                                .any(|i| i.op == Op::CallRt && i.args.first() == push.res.as_ref()))
                    })
            };
            let mut shift = 0;
            for (k, slot, ty) in calls {
                let k = k + shift;
                if registered(slot, k, f) {
                    continue;
                }
                let loc = f.blocks[bi].insts[k].loc;
                let dropper = slot_dropper(m, cx, ty);
                let handle = f.new_value(Ty::INT);
                let unit = f.new_value(Ty::UNIT);
                f.blocks[bi].insts.insert(
                    k + 1,
                    Inst {
                        op: Op::CallRt,
                        args: vec![handle],
                        imm: Imm::Ext(cx.discard),
                        res: Some(unit),
                        loc,
                    },
                );
                f.blocks[bi].insts.insert(
                    k,
                    Inst {
                        op: Op::CleanupPush,
                        args: vec![slot],
                        imm: Imm::Func(dropper),
                        res: Some(handle),
                        loc,
                    },
                );
                shift += 2;
                changed = true;
            }
            ii = exit + shift + 1;
        }
    }
    changed
}

/// Keeps a slot-held value covered after its scope close ran inline. Scope end discards the close
/// entry and then runs the close in place; when the close returns an error the program faults
/// with the value still in its slot, so a drop is registered from the close's return until the
/// result is known to be good. (While the close runs, the values it took out of the slot are
/// its own, and registering the slot too would drop them twice.)
fn cover_inline_closes(m: &mut Module, cx: &mut Cx, f: &mut Func) -> bool {
    let slot_types: HashMap<FuncId, Ty> = cx
        .with_closers
        .iter()
        .filter_map(|(close, with)| Some((*with, slot_close_value(m, *close)?)))
        .collect();
    if slot_types.is_empty() {
        return false;
    }
    let pushes: HashMap<u32, (Value, Ty)> = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter_map(|i| match (i.op, i.imm, i.res) {
            (Op::CleanupPush, Imm::Func(g), Some(h)) => {
                Some((h.0, (*i.args.first()?, *slot_types.get(&g)?)))
            }
            _ => None,
        })
        .collect();
    let named = |m: &Module, inst: &Inst, name: &str| matches!((inst.op, inst.imm), (Op::CallRt, Imm::Ext(e)) if m.externs[e.index()].name == name);
    let mut changed = false;
    for bi in 0..f.blocks.len() {
        let mut ii = 0;
        while ii < f.blocks[bi].insts.len() {
            let inst = &f.blocks[bi].insts[ii];
            let discards =
                matches!((inst.op, inst.imm), (Op::CallRt, Imm::Ext(e)) if e == cx.discard);
            let Some((slot, ty)) = discards
                .then(|| inst.args.first().and_then(|h| pushes.get(&h.0)))
                .flatten()
                .copied()
            else {
                ii += 1;
                continue;
            };
            let loc = inst.loc;
            let Some(exit) = (ii + 1..f.blocks[bi].insts.len())
                .find(|&j| named(m, &f.blocks[bi].insts[j], "msrt_shield_exit"))
            else {
                ii += 1;
                continue;
            };
            let dropper = slot_dropper(m, cx, ty);
            let handle = f.new_value(Ty::INT);
            let mut ends: Vec<(usize, usize)> = Vec::new();
            let mut targets: Vec<usize> = Vec::new();
            f.blocks[bi]
                .term
                .for_each_target(|t| targets.push(t.block.index()));
            let preds = f.predecessors();
            if targets.is_empty() || targets.iter().any(|t| preds[*t].len() != 1) {
                ii += 1;
                continue;
            }
            // The close's own result is checked next: a failed close faults with the value back
            // in its slot, so only the edges that go on leave it unregistered.
            for t in targets {
                if !matches!(f.blocks[t].term, Term::Fault(_) | Term::Unreachable) {
                    ends.push((t, 0));
                }
            }
            for (b, at) in ends {
                let unit = f.new_value(Ty::UNIT);
                f.blocks[b].insts.insert(
                    at,
                    Inst {
                        op: Op::CallRt,
                        args: vec![handle],
                        imm: Imm::Ext(cx.discard),
                        res: Some(unit),
                        loc,
                    },
                );
            }
            f.blocks[bi].insts.insert(
                exit + 1,
                Inst {
                    op: Op::CleanupPush,
                    args: vec![slot],
                    imm: Imm::Func(dropper),
                    res: Some(handle),
                    loc,
                },
            );
            changed = true;
            ii = exit + 2;
        }
    }
    changed
}

/// What one liveness walk learned: the owned values live on entry to each block, the windows
/// to register and the values to register before a terminating fault.
struct Walk {
    entry: Vec<Option<BTreeSet<u32>>>,
    plans: Vec<Vec<Window>>,
    at_fault: Vec<Vec<Value>>,
    /// Per plain block: the owners to hold at each instruction that can park or fault, and at
    /// the end of a block that terminates in a fault. Only the blocks `plan_flow` may carry a
    /// registration across use them.
    events: Vec<Vec<(usize, Vec<Value>)>>,
    plain: Vec<bool>,
}

/// Walks `f` in reverse post-order tracking which owned values are live, and plans a
/// registration around each instruction that can park or fault. `hoisted` holds, per block,
/// values a loop registration already covers.
fn analyze(
    m: &Module,
    cx: &Cx,
    f: &Func,
    owned_def: &[bool],
    closed_by_with: &BTreeSet<u32>,
    holes: &[u32],
    hoisted: &[BTreeSet<u32>],
) -> Walk {
    let plain = plain_blocks(f, cx, holes);
    let mut entry: Vec<Option<BTreeSet<u32>>> = vec![None; f.blocks.len()];
    // Per block: the instruction run `first..=last` to cover and the values to register for it.
    let mut plans: Vec<Vec<Window>> = vec![Vec::new(); f.blocks.len()];
    // Per block: values to register before a terminating fault, which never returns.
    let mut at_fault: Vec<Vec<Value>> = vec![Vec::new(); f.blocks.len()];
    let mut events: Vec<Vec<(usize, Vec<Value>)>> = vec![Vec::new(); f.blocks.len()];
    for b in f.rpo() {
        let bi = b.index();
        let blk = &f.blocks[bi];
        let mut live: BTreeSet<u32> = match (&entry[bi], bi) {
            (Some(s), _) => s.clone(),
            (None, 0) => BTreeSet::new(),
            (None, _) => continue,
        };
        for p in &blk.params {
            if owned_def[p.value.index()] {
                live.insert(p.value.0);
            }
        }
        let mut open = holes[bi];
        // The values of the window that the latest instruction may still extend.
        let mut reach: Option<Vec<Value>> = None;
        // Whether the instruction that opened the window pops cleanup entries itself: the
        // window's own registrations sit above the ones it removes, so the window stays as it
        // is.
        let mut opened_by_discard = false;
        for (k, inst) in blk.insts.iter().enumerate() {
            let discards =
                matches!((inst.op, inst.imm), (Op::CallRt, Imm::Ext(e)) if e == cx.discard);
            if discards {
                // The discard may pop entries the window pushed.
                reach = None;
            }
            let modes = crate::verify::arg_modes(m, inst);
            let consumed: Vec<u32> = inst
                .args
                .iter()
                .zip(&modes)
                .filter(|(a, mode)| **mode == Mode::Move && owned_def[a.index()])
                .map(|(a, _)| a.0)
                .collect();
            for c in &consumed {
                live.remove(c);
            }
            if inst.op == Op::Take
                && inst
                    .args
                    .first()
                    .is_some_and(|a| cx.cells.contains_key(&a.0))
            {
                live.remove(&inst.args[0].0);
            }
            if plain[bi]
                && (exits_at(m, cx, inst)
                    || (inst.op == Op::Drop
                        && inst
                            .args
                            .first()
                            .is_some_and(|a| !m.drops_plain_memory(f.ty(*a))))
                    || (inst.op == Op::CallRt
                        && k + 1 == blk.insts.len()
                        && matches!(blk.term, Term::Unreachable)))
            {
                let target = coverable(&live, closed_by_with, &hoisted[bi]);
                if events[bi].last().is_none_or(|(_, t)| *t != target) {
                    events[bi].push((k, target));
                }
            }
            if open > 0 || matches!(inst.op, Op::CleanupPush | Op::CleanupRun) {
                // A window across a hole would drop a half-emptied owner, and one across a
                // scope open or close would discard an entry that is not its own.
                reach = None;
            } else if (!live.is_empty() || reach.is_some())
                && (exits_at(m, cx, inst)
                    // Dropping a closure, interface value or handle can run a close that faults.
                    || (inst.op == Op::Drop
                        && inst.args.first().is_some_and(|a| !m.drops_plain_memory(f.ty(*a))))
                    || (inst.op == Op::CallRt
                        && k + 1 == blk.insts.len()
                        && matches!(blk.term, Term::Unreachable)))
            {
                let drops = coverable(&live, closed_by_with, &hoisted[bi]);
                match (&mut reach, plans[bi].last_mut()) {
                    (Some(set), Some(w)) if *set == drops => w.last = k,
                    // The live owners changed: the window follows them, so a value that died is
                    // discarded and one born since is registered, and the owners that stay are
                    // not registered again.
                    (Some(set), Some(w)) if !opened_by_discard => {
                        w.last = k;
                        w.steps.push((k, drops.clone()));
                        *set = drops;
                    }
                    _ => {
                        reach = None;
                        opened_by_discard = discards;
                        if !drops.is_empty() {
                            reach = Some(drops.clone());
                            plans[bi].push(Window {
                                first: k,
                                last: k,
                                values: drops,
                                steps: Vec::new(),
                            });
                        }
                    }
                }
            }
            open = hole_step(open, inst.op);
            if inst.op == Op::Put
                && inst
                    .args
                    .first()
                    .is_some_and(|a| cx.cells.contains_key(&a.0))
            {
                live.insert(inst.args[0].0);
            }
            if let Some(r) = inst.res.filter(|r| owned_def[r.index()]) {
                live.insert(r.0);
            }
        }
        if open == 0 && matches!(blk.term, Term::Fault(_)) {
            at_fault[bi] = coverable(&live, closed_by_with, &hoisted[bi]);
            if plain[bi] {
                events[bi].push((blk.insts.len(), at_fault[bi].clone()));
            }
        }
        let mut edges: Vec<Target> = Vec::new();
        blk.term.for_each_target(|t| edges.push(t.clone()));
        for t in edges {
            let dest = &f.blocks[t.block.index()];
            let mut after = live.clone();
            for (a, p) in t.args.iter().zip(&dest.params) {
                if p.mode == Mode::Move && owned_def[a.index()] {
                    after.remove(&a.0);
                }
            }
            if entry[t.block.index()].is_none() {
                entry[t.block.index()] = Some(after);
            }
        }
    }
    Walk {
        entry,
        plans,
        at_fault,
        events,
        plain,
    }
}

/// Registers values that stay owned and live across a whole loop once, before the loop, and
/// discards them where the loop is left, instead of around every faulting instruction inside.
///
/// A loop is rewritten when it has a single entry (its header), no moved-out projection, and
/// some owned value that is live into the header and consumed nowhere inside the loop (an exit
/// edge or a `ret` may consume it: the discard comes first). Entry edges are redirected through a
/// new block that registers the values; every exit edge gets a block that discards them, and a
/// `ret` inside the loop discards them just before it. Outer loops are rewritten first, so an
/// inner loop only adds the values the outer loop does not already cover.
///
/// Returns, per block, the values a loop registration covers, and whether anything changed.
fn hoist_loops(
    m: &mut Module,
    cx: &mut Cx,
    f: &mut Func,
    owned_def: &mut Vec<bool>,
    closed_by_with: &BTreeSet<u32>,
) -> (Vec<BTreeSet<u32>>, bool) {
    let n = f.blocks.len();
    let none = || vec![BTreeSet::new(); n];
    let holes = hole_states(f);
    let entry = analyze(m, cx, f, owned_def, closed_by_with, &holes, &none()).entry;
    let preds = f.predecessors();
    let rpo = f.rpo();
    let idom = crate::verify::dominators(f, &rpo, &preds);
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
    // (header, body) per natural loop whose only way in is its header.
    let mut loops: Vec<(usize, Vec<usize>)> = Vec::new();
    for h in 1..n {
        let latches: Vec<usize> = preds[h]
            .iter()
            .map(|b| b.index())
            .filter(|&p| dominates(h, p))
            .collect();
        if latches.is_empty() {
            continue;
        }
        let mut body = vec![h];
        let mut work = latches;
        while let Some(b) = work.pop() {
            if !body.contains(&b) {
                body.push(b);
                work.extend(preds[b].iter().map(|p| p.index()));
            }
        }
        let closed_off = body
            .iter()
            .all(|&b| b == h || preds[b].iter().all(|p| body.contains(&p.index())));
        let no_holes = body
            .iter()
            .all(|&b| holes[b] == 0 && f.blocks[b].insts.iter().all(|i| i.op != Op::MoveOut));
        if closed_off && no_holes {
            loops.push((h, body));
        }
    }
    loops.sort_by_key(|(_, body)| std::cmp::Reverse(body.len()));
    let mut covered: Vec<BTreeSet<u32>> = none();
    let mut chosen: Vec<(usize, Vec<Value>, Vec<usize>)> = Vec::new();
    for (h, body) in &loops {
        let Some(live) = &entry[*h] else { continue };
        let used = consumed_inside(m, f, owned_def, body);
        let (stable, chain) = stable_params(m, f, owned_def, *h, body);
        let held: Vec<Value> = live
            .iter()
            .filter(|v| {
                !closed_by_with.contains(v)
                    && !covered[*h].contains(v)
                    && !used.contains(v)
                    && !cx.cells.contains_key(v)
            })
            .map(|v| Value(*v))
            .collect();
        if held.is_empty() && stable.is_empty() {
            chosen.push((*h, Vec::new(), Vec::new()));
            continue;
        }
        for &b in body {
            covered[b].extend(held.iter().map(|v| v.0));
            covered[b].extend(chain.iter().copied());
        }
        chosen.push((*h, held, stable));
    }
    let mut bodies: Vec<Vec<usize>> = loops.iter().map(|(_, b)| b.clone()).collect();
    let mut changed = false;
    for (li, (h, held, stable)) in chosen.iter().enumerate() {
        if held.is_empty() && stable.is_empty() {
            continue;
        }
        changed = true;
        let h = *h;
        let body = bodies[li].clone();
        let loc = f.blocks[h].term_loc;
        let outside: Vec<usize> = f.predecessors()[h]
            .iter()
            .map(|b| b.index())
            .filter(|b| !body.contains(b))
            .collect();
        // The registering block takes over the header's entry edges.
        let pre = f.new_block().index();
        covered.push(BTreeSet::new());
        let params: Vec<BlockParam> = f.blocks[h]
            .params
            .clone()
            .into_iter()
            .map(|p| BlockParam {
                value: f.new_value(f.ty(p.value)),
                mode: p.mode,
            })
            .collect();
        let mut insts = Vec::new();
        let mut regs = held.clone();
        regs.extend(stable.iter().map(|k| params[*k].value));
        let first = push_all(m, cx, f, &mut insts, &regs, loc);
        let args = params.iter().map(|p| p.value).collect();
        f.blocks[pre].params = params;
        f.blocks[pre].insts = insts;
        f.blocks[pre].term = Term::Br(Target {
            block: Block(h as u32),
            args,
        });
        f.blocks[pre].term_loc = loc;
        for q in &outside {
            f.blocks[*q].term.for_each_target_mut(|t| {
                if t.block.index() == h {
                    t.block = Block(pre as u32);
                }
            });
        }
        for (lj, other) in bodies.iter_mut().enumerate() {
            if lj != li && other.contains(&h) && outside.iter().any(|q| other.contains(q)) {
                other.push(pre);
            }
        }
        let discard = |f: &mut Func, loc| Inst {
            op: Op::CallRt,
            args: vec![first],
            imm: Imm::Ext(cx.discard),
            res: Some(f.new_value(Ty::UNIT)),
            loc,
        };
        // Every way out discards the registrations first.
        for &b in &body {
            if matches!(f.blocks[b].term, Term::Ret(_)) {
                let inst = discard(f, f.blocks[b].term_loc);
                f.blocks[b].insts.push(inst);
            }
            let mut exits: Vec<(usize, Target)> = Vec::new();
            let mut slot = 0;
            f.blocks[b].term.for_each_target(|t| {
                if !body.contains(&t.block.index()) {
                    exits.push((slot, t.clone()));
                }
                slot += 1;
            });
            for (slot, t) in exits {
                let out = f.new_block().index();
                // The discard runs with the loop's registrations still in place.
                covered.push(covered[b].clone());
                let inst = discard(f, f.blocks[b].term_loc);
                f.blocks[out].insts.push(inst);
                f.blocks[out].term = Term::Br(t.clone());
                f.blocks[out].term_loc = f.blocks[b].term_loc;
                let mut at = 0;
                f.blocks[b].term.for_each_target_mut(|x| {
                    if at == slot {
                        x.block = Block(out as u32);
                        x.args = Vec::new();
                    }
                    at += 1;
                });
                for (lj, other) in bodies.iter_mut().enumerate() {
                    if lj != li && other.contains(&b) && other.contains(&t.block.index()) {
                        other.push(out);
                    }
                }
            }
        }
    }
    owned_def.resize(f.values.len(), false);
    debug_assert_eq!(covered.len(), f.blocks.len());
    (covered, changed)
}

/// Header parameters of the loop at `h` that only ever carry one list updated in place, and the
/// values of those chains (the parameter and each `list.set` result).
///
/// `list.set` stores into the list's own storage and returns the same pointer, length and
/// capacity, so one registration made before the loop names the live list for every value of the
/// chain. A parameter qualifies when each latch passes the result of a chain of `list.set`s that
/// starts at it, no chain value has another consumer, and the elements need no drop: a `set` drops
/// the old element before the store, and an unwind in between would drop it twice.
fn stable_params(
    m: &Module,
    f: &Func,
    owned_def: &[bool],
    h: usize,
    body: &[usize],
) -> (Vec<usize>, Vec<u32>) {
    let is_set = |op: Op| matches!(op, Op::ListSet | Op::ListSetNn | Op::ListSetU);
    let mut sets: BTreeMap<u32, u32> = BTreeMap::new(); // result -> list argument
    let mut moves: BTreeMap<u32, usize> = BTreeMap::new();
    for &b in body {
        for inst in &f.blocks[b].insts {
            if let (true, Some(r)) = (is_set(inst.op), inst.res) {
                sets.insert(r.0, inst.args[0].0);
            }
            let modes = crate::verify::arg_modes(m, inst);
            for (a, mode) in inst.args.iter().zip(&modes) {
                if *mode == Mode::Move {
                    *moves.entry(a.0).or_default() += 1;
                }
            }
        }
        f.blocks[b].term.for_each_target(|t| {
            if !body.contains(&t.block.index()) {
                return;
            }
            for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                if p.mode == Mode::Move {
                    *moves.entry(a.0).or_default() += 1;
                }
            }
        });
    }
    let mut stable = Vec::new();
    let mut chain_values = Vec::new();
    'params: for (k, p) in f.blocks[h].params.iter().enumerate() {
        let elem_plain = m.list_elem(f.ty(p.value)).is_some_and(|e| !m.needs_drop(e));
        if p.mode != Mode::Move || !owned_def[p.value.index()] || !elem_plain {
            continue;
        }
        let mut chain = vec![p.value.0];
        let mut latches = 0;
        for &b in body {
            let mut latch_args = Vec::new();
            f.blocks[b].term.for_each_target(|t| {
                if t.block.index() == h {
                    latch_args.push(t.args[k].0);
                }
            });
            for mut v in latch_args {
                latches += 1;
                while v != p.value.0 {
                    let Some(&from) = sets.get(&v) else {
                        continue 'params;
                    };
                    chain.push(v);
                    v = from;
                }
            }
        }
        let once = chain.iter().all(|v| moves.get(v) == Some(&1));
        let distinct = chain.iter().collect::<BTreeSet<_>>().len() == chain.len();
        if latches == 0 || !once || !distinct {
            continue;
        }
        stable.push(k);
        chain_values.extend(chain);
    }
    (stable, chain_values)
}

/// Owned values consumed by an instruction in `body`, or passed on an edge that stays inside it.
fn consumed_inside(m: &Module, f: &Func, owned_def: &[bool], body: &[usize]) -> BTreeSet<u32> {
    let mut used = BTreeSet::new();
    for &b in body {
        let blk = &f.blocks[b];
        for inst in &blk.insts {
            let modes = crate::verify::arg_modes(m, inst);
            for (a, mode) in inst.args.iter().zip(&modes) {
                if *mode == Mode::Move && owned_def[a.index()] {
                    used.insert(a.0);
                }
            }
        }
        blk.term.for_each_target(|t| {
            if !body.contains(&t.block.index()) {
                return;
            }
            for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                if p.mode == Mode::Move && owned_def[a.index()] {
                    used.insert(a.0);
                }
            }
        });
    }
    used
}

fn function(m: &mut Module, cx: &mut Cx, f: &mut Func) -> bool {
    if f.blocks.is_empty() {
        return false;
    }
    let rc = |v: Value| m.needs_drop(f.ty(v));
    let mut slot_params: BTreeSet<u32> = f.blocks[0].params.iter().map(|p| p.value.0).collect();
    // A slot pointer a closure captured by reference is the enclosing function's slot, as a
    // parameter is the caller's: a cancellation inside the closure must not drop what it took.
    for i in f.blocks.iter().flat_map(|b| &b.insts) {
        if let (Op::ClosureCap, Some(r)) = (i.op, i.res)
            && f.ty(r) == Ty::PTR
        {
            slot_params.insert(r.0);
        }
    }
    let covered_takes = covered_slot_takes(m, f);
    let mut owned_def = vec![false; f.values.len()];
    let mut from_slot: BTreeSet<u32> = BTreeSet::new();
    for b in &f.blocks {
        for p in &b.params {
            owned_def[p.value.index()] = rc(p.value) && p.mode == Mode::Move;
        }
        for i in &b.insts {
            // A value taken out of a slot the caller passed in stays the caller's: the slot still
            // holds it while the call runs, and the caller (or its owner) drops it. Dropping it
            // here too would drop it twice.
            let from_caller_slot = i.op == Op::Take
                && (i.args.first().is_some_and(|a| slot_params.contains(&a.0))
                    || i.res.is_some_and(|r| covered_takes.contains(&r.0)));
            if let (Some(r), Some(Mode::Move)) = (i.res, m.result_mode(f, i)) {
                owned_def[r.index()] = !from_caller_slot;
                if from_caller_slot {
                    from_slot.insert(r.0);
                }
            }
        }
    }
    // A block parameter that receives such a value stays the caller's too, and so does a value
    // taken back out of a local slot that only parks it for a borrower (`caller_slots`).
    let mut caller_slots: BTreeSet<u32> = BTreeSet::new();
    // Values taken from a slot the caller passed in, directly or back out of a `caller_slots` slot.
    let mut caller_values: BTreeSet<u32> = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter(|i| i.op == Op::Take && i.args.first().is_some_and(|a| slot_params.contains(&a.0)))
        .filter_map(|i| i.res.map(|r| r.0))
        .collect();
    let mut moved = true;
    while moved {
        moved = false;
        for b in &f.blocks {
            b.term.for_each_target(|t| {
                for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                    if from_slot.contains(&a.0) && from_slot.insert(p.value.0) {
                        owned_def[p.value.index()] = false;
                        moved = true;
                    }
                }
            });
            for i in &b.insts {
                match (i.op, i.res) {
                    (Op::Put, _)
                        if caller_values.contains(&i.args[1].0)
                            && !slot_params.contains(&i.args[0].0) =>
                    {
                        moved |= caller_slots.insert(i.args[0].0);
                    }
                    (Op::Take, Some(r))
                        if caller_slots.contains(&i.args[0].0)
                            && caller_values.insert(r.0)
                            && from_slot.insert(r.0) =>
                    {
                        owned_def[r.index()] = false;
                        moved = true;
                    }
                    // Refilling a field moved out of a caller's value yields that same value
                    // again (`self.items.pop()` before a park), so it stays the caller's.
                    (Op::TypeFill | Op::ListFill, Some(r))
                        if from_slot.contains(&i.args[0].0)
                            && caller_values.insert(r.0)
                            && from_slot.insert(r.0) =>
                    {
                        owned_def[r.index()] = false;
                        moved = true;
                    }
                    _ => {}
                }
            }
        }
    }
    cx.cells = find_cells(m, cx, f);
    cx.cells.retain(|slot, _| !caller_slots.contains(slot));
    // Quick exit: nothing can be live across a call without an owned definition.
    if !owned_def.iter().any(|o| *o) && cx.cells.is_empty() {
        return false;
    }
    cx.raw_values = raw_slots(m, f);
    let wrapped = wrap_with_closers(m, cx, f);
    let covered_shields = cover_shielded_slots(m, cx, f);
    let covered_closes = cover_inline_closes(m, cx, f);
    owned_def.resize(f.values.len(), false);
    // Values an existing cleanup entry (a scope close) uses: it must see them undropped.
    let closed_by_with: BTreeSet<u32> = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter(|i| i.op == Op::CleanupPush)
        .filter_map(|i| i.args.first().map(|v| v.0))
        .collect();
    let (hoisted, hoists) = hoist_loops(m, cx, f, &mut owned_def, &closed_by_with);
    let holes = hole_states(f);
    let Walk {
        plans,
        mut at_fault,
        events,
        plain,
        ..
    } = analyze(m, cx, f, &owned_def, &closed_by_with, &holes, &hoisted);
    if plans.iter().all(|p| p.is_empty()) && at_fault.iter().all(|v| v.is_empty()) {
        return wrapped || covered_shields || covered_closes || hoists;
    }
    let flow = plan_flow(f, &events, &plain);
    // The handle of each registration a flow block made, by the block and push that made it.
    let mut handles: HashMap<(u32, u32), Value> = HashMap::new();
    for b in f.rpo() {
        let bi = b.index();
        if flow.carries(bi) {
            rewrite_flow_block(m, cx, f, bi, &events[bi], &flow, &mut handles);
            continue;
        }
        let plan = &plans[bi];
        if plan.is_empty() && at_fault[bi].is_empty() {
            continue;
        }
        let old = std::mem::take(&mut f.blocks[bi].insts);
        let mut out: Vec<Inst> = Vec::with_capacity(old.len() + plan.len() * 3);
        let mut next = plan.iter().peekable();
        // The window's open registrations, oldest first, each with its handle.
        let mut stack: Vec<(Value, Value)> = Vec::new();
        let mut open_window: Option<usize> = None;
        let mut steps: std::slice::Iter<'_, (usize, Vec<Value>)> = [].iter();
        let end_loc = old.last().map(|i| i.loc);
        for (k, inst) in old.into_iter().enumerate() {
            let loc = inst.loc;
            // The recursion check stays first in its block: a registration before it would
            // repeat when the check re-invokes the function on a new stack segment.
            let mut inst = Some(inst);
            if inst.as_ref().is_some_and(|i| i.op == Op::DepthEnter) {
                out.extend(inst.take());
            }
            if let Some(w) = next.next_if(|w| w.first == k) {
                let handles = push_each(m, cx, f, &mut out, &w.values, loc);
                stack = w.values.iter().copied().zip(handles).collect();
                open_window = Some(w.last);
                steps = w.steps.iter();
            }
            if let Some((_, target)) = steps.as_slice().first().filter(|(at, _)| *at == k) {
                sync_stack(m, cx, f, &mut out, &mut stack, target, loc);
                steps.next();
            }
            out.extend(inst);
            if open_window == Some(k) {
                // The first entry's handle discards them all.
                if let Some((_, first)) = stack.first() {
                    out.push(discard_inst(f, cx, *first, loc));
                }
                stack.clear();
                open_window = None;
            }
        }
        let values = std::mem::take(&mut at_fault[bi]);
        if !values.is_empty() {
            // No discard: the fault never returns, and its cleanups run LIFO.
            let loc = end_loc.unwrap_or_default();
            push_all(m, cx, f, &mut out, &values, loc);
        }
        f.blocks[bi].insts = out;
    }
    true
}

/// Rewrites a block that carries registrations across its edges: it starts with the ones its
/// predecessors left open, brings each owner up to date before an instruction that can park or
/// fault, and discards what is held beyond what its successors take over.
fn rewrite_flow_block(
    m: &mut Module,
    cx: &mut Cx,
    f: &mut Func,
    bi: usize,
    events: &[(usize, Vec<Value>)],
    flow: &Flow,
    handles: &mut HashMap<(u32, u32), Value>,
) {
    let mut stack: Vec<(Value, Value)> = flow.entry[bi]
        .iter()
        .map(|&(v, blk, seq)| (Value(v), handles[&(blk, seq)]))
        .collect();
    let old = std::mem::take(&mut f.blocks[bi].insts);
    let end_loc = old.last().map(|i| i.loc).unwrap_or_default();
    let len = old.len();
    let mut out: Vec<Inst> = Vec::with_capacity(old.len());
    let mut next = events.iter().peekable();
    let mut seq = 0;
    // Each registration is named by this block and its push, which the blocks after it use to
    // find the handle.
    let mut record = |seq: &mut u32, pushed: Vec<Value>| {
        for h in pushed {
            handles.insert((bi as u32, *seq), h);
            *seq += 1;
        }
    };
    for (k, inst) in old.into_iter().enumerate() {
        let loc = inst.loc;
        let mut inst = Some(inst);
        // The recursion check stays first in its block, as in `function`.
        if inst.as_ref().is_some_and(|i| i.op == Op::DepthEnter) {
            out.extend(inst.take());
        }
        if let Some((_, target)) = next.next_if(|(at, _)| *at == k) {
            let pushed = sync_stack(m, cx, f, &mut out, &mut stack, target, loc);
            record(&mut seq, pushed);
        }
        out.extend(inst);
    }
    if let Some((_, target)) = next.next_if(|(at, _)| *at == len) {
        let pushed = sync_stack(m, cx, f, &mut out, &mut stack, target, end_loc);
        record(&mut seq, pushed);
    }
    // A fault never returns, and its cleanups run newest first: nothing to discard.
    if !matches!(f.blocks[bi].term, Term::Fault(_)) && stack.len() > flow.trim[bi] {
        out.push(discard_inst(f, cx, stack[flow.trim[bi]].1, end_loc));
    }
    f.blocks[bi].insts = out;
}

/// Brings `stack` to the owners in `target`: a discard pops the first entry whose owner died and
/// every newer one, and the owners above it that live, and the ones not yet held, are registered.
/// Returns the handles of the registrations it made, in order.
fn sync_stack(
    m: &mut Module,
    cx: &mut Cx,
    f: &mut Func,
    out: &mut Vec<Inst>,
    stack: &mut Vec<(Value, Value)>,
    target: &[Value],
    loc: crate::ir::Loc,
) -> Vec<Value> {
    let (cut, added) = reconcile_plan(stack, |e| e.0.0, target);
    if let Some(c) = cut {
        out.push(discard_inst(f, cx, stack[c].1, loc));
        stack.truncate(c);
    }
    let pushed = push_each(m, cx, f, out, &added, loc);
    stack.extend(added.into_iter().zip(pushed.iter().copied()));
    pushed
}

/// The results of `take`s from a local slot whose scope close is registered and not yet
/// discarded, when the value is only borrowed until it is put back. The close drops what the
/// slot holds, and the slot still holds the same value while the call runs; registering a
/// drop for the taken value as well would run first and free it before that close uses it.
/// The coverage ends at the discard, where the value is owned again.
fn covered_slot_takes(m: &Module, f: &Func) -> BTreeSet<u32> {
    let mut out = BTreeSet::new();
    let slot_push = |inst: &Inst| match (inst.op, inst.imm) {
        (Op::CleanupPush, Imm::Func(g)) if slot_close_value(m, g).is_some() => {
            inst.args.first().map(|a| a.0)
        }
        _ => None,
    };
    if !f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .any(|i| slot_push(i).is_some())
    {
        return out;
    }
    let mut handle: HashMap<u32, u32> = HashMap::new();
    for inst in f.blocks.iter().flat_map(|b| &b.insts) {
        if let (Some(slot), Some(h)) = (slot_push(inst), inst.res) {
            handle.insert(h.0, slot);
        }
    }
    // Slots covered on entry to each block: covered on every path that reaches it.
    let step = |covered: &mut BTreeSet<u32>, inst: &Inst| match (inst.op, inst.imm) {
        (Op::CleanupRun, _) => covered.clear(),
        (Op::CallRt, Imm::Ext(e)) if inst.args.len() == 1 => {
            if m.externs[e.index()].role == ExternRole::CleanupDiscard
                && let Some(slot) = handle.get(&inst.args[0].0)
            {
                covered.remove(slot);
            }
        }
        _ => {
            if let Some(slot) = slot_push(inst) {
                covered.insert(slot);
            }
        }
    };
    let mut entry: Vec<Option<BTreeSet<u32>>> = vec![None; f.blocks.len()];
    entry[0] = Some(BTreeSet::new());
    let order = f.rpo();
    let mut changed = true;
    while changed {
        changed = false;
        for b in &order {
            let Some(mut covered) = entry[b.index()].clone() else {
                continue;
            };
            for inst in &f.blocks[b.index()].insts {
                step(&mut covered, inst);
            }
            f.blocks[b.index()].term.for_each_target(|t| {
                let slot = &mut entry[t.block.index()];
                let next = match &*slot {
                    None => covered.clone(),
                    Some(old) => old.intersection(&covered).copied().collect(),
                };
                if slot.as_ref() != Some(&next) {
                    changed = true;
                    *slot = Some(next);
                }
            });
        }
    }
    for b in &order {
        let Some(mut covered) = entry[b.index()].clone() else {
            continue;
        };
        for inst in &f.blocks[b.index()].insts {
            if inst.op == Op::Take
                && let (Some(slot), Some(r)) = (inst.args.first(), inst.res)
                && covered.contains(&slot.0)
                && only_borrowed_until_put(m, f, r, *slot)
            {
                out.insert(r.0);
            }
            step(&mut covered, inst);
        }
    }
    out
}

/// Whether every use of `taken` borrows it or puts it back into `slot`.
fn only_borrowed_until_put(m: &Module, f: &Func, taken: Value, slot: Value) -> bool {
    for blk in &f.blocks {
        for inst in &blk.insts {
            let modes = crate::verify::arg_modes(m, inst);
            for (i, a) in inst.args.iter().enumerate() {
                if *a != taken {
                    continue;
                }
                let putback = inst.op == Op::Put && i == 1 && inst.args[0] == slot;
                let borrowed = modes.get(i) == Some(&Mode::Borrow)
                    && !matches!(
                        inst.op,
                        Op::MoveOut
                            | Op::Store
                            | Op::Put
                            | Op::CleanupPush
                            | Op::TypeFill
                            | Op::ListFill
                            | Op::CallInd
                    );
                if !putback && !borrowed {
                    return false;
                }
            }
        }
        let mut leaves = matches!(blk.term, Term::Ret(Some(v)) if v == taken);
        blk.term
            .for_each_target(|t| leaves |= t.args.contains(&taken));
        if leaves {
            return false;
        }
    }
    true
}

/// A registered owner of a block's cleanup stack: the value, and the block and push that
/// registered it. Two stacks that agree on all three hold the same registrations, so a block
/// that follows both may keep using the handles.
type Entry = (u32, u32, u32);

/// Brings `stack` to the owners in `target` (sorted): a discard pops the first entry whose
/// owner died and every newer one, and the owners above it that live are registered again.
/// Returns the position of the first entry to pop and the owners to register.
fn reconcile_plan<T>(
    stack: &[T],
    owner: impl Fn(&T) -> u32,
    target: &[Value],
) -> (Option<usize>, Vec<Value>) {
    let place = |v: u32| target.binary_search_by_key(&v, |t| t.0).ok();
    let cut = stack.iter().position(|e| place(owner(e)).is_none());
    let kept = &stack[..cut.unwrap_or(stack.len())];
    // The target owners no kept entry holds; both lists are small slices of one sorted target, so
    // marking by position needs no set.
    let mut held = vec![false; target.len()];
    for e in kept {
        if let Some(i) = place(owner(e)) {
            held[i] = true;
        }
    }
    let added = target
        .iter()
        .zip(&held)
        .filter(|(_, held)| !**held)
        .map(|(v, _)| *v)
        .collect();
    (cut, added)
}

/// Where a block's registrations come from and go to.
struct Flow {
    /// The registrations a block starts with: the ones all its predecessors leave open.
    entry: Vec<Vec<Entry>>,
    /// How many registrations a block leaves open for its successors; it discards the rest.
    trim: Vec<usize>,
}

impl Flow {
    /// Whether the block takes registrations over or leaves some open, so it is rewritten
    /// against the whole function's stack instead of by itself.
    fn carries(&self, bi: usize) -> bool {
        !self.entry[bi].is_empty() || (self.trim[bi] > 0 && self.trim[bi] != usize::MAX)
    }
}

/// Decides which registrations cross block edges, so a branchy function registers an owner once
/// instead of once per block.
///
/// A plain block (see `plain_blocks`) starts with the registrations all its predecessors leave
/// open, the longest prefix they share, provided every predecessor is plain and precedes it in
/// reverse post-order (a loop header starts empty). The registrations a block leaves open are the
/// prefix of its own end state that every successor starts with; it discards the rest, one
/// discard covering all of them, so a branch that registered a value of its own does not hold up
/// the join. A block that cannot continue (return, or a successor that is not plain) leaves
/// nothing open. Each registration is named by the block and push that made it, so equal names
/// mean the same handle, and that push dominates every block that holds it.
fn plan_flow(f: &Func, events: &[Vec<(usize, Vec<Value>)>], plain: &[bool]) -> Flow {
    let n = f.blocks.len();
    let rpo = f.rpo();
    let mut pos = vec![usize::MAX; n];
    for (i, b) in rpo.iter().enumerate() {
        pos[b.index()] = i;
    }
    let mut preds: Vec<Vec<usize>> = vec![Vec::new(); n];
    let mut succs: Vec<Vec<usize>> = vec![Vec::new(); n];
    for b in &rpo {
        f.blocks[b.index()].term.for_each_target(|t| {
            let ti = t.block.index();
            if !succs[b.index()].contains(&ti) {
                succs[b.index()].push(ti);
            }
            if !preds[ti].contains(&b.index()) {
                preds[ti].push(b.index());
            }
        });
    }
    let can: Vec<bool> = (0..n)
        .map(|b| {
            b != 0
                && plain[b]
                && !preds[b].is_empty()
                && preds[b].iter().all(|&p| plain[p] && pos[p] < pos[b])
        })
        .collect();
    let mut trim: Vec<usize> = plain
        .iter()
        .map(|p| if *p { usize::MAX } else { 0 })
        .collect();
    let none = || Flow {
        entry: vec![Vec::new(); n],
        trim: vec![0; n],
    };
    // Each pass lowers some trim, so this ends; the bound only guards a mistake.
    for _ in 0..n * 4 + 8 {
        let mut entry: Vec<Vec<Entry>> = vec![Vec::new(); n];
        let mut full: Vec<Vec<Entry>> = vec![Vec::new(); n];
        let mut left: Vec<Vec<Entry>> = vec![Vec::new(); n];
        for b in &rpo {
            let bi = b.index();
            if !plain[bi] {
                continue;
            }
            let mut stack: Vec<Entry> = Vec::new();
            if can[bi] {
                stack = left[preds[bi][0]].clone();
                for &p in &preds[bi][1..] {
                    let keep = stack
                        .iter()
                        .zip(&left[p])
                        .take_while(|(a, b)| a == b)
                        .count();
                    stack.truncate(keep);
                }
            }
            entry[bi] = stack.clone();
            let mut seq = 0;
            for (_, target) in &events[bi] {
                let (cut, added) = reconcile_plan(&stack, |e| e.0, target);
                if let Some(c) = cut {
                    stack.truncate(c);
                }
                for v in added {
                    stack.push((v.0, bi as u32, seq));
                    seq += 1;
                }
            }
            left[bi] = stack.clone();
            left[bi].truncate(trim[bi]);
            full[bi] = stack;
        }
        let mut changed = false;
        for bi in 0..n {
            if !plain[bi] {
                continue;
            }
            let want = match f.blocks[bi].term {
                Term::Fault(_) => usize::MAX,
                Term::Ret(_) | Term::Unreachable => 0,
                _ => succs[bi]
                    .iter()
                    .map(|&s| {
                        full[bi]
                            .iter()
                            .zip(&entry[s])
                            .take_while(|(a, b)| a == b)
                            .count()
                    })
                    .min()
                    .unwrap_or(0),
            };
            if want < trim[bi] {
                trim[bi] = want;
                changed = true;
            }
        }
        if !changed {
            return Flow { entry, trim };
        }
    }
    debug_assert!(false, "the cleanup flow did not settle");
    none()
}

/// The blocks the cleanup stack may stay open across: no scope open or close, no discard and no
/// moved-out projection, which a registration across would break.
fn plain_blocks(f: &Func, cx: &Cx, holes: &[u32]) -> Vec<bool> {
    (0..f.blocks.len())
        .map(|bi| {
            holes[bi] == 0
                && !f.blocks[bi].insts.iter().any(|i| match (i.op, i.imm) {
                    (Op::CleanupPush | Op::CleanupRun | Op::MoveOut, _) => true,
                    (Op::CallRt, Imm::Ext(e)) => e == cx.discard,
                    _ => false,
                })
        })
        .collect()
}

/// A run of instructions `first..=last` of one block covered by one registration of `values`.
#[derive(Clone)]
struct Window {
    first: usize,
    last: usize,
    values: Vec<Value>,
    /// The owners the window covers from an instruction on, where they differ from the ones
    /// before it, by the instruction they precede.
    steps: Vec<(usize, Vec<Value>)>,
}

/// The live values a registration may cover: a scope close sees its own values undropped, and a
/// loop registration already covers its hoisted values.
fn coverable(
    live: &BTreeSet<u32>,
    closed_by_with: &BTreeSet<u32>,
    hoisted: &BTreeSet<u32>,
) -> Vec<Value> {
    live.iter()
        .filter(|v| !closed_by_with.contains(v) && !hoisted.contains(v))
        .map(|v| Value(*v))
        .collect()
}

/// The instruction that discards the registration behind `handle` and every newer one.
fn discard_inst(f: &mut Func, cx: &Cx, handle: Value, loc: crate::ir::Loc) -> Inst {
    Inst {
        op: Op::CallRt,
        args: vec![handle],
        imm: Imm::Ext(cx.discard),
        res: Some(f.new_value(Ty::UNIT)),
        loc,
    }
}

/// Appends one cleanup registration per value; returns the first handle, which discards all.
fn push_all(
    m: &mut Module,
    cx: &mut Cx,
    f: &mut Func,
    out: &mut Vec<Inst>,
    values: &[Value],
    loc: crate::ir::Loc,
) -> Value {
    push_each(m, cx, f, out, values, loc)[0]
}

/// Appends one cleanup registration per value; returns their handles in order.
fn push_each(
    m: &mut Module,
    cx: &mut Cx,
    f: &mut Func,
    out: &mut Vec<Inst>,
    values: &[Value],
    loc: crate::ir::Loc,
) -> Vec<Value> {
    let mut handles = Vec::with_capacity(values.len());
    for v in values {
        let mut held = *v;
        let mut ty = f.ty(*v);
        if let Some(cell) = cx.cells.get(&v.0).copied() {
            // A cell registers a view of what its slot holds now.
            ty = cell;
            held = f.new_value(cell);
            out.push(Inst {
                op: Op::Load,
                args: vec![*v],
                imm: Imm::Ty(cell),
                res: Some(held),
                loc,
            });
        }
        let c = if cx.raw_values.contains(&v.0) {
            raw_closer(m, cx, ty)
        } else {
            closer(m, cx, ty)
        };
        let h = f.new_value(Ty::INT);
        out.push(Inst {
            op: Op::CleanupPush,
            args: vec![held],
            imm: Imm::Func(c),
            res: Some(h),
            loc,
        });
        handles.push(h);
    }
    handles
}

/// Moves-out of a projection that are not yet filled back, at the start of each block. The
/// count only matters as zero or not, and a merge keeps the larger one.
fn hole_states(f: &Func) -> Vec<u32> {
    let mut at = vec![0u32; f.blocks.len()];
    let mut changed = true;
    while changed {
        changed = false;
        for b in f.rpo() {
            let mut open = at[b.index()];
            for inst in &f.blocks[b.index()].insts {
                open = hole_step(open, inst.op);
            }
            let mut targets = Vec::new();
            f.blocks[b.index()]
                .term
                .for_each_target(|t| targets.push(t.block));
            for t in targets {
                if at[t.index()] < open {
                    at[t.index()] = open;
                    changed = true;
                }
            }
        }
    }
    at
}

fn hole_step(open: u32, op: Op) -> u32 {
    match op {
        Op::MoveOut => (open + 1).min(8),
        Op::TypeFill | Op::ListFill => open.saturating_sub(1),
        _ => open,
    }
}

/// The slots of `f` that hold an owned value across calls, each with the type it holds. A slot
/// qualifies when every use is a `put` into it, a `take` out of it, a `load`, or a call whose
/// callee only borrows what it takes from the slot, and each such use sits between a `put` and
/// its `take` in one block.
fn find_cells(m: &Module, cx: &Cx, f: &Func) -> BTreeMap<u32, Ty> {
    let mut slots: BTreeMap<u32, Ty> = BTreeMap::new();
    for inst in f.blocks.iter().flat_map(|b| &b.insts) {
        if let (Op::Slot, Imm::Ty(ty), Some(r)) = (inst.op, inst.imm, inst.res)
            && m.needs_drop(ty)
        {
            slots.insert(r.0, ty);
        }
    }
    if slots.is_empty() {
        return slots;
    }
    let mut bad: BTreeSet<u32> = BTreeSet::new();
    for blk in &f.blocks {
        let mut full: BTreeSet<u32> = BTreeSet::new();
        for inst in &blk.insts {
            for (k, a) in inst.args.iter().enumerate() {
                let Some(&ty) = slots.get(&a.0) else { continue };
                let ok = match (inst.op, inst.imm) {
                    (Op::Put, _) if k == 0 => full.insert(a.0) && f.ty(inst.args[1]) == ty,
                    (Op::Take, _) => full.remove(&a.0),
                    (Op::Load, _) => full.contains(&a.0),
                    (Op::Call, Imm::Func(g)) => {
                        full.contains(&a.0)
                            && cx.safe.get(g.index()).and_then(|p| p.get(k)).copied() == Some(true)
                    }
                    // The callee is some closure of this arity; the slot stays covered when every
                    // one that could receive it at this position only borrows it.
                    (Op::CallInd, _) => {
                        k > 0 && full.contains(&a.0) && closures_borrow(cx, inst.args.len(), k)
                    }
                    _ => false,
                };
                if !ok {
                    bad.insert(a.0);
                }
            }
        }
        // A `put` left unmatched at the end of the block spans blocks, which this does not follow.
        bad.extend(full);
        blk.term.for_each_target(|t| {
            bad.extend(t.args.iter().map(|a| a.0).filter(|a| slots.contains_key(a)));
        });
        if let Term::Ret(Some(v)) = blk.term {
            bad.insert(v.0);
        }
    }
    slots.retain(|s, _| !bad.contains(s));
    slots
}

/// The functions that `closure.new` instructions make callable.
fn closure_targets(m: &Module) -> Vec<FuncId> {
    let mut out = BTreeSet::new();
    for inst in m
        .funcs
        .iter()
        .flat_map(|f| f.blocks.iter().flat_map(|b| &b.insts))
    {
        if let (Op::ClosureNew, Imm::Func(g)) = (inst.op, inst.imm) {
            out.insert(g.0);
        }
    }
    out.into_iter().map(FuncId).collect()
}

/// Whether every closure that takes `arity` parameters (its environment first) and a pointer at
/// position `k` only borrows what that pointer's slot holds. False when there is no such closure.
fn closures_borrow(cx: &Cx, arity: usize, k: usize) -> bool {
    let mut any = false;
    for g in &cx.closure_targets {
        let safe = &cx.safe[g.index()];
        if safe.len() == arity && safe[k] {
            any = true;
        }
    }
    // A candidate whose parameter at `k` is a pointer that it may consume makes the call unsafe.
    any && cx.closure_targets.iter().all(|g| {
        let safe = &cx.safe[g.index()];
        safe.len() != arity || safe[k] || !cx.pointer_params[g.index()][k]
    })
}

/// Per function and parameter, whether the parameter is a pointer to a slot whose contents the
/// function only borrows: it `take`s them, uses them as borrows, and `put`s the same value back.
fn slot_safe_params(m: &Module) -> Vec<Vec<bool>> {
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
            if (from_held || view)
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
            let modes = crate::verify::arg_modes(m, inst);
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
                    let borrowed = modes.get(i) == Some(&Mode::Borrow)
                        && method
                        && !matches!(
                            inst.op,
                            Op::MoveOut
                                | Op::Store
                                | Op::Put
                                | Op::CleanupPush
                                | Op::TypeFill
                                | Op::ListFill
                                | Op::CallInd
                        );
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
