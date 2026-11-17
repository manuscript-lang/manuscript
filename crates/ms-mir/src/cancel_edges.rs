//! The `cancel_edges` pass: makes a delivered cancel leave a task by ordinary returns.
//!
//! A park that is cancelled sets the task's `unwinding` byte and returns (`proposals/cancel-cleanup-by-edge.md`).
//! After every call that can park, this pass tests the byte and leaves the function through a
//! cancel exit:
//!
//! ```text
//! r = call f(..); u = call.rt msrt_unwinding(); c = ne u, 0; condbr c, x1, next
//! x1: forget <every owned value live here>; br exit
//! exit: call.rt msrt_cleanup_unwind_to(base); %z = undef; ret %z
//! ```
//!
//! This first form is hybrid: the cleanups the `unwind` pass registered for the function still
//! free its owners, run by `msrt_cleanup_unwind_to` from the height taken at entry (`base`), so
//! the owned values on the exit edge are forgotten and nothing is freed differently from today.
//! Later forms replace the registered cleanups of a function by explicit drops placed from the
//! function's own move state.
//!
//! The pass runs after `unwind`, only on modules that start tasks, and only when edges are
//! switched on (`MS_CANCEL_EDGES`), until every native returns instead of jumping.

use crate::ir::*;
use crate::types::Ty;
use crate::verify::arg_modes;
use std::collections::BTreeSet;

/// Whether the edges are switched on for this build.
pub fn enabled() -> bool {
    std::env::var_os("MS_CANCEL_EDGES").is_some()
}

fn extern_of(
    m: &mut Module,
    name: &str,
    params: &[Ty],
    ret: Ty,
    leaf: bool,
    role: ExternRole,
) -> ExtId {
    if let Some(i) = m.externs.iter().position(|e| e.name == name) {
        return ExtId(i as u32);
    }
    m.add_extern(ExternDef {
        name: name.into(),
        params: params
            .iter()
            .map(|ty| Param {
                ty: *ty,
                mode: Mode::Borrow,
            })
            .collect(),
        ret,
        noreturn: false,
        pure_: false,
        fresh: false,
        retains: false,
        role,
        leaf,
        reads: false,
    })
}

/// Rewrites every function of `m` that calls something that can park; returns whether any changed.
pub fn run(m: &mut Module) -> bool {
    if !crate::unwind::starts_tasks(m) {
        return false;
    }
    let parks = crate::unwind::parking_funcs(m);
    let unwinding = extern_of(
        m,
        "msrt_unwinding",
        &[],
        Ty::UINT8,
        true,
        ExternRole::Unwinding,
    );
    let base = extern_of(m, "msrt_cleanup_base", &[], Ty::INT, true, ExternRole::None);
    let unwind_to = extern_of(
        m,
        "msrt_cleanup_unwind_to",
        &[Ty::INT],
        Ty::VOID,
        false,
        ExternRole::None,
    );
    let ext = Ext {
        unwinding,
        base,
        unwind_to,
    };
    let mut changed = false;
    // The runtime's natives return with the flag set instead of jumping only once the program
    // says every function checks it.
    let on = extern_of(
        m,
        "msrt_cancel_edges",
        &[],
        Ty::VOID,
        true,
        ExternRole::None,
    );
    if let Some(entry) = m.entry {
        let f = &mut m.funcs[entry.index()];
        if !f.blocks.is_empty() {
            let at = usize::from(
                f.blocks[0]
                    .insts
                    .first()
                    .is_some_and(|i| i.op == Op::DepthEnter),
            );
            let res = f.new_value(Ty::VOID);
            let loc = f.loc;
            f.blocks[0].insts.insert(
                at,
                Inst {
                    op: Op::CallRt,
                    args: vec![],
                    imm: Imm::Ext(on),
                    res: Some(res),
                    loc,
                },
            );
            changed = true;
        }
    }
    for fi in 0..m.funcs.len() {
        if m.funcs[fi].blocks.is_empty() || m.funcs[fi].unwind_only {
            continue;
        }
        let stand_in = m.funcs[fi].signature_stand_in();
        let mut f = std::mem::replace(&mut m.funcs[fi], stand_in);
        changed |= function(m, &parks, ext, &mut f);
        m.funcs[fi] = f;
    }
    changed
}

#[derive(Clone, Copy)]
struct Ext {
    unwinding: ExtId,
    base: ExtId,
    unwind_to: ExtId,
}

/// Whether `inst` can reach a cancellation point.
fn parks(m: &Module, parks: &[bool], inst: &Inst) -> bool {
    match (inst.op, inst.imm) {
        (Op::Poll | Op::CallInd | Op::CallMethod, _) => true,
        (Op::CallRt, Imm::Ext(e)) => {
            let d = &m.externs[e.index()];
            !(d.noreturn || d.leaf)
        }
        (Op::Call, Imm::Func(g)) => parks.get(g.index()).copied().unwrap_or(true),
        _ => false,
    }
}

fn inst(f: &mut Func, op: Op, args: Vec<Value>, imm: Imm, ty: Ty, loc: Loc) -> (Inst, Value) {
    let r = f.new_value(ty);
    (
        Inst {
            op,
            args,
            imm,
            res: Some(r),
            loc,
        },
        r,
    )
}

fn function(m: &Module, parks_of: &[bool], ext: Ext, f: &mut Func) -> bool {
    // Nothing parks in this function: no edge, and no base to take.
    let any = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .any(|i| parks(m, parks_of, i));
    if !any {
        return false;
    }
    let owned = |f: &Func, v: Value| m.needs_drop(f.ty(v));
    let entry_loc = f.loc;
    // The cleanup height at entry, and the one exit every site leaves through.
    let (base_inst, base) = inst(
        f,
        Op::CallRt,
        vec![],
        Imm::Ext(ext.base),
        Ty::INT,
        entry_loc,
    );
    let exit = f.new_block();
    let ret_ty = f.ret;
    let mut exit_insts = vec![Inst {
        op: Op::CallRt,
        args: vec![base],
        imm: Imm::Ext(ext.unwind_to),
        res: Some(f.new_value(Ty::VOID)),
        loc: entry_loc,
    }];
    let ret = if ret_ty == Ty::VOID {
        None
    } else {
        // A borrow-returning function hands back a borrowed zero (`undef 1`).
        let imm = if f.ret_borrowed { Imm::Int(1) } else { Imm::None };
        let (i, v) = inst(f, Op::Undef, vec![], imm, ret_ty, entry_loc);
        exit_insts.push(i);
        Some(v)
    };
    f.blocks[exit.index()].insts = exit_insts;
    f.blocks[exit.index()].term = Term::Ret(ret);
    let at = usize::from(
        f.blocks[0]
            .insts
            .first()
            .is_some_and(|i| i.op == Op::DepthEnter),
    );
    f.blocks[0].insts.insert(at, base_inst);

    // The owned values live at the start of each block. The verifier makes the set the same on
    // every edge into a block, so the first one found stands for all.
    let n = f.blocks.len() - 1;
    let mut entry: Vec<Option<BTreeSet<u32>>> = vec![None; f.blocks.len()];
    let rpo = f.rpo();
    let mut first = BTreeSet::new();
    for p in &f.blocks[0].params {
        if p.mode == Mode::Move && owned(f, p.value) {
            first.insert(p.value.0);
        }
    }
    entry[0] = Some(first);
    for b in rpo {
        let bi = b.index();
        if bi >= n {
            continue;
        }
        let Some(mut live) = entry[bi].clone() else {
            continue;
        };
        if bi != 0 {
            for p in &f.blocks[bi].params {
                if p.mode == Mode::Move && owned(f, p.value) {
                    live.insert(p.value.0);
                }
            }
        }
        let old = std::mem::take(&mut f.blocks[bi].insts);
        let term = f.blocks[bi].term.clone();
        let term_loc = f.blocks[bi].term_loc;
        // The block being filled; a site ends it and continues in a fresh block.
        let mut cur = b;
        let mut buf: Vec<Inst> = Vec::new();
        let count = old.len();
        for (k, i) in old.into_iter().enumerate() {
            let modes = arg_modes(m, &i);
            for (a, mode) in i.args.iter().zip(&modes) {
                if *mode == Mode::Move {
                    live.remove(&a.0);
                }
            }
            let res_owned = m.result_mode(f, &i) == Some(Mode::Move);
            let res = i.res;
            let loc = i.loc;
            let site = parks(m, parks_of, &i) && i.op != Op::Poll;
            buf.push(i);
            if let Some(r) = res
                && res_owned
                && owned(f, r)
            {
                live.insert(r.0);
            }
            if !site || (k + 1 == count && matches!(term, Term::Unreachable)) {
                continue;
            }
            let (ui, u) = inst(
                f,
                Op::CallRt,
                vec![],
                Imm::Ext(ext.unwinding),
                Ty::UINT8,
                loc,
            );
            let (zi, z) = inst(f, Op::IConst, vec![], Imm::Int(0), Ty::UINT8, loc);
            let (ci, c) = inst(f, Op::UICmp, vec![u, z], Imm::Cc(Cc::Ne), Ty::BOOL, loc);
            buf.extend([ui, zi, ci]);
            let leave = f.new_block();
            let next = f.new_block();
            f.blocks[leave.index()].insts = live
                .iter()
                .map(|v| Inst {
                    op: Op::Forget,
                    args: vec![Value(*v)],
                    imm: Imm::None,
                    res: None,
                    loc,
                })
                .collect();
            f.blocks[leave.index()].term = Term::Br(Target::to(exit));
            f.blocks[leave.index()].term_loc = loc;
            f.blocks[cur.index()].insts = std::mem::take(&mut buf);
            f.blocks[cur.index()].term = Term::CondBr {
                cond: c,
                then: Target::to(leave),
                els: Target::to(next),
            };
            f.blocks[cur.index()].term_loc = loc;
            cur = next;
        }
        f.blocks[cur.index()].insts = buf;
        f.blocks[cur.index()].term = term.clone();
        f.blocks[cur.index()].term_loc = term_loc;
        // Edges into other blocks: consumed arguments leave, and the set flows on.
        let mut out = live;
        if let Term::Ret(Some(v)) = &term {
            out.remove(&v.0);
        }
        term.for_each_target(|t| {
            let mut e = out.clone();
            for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                if p.mode == Mode::Move {
                    e.remove(&a.0);
                }
            }
            let ti = t.block.index();
            if ti < entry.len() && entry[ti].is_none() {
                // Parameters the target owns are added when it is visited.
                entry[ti] = Some(e);
            }
        });
    }
    true
}
