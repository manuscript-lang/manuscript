//! Structural equality helpers for aggregate types.

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use crate::text::{runtime_fn, ty_name};
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, FuncId, Imm, Mode, Module, Op, Param, Value};
use ms_mir::types::{Ty as MTy, TyKind};

impl Cx {
    /// The function comparing two values of `t` (reserved on first use). `scope` is the
    /// number of the module whose local implementations it calls, `0` for none.
    pub(crate) fn eq_fn(&mut self, m: &mut Module, t: MTy, scope: u32) -> FuncId {
        let key = format!("eq:{}:{scope}", t.0);
        if let Some(f) = self.helpers.get(&key) {
            return *f;
        }
        let p = Param {
            ty: t,
            mode: Mode::Borrow,
        };
        let f = ms_mir::ir::Func::new("equal", vec![p, p], MTy::BOOL);
        let id = m.add_func(f);
        self.helpers.insert(key, id);
        self.queue.push(Job {
            func: id,
            kind: JobKind::Equal(t, scope),
        });
        id
    }
}

/// Whether values of `t` can be compared structurally.
fn comparable(m: &Module, t: MTy, visiting: &mut Vec<MTy>) -> bool {
    if visiting.contains(&t) {
        return true;
    }
    visiting.push(t);
    let ok = match m.types.kind(t).clone() {
        TyKind::Rec(r) => m.records[r.index()]
            .fields
            .iter()
            .all(|f| comparable(m, f.1, visiting)),
        TyKind::Alt(a) => m.alts[a.index()]
            .cases
            .iter()
            .all(|c| c.fields.iter().all(|f| comparable(m, f.1, visiting))),
        TyKind::List(e) | TyKind::Opt(e) => comparable(m, e, visiting),
        TyKind::Iface(_) | TyKind::Fn(..) => false,
        _ => true,
    };
    visiting.pop();
    ok
}

/// Compares two borrowed operands of type `t`.
pub(crate) fn element_eq(
    cx: &mut Cx,
    b: &mut FuncBuilder<'_>,
    scope: u32,
    t: MTy,
    x: Value,
    y: Value,
) -> Result<Value, Error> {
    if b.m.types.is_int(t) || t == MTy::BOOL {
        return Ok(b.icmp(Cc::Eq, x, y));
    }
    if b.m.types.is_float(t) {
        return Ok(b.fcmp(Cc::Eq, x, y));
    }
    if t == MTy::UNIT {
        return Ok(b.bconst(true));
    }
    if t == MTy::STR {
        let ext = runtime_fn(b.m, "msrt_string_eq", &[MTy::STR, MTy::STR], MTy::BOOL);
        return Ok(b.call_rt(ext, &[x, y]));
    }
    match b.m.types.kind(t) {
        TyKind::Bytes | TyKind::Obj(..) => {
            let d = b
                .emit(Op::TypeDesc, &[], Imm::Ty(t), Some(MTy::PTR))
                .expect("typedesc");
            let ext = runtime_fn(b.m, "msrt_slot_eq", &[MTy::PTR, t, t], MTy::BOOL);
            Ok(b.call_rt(ext, &[d, x, y]))
        }
        TyKind::Rec(_) | TyKind::Alt(_) | TyKind::Opt(_) | TyKind::List(_) => {
            let scope = if cx.holds_extension(b.m, t) { scope } else { 0 };
            let f = cx.eq_fn(b.m, t, scope);
            Ok(b.call(f, &[x, y]))
        }
        _ => Err(Error::new(format!(
            "equality on {} is not supported",
            ty_name(b.m, t)
        ))),
    }
}

/// Builds the body of an equality helper.
pub(crate) fn build_eq(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    t: MTy,
    scope: u32,
) -> Result<(), Error> {
    let module = cx.scope_name(scope);
    let p = Param {
        ty: t,
        mode: Mode::Borrow,
    };
    if let Some(concrete) = cx.source_tys.get(&t).cloned()
        && let Some((callee, iface)) = cx.user_equals(m, &concrete, module)?
    {
        {
            let vt = cx.vtable_id(m, &concrete, iface, module)?;
            let other_mode = m.funcs[callee.index()].params[1].mode;
            let iface_ty = m.funcs[callee.index()].params[1].ty;
            let mut b = FuncBuilder::new(m, "equal", vec![p, p], MTy::BOOL);
            let (x, y) = (b.params()[0], b.params()[1]);
            let copy = if b.m.needs_drop(t) {
                b.emit(Op::Copy, &[y], Imm::None, Some(t)).expect("copy")
            } else {
                y
            };
            let boxed = b
                .emit(Op::IfaceNew, &[copy], Imm::Vtable(vt), Some(iface_ty))
                .expect("iface");
            let r = b.call(callee, &[x, boxed]);
            if other_mode == Mode::Borrow {
                b.emit(Op::Drop, &[boxed], Imm::None, None);
            }
            b.ret(Some(r));
            m.funcs[func.index()] = b.into_func();
            return Ok(());
        }
    }
    let mut b = FuncBuilder::new(m, "equal", vec![p, p], MTy::BOOL);
    let (x, y) = (b.params()[0], b.params()[1]);
    let no = b.new_block();
    let yes = b.new_block();
    match b.m.types.kind(t).clone() {
        TyKind::Rec(r) => {
            let fields = b.m.records[r.index()].fields.clone();
            for (i, (_, ft)) in fields.iter().enumerate() {
                let (l, rr) = (b.rec_get(r, i as u32, x), b.rec_get(r, i as u32, y));
                let e = element_eq(cx, &mut b, scope, *ft, l, rr)?;
                let next = b.new_block();
                b.br_if(e, next, &[], no, &[]);
                b.seal_block(next);
                b.switch_to(next);
            }
            b.br(yes, &[]);
        }
        TyKind::Alt(a) => {
            let cases = b.m.alts[a.index()].cases.clone();
            let (tx, ty_) = (b.alt_tag(x), b.alt_tag(y));
            let same = b.icmp(Cc::Eq, tx, ty_);
            let dispatch = b.new_block();
            b.br_if(same, dispatch, &[], no, &[]);
            b.seal_block(dispatch);
            b.switch_to(dispatch);
            let blocks: Vec<_> = cases.iter().map(|_| b.new_block()).collect();
            let arms: Vec<(i64, _)> = blocks
                .iter()
                .enumerate()
                .map(|(i, k)| (i as i64, *k))
                .collect();
            b.switch(tx, &arms, yes);
            for (i, c) in cases.iter().enumerate() {
                b.seal_block(blocks[i]);
                b.switch_to(blocks[i]);
                for (j, (_, ft)) in c.fields.iter().enumerate() {
                    let l = b.alt_get(a, i as u32, j as u32, x);
                    let r = b.alt_get(a, i as u32, j as u32, y);
                    let e = element_eq(cx, &mut b, scope, *ft, l, r)?;
                    let next = b.new_block();
                    b.br_if(e, next, &[], no, &[]);
                    b.seal_block(next);
                    b.switch_to(next);
                }
                b.br(yes, &[]);
            }
        }
        TyKind::Opt(inner) => {
            let (sx, sy) = (b.opt_is_some(x), b.opt_is_some(y));
            let same = b.icmp(Cc::Eq, sx, sy);
            let (both, check) = (b.new_block(), b.new_block());
            b.br_if(same, check, &[], no, &[]);
            b.seal_block(check);
            b.switch_to(check);
            b.br_if(sx, both, &[], yes, &[]);
            b.seal_block(both);
            b.switch_to(both);
            let (l, r) = (b.opt_get(x), b.opt_get(y));
            let e = element_eq(cx, &mut b, scope, inner, l, r)?;
            b.br_if(e, yes, &[], no, &[]);
        }
        TyKind::List(elem) => {
            let (nx, ny) = (b.list_len(x), b.list_len(y));
            let same = b.icmp(Cc::Eq, nx, ny);
            let (header, body, latch) = (b.new_block(), b.new_block(), b.new_block());
            let idx = b.declare_var(MTy::INT, Mode::Borrow);
            let zero = b.iconst(0);
            b.def_var(idx, zero);
            b.br_if(same, header, &[], no, &[]);
            b.switch_to(header);
            let i = b.use_var(idx);
            let more = b.icmp(Cc::Lt, i, nx);
            b.br_if(more, body, &[], yes, &[]);
            b.seal_block(body);
            b.switch_to(body);
            let i = b.use_var(idx);
            let (l, r) = (b.list_get(x, i), b.list_get(y, i));
            let e = element_eq(cx, &mut b, scope, elem, l, r)?;
            b.br_if(e, latch, &[], no, &[]);
            b.seal_block(latch);
            b.switch_to(latch);
            let i = b.use_var(idx);
            let one = b.iconst(1);
            let next = b.binop(Op::IAdd, i, one);
            b.def_var(idx, next);
            b.br(header, &[]);
            b.seal_block(header);
        }
        _ => {
            return Err(Error::new(format!(
                "equality on {} is not supported",
                ty_name(b.m, t)
            )));
        }
    }
    b.seal_block(no);
    b.seal_block(yes);
    b.switch_to(no);
    let f = b.bconst(false);
    b.ret(Some(f));
    b.switch_to(yes);
    let tr = b.bconst(true);
    b.ret(Some(tr));
    let mut f = b.into_func();
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

impl Cx {
    /// Registers the equality and hash functions the runtime reaches through the descriptor of
    /// `t`, and of the aggregates inside it.
    pub(crate) fn ensure_glue(&mut self, m: &mut Module, t: MTy, scope: u32) {
        if !self.glue_seen.insert((t, scope)) {
            return;
        }
        let inner: Vec<MTy> = match m.types.kind(t).clone() {
            TyKind::Rec(r) => m.records[r.index()].fields.iter().map(|f| f.1).collect(),
            TyKind::Alt(a) => m.alts[a.index()]
                .cases
                .iter()
                .flat_map(|c| c.fields.iter().map(|f| f.1))
                .collect(),
            TyKind::List(e) | TyKind::Opt(e) => vec![e],
            TyKind::Obj(_, args) => args,
            _ => return,
        };
        for i in inner {
            self.ensure_glue(m, i, scope);
        }
        // An optional scalar is a flag and a value with padding between: it compares through glue.
        let scalar_opt = matches!(m.types.kind(t), TyKind::Opt(i) if matches!(*i, MTy::INT | MTy::FLOAT | MTy::BOOL));
        if !scalar_opt && !matches!(m.types.kind(t), TyKind::Rec(_) | TyKind::Alt(_)) {
            return;
        }
        // Types holding interface or function values never compare, so they need no glue.
        if !comparable(m, t, &mut Vec::new()) {
            return;
        }
        let eq = self.eq_fn(m, t, scope);
        let module = self.scope_name(scope);
        let user_hash = match self.source_tys.get(&t).cloned() {
            Some(concrete) => self.user_hash(m, &concrete, module).ok().flatten(),
            None => None,
        };
        let (eq, hash) = (self.eq_adapter(m, t, eq), hash_adapter(m, t, user_hash));
        m.desc_glue.push((t.scoped(scope), eq, hash));
    }

    /// `fn(ptr, ptr) -> bool` over the equality helper.
    fn eq_adapter(&mut self, m: &mut Module, t: MTy, eq: FuncId) -> FuncId {
        let p = Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        };
        let mut b = FuncBuilder::new(m, "desc.eq", vec![p, p], MTy::BOOL);
        b.func_mut().linkage = ms_mir::ir::Linkage::Internal;
        let args = b.params();
        let load = |b: &mut FuncBuilder<'_>, a: Value| {
            b.emit(Op::Load, &[a], Imm::Ty(t), Some(t)).expect("load")
        };
        let (x, y) = (load(&mut b, args[0]), load(&mut b, args[1]));
        let r = b.call(eq, &[x, y]);
        b.ret(Some(r));
        let f = b.into_func();
        m.add_func(f)
    }
}

/// `fn(ptr) -> int`: equal values hash equally. Only the leaves that are cheap to reach
/// contribute (integers, booleans, strings, enum tags and nested records).
fn hash_adapter(m: &mut Module, t: MTy, user: Option<FuncId>) -> FuncId {
    let p = Param {
        ty: MTy::PTR,
        mode: Mode::Borrow,
    };
    let mut b = FuncBuilder::new(m, "desc.hash", vec![p], MTy::INT);
    b.func_mut().linkage = ms_mir::ir::Linkage::Internal;
    let arg = b.params()[0];
    let v = b.emit(Op::Load, &[arg], Imm::Ty(t), Some(t)).expect("load");
    let h = match user {
        // An `impl Hashable` decides: equal keys under the source `equals` hash the same.
        Some(f) => b.call(f, &[v]),
        None => {
            let seed = b.iconst(17);
            hash_into(&mut b, t, v, seed)
        }
    };
    b.ret(Some(h));
    let f = b.into_func();
    m.add_func(f)
}

fn hash_into(b: &mut FuncBuilder<'_>, t: MTy, v: Value, acc: Value) -> Value {
    let combine = |b: &mut FuncBuilder<'_>, acc: Value, leaf: Value| {
        let ext = runtime_fn(b.m, "msrt_hash_combine", &[MTy::INT, MTy::INT], MTy::INT);
        b.call_rt(ext, &[acc, leaf])
    };
    if b.m.types.is_int(t) {
        let ext = runtime_fn(b.m, "msrt_hash_int", &[t], MTy::INT);
        let leaf = b.call_rt(ext, &[v]);
        return combine(b, acc, leaf);
    }
    if t == MTy::BOOL {
        let leaf = b
            .emit(Op::B2I, &[v], Imm::None, Some(MTy::INT))
            .expect("b2i");
        return combine(b, acc, leaf);
    }
    if t == MTy::STR {
        let ext = runtime_fn(b.m, "msrt_string_hash", &[MTy::STR], MTy::INT);
        let leaf = b.call_rt(ext, &[v]);
        return combine(b, acc, leaf);
    }
    match b.m.types.kind(t).clone() {
        TyKind::Rec(r) => {
            let fields: Vec<MTy> = b.m.records[r.index()].fields.iter().map(|f| f.1).collect();
            let mut acc = acc;
            for (i, ft) in fields.into_iter().enumerate() {
                let f = b.rec_get(r, i as u32, v);
                acc = hash_into(b, ft, f, acc);
            }
            acc
        }
        TyKind::Alt(_) => {
            let tag = b.alt_tag(v);
            combine(b, acc, tag)
        }
        TyKind::Opt(inner) => {
            let some = b.opt_is_some(v);
            let flag = b
                .emit(Op::B2I, &[some], Imm::None, Some(MTy::INT))
                .expect("b2i");
            let acc = combine(b, acc, flag);
            if !b.m.types.is_int(inner) && inner != MTy::BOOL {
                return acc;
            }
            let x = b.opt_get(v);
            let with_value = hash_into(b, inner, x, acc);
            b.select(some, with_value, acc)
        }
        _ => acc,
    }
}
