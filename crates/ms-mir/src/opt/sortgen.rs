//! Sorts of word lists by a known, capture-free comparator, compiled with the program.
//!
//! The runtime sort calls its comparator through a pointer once per comparison, which keeps
//! the comparator from being inlined. When the comparator is a closure the module already
//! knows (see `inline::specialize_sort_thunks`), the call to `msrt_list_sorted` is replaced
//! by a copy of the list and a call to a generated merge sort that calls the closure's code
//! directly, so the backend can inline it into the merge loop.
//!
//! The generated sort is the runtime's `merge_sort_word` step for step: it makes the same
//! comparator calls in the same order, which is observable when the comparator has effects.

use crate::builder::FuncBuilder;
use crate::ir::{
    Cc, ExternDef, Func, FuncId, FuncKind, Imm, Inst, Mode, Module, Op, Param, Term, Value,
};
use crate::types::Ty;
use std::collections::HashMap;

/// Largest slice sorted by insertion, as in the runtime.
const INSERTION_MAX: i64 = 12;

/// Replaces runtime sorts that have a known comparator; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    let mut made: HashMap<FuncId, FuncId> = HashMap::new();
    for fi in 0..m.funcs.len() {
        let mut known: HashMap<Value, FuncId> = HashMap::new();
        let mut thunks: HashMap<Value, FuncId> = HashMap::new();
        for inst in m.funcs[fi].blocks.iter().flat_map(|b| b.insts.iter()) {
            match (inst.op, inst.imm, inst.res) {
                (Op::ClosureNew, Imm::Func(g), Some(r)) if inst.args.is_empty() => {
                    known.insert(r, g);
                }
                (Op::FuncAddr, Imm::Func(t), Some(r))
                    if m.funcs[t.index()].name.starts_with("sort.cmp.") =>
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
                if m.externs[e.index()].name != "msrt_list_sorted" {
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
            let sort = *made.entry(g).or_insert_with(|| build(m, g, elem));
            rewrite(&mut m.funcs[fi], bi, ii, sort, elem);
            changed = true;
        }
    }
    changed
}

/// The element type when the sort is over plain 8-byte values and `g` has the shape
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
    (shaped && (elem == Ty::INT || elem == Ty::FLOAT)).then_some(elem)
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
/// The body may only compare the two arguments with each other, branch on those comparisons
/// and return constants, so its result depends on nothing but the ordering of `a` and `b` and
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
        }
        let mut env: HashMap<Value, V> = HashMap::new();
        env.insert(a, V::Arg(x));
        env.insert(b, V::Arg(y));
        let mut block = 0usize;
        for _ in 0..64 {
            let bd = &g.blocks[block];
            for inst in &bd.insts {
                let (res, v) = match (inst.op, inst.imm) {
                    (Op::IConst, Imm::Int(i)) => (inst.res?, V::Num(i)),
                    (Op::Copy, _) => (inst.res?, *env.get(inst.args.first()?)?),
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
                    (Op::DepthEnter | Op::DepthLeave, _) => continue,
                    _ => return None,
                };
                env.insert(res, v);
            }
            let target = match &bd.term {
                Term::Ret(Some(v)) => {
                    return match env.get(v)? {
                        V::Num(c) => Some(*c < 0),
                        V::Arg(_) => None,
                    };
                }
                Term::Br(t) => t,
                Term::CondBr { cond, then, els } => match env.get(cond)? {
                    V::Num(c) if *c != 0 => then,
                    V::Num(_) => els,
                    V::Arg(_) => return None,
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
        op: Op::Copy,
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
        op: Op::Copy,
        args: vec![list],
        imm: Imm::None,
        res: Some(out),
        loc: call.loc,
    };
    let (copy_buf, buf) = new(f, Op::Copy, vec![out], Imm::None, Some(list_ty));
    let buf = buf.expect("buffer");
    let (len, len_v) = new(f, Op::ListLen, vec![out], Imm::None, Some(Ty::INT));
    let (zero, zero_v) = new(f, Op::IConst, vec![], Imm::Int(0), Some(Ty::INT));
    let (env, env_v) = new(f, Op::Slot, vec![], Imm::Ty(elem), Some(Ty::PTR));
    let (run, _) = new(
        f,
        Op::Call,
        vec![
            out,
            buf,
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

/// Builds `sort(items, buf, lo, hi, env)`: stable merge sort of `items[lo..hi]` using `buf`
/// of the same length for scratch, ordering by the sign of `g(env, a, b)`.
fn build(m: &mut Module, g: FuncId, elem: Ty) -> FuncId {
    let list_ty = m.types.list(elem);
    let p = |ty| Param {
        ty,
        mode: Mode::Borrow,
    };
    let params = vec![p(list_ty), p(list_ty), p(Ty::INT), p(Ty::INT), p(Ty::PTR)];
    let name = format!("sort.merge.{}", m.funcs[g.index()].name);
    let id = m.add_func(Func::new(&name, params.clone(), Ty::UNIT));
    let mut b = FuncBuilder::new(m, &name, params, Ty::UNIT);
    let args = b.params();
    let (items, buf, lo, hi, env) = (args[0], args[1], args[2], args[3], args[4]);

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
    let pm = at(&mut b, items, mid);
    let a = load(&mut b, pm);
    let mm1 = b.binop(Op::ISub, mid, one);
    let pmm = at(&mut b, items, mm1);
    let c = load(&mut b, pmm);
    let unordered = less(&mut b, a, c);
    let (merge, finish) = (b.new_block(), b.new_block());
    b.br_if(unordered, merge, &[], finish, &[]);
    b.seal_block(merge);
    b.seal_block(finish);
    b.switch_to(finish);
    let u = b.unit();
    b.ret(Some(u));

    // Copy the slice to the buffer.
    b.switch_to(merge);
    let kv = int(&mut b);
    b.def_var(kv, lo);
    let (copy_head, copy_body, merged) = (b.new_block(), b.new_block(), b.new_block());
    b.br(copy_head, &[]);
    b.switch_to(copy_head);
    let k = b.use_var(kv);
    let go = b.icmp(Cc::Lt, k, hi);
    b.br_if(go, copy_body, &[], merged, &[]);
    b.seal_block(copy_body);
    b.seal_block(merged);
    b.switch_to(copy_body);
    let k = b.use_var(kv);
    let src = at(&mut b, items, k);
    let v = load(&mut b, src);
    let dst = at(&mut b, buf, k);
    store(&mut b, dst, v);
    let k1 = b.binop(Op::IAdd, k, one);
    b.def_var(kv, k1);
    b.br(copy_head, &[]);
    b.seal_block(copy_head);

    // Merge from both ends at once, two output slots per step.
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
