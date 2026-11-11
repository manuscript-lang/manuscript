//! Stage 0 prototype of drop elaboration (`proposals/elaborate-drops.md`): places the
//! scope-exit cleanup of a *Raw* function, one that leaves every owned value of a scope to the
//! markers below instead of dropping it.
//!
//! Markers are real ops (`Op::ScopeBegin`, `ScopeOwn`, `ScopeEnd`, `ScopeDisown`), present only in
//! Raw functions (`verify::is_raw`):
//!
//! * `scope.begin S P`: opens scope `S`, nested in `P - 1` (`P` is 0 for the root).
//! * `scope.own S K v`: the owned `v` belongs to `S`; `K` 0 drops it, 1 closes it with the
//!   module's `close` function (`fn(move T) -> int`, nonzero is an error).
//! * `scope.disown v`: `v` left its owner without an op that consumes it (a view moving into the
//!   result); the pass stops tracking it on this path.
//! * `scope.end S`: the point where `S`'s cleanup runs, on the fallthrough end and on every early
//!   exit that leaves it.
//!
//! At each `scope.end` the pass drops the owned values of the scope that are still live, in
//! reverse definition order. Because the live set follows the consuming operands, a value an
//! earlier path moved or closed is simply absent: nothing remembers "already dropped on this
//! path". A failing close (first error wins) leaves through an error edge the pass builds: it
//! cleans up the enclosing scopes, drops what else is live (a pending return value), and returns
//! the first error. The markers are removed.
//!
//! Beyond that, the pass computes a move state per owner by dataflow over the whole function
//! (loops included): `Live`, `Moved`, `Maybe` (moved on some paths into a join) or `Part` (an
//! alternative with payload fields taken). A `Maybe` owner gets a drop flag: every consuming use
//! becomes `move.out` of the owner, which stays live for the verifier, and the flag (a boolean
//! block parameter threaded through the blocks) decides at the scope end whether to drop or
//! close it. A `Part` owner is released with `alt.release` naming the taken fields. A `Close`
//! owner registers `cleanup.push` at `raw_own` and discards the entry at its close or move.
//!
//! Not expressible: owners that are partially moved on only some paths into a join, a partially
//! moved `Close` owner, and a flagged owner returned directly; each is an error.

use crate::ir::*;
use crate::types::{AltId, Std, Ty};
use crate::verify::{arg_modes, is_raw};
use std::collections::{HashMap, HashSet};

const DISCARD: &str = "msrt_cleanup_discard";
const SHIELD_ENTER: &str = "msrt_shield_enter";
const SHIELD_EXIT: &str = "msrt_shield_exit";

/// The runtime function `name`, declared if the module does not have it yet.
fn runtime(m: &mut Module, name: &str, params: &[Ty], role: ExternRole) -> ExtId {
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
        ret: Ty::UNIT,
        noreturn: false,
        pure_: false,
        fresh: false,
        role,
        leaf: true,
        reads: false,
    })
}

#[derive(Clone, Copy, PartialEq)]
enum Marker {
    Begin,
    Own,
    End,
}

/// Elaborates every Raw function of `m`.
pub fn run(m: &mut Module) -> Result<(), String> {
    let close = m
        .funcs
        .iter()
        .position(|f| f.name == "close")
        .map(|i| FuncId(i as u32));
    if !m.funcs.iter().any(is_raw) {
        return Ok(());
    }
    let closes = m.funcs.iter().filter(|f| is_raw(f)).any(|f| {
        f.blocks
            .iter()
            .flat_map(|b| &b.insts)
            .any(|i| matches!((i.op, i.imm), (Op::ScopeOwn, Imm::Scope(_, k)) if k >= 1))
    });
    let discard = closes.then(|| runtime(m, DISCARD, &[Ty::INT], ExternRole::CleanupDiscard));
    let shield = closes.then(|| {
        (
            runtime(m, SHIELD_ENTER, &[], ExternRole::None),
            runtime(m, SHIELD_EXIT, &[], ExternRole::None),
        )
    });
    for fi in 0..m.funcs.len() {
        if !is_raw(&m.funcs[fi]) {
            continue;
        }
        let stand_in = Func::new("", Vec::new(), Ty::UNIT);
        let mut f = std::mem::replace(&mut m.funcs[fi], stand_in);
        let out = function(m, &mut f, close, discard, shield);
        m.funcs[fi] = f;
        out.map_err(|e| format!("{}: {e}", m.funcs[fi].name))?;
    }
    // The helper references are consumed: later passes renumber functions.
    for f in &mut m.funcs {
        f.slot_result = None;
        f.close_exit = None;
    }
    Ok(())
}

/// The move state of an owner.
#[derive(Clone, Copy, PartialEq, Debug)]
enum St {
    Live,
    Moved,
    /// Moved on some paths into a join: the owner carries a drop flag.
    Maybe,
    /// An alternative whose payload fields in the mask (of the case) were taken out.
    Part(AltId, u32, u32),
}

/// The owners in scope, in definition order. Untagged values are tracked while live only.
#[derive(Clone, Default)]
struct State {
    seq: std::collections::BTreeMap<u32, (Value, St)>,
    at: HashMap<Value, u32>,
    next: u32,
}

impl PartialEq for State {
    fn eq(&self, other: &State) -> bool {
        self.seq.len() == other.seq.len() && self.iter().eq(other.iter())
    }
}

impl State {
    fn push(&mut self, v: Value, s: St) {
        self.at.insert(v, self.next);
        self.seq.insert(self.next, (v, s));
        self.next += 1;
    }

    fn get(&self, v: Value) -> Option<St> {
        self.at.get(&v).map(|n| self.seq[n].1)
    }

    fn set(&mut self, v: Value, s: St) {
        if let Some(n) = self.at.get(&v) {
            self.seq.get_mut(n).expect("owner").1 = s;
        }
    }

    fn remove(&mut self, v: Value) {
        if let Some(n) = self.at.remove(&v) {
            self.seq.remove(&n);
        }
    }

    fn retain(&mut self, mut keep: impl FnMut(&(Value, St)) -> bool) {
        let gone: Vec<Value> = self
            .seq
            .values()
            .filter(|e| !keep(e))
            .map(|e| e.0)
            .collect();
        for v in gone {
            self.remove(v);
        }
    }

    /// Definition order.
    fn iter(&self) -> impl DoubleEndedIterator<Item = &(Value, St)> {
        self.seq.values()
    }
}

struct Ctx {
    /// Owner value to `(scope, kind)`.
    tags: HashMap<Value, (i64, i64)>,
    /// The owners of each scope.
    owners: HashMap<i64, Vec<Value>>,
    parents: HashMap<i64, i64>,
    close: Option<FuncId>,
    discard: Option<ExtId>,
    shield: Option<(ExtId, ExtId)>,
}

fn marker_of(inst: &Inst) -> Option<Marker> {
    match inst.op {
        Op::ScopeBegin => Some(Marker::Begin),
        Op::ScopeOwn => Some(Marker::Own),
        Op::ScopeEnd => Some(Marker::End),
        _ => None,
    }
}

/// The scope number a marker names.
fn scope_of(inst: &Inst) -> i64 {
    match inst.imm {
        Imm::Scope(s, _) => i64::from(s),
        _ => unreachable!("the verifier checks scope markers carry scope numbers"),
    }
}

fn own_params(m: &Module, f: &Func, b: usize) -> Vec<Value> {
    f.blocks[b]
        .params
        .iter()
        .filter(|p| p.mode == Mode::Move && m.needs_drop(f.ty(p.value)))
        .map(|p| p.value)
        .collect()
}

fn consume_value(cx: &Ctx, st: &mut State, v: Value) -> Result<(), String> {
    let Some(state) = st.get(v) else {
        return Ok(());
    };
    match state {
        St::Live if cx.tags.contains_key(&v) => st.set(v, St::Moved),
        St::Live => st.remove(v),
        St::Moved => return Err(format!("%{} is consumed after it was moved", v.0)),
        St::Maybe => return Err(format!("%{} is consumed but moved on some path", v.0)),
        St::Part(..) => return Err(format!("%{} is consumed after a partial move", v.0)),
    }
    Ok(())
}

fn consume_args(
    m: &Module,
    f: &Func,
    cx: &Ctx,
    st: &mut State,
    args: &[Value],
    modes: &[Mode],
) -> Result<(), String> {
    for (a, mode) in args.iter().zip(modes) {
        if *mode == Mode::Move && m.needs_drop(f.ty(*a)) {
            consume_value(cx, st, *a)?;
        }
    }
    Ok(())
}

/// The move state after `inst`.
fn apply(m: &Module, f: &Func, cx: &Ctx, st: &mut State, inst: &Inst) -> Result<(), String> {
    if inst.op == Op::ScopeDisown {
        st.remove(inst.args[0]);
        return Ok(());
    }
    // A disowned view that moves into another local is owned again by that local's scope.
    if inst.op == Op::ScopeOwn {
        if st.get(inst.args[0]).is_none() {
            st.push(inst.args[0], St::Live);
        }
        return Ok(());
    }
    if marker_of(inst) == Some(Marker::End) {
        let scope = scope_of(inst);
        st.retain(|(v, _)| cx.tags.get(v).is_none_or(|t| t.0 != scope));
        return Ok(());
    }
    // Lowering releases what an `alt.take` left behind itself: that finishes the owner.
    if inst.op == Op::AltRelease
        && let Some(St::Part(..)) = st.get(inst.args[0])
    {
        match cx.tags.contains_key(&inst.args[0]) {
            true => st.set(inst.args[0], St::Moved),
            false => st.remove(inst.args[0]),
        }
        return Ok(());
    }
    consume_args(m, f, cx, st, &inst.args, &arg_modes(m, inst))?;
    if let (Op::AltTake, Imm::AltField(a, c, i)) = (inst.op, inst.imm)
        && let Some(cur) = st.get(inst.args[0])
        && cx.tags.contains_key(&inst.args[0])
    {
        let bit = 1u32 << i;
        let next = match cur {
            St::Live => St::Part(a, c, bit),
            St::Part(pa, pc, mask) if (pa, pc) == (a, c) => St::Part(a, c, mask | bit),
            _ => {
                return Err(format!(
                    "alt.take on %{} in an unsupported state",
                    inst.args[0].0
                ));
            }
        };
        st.set(inst.args[0], next);
    }
    if m.result_mode(f, inst) == Some(Mode::Move)
        && let Some(r) = inst.res
    {
        st.push(r, St::Live);
    }
    Ok(())
}

/// The state flowing along the edge `t`: the arguments of owning parameters are consumed.
fn edge_state(m: &Module, f: &Func, cx: &Ctx, st: &State, t: &Target) -> Result<State, String> {
    let mut out = st.clone();
    for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
        if p.mode == Mode::Move && m.needs_drop(f.ty(*a)) {
            consume_value(cx, &mut out, *a)?;
        }
    }
    Ok(out)
}

fn merge(old: &State, new: &State) -> Result<State, String> {
    let mut out = State::default();
    for (v, a) in old.iter() {
        let Some(b) = new.get(*v) else {
            continue;
        };
        out.push(
            *v,
            match (a, &b) {
                _ if *a == b => *a,
                (St::Part(..), _) | (_, St::Part(..)) => {
                    return Err(format!("%{} is partially moved on only some paths", v.0));
                }
                _ => St::Maybe,
            },
        );
    }
    Ok(out)
}

fn function(
    m: &Module,
    f: &mut Func,
    close: Option<FuncId>,
    discard: Option<ExtId>,
    shield: Option<(ExtId, ExtId)>,
) -> Result<(), String> {
    let mut cx = Ctx {
        tags: HashMap::new(),
        owners: HashMap::new(),
        parents: HashMap::new(),
        close,
        discard,
        shield,
    };
    for b in &f.blocks {
        for i in &b.insts {
            match (i.op, i.imm) {
                (Op::ScopeBegin, Imm::Scope(s, parent)) => {
                    cx.parents.insert(i64::from(s), i64::from(parent) - 1);
                }
                (Op::ScopeOwn, Imm::Scope(s, kind)) => {
                    // A value owned again by a later scope leaves the earlier scope's list.
                    if let Some((old, _)) =
                        cx.tags.insert(i.args[0], (i64::from(s), i64::from(kind)))
                        && let Some(list) = cx.owners.get_mut(&old)
                    {
                        list.retain(|v| *v != i.args[0]);
                    }
                    cx.owners.entry(i64::from(s)).or_default().push(i.args[0]);
                }
                _ => {}
            }
        }
    }
    // A value that flows through a moving block parameter keeps its scope.
    loop {
        let mut changed = false;
        for b in &f.blocks {
            b.term.for_each_target(|t| {
                for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                    // A disowned value left its scope: the parameter it feeds is the new owner's.
                    let disowned = b
                        .insts
                        .iter()
                        .any(|i| i.op == Op::ScopeDisown && i.args[0] == *a);
                    if p.mode == Mode::Move
                        && !disowned
                        && let Some(tag) = cx.tags.get(a).copied()
                        && cx.tags.insert(p.value, tag).is_none()
                    {
                        cx.owners.entry(tag.0).or_default().push(p.value);
                        changed = true;
                    }
                }
            });
        }
        if !changed {
            break;
        }
    }
    let order = f.rpo();
    let entry = analyze(m, f, &cx, &order)?;
    let flagged: HashSet<Value> = entry
        .iter()
        .flatten()
        .flat_map(|s| s.iter().filter(|(_, t)| *t == St::Maybe).map(|(v, _)| *v))
        .collect();
    // The flag parameters of every block: one per flagged owner that is live on entry.
    let mut fparams: Vec<Vec<(Value, Value)>> = vec![Vec::new(); f.blocks.len()];
    for b in &order {
        let Some(e) = &entry[b.index()] else { continue };
        for (v, _) in e.iter().filter(|(v, _)| flagged.contains(v)) {
            let p = f.new_value(Ty::BOOL);
            f.blocks[b.index()].params.push(BlockParam {
                value: p,
                mode: Mode::Borrow,
            });
            fparams[b.index()].push((*v, p));
        }
    }
    let mut em = Em {
        m,
        f,
        cx: &cx,
        flagged,
        flags: HashMap::new(),
        handles: HashMap::new(),
        pending: None,
    };
    for b in order {
        let Some(e) = entry[b.index()].clone() else {
            continue;
        };
        em.block(b.index(), e, &fparams)?;
    }
    Ok(())
}

/// The move state on entry to every reachable block, to a fixpoint (loops included).
fn analyze(m: &Module, f: &Func, cx: &Ctx, order: &[Block]) -> Result<Vec<Option<State>>, String> {
    let mut entry: Vec<Option<State>> = vec![None; f.blocks.len()];
    entry[0] = Some(State::default());
    for _ in 0..=(4 * f.blocks.len() + 4) {
        let mut changed = false;
        for b in order {
            let Some(mut st) = entry[b.index()].clone() else {
                continue;
            };
            for p in own_params(m, f, b.index()) {
                st.push(p, St::Live);
            }
            for inst in &f.blocks[b.index()].insts {
                apply(m, f, cx, &mut st, inst)?;
            }
            if let Term::Ret(Some(v)) = &f.blocks[b.index()].term {
                consume_value(cx, &mut st, *v)?;
            }
            let mut err = None;
            f.blocks[b.index()].term.for_each_target(|t| {
                if err.is_some() {
                    return;
                }
                let next = match edge_state(m, f, cx, &st, t) {
                    Ok(s) => s,
                    Err(e) => return err = Some(e),
                };
                let slot = &mut entry[t.block.index()];
                let merged = match slot {
                    None => next,
                    Some(old) => match merge(old, &next) {
                        Ok(s) => s,
                        Err(e) => return err = Some(e),
                    },
                };
                if slot.as_ref() != Some(&merged) {
                    *slot = Some(merged);
                    changed = true;
                }
            });
            if let Some(e) = err {
                return Err(e);
            }
        }
        if !changed {
            return Ok(entry);
        }
    }
    Err("the move state did not reach a fixpoint".into())
}

/// The emission state of one function.
struct Em<'a> {
    m: &'a Module,
    f: &'a mut Func,
    cx: &'a Ctx,
    /// Owners that carry a drop flag.
    flagged: HashSet<Value>,
    /// The current flag value of each flagged owner (reset per block).
    flags: HashMap<Value, Value>,
    /// The `cleanup.push` handle of each closing owner.
    handles: HashMap<Value, Value>,
    /// The value the block being rebuilt returns, still to be returned after its scope ends.
    pending: Option<Value>,
}

impl Em<'_> {
    fn push(
        &mut self,
        at: usize,
        op: Op,
        args: &[Value],
        imm: Imm,
        ty: Option<Ty>,
    ) -> Option<Value> {
        let res = ty.map(|t| self.f.new_value(t));
        self.f.blocks[at].insts.push(Inst {
            op,
            args: args.to_vec(),
            imm,
            res,
            loc: Loc::NONE,
        });
        res
    }

    fn bconst(&mut self, at: usize, b: bool) -> Value {
        self.push(at, Op::BConst, &[], Imm::Bool(b), Some(Ty::BOOL))
            .expect("flag")
    }

    fn discard(&mut self, at: usize, v: Value) {
        if let (Some(h), Some(d)) = (self.handles.get(&v).copied(), self.cx.discard) {
            self.push(at, Op::CallRt, &[h], Imm::Ext(d), Some(Ty::UNIT));
        }
    }

    /// Emits one block from its entry state; the rest of the function follows from it.
    fn block(
        &mut self,
        b: usize,
        entry: State,
        fparams: &[Vec<(Value, Value)>],
    ) -> Result<(), String> {
        let old = std::mem::take(&mut self.f.blocks[b]);
        self.f.blocks[b].params = old.params;
        self.flags = fparams[b].iter().copied().collect();
        self.pending = match &old.term {
            Term::Ret(Some(v)) => Some(*v),
            _ => None,
        };
        let mut st = entry;
        let mut cur = b;
        for p in own_params(self.m, self.f, b) {
            st.push(p, St::Live);
            self.birth(cur, p);
        }
        for mut inst in old.insts {
            if inst.op == Op::ScopeDisown {
                apply(self.m, self.f, self.cx, &mut st, &inst)?;
                continue;
            }
            match marker_of(&inst) {
                Some(Marker::Begin) => continue,
                Some(Marker::Own) => {
                    let v = inst.args[0];
                    apply(self.m, self.f, self.cx, &mut st, &inst)?;
                    if self.cx.tags[&v].1 >= 1 {
                        self.register(cur, v)?;
                    }
                    continue;
                }
                Some(Marker::End) => {
                    let scope = scope_of(&inst);
                    cur = self.exit(cur, &mut st, scope)?;
                    continue;
                }
                None => {}
            }
            let modes = arg_modes(self.m, &inst);
            for (a, mode) in inst.args.iter_mut().zip(&modes) {
                if *mode == Mode::Move && self.m.needs_drop(self.f.ty(*a)) {
                    *a = self.move_arg(cur, *a);
                }
            }
            apply(self.m, self.f, self.cx, &mut st, &inst).map_err(|e| e.to_string())?;
            let res = inst.res.filter(|r| {
                self.m.result_mode(self.f, &inst) == Some(Mode::Move)
                    && self.m.needs_drop(self.f.ty(*r))
            });
            self.f.blocks[cur].insts.push(inst);
            if let Some(r) = res {
                self.birth(cur, r);
            }
        }
        if let Term::Ret(Some(v)) = &old.term {
            if self.flagged.contains(v) {
                return Err("a drop-flagged owner is returned directly".into());
            }
            self.discard(cur, *v);
        }
        let mut term = old.term;
        let mut err = None;
        let mut fresh: Vec<(Block, Vec<Inst>)> = Vec::new();
        // Each edge: the consumed owners retire their cleanup entry and the flags follow.
        term.for_each_target_mut(|t| {
            if err.is_some() {
                return;
            }
            match self.edge(cur, t, fparams) {
                Ok((extra, args)) => {
                    if let Some(insts) = extra {
                        let tramp = self.f.new_block();
                        fresh.push((tramp, insts));
                        let dest = t.block;
                        t.block = tramp;
                        t.args.clear();
                        self.f.blocks[tramp.index()].term = Term::Br(Target { block: dest, args });
                    } else {
                        t.args = args;
                    }
                }
                Err(e) => err = Some(e),
            }
        });
        if let Some(e) = err {
            return Err(e);
        }
        for (tramp, insts) in fresh {
            self.f.blocks[tramp.index()].insts = insts;
        }
        self.f.blocks[cur].term = term;
        self.f.blocks[cur].term_loc = old.term_loc;
        Ok(())
    }

    /// Initializes the flag of a new flagged owner.
    fn birth(&mut self, at: usize, v: Value) {
        if self.flagged.contains(&v) {
            let t = self.bconst(at, true);
            self.flags.insert(v, t);
        }
        if self.cx.tags.get(&v).is_some_and(|t| t.1 >= 1) && !self.handles.contains_key(&v) {
            // A closing owner that arrives as a parameter registers where it is defined.
            if self
                .f
                .blocks
                .iter()
                .any(|b| b.params.iter().any(|p| p.value == v))
            {
                let _ = self.register(at, v);
            }
        }
    }

    fn register(&mut self, at: usize, v: Value) -> Result<(), String> {
        let close = self.closer(v)?;
        let h = self
            .push(at, Op::CleanupPush, &[v], Imm::Func(close), Some(Ty::INT))
            .expect("handle");
        self.handles.insert(v, h);
        Ok(())
    }

    /// The operand for a consuming position: a flagged owner stays live and its operand is a
    /// `move.out` of it; the flag turns false. A closing owner retires its cleanup entry.
    fn move_arg(&mut self, at: usize, a: Value) -> Value {
        self.discard(at, a);
        if !self.flagged.contains(&a) {
            return a;
        }
        let ty = self.f.ty(a);
        let w = self
            .push(at, Op::MoveOut, &[a], Imm::None, Some(ty))
            .expect("moved");
        let off = self.bconst(at, false);
        self.flags.insert(a, off);
        w
    }

    /// The target for one edge: the flag arguments for the destination and, when the edge moves
    /// owners that need per-edge instructions, a trampoline body.
    fn edge(
        &mut self,
        cur: usize,
        t: &Target,
        fparams: &[Vec<(Value, Value)>],
    ) -> Result<(Option<Vec<Inst>>, Vec<Value>), String> {
        let m = self.m;
        let dest = t.block.index();
        let params: Vec<BlockParam> = self.f.blocks[dest]
            .params
            .iter()
            .filter(|p| !fparams[dest].iter().any(|(_, fp)| *fp == p.value))
            .copied()
            .collect();
        let mut args = t.args.clone();
        let mut sink = Vec::new();
        let mut moved: Vec<Value> = Vec::new();
        let mut per_edge = false;
        for (a, p) in args.iter_mut().zip(&params) {
            if p.mode == Mode::Move && m.needs_drop(self.f.ty(*a)) {
                moved.push(*a);
                let closing = self.handles.contains_key(a);
                if closing || self.flagged.contains(a) {
                    per_edge = true;
                }
            }
        }
        let target_cur = if per_edge { self.f.blocks.len() } else { cur };
        if per_edge {
            // Build the trampoline body in a scratch block so the instructions land in order.
            self.f.blocks.push(BlockData::new());
        }
        let at = target_cur;
        for (a, p) in args.iter_mut().zip(&params) {
            if p.mode == Mode::Move && m.needs_drop(self.f.ty(*a)) {
                *a = self.move_arg(at, *a);
            }
        }
        for (owner, _) in &fparams[dest] {
            let flag = if moved.contains(owner) && self.flagged.contains(owner) {
                self.bconst(at, false)
            } else {
                *self
                    .flags
                    .get(owner)
                    .ok_or_else(|| format!("no drop flag for %{}", owner.0))?
            };
            sink.push(flag);
        }
        args.extend(sink);
        if per_edge {
            let scratch = self.f.blocks.pop().expect("scratch");
            Ok((Some(scratch.insts), args))
        } else {
            Ok((None, args))
        }
    }

    /// Cleans up one owner, `st` already says its state. Returns the close result, if any, and
    /// the block to continue in.
    fn cleanup_one(
        &mut self,
        mut at: usize,
        v: Value,
        s: St,
        outcome: Option<Value>,
    ) -> Result<(usize, Option<Value>), String> {
        let kind = self.cx.tags[&v].1;
        let flag = self.flags.get(&v).copied();
        if kind >= 2 {
            if self.f.ty(v) == Ty::PTR
                && let Some(rc) = self.m.funcs[self.closer(v)?.index()].slot_result
            {
                return self.cleanup_fallible(at, v, s, rc, outcome);
            }
            return Ok((self.cleanup_infallible(at, v, s, flag)?, outcome));
        }
        let code = match (s, kind) {
            (St::Live, 0) => {
                self.push(at, Op::Drop, &[v], Imm::None, None);
                None
            }
            (St::Part(a, c, mask), 0) => {
                self.push(at, Op::AltRelease, &[v], Imm::AltMask(a, c, mask), None);
                None
            }
            (St::Part(..), _) => return Err("a partially moved closing owner".into()),
            (St::Moved | St::Maybe, 0) => {
                let flag = flag.ok_or("a moved owner without a drop flag")?;
                self.push(at, Op::DropIf, &[flag, v], Imm::None, None);
                None
            }
            (St::Live, _) => {
                self.discard(at, v);
                Some(self.close_call(at, v)?)
            }
            (St::Moved, _) => {
                let flag = flag.ok_or("a moved owner without a drop flag")?;
                self.push(at, Op::DropIf, &[flag, v], Imm::None, None);
                None
            }
            (St::Maybe, _) => {
                let flag = flag.ok_or("a moved owner without a drop flag")?;
                let (yes, no, join) = (self.f.new_block(), self.f.new_block(), self.f.new_block());
                self.f.blocks[at].term = Term::CondBr {
                    cond: flag,
                    then: Target::to(yes),
                    els: Target::to(no),
                };
                self.discard(yes.index(), v);
                let c = self.close_call(yes.index(), v)?;
                self.f.blocks[yes.index()].term = Term::Br(Target {
                    block: join,
                    args: vec![c],
                });
                self.push(no.index(), Op::DropIf, &[flag, v], Imm::None, None);
                let z = self
                    .push(no.index(), Op::IConst, &[], Imm::Int(0), Some(Ty::INT))
                    .expect("zero");
                self.f.blocks[no.index()].term = Term::Br(Target {
                    block: join,
                    args: vec![z],
                });
                let p = self.f.new_value(Ty::INT);
                self.f.blocks[join.index()].params.push(BlockParam {
                    value: p,
                    mode: Mode::Borrow,
                });
                at = join.index();
                Some(p)
            }
        };
        let Some(code) = code else {
            return Ok((at, outcome));
        };
        let outcome = match outcome {
            None => code,
            Some(first) => {
                let zero = self
                    .push(at, Op::IConst, &[], Imm::Int(0), Some(Ty::INT))
                    .expect("zero");
                let failed = self
                    .push(
                        at,
                        Op::ICmp,
                        &[first, zero],
                        Imm::Cc(Cc::Ne),
                        Some(Ty::BOOL),
                    )
                    .expect("flag");
                self.push(
                    at,
                    Op::Select,
                    &[failed, first, code],
                    Imm::None,
                    Some(Ty::INT),
                )
                .expect("pick")
            }
        };
        Ok((at, Some(outcome)))
    }

    /// The function that closes `v`: the module's `close` for kind 1 (it returns the failure
    /// code), else the owner's own function, `fn(borrow T) -> unit`, named by kind - 2.
    fn closer(&self, v: Value) -> Result<FuncId, String> {
        match self.cx.tags[&v].1 {
            1 => self
                .cx
                .close
                .ok_or_else(|| "a closing owner needs a `close` function".to_string()),
            k => Ok(FuncId((k - 2) as u32)),
        }
    }

    /// Cleans up an owner whose close cannot fail: it closes only on the paths that still hold
    /// it. Returns the block to continue in.
    fn cleanup_infallible(
        &mut self,
        at: usize,
        v: Value,
        s: St,
        flag: Option<Value>,
    ) -> Result<usize, String> {
        match s {
            St::Live => {
                self.close_infallible(at, v)?;
                if self.f.ty(v) != Ty::PTR {
                    self.push(at, Op::Drop, &[v], Imm::None, None);
                    return Ok(at);
                }
                // A memory slot owner holds its value in memory, and its close function (an
                // in-slot cleanup entry, `slot_close`) takes the address: what the close leaves
                // in the slot is taken out and dropped.
                let close = self.closer(v)?;
                if let Some(ty) = self.m.funcs[close.index()].slot_close {
                    let left = self
                        .push(at, Op::Take, &[v], Imm::Ty(ty), Some(ty))
                        .expect("taken");
                    self.push(at, Op::Drop, &[left], Imm::None, None);
                }
                Ok(at)
            }
            St::Part(..) => Err("a partially moved closing owner".into()),
            St::Moved | St::Maybe if self.f.ty(v) == Ty::PTR => {
                Err("a memory slot owner that is moved out of".into())
            }
            St::Moved => {
                let flag = flag.ok_or("a moved owner without a drop flag")?;
                self.push(at, Op::DropIf, &[flag, v], Imm::None, None);
                Ok(at)
            }
            St::Maybe => {
                let flag = flag.ok_or("a moved owner without a drop flag")?;
                let (yes, join) = (self.f.new_block(), self.f.new_block());
                self.f.blocks[at].term = Term::CondBr {
                    cond: flag,
                    then: Target::to(yes),
                    els: Target::to(join),
                };
                self.close_infallible(yes.index(), v)?;
                self.f.blocks[yes.index()].term = Term::Br(Target::to(join));
                self.push(join.index(), Op::DropIf, &[flag, v], Imm::None, None);
                Ok(join.index())
            }
        }
    }

    /// Cleans up a memory-slot owner whose close returns a `Result` (`rc` runs it): shielded, on
    /// the path that still holds it. The first failing close is the outcome (the `Result` it
    /// returned, owned); later results are dropped.
    fn cleanup_fallible(
        &mut self,
        at: usize,
        v: Value,
        s: St,
        rc: FuncId,
        outcome: Option<Value>,
    ) -> Result<(usize, Option<Value>), String> {
        if s != St::Live {
            return Err("a memory slot owner with a fallible close that is moved out of".into());
        }
        let (enter, exit) = self
            .cx
            .shield
            .ok_or("a closing owner needs the shield calls")?;
        let rty = self.m.funcs[rc.index()].ret;
        self.discard(at, v);
        self.push(at, Op::CallRt, &[], Imm::Ext(enter), Some(Ty::UNIT));
        let r = self
            .push(at, Op::Call, &[v], Imm::Func(rc), Some(rty))
            .expect("close result");
        self.push(at, Op::CallRt, &[], Imm::Ext(exit), Some(Ty::UNIT));
        let close = self.closer(v)?;
        if let Some(ty) = self.m.funcs[close.index()].slot_close {
            let left = self
                .push(at, Op::Take, &[v], Imm::Ty(ty), Some(ty))
                .expect("taken");
            self.push(at, Op::Drop, &[left], Imm::None, None);
        }
        let Some(first) = outcome else {
            return Ok((at, Some(r)));
        };
        // An earlier failure stays the outcome; otherwise this result is.
        let failed = self.is_error(at, first);
        let (keep, replace, join) = (self.f.new_block(), self.f.new_block(), self.f.new_block());
        self.f.blocks[at].term = Term::CondBr {
            cond: failed,
            then: Target::to(keep),
            els: Target::to(replace),
        };
        self.push(keep.index(), Op::Drop, &[r], Imm::None, None);
        self.f.blocks[keep.index()].term = Term::Br(Target {
            block: join,
            args: vec![first],
        });
        self.push(replace.index(), Op::Drop, &[first], Imm::None, None);
        self.f.blocks[replace.index()].term = Term::Br(Target {
            block: join,
            args: vec![r],
        });
        let p = self.f.new_value(rty);
        self.f.blocks[join.index()].params.push(BlockParam {
            value: p,
            mode: Mode::Move,
        });
        Ok((join.index(), Some(p)))
    }

    /// Whether the `Result` `r` is an error.
    fn is_error(&mut self, at: usize, r: Value) -> Value {
        let tag = self
            .push(at, Op::AltTag, &[r], Imm::None, Some(Ty::INT))
            .expect("tag");
        let err = self
            .push(
                at,
                Op::IConst,
                &[],
                Imm::Int(Std::ERROR as i64),
                Some(Ty::INT),
            )
            .expect("error tag");
        self.push(at, Op::ICmp, &[tag, err], Imm::Cc(Cc::Eq), Some(Ty::BOOL))
            .expect("is error")
    }

    fn close_call(&mut self, at: usize, v: Value) -> Result<Value, String> {
        let close = self.closer(v)?;
        Ok(self
            .push(at, Op::Call, &[v], Imm::Func(close), Some(Ty::INT))
            .expect("result"))
    }

    /// Closes the live `v` of an owner that cannot fail, shielded from a stop request; the
    /// caller drops what the close leaves behind.
    fn close_infallible(&mut self, at: usize, v: Value) -> Result<(), String> {
        let close = self.closer(v)?;
        let (enter, exit) = self
            .cx
            .shield
            .ok_or("a closing owner needs the shield calls")?;
        self.discard(at, v);
        self.push(at, Op::CallRt, &[], Imm::Ext(enter), Some(Ty::UNIT));
        self.push(at, Op::Call, &[v], Imm::Func(close), Some(Ty::UNIT));
        self.push(at, Op::CallRt, &[], Imm::Ext(exit), Some(Ty::UNIT));
        Ok(())
    }

    /// Closes or drops the owners of `scope`, last defined first.
    fn cleanup(
        &mut self,
        mut at: usize,
        st: &mut State,
        scope: i64,
        mut outcome: Option<Value>,
    ) -> Result<(usize, Option<Value>), String> {
        let mut owners: Vec<(Value, St)> = self
            .cx
            .owners
            .get(&scope)
            .into_iter()
            .flatten()
            .filter_map(|v| st.get(*v).map(|s| (*v, s)))
            .collect();
        owners.sort_by_key(|(v, _)| std::cmp::Reverse(st.at[v]));
        for (v, s) in owners {
            st.remove(v);
            if s == St::Moved && !self.flagged.contains(&v) {
                continue;
            }
            (at, outcome) = self.cleanup_one(at, v, s, outcome)?;
        }
        Ok((at, outcome))
    }

    /// The cleanup of `scope` at a `raw_end`. Returns the block to continue in.
    fn exit(&mut self, cur: usize, st: &mut State, scope: i64) -> Result<usize, String> {
        let (cur, outcome) = self.cleanup(cur, st, scope, None)?;
        let Some(first) = outcome else {
            return Ok(cur);
        };
        let by_result = self.f.ty(first) != Ty::INT;
        let failed = if by_result {
            self.is_error(cur, first)
        } else {
            let zero = self
                .push(cur, Op::IConst, &[], Imm::Int(0), Some(Ty::INT))
                .expect("zero");
            self.push(
                cur,
                Op::ICmp,
                &[first, zero],
                Imm::Cc(Cc::Ne),
                Some(Ty::BOOL),
            )
            .expect("flag")
        };
        let (err, cont) = (self.f.new_block(), self.f.new_block());
        if by_result {
            self.push(cont.index(), Op::Drop, &[first], Imm::None, None);
        }
        self.f.blocks[cur].term = Term::CondBr {
            cond: failed,
            then: Target::to(err),
            els: Target::to(cont),
        };
        // The error edge: the enclosing scopes' cleanup, then what else is live, then return.
        let mut rest = st.clone();
        let mut outcome = Some(first);
        let mut at = err.index();
        let mut scope = self.cx.parents.get(&scope).copied();
        while let Some(s) = scope.filter(|s| *s >= 0) {
            (at, outcome) = self.cleanup(at, &mut rest, s, outcome)?;
            scope = self.cx.parents.get(&s).copied();
        }
        for (v, s) in rest.iter().rev() {
            // A fallible outcome consumes the value the function was about to return.
            if by_result && self.pending == Some(*v) {
                continue;
            }
            match s {
                St::Live => {
                    self.push(at, Op::Drop, &[*v], Imm::None, None);
                }
                _ if self.flagged.contains(v) => {
                    let flag = self.flags[v];
                    self.push(at, Op::DropIf, &[flag, *v], Imm::None, None);
                }
                _ => {}
            }
        }
        let ret = match (by_result, outcome) {
            (true, Some(out)) => {
                let (plain, pending) = self
                    .f
                    .close_exit
                    .ok_or("a fallible close needs the function's close exit")?;
                let ty = self.f.ret;
                Some(
                    match self.pending {
                        Some(p) => self.push(at, Op::Call, &[out, p], Imm::Func(pending), Some(ty)),
                        None => self.push(at, Op::Call, &[out], Imm::Func(plain), Some(ty)),
                    }
                    .expect("exit value"),
                )
            }
            (_, outcome) => outcome,
        };
        self.f.blocks[at].term = Term::Ret(ret);
        Ok(cont.index())
    }
}
