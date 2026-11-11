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

use crate::ir::*;
use crate::types::Ty;
use crate::verify::arg_modes;
use std::collections::HashMap;

const BEGIN: &str = "msrt_raw_begin";
const OWN: &str = "msrt_raw_own";
const END: &str = "msrt_raw_end";

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
    for fi in 0..m.funcs.len() {
        let stand_in = Func::new("", Vec::new(), Ty::UNIT);
        let mut f = std::mem::replace(&mut m.funcs[fi], stand_in);
        let out = function(m, &mut f, &markers, close);
        m.funcs[fi] = f;
        out.map_err(|e| format!("{}: {e}", m.funcs[fi].name))?;
    }
    Ok(())
}

type Tags = HashMap<Value, (i64, i64)>;

struct Ctx {
    tags: Tags,
    parents: HashMap<i64, i64>,
    close: Option<FuncId>,
}

fn marker_of(markers: &HashMap<u32, Marker>, inst: &Inst) -> Option<Marker> {
    match (inst.op, inst.imm) {
        (Op::CallRt, Imm::Ext(e)) => markers.get(&(e.index() as u32)).copied(),
        _ => None,
    }
}

fn function(
    m: &Module,
    f: &mut Func,
    markers: &HashMap<u32, Marker>,
    close: Option<FuncId>,
) -> Result<(), String> {
    let mut consts: HashMap<Value, i64> = HashMap::new();
    for b in &f.blocks {
        for i in &b.insts {
            if let (Op::IConst, Imm::Int(n), Some(r)) = (i.op, i.imm, i.res) {
                consts.insert(r, n);
            }
        }
    }
    let konst = |v: &Value| {
        consts
            .get(v)
            .copied()
            .ok_or_else(|| "a marker operand is not an integer constant".to_string())
    };
    let mut cx = Ctx {
        tags: HashMap::new(),
        parents: HashMap::new(),
        close,
    };
    let mut any = false;
    for b in &f.blocks {
        for i in &b.insts {
            match marker_of(markers, i) {
                Some(Marker::Begin) => {
                    any = true;
                    cx.parents.insert(konst(&i.args[0])?, konst(&i.args[1])?);
                }
                Some(Marker::Own) => {
                    any = true;
                    cx.tags
                        .insert(i.args[0], (konst(&i.args[1])?, konst(&i.args[2])?));
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
    let mut entry: HashMap<usize, Vec<Value>> = HashMap::new();
    let first: Vec<Value> = f.blocks[0]
        .params
        .iter()
        .filter(|p| p.mode == Mode::Move && m.needs_drop(f.ty(p.value)))
        .map(|p| p.value)
        .collect();
    entry.insert(0, first);
    for b in f.rpo() {
        let Some(mut live) = entry.get(&b.index()).cloned() else {
            continue;
        };
        let old = std::mem::take(&mut f.blocks[b.index()]);
        f.blocks[b.index()].params = old.params;
        let mut cur = b.index();
        for inst in old.insts {
            match marker_of(markers, &inst) {
                Some(Marker::Begin | Marker::Own) => continue,
                Some(Marker::End) => {
                    let scope = konst(&inst.args[0])?;
                    cur = exit(&cx, f, cur, &mut live, scope)?;
                    continue;
                }
                None => {}
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
            live.retain(|x| x != v);
        }
        old.term.for_each_target(|t| {
            let mut after = live.clone();
            let params = &f.blocks[t.block.index()].params;
            for (a, p) in t.args.iter().zip(params) {
                if p.mode == Mode::Move && m.needs_drop(f.ty(*a)) {
                    after.retain(|x| x != a);
                }
            }
            after.extend(
                params
                    .iter()
                    .filter(|p| p.mode == Mode::Move && m.needs_drop(f.ty(p.value)))
                    .map(|p| p.value),
            );
            entry.entry(t.block.index()).or_insert(after);
        });
        f.blocks[cur].term = old.term;
        f.blocks[cur].term_loc = old.term_loc;
    }
    Ok(())
}

fn consume(m: &Module, f: &Func, args: &[Value], modes: &[Mode], live: &mut Vec<Value>) {
    for (a, mode) in args.iter().zip(modes) {
        if *mode == Mode::Move && m.needs_drop(f.ty(*a)) {
            live.retain(|x| x != a);
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
    live: &mut Vec<Value>,
    scope: i64,
    mut outcome: Option<Value>,
) -> Result<Option<Value>, String> {
    let owners: Vec<Value> = live
        .iter()
        .rev()
        .filter(|v| cx.tags.get(v).is_some_and(|t| t.0 == scope))
        .copied()
        .collect();
    for v in owners {
        live.retain(|x| *x != v);
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
fn exit(
    cx: &Ctx,
    f: &mut Func,
    cur: usize,
    live: &mut Vec<Value>,
    scope: i64,
) -> Result<usize, String> {
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
    let mut scope = cx.parents.get(&scope).copied();
    while let Some(s) = scope.filter(|s| *s >= 0) {
        outcome = cleanup(cx, f, at, &mut rest, s, outcome)?;
        scope = cx.parents.get(&s).copied();
    }
    for v in rest.iter().rev() {
        push(f, at, Op::Drop, &[*v], Imm::None, None);
    }
    f.blocks[at].term = Term::Ret(outcome);
    at = cont.index();
    Ok(at)
}
