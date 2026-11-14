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
use crate::types::{AltId, Std, Ty, TyKind};
use crate::verify::{arg_modes, is_raw};
use std::collections::{HashMap, HashSet};

const DISCARD: &str = "msrt_cleanup_discard";
const CANCEL: &str = "msrt_cleanup_cancel";
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
    let cancel = closes.then(|| runtime(m, CANCEL, &[Ty::INT], ExternRole::None));
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
        let stand_in = m.funcs[fi].signature_stand_in();
        let mut f = std::mem::replace(&mut m.funcs[fi], stand_in);
        let out = function(m, &mut f, close, discard, cancel, shield);
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
    /// A slot owner the program closed by hand (`scope.mark p 1`): the scope end closes it
    /// again to release what is left and drops that close's result.
    Closed,
    /// Closed by hand on some paths into a join: the owner carries a flag saying which.
    MaybeClosed,
    /// Closed by hand on some paths and moved out on others: the owner carries a drop flag (still
    /// held) and a closed flag (the hold is a hand close).
    ClosedOrMoved,
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
    /// Turns a cleanup entry into a no-op without popping the newer ones (a slot owner moved
    /// out of mid-scope).
    cancel: Option<ExtId>,
    shield: Option<(ExtId, ExtId)>,
    /// Flagged owners that a `scope.disown` ahead of the consuming op leaves tracked as moved.
    disown_moves: HashSet<Value>,
}

/// Whether `v` owns a memory slot (`scope.own S K p`, K >= 2): the owner is the slot's address.
fn is_slot_owner(cx: &Ctx, f: &Func, v: Value) -> bool {
    f.ty(v) == Ty::PTR && cx.tags.get(&v).is_some_and(|t| t.1 >= 2)
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

/// Whether scope `outer` encloses scope `inner`.
fn is_ancestor(parents: &HashMap<i64, i64>, outer: i64, inner: i64) -> bool {
    let mut cur = parents.get(&inner).copied();
    while let Some(s) = cur.filter(|s| *s >= 0) {
        if s == outer {
            return true;
        }
        cur = parents.get(&s).copied();
    }
    false
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
        // Disowned, then consumed by the op that takes it.
        St::Moved if cx.disown_moves.contains(&v) => {}
        St::Moved => return Err(format!("%{} is consumed after it was moved", v.0)),
        St::Maybe | St::ClosedOrMoved => {
            return Err(format!("%{} is consumed but moved on some path", v.0));
        }
        St::Part(..) => return Err(format!("%{} is consumed after a partial move", v.0)),
        St::Closed | St::MaybeClosed => {
            return Err(format!("%{} is consumed after the program closed it", v.0));
        }
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
        let v = inst.args[0];
        // A memory slot owner whose value moved out stays tracked: its entry is cancelled and
        // the scope end closes nothing for it on this path.
        if is_slot_owner(cx, f, v) {
            return match st.get(v) {
                // A slot whose close the program handles (`scope.mark 1` at its birth) moves out
                // like a live one.
                Some(St::Live | St::Closed) => {
                    st.set(v, St::Moved);
                    Ok(())
                }
                Some(St::Moved) | None => Ok(()),
                Some(t) => Err(format!(
                    "slot owner %{} moved out of in an unsupported state {t:?}",
                    v.0
                )),
            };
        }
        // A flagged owner stays tracked as moved: the op that consumes it after the disown, and
        // the exits after it, see the flag turn false.
        if cx.disown_moves.contains(&v) && st.get(v) == Some(St::Live) {
            st.set(v, St::Moved);
        } else {
            st.remove(v);
        }
        return Ok(());
    }
    if inst.op == Op::ScopeMark {
        let v = inst.args[0];
        let next = match inst.imm {
            Imm::Int(1) => St::Closed,
            _ => St::Live,
        };
        let refill = inst.imm == Imm::Int(2);
        return match st.get(v) {
            Some(St::Live | St::Closed | St::MaybeClosed) => {
                st.set(v, next);
                Ok(())
            }
            // A refill stores a new value in a slot whose value moved out.
            Some(St::Moved | St::Maybe | St::ClosedOrMoved) if refill => {
                st.set(v, St::Live);
                Ok(())
            }
            None => Ok(()),
            Some(_) => Err(format!("slot owner %{} closed by hand after a move", v.0)),
        };
    }
    // A disowned view that moves into another local is owned again by that local's scope.
    if inst.op == Op::ScopeOwn {
        let v = inst.args[0];
        match st.get(v) {
            None => st.push(v, St::Live),
            // A slot owner handed on to an enclosing scope (a pending temporary that outlives
            // the scope it was made in) holds its value again.
            Some(St::Moved) if is_slot_owner(cx, f, v) => st.set(v, St::Live),
            _ => {}
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
            // Disowned ahead of the take: the value already left the scope.
            St::Moved if cx.disown_moves.contains(&inst.args[0]) => St::Moved,
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
            // Gone on the other path: consumed or disowned there, so moved.
            if matches!(a, St::Live | St::Maybe) {
                out.push(*v, St::Maybe);
            }
            continue;
        };
        out.push(
            *v,
            match (a, &b) {
                _ if *a == b => *a,
                (
                    St::Live | St::Closed | St::MaybeClosed,
                    St::Live | St::Closed | St::MaybeClosed,
                ) => St::MaybeClosed,
                (St::Part(..), _) | (_, St::Part(..)) => {
                    return Err(format!("%{} is partially moved on only some paths", v.0));
                }
                (St::Closed | St::MaybeClosed | St::ClosedOrMoved, _)
                | (_, St::Closed | St::MaybeClosed | St::ClosedOrMoved) => St::ClosedOrMoved,
                _ => St::Maybe,
            },
        );
    }
    for (v, b) in new.iter() {
        if old.get(*v).is_none() && matches!(b, St::Live | St::Maybe) {
            out.push(*v, St::Maybe);
        }
    }
    Ok(out)
}

/// Whether `v` is disowned in block `b` or in the blocks that lead to it without a join.
fn disowned_before(f: &Func, preds: &[Vec<Block>], b: usize, v: Value) -> bool {
    let mut cur = b;
    let mut seen = HashSet::new();
    while seen.insert(cur) {
        if f.blocks[cur]
            .insts
            .iter()
            .any(|i| i.op == Op::ScopeDisown && i.args[0] == v)
        {
            return true;
        }
        match preds[cur].as_slice() {
            [only] => cur = only.index(),
            _ => return false,
        }
    }
    false
}

fn function(
    m: &Module,
    f: &mut Func,
    close: Option<FuncId>,
    discard: Option<ExtId>,
    cancel: Option<ExtId>,
    shield: Option<(ExtId, ExtId)>,
) -> Result<(), String> {
    let mut cx = Ctx {
        tags: HashMap::new(),
        owners: HashMap::new(),
        parents: HashMap::new(),
        close,
        discard,
        cancel,
        shield,
        disown_moves: HashSet::new(),
    };
    for b in &f.blocks {
        for i in &b.insts {
            if let (Op::ScopeBegin, Imm::Scope(s, parent)) = (i.op, i.imm) {
                cx.parents.insert(i64::from(s), i64::from(parent) - 1);
            }
        }
    }
    for b in &f.blocks {
        for i in &b.insts {
            if let (Op::ScopeOwn, Imm::Scope(s, kind)) = (i.op, i.imm) {
                let (s, kind) = (i64::from(s), i64::from(kind));
                // A value an inner scope owns again (a statement's temporary holding a moved
                // local) stays the outer scope's: the path that never reaches the inner scope
                // still holds it there, and the inner scope's end finds it moved.
                if let Some(&(old, _)) = cx.tags.get(&i.args[0])
                    && old != s
                    && is_ancestor(&cx.parents, old, s)
                {
                    continue;
                }
                // A value owned again by a later scope leaves the earlier scope's list.
                if let Some((old, _)) = cx.tags.insert(i.args[0], (s, kind))
                    && let Some(list) = cx.owners.get_mut(&old)
                {
                    list.retain(|v| *v != i.args[0]);
                }
                cx.owners.entry(s).or_default().push(i.args[0]);
            }
        }
    }
    // A value that flows through a moving block parameter keeps its scope.
    let preds = f.predecessors();
    loop {
        let mut changed = false;
        for (bi, b) in f.blocks.iter().enumerate() {
            b.term.for_each_target(|t| {
                for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                    // A disowned value left its scope: the parameter it feeds is the new owner's.
                    // The disown may sit in a block this one follows without a join.
                    let disowned = disowned_before(f, &preds, bi, *a);
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
    let mut entry = analyze(m, f, &cx, &order)?;
    let maybe = |entry: &[Option<State>]| -> HashSet<Value> {
        entry
            .iter()
            .flatten()
            .flat_map(|s| {
                s.iter()
                    .filter(|(_, t)| matches!(t, St::Maybe | St::ClosedOrMoved))
                    .map(|(v, _)| *v)
            })
            .collect()
    };
    // A flagged owner that is disowned before the op consuming it needs the moved state, so
    // the exits after the move do not release it again.
    let disowned: HashSet<Value> = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter(|i| i.op == Op::ScopeDisown)
        .map(|i| i.args[0])
        .collect();
    cx.disown_moves = maybe(&entry).intersection(&disowned).copied().collect();
    if !cx.disown_moves.is_empty() {
        entry = analyze(m, f, &cx, &order)?;
    }
    let flagged = maybe(&entry);
    // An owner closed by hand on some paths carries a flag too, kept under a key of its own.
    let mut ckeys: HashMap<Value, Value> = HashMap::new();
    for s in entry.iter().flatten() {
        for (v, t) in s.iter() {
            if matches!(t, St::MaybeClosed | St::ClosedOrMoved) && !ckeys.contains_key(v) {
                let key = f.new_value(Ty::BOOL);
                ckeys.insert(*v, key);
            }
        }
    }
    // A slot owner refilled after a move registers a new cleanup entry, so the entry a later move
    // cancels travels in a block parameter under a key of its own.
    let refilled: Vec<Value> = f
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter(|i| i.op == Op::ScopeMark && i.imm == Imm::Int(2))
        .map(|i| i.args[0])
        .collect();
    let mut owned_at: HashMap<Value, usize> = HashMap::new();
    for i in f.blocks.iter().flat_map(|b| &b.insts) {
        if i.op == Op::ScopeOwn {
            *owned_at.entry(i.args[0]).or_default() += 1;
        }
    }
    // A slot owner handed on to another scope registers a new entry where it is owned again.
    let reowned: Vec<Value> = owned_at
        .into_iter()
        .filter(|(v, n)| *n > 1 && is_slot_owner(&cx, f, *v))
        .map(|(v, _)| v)
        .collect();
    let mut reowned = reowned;
    reowned.sort_by_key(|v| v.0);
    let mut hkeys: HashMap<Value, Value> = HashMap::new();
    for v in refilled.into_iter().chain(reowned) {
        hkeys.entry(v).or_insert_with(|| f.new_value(Ty::INT));
    }
    // The flag parameters of every block: one per flagged owner that is live on entry.
    let mut fparams: Vec<Vec<(Value, Value)>> = vec![Vec::new(); f.blocks.len()];
    for b in &order {
        let Some(e) = &entry[b.index()] else { continue };
        for (v, t) in e.iter() {
            let mut keys = Vec::new();
            if flagged.contains(v) {
                keys.push((*v, Ty::BOOL));
            }
            if matches!(t, St::MaybeClosed | St::ClosedOrMoved) {
                keys.push((ckeys[v], Ty::BOOL));
            }
            if let Some(h) = hkeys.get(v) {
                keys.push((*h, Ty::INT));
            }
            for (key, ty) in keys {
                let p = f.new_value(ty);
                f.blocks[b.index()].params.push(BlockParam {
                    value: p,
                    mode: Mode::Borrow,
                });
                fparams[b.index()].push((key, p));
            }
        }
    }
    let counts_depth = f
        .blocks
        .iter()
        .any(|b| b.insts.iter().any(|i| i.op == Op::DepthEnter));
    let mut em = Em {
        m,
        f,
        cx: &cx,
        flagged,
        ckeys,
        hkeys,
        flags: HashMap::new(),
        handles: HashMap::new(),
        pending: None,
        counts_depth,
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
    /// The key of the closed-by-hand flag of each owner that has one.
    ckeys: HashMap<Value, Value>,
    /// The key of the live cleanup entry of each owner that can be refilled.
    hkeys: HashMap<Value, Value>,
    /// The current flag value of each flagged owner (reset per block).
    flags: HashMap<Value, Value>,
    /// The `cleanup.push` handle of each closing owner.
    handles: HashMap<Value, Value>,
    /// The value the block being rebuilt returns, still to be returned after its scope ends.
    pending: Option<Value>,
    /// The function guards its recursion depth (`depth.enter` at its start).
    counts_depth: bool,
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

    /// Cancels the cleanup entry of a slot owner whose value moved out, and clears its flag:
    /// newer entries stay, and the scope end discards this one.
    fn cancel(&mut self, at: usize, v: Value) {
        let live = self
            .hkeys
            .get(&v)
            .and_then(|k| self.flags.get(k))
            .or_else(|| self.handles.get(&v))
            .copied();
        if let (Some(h), Some(c)) = (live, self.cx.cancel) {
            self.push(at, Op::CallRt, &[h], Imm::Ext(c), Some(Ty::UNIT));
        }
        if self.flagged.contains(&v) {
            let off = self.bconst(at, false);
            self.flags.insert(v, off);
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
        // The value the block returns is pending for a close only once it exists: one the block
        // defines is not pending for a scope that ends before that (a loop's, say).
        let returned = match &old.term {
            Term::Ret(Some(v)) => Some(*v),
            _ => None,
        };
        let defined_here = |v: &Value| old.insts.iter().any(|i| i.res == Some(*v));
        self.pending = returned.filter(|v| !defined_here(v));
        let mut st = entry;
        let mut cur = b;
        let mut insts = old.insts;
        // The stack check stays the first instruction of the entry block.
        if insts.first().is_some_and(|i| i.op == Op::DepthEnter) {
            let first = insts.remove(0);
            self.f.blocks[cur].insts.push(first);
        }
        // An owner that is surely open or surely closed by hand here has a constant flag.
        let known: Vec<(Value, bool)> = self
            .ckeys
            .iter()
            .filter_map(|(v, key)| match st.get(*v) {
                Some(St::Live) if !self.flags.contains_key(key) => Some((*key, false)),
                Some(St::Closed) if !self.flags.contains_key(key) => Some((*key, true)),
                _ => None,
            })
            .collect();
        for (key, on) in known {
            let c = self.bconst(b, on);
            self.flags.insert(key, c);
        }
        for p in own_params(self.m, self.f, b) {
            st.push(p, St::Live);
            self.birth(cur, p);
        }
        for mut inst in insts {
            if inst.op == Op::ScopeDisown {
                let v = inst.args[0];
                let was = st.get(v);
                apply(self.m, self.f, self.cx, &mut st, &inst)?;
                if is_slot_owner(self.cx, self.f, v) && matches!(was, Some(St::Live | St::Closed)) {
                    self.cancel(cur, v);
                }
                continue;
            }
            if inst.op == Op::ScopeMark && inst.imm == Imm::Int(2) {
                let v = inst.args[0];
                let was = st.get(v);
                apply(self.m, self.f, self.cx, &mut st, &inst)?;
                cur = self.refill(cur, v, was)?;
                if let Some(key) = self.ckeys.get(&v).copied() {
                    let open = self.bconst(cur, false);
                    self.flags.insert(key, open);
                }
                continue;
            }
            if inst.op == Op::ScopeMark {
                apply(self.m, self.f, self.cx, &mut st, &inst)?;
                if let Some(key) = self.ckeys.get(&inst.args[0]).copied() {
                    let closed = self.bconst(cur, matches!(inst.imm, Imm::Int(1)));
                    self.flags.insert(key, closed);
                }
                continue;
            }
            match marker_of(&inst) {
                Some(Marker::Begin) => continue,
                Some(Marker::Own) => {
                    let v = inst.args[0];
                    let was = st.get(v);
                    apply(self.m, self.f, self.cx, &mut st, &inst)?;
                    if was == Some(St::Moved) && is_slot_owner(self.cx, self.f, v) {
                        let key = self.hkeys.get(&v).copied();
                        self.reregister(cur, v, key)?;
                        self.set_held(cur, v);
                        continue;
                    }
                    if self.cx.tags[&v].1 >= 1 {
                        self.register(cur, v)?;
                    }
                    if self.flagged.contains(&v) && is_slot_owner(self.cx, self.f, v) {
                        let held = self.bconst(cur, true);
                        self.flags.insert(v, held);
                    }
                    if let Some(key) = self.ckeys.get(&v).copied() {
                        let open = self.bconst(cur, false);
                        self.flags.insert(key, open);
                    }
                    if let (Some(key), Some(h)) = (self.hkeys.get(&v), self.handles.get(&v)) {
                        self.flags.insert(*key, *h);
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
            if inst.res.is_some() && inst.res == returned {
                self.pending = returned;
            }
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

    /// The program is about to store a new value in the slot owner `v` (`scope.mark 2`): what it
    /// still holds is closed shielded (the replaced value), and a slot whose value moved out
    /// registers a fresh cleanup entry for the value stored next. Returns the block to continue in.
    fn refill(&mut self, at: usize, v: Value, was: Option<St>) -> Result<usize, String> {
        let flag = self.flags.get(&v).copied();
        let key = self.hkeys.get(&v).copied();
        let held = |me: &mut Self, at: usize| me.close_replaced(at, v);
        match was {
            Some(St::Moved) => {
                self.reregister(at, v, key)?;
                self.set_held(at, v);
                Ok(at)
            }
            Some(St::Maybe | St::ClosedOrMoved) => {
                let flag = flag.ok_or("a moved slot owner without a drop flag")?;
                let (yes, no, join) = (self.f.new_block(), self.f.new_block(), self.f.new_block());
                self.f.blocks[at].term = Term::CondBr {
                    cond: flag,
                    then: Target::to(yes),
                    els: Target::to(no),
                };
                held(self, yes.index())?;
                let kept = key.and_then(|k| self.flags.get(&k).copied());
                self.f.blocks[yes.index()].term = Term::Br(Target {
                    block: join,
                    args: kept.into_iter().collect(),
                });
                let fresh = self.reregister(no.index(), v, key)?;
                self.f.blocks[no.index()].term = Term::Br(Target {
                    block: join,
                    args: fresh.into_iter().collect(),
                });
                if let Some(key) = key {
                    let p = self.f.new_value(Ty::INT);
                    self.f.blocks[join.index()].params.push(BlockParam {
                        value: p,
                        mode: Mode::Borrow,
                    });
                    self.flags.insert(key, p);
                }
                self.set_held(join.index(), v);
                Ok(join.index())
            }
            _ => {
                held(self, at)?;
                Ok(at)
            }
        }
    }

    /// Closes what the slot owner `v` holds, shielded, and releases what the close leaves; its
    /// cleanup entry stays for the value stored next.
    fn close_replaced(&mut self, at: usize, v: Value) -> Result<(), String> {
        let close = self.closer(v)?;
        if let Some(rc) = self.m.funcs[close.index()].slot_result {
            let r = self.close_result(at, v, rc)?;
            self.drop_owned(at, r);
            return Ok(());
        }
        let (enter, exit) = self
            .cx
            .shield
            .ok_or("a closing owner needs the shield calls")?;
        self.push(at, Op::CallRt, &[], Imm::Ext(enter), Some(Ty::UNIT));
        self.push(at, Op::Call, &[v], Imm::Func(close), Some(Ty::UNIT));
        self.push(at, Op::CallRt, &[], Imm::Ext(exit), Some(Ty::UNIT));
        if let Some(ty) = self.m.funcs[close.index()].slot_close {
            let left = self
                .push(at, Op::Take, &[v], Imm::Ty(ty), Some(ty))
                .expect("taken");
            self.push(at, Op::Drop, &[left], Imm::None, None);
        }
        Ok(())
    }

    /// Registers a new cleanup entry for the refilled slot owner `v` and returns its handle.
    fn reregister(
        &mut self,
        at: usize,
        v: Value,
        key: Option<Value>,
    ) -> Result<Option<Value>, String> {
        let close = self.closer(v)?;
        let h = self
            .push(at, Op::CleanupPush, &[v], Imm::Func(close), Some(Ty::INT))
            .expect("handle");
        if let Some(k) = key {
            self.flags.insert(k, h);
        }
        Ok(key.map(|_| h))
    }

    /// The refilled owner holds a value again.
    fn set_held(&mut self, at: usize, v: Value) {
        if self.flagged.contains(&v) {
            let t = self.bconst(at, true);
            self.flags.insert(v, t);
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
                match self.flags.get(owner) {
                    Some(f) => *f,
                    None => {
                        // The entry of an owner that no path has refilled yet is its first.
                        let first = self.hkeys.iter().find(|(_, k)| *k == owner);
                        match first.and_then(|(o, _)| self.handles.get(o)) {
                            Some(h) => *h,
                            // An owner this path no longer holds.
                            None if self.flagged.contains(owner) => self.bconst(at, false),
                            None => return Err(format!("no drop flag for %{}", owner.0)),
                        }
                    }
                }
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
            (St::Closed | St::MaybeClosed | St::ClosedOrMoved, _) => {
                return Err("only a memory slot owner is closed by hand".into());
            }
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
                if self.f.ty(v) == Ty::PTR {
                    self.close_slot(at, v)?;
                    return Ok(at);
                }
                self.close_infallible(at, v)?;
                self.push(at, Op::Drop, &[v], Imm::None, None);
                Ok(at)
            }
            St::Part(..) => Err("a partially moved closing owner".into()),
            St::Closed | St::MaybeClosed => {
                // Closing again releases what the hand close left; the result is ignored.
                self.close_slot(at, v)?;
                Ok(at)
            }
            St::Moved | St::Maybe | St::ClosedOrMoved if self.f.ty(v) == Ty::PTR => {
                // The flag says whether the value is still in the slot. The cancelled entry (or
                // the live one) leaves the stack either way.
                let flag = flag.ok_or("a moved slot owner without a drop flag")?;
                let (yes, no, join) = (self.f.new_block(), self.f.new_block(), self.f.new_block());
                self.f.blocks[at].term = Term::CondBr {
                    cond: flag,
                    then: Target::to(yes),
                    els: Target::to(no),
                };
                // The close discards the live entry itself; the cancelled one leaves here.
                self.close_slot(yes.index(), v)?;
                self.f.blocks[yes.index()].term = Term::Br(Target::to(join));
                self.discard(no.index(), v);
                self.f.blocks[no.index()].term = Term::Br(Target::to(join));
                Ok(join.index())
            }
            St::ClosedOrMoved => Err("only a memory slot owner is closed by hand".into()),
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

    /// Closes the infallible memory slot owner `v` that still holds its value, shielded: its
    /// close function (an in-slot cleanup entry, `slot_close`) takes the address, and what the
    /// close leaves in the slot is taken out and dropped.
    fn close_slot(&mut self, at: usize, v: Value) -> Result<(), String> {
        self.close_infallible(at, v)?;
        let close = self.closer(v)?;
        if let Some(ty) = self.m.funcs[close.index()].slot_close {
            let left = self
                .push(at, Op::Take, &[v], Imm::Ty(ty), Some(ty))
                .expect("taken");
            self.push(at, Op::Drop, &[left], Imm::None, None);
        }
        Ok(())
    }

    /// Closes the slot owner `v` the program may have closed by hand (the closed flag says): a
    /// hand close is closed again to release the rest and its result dropped, so the outcome is
    /// a plain success. Returns the block to continue in and the close's `Result`.
    fn close_maybe_closed(
        &mut self,
        at: usize,
        v: Value,
        rc: FuncId,
    ) -> Result<(usize, Value), String> {
        let rty = self.m.funcs[rc.index()].ret;
        let key = *self
            .ckeys
            .get(&v)
            .ok_or("a maybe-closed owner without a flag")?;
        let flag = self
            .flags
            .get(&key)
            .copied()
            .ok_or("a maybe-closed owner without a flag")?;
        let (yes, no, join) = (self.f.new_block(), self.f.new_block(), self.f.new_block());
        self.f.blocks[at].term = Term::CondBr {
            cond: flag,
            then: Target::to(yes),
            els: Target::to(no),
        };
        self.discard(yes.index(), v);
        self.discard(no.index(), v);
        let again = self.close_result(yes.index(), v, rc)?;
        self.drop_owned(yes.index(), again);
        let none = self.ok_unit(yes.index(), rty)?;
        self.f.blocks[yes.index()].term = Term::Br(Target {
            block: join,
            args: vec![none],
        });
        let real = self.close_result(no.index(), v, rc)?;
        self.f.blocks[no.index()].term = Term::Br(Target {
            block: join,
            args: vec![real],
        });
        let p = self.f.new_value(rty);
        self.f.blocks[join.index()].params.push(BlockParam {
            value: p,
            mode: Mode::Move,
        });
        Ok((join.index(), p))
    }

    /// Cleans up a memory-slot owner whose close returns a `Result` (`rc` runs it): shielded, on
    /// the path that still holds it. The first failing close is the outcome (the `Result` it
    /// returned, owned); later results are dropped.
    fn cleanup_fallible(
        &mut self,
        mut at: usize,
        v: Value,
        s: St,
        rc: FuncId,
        outcome: Option<Value>,
    ) -> Result<(usize, Option<Value>), String> {
        if matches!(s, St::Part(..)) {
            return Err("a partially moved slot owner".into());
        }
        let rty = self.m.funcs[rc.index()].ret;
        let closed;
        let r = if s == St::Closed {
            // Closed by the program: close again to release the rest, drop that result.
            self.discard(at, v);
            let again = self.close_result(at, v, rc)?;
            self.drop_owned(at, again);
            return Ok((at, outcome));
        } else if s == St::MaybeClosed {
            (at, closed) = self.close_maybe_closed(at, v, rc)?;
            closed
        } else if s == St::ClosedOrMoved {
            // The flag says whether the value is still in the slot; if so the closed flag says
            // whether the program closed it. A path that moved it closes nothing.
            let flag = self
                .flags
                .get(&v)
                .copied()
                .ok_or("a moved slot owner without a drop flag")?;
            let (yes, no, join) = (self.f.new_block(), self.f.new_block(), self.f.new_block());
            self.f.blocks[at].term = Term::CondBr {
                cond: flag,
                then: Target::to(yes),
                els: Target::to(no),
            };
            let (end, closed) = self.close_maybe_closed(yes.index(), v, rc)?;
            self.f.blocks[end].term = Term::Br(Target {
                block: join,
                args: vec![closed],
            });
            self.discard(no.index(), v);
            let none = self.ok_unit(no.index(), rty)?;
            self.f.blocks[no.index()].term = Term::Br(Target {
                block: join,
                args: vec![none],
            });
            let p = self.f.new_value(rty);
            self.f.blocks[join.index()].params.push(BlockParam {
                value: p,
                mode: Mode::Move,
            });
            at = join.index();
            p
        } else if s == St::Live {
            self.discard(at, v);
            self.close_result(at, v, rc)?
        } else {
            // Moved out of on some path: the flag says whether the value is still in the slot.
            // A path that moved it closes nothing and adds the success result.
            let flag = self
                .flags
                .get(&v)
                .copied()
                .ok_or("a moved slot owner without a drop flag")?;
            let (yes, no, join) = (self.f.new_block(), self.f.new_block(), self.f.new_block());
            self.f.blocks[at].term = Term::CondBr {
                cond: flag,
                then: Target::to(yes),
                els: Target::to(no),
            };
            self.discard(yes.index(), v);
            self.discard(no.index(), v);
            let closed = self.close_result(yes.index(), v, rc)?;
            self.f.blocks[yes.index()].term = Term::Br(Target {
                block: join,
                args: vec![closed],
            });
            let none = self.ok_unit(no.index(), rty)?;
            self.f.blocks[no.index()].term = Term::Br(Target {
                block: join,
                args: vec![none],
            });
            let p = self.f.new_value(rty);
            self.f.blocks[join.index()].params.push(BlockParam {
                value: p,
                mode: Mode::Move,
            });
            at = join.index();
            p
        };
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
        self.drop_owned(keep.index(), r);
        self.f.blocks[keep.index()].term = Term::Br(Target {
            block: join,
            args: vec![first],
        });
        self.drop_owned(replace.index(), first);
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

    /// Runs the fallible close `rc` of the slot owner `v` shielded and releases what it leaves
    /// in the slot. Returns the close's `Result`.
    fn close_result(&mut self, at: usize, v: Value, rc: FuncId) -> Result<Value, String> {
        let (enter, exit) = self
            .cx
            .shield
            .ok_or("a closing owner needs the shield calls")?;
        let rty = self.m.funcs[rc.index()].ret;
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
        Ok(r)
    }

    /// The success of the `Result` type `rty` (its `ok` payload is `unit`).
    fn ok_unit(&mut self, at: usize, rty: Ty) -> Result<Value, String> {
        let TyKind::Alt(a) = self.m.types.kind(rty).clone() else {
            return Err("a fallible close returns a Result".into());
        };
        if self.m.alts[a.index()].cases[Std::OK].fields[0].1 != Ty::UNIT {
            return Err("a moved slot owner whose close succeeds with a value".into());
        }
        let unit = self
            .push(at, Op::UnitConst, &[], Imm::None, Some(Ty::UNIT))
            .expect("unit");
        Ok(self
            .push(
                at,
                Op::AltNew,
                &[unit],
                Imm::Case(a, Std::OK as u32),
                Some(rty),
            )
            .expect("ok"))
    }

    /// Drops `v` when its type holds anything to release.
    fn drop_owned(&mut self, at: usize, v: Value) {
        if self.m.needs_drop(self.f.ty(v)) {
            self.push(at, Op::Drop, &[v], Imm::None, None);
        }
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
                // A slot owner's cancelled entry leaves the stack now.
                if is_slot_owner(self.cx, self.f, v) {
                    self.discard(at, v);
                }
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
            self.drop_owned(cont.index(), first);
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
                // The function leaves here: undo its recursion guard like any return.
                if self.counts_depth {
                    self.push(at, Op::DepthLeave, &[], Imm::None, None);
                }
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
