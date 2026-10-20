//! Statement lowering.

use crate::Error;
use crate::func::{FnLower, LoopCtx, Val};
use ms_mir::ir::{Cc, Imm, Op};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::*;

impl<'a> FnLower<'a> {
    /// Lowers statements until the position becomes unreachable.
    pub fn stmts(&mut self, body: &[Stmt]) -> Result<(), Error> {
        for s in body {
            if self.dead {
                break;
            }
            self.stmt(s)?;
        }
        Ok(())
    }

    /// A statement list in its own lexical scope.
    pub fn block(&mut self, body: &[Stmt]) -> Result<(), Error> {
        self.push_scope();
        let r = self.stmts(body);
        self.pop_scope();
        r
    }

    pub fn stmt(&mut self, s: &Stmt) -> Result<(), Error> {
        self.at(s.pos);
        let mark = self.temps.len();
        match &s.kind {
            StmtKind::Bind { pattern, value, .. } => self.bind(pattern, value)?,
            StmtKind::Assign { target, value, .. } => self.assign(target, value)?,
            StmtKind::Call(e) => {
                self.discard = Some(e as *const Expr as usize);
                let x = self.expr(e)?;
                if x.own {
                    self.drop_value(x.v);
                }
            }
            StmtKind::Return(e) => {
                let x = match e {
                    Some(e) => self.expr(e)?,
                    None => Val {
                        v: self.b.unit(),
                        own: false,
                    },
                };
                // A bare `return` (or `return unit`) in a test ends it successfully.
                let in_test = matches!(self.b.m.types.kind(self.result_ty()), TyKind::Alt(_));
                let x = if in_test && self.ty_of(x.v) == MTy::UNIT {
                    let u = self.b.unit();
                    let ok = self.testing_ok(self.result_ty(), u)?;
                    Val { v: ok, own: true }
                } else {
                    x
                };
                self.emit_return(Some(x));
                // The return released this statement's temporaries.
                self.temps.truncate(mark);
                return Ok(());
            }
            StmtKind::Break => {
                let ctx = self
                    .loops
                    .last_mut()
                    .ok_or_else(|| Error::new("break outside loop"))?;
                ctx.brk_used = true;
                let (brk, depth) = (ctx.brk, ctx.depth);
                self.flush_temps(mark);
                self.unwind_to(depth);
                self.b.br(brk, &[]);
                self.terminated();
                return Ok(());
            }
            StmtKind::Continue => {
                let ctx = self
                    .loops
                    .last_mut()
                    .ok_or_else(|| Error::new("continue outside loop"))?;
                ctx.cont_used = true;
                let (cont, depth) = (ctx.cont, ctx.depth);
                self.flush_temps(mark);
                self.unwind_to(depth);
                self.b.br(cont, &[]);
                self.terminated();
                return Ok(());
            }
            StmtKind::If {
                binding,
                cond,
                body,
                else_body,
            } => {
                self.if_stmt(binding.as_ref(), cond, body, else_body)?;
                self.flush_temps(mark);
                return Ok(());
            }
            StmtKind::While { cond, body } => self.while_stmt(cond, body)?,
            StmtKind::For { iter, body, .. } => self.for_stmt(s, iter, body)?,
            StmtKind::With { value, body, .. } => {
                self.with_stmt(s, value, body)?;
            }
        }
        self.flush_temps(mark);
        Ok(())
    }

    fn bind(&mut self, pattern: &Pattern, value: &Expr) -> Result<(), Error> {
        let x = self.expr(value)?;
        if self.dead {
            return Ok(());
        }
        self.bind_pattern(pattern, x)
    }

    /// Binds the names of `pattern` to the parts of `x`: lists by position (the length is
    /// checked), records by field.
    fn bind_pattern(&mut self, pattern: &Pattern, x: Val) -> Result<(), Error> {
        match &pattern.kind {
            PatternKind::Name(_) => {
                // `_` introduces no binding.
                if let Some(b) = self.hir.pattern_binding(pattern) {
                    self.bind_local(&b, x);
                }
                Ok(())
            }
            PatternKind::List(items) => {
                let list = self.borrow(x);
                let len = self.b.list_len(list);
                let want = self.b.iconst(items.len() as i64);
                let same = self.b.icmp(Cc::Eq, len, want);
                let (good, bad) = (self.b.new_block(), self.b.new_block());
                self.b.br_if(same, good, &[], bad, &[]);
                self.b.seal_block(good);
                self.b.seal_block(bad);
                self.b.switch_to(bad);
                let ext = crate::text::runtime_fn(
                    self.b.m,
                    "msrt_fault_destructure",
                    &[MTy::INT, MTy::INT],
                    MTy::UNIT,
                );
                self.b.m.externs[ext.index()].noreturn = true;
                self.b.call_rt(ext, &[want, len]);
                self.b.unreachable();
                self.b.switch_to(good);
                for (i, p) in items.iter().enumerate() {
                    let at = self.b.iconst(i as i64);
                    let e = self.b.list_get(list, at);
                    self.bind_pattern(p, Val { v: e, own: false })?;
                }
                Ok(())
            }
            PatternKind::Record(fields) => {
                let rec = self.borrow(x);
                let TyKind::Rec(rid) = self.b.m.types.kind(self.ty_of(rec)).clone() else {
                    return Err(Error::new("a record pattern needs a record"));
                };
                for f in fields {
                    let idx = self.b.m.records[rid.index()]
                        .fields
                        .iter()
                        .position(|d| d.0 == f.name.as_str())
                        .ok_or_else(|| Error::new(format!("no field {}", f.name)))?;
                    let fv = self.b.rec_get(rid, idx as u32, rec);
                    self.bind_pattern(&f.pattern, Val { v: fv, own: false })?;
                }
                Ok(())
            }
        }
    }

    fn assign(&mut self, target: &AssignTarget, value: &Expr) -> Result<(), Error> {
        let x = self.expr(value)?;
        if self.dead {
            return Ok(());
        }
        match target {
            AssignTarget::Name(_) => {
                let b = self
                    .hir
                    .assigned(value)
                    .ok_or_else(|| Error::new("assignment without target binding"))?;
                let l = self.local(&b)?;
                let new = self.owned(x);
                let old = self.b.use_var(l.var);
                self.b.def_var(l.var, new);
                if self.cx_needs_drop_ty(l.ty) {
                    self.drop_value(old);
                }
                Ok(())
            }
            AssignTarget::Member(t) => self.assign_member(t, value, x),
        }
    }

    fn cx_needs_drop_ty(&self, t: MTy) -> bool {
        self.b.m.needs_drop(t)
    }

    /// `a.b.c = v`: rebuilds the record chain with `rec.set`.
    fn assign_member(&mut self, target: &Expr, value: &Expr, x: Val) -> Result<(), Error> {
        let mut path: Vec<&Expr> = Vec::new();
        let mut cur = target;
        while let ExprKind::Member { left, .. } = &cur.kind {
            path.push(cur);
            cur = left;
        }
        path.reverse();
        if let ExprKind::Index { left, index } = &cur.kind {
            // A field of a list element (`xs[i].n = 1`): the list receives the updated element.
            let i = self.expr(index)?;
            if self.dead {
                return Ok(());
            }
            let at = self.borrow(i);
            let mut new = Some(self.owned(x));
            return self.place_update(left, &mut |s, list| {
                let elem = s.list_elem_at(list, at)?;
                let new = new.take().expect("one update");
                let updated = s.set_path(elem, true, &path, new)?;
                Ok(s.b.list_set(list, at, updated))
            });
        }
        let ExprKind::Name(_) = &cur.kind else {
            // A field of a computed value (`f().n = 1`): values do not alias, so the update
            // lands on a copy that is dropped.
            let base = self.expr(cur)?;
            let root = self.owned(base);
            let new = self.owned(x);
            let updated = self.set_path(root, true, &path, new)?;
            self.drop_value(updated);
            return Ok(());
        };
        let ms_check::hir::Resolution::Local(binding) = self.hir.resolution(cur) else {
            return Err(Error::new("assignment target is not a local variable"));
        };
        let _ = value;
        let l = self.local(&binding)?;
        let root = self.b.use_var(l.var);
        let new = self.owned(x);
        let updated = self.set_path(root, true, &path, new)?;
        self.b.def_var(l.var, updated);
        Ok(())
    }

    /// Replaces the place `target` (a variable or a field chain from one) by `f(current)`.
    pub fn place_update(
        &mut self,
        target: &Expr,
        f: &mut dyn FnMut(&mut Self, ms_mir::ir::Value) -> Result<ms_mir::ir::Value, Error>,
    ) -> Result<(), Error> {
        let mut path: Vec<&Expr> = Vec::new();
        let mut cur = target;
        while let ExprKind::Member { left, .. } = &cur.kind {
            path.push(cur);
            cur = left;
        }
        path.reverse();
        if let ExprKind::Index { left, index } = &cur.kind {
            // A list element changes in place: the list receives the updated element.
            let i = self.expr(index)?;
            if self.dead {
                return Ok(());
            }
            let at = self.borrow(i);
            return self.place_update(left, &mut |s, list| {
                let elem = s.list_elem_at(list, at)?;
                let updated = s.update_path(elem, &path, f)?;
                Ok(s.b.list_set(list, at, updated))
            });
        }
        if !matches!(cur.kind, ExprKind::Name(_)) {
            // Mutating a computed value (`xs.get(0).append(1)`) changes a copy that is dropped.
            let base = self.expr(cur)?;
            let root = self.owned(base);
            let updated = self.update_path(root, &path, f)?;
            self.drop_value(updated);
            return Ok(());
        }
        let ms_check::hir::Resolution::Local(binding) = self.hir.resolution(cur) else {
            return Err(Error::new("mutation target is not a local variable"));
        };
        let l = self.local(&binding)?;
        let root = self.b.use_var(l.var);
        let updated = self.update_path(root, &path, f)?;
        self.b.def_var(l.var, updated);
        Ok(())
    }

    /// An owned copy of element `at` of the list `list`.
    fn list_elem_at(
        &mut self,
        list: ms_mir::ir::Value,
        at: ms_mir::ir::Value,
    ) -> Result<ms_mir::ir::Value, Error> {
        if !matches!(self.b.m.types.kind(self.ty_of(list)), TyKind::List(_)) {
            return Err(Error::new("element update on a non-list"));
        }
        let elem = self.b.list_get(list, at);
        Ok(self.owned(Val {
            v: elem,
            own: false,
        }))
    }

    fn update_path(
        &mut self,
        obj: ms_mir::ir::Value,
        path: &[&Expr],
        f: &mut dyn FnMut(&mut Self, ms_mir::ir::Value) -> Result<ms_mir::ir::Value, Error>,
    ) -> Result<ms_mir::ir::Value, Error> {
        let Some((first, rest)) = path.split_first() else {
            return f(self, obj);
        };
        let ExprKind::Member { name, .. } = &first.kind else {
            unreachable!()
        };
        let oty = self.ty_of(obj);
        let TyKind::Rec(rid) = self.b.m.types.kind(oty).clone() else {
            return Err(Error::new("field mutation on a non-record"));
        };
        let idx = self.b.m.records[rid.index()]
            .fields
            .iter()
            .position(|f| f.0 == name.as_str())
            .ok_or_else(|| Error::new(format!("no field {name}")))? as u32;
        let cur = self.b.rec_get(rid, idx, obj);
        let cur_own = self.owned(Val { v: cur, own: false });
        let inner = self.update_path(cur_own, rest, f)?;
        Ok(self.b.rec_set(rid, idx, obj, inner))
    }

    /// Returns `obj` with the field chain replaced by `new`. `obj_own` says whether `obj` is
    /// owned by the caller (consumed here) or borrowed (copied first).
    fn set_path(
        &mut self,
        obj: ms_mir::ir::Value,
        obj_own: bool,
        path: &[&Expr],
        new: ms_mir::ir::Value,
    ) -> Result<ms_mir::ir::Value, Error> {
        let (first, rest) = path.split_first().expect("non-empty path");
        let ExprKind::Member { name, .. } = &first.kind else {
            unreachable!()
        };
        let oty = self.ty_of(obj);
        let TyKind::Rec(rid) = self.b.m.types.kind(oty).clone() else {
            return Err(Error::new("field assignment on a non-record"));
        };
        let idx = self.b.m.records[rid.index()]
            .fields
            .iter()
            .position(|f| f.0 == name.as_str())
            .ok_or_else(|| Error::new(format!("no field {name}")))? as u32;
        let inner = if rest.is_empty() {
            new
        } else {
            let cur = self.b.rec_get(rid, idx, obj);
            let cur_own = if self.needs_drop(self.ty_of(cur)) {
                self.owned(Val { v: cur, own: false })
            } else {
                cur
            };
            self.set_path(cur_own, true, rest, new)?
        };
        let base = if obj_own {
            obj
        } else {
            self.owned(Val { v: obj, own: false })
        };
        Ok(self.b.rec_set(rid, idx, base, inner))
    }

    fn if_stmt(
        &mut self,
        binding: Option<&Pattern>,
        cond: &Expr,
        body: &[Stmt],
        else_body: &[Stmt],
    ) -> Result<(), Error> {
        let mark = self.temps.len();
        let (then_b, else_b, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        let mut scrutinee: Option<Val> = None;
        let c = if binding.is_some() {
            let o = self.expr(cond)?;
            if self.dead {
                return Ok(());
            }
            scrutinee = Some(o);
            self.success_test(o.v)?
        } else {
            let x = self.expr(cond)?;
            if self.dead {
                return Ok(());
            }
            self.truthy(x)
        };
        if binding.is_none() {
            self.flush_temps(mark);
        }
        self.b.br_if(c, then_b, &[], else_b, &[]);
        self.b.seal_block(then_b);
        self.b.seal_block(else_b);

        self.enter(then_b);
        self.push_scope();
        if let (Some(p), Some(o)) = (binding, scrutinee) {
            let payload = self.success_payload(o.v)?;
            let bnd = self
                .hir
                .pattern_binding(p)
                .ok_or_else(|| Error::new("if let without binding"))?;
            self.bind_local(
                &bnd,
                Val {
                    v: payload,
                    own: false,
                },
            );
            if o.own {
                self.drop_value(o.v);
            }
        }
        self.stmts(body)?;
        self.pop_scope();
        let then_live = !self.dead;
        if then_live {
            self.b.br(join, &[]);
        }

        self.enter(else_b);
        if let Some(o) = scrutinee.filter(|o| o.own) {
            self.drop_value(o.v);
        }
        self.block(else_body)?;
        let else_live = !self.dead;
        if else_live {
            self.b.br(join, &[]);
        }
        self.b.seal_block(join);
        self.b.switch_to(join);
        self.dead = !(then_live || else_live);
        Ok(())
    }

    /// Whether an Optional is `some` or a Result is `ok`.
    fn success_test(&mut self, v: ms_mir::ir::Value) -> Result<ms_mir::ir::Value, Error> {
        match self.b.m.types.kind(self.ty_of(v)).clone() {
            TyKind::Opt(_) => Ok(self.b.opt_is_some(v)),
            TyKind::Alt(a) => {
                let ok = self.ok_case(a)?;
                let tag = self.b.alt_tag(v);
                let k = self.b.iconst(ok as i64);
                Ok(self.b.icmp(Cc::Eq, tag, k))
            }
            _ => Err(Error::new("if let needs an Optional or a Result")),
        }
    }

    /// The `some` / `ok` payload (a borrow).
    fn success_payload(&mut self, v: ms_mir::ir::Value) -> Result<ms_mir::ir::Value, Error> {
        match self.b.m.types.kind(self.ty_of(v)).clone() {
            TyKind::Alt(a) => {
                let ok = self.ok_case(a)?;
                Ok(self.b.alt_get(a, ok as u32, 0, v))
            }
            _ => Ok(self.b.opt_get(v)),
        }
    }

    fn ok_case(&self, a: ms_mir::types::AltId) -> Result<usize, Error> {
        self.b.m.alts[a.index()]
            .cases
            .iter()
            .position(|c| c.name == "ok")
            .ok_or_else(|| Error::new("if let on an alternative that is not a Result"))
    }

    /// A Bool operand as an SSA value (dropping nothing: Bool is a scalar).
    pub fn truthy(&mut self, x: Val) -> ms_mir::ir::Value {
        x.v
    }

    fn while_stmt(&mut self, cond: &Expr, body: &[Stmt]) -> Result<(), Error> {
        let (header, body_b, exit) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(header, &[]);
        self.enter(header);
        // `while true` leaves only through `break`, `return` or a fault.
        let forever = matches!(cond.kind, ExprKind::Bool(true));
        if forever {
            self.b.br(body_b, &[]);
        } else {
            let mark = self.temps.len();
            let x = self.expr(cond)?;
            let c = self.truthy(x);
            self.flush_temps(mark);
            self.b.br_if(c, body_b, &[], exit, &[]);
        }
        self.b.seal_block(body_b);
        self.enter(body_b);
        let depth = self.scopes.len();
        self.loops.push(LoopCtx {
            brk: exit,
            cont: header,
            depth,
            cont_used: false,
            brk_used: false,
        });
        self.block(body)?;
        let ctx = self.loops.pop().expect("loop");
        if !self.dead {
            self.b.br(header, &[]);
        }
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.enter(exit);
        if forever && !ctx.brk_used {
            self.b.unreachable();
            self.terminated();
        }
        Ok(())
    }

    /// `(start, end)` of `range(start, end)`, which a `for` runs as a counting loop.
    fn range_bounds(
        &mut self,
        iter: &Expr,
    ) -> Result<Option<(ms_mir::ir::Value, ms_mir::ir::Value)>, Error> {
        let Some(view) = self.hir.call(iter) else {
            return Ok(None);
        };
        let ms_check::hir::Resolution::Function(sym) = &view.target else {
            return Ok(None);
        };
        if sym.native.as_str() != "collections/range" || view.arguments.len() != 2 {
            return Ok(None);
        }
        let a = self.expr(view.arguments[0].expr)?;
        let b = self.expr(view.arguments[1].expr)?;
        Ok(Some((a.v, b.v)))
    }

    fn for_stmt(&mut self, s: &Stmt, iter: &Expr, body: &[Stmt]) -> Result<(), Error> {
        let loop_var = self
            .hir
            .stmt(s)
            .loop_binding
            .ok_or_else(|| Error::new("for without loop binding"))?;
        self.push_scope();
        let mut list_var = None;
        let (start, len) = match self.range_bounds(iter)? {
            Some(bounds) => bounds,
            None => {
                let it = self.expr(iter)?;
                if self.dead {
                    self.scopes.pop();
                    return Ok(());
                }
                let mut it = it;
                let mut ity = self.ty_of(it.v);
                if crate::mapset::is_map_or_set(self.b.m, ity) {
                    // A map yields its entries and a set its values, as a list snapshot.
                    let elem = self.mty(&loop_var.ty)?;
                    let list = self.b.m.types.list(elem);
                    it = match self.b.m.types.kind(ity).clone() {
                        TyKind::Obj(n, _) if n == "Map" => self.map_entries(iter, it, list)?,
                        _ => {
                            let sym = crate::rtcall::method_symbol(self.b.m, ity, "values")
                                .ok_or_else(|| Error::new("no values for a set"))?;
                            self.rt_method(&sym, it, &[], &[], list)?
                        }
                    };
                    ity = list;
                }
                let TyKind::List(_) = self.b.m.types.kind(ity).clone() else {
                    return Err(Error::new("for over this type is not supported yet"));
                };
                let var = self.bind_hidden(it);
                list_var = Some(var);
                let list = self.b.use_var(var);
                (self.b.iconst(0), self.b.list_len(list))
            }
        };
        if self.dead {
            self.scopes.pop();
            return Ok(());
        }
        let one = self.b.iconst(1);
        let idx = self.b.declare_var(MTy::INT, ms_mir::ir::Mode::Borrow);
        self.b.def_var(idx, start);
        let (header, body_b, step, exit) = (
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
        );
        self.b.br(header, &[]);
        self.enter(header);
        let i = self.b.use_var(idx);
        let c = self.b.icmp(Cc::Lt, i, len);
        self.b.br_if(c, body_b, &[], exit, &[]);
        self.b.seal_block(body_b);
        self.enter(body_b);
        let depth = self.scopes.len();
        self.loops.push(LoopCtx {
            brk: exit,
            cont: step,
            depth,
            cont_used: false,
            brk_used: false,
        });
        self.push_scope();
        let i = self.b.use_var(idx);
        let e = match list_var {
            Some(var) => {
                let list = self.b.use_var(var);
                self.b.list_get(list, i)
            }
            None => i,
        };
        self.bind_local(&loop_var, Val { v: e, own: false });
        self.stmts(body)?;
        self.pop_scope();
        let ctx = self.loops.pop().expect("loop");
        let body_live = !self.dead;
        if body_live {
            self.b.br(step, &[]);
        }
        let step_reached = ctx.cont_used || body_live;
        self.b.seal_block(step);
        if step_reached {
            self.enter(step);
            let i = self.b.use_var(idx);
            let n = self
                .b
                .emit(Op::IAdd, &[i, one], Imm::None, Some(MTy::INT))
                .expect("add");
            self.b.def_var(idx, n);
            self.b.br(header, &[]);
        }
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.enter(exit);
        self.pop_scope();
        Ok(())
    }
}
