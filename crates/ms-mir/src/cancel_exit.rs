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
use std::collections::{BTreeSet, HashMap, HashSet};

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
    /// Per function: converted (or free of parks), so its cancel exits leave every `var` slot
    /// parameter holding the value the normal exit would. Filled callee first.
    pub(crate) restores: std::cell::RefCell<Vec<bool>>,
}

pub(crate) fn context(m: &mut Module) -> Cx {
    Cx {
        parks: crate::unwind::parking_funcs(m),
        safe: crate::unwind::slot_safe_params(m),
        restores: std::cell::RefCell::new(vec![false; m.funcs.len()]),
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
    /// Slots a `take` emptied whose value is still live: the exit puts it back before the scopes
    /// end, so the owner of the slot (a caller, or a scope) releases it.
    putback: Vec<(Value, Value)>,
    /// Values taken from a `var` slot parameter with a part moved out into a local slot: the exit
    /// takes the part back, fills it in, and puts the whole value back.
    refills: Vec<Refill>,
    /// A `var` slot whose value was moved whole into a local slot: take it back and put it in.
    returns: Vec<(Value, Value, Ty)>,
}

/// A value taken from a slot, with the part it moved out held in another slot.
struct Refill {
    slot: Value,
    whole: Value,
    part_slot: Value,
    part_ty: Ty,
    /// The `type.fill` the normal path runs, copied for the exit.
    fill: Inst,
    whole_ty: Ty,
}

/// What a walk knows at a point: the owned values live, the scopes open, and the values a
/// `scope.disown` took from their scope.
type Walk = (
    BTreeSet<u32>,
    Vec<i64>,
    BTreeSet<u32>,
    BTreeSet<u32>,
    BTreeSet<u32>,
);

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
            | Op::TypeFill
            | Op::OptNoneOwned
            | Op::AltTake
    )
}

/// The parking calls of `f` in block order, or `None` when a value live at one has no rule.
fn sites(m: &Module, cx: &Cx, f: &Func, tags: &HashMap<Value, (i64, i64)>) -> Option<Vec<Site>> {
    let owned = |v: Value| m.needs_drop(f.ty(v));
    let defs: HashMap<u32, &Inst> = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter_map(|i| i.res.map(|r| (r.0, i)))
        .collect();
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
    // A pointer derived from a slot stands for the slot. Deriving one is not an escape: only a
    // parking call or a closure that receives it can take a part out.
    let mut alias: HashSet<u32> = tags
        .iter()
        .filter(|(_, t)| t.1 >= 2)
        .map(|(v, _)| v.0)
        .collect();
    for b in f.rpo() {
        for i in &f.blocks[b.index()].insts {
            if let (Op::PtrField | Op::PtrAdd, Some(r)) = (i.op, i.res)
                && i.args.first().is_some_and(|a| alias.contains(&a.0))
            {
                alias.insert(r.0);
            }
        }
    }
    let shielded = shield_windows(m, f);
    for (bi, ii, i) in f
        .blocks
        .iter()
        .enumerate()
        .flat_map(|(bi, b)| b.insts.iter().enumerate().map(move |(ii, i)| (bi, ii, i)))
    {
        if shielded.contains(&(bi, ii)) || !(parks(m, parks_of, i) || i.op == Op::ClosureNew) {
            continue;
        }
        for (k, a) in i.args.iter().enumerate() {
            if !alias.contains(&a.0) {
                continue;
            }
            let borrowed = match (i.op, i.imm) {
                (Op::Call, Imm::Func(g)) => {
                    tags.contains_key(a)
                        && (cx.safe[g.index()].get(k).copied().unwrap_or(false)
                            // A callee whose cancel exits restore its `var` slots leaves the slot
                            // as its normal exit would.
                            || (m.funcs[g.index()].noalias.contains(&(k as u32))
                                && cx.restores.borrow().get(g.index()).copied().unwrap_or(false)))
                }
                _ => false,
            };
            if !borrowed {
                return None;
            }
        }
    }
    // The value each `take` produced and the slot it came from, and the values some part was
    // moved out of.
    let mut taken: HashMap<u32, Value> = HashMap::new();
    let mut holed: HashSet<u32> = HashSet::new();
    for i in f.blocks.iter().flat_map(|b| &b.insts) {
        match (i.op, i.res) {
            (Op::Take, Some(r)) => {
                taken.insert(r.0, i.args[0]);
            }
            (Op::MoveOut, _) => {
                if let Some(Op::TypeGet) = def.get(&i.args[0].0).copied()
                    && let Some(g) = f
                        .blocks
                        .iter()
                        .flat_map(|b| &b.insts)
                        .find(|g| g.res == Some(i.args[0]))
                {
                    holed.insert(g.args[0].0);
                }
            }
            _ => {}
        }
    }
    // A taken value handed to a block parameter that owns it stays the slot's value.
    let mut moved_on = true;
    while moved_on {
        moved_on = false;
        for blk in &f.blocks {
            blk.term.for_each_target(|t| {
                for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                    if p.mode != Mode::Move {
                        continue;
                    }
                    if let Some(&s) = taken.get(&a.0)
                        && !taken.contains_key(&p.value.0)
                    {
                        taken.insert(p.value.0, s);
                        moved_on = true;
                    }
                    if holed.contains(&a.0) && holed.insert(p.value.0) {
                        moved_on = true;
                    }
                }
            });
        }
    }
    // A taken `var` slot value moved whole into a local slot (handed on to a callee that borrows it
    // or restores it): the slot it came from, by the local slot holding it.
    let mut fwd: HashMap<u32, (Value, Ty)> = HashMap::new();
    for i in f.blocks.iter().flat_map(|b| &b.insts) {
        if i.op == Op::Put
            && let Some(&s) = i.args.get(1).and_then(|v| taken.get(&v.0))
            && var_param(f, s)
            && defs.get(&i.args[0].0).is_some_and(|d| d.op == Op::Slot)
        {
            fwd.insert(s.0, (i.args[0], f.ty(i.args[1])));
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
    entry[0] = Some((
        first,
        Vec::new(),
        BTreeSet::new(),
        BTreeSet::new(),
        BTreeSet::new(),
    ));
    let mut out = Vec::new();
    for b in f.rpo() {
        let bi = b.index();
        let Some((mut live, mut scopes, mut disowned, mut empty, mut full)) = entry[bi].clone()
        else {
            continue;
        };
        if bi != 0 {
            for p in &f.blocks[bi].params {
                if p.mode == Mode::Move && owned(p.value) {
                    live.insert(p.value.0);
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
                (Op::ScopeEnd, Imm::Scope(s, _)) => {
                    scopes.retain(|x| *x != i64::from(s));
                    // The scope released what it owned.
                    live.retain(|v| {
                        disowned.contains(v)
                            || tags.get(&Value(*v)).is_none_or(|t| t.0 != i64::from(s))
                    });
                }
                (Op::ScopeDisown, _) => {
                    disowned.insert(i.args[0].0);
                }
                (Op::ScopeOwn, _) => {
                    disowned.remove(&i.args[0].0);
                }
                (Op::Take, _) => {
                    empty.insert(i.args[0].0);
                    full.remove(&i.args[0].0);
                }
                (Op::Put, _) => {
                    empty.remove(&i.args[0].0);
                    full.insert(i.args[0].0);
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
            if !parks(m, parks_of, i)
                || i.op == Op::Poll
                || last_unreachable
                || shielded.contains(&(bi, k))
            {
                continue;
            }
            let mut explicit = Vec::new();
            let mut putback = Vec::new();
            let mut refills = Vec::new();
            let mut handled: BTreeSet<u32> = BTreeSet::new();
            let mut returns = Vec::new();
            for v in &live {
                let v = Value(*v);
                if Some(v) == i.res {
                    continue;
                }
                // A scope owner releases it at the scope end, if that scope is open here; one that
                // is not is begun by the normal path only at its exits.
                if !disowned.contains(&v.0)
                    && tags
                        .get(&v)
                        .is_some_and(|(scope, _)| scopes.contains(scope))
                {
                    continue;
                }
                // A value taken from a slot a scope owns goes back into it, unless a part was moved
                // out of it (the slot would then hold a hole the scope end drops twice). A slot
                // parameter is not put back: a callee may own what it holds.
                if let Some(&s) = taken.get(&v.0)
                    && empty.contains(&s.0)
                    && (tags.get(&s).is_some_and(|t| scopes.contains(&t.0)) || var_param(f, s))
                {
                    let window = refill_pattern(f, &defs, v);
                    match window {
                        // A part is out in a slot: take it back and fill it in first.
                        Some((w, part_ty, fill))
                            if full.contains(&w.0) && var_param(f, s) && handed_ok(cx, i, w) =>
                        {
                            handled.insert(s.0);
                            refills.push(Refill {
                                slot: s,
                                whole: v,
                                part_slot: w,
                                part_ty,
                                whole_ty: f.ty(v),
                                fill,
                            });
                            continue;
                        }
                        _ if !holed.contains(&v.0) => {
                            handled.insert(s.0);
                            putback.push((s, v));
                            continue;
                        }
                        _ => {}
                    }
                }
                // A value taken from a local slot no scope owns is dropped like any other owner.
                let local = taken.get(&v.0).is_some_and(|s| {
                    def.get(&s.0) == Some(&Op::Slot)
                        && !tags.contains_key(s)
                        && !holed.contains(&v.0)
                });
                let ok = match def.get(&v.0) {
                    Some(op) => droppable(*op) || local,
                    None => f
                        .blocks
                        .iter()
                        .any(|b| b.params.iter().any(|p| p.value == v)),
                };
                if !ok {
                    return None;
                }
                explicit.push(v);
            }
            // A `var` slot parameter the function has taken from must be restored by this exit:
            // only a live taken value (put back or refilled above) can be.
            for s in &empty {
                if !var_param(f, Value(*s)) || handled.contains(s) {
                    continue;
                }
                if let Some((w, ty)) = fwd.get(s)
                    && full.contains(&w.0)
                    && handed_ok(cx, i, *w)
                {
                    handled.insert(*s);
                    returns.push((Value(*s), *w, *ty));
                }
            }
            if empty
                .iter()
                .any(|s| var_param(f, Value(*s)) && !handled.contains(s))
            {
                return None;
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
                putback,
                refills,
                returns,
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
            if let Some(known) = &mut entry[ti] {
                // Only what every path agrees on stays full.
                known.4.retain(|s| full.contains(s));
                known.3.extend(empty.iter().copied());
            } else {
                entry[ti] = Some((
                    e,
                    scopes.clone(),
                    disowned.clone(),
                    empty.clone(),
                    full.clone(),
                ));
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
    fi: usize,
    f: &mut Func,
    tags: &HashMap<Value, (i64, i64)>,
) -> Vec<usize> {
    if f.blocks.is_empty() || f.unwind_only {
        return Vec::new();
    }
    let Some(sites) = sites(m, cx, f, tags) else {
        return Vec::new();
    };
    // A function that parks nowhere, or whose exits are built below, leaves its `var` slots as
    // its normal exit does.
    cx.restores.borrow_mut()[fi] = true;
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
        for (s, w, ty) in &site.returns {
            let (take, held) = push(f, Op::Take, vec![*w], Imm::Ty(*ty), Some(*ty), sloc);
            body.push(take);
            body.push(
                push(
                    f,
                    Op::Put,
                    vec![*s, held.expect("held")],
                    Imm::None,
                    None,
                    sloc,
                )
                .0,
            );
        }
        for r in &site.refills {
            let (take, part) = push(
                f,
                Op::Take,
                vec![r.part_slot],
                Imm::Ty(r.part_ty),
                Some(r.part_ty),
                sloc,
            );
            let mut fill = r.fill.clone();
            fill.args = vec![r.whole, part.expect("part")];
            fill.res = Some(f.new_value(r.whole_ty));
            let whole = fill.res.expect("whole");
            body.push(take);
            body.push(fill);
            body.push(push(f, Op::Put, vec![r.slot, whole], Imm::None, None, sloc).0);
        }
        for (s, v) in &site.putback {
            body.push(push(f, Op::Put, vec![*s, *v], Imm::None, None, sloc).0);
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

/// Whether `s` is a `var` slot parameter of `f`: the function takes its value out and puts the final
/// value back by its normal exit.
fn var_param(f: &Func, s: Value) -> bool {
    f.blocks[0]
        .params
        .iter()
        .position(|p| p.value == s)
        .is_some_and(|k| f.noalias.contains(&(k as u32)))
}

/// The one window a taken value `v` opens: a part moved out into a local slot, taken back and filled
/// in by a single `type.fill` before the value goes back. Returns that slot, the part's type, and the
/// fill. `None` when `v` has no such window.
fn refill_pattern(f: &Func, defs: &HashMap<u32, &Inst>, v: Value) -> Option<(Value, Ty, Inst)> {
    let insts = || f.blocks.iter().flat_map(|b| &b.insts);
    let moved_from_v = |i: &&Inst| {
        i.op == Op::MoveOut
            && defs
                .get(&i.args[0].0)
                .is_some_and(|g| g.op == Op::TypeGet && g.args[0] == v)
    };
    let mut moves = insts().filter(moved_from_v);
    let moved = moves.next()?;
    if moves.next().is_some() {
        return None;
    }
    let mut fills = insts().filter(|i| i.op == Op::TypeFill && i.args[0] == v);
    let fill = fills.next()?;
    if fills.next().is_some() {
        return None;
    }
    // The part goes into one slot and comes back out of it.
    let mut puts = insts().filter(|i| i.op == Op::Put && i.args.get(1) == moved.res.as_ref());
    let put = puts.next()?;
    if puts.next().is_some() {
        return None;
    }
    let w = put.args[0];
    let back = defs.get(&fill.args[1].0)?;
    (back.op == Op::Take && back.args[0] == w).then(|| (w, f.ty(fill.args[1]), (*fill).clone()))
}

/// Whether the parking call `i` leaves slot `w` as its normal return would: it is not handed to the
/// call, or the callee is a function whose cancel exits restore its `var` slots.
fn handed_ok(cx: &Cx, i: &Inst, w: Value) -> bool {
    if !i.args.contains(&w) {
        return true;
    }
    match (i.op, i.imm) {
        (Op::Call, Imm::Func(g)) => cx
            .restores
            .borrow()
            .get(g.index())
            .copied()
            .unwrap_or(false),
        _ => false,
    }
}

/// The functions in the order their conversion should run: a callee before its callers (a cycle is
/// cut where it is first met), so `Cx::restores` is known when a caller asks. Natural order when no
/// cancel exits are built.
pub(crate) fn callee_first(m: &Module, wanted: bool) -> Vec<usize> {
    let n = m.funcs.len();
    if !wanted {
        return (0..n).collect();
    }
    let calls: Vec<Vec<usize>> = m
        .funcs
        .iter()
        .map(|f| {
            f.blocks
                .iter()
                .flat_map(|b| &b.insts)
                .filter_map(|i| match (i.op, i.imm) {
                    (Op::Call, Imm::Func(g)) => Some(g.index()),
                    _ => None,
                })
                .collect()
        })
        .collect();
    let mut order = Vec::with_capacity(n);
    let mut state = vec![0u8; n];
    for root in 0..n {
        if state[root] != 0 {
            continue;
        }
        let mut stack = vec![(root, 0usize)];
        state[root] = 1;
        while let Some((fi, ci)) = stack.pop() {
            let callees = &calls[fi];
            if ci < callees.len() {
                stack.push((fi, ci + 1));
                let g = callees[ci];
                if state[g] == 0 {
                    state[g] = 1;
                    stack.push((g, 0));
                }
            } else {
                state[fi] = 2;
                order.push(fi);
            }
        }
    }
    order
}

/// The instructions between a shield enter and its exit in one block: cancellation is held back
/// there, so a call inside is no cancel point.
fn shield_windows(m: &Module, f: &Func) -> HashSet<(usize, usize)> {
    let role = |i: &Inst| match (i.op, i.imm) {
        (Op::CallRt, Imm::Ext(e)) => Some(m.externs[e.index()].role),
        _ => None,
    };
    let mut out = HashSet::new();
    for (bi, b) in f.blocks.iter().enumerate() {
        let mut depth = 0u32;
        for (ii, i) in b.insts.iter().enumerate() {
            match role(i) {
                Some(ExternRole::ShieldEnter) => depth += 1,
                Some(ExternRole::ShieldExit) => depth = depth.saturating_sub(1),
                _ if depth > 0 => {
                    out.insert((bi, ii));
                }
                _ => {}
            }
        }
    }
    out
}
