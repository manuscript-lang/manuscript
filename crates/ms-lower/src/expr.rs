//! Expression lowering.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::hir::Resolution;
use ms_check::types::{self as ct, Kind};
use ms_mir::ir::{Cc, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::*;

impl<'a> FnLower<'a> {
    /// A placeholder for the value of code that cannot run.
    pub fn dummy(&mut self, ty: MTy) -> Val {
        let v = self.b.func_mut().new_value(ty);
        Val { v, own: false }
    }

    /// The checked type of an expression under the instance substitution.
    pub fn ety(&self, e: &Expr) -> ct::Ty {
        ct::sub(&self.value_ty(e), &self.subst)
    }

    /// The MIR type of an expression.
    pub fn emty(&mut self, e: &Expr) -> Result<MTy, Error> {
        let t = self.value_ty(e);
        self.mty(&t)
    }

    /// The type of the value an expression computes: while it is lowered ahead of a conversion
    /// to an interface, its own type rather than the interface.
    fn value_ty(&self, e: &Expr) -> ct::Ty {
        match self.hir.info(e).error_source {
            Some(src) if self.converting == Some(e as *const Expr) => src,
            _ => self.hir.ty(e),
        }
    }

    /// Lowers an expression, converting at an Error boundary the checker marked.
    pub fn expr(&mut self, e: &Expr) -> Result<Val, Error> {
        let saved = self.converting;
        if self.hir.info(e).error_source.is_some() {
            self.converting = Some(e as *const Expr);
        }
        let x = self.expr_value(e);
        self.converting = saved;
        let x = x?;
        let x = match self.hir.info(e).wrap_some {
            Some(_)
                if !self.dead
                    && self.lent_return
                    && !x.own
                    && self.lent_expr == Some(e as *const Expr as usize) =>
            {
                // A lending function wraps a borrow as a borrow, as `some(value)` does.
                Val {
                    v: self.b.opt_view(x.v),
                    own: false,
                }
            }
            Some(_) if !self.dead => {
                let o = self.owned(x);
                Val {
                    v: self.b.opt_some(o),
                    own: true,
                }
            }
            _ => x,
        };
        match self.hir.info(e).error_source {
            Some(src) if !self.dead => {
                let want = self.emty(e)?;
                // An owned resource converted to an interface without `close` is only read (the
                // checker rejects owning positions), so it stays a temporary of the statement,
                // which closes it; the interface value reads a copy and never closes. An
                // interface with `close` takes the duty over with the value.
                let target = self.hir.ty(e);
                let hands_on = target.def.as_ref().is_some_and(|d| {
                    d.operations
                        .borrow()
                        .iter()
                        .any(|o| o.name.as_str() == "close")
                });
                let x = if x.own && !hands_on && self.is_resource(self.ty_of(x.v)) {
                    self.temps.push(x.v);
                    Val { v: x.v, own: false }
                } else {
                    x
                };
                let saved = self.scope_override;
                self.scope_override = self.evidence_of(std::slice::from_ref(&src));
                let out = self.fit_ty(x, &ct::sub(&src, &self.subst), want);
                self.scope_override = saved;
                out
            }
            _ => Ok(x),
        }
    }

    pub(crate) fn expr_value(&mut self, e: &Expr) -> Result<Val, Error> {
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        self.at(e.pos);
        match &e.kind {
            ExprKind::Number(text) => self.number(e, text.as_str(), false),
            ExprKind::Bool(b) => {
                let v = self.b.bconst(*b);
                Ok(Val { v, own: false })
            }
            ExprKind::Unit => {
                let v = self.b.unit();
                Ok(Val { v, own: false })
            }
            ExprKind::Text(parts) => self.text(parts),
            ExprKind::Name(_) => self.name(e),
            ExprKind::Member { left, name } => self.member(e, left, name.as_str()),
            ExprKind::Index { left, index } => self.index(e, left, index),
            ExprKind::Apply { value, .. } => match value {
                Some(v) if self.is_index_apply(e) => {
                    let ExprKind::Apply { left, .. } = &e.kind else {
                        unreachable!()
                    };
                    self.index(e, left, v)
                }
                _ => self.type_application(e),
            },
            ExprKind::List(items) => self.list_literal(e, items),
            ExprKind::Map(entries) => {
                let t = self.emty(e)?;
                self.map_literal(t, entries)
            }
            ExprKind::Unary { op, operand } => self.unary(e, *op, operand),
            ExprKind::Binary { op, left, right } => self.binary(e, *op, left, right),
            ExprKind::Lambda(_) => self.lambda(e),
            ExprKind::Call { .. } => self.call_expr(e),
            ExprKind::Match { scrutinee, arms } => self.match_expr(e, scrutinee, arms),
        }
    }

    /// Whether an `Apply` node is really an index read (`xs[i]`).
    fn is_index_apply(&self, e: &Expr) -> bool {
        crate::mutation::is_index_apply(&self.hir, e)
    }

    /// A method used as a value (`value.name`).
    fn method_value(&mut self, e: &Expr, left: &Expr, m: &ct::MethodRef) -> Result<Val, Error> {
        if m.native.as_str() == "to_string" && m.ty.params.is_empty() {
            return self.bound_to_string(left);
        }
        if !m.native.as_str().is_empty() && m.native.as_str() != "contract" {
            return self.bound_native_method(e, left, m);
        }
        self.bound_method(e, left, m)
    }

    /// `f[T]` or `value.method[T]` used as a value: the function or method specialized by the
    /// node's own checked type.
    fn type_application(&mut self, e: &Expr) -> Result<Val, Error> {
        let ExprKind::Apply { left, .. } = &e.kind else {
            return Err(Error::new("malformed type application"));
        };
        let res = match self.hir.resolution(left) {
            Resolution::Value => self.hir.resolution(e),
            r => r,
        };
        match (&left.kind, res) {
            (_, Resolution::Function(sym)) if sym.native.as_str().is_empty() => {
                self.function_value(e, &sym)
            }
            (_, Resolution::Function(sym)) => self.native_function_value(e, &sym),
            (ExprKind::Member { left: recv, .. }, Resolution::Method(m)) => {
                self.method_value(e, recv, &m)
            }
            (_, r) => Err(Error::new(format!(
                "type application as a value is not supported yet ({})",
                match r {
                    Resolution::Type(_) => "type",
                    Resolution::Constructor { .. } => "constructor",
                    Resolution::Native(_) => "native",
                    Resolution::Method(_) => "method",
                    Resolution::Local(_) => "local",
                    Resolution::Constant(_) => "constant",
                    _ => "other",
                }
            ))),
        }
    }

    // --------------------------------------------------------------- literals

    fn number(&mut self, e: &Expr, text: &str, negate: bool) -> Result<Val, Error> {
        let t = self.ety(e);
        match t.id.as_str() {
            "Int" | "Int8" | "Int16" | "Int32" | "Int64" | "UInt8" | "UInt16" | "UInt32" => {
                let n: i128 = parse_int(text)
                    .ok_or_else(|| Error::new(format!("bad integer literal {text}")))?;
                let n = if negate { -n } else { n };
                let n = i64::try_from(n).map_err(|_| Error::new("integer literal out of range"))?;
                let ty = self.mty(&t)?;
                let v = self.b.iconst_ty(n, ty);
                Ok(Val { v, own: false })
            }
            "UInt64" => {
                let n: i128 = parse_int(text)
                    .ok_or_else(|| Error::new(format!("bad integer literal {text}")))?;
                let n = u64::try_from(n).map_err(|_| Error::new("integer literal out of range"))?;
                let v = self.b.iconst_ty(n as i64, MTy::UINT64);
                Ok(Val { v, own: false })
            }
            "Float" | "Float32" | "Float64" => {
                let f: f64 = ms_syntax::number::canonical(text)
                    .parse()
                    .map_err(|_| Error::new(format!("bad float literal {text}")))?;
                let f = if negate { -f } else { f };
                let f = if ct::float_bits(&t) == Some(32) {
                    f64::from(f as f32)
                } else {
                    f
                };
                let ty = self.mty(&t)?;
                let v = self.b.fconst_ty(f, ty);
                Ok(Val { v, own: false })
            }
            "@std/Decimal" => {
                let dec = ms_std_decimal::Dec::parse(&ms_syntax::number::canonical(text))
                    .ok_or_else(|| Error::new(format!("invalid Decimal literal {text}")))?;
                let dec = if negate { dec.negate() } else { dec };
                let ty = self.emty(e)?;
                let TyKind::Rec(rid) = self.b.m.types.kind(ty).clone() else {
                    return Err(Error::new("Decimal is not a record"));
                };
                let fields = [dec.lo as i64, dec.hi, dec.exp].map(|n| self.b.iconst(n));
                let v = self.b.rec_new(rid, &fields);
                Ok(Val { v, own: false })
            }
            other => Err(Error::new(format!(
                "unsupported numeric literal type {other}"
            ))),
        }
    }

    fn list_literal(&mut self, e: &Expr, items: &[Expr]) -> Result<Val, Error> {
        let lt = self.emty(e)?;
        let TyKind::List(elem) = self.b.m.types.kind(lt).clone() else {
            return Err(Error::new("list literal of a non-list type"));
        };
        let mut vals = Vec::new();
        let mut pending = Vec::new();
        for (n, it) in items.iter().enumerate() {
            let x = self.expr(it)?;
            if self.dead {
                for v in pending {
                    self.unhold_temp(v);
                }
                return Ok(self.dummy(lt));
            }
            // Each element is copied when read, so later elements cannot change it. A later
            // element may return early (`try`): this copy stays a temporary until then.
            let o = self.owned(x);
            if self.needs_drop(self.ty_of(o)) && items[n + 1..].iter().any(crate::mutation::has_try)
            {
                self.temps.push(o);
                pending.push(o);
            }
            vals.push(o);
        }
        let v = self.b.list_lit(elem, &vals);
        for v in pending {
            self.unhold_temp(v);
        }
        Ok(Val { v, own: true })
    }

    // ----------------------------------------------------------------- names

    fn name(&mut self, e: &Expr) -> Result<Val, Error> {
        match self.hir.resolution(e) {
            Resolution::Local(b) => {
                let x = self.read_local(&b)?;
                self.moved_closer(b.uid, e);
                self.fit_function_value(e, x)
            }
            Resolution::Constant(_) => self.call_expr(e),
            Resolution::Constructor { ty, case } => self.construct_unit(e, &ty, case),
            Resolution::Function(sym) if sym.native.as_str().is_empty() => {
                self.function_value(e, &sym)
            }
            Resolution::Function(sym) => self.native_function_value(e, &sym),
            other => Err(Error::new(format!(
                "unsupported name {}",
                match other {
                    Resolution::Type(_) => "type",
                    Resolution::Method(_) => "method",
                    Resolution::Native(_) => "native",
                    _ => "value",
                }
            ))),
        }
    }

    /// A case without payload (`none`, `Color.red`).
    pub fn construct_unit(
        &mut self,
        e: &Expr,
        ty: &ct::Ty,
        case: Option<ct::Name>,
    ) -> Result<Val, Error> {
        let _ = e;
        let t = ct::sub(ty, &self.subst);
        let mt = self.cx.lower_ty(self.b.m, &t)?;
        let Some(case) = case else {
            return Err(Error::new("type used as a value"));
        };
        if t.is_std("Optional") {
            let v = self.b.opt_none(mt);
            return Ok(Val { v, own: false });
        }
        let TyKind::Alt(a) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("case of a non-alternative"));
        };
        let idx = self.b.m.alts[a.index()]
            .cases
            .iter()
            .position(|c| c.name == case.as_str())
            .ok_or_else(|| Error::new(format!("no case {case}")))?;
        let v = self.b.alt_new(a, idx as u32, &[]);
        Ok(Val { v, own: true })
    }

    // --------------------------------------------------------------- members

    fn member(&mut self, e: &Expr, left: &Expr, name: &str) -> Result<Val, Error> {
        if let Resolution::Constructor { ty, case } = self.hir.resolution(e) {
            return self.construct_unit(e, &ty, case);
        }
        if let Resolution::Native(unit) = self.hir.resolution(e)
            && matches!(unit.as_str(), "seconds" | "milliseconds" | "minutes")
        {
            let n = self.expr(left)?;
            if self.dead {
                return Ok(n);
            }
            return self.duration_unit(unit.as_str(), n);
        }
        if let Resolution::Method(m) = self.hir.resolution(e) {
            return self.method_value(e, left, &m);
        }
        let lt = self.ety(left);
        if lt.id == "Int" && matches!(name, "seconds" | "milliseconds" | "minutes") {
            // `3.minutes`: a duration of that many units.
            let n = self.expr(left)?;
            if self.dead {
                return Ok(n);
            }
            let arg = self.borrow(n);
            let sym = format!("msstd_time_int_{name}");
            return Ok(Val {
                v: self.call_runtime(&sym, &[arg], MTy::INT)?,
                own: false,
            });
        }
        if lt.kind != Kind::Record {
            return Err(Error::new(format!("unsupported member access .{name}")));
        }
        let obj = self.expr(left)?;
        if self.dead {
            return Ok(obj);
        }
        let oty = self.ty_of(obj.v);
        let TyKind::Rec(rid) = self.b.m.types.kind(oty).clone() else {
            return Err(Error::new("member access on a non-record"));
        };
        let idx = self.b.m.records[rid.index()]
            .fields
            .iter()
            .position(|f| f.0 == name)
            .ok_or_else(|| Error::new(format!("no field {name}")))? as u32;
        let mut f = self.b.rec_get(rid, idx, obj.v);
        // A `ref` field holds a view; reading it borrows what it views.
        if matches!(self.b.m.types.kind(self.ty_of(f)), TyKind::Ref(_)) {
            f = self.b.ref_get(f);
        }
        if let Some((uid, names)) = self.resource_move_of(e) {
            let o = self.moved_field(uid, &names, f)?;
            return Ok(Val { v: o, own: true });
        }
        if obj.own && self.is_resource(self.ty_of(obj.v)) {
            // A resource is read in place and closed whole with the statement's temporaries:
            // copying the part out would make a second owner of it.
            self.temps.push(obj.v);
            return Ok(Val { v: f, own: false });
        }
        if obj.own {
            // Take a copy out of the temporary, then release the temporary.
            let o = self.owned(Val { v: f, own: false });
            self.close_temp(obj.v);
            self.drop_value(obj.v);
            return Ok(Val {
                v: o,
                own: self.holds(self.ty_of(o)),
            });
        }
        Ok(Val { v: f, own: false })
    }

    /// The binding and field path when the member `e` moves a resource field out of a binding.
    fn resource_move_of(&self, e: &Expr) -> Option<(usize, Vec<ct::Name>)> {
        let mut at = e;
        while let ExprKind::Member { left, .. } = &at.kind {
            at = left;
        }
        let Resolution::Local(b) = self.hir.resolution(at) else {
            return None;
        };
        let names = self.cx.resource_moves.get(&b.uid)?.get(&e.id)?;
        Some((b.uid, names.clone()))
    }

    fn index(&mut self, e: &Expr, left: &Expr, index: &Expr) -> Result<Val, Error> {
        if self.ety(left).is_std("Map") {
            return self.map_index(e, left, index);
        }
        let l = self.expr(left)?;
        if self.dead {
            return Ok(l);
        }
        // An owned list stays a temporary while the index runs, so a `try` inside it releases it.
        if l.own {
            self.temps.push(l.v);
        }
        let i = self.expr(index);
        if l.own
            && let Some(at) = self.temps.iter().rposition(|t| *t == l.v)
        {
            self.temps.remove(at);
        }
        let i = i?;
        if self.dead {
            return Ok(l);
        }
        let lt = self.ty_of(l.v);
        match self.b.m.types.kind(lt).clone() {
            TyKind::List(_) => {
                let got = self.b.list_get(l.v, i.v);
                if l.own && self.is_resource(lt) {
                    // A list of resources is read in place and closed whole with the statement's
                    // temporaries: copying the element out would make a second owner of it.
                    self.temps.push(l.v);
                    return Ok(Val { v: got, own: false });
                }
                if l.own {
                    let o = self.owned(Val { v: got, own: false });
                    self.drop_value(l.v);
                    return Ok(Val {
                        v: o,
                        own: self.holds(self.ty_of(o)),
                    });
                }
                Ok(Val { v: got, own: false })
            }
            TyKind::Bytes => {
                let no_default = self.b.bconst(false);
                let zero = self.b.iconst(0);
                self.at(e.pos);
                let got =
                    self.call_runtime("msrt_bytes_get", &[l.v, i.v, no_default, zero], MTy::UINT8)?;
                if l.own {
                    self.drop_value(l.v);
                }
                Ok(Val { v: got, own: false })
            }
            _ => Err(Error::new("indexing this type is not supported yet")),
        }
    }

    // ----------------------------------------------------------------- unary

    fn unary(&mut self, e: &Expr, op: UnaryOp, operand: &Expr) -> Result<Val, Error> {
        match op {
            UnaryOp::Plus => self.expr(operand),
            UnaryOp::Not => {
                let x = self.expr(operand)?;
                if self.dead {
                    return Ok(x);
                }
                let v = self.b.unop(Op::Not, x.v);
                Ok(Val { v, own: false })
            }
            UnaryOp::Neg => {
                if let ExprKind::Number(text) = &operand.kind {
                    return self.number(operand, text.as_str(), true);
                }
                let x = self.expr(operand)?;
                if self.dead {
                    return Ok(x);
                }
                let t = self.ty_of(x.v);
                if self.is_bigint(t) {
                    let a = self.borrow(x);
                    let v = self.call_runtime("msstd_bigint_negate", &[a], t)?;
                    return Ok(Val { v, own: true });
                }
                if self.is_decimal(t) {
                    let a = self.borrow(x);
                    let v = self.call_runtime("msstd_decimal_negate", &[a], t)?;
                    return Ok(Val { v, own: false });
                }
                let v = if self.b.m.types.is_float(t) {
                    self.b.unop(Op::FNeg, x.v)
                } else {
                    let v = self.b.unop(Op::INegChk, x.v);
                    self.narrow(v, &self.hir.ty(operand))
                };
                Ok(Val { v, own: false })
            }
            UnaryOp::Try => self.try_expr(e, operand),
        }
    }

    // ---------------------------------------------------------------- binary

    fn binary(&mut self, e: &Expr, op: BinaryOp, left: &Expr, right: &Expr) -> Result<Val, Error> {
        match op {
            BinaryOp::And | BinaryOp::Or => return self.short_circuit(op, left, right),
            _ => {}
        }
        let at = self.b.current();
        let l = self.expr(left)?;
        let l = if crate::mutation::has_try(right) {
            self.hold_temp(l)
        } else {
            l
        };
        let r = self.expr(right)?;
        if self.dead {
            return Ok(l);
        }
        let l = self.refresh(left, l, at)?;
        let t = self.ty_of(l.v);
        self.at(e.pos);
        let out = match op {
            BinaryOp::Add | BinaryOp::Sub | BinaryOp::Mul | BinaryOp::Div | BinaryOp::Rem => {
                let v = self.arithmetic(op, t, l, r)?;
                self.narrow(v, &self.hir.ty(left))
            }
            BinaryOp::Eq | BinaryOp::Ne => {
                let saved = self.scope_override;
                self.scope_override = self.evidence_of(&[self.hir.ty(left)]);
                let eq = self.equal(t, l, r);
                self.scope_override = saved;
                let eq = eq?;
                if op == BinaryOp::Ne {
                    self.b.unop(Op::Not, eq)
                } else {
                    eq
                }
            }
            BinaryOp::Lt | BinaryOp::Gt | BinaryOp::Le | BinaryOp::Ge => {
                let cc = match op {
                    BinaryOp::Lt => Cc::Lt,
                    BinaryOp::Gt => Cc::Gt,
                    BinaryOp::Le => Cc::Le,
                    _ => Cc::Ge,
                };
                self.compare(cc, t, l, r)?
            }
            BinaryOp::And | BinaryOp::Or => unreachable!(),
        };
        Ok(self.val(out, true))
    }

    /// Brings a 64-bit result back to its sized type: integers fault when out of range,
    /// binary32 floats round. Default-width and 64-bit types pass through.
    fn narrow(&mut self, v: Value, t: &ct::Ty) -> Value {
        if ct::int_bits(t).is_some_and(|bits| bits < 64) {
            return self.b.narrow_chk(v);
        }
        if ct::float_bits(t) == Some(32) {
            return self.b.f32_round(v);
        }
        v
    }

    fn arithmetic(&mut self, op: BinaryOp, t: MTy, l: Val, r: Val) -> Result<Value, Error> {
        if t == MTy::UINT64 {
            let sym = match op {
                BinaryOp::Add => return Ok(self.b.binop(Op::UAddChk, l.v, r.v)),
                BinaryOp::Sub => return Ok(self.b.binop(Op::USubChk, l.v, r.v)),
                BinaryOp::Mul => return Ok(self.b.binop(Op::UMulChk, l.v, r.v)),
                BinaryOp::Div => "msrt_uint_div",
                _ => "msrt_uint_rem",
            };
            return self.call_runtime(sym, &[l.v, r.v], t);
        }
        if self.b.m.types.is_int(t) {
            let o = match op {
                BinaryOp::Add => Op::IAddChk,
                BinaryOp::Sub => Op::ISubChk,
                BinaryOp::Mul => Op::IMulChk,
                BinaryOp::Div => Op::SDivChk,
                _ => Op::SRemChk,
            };
            return Ok(self.b.binop(o, l.v, r.v));
        }
        if self.b.m.types.is_float(t) {
            let o = match op {
                BinaryOp::Add => Op::FAdd,
                BinaryOp::Sub => Op::FSub,
                BinaryOp::Mul => Op::FMul,
                BinaryOp::Div => Op::FDiv,
                _ => return Err(Error::new("% on Float")),
            };
            return Ok(self.b.binop(o, l.v, r.v));
        }
        if t == MTy::STR && op == BinaryOp::Add {
            let a = self.borrow(l);
            let b = self.borrow(r);
            return self.call_runtime("msrt_string_concat", &[a, b], MTy::STR);
        }
        if matches!(self.b.m.types.kind(t), TyKind::List(_)) && op == BinaryOp::Add {
            return Err(Error::new("list concatenation is not supported yet"));
        }
        if self.is_decimal(t) {
            let sym = match op {
                BinaryOp::Add => "msstd_decimal_add",
                BinaryOp::Sub => "msstd_decimal_subtract",
                BinaryOp::Mul => "msstd_decimal_multiply",
                BinaryOp::Div => "msstd_decimal_divide",
                _ => return Err(Error::new("% on Decimal")),
            };
            let (a, b) = (self.borrow(l), self.borrow(r));
            return self.call_runtime(sym, &[a, b], t);
        }
        if self.is_bigint(t) {
            let sym = match op {
                BinaryOp::Add => "msstd_bigint_add",
                BinaryOp::Sub => "msstd_bigint_subtract",
                BinaryOp::Mul => "msstd_bigint_multiply",
                BinaryOp::Div => "msstd_bigint_quotient",
                _ => "msstd_bigint_modulo",
            };
            let (a, b) = (self.borrow(l), self.borrow(r));
            return self.call_runtime(sym, &[a, b], t);
        }
        if self.is_instant(t) && matches!(op, BinaryOp::Add | BinaryOp::Sub) {
            let (a, b) = (self.borrow(l), self.borrow(r));
            // `instant - instant` is the elapsed duration; a duration moves the instant.
            let (sym, out) = match (op, self.ty_of(b) == t) {
                (BinaryOp::Sub, true) => ("msstd_time_instant_difference", MTy::INT),
                (BinaryOp::Sub, false) => ("msstd_time_instant_unshift", t),
                _ => ("msstd_time_instant_shift", t),
            };
            return self.call_runtime(sym, &[a, b], out);
        }
        Err(Error::new(format!(
            "arithmetic on {} is not supported yet",
            crate::text::ty_name(self.b.m, t)
        )))
    }

    fn compare(&mut self, cc: Cc, t: MTy, l: Val, r: Val) -> Result<Value, Error> {
        if self.b.m.types.is_int(t) {
            return Ok(self.b.icmp(cc, l.v, r.v));
        }
        if self.b.m.types.is_float(t) {
            return Ok(self.b.fcmp(cc, l.v, r.v));
        }
        if t == MTy::STR {
            let a = self.borrow(l);
            let b = self.borrow(r);
            let c = self.call_runtime("msrt_string_compare", &[a, b], MTy::INT)?;
            let zero = self.b.iconst(0);
            return Ok(self.b.icmp(cc, c, zero));
        }
        let sym = if self.is_bigint(t) {
            Some("msstd_bigint_compare")
        } else {
            self.ordering_symbol(t)
        };
        if let Some(sym) = sym {
            let a = self.borrow(l);
            let b = self.borrow(r);
            let c = self.call_runtime(sym, &[a, b], MTy::INT)?;
            let zero = self.b.iconst(0);
            return Ok(self.b.icmp(cc, c, zero));
        }
        Err(Error::new("ordering this type is not supported yet"))
    }

    /// The runtime function ordering two values of a native record type (`-1`, `0` or `1`).
    pub(crate) fn ordering_symbol(&self, t: MTy) -> Option<&'static str> {
        let TyKind::Rec(rid) = self.b.m.types.kind(t) else {
            return None;
        };
        match self.b.m.records[rid.index()].name.as_str() {
            "Timestamp" => Some("msstd_time_timestamp_compare"),
            "Instant" => Some("msstd_time_instant_compare"),
            "Decimal" => Some("msstd_decimal_compare"),
            _ => None,
        }
    }

    /// Whether `t` is the `Instant` record.
    fn is_instant(&self, t: MTy) -> bool {
        matches!(self.b.m.types.kind(t), TyKind::Rec(rid) if self.b.m.records[rid.index()].name == "Instant")
    }

    /// Whether `t` is the `BigInt` runtime object.
    pub(crate) fn is_bigint(&self, t: MTy) -> bool {
        matches!(self.b.m.types.kind(t), TyKind::Obj(n, _) if n == "BigInt")
    }

    /// Whether `t` is the `Decimal` record.
    pub(crate) fn is_decimal(&self, t: MTy) -> bool {
        matches!(self.b.m.types.kind(t), TyKind::Rec(rid) if self.b.m.records[rid.index()].name == "Decimal")
    }

    /// Structural equality of two operands of the same type.
    pub fn equal(&mut self, t: MTy, l: Val, r: Val) -> Result<Value, Error> {
        let (a, b) = (self.borrow(l), self.borrow(r));
        let scope = self.glue_scope(t);
        crate::eq::element_eq(self.cx, &mut self.b, scope, t, a, b)
    }

    fn short_circuit(&mut self, op: BinaryOp, left: &Expr, right: &Expr) -> Result<Val, Error> {
        let l = self.expr(left)?;
        if self.dead {
            return Ok(l);
        }
        let rhs = self.b.new_block();
        let join = self.b.new_block();
        let jp = self
            .b
            .add_block_param(join, MTy::BOOL, ms_mir::ir::Mode::Borrow);
        let short = self.b.bconst(op == BinaryOp::Or);
        if op == BinaryOp::And {
            self.b.br_if(l.v, rhs, &[], join, &[short]);
        } else {
            self.b.br_if(l.v, join, &[short], rhs, &[]);
        }
        self.b.seal_block(rhs);
        self.enter(rhs);
        let mark = self.temps.len();
        let r = self.expr(right)?;
        let rv = r.v;
        self.flush_temps(mark);
        let live = !self.dead;
        if live {
            self.b.br(join, &[rv]);
        }
        self.b.seal_block(join);
        self.b.switch_to(join);
        self.dead = false;
        Ok(Val { v: jp, own: false })
    }

    /// Calls a runtime function by symbol, declaring it from the operand types
    /// (all operands borrowed, result owned).
    pub fn call_runtime(&mut self, sym: &str, args: &[Value], ret: MTy) -> Result<Value, Error> {
        let params = args
            .iter()
            .map(|a| ms_mir::ir::Param {
                ty: self.ty_of(*a),
                mode: ms_mir::ir::Mode::Borrow,
            })
            .collect();
        let ext = self.b.m.add_extern(ms_mir::ir::ExternDef {
            name: sym.to_string(),
            params,
            ret,
            noreturn: false,
            pure_: false,
            fresh: crate::rtcall::fresh_result(sym),
        });
        Ok(self.b.call_rt(ext, args))
    }
}

/// Parses an integer literal spelling.
fn parse_int(text: &str) -> Option<i128> {
    ms_syntax::number::canonical(text).parse().ok()
}
