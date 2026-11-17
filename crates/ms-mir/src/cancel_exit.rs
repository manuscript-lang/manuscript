//! Explicit cancel exits for Raw functions (`proposals/cancel-cleanup-by-edge.md`, stage 2).
//!
//! `elaborate` calls [`convert`] on a Raw function before it places the scope-exit cleanup. After
//! every call that can park, the function tests the task's `unwinding` byte and leaves through a
//! block built like an early `return`:
//!
//! ```text
//! r = call f(..); u = call.rt msrt_unwinding(); c = ne u, 0; condbr c, leave, next
//! leave: call.rt msrt_unwinding_pause(); forget r; drop <untagged live owners>;
//!        scope.end S_n; ..; scope.end S_1; br tail
//! tail:  call.rt msrt_unwinding_resume(); call.rt msrt_cleanup_truncate(base); %z = undef; ret %z
//! ```
//!
//! `elaborate` then turns the `scope.end` markers into the drops and closes the move state calls
//! for, exactly as on the normal path. The registrations `unwind` adds later stay for faults, so
//! the tail pops them without running them (`msrt_cleanup_truncate`).
//!
//! A function converts only when every owned value live at a park is a scope owner or a value
//! that is plainly droppable (a fresh result or an entry parameter). A value taken from a memory
//! slot or moved out of a field has no such rule yet, nor has a slot handed to a call that can park;
//! those functions keep the hybrid exit.

use crate::cancel_edges::{extern_of, parks};
use crate::ir::*;
use crate::types::Ty;
use crate::verify::arg_modes;
use std::collections::{BTreeSet, HashMap};

/// The runtime entries the exits call.
#[derive(Clone, Copy)]
pub(crate) struct Ext {
    unwinding: ExtId,
    base: ExtId,
    truncate: ExtId,
    pause: ExtId,
    resume: ExtId,
}

pub(crate) fn externs(m: &mut Module) -> Ext {
    let none = ExternRole::None;
    Ext {
        unwinding: extern_of(
            m,
            "msrt_unwinding",
            &[],
            Ty::UINT8,
            true,
            ExternRole::Unwinding,
        ),
        base: extern_of(m, "msrt_cleanup_base", &[], Ty::INT, true, none),
        truncate: extern_of(m, "msrt_cleanup_truncate", &[Ty::INT], Ty::VOID, true, none),
        pause: extern_of(m, "msrt_unwinding_pause", &[], Ty::VOID, true, none),
        resume: extern_of(m, "msrt_unwinding_resume", &[], Ty::VOID, true, none),
    }
}

/// What the conversion reads about the whole module.
pub(crate) struct Cx {
    pub(crate) parks: Vec<bool>,
    pub(crate) ext: Ext,
    /// Per function and parameter: a slot pointer the function only borrows (`unwind`).
    pub(crate) safe: Vec<Vec<bool>>,
}

pub(crate) fn context(m: &mut Module) -> Cx {
    Cx {
        parks: crate::unwind::parking_funcs(m),
        safe: crate::unwind::slot_safe_params(m),
        ext: externs(m),
    }
}

/// A parking call, with what is live and which scopes are open right after it.
struct Site {
    block: usize,
    inst: usize,
    /// The live owned values no open scope will release: the exit drops them itself.
    explicit: Vec<Value>,
    scopes: Vec<i64>,
}

/// What a walk knows at a point: the owned values live, the scopes open, and the values a
/// `scope.disown` took from their scope.
type Walk = (BTreeSet<u32>, Vec<i64>, BTreeSet<u32>);

/// Values a cancel exit can drop without knowing more: fresh results and constructions.
fn droppable(op: Op) -> bool {
    matches!(
        op,
        Op::Call
            | Op::CallRt
            | Op::CallInd
            | Op::CallMethod
            | Op::Clone
            | Op::ListLit
            | Op::AltNew
            | Op::OptSome
            | Op::ClosureNew
            | Op::TypeNew
    )
}

/// The parking calls of `f` in block order, or `None` when a value live at one has no rule.
fn sites(m: &Module, cx: &Cx, f: &Func, tags: &HashMap<Value, (i64, i64)>) -> Option<Vec<Site>> {
    let owned = |v: Value| m.needs_drop(f.ty(v));
    let mut def: HashMap<u32, Op> = HashMap::new();
    for i in f.blocks.iter().flat_map(|b| &b.insts) {
        if let Some(r) = i.res {
            def.insert(r.0, i.op);
        }
    }
    // A callee that takes a part out of a slot and parks leaves the slot with a hole this exit
    // cannot see. A slot handed to a parking callee that only borrows it is fine: the callee
    // leaves the contents in place for the scope end. A slot handed to anything else that can
    // park or keep it (a closure, a derived pointer) keeps the function hybrid.
    let parks_of = &cx.parks[..];
    for i in f.blocks.iter().flat_map(|b| &b.insts) {
        let escapes =
            parks(m, parks_of, i) || matches!(i.op, Op::ClosureNew | Op::PtrField | Op::PtrAdd);
        if !escapes {
            continue;
        }
        for (k, a) in i.args.iter().enumerate() {
            if !tags.get(a).is_some_and(|t| t.1 >= 2) {
                continue;
            }
            let borrowed = match (i.op, i.imm) {
                (Op::Call, Imm::Func(g)) => cx.safe[g.index()].get(k).copied().unwrap_or(false),
                _ => false,
            };
            if !borrowed {
                return None;
            }
        }
    }
    let n = f.blocks.len();
    let mut entry: Vec<Option<Walk>> = vec![None; n];
    let mut first = BTreeSet::new();
    for p in &f.blocks[0].params {
        if p.mode == Mode::Move && owned(p.value) {
            first.insert(p.value.0);
        }
    }
    entry[0] = Some((first, Vec::new(), BTreeSet::new()));
    let mut out = Vec::new();
    for b in f.rpo() {
        let bi = b.index();
        let Some((mut live, mut scopes, mut disowned)) = entry[bi].clone() else {
            continue;
        };
        if bi != 0 {
            for p in &f.blocks[bi].params {
                if p.mode == Mode::Move && owned(p.value) {
                    live.insert(p.value.0);
                    if !tags.contains_key(&p.value) {
                        return None;
                    }
                }
            }
        }
        let count = f.blocks[bi].insts.len();
        for (k, i) in f.blocks[bi].insts.iter().enumerate() {
            let modes = arg_modes(m, i);
            for (a, mode) in i.args.iter().zip(&modes) {
                if *mode == Mode::Move {
                    live.remove(&a.0);
                }
            }
            match (i.op, i.imm) {
                (Op::ScopeBegin, Imm::Scope(s, _)) => scopes.push(i64::from(s)),
                (Op::ScopeEnd, Imm::Scope(s, _)) => scopes.retain(|x| *x != i64::from(s)),
                (Op::ScopeDisown, _) => {
                    disowned.insert(i.args[0].0);
                }
                (Op::ScopeOwn, _) => {
                    disowned.remove(&i.args[0].0);
                }
                _ => {}
            }
            if let Some(r) = i.res
                && m.result_mode(f, i) == Some(Mode::Move)
                && owned(r)
            {
                live.insert(r.0);
            }
            let last_unreachable = k + 1 == count && matches!(f.blocks[bi].term, Term::Unreachable);
            if !parks(m, parks_of, i) || i.op == Op::Poll || last_unreachable {
                continue;
            }
            let mut explicit = Vec::new();
            for v in &live {
                let v = Value(*v);
                if Some(v) == i.res {
                    continue;
                }
                match tags.get(&v) {
                    // A scope owner releases it at the scope end, if that scope is open here.
                    Some((scope, _)) if !disowned.contains(&v.0) => {
                        if !scopes.contains(scope) {
                            return None;
                        }
                        continue;
                    }
                    _ => {}
                }
                let ok = match def.get(&v.0) {
                    Some(op) => droppable(*op),
                    None => f.blocks[0].params.iter().any(|p| p.value == v),
                };
                if !ok {
                    return None;
                }
                explicit.push(v);
            }
            // The result a scope takes right after the call is forgotten here, and that scope
            // still ends so a drop flag it carries sees the value gone.
            let mut open = scopes.clone();
            if let Some(r) = i.res
                && let Some((scope, _)) = tags.get(&r)
                && !open.contains(scope)
            {
                open.push(*scope);
            }
            out.push(Site {
                block: bi,
                inst: k,
                explicit,
                scopes: open,
            });
        }
        let term = &f.blocks[bi].term;
        let mut after = live;
        if let Term::Ret(Some(v)) = term {
            after.remove(&v.0);
        }
        term.for_each_target(|t| {
            let mut e = after.clone();
            for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                if p.mode == Mode::Move {
                    e.remove(&a.0);
                }
            }
            let ti = t.block.index();
            if entry[ti].is_none() {
                entry[ti] = Some((e, scopes.clone(), disowned.clone()));
            }
        });
    }
    Some(out)
}

fn push(
    f: &mut Func,
    op: Op,
    args: Vec<Value>,
    imm: Imm,
    ty: Option<Ty>,
    loc: Loc,
) -> (Inst, Option<Value>) {
    let res = ty.map(|t| f.new_value(t));
    (
        Inst {
            op,
            args,
            imm,
            res,
            loc,
        },
        res,
    )
}

/// Adds the cancel exits to `f`. Returns the leave blocks, empty when `f` stays hybrid. `tagged`
/// maps every value some scope owns to its scope.
pub(crate) fn convert(
    m: &Module,
    cx: &Cx,
    f: &mut Func,
    tags: &HashMap<Value, (i64, i64)>,
) -> Vec<usize> {
    if f.blocks.is_empty() || f.unwind_only {
        return Vec::new();
    }
    let Some(sites) = sites(m, cx, f, tags) else {
        return Vec::new();
    };
    if sites.is_empty() {
        return Vec::new();
    }
    let ext = cx.ext;
    let loc = f.loc;
    let (base_inst, base) = push(
        f,
        Op::CallRt,
        vec![],
        Imm::Ext(ext.base),
        Some(Ty::INT),
        loc,
    );
    let base = base.expect("base");
    let counts_depth = f.blocks[0]
        .insts
        .first()
        .is_some_and(|i| i.op == Op::DepthEnter);
    let at = usize::from(counts_depth);
    f.blocks[0].insts.insert(at, base_inst.clone());
    // Splitting a block moves its tail; the sites are walked from the last so indices hold. The
    // base call shifted block 0 by one.
    let tail = f.new_block();
    let mut insts = vec![
        push(
            f,
            Op::CallRt,
            vec![],
            Imm::Ext(ext.resume),
            Some(Ty::VOID),
            loc,
        )
        .0,
        push(
            f,
            Op::CallRt,
            vec![base],
            Imm::Ext(ext.truncate),
            Some(Ty::VOID),
            loc,
        )
        .0,
    ];
    if counts_depth {
        insts.push(push(f, Op::DepthLeave, vec![], Imm::None, None, loc).0);
    }
    let ret = if f.ret == Ty::VOID {
        None
    } else {
        let imm = if f.ret_borrowed {
            Imm::Int(1)
        } else {
            Imm::None
        };
        let (i, v) = push(f, Op::Undef, vec![], imm, Some(f.ret), loc);
        insts.push(i);
        v
    };
    f.blocks[tail.index()].insts = insts;
    f.blocks[tail.index()].term = Term::Ret(ret);
    let mut leaves = Vec::new();
    for site in sites.into_iter().rev() {
        let bi = site.block;
        let ii = site.inst + usize::from(bi == 0);
        let rest = f.blocks[bi].insts.split_off(ii + 1);
        let term = f.blocks[bi].term.clone();
        let term_loc = f.blocks[bi].term_loc;
        let call = f.blocks[bi].insts[ii].clone();
        let sloc = call.loc;
        let next = f.new_block();
        let leave = f.new_block();
        f.blocks[next.index()].insts = rest;
        f.blocks[next.index()].term = term;
        f.blocks[next.index()].term_loc = term_loc;
        let (ui, u) = push(
            f,
            Op::CallRt,
            vec![],
            Imm::Ext(ext.unwinding),
            Some(Ty::UINT8),
            sloc,
        );
        let (zi, z) = push(f, Op::IConst, vec![], Imm::Int(0), Some(Ty::UINT8), sloc);
        let (ci, c) = push(
            f,
            Op::UICmp,
            vec![u.expect("u"), z.expect("z")],
            Imm::Cc(Cc::Ne),
            Some(Ty::BOOL),
            sloc,
        );
        f.blocks[bi].insts.extend([ui, zi, ci]);
        f.blocks[bi].term = Term::CondBr {
            cond: c.expect("c"),
            then: Target::to(leave),
            els: Target::to(next),
        };
        f.blocks[bi].term_loc = sloc;
        let mut body = vec![
            push(
                f,
                Op::CallRt,
                vec![],
                Imm::Ext(ext.pause),
                Some(Ty::VOID),
                sloc,
            )
            .0,
        ];
        if let Some(r) = call.res
            && m.result_mode(f, &call) == Some(Mode::Move)
            && m.needs_drop(f.ty(r))
        {
            body.push(push(f, Op::Forget, vec![r], Imm::None, None, sloc).0);
        }
        for v in site.explicit.iter().rev() {
            body.push(push(f, Op::Drop, vec![*v], Imm::None, None, sloc).0);
        }
        for s in site.scopes.iter().rev() {
            body.push(
                push(
                    f,
                    Op::ScopeEnd,
                    vec![],
                    Imm::Scope(*s as u32, 0),
                    None,
                    sloc,
                )
                .0,
            );
        }
        f.blocks[leave.index()].insts = body;
        f.blocks[leave.index()].term = Term::Br(Target::to(tail));
        f.blocks[leave.index()].term_loc = sloc;
        leaves.push(leave.index());
    }
    f.explicit_cancel = true;
    leaves
}
