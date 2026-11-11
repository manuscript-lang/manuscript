//! Stage 0 prototype of drop elaboration (`proposals/elaborate-drops.md`): places the
//! scope-exit cleanup of a *Raw* function, one that leaves every owned value of a scope to the
//! markers below instead of dropping it.
//!
//! Markers are calls to three runtime declarations, so Raw MIR needs no new ops yet:
//!
//! * `msrt_raw_begin(scope, parent)`: opens `scope`, nested in `parent` (`-1` for the root).
//! * `msrt_raw_own(value, scope, kind)`: the owned `value` belongs to `scope`; `kind` 0 drops it,
//!   1 closes it with the module's `close` function (`fn(move T) -> int`, nonzero is an error).
//! * `msrt_raw_end(scope)`: the point where `scope`'s cleanup runs, on the fallthrough end and on
//!   every early exit that leaves it.
//!
//! At each `raw_end` the pass drops the owned values of the scope that are still live, in
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
use crate::types::{AltId, Ty};
use crate::verify::arg_modes;
use std::collections::{HashMap, HashSet};

const BEGIN: &str = "msrt_raw_begin";
const OWN: &str = "msrt_raw_own";
const END: &str = "msrt_raw_end";
const DISCARD: &str = "msrt_cleanup_discard";

#[derive(Clone, Copy, PartialEq)]
enum Marker {
    Begin,
    Own,
    End,
}

/// Elaborates every function of `m` that uses markers.
pub fn run(m: &mut Module) -> Result<(), String> {
    let close = m
        .funcs
        .iter()
        .position(|f| f.name == "close")
        .map(|i| FuncId(i as u32));
    let markers: HashMap<u32, Marker> = m
        .externs
        .iter()
        .enumerate()
        .filter_map(|(i, e)| {
            let kind = match e.name.as_str() {
                BEGIN => Marker::Begin,
                OWN => Marker::Own,
                END => Marker::End,
                _ => return None,
            };
            Some((i as u32, kind))
        })
        .collect();
    if markers.is_empty() {
        return Ok(());
    }
    let discard = match m.externs.iter().position(|e| e.name == DISCARD) {
        Some(i) => Some(ExtId(i as u32)),
        None if close.is_some() => Some(m.add_extern(ExternDef {
            name: DISCARD.into(),
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
        })),
        None => None,
    };
    for fi in 0..m.funcs.len() {
        let stand_in = Func::new("", Vec::new(), Ty::UNIT);
        let mut f = std::mem::replace(&mut m.funcs[fi], stand_in);
        let out = function(m, &mut f, &markers, close, discard);
        m.funcs[fi] = f;
        out.map_err(|e| format!("{}: {e}", m.funcs[fi].name))?;
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
type State = Vec<(Value, St)>;

struct Ctx {
    /// Owner value to `(scope, kind)`.
    tags: HashMap<Value, (i64, i64)>,
    parents: HashMap<i64, i64>,
    close: Option<FuncId>,
    discard: Option<ExtId>,
    markers: HashMap<u32, Marker>,
}

fn marker_of(cx: &Ctx, inst: &Inst) -> Option<Marker> {
    match (inst.op, inst.imm) {
        (Op::CallRt, Imm::Ext(e)) => cx.markers.get(&(e.index() as u32)).copied(),
        _ => None,
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

fn find(st: &State, v: Value) -> Option<usize> {
    st.iter().position(|(x, _)| *x == v)
}

fn consume_value(cx: &Ctx, st: &mut State, v: Value) -> Result<(), String> {
    let Some(i) = find(st, v) else {
        return Ok(());
    };
    match st[i].1 {
        St::Live if cx.tags.contains_key(&v) => st[i].1 = St::Moved,
        St::Live => {
            st.remove(i);
        }
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
    if marker_of(cx, inst) == Some(Marker::End) {
        let scope = konst(f, inst.args[0])?;
        st.retain(|(v, _)| cx.tags.get(v).is_none_or(|t| t.0 != scope));
        return Ok(());
    }
    consume_args(m, f, cx, st, &inst.args, &arg_modes(m, inst))?;
    if let (Op::AltTake, Imm::AltField(a, c, i)) = (inst.op, inst.imm)
        && let Some(k) = find(st, inst.args[0])
        && cx.tags.contains_key(&inst.args[0])
    {
        let bit = 1u32 << i;
        st[k].1 = match st[k].1 {
            St::Live => St::Part(a, c, bit),
            St::Part(pa, pc, mask) if (pa, pc) == (a, c) => St::Part(a, c, mask | bit),
            _ => {
                return Err(format!(
                    "alt.take on %{} in an unsupported state",
                    inst.args[0].0
                ));
            }
        };
    }
    if m.result_mode(f, inst) == Some(Mode::Move)
        && let Some(r) = inst.res
    {
        st.push((r, St::Live));
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
    let mut out = Vec::new();
    for (v, a) in old {
        let Some((_, b)) = new.iter().find(|(x, _)| x == v) else {
            continue;
        };
        out.push((
            *v,
            match (a, b) {
                _ if a == b => *a,
                (St::Part(..), _) | (_, St::Part(..)) => {
                    return Err(format!("%{} is partially moved on only some paths", v.0));
                }
                _ => St::Maybe,
            },
        ));
    }
    Ok(out)
}

fn konst(f: &Func, v: Value) -> Result<i64, String> {
    for b in &f.blocks {
        for i in &b.insts {
            if let (Op::IConst, Imm::Int(n), Some(r)) = (i.op, i.imm, i.res)
                && r == v
            {
                return Ok(n);
            }
        }
    }
    Err("a marker operand is not an integer constant".to_string())
}

fn function(
    m: &Module,
    f: &mut Func,
    markers: &HashMap<u32, Marker>,
    close: Option<FuncId>,
    discard: Option<ExtId>,
) -> Result<(), String> {
    let mut cx = Ctx {
        tags: HashMap::new(),
        parents: HashMap::new(),
        close,
        discard,
        markers: markers.clone(),
    };
    let mut any = false;
    for b in &f.blocks {
        for i in &b.insts {
            match marker_of(&cx, i) {
                Some(Marker::Begin) => {
                    any = true;
                    cx.parents
                        .insert(konst(f, i.args[0])?, konst(f, i.args[1])?);
                }
                Some(Marker::Own) => {
                    any = true;
                    cx.tags
                        .insert(i.args[0], (konst(f, i.args[1])?, konst(f, i.args[2])?));
                }
                _ => {}
            }
        }
    }
    if !any {
        return Ok(());
    }
    // A value that flows through a moving block parameter keeps its scope.
    loop {
        let mut changed = false;
        for b in &f.blocks {
            b.term.for_each_target(|t| {
                for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                    if p.mode == Mode::Move
                        && let Some(tag) = cx.tags.get(a).copied()
                        && cx.tags.insert(p.value, tag).is_none()
                    {
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
    entry[0] = Some(Vec::new());
    for _ in 0..=(4 * f.blocks.len() + 4) {
        let mut changed = false;
        for b in order {
            let Some(mut st) = entry[b.index()].clone() else {
                continue;
            };
            st.extend(
                own_params(m, f, b.index())
                    .into_iter()
                    .map(|p| (p, St::Live)),
            );
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
        let mut st = entry;
        let mut cur = b;
        for p in own_params(self.m, self.f, b) {
            st.push((p, St::Live));
            self.birth(cur, p);
        }
        for mut inst in old.insts {
            match marker_of(self.cx, &inst) {
                Some(Marker::Begin) => continue,
                Some(Marker::Own) => {
                    let v = inst.args[0];
                    if self.cx.tags[&v].1 == 1 {
                        self.register(cur, v)?;
                    }
                    continue;
                }
                Some(Marker::End) => {
                    let scope = konst(self.f, inst.args[0])?;
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
        if self.cx.tags.get(&v).is_some_and(|t| t.1 == 1) && !self.handles.contains_key(&v) {
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
        let close = self
            .cx
            .close
            .ok_or_else(|| "a closing owner needs a `close` function".to_string())?;
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

    fn close_call(&mut self, at: usize, v: Value) -> Result<Value, String> {
        let close = self
            .cx
            .close
            .ok_or_else(|| "a closing owner needs a `close` function".to_string())?;
        Ok(self
            .push(at, Op::Call, &[v], Imm::Func(close), Some(Ty::INT))
            .expect("result"))
    }

    /// Closes or drops the owners of `scope`, last defined first.
    fn cleanup(
        &mut self,
        mut at: usize,
        st: &mut State,
        scope: i64,
        mut outcome: Option<Value>,
    ) -> Result<(usize, Option<Value>), String> {
        let owners: Vec<(Value, St)> = st
            .iter()
            .rev()
            .filter(|(v, _)| self.cx.tags.get(v).is_some_and(|t| t.0 == scope))
            .copied()
            .collect();
        for (v, s) in owners {
            st.retain(|(x, _)| *x != v);
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
        let zero = self
            .push(cur, Op::IConst, &[], Imm::Int(0), Some(Ty::INT))
            .expect("zero");
        let failed = self
            .push(
                cur,
                Op::ICmp,
                &[first, zero],
                Imm::Cc(Cc::Ne),
                Some(Ty::BOOL),
            )
            .expect("flag");
        let (err, cont) = (self.f.new_block(), self.f.new_block());
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
        self.f.blocks[at].term = Term::Ret(outcome);
        Ok(cont.index())
    }
}
