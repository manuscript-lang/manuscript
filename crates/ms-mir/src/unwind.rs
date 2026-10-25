//! The `unwind` pass: lets a cancelled task release the values its frames own.
//!
//! Cancellation leaves a task by a jump, so no `drop` after the park point runs. Around every
//! call that can reach a cancellation point the pass registers one runtime cleanup per owned
//! value that is live across the call, and discards them when the call returns:
//!
//! ```text
//! h = cleanup.push v, drop_if_unwinding;  ..;  call f(..);  call.rt msrt_cleanup_discard(h)
//! ```
//!
//! `cleanup.push` keeps a bitwise copy of `v`, which is sound because `v` is owned, live and
//! not consumed by the call. The cleanup drops `v` only when `msrt_unwind_drops` says a
//! cancellation is leaving a guarded task; a fault or a process exit frees nothing.
//!
//! Only programs that start tasks or workers are rewritten. A value moved out of a field and
//! not yet filled back leaves a hole in its owner, so calls inside that window are skipped, as
//! are values held in stack slots (a call may leave a `var` local there); both only leak.

use crate::builder::FuncBuilder;
use crate::ir::*;
use crate::types::Ty;
use std::collections::{BTreeSet, HashMap};

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
    "msrt_json_",
    "msrt_path_",
    "msrt_url_",
    "msrt_html_",
    "msrt_encoding_",
    "msrt_binary_",
    "msrt_regex_",
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
    });
    let mut cx = Cx {
        parks,
        discard,
        closers: HashMap::new(),
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
    discard: ExtId,
    /// The cleanup that drops a value of a type while a cancellation unwinds.
    closers: HashMap<Ty, FuncId>,
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

fn function(m: &mut Module, cx: &mut Cx, f: &mut Func) -> bool {
    if f.blocks.is_empty() {
        return false;
    }
    let rc = |v: Value| m.needs_drop(f.ty(v));
    let mut owned_def = vec![false; f.values.len()];
    for b in &f.blocks {
        for p in &b.params {
            owned_def[p.value.index()] = rc(p.value) && p.mode == Mode::Own;
        }
        for i in &b.insts {
            if let (Some(r), Some(Mode::Own)) = (i.res, m.result_mode(f, i)) {
                owned_def[r.index()] = true;
            }
        }
    }
    // Quick exit: nothing can be live across a call without an owned definition.
    if !owned_def.iter().any(|o| *o) {
        return false;
    }
    let holes = hole_states(f);
    let mut entry: Vec<Option<BTreeSet<u32>>> = vec![None; f.blocks.len()];
    // Per block: instruction index -> values to register before it.
    let mut plans: Vec<Vec<(usize, Vec<Value>)>> = vec![Vec::new(); f.blocks.len()];
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
            if open == 0 && !live.is_empty() && parks_at(m, cx, inst) {
                plans[bi].push((k, live.iter().map(|v| Value(*v)).collect()));
            }
            open = hole_step(open, inst.op);
            if let Some(r) = inst.res.filter(|r| owned_def[r.index()]) {
                live.insert(r.0);
            }
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
    if plans.iter().all(|p| p.is_empty()) {
        return false;
    }
    for (bi, plan) in plans.iter().enumerate() {
        if plan.is_empty() {
            continue;
        }
        let old = std::mem::take(&mut f.blocks[bi].insts);
        let mut out: Vec<Inst> = Vec::with_capacity(old.len() + plan.len() * 3);
        let mut next = plan.iter().peekable();
        for (k, inst) in old.into_iter().enumerate() {
            let Some((_, values)) = next.next_if(|(pk, _)| *pk == k) else {
                out.push(inst);
                continue;
            };
            let loc = inst.loc;
            let mut first = None;
            for v in values {
                let c = closer(m, cx, f.ty(*v));
                let h = f.new_value(Ty::INT);
                out.push(Inst {
                    op: Op::CleanupPush,
                    args: vec![*v],
                    imm: Imm::Func(c),
                    res: Some(h),
                    loc,
                });
                first.get_or_insert(h);
            }
            out.push(inst);
            out.push(Inst {
                op: Op::CallRt,
                args: vec![first.expect("a registered value")],
                imm: Imm::Ext(cx.discard),
                res: Some(f.new_value(Ty::UNIT)),
                loc,
            });
        }
        f.blocks[bi].insts = out;
    }
    true
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
