//! Sorts of word lists by a known, capture-free comparator, compiled with the program.
//!
//! The runtime sort calls its comparator through a pointer once per comparison, which keeps
//! the comparator from being inlined. When the comparator is a closure the module already
//! knows (see `inline::specialize_sort_thunks`), the call to `msrt_list_sorted` is replaced
//! by a copy of the list and a call to a generated driftsort that calls the closure's code
//! directly, so the backend can inline it into the sort loops.
//!
//! The generated sort is stable, like the runtime's, which is its whole contract: equal elements
//! keep their order. It calls a comparator with effects in a different order than the runtime
//! sort does. Slots move as bits and the scratch list owns nothing, so a comparator that exits
//! early never leaves an owner duplicated.

use crate::builder::{FuncBuilder, Var};
use crate::ir::{
    Block, Cc, ExternDef, ExternRole, Func, FuncId, FuncKind, Imm, Inst, Mode, Module, Op, Param,
    SortThunk, Term, Value,
};
use crate::types::{Ty, TyKind};
use crate::vmap::ValueMap;
use std::collections::HashMap;

/// Largest slice the fallback merge sort handles by insertion.
const INSERTION_MAX: i64 = 12;

/// Replaces runtime sorts that have a known comparator; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    let mut made: HashMap<FuncId, FuncId> = HashMap::new();
    for fi in 0..m.funcs.len() {
        let mut known: ValueMap<FuncId> = ValueMap::new();
        let mut thunks: ValueMap<FuncId> = ValueMap::new();
        for inst in m.funcs[fi].blocks.iter().flat_map(|b| b.insts.iter()) {
            match (inst.op, inst.imm, inst.res) {
                (Op::ClosureNew, Imm::Func(g), Some(r)) if inst.args.is_empty() => {
                    known.insert(r, g);
                }
                (Op::FuncAddr, Imm::Func(t), Some(r))
                    if m.funcs[t.index()].sort == SortThunk::Specialized =>
                {
                    thunks.insert(r, t);
                }
                _ => {}
            }
        }
        if known.is_empty() || thunks.is_empty() {
            continue;
        }
        let mut sites = Vec::new();
        for (bi, b) in m.funcs[fi].blocks.iter().enumerate() {
            for (ii, inst) in b.insts.iter().enumerate() {
                if inst.op != Op::CallRt || inst.args.len() != 4 {
                    continue;
                }
                let Imm::Ext(e) = inst.imm else { continue };
                if m.externs[e.index()].role != ExternRole::ListSorted {
                    continue;
                }
                let (Some(&t), Some(&g)) = (thunks.get(&inst.args[2]), known.get(&inst.args[3]))
                else {
                    continue;
                };
                if let Some(elem) = word_elem(m, t, g) {
                    sites.push((bi, ii, g, elem));
                }
            }
        }
        // Last first, so each rewrite leaves the earlier indices valid.
        for (bi, ii, g, elem) in sites.into_iter().rev() {
            if elem == Ty::INT
                && let Some(desc) = plain_int_order(m, g)
            {
                let ext = m.add_extern(ExternDef {
                    name: "msrt_list_sort_ints".to_string(),
                    params: vec![
                        Param {
                            ty: m.funcs[fi].values
                                [m.funcs[fi].blocks[bi].insts[ii].args[0].index()],
                            mode: Mode::Borrow,
                        },
                        Param {
                            ty: Ty::INT,
                            mode: Mode::Borrow,
                        },
                    ],
                    ret: Ty::UNIT,
                    noreturn: false,
                    pure_: false,
                    fresh: false,
                    role: ExternRole::ListSortInts,
                    leaf: true,
                    reads: false,
                });
                rewrite_plain(&mut m.funcs[fi], bi, ii, ext, desc);
                changed = true;
                continue;
            }
            if elem == Ty::INT
                && let Some(desc) = difference_order(m, g)
            {
                let call = &m.funcs[fi].blocks[bi].insts[ii];
                let Imm::Ext(e) = call.imm else { continue };
                let mut def = m.externs[e.index()].clone();
                def.name = "msrt_list_sorted_by_difference".to_string();
                def.role = ExternRole::ListSortedByDifference;
                def.params.push(Param {
                    ty: Ty::INT,
                    mode: Mode::Borrow,
                });
                let ext = m.add_extern(def);
                let f = &mut m.funcs[fi];
                let flag = f.new_value(Ty::INT);
                let loc = f.blocks[bi].insts[ii].loc;
                let call = &mut f.blocks[bi].insts[ii];
                call.imm = Imm::Ext(ext);
                call.args.push(flag);
                f.blocks[bi].insts.insert(
                    ii,
                    Inst {
                        op: Op::IConst,
                        args: vec![],
                        imm: Imm::Int(desc as i64),
                        res: Some(flag),
                        loc,
                    },
                );
                changed = true;
                continue;
            }
            let sort = *made.entry(g).or_insert_with(|| build_drift(m, g, elem));
            if m.needs_drop(elem) {
                let ext = shadow_externs(m, fi, bi, ii);
                rewrite_owned(&mut m.funcs[fi], bi, ii, sort, elem, ext);
            } else {
                rewrite(&mut m.funcs[fi], bi, ii, sort, elem);
            }
            changed = true;
        }
    }
    changed
}

/// The element type when the sort is over plain-data values (words or types that own nothing) and `g` has the shape
/// `(env, elem, elem) -> int`.
fn word_elem(m: &Module, thunk: FuncId, g: FuncId) -> Option<Ty> {
    let code = &m.funcs[g.index()];
    let elem = m.funcs[thunk.index()]
        .blocks
        .iter()
        .flat_map(|b| b.insts.iter())
        .find_map(|i| match (i.op, i.imm) {
            (Op::Load, Imm::Ty(t)) => Some(t),
            _ => None,
        })?;
    let shaped = matches!(code.kind, FuncKind::Closure { .. })
        && code.params.len() == 3
        && code.params[0].ty == Ty::PTR
        && code.params[1].ty == elem
        && code.params[2].ty == elem
        && code.ret == Ty::INT;
    let plain =
        elem == Ty::INT || elem == Ty::FLOAT || matches!(m.types.kind(elem), TyKind::Type(_));
    (shaped && plain).then_some(elem)
}

/// The function that decides `g(env, a, b)` and its two element parameters: a closure that
/// only forwards its two arguments to a named function is that function.
fn comparator(m: &Module, g: FuncId) -> Option<(&Func, Value, Value)> {
    let closure = &m.funcs[g.index()];
    let (g, skip) = match (
        closure.blocks.as_slice(),
        closure.blocks[0].params.as_slice(),
    ) {
        ([only], [_, p, q]) => match (only.insts.as_slice(), &only.term) {
            ([call], Term::Ret(Some(r)))
                if call.op == Op::Call
                    && call.res == Some(*r)
                    && call.args == [p.value, q.value] =>
            {
                let Imm::Func(h) = call.imm else { return None };
                (&m.funcs[h.index()], 0)
            }
            _ => (closure, 1),
        },
        _ => return None,
    };
    let [a, b] = &g.blocks[0].params[skip..] else {
        return None;
    };
    Some((g, a.value, b.value))
}

/// Whether `g(env, a, b)` for `Int`s is exactly `a - b` (`Some(false)`) or `b - a`
/// (`Some(true)`), checked for overflow: a single block that subtracts one argument from the
/// other and returns the difference.
fn difference_order(m: &Module, g: FuncId) -> Option<bool> {
    let (g, a, b) = comparator(m, g)?;
    let [only] = g.blocks.as_slice() else {
        return None;
    };
    let mut sub = only
        .insts
        .iter()
        .filter(|i| !matches!(i.op, Op::DepthEnter | Op::DepthLeave));
    let (Some(i), None, Term::Ret(Some(r))) = (sub.next(), sub.next(), &only.term) else {
        return None;
    };
    if i.op != Op::ISubChk || i.res != Some(*r) {
        return None;
    }
    match i.args.as_slice() {
        [x, y] if (*x, *y) == (a, b) => Some(false),
        [x, y] if (*x, *y) == (b, a) => Some(true),
        _ => None,
    }
}

/// Whether `g(env, a, b)` for `Int`s is exactly "a before b" (`Some(false)`) or "b before a"
/// (`Some(true)`), where "before" means a negative result.
///
/// The body may only compare the two arguments with each other, branch or select on those
/// comparisons and return constants, so its result depends on nothing but the ordering of `a` and `b` and
/// trying the three orderings decides every input. Anything else (arithmetic, calls, a
/// comparison against a constant) yields `None`.
fn plain_int_order(m: &Module, g: FuncId) -> Option<bool> {
    let (g, a, b) = comparator(m, g)?;
    let negative = |x: i64, y: i64| -> Option<bool> {
        // `Err` marks the two arguments, which may only be compared with each other.
        #[derive(Clone, Copy)]
        enum V {
            Arg(i64),
            Num(i64),
            // An argument boxed into a `Comparable` value, and the pointer to its payload.
            Boxed(i64),
            Payload(i64),
        }
        let mut env: ValueMap<V> = ValueMap::new();
        env.insert(a, V::Arg(x));
        env.insert(b, V::Arg(y));
        let mut block = 0usize;
        for _ in 0..64 {
            let bd = &g.blocks[block];
            for inst in &bd.insts {
                let (res, v) = match (inst.op, inst.imm) {
                    (Op::IConst, Imm::Int(i)) => (inst.res?, V::Num(i)),
                    (Op::Clone, _) => (inst.res?, *env.get(inst.args.first()?)?),
                    (Op::ICmp, Imm::Cc(cc)) => {
                        let (l, r) =
                            match (env.get(inst.args.first()?)?, env.get(inst.args.get(1)?)?) {
                                (V::Arg(l), V::Arg(r)) | (V::Num(l), V::Num(r)) => (*l, *r),
                                _ => return None,
                            };
                        let t = match cc {
                            Cc::Eq => l == r,
                            Cc::Ne => l != r,
                            Cc::Lt => l < r,
                            Cc::Le => l <= r,
                            Cc::Gt => l > r,
                            Cc::Ge => l >= r,
                        };
                        (inst.res?, V::Num(t as i64))
                    }
                    (Op::Select, _) => {
                        let (V::Num(c), V::Num(t), V::Num(e)) = (
                            *env.get(inst.args.first()?)?,
                            *env.get(inst.args.get(1)?)?,
                            *env.get(inst.args.get(2)?)?,
                        ) else {
                            return None;
                        };
                        (inst.res?, V::Num(if c != 0 { t } else { e }))
                    }
                    // `a.compare(b)` on a generic element passes `b` as a boxed `Comparable`.
                    (Op::IfaceNew, _) => match env.get(inst.args.first()?)? {
                        V::Arg(x) => (inst.res?, V::Boxed(*x)),
                        _ => return None,
                    },
                    (Op::IfaceData, _) => match env.get(inst.args.first()?)? {
                        V::Boxed(x) => (inst.res?, V::Payload(*x)),
                        _ => return None,
                    },
                    (Op::Load, _) => match env.get(inst.args.first()?)? {
                        V::Payload(x) => (inst.res?, V::Arg(*x)),
                        _ => return None,
                    },
                    (Op::DepthEnter | Op::DepthLeave | Op::Drop, _) => continue,
                    _ => return None,
                };
                env.insert(res, v);
            }
            let target = match &bd.term {
                Term::Ret(Some(v)) => {
                    return match env.get(v)? {
                        V::Num(c) => Some(*c < 0),
                        _ => None,
                    };
                }
                Term::Br(t) => t,
                Term::CondBr { cond, then, els } => match env.get(cond)? {
                    V::Num(c) if *c != 0 => then,
                    V::Num(_) => els,
                    _ => return None,
                },
                _ => return None,
            };
            let dest = &g.blocks[target.block.index()];
            if dest.params.len() != target.args.len() {
                return None;
            }
            let passed: Vec<V> = target
                .args
                .iter()
                .map(|v| env.get(v).copied())
                .collect::<Option<_>>()?;
            for (p, v) in dest.params.iter().zip(passed) {
                env.insert(p.value, v);
            }
            block = target.block.index();
        }
        None
    };
    let (lt, eq, gt) = (negative(0, 1)?, negative(1, 1)?, negative(1, 0)?);
    match (lt, eq, gt) {
        (true, false, false) => Some(false),
        (false, false, true) => Some(true),
        _ => None,
    }
}

/// Rewrites the runtime sort at `blocks[bi].insts[ii]` into a copy and an in-place integer sort.
fn rewrite_plain(f: &mut Func, bi: usize, ii: usize, ext: crate::ir::ExtId, desc: bool) {
    let call = f.blocks[bi].insts[ii].clone();
    let out = call.res.expect("sorted result");
    let copy_out = Inst {
        op: Op::Clone,
        args: vec![call.args[0]],
        imm: Imm::None,
        res: Some(out),
        loc: call.loc,
    };
    let flag = f.new_value(Ty::INT);
    let flag_inst = Inst {
        op: Op::IConst,
        args: vec![],
        imm: Imm::Int(desc as i64),
        res: Some(flag),
        loc: call.loc,
    };
    let unit = f.new_value(Ty::UNIT);
    let run = Inst {
        op: Op::CallRt,
        args: vec![out, flag],
        imm: Imm::Ext(ext),
        res: Some(unit),
        loc: call.loc,
    };
    f.blocks[bi]
        .insts
        .splice(ii..=ii, [copy_out, flag_inst, run]);
}

/// The runtime functions that copy a list's slots bitwise and free that copy, declared from
/// the sort call at `blocks[bi].insts[ii]`.
fn shadow_externs(
    m: &mut Module,
    fi: usize,
    bi: usize,
    ii: usize,
) -> (crate::ir::ExtId, crate::ir::ExtId) {
    let call = &m.funcs[fi].blocks[bi].insts[ii];
    let Imm::Ext(e) = call.imm else {
        unreachable!("sort call");
    };
    let mut shadow = m.externs[e.index()].clone();
    shadow.name = "msrt_list_shadow".to_string();
    shadow.role = ExternRole::RawSlots;
    shadow.params.truncate(2);
    shadow.leaf = true;
    let list = shadow.params[0].ty;
    let free = ExternDef {
        name: "msrt_list_free_raw".to_string(),
        // The runtime releases the scratch buffer, so the call consumes the owned list value.
        params: vec![Param {
            ty: list,
            mode: Mode::Move,
        }],
        ret: Ty::UNIT,
        noreturn: false,
        pure_: false,
        fresh: false,
        role: ExternRole::RawFree,
        leaf: true,
        reads: false,
    };
    let (shadow, free) = (m.add_extern(shadow), m.add_extern(free));
    // A declaration the program already had keeps its role otherwise.
    m.externs[shadow.index()].role = ExternRole::RawSlots;
    m.externs[free.index()].role = ExternRole::RawFree;
    (shadow, free)
}

/// Rewrites the runtime sort of owning elements. The sort permutes bitwise copies of the slots
/// (two scratch buffers that own nothing) and only then clones the sorted slots into the result,
/// so a comparator that exits early never leaves a list with duplicated owners.
fn rewrite_owned(
    f: &mut Func,
    bi: usize,
    ii: usize,
    sort: FuncId,
    elem: Ty,
    (shadow, free): (crate::ir::ExtId, crate::ir::ExtId),
) {
    let call = f.blocks[bi].insts[ii].clone();
    let (list, desc) = (call.args[0], call.args[1]);
    let out = call.res.expect("sorted result");
    let list_ty = f.values[out.index()];
    let mut insts = Vec::new();
    let mut emit = |op, args: Vec<Value>, imm, res: Option<Value>| {
        insts.push(Inst {
            op,
            args,
            imm,
            res,
            loc: call.loc,
        });
        res
    };
    let items = f.new_value(list_ty);
    let buf = f.new_value(list_ty);
    emit(Op::CallRt, vec![list, desc], Imm::Ext(shadow), Some(items));
    emit(Op::CallRt, vec![list, desc], Imm::Ext(shadow), Some(buf));
    let len = f.new_value(Ty::INT);
    emit(Op::ListLen, vec![items], Imm::None, Some(len));
    let zero = f.new_value(Ty::INT);
    emit(Op::IConst, vec![], Imm::Int(0), Some(zero));
    let env = f.new_value(Ty::PTR);
    emit(Op::Slot, vec![], Imm::Ty(elem), Some(env));
    let unit = f.new_value(Ty::UNIT);
    emit(
        Op::Call,
        vec![buf, items, zero, len, env],
        Imm::Func(sort),
        Some(unit),
    );
    emit(Op::Clone, vec![items], Imm::None, Some(out));
    for raw in [items, buf] {
        let u = f.new_value(Ty::UNIT);
        emit(Op::CallRt, vec![raw], Imm::Ext(free), Some(u));
    }
    f.blocks[bi].insts.splice(ii..=ii, insts);
}

/// Rewrites the runtime sort at `blocks[bi].insts[ii]` into a copy, a buffer copy and a call.
fn rewrite(f: &mut Func, bi: usize, ii: usize, sort: FuncId, elem: Ty) {
    let call = f.blocks[bi].insts[ii].clone();
    let list = call.args[0];
    let out = call.res.expect("sorted result");
    let list_ty = f.values[out.index()];
    let new = |f: &mut Func, op, args: Vec<Value>, imm, ty: Option<Ty>| -> (Inst, Option<Value>) {
        let res = ty.map(|t| f.new_value(t));
        (
            Inst {
                op,
                args,
                imm,
                res,
                loc: call.loc,
            },
            res,
        )
    };
    let copy_out = Inst {
        op: Op::Clone,
        args: vec![list],
        imm: Imm::None,
        res: Some(out),
        loc: call.loc,
    };
    let (copy_buf, buf) = new(f, Op::Clone, vec![out], Imm::None, Some(list_ty));
    let buf = buf.expect("buffer");
    let (len, len_v) = new(f, Op::ListLen, vec![out], Imm::None, Some(Ty::INT));
    let (zero, zero_v) = new(f, Op::IConst, vec![], Imm::Int(0), Some(Ty::INT));
    let (env, env_v) = new(f, Op::Slot, vec![], Imm::Ty(elem), Some(Ty::PTR));
    let (run, _) = new(
        f,
        Op::Call,
        vec![
            buf,
            out,
            zero_v.expect("zero"),
            len_v.expect("len"),
            env_v.expect("env"),
        ],
        Imm::Func(sort),
        Some(Ty::UNIT),
    );
    let (drop_buf, _) = new(f, Op::Drop, vec![buf], Imm::None, None);
    f.blocks[bi]
        .insts
        .splice(ii..=ii, [copy_out, copy_buf, len, zero, env, run, drop_buf]);
}

/// Builds `merge(src, dst, lo, hi, env)`: stable merge sort that leaves `dst[lo..hi]` sorted by the
/// sign of `g(env, a, b)`. Both lists hold the same elements in `lo..hi` on entry; `src` is
/// scratch and holds unspecified elements there afterwards. Each level sorts its halves into the
/// other list and merges them back, so no level copies the slice.
fn build_merge(m: &mut Module, g: FuncId, elem: Ty) -> FuncId {
    let list_ty = m.types.list(elem);
    let p = |ty| Param {
        ty,
        mode: Mode::Borrow,
    };
    let params = vec![p(list_ty), p(list_ty), p(Ty::INT), p(Ty::INT), p(Ty::PTR)];
    let name = format!("sort.mergesort.{}", m.funcs[g.index()].name);
    let id = m.add_func(Func::new(&name, params.clone(), Ty::UNIT));
    let mut b = FuncBuilder::new(m, &name, params, Ty::UNIT);
    b.func_mut().raw_scratch = true;
    let args = b.params();
    // `buf` is the list the merge reads from and `items` the list it writes.
    let (buf, items, lo, hi, env) = (args[0], args[1], args[2], args[3], args[4]);

    let one = b.iconst(1);
    let at = |b: &mut FuncBuilder, list: Value, i: Value| {
        b.emit(Op::ListAddrU, &[list, i], Imm::None, Some(Ty::PTR))
            .expect("addr")
    };
    let load = |b: &mut FuncBuilder, ptr: Value| {
        b.emit(Op::Load, &[ptr], Imm::Ty(elem), Some(elem))
            .expect("load")
    };
    let store = |b: &mut FuncBuilder, ptr: Value, v: Value| {
        b.emit(Op::Store, &[ptr, v], Imm::None, None);
    };
    // `cmp(a, b) < 0`.
    let less = |b: &mut FuncBuilder, x: Value, y: Value| {
        let c = b.call(g, &[env, x, y]);
        let zero = b.iconst(0);
        b.icmp(Cc::Lt, c, zero)
    };
    let int = |b: &mut FuncBuilder| b.declare_var(Ty::INT, Mode::Borrow);
    let b2i = |b: &mut FuncBuilder, flag: Value| {
        b.emit(Op::B2I, &[flag], Imm::None, Some(Ty::INT))
            .expect("b2i")
    };

    let n = b.binop(Op::ISub, hi, lo);
    let limit = b.iconst(INSERTION_MAX);
    let small = b.icmp(Cc::Le, n, limit);
    let (insertion, big) = (b.new_block(), b.new_block());
    b.br_if(small, insertion, &[], big, &[]);
    b.seal_block(insertion);
    b.seal_block(big);

    // Insertion sort of a short slice.
    b.switch_to(insertion);
    let (iv, jv) = (int(&mut b), int(&mut b));
    let first = b.binop(Op::IAdd, lo, one);
    b.def_var(iv, first);
    let (outer, outer_body, inner, inner_body, shift, place, done) = (
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
    );
    b.br(outer, &[]);
    b.switch_to(outer);
    let i = b.use_var(iv);
    let more = b.icmp(Cc::Lt, i, hi);
    b.br_if(more, outer_body, &[], done, &[]);
    b.seal_block(outer_body);
    b.seal_block(done);
    b.switch_to(outer_body);
    let i = b.use_var(iv);
    let pi = at(&mut b, items, i);
    let x = load(&mut b, pi);
    b.def_var(jv, i);
    b.br(inner, &[]);
    b.switch_to(inner);
    let j = b.use_var(jv);
    let above = b.icmp(Cc::Gt, j, lo);
    b.br_if(above, inner_body, &[], place, &[]);
    b.seal_block(inner_body);
    b.switch_to(inner_body);
    let j = b.use_var(jv);
    let jm = b.binop(Op::ISub, j, one);
    let pjm = at(&mut b, items, jm);
    let y = load(&mut b, pjm);
    let lt = less(&mut b, x, y);
    b.br_if(lt, shift, &[], place, &[]);
    b.seal_block(shift);
    b.seal_block(place);
    b.switch_to(shift);
    let j = b.use_var(jv);
    let pj = at(&mut b, items, j);
    store(&mut b, pj, y);
    b.def_var(jv, jm);
    b.br(inner, &[]);
    b.seal_block(inner);
    b.switch_to(place);
    let j = b.use_var(jv);
    let pj = at(&mut b, items, j);
    store(&mut b, pj, x);
    let i = b.use_var(iv);
    let next = b.binop(Op::IAdd, i, one);
    b.def_var(iv, next);
    b.br(outer, &[]);
    b.seal_block(outer);
    b.switch_to(done);
    let u = b.unit();
    b.ret(Some(u));

    // Sort both halves, then merge unless they are already in order.
    b.switch_to(big);
    let half = b.binop(Op::Sshr, n, one);
    let mid = b.binop(Op::IAdd, lo, half);
    b.call(id, &[items, buf, lo, mid, env]);
    b.call(id, &[items, buf, mid, hi, env]);
    let pm = at(&mut b, buf, mid);
    let a = load(&mut b, pm);
    let mm1 = b.binop(Op::ISub, mid, one);
    let pmm = at(&mut b, buf, mm1);
    let c = load(&mut b, pmm);
    let unordered = less(&mut b, a, c);
    let (merge, finish) = (b.new_block(), b.new_block());
    b.br_if(unordered, merge, &[], finish, &[]);
    b.seal_block(merge);
    b.seal_block(finish);
    // The halves are already in order: the result is the slice as the halves left it.
    b.switch_to(finish);
    let kv = int(&mut b);
    b.def_var(kv, lo);
    let (copy_head, copy_body, copied) = (b.new_block(), b.new_block(), b.new_block());
    b.br(copy_head, &[]);
    b.switch_to(copy_head);
    let k = b.use_var(kv);
    let go = b.icmp(Cc::Lt, k, hi);
    b.br_if(go, copy_body, &[], copied, &[]);
    b.seal_block(copy_body);
    b.seal_block(copied);
    b.switch_to(copy_body);
    let k = b.use_var(kv);
    let from = at(&mut b, buf, k);
    let v = load(&mut b, from);
    let to = at(&mut b, items, k);
    store(&mut b, to, v);
    let k1 = b.binop(Op::IAdd, k, one);
    b.def_var(kv, k1);
    b.br(copy_head, &[]);
    b.seal_block(copy_head);
    b.switch_to(copied);
    let u = b.unit();
    b.ret(Some(u));

    // Merge from both ends at once, two output slots per step.
    let merged = merge;
    b.switch_to(merged);
    let (lv, lev, rv, rev, sv) = (
        int(&mut b),
        int(&mut b),
        int(&mut b),
        int(&mut b),
        int(&mut b),
    );
    let zero = b.iconst(0);
    let steps = b.binop(Op::Sshr, n, one);
    b.def_var(lv, lo);
    b.def_var(lev, mid);
    b.def_var(rv, mid);
    b.def_var(rev, hi);
    b.def_var(sv, zero);
    let (head, step, tail) = (b.new_block(), b.new_block(), b.new_block());
    b.br(head, &[]);
    b.switch_to(head);
    let s = b.use_var(sv);
    let go = b.icmp(Cc::Lt, s, steps);
    b.br_if(go, step, &[], tail, &[]);
    b.seal_block(step);
    b.seal_block(tail);

    // Front: take from the right run only when it is strictly smaller.
    b.switch_to(step);
    let (l, le, r, re) = (b.use_var(lv), b.use_var(lev), b.use_var(rv), b.use_var(rev));
    let (front_true, front_chk, front_cmp, front_join) =
        (b.new_block(), b.new_block(), b.new_block(), b.new_block());
    let take_r = b.add_block_param(front_join, Ty::BOOL, Mode::Borrow);
    let left_done = b.icmp(Cc::Eq, l, le);
    b.br_if(left_done, front_true, &[], front_chk, &[]);
    b.seal_block(front_true);
    b.seal_block(front_chk);
    b.switch_to(front_true);
    let yes = b.bconst(true);
    b.br(front_join, &[yes]);
    b.switch_to(front_chk);
    let right_left = b.icmp(Cc::Lt, r, re);
    let no = b.bconst(false);
    b.br_if(right_left, front_cmp, &[], front_join, &[no]);
    b.seal_block(front_cmp);
    b.switch_to(front_cmp);
    let pr = at(&mut b, buf, r);
    let xr = load(&mut b, pr);
    let pl = at(&mut b, buf, l);
    let yl = load(&mut b, pl);
    let t = less(&mut b, xr, yl);
    b.br(front_join, &[t]);
    b.seal_block(front_join);
    b.switch_to(front_join);
    let idx = b.select(take_r, r, l);
    let pi = at(&mut b, buf, idx);
    let v = load(&mut b, pi);
    let s = b.use_var(sv);
    let slot = b.binop(Op::IAdd, lo, s);
    let po = at(&mut b, items, slot);
    store(&mut b, po, v);
    let tr = b2i(&mut b, take_r);
    let r1 = b.binop(Op::IAdd, r, tr);
    let one_minus = b.binop(Op::ISub, one, tr);
    let l1 = b.binop(Op::IAdd, l, one_minus);

    // Back: take from the left run only when the right run's last is not smaller.
    let (back_true, back_chk, back_cmp, back_join) =
        (b.new_block(), b.new_block(), b.new_block(), b.new_block());
    let take_l = b.add_block_param(back_join, Ty::BOOL, Mode::Borrow);
    let right_done = b.icmp(Cc::Eq, re, r1);
    b.br_if(right_done, back_true, &[], back_chk, &[]);
    b.seal_block(back_true);
    b.seal_block(back_chk);
    b.switch_to(back_true);
    let yes = b.bconst(true);
    b.br(back_join, &[yes]);
    b.switch_to(back_chk);
    let left_left = b.icmp(Cc::Lt, l1, le);
    let no = b.bconst(false);
    b.br_if(left_left, back_cmp, &[], back_join, &[no]);
    b.seal_block(back_cmp);
    b.switch_to(back_cmp);
    let rem1 = b.binop(Op::ISub, re, one);
    let lem1 = b.binop(Op::ISub, le, one);
    let pre = at(&mut b, buf, rem1);
    let xre = load(&mut b, pre);
    let ple = at(&mut b, buf, lem1);
    let yle = load(&mut b, ple);
    let t = less(&mut b, xre, yle);
    b.br(back_join, &[t]);
    b.seal_block(back_join);
    b.switch_to(back_join);
    let rem1 = b.binop(Op::ISub, re, one);
    let lem1 = b.binop(Op::ISub, le, one);
    let idx = b.select(take_l, lem1, rem1);
    let pi = at(&mut b, buf, idx);
    let v = load(&mut b, pi);
    let s = b.use_var(sv);
    let back = b.binop(Op::ISub, hi, one);
    let slot = b.binop(Op::ISub, back, s);
    let po = at(&mut b, items, slot);
    store(&mut b, po, v);
    let tl = b2i(&mut b, take_l);
    let le1 = b.binop(Op::ISub, le, tl);
    let keep = b.binop(Op::ISub, one, tl);
    let re1 = b.binop(Op::ISub, re, keep);
    let s1 = b.binop(Op::IAdd, s, one);
    b.def_var(lv, l1);
    b.def_var(lev, le1);
    b.def_var(rv, r1);
    b.def_var(rev, re1);
    b.def_var(sv, s1);
    b.br(head, &[]);
    b.seal_block(head);

    // An odd slice leaves one element for the middle.
    b.switch_to(tail);
    let (l, le, r) = (b.use_var(lv), b.use_var(lev), b.use_var(rv));
    let odd_bit = b.binop(Op::And, n, one);
    let zero = b.iconst(0);
    let odd = b.icmp(Cc::Ne, odd_bit, zero);
    let (middle, end) = (b.new_block(), b.new_block());
    b.br_if(odd, middle, &[], end, &[]);
    b.seal_block(middle);
    b.seal_block(end);
    b.switch_to(middle);
    let from_left = b.icmp(Cc::Lt, l, le);
    let idx = b.select(from_left, l, r);
    let pi = at(&mut b, buf, idx);
    let v = load(&mut b, pi);
    let slot = b.binop(Op::IAdd, lo, steps);
    let po = at(&mut b, items, slot);
    store(&mut b, po, v);
    b.br(end, &[]);
    b.switch_to(end);
    let u = b.unit();
    b.ret(Some(u));

    let f = b.into_func();
    m.funcs[id.index()] = f;
    id
}

// ---- driftsort ----

/// Slices at most this long are sorted by insertion.
const SMALL: i64 = 20;

/// Emits straight-line and structured code for the driftsort helpers.
struct Em<'a, 'm> {
    b: &'a mut FuncBuilder<'m>,
    elem: Ty,
    g: FuncId,
}

impl Em<'_, '_> {
    fn int(&mut self, v: i64) -> Value {
        self.b.iconst(v)
    }
    fn add(&mut self, x: Value, y: Value) -> Value {
        self.b.binop(Op::IAdd, x, y)
    }
    fn sub(&mut self, x: Value, y: Value) -> Value {
        self.b.binop(Op::ISub, x, y)
    }
    fn add_k(&mut self, x: Value, k: i64) -> Value {
        let k = self.int(k);
        self.add(x, k)
    }
    fn cmp(&mut self, cc: Cc, x: Value, y: Value) -> Value {
        self.b.icmp(cc, x, y)
    }
    fn b2i(&mut self, flag: Value) -> Value {
        self.b
            .emit(Op::B2I, &[flag], Imm::None, Some(Ty::INT))
            .expect("b2i")
    }
    fn var(&mut self, init: Value) -> Var {
        let v = self.b.declare_var(Ty::INT, Mode::Borrow);
        self.b.def_var(v, init);
        v
    }
    fn get(&mut self, v: Var) -> Value {
        self.b.use_var(v)
    }
    fn set(&mut self, v: Var, x: Value) {
        self.b.def_var(v, x);
    }
    fn at(&mut self, list: Value, i: Value) -> Value {
        self.b
            .emit(Op::ListAddrU, &[list, i], Imm::None, Some(Ty::PTR))
            .expect("addr")
    }
    fn load_at(&mut self, p: Value) -> Value {
        self.b
            .emit(Op::Load, &[p], Imm::Ty(self.elem), Some(self.elem))
            .expect("load")
    }
    /// The element at `list[i]`, which is not bounds-checked.
    fn ld(&mut self, list: Value, i: Value) -> Value {
        let p = self.at(list, i);
        self.load_at(p)
    }
    fn st(&mut self, list: Value, i: Value, v: Value) {
        let p = self.at(list, i);
        self.b.emit(Op::Store, &[p, v], Imm::None, None);
    }
    /// The word at `ints[i]` of a scratch list of `Int`.
    fn ld_int(&mut self, ints: Value, i: Value) -> Value {
        let p = self.at(ints, i);
        self.b
            .emit(Op::Load, &[p], Imm::Ty(Ty::INT), Some(Ty::INT))
            .expect("load")
    }
    fn st_int(&mut self, ints: Value, i: Value, v: Value) {
        let p = self.at(ints, i);
        self.b.emit(Op::Store, &[p, v], Imm::None, None);
    }
    /// `cmp(x, y) < 0`.
    fn less(&mut self, env: Value, x: Value, y: Value) -> Value {
        let c = self.b.call(self.g, &[env, x, y]);
        let zero = self.int(0);
        self.cmp(Cc::Lt, c, zero)
    }
    /// Runs `then` when `cond` holds, then continues after it.
    fn if_(&mut self, cond: Value, then: impl FnOnce(&mut Self)) {
        let (t, join) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(cond, t, &[], join, &[]);
        self.b.seal_block(t);
        self.b.switch_to(t);
        then(self);
        self.b.br(join, &[]);
        self.b.seal_block(join);
        self.b.switch_to(join);
    }
    /// Runs `then`, which ends in a return, when `cond` holds; otherwise continues.
    fn if_ret(&mut self, cond: Value, then: impl FnOnce(&mut Self)) {
        let (t, rest) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(cond, t, &[], rest, &[]);
        self.b.seal_block(t);
        self.b.seal_block(rest);
        self.b.switch_to(t);
        then(self);
        self.b.switch_to(rest);
    }
    /// A value chosen by `cond`, computing only the chosen side.
    fn pick(
        &mut self,
        ty: Ty,
        cond: Value,
        a: impl FnOnce(&mut Self) -> Value,
        c: impl FnOnce(&mut Self) -> Value,
    ) -> Value {
        let (ta, tc, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        let out = self.b.add_block_param(join, ty, Mode::Borrow);
        self.b.br_if(cond, ta, &[], tc, &[]);
        self.b.seal_block(ta);
        self.b.seal_block(tc);
        self.b.switch_to(ta);
        let x = a(self);
        self.b.br(join, &[x]);
        self.b.switch_to(tc);
        let y = c(self);
        self.b.br(join, &[y]);
        self.b.seal_block(join);
        self.b.switch_to(join);
        out
    }
    /// Repeats `body` until it leaves through the block it is given.
    fn loop_(&mut self, body: impl FnOnce(&mut Self, Block)) {
        let (head, exit) = (self.b.new_block(), self.b.new_block());
        self.b.br(head, &[]);
        self.b.switch_to(head);
        body(self, exit);
        self.b.br(head, &[]);
        self.b.seal_block(head);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
    }
    /// Leaves the loop through `exit` when `cond` holds.
    fn brk_if(&mut self, cond: Value, exit: Block) {
        let go = self.b.new_block();
        self.b.br_if(cond, exit, &[], go, &[]);
        self.b.seal_block(go);
        self.b.switch_to(go);
    }
    fn unit_ret(&mut self) {
        let u = self.b.unit();
        self.b.ret(Some(u));
    }
}

/// Starts a function with borrowed parameters and returns its id and builder.
fn declare(m: &mut Module, name: &str, params: &[Ty], ret: Ty) -> (FuncId, Vec<Param>) {
    let params: Vec<Param> = params
        .iter()
        .map(|&ty| Param {
            ty,
            mode: Mode::Borrow,
        })
        .collect();
    let id = m.add_func(Func::new(name, params.clone(), ret));
    (id, params)
}

/// The helpers of [`build_drift`], by role.
struct Parts {
    ins: FuncId,
    merge: FuncId,
    part: FuncId,
    pivot: FuncId,
    quick: FuncId,
    msort: FuncId,
    mergesort: FuncId,
}

/// Builds `drift(scratch, items, 0, n, env)`: a stable driftsort of `items[0..n]` by the sign of
/// `g(env, a, b)`, the algorithm of Rust's `slice::sort`. The call has the shape of
/// [`build_merge`]'s sort, and the slots are permuted as bits, so a faulting comparator leaves
/// scratch, not an owner, in a partial state.
///
/// The input is cut into runs: a natural run that is long enough (a descending one is reversed
/// in place) or a stretch that is left unsorted. Neighbouring runs are merged in a tree split near
/// the middle of the data; two unsorted stretches join into one, so random data is a single
/// unsorted stretch that a stable quicksort handles. The quicksort partitions through the
/// scratch list, gives an element equal to its ancestor pivot a partition of its own, so data
/// with few distinct keys sorts in `O(n log k)`, and falls back to merge sort when it
/// recurses deeper than `2 log n`.
fn build_drift(m: &mut Module, g: FuncId, elem: Ty) -> FuncId {
    let list_ty = m.types.list(elem);
    let (i, p) = (Ty::INT, Ty::PTR);
    let tag = m.funcs[g.index()].name.clone();
    let mergesort = build_merge(m, g, elem);
    let (ins, ins_p) = declare(m, &format!("sort.ins.{tag}"), &[list_ty, i, i, p], Ty::UNIT);
    let (merge, merge_p) = declare(
        m,
        &format!("sort.run_merge.{tag}"),
        &[list_ty, list_ty, i, i, i, p],
        Ty::UNIT,
    );
    let (part, part_p) = declare(
        m,
        &format!("sort.part.{tag}"),
        &[list_ty, list_ty, i, i, elem, i, p],
        Ty::INT,
    );
    let (pivot, pivot_p) = declare(
        m,
        &format!("sort.pivot.{tag}"),
        &[list_ty, i, i, i, i, p],
        Ty::INT,
    );
    let (quick, quick_p) = declare(
        m,
        &format!("sort.quick.{tag}"),
        &[list_ty, list_ty, i, i, i, elem, i, p],
        Ty::UNIT,
    );
    let int_list = m.types.list(Ty::INT);
    let (msort, msort_p) = declare(
        m,
        &format!("sort.runs.{tag}"),
        &[list_ty, list_ty, int_list, i, i, i, p],
        Ty::INT,
    );
    let (drift, drift_p) = declare(
        m,
        &format!("sort.drift.{tag}"),
        &[list_ty, list_ty, i, i, p],
        Ty::UNIT,
    );
    let parts = Parts {
        ins,
        merge,
        part,
        pivot,
        quick,
        msort,
        mergesort,
    };
    let finish = |m: &mut Module, id: FuncId, f: Func| m.funcs[id.index()] = f;

    let f = build_ins(m, g, elem, &format!("sort.ins.{tag}"), ins_p);
    finish(m, ins, f);
    let f = build_run_merge(m, g, elem, &format!("sort.run_merge.{tag}"), merge_p);
    finish(m, merge, f);
    let f = build_part(m, g, elem, &format!("sort.part.{tag}"), part_p);
    finish(m, part, f);
    let f = build_pivot(m, g, elem, &format!("sort.pivot.{tag}"), pivot_p, &parts);
    finish(m, pivot, f);
    let f = build_quick(m, g, elem, &format!("sort.quick.{tag}"), quick_p, &parts);
    finish(m, quick, f);
    let f = build_runs(m, g, elem, &format!("sort.runs.{tag}"), msort_p, &parts);
    finish(m, msort, f);
    let f = build_top(m, g, elem, &format!("sort.drift.{tag}"), drift_p, &parts);
    finish(m, drift, f);
    drift
}

fn start<'m>(m: &'m mut Module, name: &str, params: Vec<Param>, ret: Ty) -> FuncBuilder<'m> {
    let mut b = FuncBuilder::new(m, name, params, ret);
    b.func_mut().raw_scratch = true;
    b
}

/// `ins(items, lo, hi, env)`: stable insertion sort of `items[lo..hi]`.
fn build_ins(m: &mut Module, g: FuncId, elem: Ty, name: &str, params: Vec<Param>) -> Func {
    let mut fb = start(m, name, params, Ty::UNIT);
    let a = fb.params();
    let (items, lo, hi, env) = (a[0], a[1], a[2], a[3]);
    let mut e = Em {
        b: &mut fb,
        elem,
        g,
    };
    let first = e.add_k(lo, 1);
    let iv = e.var(first);
    e.loop_(|e, exit| {
        let i = e.get(iv);
        let done = e.cmp(Cc::Ge, i, hi);
        e.brk_if(done, exit);
        let x = e.ld(items, i);
        let jv = e.var(i);
        e.loop_(|e, stop| {
            let j = e.get(jv);
            let at_lo = e.cmp(Cc::Le, j, lo);
            e.brk_if(at_lo, stop);
            let jm = e.add_k(j, -1);
            let y = e.ld(items, jm);
            let lt = e.less(env, x, y);
            let ordered = e.b2i(lt);
            let zero = e.int(0);
            let stay = e.cmp(Cc::Eq, ordered, zero);
            e.brk_if(stay, stop);
            e.st(items, j, y);
            e.set(jv, jm);
        });
        let j = e.get(jv);
        e.st(items, j, x);
        let i = e.get(iv);
        let next = e.add_k(i, 1);
        e.set(iv, next);
    });
    e.unit_ret();
    fb.into_func()
}

/// `run_merge(items, scratch, lo, mid, hi, env)`: merges the sorted `items[lo..mid]` and
/// `items[mid..hi]` stably, copying the shorter side into `scratch[lo..hi]`.
fn build_run_merge(m: &mut Module, g: FuncId, elem: Ty, name: &str, params: Vec<Param>) -> Func {
    let mut fb = start(m, name, params, Ty::UNIT);
    let a = fb.params();
    let (items, buf, lo, mid, hi, env) = (a[0], a[1], a[2], a[3], a[4], a[5]);
    let mut e = Em {
        b: &mut fb,
        elem,
        g,
    };
    // Already in order: nothing to do.
    let first = e.ld(items, mid);
    let mm1 = e.add_k(mid, -1);
    let last = e.ld(items, mm1);
    let unordered = e.less(env, first, last);
    let zero = e.int(0);
    let flag = e.b2i(unordered);
    let ordered = e.cmp(Cc::Eq, flag, zero);
    e.if_ret(ordered, |e| e.unit_ret());
    let left_len = e.sub(mid, lo);
    let right_len = e.sub(hi, mid);
    let left_short = e.cmp(Cc::Le, left_len, right_len);
    let (fwd, back) = (e.b.new_block(), e.b.new_block());
    e.b.br_if(left_short, fwd, &[], back, &[]);
    e.b.seal_block(fwd);
    e.b.seal_block(back);

    // Forward: the left run waits in scratch; take the right element only when it is smaller.
    e.b.switch_to(fwd);
    let kv = e.var(lo);
    e.loop_(|e, exit| {
        let k = e.get(kv);
        let done = e.cmp(Cc::Ge, k, mid);
        e.brk_if(done, exit);
        let x = e.ld(items, k);
        e.st(buf, k, x);
        let k1 = e.add_k(k, 1);
        e.set(kv, k1);
    });
    let (lv, rv, ov) = (e.var(lo), e.var(mid), e.var(lo));
    e.loop_(|e, exit| {
        let (l, r) = (e.get(lv), e.get(rv));
        let l_done = e.cmp(Cc::Ge, l, mid);
        e.brk_if(l_done, exit);
        let r_done = e.cmp(Cc::Ge, r, hi);
        e.brk_if(r_done, exit);
        let (pr, pl) = (e.at(items, r), e.at(buf, l));
        let xr = e.load_at(pr);
        let xl = e.load_at(pl);
        let take_r = e.less(env, xr, xl);
        let o = e.get(ov);
        // Select the address: an element that owns data cannot be selected as a value.
        let from = e.b.select(take_r, pr, pl);
        let x = e.load_at(from);
        e.st(items, o, x);
        let tr = e.b2i(take_r);
        let r1 = e.add(r, tr);
        let one = e.int(1);
        let keep = e.sub(one, tr);
        let l1 = e.add(l, keep);
        e.set(rv, r1);
        e.set(lv, l1);
        let o1 = e.add_k(o, 1);
        e.set(ov, o1);
    });
    // What remains of the left run goes to the end; a remaining right run is in place.
    e.loop_(|e, exit| {
        let l = e.get(lv);
        let done = e.cmp(Cc::Ge, l, mid);
        e.brk_if(done, exit);
        let o = e.get(ov);
        let x = e.ld(buf, l);
        e.st(items, o, x);
        let (l1, o1) = (e.add_k(l, 1), e.add_k(o, 1));
        e.set(lv, l1);
        e.set(ov, o1);
    });
    e.unit_ret();

    // Backward: the right run waits in scratch; take the left element only when the right one
    // is smaller.
    e.b.switch_to(back);
    let kv = e.var(mid);
    e.loop_(|e, exit| {
        let k = e.get(kv);
        let done = e.cmp(Cc::Ge, k, hi);
        e.brk_if(done, exit);
        let x = e.ld(items, k);
        e.st(buf, k, x);
        let k1 = e.add_k(k, 1);
        e.set(kv, k1);
    });
    let (lv, rv, ov) = (e.var(mm1), e.var(hi), e.var(hi));
    // `rv` and `ov` are one past the next slot to read and to fill.
    e.loop_(|e, exit| {
        let (l, r) = (e.get(lv), e.get(rv));
        let l_done = e.cmp(Cc::Lt, l, lo);
        e.brk_if(l_done, exit);
        let r_done = e.cmp(Cc::Le, r, mid);
        e.brk_if(r_done, exit);
        let r1 = e.add_k(r, -1);
        let (pr, pl) = (e.at(buf, r1), e.at(items, l));
        let xr = e.load_at(pr);
        let xl = e.load_at(pl);
        let take_l = e.less(env, xr, xl);
        let o = e.get(ov);
        let o1 = e.add_k(o, -1);
        let from = e.b.select(take_l, pl, pr);
        let x = e.load_at(from);
        e.st(items, o1, x);
        let tl = e.b2i(take_l);
        let one = e.int(1);
        let keep = e.sub(one, tl);
        let l1 = e.sub(l, tl);
        let r2 = e.sub(r, keep);
        e.set(lv, l1);
        e.set(rv, r2);
        e.set(ov, o1);
    });
    e.loop_(|e, exit| {
        let r = e.get(rv);
        let done = e.cmp(Cc::Le, r, mid);
        e.brk_if(done, exit);
        let o = e.get(ov);
        let (r1, o1) = (e.add_k(r, -1), e.add_k(o, -1));
        let x = e.ld(buf, r1);
        e.st(items, o1, x);
        e.set(rv, r1);
        e.set(ov, o1);
    });
    e.unit_ret();
    fb.into_func()
}

/// `part(items, scratch, lo, hi, pivot, le, env)`: moves the elements before `pivot` (or, when
/// `le` is not 0, not after it) to the front of `items[lo..hi]` and the rest behind them, both in
/// their original order; returns how many moved to the front. No step branches on the
/// comparison: the store goes to a selected address.
fn build_part(m: &mut Module, g: FuncId, elem: Ty, name: &str, params: Vec<Param>) -> Func {
    let mut fb = start(m, name, params, Ty::INT);
    let a = fb.params();
    let (items, buf, lo, hi, pivot, le, env) = (a[0], a[1], a[2], a[3], a[4], a[5], a[6]);
    let mut e = Em {
        b: &mut fb,
        elem,
        g,
    };
    let zero = e.int(0);
    let (iv, ltv, gev) = (e.var(lo), e.var(zero), e.var(zero));
    let non_strict = e.cmp(Cc::Ne, le, zero);
    e.loop_(|e, exit| {
        let i = e.get(iv);
        let done = e.cmp(Cc::Ge, i, hi);
        e.brk_if(done, exit);
        let x = e.ld(items, i);
        let before = e.pick(
            Ty::BOOL,
            non_strict,
            |e| {
                let after = e.less(env, pivot, x);
                let z = e.int(0);
                let f = e.b2i(after);
                e.cmp(Cc::Eq, f, z)
            },
            |e| e.less(env, x, pivot),
        );
        let (lt, ge) = (e.get(ltv), e.get(gev));
        // One store, to the front of `items` or to the next slot of the scratch list.
        let (front, back) = (e.add(lo, lt), e.add(lo, ge));
        let (pf, pb) = (e.at(items, front), e.at(buf, back));
        let dest = e.b.select(before, pf, pb);
        e.b.emit(Op::Store, &[dest, x], Imm::None, None);
        let c = e.b2i(before);
        let one = e.int(1);
        let rest = e.sub(one, c);
        let (lt1, ge1) = (e.add(lt, c), e.add(ge, rest));
        e.set(ltv, lt1);
        e.set(gev, ge1);
        let i1 = e.add_k(i, 1);
        e.set(iv, i1);
    });
    let (lt, ge) = (e.get(ltv), e.get(gev));
    let dest = e.add(lo, lt);
    let kv = e.var(zero);
    e.loop_(|e, exit| {
        let k = e.get(kv);
        let done = e.cmp(Cc::Ge, k, ge);
        e.brk_if(done, exit);
        let from = e.add(lo, k);
        let x = e.ld(buf, from);
        let to = e.add(dest, k);
        e.st(items, to, x);
        let k1 = e.add_k(k, 1);
        e.set(kv, k1);
    });
    e.b.ret(Some(lt));
    fb.into_func()
}

/// `pivot(items, a, b, c, n, env)`: the index of the median of `items[a]`, `items[b]` and
/// `items[c]`; with `n` of 8 or more, each is first the median of three slots `n / 8` apart.
fn build_pivot(
    m: &mut Module,
    g: FuncId,
    elem: Ty,
    name: &str,
    params: Vec<Param>,
    parts: &Parts,
) -> Func {
    let this = parts.pivot;
    let mut fb = start(m, name, params, Ty::INT);
    let a = fb.params();
    let (items, x, y, z, n, env) = (a[0], a[1], a[2], a[3], a[4], a[5]);
    let mut e = Em {
        b: &mut fb,
        elem,
        g,
    };
    let eight = e.int(8);
    let deep = e.cmp(Cc::Ge, n, eight);
    let three = e.int(3);
    let n8 = e.b.binop(Op::Sshr, n, three);
    let (four, seven) = (e.int(4), e.int(7));
    let (s4, s7) = (
        e.b.binop(Op::IMul, n8, four),
        e.b.binop(Op::IMul, n8, seven),
    );
    let mut refined = Vec::new();
    for at in [x, y, z] {
        let v = e.pick(
            Ty::INT,
            deep,
            |e| {
                let (b, c) = (e.add(at, s4), e.add(at, s7));
                e.b.call(this, &[items, at, b, c, n8, env])
            },
            |_| at,
        );
        refined.push(v);
    }
    let (x, y, z) = (refined[0], refined[1], refined[2]);
    let (vx, vy, vz) = (e.ld(items, x), e.ld(items, y), e.ld(items, z));
    let xy = e.less(env, vx, vy);
    let xz = e.less(env, vx, vz);
    let yz = e.less(env, vy, vz);
    let (xy, xz, yz) = (e.b2i(xy), e.b2i(xz), e.b2i(yz));
    // When `x` is neither the least nor the greatest it is the median; otherwise `y` or `z` is.
    let agree = e.cmp(Cc::Eq, xy, xz);
    let flip = e.b.binop(Op::Xor, yz, xy);
    let zero = e.int(0);
    let flipped = e.cmp(Cc::Ne, flip, zero);
    let other = e.b.select(flipped, z, y);
    let m3 = e.b.select(agree, other, x);
    e.b.ret(Some(m3));
    fb.into_func()
}

/// `quick(items, scratch, lo, hi, anc_set, anc, limit, env)`: stable quicksort of
/// `items[lo..hi]`. `anc` (when `anc_set` is not 0) is a pivot of an enclosing call and not
/// after any element here.
fn build_quick(
    m: &mut Module,
    g: FuncId,
    elem: Ty,
    name: &str,
    params: Vec<Param>,
    parts: &Parts,
) -> Func {
    let mut fb = start(m, name, params, Ty::UNIT);
    let a = fb.params();
    let (items, buf, lo, hi) = (a[0], a[1], a[2], a[3]);
    let (anc_set, anc, limit, env) = (a[4], a[5], a[6], a[7]);
    let mut e = Em {
        b: &mut fb,
        elem,
        g,
    };
    let n = e.sub(hi, lo);
    let small = e.int(SMALL);
    let few = e.cmp(Cc::Le, n, small);
    e.if_ret(few, |e| {
        e.b.call(parts.ins, &[items, lo, hi, env]);
        e.unit_ret();
    });
    let zero = e.int(0);
    let spent = e.cmp(Cc::Le, limit, zero);
    e.if_ret(spent, |e| {
        // Too deep: merge sort the slice, which needs both lists to hold it.
        let kv = e.var(lo);
        e.loop_(|e, exit| {
            let k = e.get(kv);
            let done = e.cmp(Cc::Ge, k, hi);
            e.brk_if(done, exit);
            let x = e.ld(items, k);
            e.st(buf, k, x);
            let k1 = e.add_k(k, 1);
            e.set(kv, k1);
        });
        e.b.call(parts.mergesort, &[buf, items, lo, hi, env]);
        e.unit_ret();
    });
    let three = e.int(3);
    let n8 = e.b.binop(Op::Sshr, n, three);
    let (four, seven) = (e.int(4), e.int(7));
    let (s4, s7) = (
        e.b.binop(Op::IMul, n8, four),
        e.b.binop(Op::IMul, n8, seven),
    );
    let (pb, pc) = (e.add(lo, s4), e.add(lo, s7));
    let sixty_four = e.int(64);
    let big = e.cmp(Cc::Ge, n, sixty_four);
    // Below 64 slots the three are the candidates themselves.
    let depth = e.b.select(big, n8, zero);
    let p = e.b.call(parts.pivot, &[items, lo, pb, pc, depth, env]);
    let pv = e.ld(items, p);
    let next = e.add_k(limit, -1);
    // An element that is not after the ancestor pivot is, with this pivot, equal to it: the
    // slice's elements up to the pivot are all equal and need no more sorting.
    let has_anc = e.cmp(Cc::Ne, anc_set, zero);
    let equal = e.pick(
        Ty::BOOL,
        has_anc,
        |e| {
            let after = e.less(env, anc, pv);
            let f = e.b2i(after);
            let z = e.int(0);
            e.cmp(Cc::Eq, f, z)
        },
        |e| e.b.bconst(false),
    );
    let one = e.int(1);
    e.if_ret(equal, |e| {
        let c = e.b.call(parts.part, &[items, buf, lo, hi, pv, one, env]);
        let from = e.add(lo, c);
        e.b.call(parts.quick, &[items, buf, from, hi, zero, pv, next, env]);
        e.unit_ret();
    });
    let c = e.b.call(parts.part, &[items, buf, lo, hi, pv, zero, env]);
    let none = e.cmp(Cc::Eq, c, zero);
    e.if_ret(none, |e| {
        // The pivot is the least: everything equal to it goes first.
        let c = e.b.call(parts.part, &[items, buf, lo, hi, pv, one, env]);
        let from = e.add(lo, c);
        e.b.call(parts.quick, &[items, buf, from, hi, zero, pv, next, env]);
        e.unit_ret();
    });
    let mid = e.add(lo, c);
    e.b.call(parts.quick, &[items, buf, lo, mid, anc_set, anc, next, env]);
    e.b.call(parts.quick, &[items, buf, mid, hi, one, pv, next, env]);
    e.unit_ret();
    fb.into_func()
}

/// `runs(items, scratch, ends, i, j, limit, env)`: sorts the runs `i..j` that `ends` describes
/// (the end of run `k` shifted left once, with the low bit set when the run is already sorted)
/// as far as merging them goes. Returns 1 when the result is one unsorted slice that its caller
/// sorts, 0 when it is sorted.
fn build_runs(
    m: &mut Module,
    g: FuncId,
    elem: Ty,
    name: &str,
    params: Vec<Param>,
    parts: &Parts,
) -> Func {
    let mut fb = start(m, name, params, Ty::INT);
    let a = fb.params();
    let (items, buf, ends, i, j) = (a[0], a[1], a[2], a[3], a[4]);
    let (limit, env) = (a[5], a[6]);
    let mut e = Em {
        b: &mut fb,
        elem,
        g,
    };
    let zero = e.int(0);
    let one = e.int(1);
    // The end of run `k`.
    let end_of = |e: &mut Em, k: Value| {
        let w = e.ld_int(ends, k);
        e.b.binop(Op::Sshr, w, one)
    };
    let count = e.sub(j, i);
    let single = e.cmp(Cc::Eq, count, one);
    e.if_ret(single, |e| {
        let w = e.ld_int(ends, i);
        let bit = e.b.binop(Op::And, w, one);
        let unsorted = e.sub(one, bit);
        e.b.ret(Some(unsorted));
    });
    // The run before `i` ends where run `i` starts.
    let has_prev = e.cmp(Cc::Gt, i, zero);
    let start = e.pick(
        Ty::INT,
        has_prev,
        |e| {
            let p = e.add_k(i, -1);
            end_of(e, p)
        },
        |e| e.int(0),
    );
    let last = e.add_k(j, -1);
    let finish = end_of(&mut e, last);
    let span = e.sub(finish, start);
    let half = e.b.binop(Op::Sshr, span, one);
    let target = e.add(start, half);
    // Split after the first run that reaches the middle of the data, leaving one run on the right.
    let first = e.add_k(i, 1);
    let kv = e.var(first);
    e.loop_(|e, exit| {
        let k = e.get(kv);
        let at_last = e.cmp(Cc::Ge, k, last);
        e.brk_if(at_last, exit);
        let pk = e.add_k(k, -1);
        let reach = end_of(e, pk);
        let enough = e.cmp(Cc::Ge, reach, target);
        e.brk_if(enough, exit);
        let k1 = e.add_k(k, 1);
        e.set(kv, k1);
    });
    let k = e.get(kv);
    let pk = e.add_k(k, -1);
    let mid = end_of(&mut e, pk);
    let left = e.b.call(parts.msort, &[items, buf, ends, i, k, limit, env]);
    let right = e.b.call(parts.msort, &[items, buf, ends, k, j, limit, env]);
    let both = e.b.binop(Op::And, left, right);
    let merged_open = e.cmp(Cc::Ne, both, zero);
    e.if_ret(merged_open, |e| e.b.ret(Some(one)));
    let dummy = e.ld(items, start);
    let left_open = e.cmp(Cc::Ne, left, zero);
    e.if_(left_open, |e| {
        e.b.call(
            parts.quick,
            &[items, buf, start, mid, zero, dummy, limit, env],
        );
    });
    let right_open = e.cmp(Cc::Ne, right, zero);
    e.if_(right_open, |e| {
        e.b.call(
            parts.quick,
            &[items, buf, mid, finish, zero, dummy, limit, env],
        );
    });
    e.b.call(parts.merge, &[items, buf, start, mid, finish, env]);
    e.b.ret(Some(zero));
    fb.into_func()
}

/// `drift(scratch, items, 0, n, env)`: the entry point (see [`build_drift`]).
fn build_top(
    m: &mut Module,
    g: FuncId,
    elem: Ty,
    name: &str,
    params: Vec<Param>,
    parts: &Parts,
) -> Func {
    let mut fb = start(m, name, params, Ty::UNIT);
    let a = fb.params();
    let (buf, items, n, env) = (a[0], a[1], a[3], a[4]);
    let mut e = Em {
        b: &mut fb,
        elem,
        g,
    };
    let zero = e.int(0);
    let one = e.int(1);
    let small = e.int(SMALL);
    let few = e.cmp(Cc::Le, n, small);
    e.if_ret(few, |e| {
        e.b.call(parts.ins, &[items, zero, n, env]);
        e.unit_ret();
    });
    // The shortest run kept as it is: 64, or about the square root of `n` for long inputs.
    let sixty_four = e.int(64);
    let wide = e.int(4096);
    let long = e.cmp(Cc::Gt, n, wide);
    let half = e.b.binop(Op::Sshr, n, one);
    let upper = e.sub(n, half);
    let short_cut = e.cmp(Cc::Lt, upper, sixty_four);
    let short_min = e.b.select(short_cut, upper, sixty_four);
    let sv = e.var(sixty_four);
    e.if_(long, |e| {
        e.loop_(|e, exit| {
            let s = e.get(sv);
            let sq = e.b.binop(Op::IMul, s, s);
            let enough = e.cmp(Cc::Ge, sq, n);
            e.brk_if(enough, exit);
            let two = e.int(2);
            let s2 = e.b.binop(Op::IMul, s, two);
            e.set(sv, s2);
        });
    });
    let root = e.get(sv);
    let min_run = e.b.select(long, root, short_min);
    // Quicksort depth: twice the floor of log2 of `n`.
    let tv = e.var(n);
    let lv = e.var(zero);
    e.loop_(|e, exit| {
        let t = e.get(tv);
        let done = e.cmp(Cc::Le, t, one);
        e.brk_if(done, exit);
        let t1 = e.b.binop(Op::Sshr, t, one);
        e.set(tv, t1);
        let l = e.get(lv);
        let l1 = e.add_k(l, 1);
        e.set(lv, l1);
    });
    let l = e.get(lv);
    let limit = e.b.binop(Op::IAdd, l, l);
    let max_runs = e.b.binop(Op::SDiv, n, min_run);
    let cap = e.add_k(max_runs, 2);
    let ends = e.b.list_new(Ty::INT, cap);
    // Cut the input into runs.
    let (pv, rv) = (e.var(zero), e.var(zero));
    e.loop_(|e, exit| {
        let pos = e.get(pv);
        let done = e.cmp(Cc::Ge, pos, n);
        e.brk_if(done, exit);
        let left = e.sub(n, pos);
        // A natural run: non-descending, or strictly descending.
        let two = e.int(2);
        let pair = e.cmp(Cc::Ge, left, two);
        let (lenv, descv) = (e.var(one), e.var(zero));
        e.if_(pair, |e| {
            let p1 = e.add_k(pos, 1);
            let (x1, x0) = (e.ld(items, p1), e.ld(items, pos));
            let down = e.less(env, x1, x0);
            let d = e.b2i(down);
            e.set(descv, d);
            e.set(lenv, two);
            e.loop_(|e, stop| {
                let len = e.get(lenv);
                let at = e.add(pos, len);
                let end = e.cmp(Cc::Ge, at, n);
                e.brk_if(end, stop);
                let before = e.add_k(at, -1);
                let (cur, prev) = (e.ld(items, at), e.ld(items, before));
                let step = e.less(env, cur, prev);
                let s = e.b2i(step);
                let d = e.get(descv);
                let stops = e.cmp(Cc::Ne, s, d);
                e.brk_if(stops, stop);
                let len1 = e.add_k(len, 1);
                e.set(lenv, len1);
            });
        });
        let len = e.get(lenv);
        let kept = e.cmp(Cc::Ge, len, min_run);
        let entry = e.pick(
            Ty::INT,
            kept,
            |e| {
                let down = e.get(descv);
                let flip = e.cmp(Cc::Ne, down, zero);
                let end = e.add(pos, len);
                e.if_(flip, |e| {
                    // Reverse the descending run in place.
                    let (fv, bv) = (e.var(pos), e.var(end));
                    e.loop_(|e, stop| {
                        let (f, b) = (e.get(fv), e.get(bv));
                        let b1 = e.add_k(b, -1);
                        let crossed = e.cmp(Cc::Ge, f, b1);
                        e.brk_if(crossed, stop);
                        let (x, y) = (e.ld(items, f), e.ld(items, b1));
                        e.st(items, f, y);
                        e.st(items, b1, x);
                        let f1 = e.add_k(f, 1);
                        e.set(fv, f1);
                        e.set(bv, b1);
                    });
                });
                let shifted = e.b.binop(Op::Shl, end, one);
                e.b.binop(Op::Or, shifted, one)
            },
            |e| {
                let rest = e.sub(n, pos);
                let fits = e.cmp(Cc::Lt, rest, min_run);
                let chunk = e.b.select(fits, rest, min_run);
                let end = e.add(pos, chunk);
                e.b.binop(Op::Shl, end, one)
            },
        );
        let end = e.b.binop(Op::Sshr, entry, one);
        let r = e.get(rv);
        e.st_int(ends, r, entry);
        let r1 = e.add_k(r, 1);
        e.set(rv, r1);
        e.set(pv, end);
    });
    let runs = e.get(rv);
    let open =
        e.b.call(parts.msort, &[items, buf, ends, zero, runs, limit, env]);
    let dummy = e.ld(items, zero);
    let unsorted = e.cmp(Cc::Ne, open, zero);
    e.if_(unsorted, |e| {
        e.b.call(parts.quick, &[items, buf, zero, n, zero, dummy, limit, env]);
    });
    e.b.emit(Op::Drop, &[ends], Imm::None, None);
    e.unit_ret();
    fb.into_func()
}
