//! Stage 0 prototype of drop elaboration (`proposals/elaborate-drops.md`): places the
//! scope-exit cleanup of a *Raw* function, one that leaves every owned value of a scope to the
//! markers below instead of dropping it.
//!
//! Markers are real ops (`Op::ScopeBegin`, `ScopeOwn`, `ScopeEnd`), present only in Raw
//! functions (`verify::is_raw`):
//!
//! * `scope.begin S P`: opens scope `S`, nested in `P - 1` (`P` is 0 for the root).
//! * `scope.own S K v`: the owned `v` belongs to `S`; `K` 0 drops it, 1 closes it with the
//!   module's `close` function (`fn(move T) -> int`, nonzero is an error).
//! * `scope.end S`: the point where `S`'s cleanup runs, on the fallthrough end and on every early
//!   exit that leaves it.
//!
//! At each `scope.end` the pass drops the owned values of the scope that are still live, in
//! reverse definition order. Because the live set follows the consuming operands, a value an
//! earlier path moved or closed is simply absent: nothing remembers "already dropped on this
//! path". A failing close (first error wins) leaves through an error edge the pass builds: it
//! cleans up the enclosing scopes, drops what else is live (a pending return value), and returns
//! the first error. The markers are removed.

use crate::ir::*;
use crate::types::Ty;
use crate::verify::{arg_modes, is_raw};
use std::collections::HashMap;

/// Elaborates every Raw function of `m`.
pub fn run(m: &mut Module) -> Result<(), String> {
    let close = m
        .funcs
        .iter()
        .position(|f| f.name == "close")
        .map(|i| FuncId(i as u32));
    for fi in 0..m.funcs.len() {
        if !is_raw(&m.funcs[fi]) {
            continue;
        }
        let stand_in = Func::new("", Vec::new(), Ty::UNIT);
        let mut f = std::mem::replace(&mut m.funcs[fi], stand_in);
        let out = function(m, &mut f, close);
        m.funcs[fi] = f;
        out.map_err(|e| format!("{}: {e}", m.funcs[fi].name))?;
    }
    Ok(())
}

type Tags = HashMap<Value, (u32, u32)>;

/// The owned values live at a point, with O(1) removal: consuming an operand must not rescan
/// what else is live (a long function holds many temporaries at once).
#[derive(Clone, Default)]
struct Live {
    seq: HashMap<Value, u32>,
    next: u32,
}

impl Live {
    fn push(&mut self, v: Value) {
        self.seq.insert(v, self.next);
        self.next += 1;
    }

    fn remove(&mut self, v: &Value) {
        self.seq.remove(v);
    }

    /// The live values among `candidates`, last defined first.
    fn latest_first(&self, candidates: impl Iterator<Item = Value>) -> Vec<Value> {
        let mut vs: Vec<(u32, Value)> = candidates
            .filter_map(|v| self.seq.get(&v).map(|n| (*n, v)))
            .collect();
        vs.sort_by_key(|(n, _)| std::cmp::Reverse(*n));
        vs.into_iter().map(|(_, v)| v).collect()
    }

    fn all_latest_first(&self) -> Vec<Value> {
        self.latest_first(self.seq.keys().copied())
    }
}

struct Ctx {
    tags: Tags,
    parents: HashMap<u32, u32>,
    /// The owners of each scope, in the order their markers were found.
    owners: HashMap<u32, Vec<Value>>,
    close: Option<FuncId>,
}

fn function(m: &Module, f: &mut Func, close: Option<FuncId>) -> Result<(), String> {
    let mut cx = Ctx {
        tags: HashMap::new(),
        parents: HashMap::new(),
        owners: HashMap::new(),
        close,
    };
    for b in &f.blocks {
        for i in &b.insts {
            match (i.op, i.imm) {
                (Op::ScopeBegin, Imm::Scope(s, parent)) => {
                    cx.parents.insert(s, parent);
                }
                (Op::ScopeOwn, Imm::Scope(s, policy)) => {
                    cx.tags.insert(i.args[0], (s, policy));
                    cx.owners.entry(s).or_default().push(i.args[0]);
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
    let mut entry: HashMap<usize, Live> = HashMap::new();
    let mut first = Live::default();
    for p in &f.blocks[0].params {
        if p.mode == Mode::Move && m.needs_drop(f.ty(p.value)) {
            first.push(p.value);
        }
    }
    entry.insert(0, first);
    for b in f.rpo() {
        let Some(mut live) = entry.get(&b.index()).cloned() else {
            continue;
        };
        let old = std::mem::take(&mut f.blocks[b.index()]);
        f.blocks[b.index()].params = old.params;
        let mut cur = b.index();
        for inst in old.insts {
            match (inst.op, inst.imm) {
                (Op::ScopeBegin | Op::ScopeOwn, _) => continue,
                (Op::ScopeEnd, Imm::Scope(scope, _)) => {
                    cur = exit(&cx, f, cur, &mut live, scope)?;
                    continue;
                }
                _ => {}
            }
            consume(m, f, &inst.args, &arg_modes(m, &inst), &mut live);
            if m.result_mode(f, &inst) == Some(Mode::Move)
                && let Some(r) = inst.res
            {
                live.push(r);
            }
            f.blocks[cur].insts.push(inst);
        }
        if let Term::Ret(Some(v)) = &old.term {
            live.remove(v);
        }
        old.term.for_each_target(|t| {
            let mut after = live.clone();
            let params = &f.blocks[t.block.index()].params;
            for (a, p) in t.args.iter().zip(params) {
                if p.mode == Mode::Move && m.needs_drop(f.ty(*a)) {
                    after.remove(a);
                }
            }
            for p in params {
                if p.mode == Mode::Move && m.needs_drop(f.ty(p.value)) {
                    after.push(p.value);
                }
            }
            entry.entry(t.block.index()).or_insert(after);
        });
        f.blocks[cur].term = old.term;
        f.blocks[cur].term_loc = old.term_loc;
    }
    Ok(())
}

fn consume(m: &Module, f: &Func, args: &[Value], modes: &[Mode], live: &mut Live) {
    for (a, mode) in args.iter().zip(modes) {
        if *mode == Mode::Move && m.needs_drop(f.ty(*a)) {
            live.remove(a);
        }
    }
}

fn push(
    f: &mut Func,
    at: usize,
    op: Op,
    args: &[Value],
    imm: Imm,
    ty: Option<Ty>,
) -> Option<Value> {
    let res = ty.map(|t| f.new_value(t));
    f.blocks[at].insts.push(Inst {
        op,
        args: args.to_vec(),
        imm,
        res,
        loc: Loc::NONE,
    });
    res
}

/// Closes or drops the live owners tagged `scope`, last defined first. Returns the first error.
fn cleanup(
    cx: &Ctx,
    f: &mut Func,
    at: usize,
    live: &mut Live,
    scope: u32,
    mut outcome: Option<Value>,
) -> Result<Option<Value>, String> {
    let owners = live.latest_first(cx.owners.get(&scope).into_iter().flatten().copied());
    for v in owners {
        live.remove(&v);
        if cx.tags[&v].1 == 0 {
            push(f, at, Op::Drop, &[v], Imm::None, None);
            continue;
        }
        let close = cx
            .close
            .ok_or_else(|| "a closing owner needs a `close` function".to_string())?;
        let code = push(f, at, Op::Call, &[v], Imm::Func(close), Some(Ty::INT)).expect("result");
        outcome = Some(match outcome {
            None => code,
            Some(first) => {
                let zero = push(f, at, Op::IConst, &[], Imm::Int(0), Some(Ty::INT)).expect("zero");
                let failed = push(
                    f,
                    at,
                    Op::ICmp,
                    &[first, zero],
                    Imm::Cc(Cc::Ne),
                    Some(Ty::BOOL),
                )
                .expect("flag");
                push(
                    f,
                    at,
                    Op::Select,
                    &[failed, first, code],
                    Imm::None,
                    Some(Ty::INT),
                )
                .expect("pick")
            }
        });
    }
    Ok(outcome)
}

/// The cleanup of `scope` at a `raw_end`. Returns the block to continue in.
fn exit(cx: &Ctx, f: &mut Func, cur: usize, live: &mut Live, scope: u32) -> Result<usize, String> {
    let outcome = cleanup(cx, f, cur, live, scope, None)?;
    let Some(first) = outcome else {
        return Ok(cur);
    };
    let zero = push(f, cur, Op::IConst, &[], Imm::Int(0), Some(Ty::INT)).expect("zero");
    let failed = push(
        f,
        cur,
        Op::ICmp,
        &[first, zero],
        Imm::Cc(Cc::Ne),
        Some(Ty::BOOL),
    )
    .expect("flag");
    let (err, cont) = (f.new_block(), f.new_block());
    f.blocks[cur].term = Term::CondBr {
        cond: failed,
        then: Target::to(err),
        els: Target::to(cont),
    };
    // The error edge: the enclosing scopes' cleanup, then what else is live, then return.
    let mut rest = live.clone();
    let mut outcome = Some(first);
    let mut at = err.index();
    let mut scope = cx
        .parents
        .get(&scope)
        .copied()
        .and_then(|p| p.checked_sub(1));
    while let Some(s) = scope {
        outcome = cleanup(cx, f, at, &mut rest, s, outcome)?;
        scope = cx.parents.get(&s).copied().and_then(|p| p.checked_sub(1));
    }
    for v in rest.all_latest_first() {
        push(f, at, Op::Drop, &[v], Imm::None, None);
    }
    f.blocks[at].term = Term::Ret(outcome);
    at = cont.index();
    Ok(at)
}
