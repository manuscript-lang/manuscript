//! Structural equality helpers for aggregate types.

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use crate::text::{runtime_fn, ty_name};
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, FuncId, Imm, Mode, Module, Op, Param, Value};
use ms_mir::types::{Ty as MTy, TyKind};

impl Cx {
    /// The function comparing two values of `t` (reserved on first use).
    pub(crate) fn eq_fn(&mut self, m: &mut Module, t: MTy) -> FuncId {
        let key = format!("eq:{}", t.0);
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
            kind: JobKind::Equal(t),
        });
        id
    }
}

/// Compares two borrowed operands of type `t`.
pub(crate) fn element_eq(
    cx: &mut Cx,
    b: &mut FuncBuilder<'_>,
    t: MTy,
    x: Value,
    y: Value,
) -> Result<Value, Error> {
    if t == MTy::INT || t == MTy::BOOL {
        return Ok(b.icmp(Cc::Eq, x, y));
    }
    if t == MTy::FLOAT {
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
            let f = cx.eq_fn(b.m, t);
            Ok(b.call(f, &[x, y]))
        }
        _ => Err(Error::new(format!(
            "equality on {} is not supported",
            ty_name(b.m, t)
        ))),
    }
}

/// Builds the body of an equality helper.
pub(crate) fn build_eq(cx: &mut Cx, m: &mut Module, func: FuncId, t: MTy) -> Result<(), Error> {
    let p = Param {
        ty: t,
        mode: Mode::Borrow,
    };
    let mut b = FuncBuilder::new(m, "equal", vec![p, p], MTy::BOOL);
    let (x, y) = (b.params()[0], b.params()[1]);
    let no = b.new_block();
    let yes = b.new_block();
    match b.m.types.kind(t).clone() {
        TyKind::Rec(r) => {
            let fields = b.m.records[r.index()].fields.clone();
            for (i, (_, ft)) in fields.iter().enumerate() {
                let (l, rr) = (b.rec_get(r, i as u32, x), b.rec_get(r, i as u32, y));
                let e = element_eq(cx, &mut b, *ft, l, rr)?;
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
                    let e = element_eq(cx, &mut b, *ft, l, r)?;
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
            let e = element_eq(cx, &mut b, inner, l, r)?;
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
            let e = element_eq(cx, &mut b, elem, l, r)?;
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
