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
use ms_mir::types::{Ty as MTy, TyKind};

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
