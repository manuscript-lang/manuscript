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
//! the slot's contents, which stays valid because no such callee consumes or moves a part out of
//! them. Any other use of the slot leaves its contents to leak.
//!
//! Only programs that start tasks or workers are rewritten. A value moved out of a field and
//! not yet filled back leaves a hole in its owner, so calls inside that window are skipped, as
//! are values held in stack slots that a callee may consume or rearrange; both only leak.

use crate::builder::FuncBuilder;
use crate::ir::*;
use crate::types::{Ty, TyKind};
use std::collections::{BTreeMap, BTreeSet, HashMap, VecDeque};
use std::rc::Rc;

/// Runtime symbols whose presence means the program starts tasks that can be cancelled.
const SPAWNERS: &[&str] = &["msrt_scope_spawn", "msrt_worker_start"];

/// Runtime functions that never reach a cancellation point.
const LEAF_PREFIXES: &[&str] = &[
    "msrt_string_",
    "msrt_str_",
    "msrt_strbuf_",
    "msrt_strbuilder_",
    "msrt_list_",
    "msrt_map_",
    "msrt_set_",
    "msrt_bytes_",
    "msrt_bits_",
    "msrt_float",
    "msrt_int_",
    "msrt_bool_",
    "msrt_desc_",
    "msrt_slot_",
    "msrt_eq_",
    "msrt_hash_",
    "msrt_split_",
    "msrt_ascii_",
    "msrt_fault_",
    "msrt_index_",
    "msrt_drop_",
    "msrt_alloc",
    "msrt_cleanup_",
    "msrt_shield_",
    "msrt_unwind_",
    "msstd_json_",
    "msstd_path_",
    "msstd_url_",
    "msstd_html_",
    "msstd_encoding_",
    "msstd_regex_",
    "msrt_numbers_",
    "msstd_math_",
    "msstd_bigint_",
    "msstd_decimal_",
];

/// Rewrites `m` so cancellation releases owned locals; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    if !starts_tasks(m) {
        return false;
    }
    let parks = parking_funcs(m);
    let faults = faulting_funcs(m, &parks);
    let safe = slot_borrowers(m, false, &[]);
    let local = slot_borrowers(m, true, &safe);
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
    });
    let mut cx = Cx {
        parks,
        faults,
        safe,
        local,
        cells: BTreeMap::new(),
        scope_owners: BTreeMap::new(),
        discard,
        closers: HashMap::new(),
        with_closers: HashMap::new(),
    };
    let mut changed = false;
    for fi in 0..count {
        let mut f = std::mem::replace(&mut m.funcs[fi], Func::new("", Vec::new(), Ty::UNIT));
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
    /// Slot parameters that never escape and restore any changed resources before returning.
    /// They may replace owned fields, so snapshots must not span these mutating calls.
    local: Vec<Vec<bool>>,
    /// The slots of the function being rewritten that hold an owned value between a `put` and a
    /// `take`, with the type held.
    cells: BTreeMap<u32, Ty>,
    /// Original scope cleanup handles and the local slots their close/drop callbacks own.
    scope_owners: BTreeMap<u32, u32>,
    discard: ExtId,
    /// The cleanup that drops a value of a type while a cancellation unwinds.
    closers: HashMap<Ty, FuncId>,
    /// A scope close followed by the drop of the value it closed, per close function.
    with_closers: HashMap<FuncId, FuncId>,
}

fn starts_tasks(m: &Module) -> bool {
    m.externs
        .iter()
        .any(|e| SPAWNERS.contains(&e.name.as_str()) || e.name.contains("_serve"))
}

fn leaf_extern(m: &Module, e: ExtId) -> bool {
    let d = &m.externs[e.index()];
    d.noreturn || LEAF_PREFIXES.iter().any(|p| d.name.starts_with(p))
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
    });
    let mut b = FuncBuilder::new(
        m,
        "unwind.drop",
        vec![Param {
            ty,
            mode: Mode::Own,
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
    // Closing that consumes the value, or yields one that needs a drop, leaves nothing to add.
    if param.mode == Mode::Own || callee.ret != Ty::UNIT {
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
    });
    let mut b = FuncBuilder::new(
        m,
        "unwind.close_drop",
        vec![Param {
            ty,
            mode: Mode::Own,
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

/// The type of the value a scope close reads from the slot it is registered with, when `close` is
/// the thunk of a `var` binding that lives in memory: it takes the slot's address and loads first.
fn slot_close_value(m: &Module, close: FuncId) -> Option<Ty> {
    let f = m.funcs.get(close.index())?;
    let [param] = f.params.as_slice() else {
        return None;
    };
    if param.ty != Ty::PTR {
        return None;
    }
    let first = f.blocks.first()?.insts.first()?;
    match (first.op, first.imm) {
        (Op::Load, Imm::Ty(ty))
            if first.args.first().copied() == f.param_values().first().copied()
                && m.needs_drop(ty) =>
        {
            Some(ty)
        }
        _ => None,
    }
}

/// [`with_closer`] for a slot-held value: runs the thunk, then drops what the slot still holds.
/// The thunk closes a copy or borrows, so the original is left for this drop.
fn slot_with_closer(m: &mut Module, cx: &mut Cx, close: FuncId, ty: Ty) -> Option<FuncId> {
    let gate = m.add_extern(ExternDef {
        name: "msrt_unwind_drops".into(),
        params: Vec::new(),
        ret: Ty::BOOL,
        noreturn: false,
        pure_: false,
        fresh: false,
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
    b.call(close, &[p]);
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

/// What one liveness walk learned: the owned values live on entry to each block, the windows
/// to register and the values to register before a terminating fault.
struct Walk {
    scope_snapshots: BTreeSet<u32>,
    entry: Vec<Option<BTreeSet<u32>>>,
    plans: Vec<Vec<Window>>,
    at_fault: Vec<Vec<Value>>,
}

/// A snapshot may span a call that borrows its slot without replacing any resources.
fn preserves_cell(cx: &Cx, inst: &Inst, slot: u32) -> bool {
    inst.args.iter().enumerate().all(|(k, a)| {
        if a.0 != slot {
            return true;
        }
        match (inst.op, inst.imm) {
            (Op::Call, Imm::Func(g)) => {
                cx.safe.get(g.index()).and_then(|s| s.get(k)).copied() == Some(true)
            }
            (Op::Call | Op::CallRt | Op::CallInd | Op::CallMethod, _) => false,
            _ => true,
        }
    })
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
    let active = active_slot_closes(m, cx, f);
    let snapshots = scope_owned_takes(m, cx, f);
    let no_scope = BTreeSet::new();
    let mut entry: Vec<Option<BTreeSet<u32>>> = vec![None; f.blocks.len()];
    // Per block: the instruction run `first..=last` to cover and the values to register for it.
    let mut plans: Vec<Vec<Window>> = vec![Vec::new(); f.blocks.len()];
    // Per block: values to register before a terminating fault, which never returns.
    let mut at_fault: Vec<Vec<Value>> = vec![Vec::new(); f.blocks.len()];
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
        for (k, inst) in blk.insts.iter().enumerate() {
            let modes = crate::verify::arg_modes(m, inst);
            let consumed: Vec<u32> = inst
                .args
                .iter()
                .zip(&modes)
                .filter(|(a, mode)| **mode == Mode::Own && owned_def[a.index()])
                .map(|(a, _)| a.0)
                .collect();
            for c in &consumed {
                live.remove(c);
            }
            if live.iter().any(|v| {
                cx.cells.contains_key(v)
                    && (matches!(inst.op, Op::Take | Op::Put)
                        && inst.args.first().is_some_and(|a| a.0 == *v)
                        || !preserves_cell(cx, inst, *v))
            }) {
                // A later registration must load the current contents again, even when
                // this mutation itself cannot fault and would otherwise extend a window.
                reach = None;
            }
            if inst.op == Op::Take
                && inst
                    .args
                    .first()
                    .is_some_and(|a| cx.cells.contains_key(&a.0))
            {
                live.remove(&inst.args[0].0);
            }
            if open > 0 || matches!(inst.op, Op::CleanupPush | Op::CleanupRun) {
                // A window across a hole would drop a half-emptied owner, and one across a
                // scope open or close would discard an entry that is not its own.
                reach = None;
            } else if !live.is_empty() && exits_at(m, cx, inst) {
                let drops: Vec<Value> = coverable(
                    &live,
                    closed_by_with,
                    &hoisted[bi],
                    active.get(&(bi, k)).map(Rc::as_ref).unwrap_or(&no_scope),
                )
                .into_iter()
                .filter(|v| snapshots.needs_drop(*v, (bi, k)))
                .filter(|v| !cx.cells.contains_key(&v.0) || preserves_cell(cx, inst, v.0))
                .collect();
                match (&mut reach, plans[bi].last_mut()) {
                    (Some(set), Some(w)) if *set == drops => w.last = k,
                    _ => {
                        reach = None;
                        if !drops.is_empty() {
                            reach = Some(drops.clone());
                            plans[bi].push(Window {
                                first: k,
                                last: k,
                                values: drops,
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
            at_fault[bi] = coverable(
                &live,
                closed_by_with,
                &hoisted[bi],
                active
                    .get(&(bi, blk.insts.len()))
                    .map(Rc::as_ref)
                    .unwrap_or(&no_scope),
            )
            .into_iter()
            .filter(|v| snapshots.needs_drop(*v, (bi, blk.insts.len())))
            .collect();
        }
        let mut edges: Vec<Target> = Vec::new();
        blk.term.for_each_target(|t| edges.push(t.clone()));
        for t in edges {
            let dest = &f.blocks[t.block.index()];
            let mut after = live.clone();
            for (a, p) in t.args.iter().zip(&dest.params) {
                if p.mode == Mode::Own && owned_def[a.index()] {
                    after.remove(&a.0);
                }
            }
            if entry[t.block.index()].is_none() {
                entry[t.block.index()] = Some(after);
            }
        }
    }
    Walk {
        scope_snapshots: snapshots.exempt,
        entry,
        plans,
        at_fault,
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
    let initial = analyze(m, cx, f, owned_def, closed_by_with, &holes, &none());
    let entry = initial.entry;
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
    let mut chosen: Vec<(usize, Vec<Value>)> = Vec::new();
    for (h, body) in &loops {
        let Some(live) = &entry[*h] else { continue };
        let used = consumed_inside(m, f, owned_def, body);
        let held: Vec<Value> = live
            .iter()
            .filter(|v| {
                !closed_by_with.contains(v)
                    && !covered[*h].contains(v)
                    && !used.contains(v)
                    && !cx.cells.contains_key(v)
                    && !initial.scope_snapshots.contains(v)
            })
            .map(|v| Value(*v))
            .collect();
        if held.is_empty() {
            chosen.push((*h, Vec::new()));
            continue;
        }
        for &b in body {
            covered[b].extend(held.iter().map(|v| v.0));
        }
        chosen.push((*h, held));
    }
    let mut bodies: Vec<Vec<usize>> = loops.iter().map(|(_, b)| b.clone()).collect();
    let mut changed = false;
    for (li, (h, held)) in chosen.iter().enumerate() {
        if held.is_empty() {
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
        let first = push_all(m, cx, f, &mut insts, held, loc);
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

/// Owned values consumed by an instruction in `body`, or passed on an edge that stays inside it.
fn consumed_inside(m: &Module, f: &Func, owned_def: &[bool], body: &[usize]) -> BTreeSet<u32> {
    let mut used = BTreeSet::new();
    for &b in body {
        let blk = &f.blocks[b];
        for inst in &blk.insts {
            let modes = crate::verify::arg_modes(m, inst);
            for (a, mode) in inst.args.iter().zip(&modes) {
                if *mode == Mode::Own && owned_def[a.index()] {
                    used.insert(a.0);
                }
            }
        }
        blk.term.for_each_target(|t| {
            if !body.contains(&t.block.index()) {
                return;
            }
            for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                if p.mode == Mode::Own && owned_def[a.index()] {
                    used.insert(a.0);
                }
            }
        });
    }
    used
}

/// A discarded owner leaves the same physical slot value available for a later owner.
/// An overwritten slot instead leaves the old snapshot independent of future owners.
#[derive(Clone, Copy, PartialEq, Eq)]
struct DetachedSnapshot {
    slot: u32,
    replaced: bool,
    reowned: bool,
}

/// Proof state for local slot snapshots. Cleanup entries keep their original handles, so
/// discarding a newer entry preserves older owners and cancellation invalidates only its owner.
#[derive(Clone, Default, PartialEq, Eq)]
struct SlotCoverage {
    stack: Vec<(u32, Option<u32>)>,
    positions: BTreeMap<u32, usize>,
    owners: BTreeMap<u32, usize>,
    held: BTreeMap<u32, u32>,
    detached: BTreeMap<u32, DetachedSnapshot>,
    by_slot: BTreeMap<u32, BTreeSet<u32>>,
    /// Ownership lost from the must-stack may still be present on some runtime paths.
    ambiguous: BTreeSet<u32>,
}

impl SlotCoverage {
    fn owns(&self, slot: u32) -> bool {
        self.owners.contains_key(&slot)
    }

    fn hold(&mut self, group: u32, slot: u32) {
        self.forget_group(group);
        self.held.insert(group, slot);
        self.by_slot.entry(slot).or_default().insert(group);
    }

    fn forget_group(&mut self, group: u32) {
        let slot = self
            .held
            .remove(&group)
            .or_else(|| self.detached.remove(&group).map(|d| d.slot));
        if let Some(slot) = slot {
            let groups = self.by_slot.get_mut(&slot).expect("held snapshot");
            groups.remove(&group);
            if groups.is_empty() {
                self.by_slot.remove(&slot);
            }
        }
    }

    fn forget_slot(&mut self, slot: u32) {
        if let Some(groups) = self.by_slot.remove(&slot) {
            for group in groups {
                self.held.remove(&group);
                self.detached.remove(&group);
            }
        }
    }

    fn detach_slot(&mut self, slot: u32, replaced: bool) {
        if let Some(groups) = self.by_slot.get(&slot) {
            for group in groups {
                self.held.remove(group);
                let d = self.detached.entry(*group).or_insert(DetachedSnapshot {
                    slot,
                    replaced,
                    reowned: false,
                });
                d.replaced |= replaced;
                d.reowned = false;
            }
        }
    }

    fn clear_detached(&mut self) {
        let groups: Vec<u32> = self.detached.keys().copied().collect();
        for group in groups {
            self.forget_group(group);
        }
    }

    fn remove_owner(&mut self, slot: u32, detach: bool) {
        let count = self.owners.get_mut(&slot).expect("registered owner");
        *count -= 1;
        if *count == 0 {
            self.owners.remove(&slot);
            if detach {
                self.detach_slot(slot, false);
            } else {
                self.forget_slot(slot);
            }
        }
    }

    fn truncate(&mut self, len: usize, detach: bool) {
        while self.stack.len() > len {
            let (handle, owner) = self.stack.pop().expect("cleanup entry");
            self.positions.remove(&handle);
            if let Some(slot) = owner {
                self.remove_owner(slot, detach);
            }
        }
    }

    fn push(&mut self, handle: u32, owner: Option<u32>) {
        // A loop can execute a push again with the same SSA handle. Retain only the known
        // prefix before that iteration, so proof state stays bounded by the function's pushes.
        if let Some(at) = self.positions.get(&handle).copied() {
            self.ambiguous
                .extend(self.stack[at..].iter().filter_map(|(_, s)| *s));
            self.truncate(at, false);
        }
        if let Some(slot) = owner
            && let Some(groups) = self.by_slot.get(&slot)
        {
            for group in groups {
                if let Some(d) = self.detached.get_mut(group)
                    && !d.replaced
                {
                    d.reowned = true;
                }
            }
        }
        self.positions.insert(handle, self.stack.len());
        self.stack.push((handle, owner));
        if let Some(slot) = owner {
            *self.owners.entry(slot).or_default() += 1;
        }
    }

    fn merge(&mut self, incoming: &Self) -> bool {
        let common = self
            .stack
            .iter()
            .zip(&incoming.stack)
            .take_while(|(a, b)| a == b)
            .count();
        let missing: Vec<u32> = self
            .held
            .iter()
            .filter(|(g, s)| incoming.held.get(g) != Some(s))
            .map(|(g, _)| *g)
            .collect();
        let detached: BTreeMap<u32, DetachedSnapshot> = self
            .detached
            .iter()
            .filter_map(|(g, d)| {
                let other = incoming.detached.get(g)?;
                (d.slot == other.slot).then_some((
                    *g,
                    DetachedSnapshot {
                        slot: d.slot,
                        replaced: d.replaced && other.replaced,
                        reowned: d.reowned || other.reowned,
                    },
                ))
            })
            .collect();
        let changed_detachment = detached != self.detached;
        let before = self.ambiguous.len();
        self.ambiguous.extend(incoming.ambiguous.iter().copied());
        self.ambiguous.extend(
            self.stack[common..]
                .iter()
                .chain(&incoming.stack[common..])
                .filter_map(|(_, s)| *s),
        );
        let changed = common != self.stack.len()
            || !missing.is_empty()
            || before != self.ambiguous.len()
            || changed_detachment;
        self.truncate(common, false);
        for group in missing {
            self.forget_group(group);
        }
        self.clear_detached();
        for (group, d) in detached {
            self.detached.insert(group, d);
            self.by_slot.entry(d.slot).or_default().insert(group);
        }
        changed
    }
}

/// Original callbacks must load the exact slot type; arbitrary pointer cleanups are not owners.
fn scope_slot_owners(m: &Module, f: &Func) -> BTreeMap<u32, u32> {
    let local: BTreeMap<u32, Ty> = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter_map(|i| match (i.op, i.imm, i.res) {
            (Op::Slot, Imm::Ty(ty), Some(v)) => Some((v.0, ty)),
            _ => None,
        })
        .collect();
    f.blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter_map(|i| {
            let (Op::CleanupPush, Imm::Func(close), Some(handle)) = (i.op, i.imm, i.res) else {
                return None;
            };
            let slot = *i.args.first()?;
            if slot_close_value(m, close)? != *local.get(&slot.0)? {
                return None;
            }
            Some((handle.0, slot.0))
        })
        .collect()
}

fn scope_cleanup_step(state: &mut SlotCoverage, i: &Inst, m: &Module, owners: &BTreeMap<u32, u32>) {
    if let (Op::CleanupPush, Some(h)) = (i.op, i.res) {
        state.push(h.0, owners.get(&h.0).copied());
    }
    let cleanup = match (i.op, i.imm) {
        (Op::CleanupRun, _) => Some((false, false)),
        (Op::CallRt, Imm::Ext(e)) => match m.externs[e.index()].name.as_str() {
            "msrt_cleanup_cancel" => Some((true, true)),
            "msrt_cleanup_discard" => Some((false, true)),
            "msrt_cleanup_run" => Some((false, false)),
            _ => None,
        },
        _ => None,
    };
    if let Some((cancel, detach)) = cleanup {
        if !detach {
            state.clear_detached();
        }
        let at = i
            .args
            .first()
            .and_then(|h| state.positions.get(&h.0).copied());
        if let Some(at) = at {
            if cancel {
                if let Some(slot) = state.stack[at].1.take() {
                    state.remove_owner(slot, detach);
                }
            } else {
                state.truncate(at, detach);
            }
        } else {
            state.ambiguous.extend(state.owners.keys().copied());
            state.clear_detached();
            state.truncate(0, false);
        }
    }
}

/// Must-coverage at block entry. Joins keep only a common cleanup prefix and snapshots held
/// on every incoming edge. A worklist handles ordinary branches and loop backedges alike.
fn slot_coverage_entries(
    f: &Func,
    step: &impl Fn(&mut SlotCoverage, &Inst),
) -> Vec<Option<SlotCoverage>> {
    let mut entry: Vec<Option<SlotCoverage>> = vec![None; f.blocks.len()];
    entry[0] = Some(SlotCoverage::default());
    let mut work = VecDeque::from([0]);
    let mut queued = vec![false; f.blocks.len()];
    queued[0] = true;
    while let Some(b) = work.pop_front() {
        queued[b] = false;
        let mut state = entry[b].clone().expect("reachable block");
        for i in &f.blocks[b].insts {
            step(&mut state, i);
        }
        f.blocks[b].term.for_each_target(|t| {
            let bi = t.block.index();
            let changed = match &mut entry[bi] {
                Some(known) => known.merge(&state),
                place @ None => {
                    *place = Some(state.clone());
                    true
                }
            };
            if changed && !queued[bi] {
                work.push_back(bi);
                queued[bi] = true;
            }
        });
    }

    entry
}

/// Active slot owners only where unwind registration can be needed. In particular a normal
/// close runs after its scope entry was discarded, and then needs its own cell snapshot drop.
fn active_slot_closes(
    m: &Module,
    cx: &Cx,
    f: &Func,
) -> BTreeMap<(usize, usize), Rc<BTreeSet<u32>>> {
    let mut at = BTreeMap::new();
    if cx.scope_owners.is_empty() {
        return at;
    }
    let step = |state: &mut SlotCoverage, i: &Inst| {
        scope_cleanup_step(state, i, m, &cx.scope_owners);
    };
    let entry = slot_coverage_entries(f, &step);
    for (bi, b) in f.blocks.iter().enumerate() {
        let Some(mut state) = entry[bi].clone() else {
            continue;
        };
        let mut snapshot = None;
        for (k, i) in b.insts.iter().enumerate() {
            if exits_at(m, cx, i) {
                let held =
                    snapshot.get_or_insert_with(|| Rc::new(state.owners.keys().copied().collect()));
                at.insert((bi, k), Rc::clone(held));
            }
            step(&mut state, i);
            let changes_cleanup = matches!(i.op, Op::CleanupPush | Op::CleanupRun)
                || matches!((i.op, i.imm), (Op::CallRt, Imm::Ext(e)) if m.externs[e.index()].name.starts_with("msrt_cleanup_"));
            if changes_cleanup {
                snapshot = None;
            }
        }
        if matches!(b.term, Term::Fault(_)) {
            at.insert(
                (bi, b.insts.len()),
                snapshot.unwrap_or_else(|| Rc::new(state.owners.keys().copied().collect())),
            );
        }
    }
    at
}

/// SSA block arguments can relay a taken value, but a merge with any fresh definition must
/// not inherit its owner's coverage. Build disjoint groups once, rather than walking uses
/// separately for every Take. A qualifying group has exactly one definition: a local Take.
fn slot_groups(m: &Module, f: &Func) -> (Vec<usize>, Vec<Option<u32>>, BTreeMap<u32, Ty>) {
    fn root(parent: &mut [usize], mut v: usize) -> usize {
        while parent[v] != v {
            parent[v] = parent[parent[v]];
            v = parent[v];
        }
        v
    }
    let mut groups: Vec<usize> = (0..f.values.len()).collect();
    for b in &f.blocks {
        b.term.for_each_target(|t| {
            for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                let a = root(&mut groups, a.index());
                let p = root(&mut groups, p.value.index());
                groups[a.max(p)] = a.min(p);
            }
        });
    }
    for v in 0..groups.len() {
        groups[v] = root(&mut groups, v);
    }
    let local: BTreeMap<u32, Ty> = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter_map(|i| match (i.op, i.imm, i.res) {
            (Op::Slot, Imm::Ty(ty), Some(v)) => Some((v.0, ty)),
            _ => None,
        })
        .collect();
    let mut definitions = vec![0usize; groups.len()];
    let mut slots = vec![None; groups.len()];
    for p in &f.blocks[0].params {
        definitions[groups[p.value.index()]] += 1;
    }
    for i in f.blocks.iter().flat_map(|b| &b.insts) {
        let Some(r) = i.res else { continue };
        let group = groups[r.index()];
        definitions[group] += 1;
        if i.op == Op::Take
            && m.needs_drop(f.ty(r))
            && let Some(s) = i.args.first().filter(|s| local.contains_key(&s.0))
        {
            slots[group] = Some(s.0);
        }
    }
    for (g, slot) in slots.iter_mut().enumerate() {
        if definitions[g] != 1 {
            *slot = None;
        }
    }
    (groups, slots, local)
}

/// Slot addresses are opaque: an alias or escape before Take could later change the
/// snapshot invisibly. Only known identity-preserving slot borrowers may receive them.
fn escaped_slot_addresses(
    cx: &Cx,
    safe: &[Vec<bool>],
    f: &Func,
    local: &BTreeMap<u32, Ty>,
) -> BTreeSet<u32> {
    let mut escaped = BTreeSet::new();
    for b in &f.blocks {
        for i in &b.insts {
            for (k, a) in i
                .args
                .iter()
                .enumerate()
                .filter(|(_, a)| local.contains_key(&a.0))
            {
                let safe = match (i.op, i.imm) {
                    (Op::Take | Op::Load | Op::Put, _) => k == 0,
                    (Op::CleanupPush, _) => i
                        .res
                        .is_some_and(|h| cx.scope_owners.get(&h.0) == Some(&a.0)),
                    (Op::Call, Imm::Func(g)) => {
                        safe.get(g.index()).and_then(|s| s.get(k)).copied() == Some(true)
                    }
                    _ => false,
                };
                if !safe {
                    escaped.insert(a.0);
                }
            }
        }
        b.term.for_each_target(|t| {
            escaped.extend(
                t.args
                    .iter()
                    .filter(|a| local.contains_key(&a.0))
                    .map(|a| a.0),
            );
        });
        if let Term::Ret(Some(v)) = b.term
            && local.contains_key(&v.0)
        {
            escaped.insert(v.0);
        }
    }
    escaped
}

/// Existing protected alias groups remain owned in ordinary liveness. Their drops are
/// suppressed by default, preserving conservative behavior for unknown/mixed cleanup and
/// executed callbacks. Exact discard/cancel or slot replacement can establish independent
/// ownership at a particular exit, even when that exit never mentions the SSA value.
///
/// Eligibility still proves the whole alias group from explicit uses: only borrowing and
/// matching Put-back are allowed. Pointwise detachment does not widen that escape proof.
#[derive(Default)]
struct ScopeSnapshots {
    exempt: BTreeSet<u32>,
    groups: Vec<usize>,
    detached: BTreeMap<(usize, usize), Rc<BTreeSet<usize>>>,
}

impl ScopeSnapshots {
    fn needs_drop(&self, value: Value, point: (usize, usize)) -> bool {
        !self.exempt.contains(&value.0)
            || self
                .detached
                .get(&point)
                .is_some_and(|groups| groups.contains(&self.groups[value.index()]))
    }
}

fn scope_owned_takes(m: &Module, cx: &Cx, f: &Func) -> ScopeSnapshots {
    if cx.scope_owners.is_empty() {
        return ScopeSnapshots::default();
    }
    let (groups, mut slots, local) = slot_groups(m, f);
    if slots.iter().all(Option::is_none) {
        return ScopeSnapshots::default();
    }
    let owners = &cx.scope_owners;

    let escaped = escaped_slot_addresses(cx, &cx.safe, f, &local);
    for slot in &mut slots {
        if slot.is_some_and(|s| escaped.contains(&s)) {
            *slot = None;
        }
    }

    let step = |state: &mut SlotCoverage, i: &Inst| {
        for (a, mode) in i.args.iter().zip(crate::verify::arg_modes(m, i)) {
            if mode == Mode::Own {
                state.forget_group(groups[a.index()] as u32);
            }
        }
        // An address used by an unproven callee or arbitrary pointer operation may be changed.
        for (k, a) in i
            .args
            .iter()
            .enumerate()
            .filter(|(_, a)| local.contains_key(&a.0))
        {
            let safe = match (i.op, i.imm) {
                (Op::Take | Op::Load, _) => k == 0,
                (Op::Put, _) => false,
                (Op::CleanupPush, _) => i.res.is_some_and(|h| owners.contains_key(&h.0)),
                (Op::Call, Imm::Func(g)) => {
                    cx.safe.get(g.index()).and_then(|s| s.get(k)).copied() == Some(true)
                }
                _ => false,
            };
            if !safe {
                if i.op == Op::Put && k == 0 {
                    state.detach_slot(a.0, true);
                } else {
                    state.forget_slot(a.0);
                }
            }
        }
        scope_cleanup_step(state, i, m, owners);
        if i.op == Op::Take
            && let Some(r) = i.res
        {
            let g = groups[r.index()];
            state.forget_group(g as u32);
            if let Some(slot) = slots[g].filter(|s| state.owns(*s)) {
                state.hold(g as u32, slot);
            }
        }
    };

    let entry = slot_coverage_entries(f, &step);

    // Follow borrowed projections too: a field or view derived from a snapshot must not
    // escape, replace a payload, or enter an unproven indirect/mutating call. Owned results
    // are independent allocations and still receive their own unwind coverage.
    let mut borrowed = vec![BTreeSet::<usize>::new(); f.values.len()];
    let mut uses = vec![Vec::new(); f.values.len()];
    let mut pending = VecDeque::new();
    for v in 0..f.values.len() {
        if slots[groups[v]].is_some() {
            borrowed[v].insert(groups[v]);
            pending.push_back(v);
        }
    }
    for b in &f.blocks {
        for i in &b.insts {
            if let Some(r) = i.res
                && (m.result_mode(f, i) == Some(Mode::Borrow)
                    || m.result_views(i)
                    || f.ty(r) == Ty::PTR)
            {
                for a in &i.args {
                    uses[a.index()].push(r.index());
                }
            }
        }
        b.term.for_each_target(|t| {
            for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                uses[a.index()].push(p.value.index());
            }
        });
    }
    while let Some(v) = pending.pop_front() {
        for &to in &uses[v] {
            let inherited = borrowed[v].clone();
            let before = borrowed[to].len();
            borrowed[to].extend(inherited);
            if borrowed[to].len() != before {
                pending.push_back(to);
            }
        }
    }

    let mut detached = BTreeMap::new();
    let mut valid: Vec<bool> = slots.iter().map(Option::is_some).collect();
    let mut restored = vec![false; groups.len()];
    for (bi, b) in f.blocks.iter().enumerate() {
        let Some(mut state) = entry[bi].clone() else {
            continue;
        };
        let mut snapshot = None;
        for (k, i) in b.insts.iter().enumerate() {
            if exits_at(m, cx, i) && !state.detached.is_empty() {
                let set = snapshot.get_or_insert_with(|| {
                    Rc::new(
                        state
                            .detached
                            .iter()
                            .filter(|(_, d)| !d.reowned)
                            .map(|(g, _)| *g as usize)
                            .collect(),
                    )
                });
                detached.insert((bi, k), Rc::clone(set));
            }
            let modes = crate::verify::arg_modes(m, i);
            for (k, a) in i.args.iter().enumerate() {
                for &g in &borrowed[a.index()] {
                    let slot = slots[g].expect("snapshot origin");
                    let direct = groups[a.index()] == g;
                    let putback = direct
                        && i.op == Op::Put
                        && k == 1
                        && i.args.first().is_some_and(|s| s.0 == slot);
                    let method = match (i.op, i.imm) {
                        (Op::CallMethod, Imm::Method(iface, method)) if k == 0 => {
                            m.vtables.iter().filter(|v| v.iface == iface).all(|v| {
                                v.methods.get(method as usize).is_some_and(|g| {
                                    cx.safe.get(g.index()).and_then(|s| s.first()).copied()
                                        == Some(true)
                                })
                            })
                        }
                        _ => true,
                    };
                    let pointer_call = if f.ty(*a) == Ty::PTR && i.op.is_call() {
                        match (i.op, i.imm) {
                            (Op::Call, Imm::Func(callee)) => {
                                cx.safe.get(callee.index()).and_then(|s| s.get(k)).copied()
                                    == Some(true)
                            }
                            _ => false,
                        }
                    } else {
                        true
                    };
                    let reads = modes.get(k) == Some(&Mode::Borrow)
                        && method
                        && pointer_call
                        && !matches!(
                            i.op,
                            Op::MoveOut
                                | Op::Store
                                | Op::Put
                                | Op::CleanupPush
                                | Op::RecFill
                                | Op::ListFill
                                | Op::CallInd
                        );
                    valid[g] &= state.held.contains_key(&(g as u32)) && (putback || reads);
                    restored[g] |= putback;
                }
            }
            step(&mut state, i);
            if matches!(i.op, Op::Take | Op::Put | Op::CleanupPush | Op::CleanupRun)
                || matches!((i.op, i.imm), (Op::CallRt, Imm::Ext(e)) if m.externs[e.index()].name.starts_with("msrt_cleanup_"))
                || i.op == Op::Drop
            {
                snapshot = None;
            }
        }
        if matches!(b.term, Term::Fault(_)) && !state.detached.is_empty() {
            detached.insert(
                (bi, b.insts.len()),
                snapshot.unwrap_or_else(|| {
                    Rc::new(
                        state
                            .detached
                            .iter()
                            .filter(|(_, d)| !d.reowned)
                            .map(|(g, _)| *g as usize)
                            .collect(),
                    )
                }),
            );
        }
        b.term.for_each_target(|t| {
            for a in &t.args {
                let g = groups[a.index()];
                if slots[g].is_some() {
                    valid[g] &= state.held.contains_key(&(g as u32));
                }
            }
        });
        if let Term::Ret(Some(v)) = b.term {
            for &g in &borrowed[v.index()] {
                valid[g] = false;
            }
        }
    }
    let exempt = groups
        .iter()
        .enumerate()
        .filter(|(_, g)| valid[**g] && restored[**g])
        .map(|(v, _)| v as u32)
        .collect();
    ScopeSnapshots {
        exempt,
        groups,
        detached,
    }
}

fn function(m: &mut Module, cx: &mut Cx, f: &mut Func) -> bool {
    if f.blocks.is_empty() {
        return false;
    }
    let rc = |v: Value| m.needs_drop(f.ty(v));
    let slot_params: BTreeSet<u32> = f.blocks[0].params.iter().map(|p| p.value.0).collect();
    let mut owned_def = vec![false; f.values.len()];
    let mut from_slot: BTreeSet<u32> = BTreeSet::new();
    for b in &f.blocks {
        for p in &b.params {
            owned_def[p.value.index()] = rc(p.value) && p.mode == Mode::Own;
        }
        for i in &b.insts {
            // A value taken out of a slot the caller passed in stays the caller's: the slot still
            // holds it while the call runs, and the caller (or its owner) drops it. Dropping it
            // here too would drop it twice.
            let from_caller_slot =
                i.op == Op::Take && i.args.first().is_some_and(|a| slot_params.contains(&a.0));
            if let (Some(r), Some(Mode::Own)) = (i.res, m.result_mode(f, i)) {
                owned_def[r.index()] = !from_caller_slot;
                if from_caller_slot {
                    from_slot.insert(r.0);
                }
            }
        }
    }
    // A block parameter that receives such a value stays the caller's too.
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
        }
    }
    cx.scope_owners = scope_slot_owners(m, f);
    cx.cells = find_cells(m, cx, f);
    // Quick exit: nothing can be live across a call without an owned definition.
    if !owned_def.iter().any(|o| *o) && cx.cells.is_empty() {
        return false;
    }
    let wrapped = wrap_with_closers(m, cx, f);
    // Values an existing cleanup entry (a scope close) uses: it must see them undropped.
    let closed_by_with: BTreeSet<u32> = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter(|i| i.op == Op::CleanupPush)
        .filter_map(|i| i.args.first().map(|v| v.0))
        .filter(|v| !cx.cells.contains_key(v))
        .collect();
    let (hoisted, hoists) = hoist_loops(m, cx, f, &mut owned_def, &closed_by_with);
    let holes = hole_states(f);
    let Walk {
        plans,
        mut at_fault,
        ..
    } = analyze(m, cx, f, &owned_def, &closed_by_with, &holes, &hoisted);
    if plans.iter().all(|p| p.is_empty()) && at_fault.iter().all(|v| v.is_empty()) {
        return wrapped || hoists;
    }
    for bi in 0..f.blocks.len() {
        let plan = &plans[bi];
        if plan.is_empty() && at_fault[bi].is_empty() {
            continue;
        }
        let old = std::mem::take(&mut f.blocks[bi].insts);
        let mut out: Vec<Inst> = Vec::with_capacity(old.len() + plan.len() * 3);
        let mut next = plan.iter().peekable();
        let mut open_window: Option<(usize, Value, Option<crate::ir::Loc>)> = None;
        let end_loc = old.last().map(|i| i.loc);
        for (k, inst) in old.into_iter().enumerate() {
            let loc = inst.loc;
            if let Some(w) = next.next_if(|w| w.first == k) {
                let first = push_all(m, cx, f, &mut out, &w.values, loc);
                open_window = Some((w.last, first, Some(loc)));
            }
            out.push(inst);
            if let Some((last, first, loc)) = open_window
                && last == k
            {
                out.push(Inst {
                    op: Op::CallRt,
                    args: vec![first],
                    imm: Imm::Ext(cx.discard),
                    res: Some(f.new_value(Ty::UNIT)),
                    loc: loc.expect("window location"),
                });
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

/// A run of instructions `first..=last` of one block covered by one registration of `values`.
#[derive(Clone)]
struct Window {
    first: usize,
    last: usize,
    values: Vec<Value>,
}

/// The live values a registration may cover: a scope close sees its own values undropped, and a
/// loop registration already covers its hoisted values.
fn coverable(
    live: &BTreeSet<u32>,
    closed_by_with: &BTreeSet<u32>,
    hoisted: &BTreeSet<u32>,
    active_scope: &BTreeSet<u32>,
) -> Vec<Value> {
    live.iter()
        .filter(|v| {
            !closed_by_with.contains(v) && !hoisted.contains(v) && !active_scope.contains(v)
        })
        .map(|v| Value(*v))
        .collect()
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
    let mut first = None;
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
        let c = closer(m, cx, ty);
        let h = f.new_value(Ty::INT);
        out.push(Inst {
            op: Op::CleanupPush,
            args: vec![held],
            imm: Imm::Func(c),
            res: Some(h),
            loc,
        });
        first.get_or_insert(h);
    }
    first.expect("a registered value")
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
        Op::RecFill | Op::ListFill => open.saturating_sub(1),
        _ => open,
    }
}

/// A scope-owned slot can stay full across the Result branches of a normal close. Keep
/// this extension separate from general cells: every address use must be proven, and every
/// reachable block entry must agree on full/empty occupancy. Mixed states are rejected, so
/// the existing liveness walk never picks an arbitrary predecessor's cell ownership.
fn scope_cells(m: &Module, cx: &Cx, f: &Func) -> BTreeMap<u32, Ty> {
    let registered: BTreeSet<u32> = cx.scope_owners.values().copied().collect();
    let mut slots: BTreeMap<u32, Ty> = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter_map(|i| match (i.op, i.imm, i.res) {
            (Op::Slot, Imm::Ty(ty), Some(v)) if registered.contains(&v.0) => Some((v.0, ty)),
            _ => None,
        })
        .collect();
    let escaped = escaped_slot_addresses(cx, &cx.local, f, &slots);
    slots.retain(|s, _| !escaped.contains(s));
    if slots.is_empty() {
        return slots;
    }
    let step = |state: &mut BTreeMap<u32, bool>, i: &Inst| {
        if matches!(i.op, Op::Put | Op::Take)
            && let Some(s) = i.args.first().filter(|s| slots.contains_key(&s.0))
        {
            state.insert(s.0, i.op == Op::Put);
        }
    };
    let mut entry: Vec<Option<BTreeMap<u32, bool>>> = vec![None; f.blocks.len()];
    entry[0] = Some(slots.keys().map(|s| (*s, false)).collect());
    let mut work = VecDeque::from([0]);
    let mut queued = vec![false; f.blocks.len()];
    queued[0] = true;
    while let Some(b) = work.pop_front() {
        queued[b] = false;
        let mut state = entry[b].clone().expect("reachable block");
        for i in &f.blocks[b].insts {
            step(&mut state, i);
        }
        f.blocks[b].term.for_each_target(|t| {
            let bi = t.block.index();
            let changed = match &mut entry[bi] {
                Some(known) => {
                    let before = known.len();
                    known.retain(|s, full| state.get(s) == Some(full));
                    known.len() != before
                }
                place @ None => {
                    *place = Some(state.clone());
                    true
                }
            };
            if changed && !queued[bi] {
                work.push_back(bi);
                queued[bi] = true;
            }
        });
    }
    let mut bad = BTreeSet::new();
    for (bi, b) in f.blocks.iter().enumerate() {
        let Some(mut state) = entry[bi].clone() else {
            continue;
        };
        bad.extend(slots.keys().filter(|s| !state.contains_key(s)).copied());
        for i in &b.insts {
            for (k, a) in i
                .args
                .iter()
                .enumerate()
                .filter(|(_, a)| slots.contains_key(&a.0))
            {
                let ty = slots[&a.0];
                let valid = match (i.op, i.imm) {
                    (Op::Put, _) => {
                        k == 0 && state.get(&a.0) == Some(&false) && f.ty(i.args[1]) == ty
                    }
                    (Op::Take | Op::Load, Imm::Ty(read)) => {
                        k == 0 && read == ty && state.get(&a.0) == Some(&true)
                    }
                    _ => state.get(&a.0) == Some(&true), // Address uses already passed the escape proof.
                };
                if !valid {
                    bad.insert(a.0);
                }
            }
            step(&mut state, i);
        }
    }
    let cleanup_step =
        |state: &mut SlotCoverage, i: &Inst| scope_cleanup_step(state, i, m, &cx.scope_owners);
    let cleanup_entry = slot_coverage_entries(f, &cleanup_step);
    for (bi, b) in f.blocks.iter().enumerate() {
        let Some(mut state) = cleanup_entry[bi].clone() else {
            continue;
        };
        bad.extend(state.ambiguous.iter().copied());
        for i in &b.insts {
            cleanup_step(&mut state, i);
            bad.extend(state.ambiguous.iter().copied());
        }
    }
    slots.retain(|s, ty| !bad.contains(s) && m.needs_drop(*ty));
    slots
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
                    (Op::CleanupPush, _) => {
                        full.contains(&a.0)
                            && inst
                                .res
                                .is_some_and(|h| cx.scope_owners.get(&h.0) == Some(&a.0))
                    }
                    (Op::Call, Imm::Func(g)) => {
                        full.contains(&a.0)
                            && cx.safe.get(g.index()).and_then(|p| p.get(k)).copied() == Some(true)
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
    let registered: BTreeSet<u32> = cx.scope_owners.values().copied().collect();
    slots.retain(|s, _| !bad.contains(s) && !registered.contains(s));
    slots.extend(scope_cells(m, cx, f));
    slots
}

/// Per function and parameter, whether a slot pointer remains local. Without `replacements`,
/// every borrowed value retains the same owned resources. With it, owned-field updates are
/// also allowed when the updated record is immediately put back in the original slot.
fn slot_borrowers(m: &Module, replacements: bool, preserved: &[Vec<bool>]) -> Vec<Vec<bool>> {
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
                if safe[fi][k] && !borrows_slot_param(m, &safe, f, k, replacements, preserved) {
                    safe[fi][k] = false;
                    changed = true;
                }
            }
        }
    }
    safe
}

/// Updating a plain-data record field preserves every resource the old record owns.
/// A cleanup snapshot may retain the old scalar bits unless they control conditional
/// ownership. An owned-field or drop-control update could invalidate that snapshot.
fn keeps_record_resources(m: &Module, i: &Inst) -> bool {
    let (Op::RecSet, Imm::Field(r, field)) = (i.op, i.imm) else {
        return false;
    };
    if m.shared_guard_fields(r)
        .is_some_and(|(held, _)| held == field as usize)
    {
        return false;
    }
    m.records
        .get(r.index())
        .and_then(|r| r.fields.get(field as usize))
        .is_some_and(|(_, ty)| !m.needs_drop(*ty))
}

/// Scalar values and aggregates of scalars cannot retain a borrowed resource or address.
/// Raw pointers still count, including pointers nested in otherwise non-dropping data.
fn may_hold_borrow(m: &Module, ty: Ty) -> bool {
    if m.needs_drop(ty) {
        return true;
    }
    match m.types.kind(ty) {
        TyKind::Ptr => true,
        TyKind::Rec(r) => m.records[r.index()]
            .fields
            .iter()
            .any(|(_, t)| may_hold_borrow(m, *t)),
        TyKind::Alt(a) => m.alts[a.index()]
            .cases
            .iter()
            .any(|c| c.fields.iter().any(|(_, t)| may_hold_borrow(m, *t))),
        TyKind::Opt(inner) => may_hold_borrow(m, *inner),
        _ => false,
    }
}

fn borrows_slot_param(
    m: &Module,
    safe: &[Vec<bool>],
    f: &Func,
    k: usize,
    replacements: bool,
    preserved: &[Vec<bool>],
) -> bool {
    let Some(p) = f
        .blocks
        .first()
        .and_then(|b| b.params.get(k))
        .map(|p| p.value)
    else {
        return false;
    };
    let updates: BTreeSet<u32> = f
        .blocks
        .iter()
        .flat_map(|b| {
            b.insts.iter().enumerate().filter_map(|(n, i)| {
                let r = i.res?;
                let restored = i.op == Op::RecSet
                    && b.insts
                        .get(n + 1)
                        .is_some_and(|next| next.op == Op::Put && next.args.as_slice() == [p, r]);
                (restored && (keeps_record_resources(m, i) || replacements)).then_some(r.0)
            })
        })
        .collect();
    // What `p` holds (taken, or passed on to a block parameter), and the borrows derived from it.
    let mut taken: BTreeSet<u32> = BTreeSet::new();
    let mut derived: BTreeSet<u32> = BTreeSet::new();
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
            let Some(r) = inst.res else { continue };
            if updates.contains(&r.0)
                && inst.args.first().is_some_and(|a| taken.contains(&a.0))
                && taken.insert(r.0)
            {
                grew = true;
            }
            let from_held = inst
                .args
                .iter()
                .any(|a| taken.contains(&a.0) || derived.contains(&a.0));
            let view = inst.op == Op::Load && inst.args.first() == Some(&p);
            if (from_held || view)
                && !taken.contains(&r.0)
                && m.result_mode(f, inst) != Some(Mode::Own)
                && may_hold_borrow(m, f.ty(r))
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
                if *a == p {
                    let ok = match (inst.op, inst.imm) {
                        (Op::Take | Op::Load, _) => i == 0,
                        (Op::Put, _) => i == 0 && taken.contains(&inst.args[1].0),
                        (Op::Call, Imm::Func(g)) => {
                            safe.get(g.index()).and_then(|s| s.get(i)).copied() == Some(true)
                                // An old Take cannot later be put back after a forwarded
                                // mutator has replaced the resources it physically holds.
                                && (!replacements
                                    || taken.is_empty()
                                    || preserved.get(g.index()).and_then(|s| s.get(i)).copied()
                                        == Some(true))
                        }
                        _ => false,
                    };
                    if !ok {
                        return false;
                    }
                } else if taken.contains(&a.0) || derived.contains(&a.0) {
                    let putback = inst.op == Op::Put && i == 1 && inst.args[0] == p;
                    let record_update = i == 0
                        && taken.contains(&a.0)
                        && inst.res.is_some_and(|r| updates.contains(&r.0));
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
                                | Op::RecFill
                                | Op::ListFill
                                | Op::CallInd
                        );
                    if !putback && !record_update && !borrowed {
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
