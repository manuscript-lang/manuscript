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
use crate::types::Ty;
use std::collections::{BTreeMap, BTreeSet, HashMap};

/// Runtime symbols whose presence means the program starts tasks that can be cancelled.
const SPAWNERS: &[&str] = &["msrt_scope_spawn", "msrt_worker_start"];

/// Runtime functions that never reach a cancellation point. `msrt_shared_hold` is not one of them,
/// although it never parks: a hold must be registered after the cleanups of the values live across
/// the call it holds for, so that a cancelled call ends the hold before those values are dropped.
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
    "msrt_shared_release",
    "msrt_addr_id",
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
    let closures = closures_by_type(m);

    let mut cx = Cx {
        parks,
        faults,
        safe: slot_safe_params(m, &closures),
        closures,
        cells: BTreeMap::new(),
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
    /// The functions each function type's closures are made from.
    closures: HashMap<Ty, Vec<FuncId>>,
    /// The slots of the function being rewritten that hold an owned value between a `put` and a
    /// `take`, with the type held.
    cells: BTreeMap<u32, Ty>,
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
    entry: Vec<Option<BTreeSet<u32>>>,
    plans: Vec<Vec<Window>>,
    at_fault: Vec<Vec<Value>>,
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
                let drops = coverable(&live, closed_by_with, &hoisted[bi]);
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
            at_fault[bi] = coverable(&live, closed_by_with, &hoisted[bi]);
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
    // A block parameter that receives such a value stays the caller's too, and so does a local
    // slot it is put into for a call (`homes`) and what is taken back out of that slot.
    let mut homes: BTreeSet<u32> = BTreeSet::new();
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
                if i.op == Op::Put && from_slot.contains(&i.args[1].0) && homes.insert(i.args[0].0)
                {
                    moved = true;
                }
                if let (Op::Take, Some(r)) = (i.op, i.res)
                    && homes.contains(&i.args[0].0)
                    && from_slot.insert(r.0)
                {
                    owned_def[r.index()] = false;
                    moved = true;
                }
            }
        }
    }
    cx.cells = find_cells(m, cx, f);
    cx.cells.retain(|s, _| !homes.contains(s));
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
) -> Vec<Value> {
    live.iter()
        .filter(|v| !closed_by_with.contains(v) && !hoisted.contains(v))
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
                    (Op::CallInd, _) if k > 0 => {
                        full.contains(&a.0)
                            && indirect_safe(&cx.safe, &cx.closures, f.ty(inst.args[0]), k)
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

/// Per function and parameter, whether the parameter is a pointer to a slot whose contents the
/// function only borrows: it `take`s them, uses them as borrows, and `put`s the same value back.
fn slot_safe_params(m: &Module, closures: &HashMap<Ty, Vec<FuncId>>) -> Vec<Vec<bool>> {
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
                if safe[fi][k] && !borrows_slot_param(m, &safe, closures, f, k) {
                    safe[fi][k] = false;
                    changed = true;
                }
            }
        }
    }
    safe
}

/// The functions the closures of each function type are made from (`closure.new`).
fn closures_by_type(m: &Module) -> HashMap<Ty, Vec<FuncId>> {
    let mut by_type: HashMap<Ty, Vec<FuncId>> = HashMap::new();
    for f in &m.funcs {
        for inst in f.blocks.iter().flat_map(|b| &b.insts) {
            if let (Op::ClosureNew, Imm::Func(g), Some(r)) = (inst.op, inst.imm, inst.res) {
                let all = by_type.entry(f.ty(r)).or_default();
                if !all.contains(&g) {
                    all.push(g);
                }
            }
        }
    }
    by_type
}

/// Whether every function a closure of type `fty` can run only borrows the slot passed as its
/// argument `k` (the closure itself is argument 0, as its environment is parameter 0).
fn indirect_safe(
    safe: &[Vec<bool>],
    closures: &HashMap<Ty, Vec<FuncId>>,
    fty: Ty,
    k: usize,
) -> bool {
    closures.get(&fty).is_some_and(|all| {
        all.iter()
            .all(|g| safe.get(g.index()).and_then(|s| s.get(k)).copied() == Some(true))
    })
}

/// Whether values of `ty` are plain numbers or flags, which hold no pointer.
fn scalar(m: &Module, ty: Ty) -> bool {
    m.types.is_int(ty) || matches!(ty, Ty::UNIT | Ty::BOOL | Ty::FLOAT | Ty::FLOAT32)
}

fn borrows_slot_param(
    m: &Module,
    safe: &[Vec<bool>],
    closures: &HashMap<Ty, Vec<FuncId>>,
    f: &Func,
    k: usize,
) -> bool {
    let Some(p) = f
        .blocks
        .first()
        .and_then(|b| b.params.get(k))
        .map(|p| p.value)
    else {
        return false;
    };
    // What `p` holds (taken, or passed on to a block parameter), and the borrows derived from it.
    // The value may move unchanged through local slots (`homes`), as it does when the function
    // hands it to a callee that changes it in place: those slots are held to the rules of `p`.
    let mut taken: BTreeSet<u32> = BTreeSet::new();
    let mut derived: BTreeSet<u32> = BTreeSet::new();
    let mut homes: BTreeSet<u32> = BTreeSet::from([p.0]);
    let local_slots: BTreeSet<u32> = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter(|i| i.op == Op::Slot)
        .filter_map(|i| i.res.map(|r| r.0))
        .collect();
    let mut grew = true;
    while grew {
        grew = false;
        for inst in f.blocks.iter().flat_map(|b| &b.insts) {
            let home = inst.args.first().is_some_and(|a| homes.contains(&a.0));
            if let (Op::Take, Some(r), true) = (inst.op, inst.res, home)
                && taken.insert(r.0)
            {
                grew = true;
            }
            if inst.op == Op::Put
                && local_slots.contains(&inst.args[0].0)
                && taken.contains(&inst.args[1].0)
                && homes.insert(inst.args[0].0)
            {
                grew = true;
            }
        }
        for inst in f.blocks.iter().flat_map(|b| &b.insts) {
            let Some(r) = inst.res else { continue };
            let from_held = inst
                .args
                .iter()
                .any(|a| taken.contains(&a.0) || derived.contains(&a.0));
            let view =
                inst.op == Op::Load && inst.args.first().is_some_and(|a| homes.contains(&a.0));
            // A number or flag read out of the value is a copy, not a borrow of it. The box a
            // `Shared` handle points to is outside the value: changing it leaves the value's bits.
            if (from_held || view)
                && inst.op != Op::SharedAddr
                && !scalar(m, f.ty(r))
                && !taken.contains(&r.0)
                && m.result_mode(f, inst) != Some(Mode::Own)
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
                if homes.contains(&a.0) {
                    let ok = match (inst.op, inst.imm) {
                        (Op::Take | Op::Load, _) => i == 0,
                        (Op::Put, _) => i == 0 && taken.contains(&inst.args[1].0),
                        (Op::Call, Imm::Func(g)) => {
                            safe.get(g.index()).and_then(|s| s.get(i)).copied() == Some(true)
                        }
                        (Op::CallInd, _) => {
                            i > 0 && indirect_safe(safe, closures, f.ty(inst.args[0]), i)
                        }
                        _ => false,
                    };
                    if !ok {
                        return false;
                    }
                } else if taken.contains(&a.0) || derived.contains(&a.0) {
                    let putback = inst.op == Op::Put && i == 1 && homes.contains(&inst.args[0].0);
                    // Writing a number or flag into memory the value owns changes it in place;
                    // the slot still holds the same value.
                    let in_place = i == 0
                        && match inst.op {
                            Op::Store | Op::Put => scalar(m, f.ty(inst.args[1])),
                            Op::Take => inst.res.is_some_and(|r| scalar(m, f.ty(r))),
                            _ => false,
                        };
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
                    if !putback && !in_place && !borrowed {
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
