//! `filter` and `map` chains over lists of numbers run as one loop.
//!
//! `xs.filter(f).map(g).sum()` built a list for each stage: an allocation, a push per element
//! and a second pass to read it back. When every callback is a lambda whose body only reads
//! (operators, names, fields, indexing; no call, so no effect other than a possible fault) and
//! every element in the chain is a number or a `Bool`, the stages instead run per element in one
//! loop and only the last result is built. Callbacks run per element rather than per stage; with
//! no effects the only visible difference is which fault is reported when two stages would
//! both fault.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::api::ast::*;
use ms_check::api::hir::Resolution;
use ms_check::api::types as ct;
use ms_mir::builder::Var;
use ms_mir::ir::{Cc, Imm, Mode, Op};
use ms_mir::types::{Ty as MTy, TyKind};

/// The per-scalar step of a fused scan: the scalar in, a flag that stops the scan out.
type ScalarBody<'b, S> =
    dyn FnMut(&mut S, ms_mir::ir::Value) -> Result<Option<ms_mir::ir::Value>, Error> + 'b;

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Map,
    Filter,
}

struct Stage<'e> {
    kind: Kind,
    /// The lambda argument.
    f: &'e Expr,
    /// The call, which is the stage's result list.
    call: &'e Expr,
    /// The receiver list expression.
    recv: &'e Expr,
}

/// A lambda of one by-value parameter whose body is one `return` of a reading expression.
fn simple_lambda(l: &Lambda) -> bool {
    l.params.len() == 1
        && !l.params[0].mutable
        && l.body.len() == 1
        && matches!(&l.body[0].kind, StmtKind::Return(Some(e)) if reading(e))
}

fn reading(e: &Expr) -> bool {
    match &e.kind {
        ExprKind::Number(_) | ExprKind::Bool(_) | ExprKind::Name(_) => true,
        ExprKind::Member { left, .. } => reading(left),
        ExprKind::Index { left, index } => reading(left) && reading(index),
        ExprKind::Unary { op, operand } => *op != UnaryOp::Try && reading(operand),
        ExprKind::Binary { left, right, .. } => reading(left) && reading(right),
        _ => false,
    }
}

impl FnLower<'_> {
    fn scalar(&self, t: MTy) -> bool {
        let ty = &self.b.m.types;
        t == MTy::BOOL || ty.is_int(t) || ty.is_float(t)
    }

    /// The element type of a list type.
    fn list_elem(&self, t: MTy) -> Option<MTy> {
        match self.b.m.types.kind(t) {
            TyKind::List(e) => Some(*e),
            _ => None,
        }
    }

    /// `e` as a `map` or `filter` stage: a lambda that only reads, over a list of numbers,
    /// producing one.
    fn stage_of<'e>(&mut self, e: &'e Expr) -> Result<Option<Stage<'e>>, Error> {
        let Some(view) = self.hir.call(e) else {
            return Ok(None);
        };
        let Resolution::Method(m) = &view.target else {
            return Ok(None);
        };
        let kind = match m.name().map(|n| self.syms.str(n)) {
            Some("map") => Kind::Map,
            Some("filter") => Kind::Filter,
            _ => return Ok(None),
        };
        if matches!(m.native, ct::Native::Source | ct::Native::Contract) {
            return Ok(None);
        }
        let (Some(recv), ExprKind::Call { args, .. }) = (self.receiver_expr(e), &e.kind) else {
            return Ok(None);
        };
        let [arg] = args.as_slice() else {
            return Ok(None);
        };
        let ExprKind::Lambda(l) = &arg.value.kind else {
            return Ok(None);
        };
        if arg.name.is_some() || arg.mutable || !simple_lambda(l) {
            return Ok(None);
        }
        let (rt, ot) = (self.emty(recv)?, self.emty(e)?);
        let (Some(from), Some(to)) = (self.list_elem(rt), self.list_elem(ot)) else {
            return Ok(None);
        };
        if !self.scalar(from) || !self.scalar(to) {
            return Ok(None);
        }
        Ok(Some(Stage {
            kind,
            f: &arg.value,
            call: e,
            recv,
        }))
    }

    /// The stages of the chain that ends at `e` (itself included), first stage first, and the
    /// list expression they read.
    fn chain_of<'e>(&mut self, e: &'e Expr) -> Result<(Vec<Stage<'e>>, &'e Expr), Error> {
        let mut stages = Vec::new();
        let mut at = e;
        while let Some(s) = self.stage_of(at)? {
            at = s.recv;
            stages.push(s);
        }
        stages.reverse();
        Ok((stages, at))
    }

    /// `text.scalar_values().all(f)` (also `any` and `count`) with a reading lambda: the callback
    /// runs on each scalar as the string is decoded, so no list of scalars is built.
    pub(crate) fn fused_scalar_scan(
        &mut self,
        e: &Expr,
        m: &ct::MethodRef,
        recv_expr: &Expr,
    ) -> Result<Option<Val>, Error> {
        let name = match m.name().map(|n| self.syms.str(n)) {
            Some(n @ ("all" | "any" | "count")) => n.to_string(),
            _ => return Ok(None),
        };
        if matches!(m.native, ct::Native::Source | ct::Native::Contract) {
            return Ok(None);
        }
        let ExprKind::Call { args, .. } = &e.kind else {
            return Ok(None);
        };
        let [arg] = args.as_slice() else {
            return Ok(None);
        };
        let ExprKind::Lambda(l) = &arg.value.kind else {
            return Ok(None);
        };
        if arg.name.is_some() || arg.mutable || !simple_lambda(l) {
            return Ok(None);
        }
        let ExprKind::Call { callee, args: none } = &recv_expr.kind else {
            return Ok(None);
        };
        let ExprKind::Member {
            left: text_expr,
            name: inner,
        } = &callee.kind
        else {
            return Ok(None);
        };
        if !none.is_empty() || self.syms.str(inner) != "scalar_values" {
            return Ok(None);
        }
        let Some(Resolution::Method(inner_m)) = self.hir.call(recv_expr).map(|v| v.target) else {
            return Ok(None);
        };
        let text_ty = self.emty(text_expr)?;
        if inner_m.native == ct::Native::Source
            || !matches!(self.b.m.types.kind(text_ty), TyKind::Str)
        {
            return Ok(None);
        }
        let text = self.expr(text_expr)?;
        if self.dead {
            return Ok(Some(text));
        }
        let f = self.expr(&arg.value)?;
        if self.dead {
            return Ok(Some(f));
        }
        let (fvar, fhidden) = self.callback_var(f);
        let hidden = text.own && self.needs_drop(MTy::STR);
        let tvar = self
            .b
            .declare_var(MTy::STR, if hidden { Mode::Move } else { Mode::Borrow });
        self.b.def_var(tvar, text.v);
        let counting = name == "count";
        let any = name == "any";
        let acc = self
            .b
            .declare_var(if counting { MTy::INT } else { MTy::BOOL }, Mode::Borrow);
        let init = if counting {
            self.b.iconst(0)
        } else {
            self.b.bconst(!any)
        };
        self.b.def_var(acc, init);
        self.each_scalar(tvar, &mut |s, x| {
            let r = {
                let f = s.b.use_var(fvar);
                s.b.call_ind(f, &[x])
            };
            let cur = s.b.use_var(acc);
            if counting {
                let (one, zero) = (s.b.iconst(1), s.b.iconst(0));
                let inc = s.b.select(r, one, zero);
                let next = s.b.binop(Op::IAdd, cur, inc);
                s.b.def_var(acc, next);
                return Ok(None);
            }
            let hit = if any { r } else { s.b.unop(Op::Not, r) };
            let t = s.b.bconst(any);
            let next = s.b.select(hit, t, cur);
            s.b.def_var(acc, next);
            Ok(Some(hit))
        })?;
        if hidden {
            let v = self.b.use_var(tvar);
            self.drop_value(v);
        }
        self.release_source(fvar, fhidden);
        Ok(Some(Val {
            v: self.b.use_var(acc),
            own: false,
        }))
    }

    /// Runs `body` on each scalar value of the string in `tvar`, ASCII bytes inline and other
    /// characters decoded by the runtime; the body returns a flag that stops the scan.
    fn each_scalar(&mut self, tvar: Var, body: &mut ScalarBody<'_, Self>) -> Result<(), Error> {
        let s = self.b.use_var(tvar);
        let len = self.b.str_bytes(s);
        let idx = self.b.declare_var(MTy::INT, Mode::Borrow);
        let zero = self.b.iconst(0);
        self.b.def_var(idx, zero);
        let cur = self.b.declare_var(MTy::INT, Mode::Borrow);
        let (header, scan, fast, slow, join, exit) = (
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
        );
        self.b.br(header, &[]);
        self.b.switch_to(header);
        let i = self.b.use_var(idx);
        let more = self.b.icmp(Cc::Lt, i, len);
        self.b.br_if(more, scan, &[], exit, &[]);
        self.b.seal_block(scan);
        self.b.switch_to(scan);
        let s = self.b.use_var(tvar);
        let i = self.b.use_var(idx);
        let byte = self
            .b
            .emit(Op::StrByte, &[s, i], Imm::None, Some(MTy::INT))
            .expect("byte");
        let limit = self.b.iconst(128);
        let ascii = self.b.icmp(Cc::Lt, byte, limit);
        self.b.br_if(ascii, fast, &[], slow, &[]);
        self.b.seal_block(fast);
        self.b.seal_block(slow);
        self.b.switch_to(fast);
        let one = self.b.iconst(1);
        let next = self.b.binop(Op::IAdd, i, one);
        self.b.def_var(cur, byte);
        self.b.def_var(idx, next);
        self.b.br(join, &[]);
        self.b.switch_to(slow);
        let s = self.b.use_var(tvar);
        let i = self.b.use_var(idx);
        let step = self.call_runtime("msrt_string_scalar_step", &[s, i], MTy::INT)?;
        let three = self.b.iconst(3);
        let seven = self.b.iconst(7);
        let ch = self.b.binop(Op::Ushr, step, three);
        let width = self.b.binop(Op::And, step, seven);
        let next = self.b.binop(Op::IAdd, i, width);
        self.b.def_var(cur, ch);
        self.b.def_var(idx, next);
        self.b.br(join, &[]);
        self.b.seal_block(join);
        self.b.switch_to(join);
        let x = self.b.use_var(cur);
        let stop = body(self, x)?;
        match stop {
            Some(flag) => self.b.br_if(flag, exit, &[], header, &[]),
            None => self.b.br(header, &[]),
        }
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        Ok(())
    }

    /// Fuses a chain that ends in this call (`map`, `filter` or `sum`), when it can.
    pub(crate) fn fused_chain(
        &mut self,
        e: &Expr,
        m: &ct::MethodRef,
        recv_expr: &Expr,
    ) -> Result<Option<Val>, Error> {
        let sum = match m.name().map(|n| self.syms.str(n)) {
            Some("sum") => {
                if m.native != ct::Native::Source || !self.syms.str(m.module).starts_with("@std/") {
                    return Ok(None);
                }
                true
            }
            Some("map" | "filter") => false,
            _ => return Ok(None),
        };
        let (stages, src) = if sum {
            self.chain_of(recv_expr)?
        } else {
            self.chain_of(e)?
        };
        if stages.len() < if sum { 1 } else { 2 } {
            return Ok(None);
        }
        let last = stages.last().expect("a stage");
        let out = self.emty(last.call)?;
        let elem = self.list_elem(out).expect("list result");
        if sum && elem != MTy::INT && elem != MTy::FLOAT {
            return Ok(None);
        }
        let result = self.emty(e)?;

        let source = self.expr(src)?;
        if self.dead {
            return Ok(Some(source));
        }
        let (lv, hidden) = self.list_source(Some(src), source)?;
        let mut fns = Vec::with_capacity(stages.len());
        for s in &stages {
            let f = self.expr(s.f)?;
            if self.dead {
                return Ok(Some(f));
            }
            fns.push(self.callback_var(f));
        }
        let acc: Var = if sum {
            let acc = self.fresh_var(elem);
            let zero = if elem == MTy::INT {
                self.b.iconst(0)
            } else {
                self.b.fconst(0.0)
            };
            self.b.def_var(acc, zero);
            acc
        } else {
            let acc = self.fresh_var(result);
            let capacity = if stages.iter().all(|s| s.kind == Kind::Map) {
                let l = self.b.use_var(lv);
                self.b.list_len(l)
            } else {
                self.b.iconst(0)
            };
            let first = self.b.list_new(elem, capacity);
            self.b.def_var(acc, first);
            acc
        };
        let kinds: Vec<Kind> = stages.iter().map(|s| s.kind).collect();
        self.each_element(lv, &mut |s, _, x| {
            let skip = kinds.contains(&Kind::Filter).then(|| s.b.new_block());
            let mut x = x;
            for (kind, (fv, _)) in kinds.iter().zip(&fns) {
                let f = s.b.use_var(*fv);
                let r = s.b.call_ind(f, &[x]);
                match kind {
                    Kind::Map => x = r,
                    Kind::Filter => {
                        let keep = s.b.new_block();
                        s.b.br_if(r, keep, &[], skip.expect("skip block"), &[]);
                        s.b.seal_block(keep);
                        s.b.switch_to(keep);
                    }
                }
            }
            let cur = s.b.use_var(acc);
            let next = if sum {
                let total = Val { v: cur, own: false };
                s.arithmetic(
                    ms_check::api::ast::BinaryOp::Add,
                    elem,
                    total,
                    Val { v: x, own: false },
                )?
            } else {
                s.b.list_push(cur, x)
            };
            s.b.def_var(acc, next);
            if let Some(skip) = skip {
                s.b.br(skip, &[]);
                s.b.seal_block(skip);
                s.b.switch_to(skip);
            }
            Ok(None)
        })?;
        self.release_source(lv, hidden);
        for (fv, fhidden) in fns {
            self.release_source(fv, fhidden);
        }
        let v = self.b.use_var(acc);
        Ok(Some(Val { v, own: !sum }))
    }
}
