//! Prototype of the state-machine transform (plan mechanism M2): a function that waits becomes a
//! frame type plus three functions, so a waiting task is one block and not a stack.
//!
//! For `fn f(params) -> R` that calls wait natives `w(args)`:
//!
//! ```text
//! f.start(params)  -> Frame          state 0, parameters saved
//! f.step(move Frame) -> Frame       runs from the saved state to the next wait or to the end
//! f.cancel(move Frame)              drops what the saved state owns; nothing else runs
//! ```
//!
//! A wait `r = call.rt @w(args)` becomes `tk = call.rt @w_begin(args)`, the values live after it
//! saved into the frame (state `k`, ticket `tk`), and a return of the frame. The scheduler calls
//! `step` again once the wait completes; state `k` starts by `r = call.rt @w_result(tk)`.
//!
//! The function is cloned per resume point: the code reachable from state `k` up to the next
//! waits is copied into `step`, with every value that crosses a wait reloaded from the frame. That
//! keeps SSA and the ownership rules intact without a new memory model. Frame slots are shared by
//! type across states, so the frame is as large as the busiest wait, not the sum of all of them.
//!
//! Prototype limits (each is a known item of the full change, see `w13/state-machine-plan.md`):
//! the function must be elaborated (no scope markers), a borrowed value of a type that needs a drop
//! may not live across a wait, at most 32 frame fields, no `depth`/`poll` ops, and only direct
//! calls to wait natives are waits (a call to another waiting function is not yet converted).

use crate::ir::*;
use crate::types::Ty;
use crate::types::TypeId;
use crate::verify::arg_modes;
use std::collections::{BTreeSet, HashMap, VecDeque};

/// What `convert` made.
#[derive(Debug)]
pub struct Machine {
    /// The frame type.
    pub frame: Ty,
    /// The frame's type declaration.
    pub frame_id: TypeId,
    /// `f.start`.
    pub start: FuncId,
    /// `f.step`.
    pub step: FuncId,
    /// `f.cancel`.
    pub cancel: FuncId,
    /// The frame state meaning finished; the result is in the `ret` field.
    pub done: i64,
    /// Per wait, in order of appearance: how many values it saves and how many of them it owns.
    pub saved: Vec<(usize, usize)>,
    /// Frame fields including the three fixed ones (`state`, `tk`, `ret`).
    pub fields: usize,
    /// Fields if every saved value of every wait had a field of its own (no sharing).
    pub fields_unshared: usize,
}

const STATE: u32 = 0;
const TK: u32 = 1;
const RET: u32 = 2;
const FIXED: u32 = 3;

type R<T> = Result<T, String>;

struct Site {
    block: usize,
    idx: usize,
    /// The block that continues after the wait (the wait ends `block`).
    cont: usize,
    ext: ExtId,
    /// Values live after the wait, not counting its result.
    live: Vec<u32>,
    /// The owned ones among them.
    owned: BTreeSet<u32>,
    /// Frame field of each live value in this state.
    slot: HashMap<u32, u32>,
}

fn is_wait(m: &Module, inst: &Inst, waits: &[&str]) -> Option<ExtId> {
    match (inst.op, inst.imm) {
        (Op::CallRt, Imm::Ext(e)) if waits.contains(&m.externs[e.index()].name.as_str()) => Some(e),
        _ => None,
    }
}

fn uses(i: &Inst, mut f: impl FnMut(u32)) {
    for a in &i.args {
        f(a.0);
    }
}

/// Liveness: for each block, the values live at its start (own parameters excluded).
fn live_in(f: &Func) -> Vec<BTreeSet<u32>> {
    let n = f.blocks.len();
    let mut li: Vec<BTreeSet<u32>> = vec![BTreeSet::new(); n];
    let mut changed = true;
    while changed {
        changed = false;
        for b in (0..n).rev() {
            let mut live = live_out(f, &li, b);
            for i in f.blocks[b].insts.iter().rev() {
                if let Some(r) = i.res {
                    live.remove(&r.0);
                }
                uses(i, |v| {
                    live.insert(v);
                });
            }
            for p in &f.blocks[b].params {
                live.remove(&p.value.0);
            }
            if live != li[b] {
                li[b] = live;
                changed = true;
            }
        }
    }
    li
}

fn live_out(f: &Func, li: &[BTreeSet<u32>], b: usize) -> BTreeSet<u32> {
    let mut live = BTreeSet::new();
    f.blocks[b].term.for_each_target(|t| {
        live.extend(li[t.block.index()].iter().copied());
    });
    f.blocks[b].term.for_each_use(|v| {
        live.insert(v.0);
    });
    live
}

/// The owned values held at the start of each block (the verifier makes them the same on every edge).
fn owned_in(m: &Module, f: &Func) -> Vec<Option<BTreeSet<u32>>> {
    let owned = |v: Value| m.needs_drop(f.ty(v));
    let mut entry: Vec<Option<BTreeSet<u32>>> = vec![None; f.blocks.len()];
    let mut first = BTreeSet::new();
    for p in &f.blocks[0].params {
        if p.mode == Mode::Move && owned(p.value) {
            first.insert(p.value.0);
        }
    }
    entry[0] = Some(first);
    for b in f.rpo() {
        let bi = b.index();
        let Some(mut live) = entry[bi].clone() else {
            continue;
        };
        if bi != 0 {
            for p in &f.blocks[bi].params {
                if p.mode == Mode::Move && owned(p.value) {
                    live.insert(p.value.0);
                }
            }
        }
        for i in &f.blocks[bi].insts {
            step_owned(m, f, i, &mut live);
        }
        let term = &f.blocks[bi].term;
        if let Term::Ret(Some(v)) = term {
            live.remove(&v.0);
        }
        term.for_each_target(|t| {
            let mut e = live.clone();
            for (a, p) in t.args.iter().zip(&f.blocks[t.block.index()].params) {
                if p.mode == Mode::Move {
                    e.remove(&a.0);
                }
            }
            if entry[t.block.index()].is_none() {
                entry[t.block.index()] = Some(e);
            }
        });
    }
    entry
}

fn step_owned(m: &Module, f: &Func, i: &Inst, live: &mut BTreeSet<u32>) {
    let modes = arg_modes(m, f, i);
    for (a, mode) in i.args.iter().zip(&modes) {
        if *mode == Mode::Move {
            live.remove(&a.0);
        }
    }
    if let Some(r) = i.res
        && m.result_mode(f, i) == Some(Mode::Move)
        && m.needs_drop(f.ty(r))
    {
        live.insert(r.0);
    }
}

fn emit(f: &mut Func, b: Block, op: Op, args: &[Value], imm: Imm, ty: Option<Ty>) -> Option<Value> {
    let res = ty.map(|t| f.new_value(t));
    f.blocks[b.index()].insts.push(Inst {
        op,
        args: args.to_vec(),
        imm,
        res,
        loc: Loc::NONE,
    });
    res
}

struct Ctx {
    frame_id: TypeId,
    frame: Ty,
    field_ty: Vec<Ty>,
    ret_ty: Ty,
}

/// Builds the frame of `site` (or of the entry, or of the end) in `b` and returns it.
fn build_frame(
    cx: &Ctx,
    nf: &mut Func,
    b: Block,
    head: (i64, Option<Value>, Option<Value>),
    saved: &[(u32, Value, u32)],
) -> Value {
    let (state, tk, ret) = head;
    let mut vals: Vec<Option<Value>> = vec![None; cx.field_ty.len()];
    vals[STATE as usize] = emit(nf, b, Op::IConst, &[], Imm::Int(state), Some(Ty::INT));
    vals[TK as usize] = Some(match tk {
        Some(t) => t,
        None => emit(nf, b, Op::IConst, &[], Imm::Int(0), Some(Ty::INT)).unwrap(),
    });
    vals[RET as usize] = ret;
    for (_, v, slot) in saved {
        vals[*slot as usize] = Some(*v);
    }
    let args: Vec<Value> = (0..cx.field_ty.len())
        .map(|i| match vals[i] {
            Some(v) => v,
            None => emit(nf, b, Op::Undef, &[], Imm::None, Some(cx.field_ty[i])).unwrap(),
        })
        .collect();
    emit(
        nf,
        b,
        Op::TypeNew,
        &args,
        Imm::Type(cx.frame_id),
        Some(cx.frame),
    )
    .unwrap()
}

/// Loads the saved values of one state out of `frame` and releases the frame block.
/// Returns the new value of each live value, in the order of `site.live`.
fn load_state(
    m: &Module,
    cx: &Ctx,
    nf: &mut Func,
    b: Block,
    frame: Value,
    orig: &Func,
    st: (&[u32], &HashMap<u32, u32>, &BTreeSet<u32>),
) -> (Vec<Value>, Value) {
    let (live, slot, owned) = st;
    let mut out = Vec::new();
    let mut moved: u32 = 0;
    let tk = emit(
        nf,
        b,
        Op::TypeGet,
        &[frame],
        Imm::Field(cx.frame_id, TK),
        Some(Ty::INT),
    )
    .unwrap();
    for v in live {
        let s = slot[v];
        let ty = orig.values[*v as usize];
        let g = emit(
            nf,
            b,
            Op::TypeGet,
            &[frame],
            Imm::Field(cx.frame_id, s),
            Some(ty),
        )
        .unwrap();
        if owned.contains(v) {
            moved |= 1 << s;
            out.push(emit(nf, b, Op::MoveOut, &[g], Imm::None, Some(ty)).unwrap());
        } else {
            out.push(g);
        }
    }
    // Fields that hold no owned value of this state are zero and own nothing; mark every field that
    // can own something as taken so the release frees the block and nothing else.
    for (i, t) in cx.field_ty.iter().enumerate() {
        if m.needs_drop(*t) {
            moved |= 1 << i;
        }
    }
    emit(
        nf,
        b,
        Op::TypeRelease,
        &[frame],
        Imm::TypeMask(cx.frame_id, moved),
        None,
    );
    (out, tk)
}

/// Converts `fid`; `waits` names the runtime functions that wait (`@w` gets `@w_begin` and
/// `@w_result`, which the caller supplies to the runtime or the test host).
pub fn convert(m: &mut Module, fid: FuncId, waits: &[&str]) -> R<Machine> {
    let mut f = m.funcs[fid.index()].clone();
    if crate::verify::is_raw(&f) {
        return Err("function still has scope markers (run after elaborate)".into());
    }
    reject_unsupported(&f)?;
    split_at_waits(m, &mut f, waits);
    let li = live_in(&f);
    let oi = owned_in(m, &f);

    // The waits, with what is live and owned at each.
    let mut sites: Vec<Site> = Vec::new();
    for (bi, blk) in f.blocks.iter().enumerate() {
        let Some(mut own) = oi[bi].clone() else {
            continue;
        };
        if bi != 0 {
            for p in &blk.params {
                if p.mode == Mode::Move && m.needs_drop(f.ty(p.value)) {
                    own.insert(p.value.0);
                }
            }
        }
        for (ii, inst) in blk.insts.iter().enumerate() {
            let w = is_wait(m, inst, waits);
            step_owned(m, &f, inst, &mut own);
            let Some(ext) = w else { continue };
            if let Some(r) = inst.res {
                own.remove(&r.0);
            }
            let mut live = live_out(&f, &li, bi);
            for j in (ii + 1..blk.insts.len()).rev() {
                let i = &blk.insts[j];
                if let Some(r) = i.res {
                    live.remove(&r.0);
                }
                uses(i, |v| {
                    live.insert(v);
                });
            }
            if let Some(r) = inst.res {
                live.remove(&r.0);
            }
            for v in &live {
                let ty = f.values[*v as usize];
                if m.needs_drop(ty) && !own.contains(v) {
                    return Err(format!(
                        "borrowed value %{v} of an owning type lives across a wait in {}",
                        f.name
                    ));
                }
            }
            let owned: BTreeSet<u32> = own.iter().copied().filter(|v| live.contains(v)).collect();
            if own.iter().any(|v| !live.contains(v)) {
                return Err(format!(
                    "an owned value is held across a wait but never used again in {}",
                    f.name
                ));
            }
            let Term::Br(ct) = &blk.term else {
                return Err("internal: wait not followed by a branch".into());
            };
            sites.push(Site {
                block: bi,
                idx: ii,
                cont: ct.block.index(),
                ext,
                live: live.into_iter().collect(),
                owned,
                slot: HashMap::new(),
            });
        }
    }
    if sites.is_empty() {
        return Err("function has no wait".into());
    }

    // State 0 saves the parameters.
    let params: Vec<u32> = f.blocks[0].params.iter().map(|p| p.value.0).collect();
    let param_owned: BTreeSet<u32> = f.blocks[0]
        .params
        .iter()
        .filter(|p| p.mode == Mode::Move && m.needs_drop(f.ty(p.value)))
        .map(|p| p.value.0)
        .collect();
    for p in &f.blocks[0].params {
        if p.mode != Mode::Move && m.needs_drop(f.ty(p.value)) {
            return Err(
                "a borrowed owning parameter of a waiting function is not supported yet".into(),
            );
        }
    }
    let mut state0 = Site {
        block: 0,
        idx: 0,
        cont: 0,
        ext: sites[0].ext,
        live: params.clone(),
        owned: param_owned,
        slot: HashMap::new(),
    };

    // Slots: per type, the i-th value of a state takes the i-th slot of that type.
    let mut pool: Vec<(Ty, u32)> = Vec::new(); // (type, field index) in creation order
    let mut field_ty = vec![
        Ty::INT,
        Ty::INT,
        if f.ret == Ty::VOID { Ty::INT } else { f.ret },
    ];
    let mut assign = |site: &mut Site, f: &Func, field_ty: &mut Vec<Ty>| {
        let mut used: HashMap<Ty, usize> = HashMap::new();
        for v in &site.live {
            let ty = f.values[*v as usize];
            let k = used.entry(ty).or_insert(0);
            let existing: Vec<u32> = pool
                .iter()
                .filter(|(t, _)| *t == ty)
                .map(|(_, i)| *i)
                .collect();
            let idx = if *k < existing.len() {
                existing[*k]
            } else {
                field_ty.push(ty);
                let i = field_ty.len() as u32 - 1;
                pool.push((ty, i));
                i
            };
            *k += 1;
            site.slot.insert(*v, idx);
        }
    };
    assign(&mut state0, &f, &mut field_ty);
    for s in sites.iter_mut() {
        assign(s, &f, &mut field_ty);
    }
    if field_ty.len() > 32 {
        return Err("frame has more than 32 fields".into());
    }
    let unshared =
        FIXED as usize + params.len() + sites.iter().map(|s| s.live.len()).sum::<usize>();

    let frame_name = format!("{}.frame", f.name);
    let fields: Vec<(String, Ty)> = field_ty
        .iter()
        .enumerate()
        .map(|(i, t)| {
            let n = match i as u32 {
                STATE => "state".to_string(),
                TK => "tk".to_string(),
                RET => "ret".to_string(),
                _ => format!("s{i}"),
            };
            (n, *t)
        })
        .collect();
    let (frame_id, frame) = m.add_type(&frame_name, fields);
    let cx = Ctx {
        frame_id,
        frame,
        field_ty: field_ty.clone(),
        ret_ty: f.ret,
    };
    let done: i64 = -1;

    // Externs: begin and result for each wait native.
    let mut begin: HashMap<usize, ExtId> = HashMap::new();
    let mut result: HashMap<usize, ExtId> = HashMap::new();
    for s in &sites {
        let e = s.ext;
        if begin.contains_key(&e.index()) {
            continue;
        }
        let d = m.externs[e.index()].clone();
        let mut b = d.clone();
        b.name = format!("{}_begin", d.name);
        b.ret = Ty::INT;
        b.fresh = true;
        begin.insert(e.index(), m.add_extern(b));
        let mut r = d.clone();
        r.name = format!("{}_result", d.name);
        r.params = vec![Param {
            ty: Ty::INT,
            mode: Mode::Borrow,
        }];
        result.insert(e.index(), m.add_extern(r));
    }

    // start.
    let mut start = Func::new(&format!("{}.start", f.name), f.params.clone(), frame);
    {
        let ps: Vec<Value> = start.blocks[0].params.iter().map(|p| p.value).collect();
        let saved: Vec<(u32, Value, u32)> = params
            .iter()
            .zip(&ps)
            .map(|(v, nv)| (*v, *nv, state0.slot[v]))
            .collect();
        let fr = build_frame(&cx, &mut start, Block(0), (0, None, None), &saved);
        start.blocks[0].term = Term::Ret(Some(fr));
    }
    let start_id = m.add_func(start);

    // step.
    let mut step = Func::new(
        &format!("{}.step", f.name),
        vec![Param {
            ty: frame,
            mode: Mode::Move,
        }],
        frame,
    );
    let frame_in = step.blocks[0].params[0].value;
    let mut cases: Vec<(i64, Target)> = Vec::new();
    // Each region: (state number, live set, slots, owned, tail start).
    for state in 0..=sites.len() {
        let (site_live, site_slot, site_owned): (Vec<u32>, HashMap<u32, u32>, BTreeSet<u32>) =
            if state == 0 {
                (
                    state0.live.clone(),
                    state0.slot.clone(),
                    state0.owned.clone(),
                )
            } else {
                let s = &sites[state - 1];
                (s.live.clone(), s.slot.clone(), s.owned.clone())
            };
        let load = step.new_block();
        cases.push((state as i64, Target::to(load)));
        let (loaded, ticket) = load_state(
            m,
            &cx,
            &mut step,
            load,
            frame_in,
            &f,
            (&site_live, &site_slot, &site_owned),
        );
        let mut map: HashMap<u32, Value> = site_live
            .iter()
            .copied()
            .zip(loaded.iter().copied())
            .collect();
        let mut bmap: HashMap<usize, Block> = HashMap::new();
        let mut queue: VecDeque<usize> = VecDeque::new();
        // Where the region starts.
        let (first_block, skip) = if state == 0 {
            (0usize, 0usize)
        } else {
            (sites[state - 1].cont, 0)
        };
        let tail = step.new_block();
        let (tail_blk, tail_params): (Block, Vec<Value>) = if state == 0 {
            // The entry block keeps its parameters; they are the loaded values.
            let mut ps = Vec::new();
            for p in &f.blocks[0].params {
                let nv = step.new_value(f.ty(p.value));
                step.blocks[tail.index()].params.push(BlockParam {
                    value: nv,
                    mode: p.mode,
                });
                ps.push(nv);
            }
            (tail, ps)
        } else {
            (tail, Vec::new())
        };
        step.blocks[load.index()].term = Term::Br(Target {
            block: tail_blk,
            args: if state == 0 {
                loaded.clone()
            } else {
                Vec::new()
            },
        });
        if state == 0 {
            for (p, nv) in f.blocks[0].params.iter().zip(&tail_params) {
                map.insert(p.value.0, *nv);
            }
        }
        // `map` holds live-ins; state-0 params are rebound to the tail block's own parameters.
        let mut work: Vec<(usize, Block, usize)> = vec![(first_block, tail_blk, skip)];
        bmap.insert(usize::MAX, tail_blk);
        if state != 0 {
            let t = ticket;
            let s = &sites[state - 1];
            let orig_inst = &f.blocks[s.block].insts[s.idx];
            let rty = orig_inst.res.map(|r| f.ty(r)).unwrap_or(Ty::VOID);
            let rv = emit(
                &mut step,
                tail_blk,
                Op::CallRt,
                &[t],
                Imm::Ext(result[&s.ext.index()]),
                Some(rty),
            )
            .unwrap();
            if let Some(r) = orig_inst.res {
                map.insert(r.0, rv);
            }
        }
        let mut done_blocks: HashMap<(usize, usize), Block> = HashMap::new();
        done_blocks.insert((first_block, skip), tail_blk);
        // Clone reachable blocks.
        let mut pending: VecDeque<(usize, Block, usize)> = work.drain(..).collect();
        while let Some((ob, nb, from)) = pending.pop_front() {
            let src = &f.blocks[ob];
            if !(state == 0 && from == 0 && ob == 0) {
                // Params of a full-block clone are set when the block is created below.
            }
            let mut cut = false;
            for (ii, inst) in src.insts.iter().enumerate().skip(from) {
                if let Some(wext) = is_wait(m, inst, waits)
                    && let Some(k) = sites.iter().position(|s| s.block == ob && s.idx == ii)
                {
                    let s = &sites[k];
                    let args: Vec<Value> = inst.args.iter().map(|a| map[&a.0]).collect();
                    let tk = emit(
                        &mut step,
                        nb,
                        Op::CallRt,
                        &args,
                        Imm::Ext(begin[&wext.index()]),
                        Some(Ty::INT),
                    )
                    .unwrap();
                    let saved: Vec<(u32, Value, u32)> =
                        s.live.iter().map(|v| (*v, map[v], s.slot[v])).collect();
                    let fr =
                        build_frame(&cx, &mut step, nb, (k as i64 + 1, Some(tk), None), &saved);
                    step.blocks[nb.index()].term = Term::Ret(Some(fr));
                    cut = true;
                    break;
                }
                let args: Vec<Value> = inst.args.iter().map(|a| map[&a.0]).collect();
                let res = inst.res.map(|r| step.new_value(f.ty(r)));
                if let (Some(r), Some(nr)) = (inst.res, res) {
                    map.insert(r.0, nr);
                }
                step.blocks[nb.index()].insts.push(Inst {
                    op: inst.op,
                    args,
                    imm: inst.imm,
                    res,
                    loc: inst.loc,
                });
            }
            if cut {
                continue;
            }
            let mut term = src.term.clone();
            let mut map_target =
                |t: &mut Target,
                 step: &mut Func,
                 map: &mut HashMap<u32, Value>,
                 pending: &mut VecDeque<(usize, Block, usize)>| {
                    let tb = t.block.index();
                    let nb2 = *done_blocks.entry((tb, 0)).or_insert_with(|| {
                        let nb2 = step.new_block();
                        for p in &f.blocks[tb].params {
                            let nv = step.new_value(f.ty(p.value));
                            step.blocks[nb2.index()].params.push(BlockParam {
                                value: nv,
                                mode: p.mode,
                            });
                            map.insert(p.value.0, nv);
                        }
                        pending.push_back((tb, nb2, 0));
                        nb2
                    });
                    t.block = nb2;
                    for a in t.args.iter_mut() {
                        *a = map[&a.0];
                    }
                };
            match &mut term {
                Term::Ret(v) => {
                    let rv = v.map(|v| map[&v.0]);
                    let ret = if f.ret == Ty::VOID { None } else { rv };
                    let fr = build_frame(&cx, &mut step, nb, (done, None, ret), &[]);
                    step.blocks[nb.index()].term = Term::Ret(Some(fr));
                    continue;
                }
                Term::Br(t) => map_target(t, &mut step, &mut map, &mut pending),
                Term::CondBr { cond, then, els } => {
                    *cond = map[&cond.0];
                    map_target(then, &mut step, &mut map, &mut pending);
                    map_target(els, &mut step, &mut map, &mut pending);
                }
                Term::Switch {
                    value,
                    cases,
                    default,
                } => {
                    *value = map[&value.0];
                    for (_, t) in cases.iter_mut() {
                        map_target(t, &mut step, &mut map, &mut pending);
                    }
                    map_target(default, &mut step, &mut map, &mut pending);
                }
                Term::Fault(_) | Term::Unreachable => {}
            }
            step.blocks[nb.index()].term = term;
        }
        let _ = (&mut bmap, &mut queue);
    }
    // Dispatcher.
    let disp = step.new_block();
    let st = emit(
        &mut step,
        disp,
        Op::TypeGet,
        &[frame_in],
        Imm::Field(frame_id, STATE),
        Some(Ty::INT),
    )
    .unwrap();
    // `load` blocks read the frame, which is still owned here: the dispatcher borrows it.
    let bad = step.new_block();
    step.blocks[bad.index()].term = Term::Unreachable;
    step.blocks[disp.index()].term = Term::Switch {
        value: st,
        cases,
        default: Target::to(bad),
    };
    // Make the dispatcher the entry: swap block 0 (which holds the parameter) with `disp`.
    swap_entry(&mut step, disp);
    let step_id = m.add_func(step);

    // cancel.
    let mut cancel = Func::new(
        &format!("{}.cancel", f.name),
        vec![Param {
            ty: frame,
            mode: Mode::Move,
        }],
        Ty::VOID,
    );
    {
        let frame_in = cancel.blocks[0].params[0].value;
        let st = emit(
            &mut cancel,
            Block(0),
            Op::TypeGet,
            &[frame_in],
            Imm::Field(frame_id, STATE),
            Some(Ty::INT),
        )
        .unwrap();
        let mut cases = Vec::new();
        let bad = cancel.new_block();
        cancel.blocks[bad.index()].term = Term::Unreachable;
        let end = cancel.new_block();
        cancel.blocks[end.index()].term = Term::Ret(None);
        let mut all: Vec<(i64, &Site)> = vec![(0, &state0)];
        for (k, s) in sites.iter().enumerate() {
            all.push((k as i64 + 1, s));
        }
        for (n, s) in all {
            let b = cancel.new_block();
            cases.push((n, Target::to(b)));
            let owned_live: Vec<u32> = s
                .live
                .iter()
                .copied()
                .filter(|v| s.owned.contains(v))
                .collect();
            let (loaded, _) = load_state(
                m,
                &cx,
                &mut cancel,
                b,
                frame_in,
                &f,
                (&s.live, &s.slot, &s.owned),
            );
            for (v, nv) in s.live.iter().zip(&loaded) {
                if owned_live.contains(v) {
                    emit(&mut cancel, b, Op::Drop, &[*nv], Imm::None, None);
                }
            }
            cancel.blocks[b.index()].term = Term::Br(Target::to(end));
        }
        // Finished: only the result can be owned.
        let b = cancel.new_block();
        cases.push((done, Target::to(b)));
        let mut moved: u32 = 0;
        for (i, t) in cx.field_ty.iter().enumerate() {
            if m.needs_drop(*t) {
                moved |= 1 << i;
            }
        }
        if m.needs_drop(cx.ret_ty) {
            let g = emit(
                &mut cancel,
                b,
                Op::TypeGet,
                &[frame_in],
                Imm::Field(frame_id, RET),
                Some(cx.ret_ty),
            )
            .unwrap();
            let mv = emit(
                &mut cancel,
                b,
                Op::MoveOut,
                &[g],
                Imm::None,
                Some(cx.ret_ty),
            )
            .unwrap();
            emit(
                &mut cancel,
                b,
                Op::TypeRelease,
                &[frame_in],
                Imm::TypeMask(frame_id, moved),
                None,
            );
            emit(&mut cancel, b, Op::Drop, &[mv], Imm::None, None);
        } else {
            emit(
                &mut cancel,
                b,
                Op::TypeRelease,
                &[frame_in],
                Imm::TypeMask(frame_id, moved),
                None,
            );
        }
        cancel.blocks[b.index()].term = Term::Br(Target::to(end));
        cancel.blocks[Block(0).index()].term = Term::Switch {
            value: st,
            cases,
            default: Target::to(bad),
        };
    }
    let cancel_id = m.add_func(cancel);

    Ok(Machine {
        frame,
        frame_id,
        start: start_id,
        step: step_id,
        cancel: cancel_id,
        done,
        saved: sites
            .iter()
            .map(|s| (s.live.len(), s.owned.len()))
            .collect(),
        fields: field_ty.len(),
        fields_unshared: unshared,
    })
}

/// Makes `disp` block 0 by exchanging it with the current entry block, keeping parameters in place.
fn swap_entry(f: &mut Func, disp: Block) {
    let n = f.blocks.len();
    let d = disp.index();
    // Move the parameters of block 0 onto the dispatcher, then swap the two blocks' contents and
    // renumber every target that named either one.
    let params = std::mem::take(&mut f.blocks[0].params);
    f.blocks[d].params = params;
    f.blocks.swap(0, d);
    let fix = |b: Block| -> Block {
        if b.index() == 0 {
            Block(d as u32)
        } else if b.index() == d {
            Block(0)
        } else {
            b
        }
    };
    for bi in 0..n {
        f.blocks[bi]
            .term
            .for_each_target_mut(|t| t.block = fix(t.block));
    }
}

/// Ops whose ownership or address rules the prototype does not model: a function using one is
/// refused instead of converted wrongly. Each is a named item of the in-place form.
fn reject_unsupported(f: &Func) -> R<()> {
    for i in f.blocks.iter().flat_map(|b| &b.insts) {
        let why = match i.op {
            Op::Slot | Op::Load | Op::Take | Op::Store | Op::Put => {
                "memory slots (addresses into the frame)"
            }
            Op::MoveOut | Op::TypeFill | Op::ListFill | Op::AltTake | Op::ListTake => {
                "moved-out fields (holes)"
            }
            Op::DepthEnter | Op::DepthLeave => "stack-depth guard",
            Op::CleanupPush | Op::CleanupRun => "the cleanup stack",
            Op::Poll => "cancellation polls",
            _ => continue,
        };
        return Err(format!("{}: {} are not supported yet", f.name, why));
    }
    Ok(())
}

/// Ends the block of every wait at the wait: the rest of the block moves to a new block that the
/// first one branches to. A resume then starts at a block boundary, so each block is cloned once
/// per resume point and every value keeps one definition in it.
fn split_at_waits(m: &Module, f: &mut Func, waits: &[&str]) {
    let mut conts: std::collections::HashSet<usize> = Default::default();
    let mut bi = 0;
    while bi < f.blocks.len() {
        let at = f.blocks[bi]
            .insts
            .iter()
            .position(|i| is_wait(m, i, waits).is_some());
        let done = at.is_some_and(|ii| {
            ii + 1 == f.blocks[bi].insts.len()
                && matches!(&f.blocks[bi].term, Term::Br(t) if conts.contains(&t.block.index()))
        });
        if let (Some(ii), false) = (at, done) {
            let c = f.new_block();
            let rest: Vec<Inst> = f.blocks[bi].insts.split_off(ii + 1);
            let term = std::mem::replace(&mut f.blocks[bi].term, Term::Br(Target::to(c)));
            f.blocks[c.index()].insts = rest;
            f.blocks[c.index()].term = term;
            f.blocks[c.index()].term_loc = f.blocks[bi].term_loc;
            conts.insert(c.index());
            // Blocks that branched with arguments keep targeting the original block.
        }
        bi += 1;
    }
}
