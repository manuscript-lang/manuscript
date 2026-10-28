//! Statement lowering.

use crate::Error;
use crate::func::{FnLower, LoopCtx, Val};
use ms_mir::ir::{Cc, Imm, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::*;

impl<'a> FnLower<'a> {
    /// Lowers statements until the position becomes unreachable.
    pub fn stmts(&mut self, body: &[Stmt]) -> Result<(), Error> {
        let mut i = 0;
        while i < body.len() {
            if self.dead {
                break;
            }
            if let Some((gap, split, loop_body)) = self.split_then_loop(&body[i..]) {
                // `let parts = text.split(..)` read only by a later `for`; what lies between
                // them cannot affect the split.
                for s in &body[i + 1..i + 1 + gap] {
                    self.stmt(s)?;
                }
                let loop_stmt = &body[i + 1 + gap];
                self.stmt_with_pos(loop_stmt, |this| this.for_stmt(loop_stmt, split, loop_body))?;
                i += gap + 2;
                continue;
            }
            self.split_view_for = self.split_read_in_place(&body[i], &body[i + 1..]);
            let r = self.stmt(&body[i]);
            self.split_view_for = None;
            r?;
            i += 1;
        }
        Ok(())
    }

    /// `let name = <text>.split(..)` where the rest of the block only reads `name` in place
    /// (indexing, length, a `for`): the split call, whose pieces may then borrow `text`.
    fn split_read_in_place(&self, s: &Stmt, rest: &[Stmt]) -> Option<*const Expr> {
        let StmtKind::Bind {
            mutable: false,
            pattern,
            value,
            ..
        } = &s.kind
        else {
            return None;
        };
        let ExprKind::Call { callee, .. } = &value.kind else {
            return None;
        };
        let ExprKind::Member { name, .. } = &callee.kind else {
            return None;
        };
        if name.as_str() != "split" {
            return None;
        }
        let b = self.hir.pattern_binding(pattern)?;
        crate::mutation::only_read_in_place(&self.hir, rest, b.uid).then_some(value as *const Expr)
    }

    /// `let name = <call>.split(..)`, then plain `let`s of literals, then `for x in name:` with
    /// nothing else naming `name`: the number of statements between, the split call and the
    /// loop body.
    fn split_then_loop<'s>(&self, rest: &'s [Stmt]) -> Option<(usize, &'s Expr, &'s [Stmt])> {
        let (first, after) = rest.split_first()?;
        let StmtKind::Bind {
            mutable: false,
            pattern,
            ty: None,
            value,
            ..
        } = &first.kind
        else {
            return None;
        };
        let ExprKind::Call { callee, .. } = &value.kind else {
            return None;
        };
        let ExprKind::Member { name, .. } = &callee.kind else {
            return None;
        };
        if name.as_str() != "split" {
            return None;
        }
        let binding = self.hir.pattern_binding(pattern)?;
        let gap = after.iter().take_while(|s| is_literal_bind(s)).count();
        let (second, tail) = after[gap..].split_first()?;
        let StmtKind::For { iter, body, .. } = &second.kind else {
            return None;
        };
        let ms_check::hir::Resolution::Local(used) = self.hir.resolution(iter) else {
            return None;
        };
        let unused =
            |stmts: &[Stmt]| !crate::mutation::block_mentions(&self.hir, stmts, binding.uid);
        (used.uid == binding.uid && unused(body) && unused(tail)).then_some((gap, value, body))
    }

    /// Runs `f` for statement `s` with the position bookkeeping of [`Self::stmt`].
    fn stmt_with_pos(
        &mut self,
        s: &Stmt,
        f: impl FnOnce(&mut Self) -> Result<(), Error>,
    ) -> Result<(), Error> {
        let outer = self.stmt_pos.replace(s.pos);
        self.at(s.pos);
        let r = f(self);
        self.stmt_pos = outer;
        if let Some(p) = outer {
            self.at(p);
        }
        r
    }

    /// A statement list in its own lexical scope.
    pub fn block(&mut self, body: &[Stmt]) -> Result<(), Error> {
        self.push_scope();
        let r = self.stmts(body);
        self.pop_scope();
        r
    }

    /// Lowers a statement; every instruction in it reports the statement's first line, as
    /// fault traces do for multi-line statements.
    pub fn stmt(&mut self, s: &Stmt) -> Result<(), Error> {
        let outer = self.stmt_pos.replace(s.pos);
        self.at(s.pos);
        let r = self.stmt_inner(s);
        self.stmt_pos = outer;
        if let Some(p) = outer {
            self.at(p);
        }
        r
    }

    fn stmt_inner(&mut self, s: &Stmt) -> Result<(), Error> {
        let mark = self.temps.len();
        match &s.kind {
            StmtKind::Bind { pattern, value, .. } => self.bind(s, pattern, value)?,
            StmtKind::Assign { target, value, .. } => self.assign(target, value)?,
            StmtKind::Call(e) => {
                self.discard = Some(e as *const Expr as usize);
                let x = self.expr(e)?;
                if x.own {
                    self.drop_value(x.v);
                }
            }
            StmtKind::Return(e) => {
                self.lent_expr = e.as_ref().map(|e| e as *const Expr as usize);
                let x = match e {
                    Some(e) => self.expr(e)?,
                    None => Val {
                        v: self.b.unit(),
                        own: false,
                    },
                };
                // A bare `return` (or `return unit`) in a test ends it successfully.
                let in_test = matches!(self.b.m.types.kind(self.result_ty()), TyKind::Alt(_));
                let x = if in_test && !self.dead && self.ty_of(x.v) == MTy::UNIT {
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
                mutable: _,
                cond,
                body,
                else_body,
            } => {
                self.if_stmt(binding.as_ref(), cond, body, else_body)?;
                self.flush_temps(mark);
                return Ok(());
            }
            StmtKind::While { cond, body } => self.while_stmt(cond, body)?,
            StmtKind::For { iter, body, .. } => {
                if let Some(expansion) = self.hir.stmt(s).expansion {
                    // A `for` over an `Iterator` is the loop the checker expanded it into.
                    self.block(&expansion)?;
                } else {
                    self.for_stmt(s, iter, body)?;
                }
            }
            StmtKind::With { value, body, .. } => {
                self.with_stmt(s, value, body)?;
            }
        }
        self.flush_temps(mark);
        Ok(())
    }

    fn bind(&mut self, s: &Stmt, pattern: &Pattern, value: &Expr) -> Result<(), Error> {
        if let PatternKind::Name(_) = pattern.kind
            && let Some(b) = self.hir.pattern_binding(pattern)
            && self.cx.exclusive(b.uid)
        {
            let alias = self.alias_chain(value)?;
            self.aliases.insert(b.uid, alias);
            return Ok(());
        }
        let mark = self.temps.len();
        if let Some((b, shape)) = self.lendable(Some(pattern), value)? {
            // A lexical borrow of the container (the checker rejects changing it while the
            // binding lives): read the entry in place, as a lent `Optional`.
            let Some((present, entry)) = self.lent_read(shape, value)? else {
                return Ok(());
            };
            let opt = self.lent_optional(present, &entry)?;
            if self.dead {
                return Ok(());
            }
            for t in self.temps.split_off(mark) {
                self.bind_hidden(Val { v: t, own: true });
            }
            self.bind_lent(&b, opt.v);
            return Ok(());
        }
        if self.lent_return
            && let PatternKind::Name(_) = pattern.kind
            && let Some(b) = self.hir.pattern_binding(pattern)
            && self.cx.shared(b.uid)
        {
            // A `let` borrow in a lending function takes the lent form of an accessor, so the
            // function can hand it back.
            self.lent_expr = Some(value as *const Expr as usize);
        }
        let x = self.expr(value)?;
        if self.dead {
            return Ok(());
        }
        if let PatternKind::Name(_) = pattern.kind
            && let Some(b) = self.hir.pattern_binding(pattern)
            && self.cx.shared(b.uid)
            && !x.own
            && self.ownership_checked()
            && !self.slotted.contains(&b.uid)
            && self.needs_drop(self.ty_of(x.v))
        {
            // A lexical borrow (the checker rejects changing its source while it lives): the
            // temporaries it points into live as long as the binding does.
            for t in self.temps.split_off(mark) {
                self.bind_hidden(Val { v: t, own: true });
            }
            self.bind_lent(&b, x.v);
            return Ok(());
        }
        if let PatternKind::Name(_) = pattern.kind
            && let Some(b) = self.hir.pattern_binding(pattern)
            && self.cx.implicit_closes.contains(&b.uid)
            && let Some(cleanup) = self.hir.stmt(s).cleanup
        {
            return self.bind_closing(&b, x, &cleanup);
        }
        self.bind_pattern(pattern, x)
    }

    /// The binding and read shape when `let name = value` or `if let name = value` can lend
    /// the container entry `value` reads: an immutable name the closures do not share.
    fn lendable(
        &mut self,
        pattern: Option<&Pattern>,
        value: &Expr,
    ) -> Result<Option<(ms_check::types::BindingRef, crate::lend::Shape)>, Error> {
        let Some(pattern) = pattern else {
            return Ok(None);
        };
        if !matches!(pattern.kind, PatternKind::Name(_)) {
            return Ok(None);
        }
        let Some(b) = self.hir.pattern_binding(pattern) else {
            return Ok(None);
        };
        if b.mutable || self.slotted.contains(&b.uid) || self.cx.exclusive(b.uid) {
            return Ok(None);
        }
        Ok(self.lent_shape(value)?.map(|shape| (b, shape)))
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
                if let Some(a) = self.aliases.get(&b.uid).cloned() {
                    // A scalar borrow: the whole value is the origin's place.
                    let mut new = Some(self.owned(x));
                    return self.alias_update(&a, &[], &mut |s, old| {
                        s.drop_value(old);
                        Ok(new.take().expect("one update"))
                    });
                }
                let l = self.local(&b)?;
                let new = self.owned(x);
                let old = self.local_take(&l);
                // A registered resource closes the value it replaces; the scope closes the new one.
                if let Some(closer) = self.closers.get(&b.uid).cloned() {
                    self.close_replaced(&closer, old, l.ty);
                }
                self.local_put(&l, new);
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
        if let Some((left, index)) = crate::mutation::index_parts(&self.hir, cur) {
            // A field of a list element (`xs[i].n = 1`): the list receives the updated element.
            let i = self.expr(index)?;
            if self.dead {
                return Ok(());
            }
            let at = self.borrow(i);
            let mut new = Some(self.owned(x));
            return self.place_update(left, &mut |s, list| {
                let (elem, moved) = s.list_elem_at(list, at)?;
                let new = new.take().expect("one update");
                let updated = s.set_path(elem, true, &path, new)?;
                Ok(if moved {
                    s.b.list_fill(list, at, updated)
                } else {
                    s.b.list_set(list, at, updated)
                })
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
        if let Some(a) = self.aliases.get(&binding.uid).cloned() {
            let fields = Self::field_names(&path);
            let mut new = Some(self.owned(x));
            return self.alias_update(&a, &fields, &mut |s, old| {
                s.drop_value(old);
                Ok(new.take().expect("one update"))
            });
        }
        let l = self.local(&binding)?;
        let root = self.local_take(&l);
        let new = self.owned(x);
        let updated = self.set_path(root, true, &path, new)?;
        self.local_put(&l, updated);
        Ok(())
    }

    /// The field names of a chain of member selections.
    fn field_names(path: &[&Expr]) -> Vec<ms_check::types::Name> {
        path.iter()
            .filter_map(|e| match &e.kind {
                ExprKind::Member { name, .. } => Some(*name),
                _ => None,
            })
            .collect()
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
        if let Some((left, index)) = crate::mutation::index_parts(&self.hir, cur) {
            // A list element changes in place: the list receives the updated element.
            let i = self.expr(index)?;
            if self.dead {
                return Ok(());
            }
            let at = self.borrow(i);
            return self.place_update(left, &mut |s, list| {
                let (elem, moved) = s.list_elem_at(list, at)?;
                let updated = s.update_path(elem, &path, f)?;
                Ok(if moved {
                    s.b.list_fill(list, at, updated)
                } else {
                    s.b.list_set(list, at, updated)
                })
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
        if let Some(a) = self.aliases.get(&binding.uid).cloned() {
            let fields = Self::field_names(&path);
            return self.alias_update(&a, &fields, f);
        }
        let l = self.local(&binding)?;
        let root = self.local_take(&l);
        let updated = self.update_path(root, &path, f)?;
        self.local_put(&l, updated);
        Ok(())
    }

    /// Element `at` of the owned list `list`, owned: a droppable element is moved out (the caller
    /// refills the slot with `list_fill`, reported by the flag) instead of copied.
    pub(crate) fn list_elem_at(
        &mut self,
        list: ms_mir::ir::Value,
        at: ms_mir::ir::Value,
    ) -> Result<(ms_mir::ir::Value, bool), Error> {
        if !matches!(self.b.m.types.kind(self.ty_of(list)), TyKind::List(_)) {
            return Err(Error::new("element update on a non-list"));
        }
        let elem = self.b.list_get(list, at);
        Ok(self.take_projection(elem))
    }

    /// An owned `projection` of a value the caller owns and will overwrite: moved out when it
    /// needs dropping (the flag), a plain copy otherwise.
    pub(crate) fn take_projection(
        &mut self,
        projection: ms_mir::ir::Value,
    ) -> (ms_mir::ir::Value, bool) {
        if self.needs_drop(self.ty_of(projection)) {
            (self.b.move_out(projection), true)
        } else {
            let v = self.owned(Val {
                v: projection,
                own: false,
            });
            (v, false)
        }
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
        let (cur_own, moved) = self.take_projection(cur);
        let inner = self.update_path(cur_own, rest, f)?;
        Ok(if moved {
            self.b.rec_fill(rid, idx, obj, inner)
        } else {
            self.b.rec_set(rid, idx, obj, inner)
        })
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
        let mut moved = false;
        let inner = if rest.is_empty() {
            new
        } else {
            let cur = self.b.rec_get(rid, idx, obj);
            let cur_own = if obj_own {
                let (v, was_moved) = self.take_projection(cur);
                moved = was_moved;
                v
            } else if self.needs_drop(self.ty_of(cur)) {
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
        Ok(if moved {
            self.b.rec_fill(rid, idx, base, inner)
        } else {
            self.b.rec_set(rid, idx, base, inner)
        })
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
        let mut accessor_alias = None;
        let mut lent = None;
        let c = if binding.is_some() {
            let exclusive = binding
                .and_then(|p| self.hir.pattern_binding(p))
                .is_some_and(|b| self.cx.exclusive(b.uid));
            let found = if exclusive {
                let (alias, found) = self.alias_accessor(cond)?;
                accessor_alias = Some(alias);
                found
            } else if let Some((b, shape)) = self.lendable(binding, cond)? {
                // `if let x = m.get(k)`: the test is the entry's presence and `x` is the entry
                // itself, lent for the branch; no `Optional` is built.
                let Some((present, entry)) = self.lent_read(shape, cond)? else {
                    return Ok(());
                };
                lent = Some((b, entry));
                crate::alias::Found::Present(present)
            } else {
                crate::alias::Found::Opt(self.expr(cond)?)
            };
            if self.dead {
                return Ok(());
            }
            match found {
                crate::alias::Found::Opt(o) => {
                    scrutinee = Some(o);
                    self.success_test(o.v)?
                }
                crate::alias::Found::Present(c) => c,
            }
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
        if let Some(alias) = accessor_alias.as_ref().filter(|_| scrutinee.is_none()) {
            // `if var` over a map entry found by address: nothing was read to drop.
            let bnd = binding
                .and_then(|p| self.hir.pattern_binding(p))
                .ok_or_else(|| Error::new("if var without binding"))?;
            self.aliases.insert(bnd.uid, alias.clone());
        }
        if let Some((bnd, entry)) = lent.as_ref() {
            let payload = self.lent_payload(entry);
            self.bind_lent(bnd, payload);
        }
        if let (Some(p), Some(o)) = (binding, scrutinee) {
            let bnd = self
                .hir
                .pattern_binding(p)
                .ok_or_else(|| Error::new("if let without binding"))?;
            if self.cx.exclusive(bnd.uid) {
                // `if var`: the payload is the entry itself, not a copy.
                if o.own {
                    self.drop_value(o.v);
                }
                let alias = accessor_alias.expect("exclusive accessor evaluated before branch");
                self.aliases.insert(bnd.uid, alias);
            } else {
                let payload = self.success_payload(o.v)?;
                // The payload of a scrutinee that is itself a borrow is a lexical borrow for
                // the branch (the checker rejects changing its origin meanwhile): no copy. An
                // owned scrutinee is dropped here, so its payload is copied out first.
                let lend = !o.own
                    && !bnd.mutable
                    && matches!(p.kind, PatternKind::Name(_))
                    && self.ownership_checked()
                    && !self.slotted.contains(&bnd.uid)
                    && self.needs_drop(self.ty_of(payload));
                if lend {
                    self.bind_lent(&bnd, payload);
                } else {
                    self.bind_local(
                        &bnd,
                        Val {
                            v: payload,
                            own: false,
                        },
                    );
                }
                if o.own {
                    self.drop_value(o.v);
                }
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

    /// Whether `iter` is a local, or a field of one, that the loop cannot change: the local is
    /// immutable or `body` never mentions it. The loop then borrows the list instead of copying it.
    /// Whether `e` is a field path from a parameter the body only reads: the caller keeps it
    /// alive and unchanged for the whole call.
    pub(crate) fn stable_place(&self, e: &Expr) -> bool {
        let mut root = e;
        while let ExprKind::Member { left, .. } = &root.kind {
            root = left;
        }
        matches!(&root.kind, ExprKind::Name(_))
            && matches!(
                self.hir.resolution(root),
                ms_check::hir::Resolution::Local(b) if self.borrowed_params.contains(&b.uid)
            )
    }

    /// Whether the place `e` stays unchanged while `body` runs: a parameter the function only
    /// reads, or a local the body cannot change.
    fn unchanged_by(&self, e: &Expr, body: &[Stmt]) -> bool {
        self.stable_place(e) || self.iterates_untouched_local(e, body)
    }

    /// Whether a walk of a map of type `mt` can bind its items in place. A `MapEntry` is read
    /// straight out of the slot, which matches the record's layout only when the key fills
    /// whole words (`Int`, `Float`, `String`): the value then starts right after it in both.
    fn walks(&self, walk: Walk, mt: MTy) -> bool {
        let TyKind::Obj(_, a) = self.b.m.types.kind(mt) else {
            return false;
        };
        match walk {
            Walk::Entries => matches!(a[0], MTy::INT | MTy::FLOAT | MTy::STR),
            Walk::Values | Walk::Keys => true,
        }
    }

    /// `for e in m`, `for e in m.entries()`, `for v in m.values()` or `for k in m.keys()` over a
    /// map (or set) the body cannot change: walks the slots in place. The loop variable borrows
    /// the entry, so nothing is copied and no list is built.
    fn map_walk_loop(
        &mut self,
        loop_var: &ms_check::types::BindingRef,
        it: Val,
        walk: Walk,
        body: &[Stmt],
    ) -> Result<(), Error> {
        let mt = self.ty_of(it.v);
        let TyKind::Obj(_, a) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("not a map or set"));
        };
        let (kt, vt) = (a[0], a.get(1).copied());
        let elem = self.mty(&loop_var.ty)?;
        let mvar = self.b.declare_var(mt, ms_mir::ir::Mode::Borrow);
        self.b.def_var(mvar, it.v);
        let m = self.b.use_var(mvar);
        let count = self.call_runtime("msrt_map_slot_count", &[m], MTy::INT)?;
        let idx = self.b.declare_var(MTy::INT, ms_mir::ir::Mode::Borrow);
        let zero = self.b.iconst(0);
        self.b.def_var(idx, zero);
        let (header, probe, body_b, step, exit) = (
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
        );
        self.b.br(header, &[]);
        self.enter(header);
        let i = self.b.use_var(idx);
        let more = self.b.icmp(Cc::Lt, i, count);
        self.b.br_if(more, probe, &[], exit, &[]);
        self.b.seal_block(probe);
        self.enter(probe);
        let (kd, vd) = self.map_descs(mt)?;
        // A set is a map without a value descriptor: a null pointer.
        let vd = vd.unwrap_or_else(|| self.b.iconst(0));
        let slot = |s: &mut Self| {
            s.b.emit(Op::Slot, &[], Imm::Ty(MTy::PTR), Some(MTy::PTR))
                .expect("slot")
        };
        let (kp, vp) = (slot(self), slot(self));
        let m = self.b.use_var(mvar);
        let i = self.b.use_var(idx);
        let live = self.call_runtime("msrt_map_entry_ptrs", &[m, kd, vd, i, kp, vp], MTy::BOOL)?;
        self.b.br_if(live, body_b, &[], step, &[]);
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
        let load = |s: &mut Self, p: Value, t: MTy| {
            let addr =
                s.b.emit(Op::Load, &[p], Imm::Ty(MTy::PTR), Some(MTy::PTR))
                    .expect("load");
            s.b.emit(Op::Load, &[addr], Imm::Ty(t), Some(t))
                .expect("load")
        };
        let e = match (walk, vt) {
            (Walk::Keys, _) => load(self, kp, kt),
            (Walk::Values, Some(vt)) => load(self, vp, vt),
            // The slot holds the key and then the value exactly where a `MapEntry` record keeps
            // them when the key is word-sized and word-aligned (see `walks_entries`), so the
            // entry is read in place as one record.
            (Walk::Entries, Some(_)) => load(self, kp, elem),
            _ => return Err(Error::new("values of a set walk its keys")),
        };
        self.bind_lent(loop_var, e);
        self.stmts(body)?;
        self.pop_scope();
        self.loops.pop();
        if !self.dead {
            self.b.br(step, &[]);
        }
        self.b.seal_block(step);
        self.enter(step);
        let i = self.b.use_var(idx);
        let one = self.b.iconst(1);
        let n = self
            .b
            .emit(Op::IAdd, &[i, one], Imm::None, Some(MTy::INT))
            .expect("add");
        self.b.def_var(idx, n);
        self.b.br(header, &[]);
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.enter(exit);
        self.pop_scope();
        Ok(())
    }

    fn iterates_untouched_local(&self, iter: &Expr, body: &[Stmt]) -> bool {
        let mut root = iter;
        while let ExprKind::Member { left, .. } = &root.kind {
            root = left;
        }
        matches!(&root.kind, ExprKind::Name(_))
            && matches!(
                self.hir.resolution(root),
                ms_check::hir::Resolution::Local(b)
                    if !b.mutable || !crate::mutation::block_mentions(&self.hir, body, b.uid)
            )
    }

    /// `for piece in text.split(..)` over a piece iterator: no list, and a piece nothing else
    /// holds is rewritten in place for the next one.
    fn split_loop(
        &mut self,
        loop_var: &ms_check::types::BindingRef,
        it: Val,
        body: &[Stmt],
    ) -> Result<(), Error> {
        let var = self.bind_hidden(it);
        let (header, body_b, done, exit) = (
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
        );
        self.b.br(header, &[]);
        self.enter(header);
        let iter = self.b.use_var(var);
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(MTy::STR), Some(MTy::PTR))
            .expect("slot");
        let more = self.call_runtime("msrt_split_next", &[iter, slot], MTy::BOOL)?;
        self.b.br_if(more, body_b, &[], done, &[]);
        self.b.seal_block(body_b);
        self.b.seal_block(done);
        // The piece is a borrow of the iterator's buffer, valid until the next call.
        self.enter(done);
        self.b.br(exit, &[]);
        self.enter(body_b);
        let depth = self.scopes.len();
        self.loops.push(LoopCtx {
            brk: exit,
            cont: header,
            depth,
            cont_used: false,
            brk_used: false,
        });
        self.push_scope();
        let e = self
            .b
            .emit(Op::Load, &[slot], Imm::Ty(MTy::STR), Some(MTy::STR))
            .expect("load");
        if !loop_var.mutable && !self.slotted.contains(&loop_var.uid) {
            self.bind_lent(loop_var, e);
        } else {
            self.bind_local(loop_var, Val { v: e, own: false });
        }
        self.stmts(body)?;
        self.pop_scope();
        self.loops.pop();
        if !self.dead {
            self.b.br(header, &[]);
        }
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.enter(exit);
        self.pop_scope();
        Ok(())
    }

    /// `for c in text.chars()`: scans the bytes of `text`. An ASCII byte is the shared
    /// one-character string for it, borrowed and counted by nothing; any other character is
    /// built by the runtime and kept in a hidden variable until the next one replaces it.
    /// With `scalars` (`for c in text.scalar_values()`), each step is the scalar value instead:
    /// an ASCII byte is its own value, and the runtime decodes any other.
    fn chars_loop(
        &mut self,
        loop_var: &ms_check::types::BindingRef,
        text: Val,
        scalars: bool,
        body: &[Stmt],
    ) -> Result<(), Error> {
        let item = if scalars { MTy::INT } else { MTy::STR };
        let text_var = self.bind_hidden(text);
        let empty = self.b.str_lit("");
        let keep = self.bind_hidden(Val {
            v: empty,
            own: false,
        });
        let s = self.b.use_var(text_var);
        let len = self.call_runtime("msrt_string_byte_length", &[s], MTy::INT)?;
        let zero = self.b.iconst(0);
        let idx = self.b.declare_var(MTy::INT, ms_mir::ir::Mode::Borrow);
        self.b.def_var(idx, zero);
        let cur = self.b.declare_var(item, ms_mir::ir::Mode::Borrow);
        let (header, scan, fast, slow, join, exit) = (
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
        );
        self.b.br(header, &[]);
        self.enter(header);
        let i = self.b.use_var(idx);
        let more = self.b.icmp(Cc::Lt, i, len);
        self.b.br_if(more, scan, &[], exit, &[]);
        self.b.seal_block(scan);
        self.enter(scan);
        let s = self.b.use_var(text_var);
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
        self.enter(fast);
        let ch = if scalars {
            byte
        } else {
            self.b
                .emit(Op::StrAscii, &[byte], Imm::None, Some(MTy::STR))
                .expect("ascii")
        };
        let one = self.b.iconst(1);
        let next = self
            .b
            .emit(Op::IAdd, &[i, one], Imm::None, Some(MTy::INT))
            .expect("add");
        self.b.def_var(cur, ch);
        self.b.def_var(idx, next);
        self.b.br(join, &[]);
        self.enter(slow);
        let s = self.b.use_var(text_var);
        let i = self.b.use_var(idx);
        let ch = if scalars {
            self.call_runtime("msrt_string_scalar_at_byte", &[s, i], MTy::INT)?
        } else {
            self.call_runtime("msrt_string_char_at", &[s, i], MTy::STR)?
        };
        let width = self.call_runtime("msrt_string_char_width", &[s, i], MTy::INT)?;
        let next = self
            .b
            .emit(Op::IAdd, &[i, width], Imm::None, Some(MTy::INT))
            .expect("add");
        if !scalars {
            let old = self.b.use_var(keep);
            self.drop_value(old);
            self.b.def_var(keep, ch);
        }
        self.b.def_var(cur, ch);
        self.b.def_var(idx, next);
        self.b.br(join, &[]);
        self.b.seal_block(join);
        self.enter(join);
        let depth = self.scopes.len();
        self.loops.push(LoopCtx {
            brk: exit,
            cont: header,
            depth,
            cont_used: false,
            brk_used: false,
        });
        self.push_scope();
        let ch = self.b.use_var(cur);
        self.bind_local(loop_var, Val { v: ch, own: false });
        self.stmts(body)?;
        self.pop_scope();
        self.loops.pop();
        if !self.dead {
            self.b.br(header, &[]);
        }
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.enter(exit);
        self.pop_scope();
        Ok(())
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
                let lent = !loop_var.mutable && !self.slotted.contains(&loop_var.uid);
                let call_root = match &iter.kind {
                    ExprKind::Call { callee, args } if args.is_empty() => match &callee.kind {
                        ExprKind::Member { left, .. } => Some(&**left),
                        _ => None,
                    },
                    _ => None,
                };
                if lent && call_root.is_some_and(|r| self.unchanged_by(r, body)) {
                    self.map_walk_for = Some(iter as *const Expr);
                }
                self.split_iter_for = Some(iter as *const Expr);
                self.chars_iter_for = Some(iter as *const Expr);
                self.keys_view_for = Some(iter as *const Expr);
                let it = self.expr(iter);
                self.split_iter_for = None;
                self.chars_iter_for = None;
                self.keys_view_for = None;
                self.map_walk_for = None;
                let walk = self.map_walk.take();
                let it = it?;
                if self.dead {
                    self.scopes.pop();
                    return Ok(());
                }
                let direct = crate::mapset::is_map_or_set(self.b.m, self.ty_of(it.v))
                    && lent
                    && !it.own
                    && self.unchanged_by(iter, body);
                let walk = walk.filter(|w| self.walks(*w, self.ty_of(it.v)));
                if let Some(walk) = walk.or_else(|| {
                    direct
                        .then(|| {
                            let is_map = matches!(
                                self.b.m.types.kind(self.ty_of(it.v)),
                                TyKind::Obj(n, _) if n == "Map"
                            );
                            if is_map { Walk::Entries } else { Walk::Keys }
                        })
                        .filter(|w| self.walks(*w, self.ty_of(it.v)))
                }) {
                    return self.map_walk_loop(&loop_var, it, walk, body);
                }
                let mut it = it;
                let mut ity = self.ty_of(it.v);
                if matches!(self.b.m.types.kind(ity), TyKind::Obj(n, _) if n == "SplitIter") {
                    return self.split_loop(&loop_var, it, body);
                }
                if ity == MTy::STR {
                    let scalars = std::mem::take(&mut self.scalars_scan);
                    return self.chars_loop(&loop_var, it, scalars, body);
                }
                if crate::mapset::is_map_or_set(self.b.m, ity) {
                    // A map yields its entries and a set its values, as a list snapshot.
                    let elem = self.mty(&loop_var.ty)?;
                    let list = self.b.m.types.list(elem);
                    it = match self.b.m.types.kind(ity).clone() {
                        TyKind::Obj(n, _) if n == "Map" => {
                            self.map_entries(Some(iter), it, list)?
                        }
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
                let frozen = self.ownership_checked()
                    && self
                        .hir
                        .stmt(s)
                        .loop_binding
                        .is_some_and(|b| self.cx.shared(b.uid));
                let var = if !it.own && (frozen || self.iterates_untouched_local(iter, body)) {
                    // The checker keeps the list unchanged while the loop variable borrows it
                    // (or the body never names it): walk it in place instead of copying it, so
                    // a lending function can hand back its elements.
                    let ty = self.ty_of(it.v);
                    let var = self.b.declare_var(ty, ms_mir::ir::Mode::Borrow);
                    self.b.def_var(var, it.v);
                    var
                } else {
                    self.bind_hidden(it)
                };
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
        if list_var.is_some() && !loop_var.mutable && !self.slotted.contains(&loop_var.uid) {
            // The loop holds the list and the body cannot change it: the element is a borrow.
            self.bind_lent(&loop_var, e);
        } else {
            self.bind_local(&loop_var, Val { v: e, own: false });
        }
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

/// `let`/`var` of a number, boolean or text without interpolation: evaluating it has no effect.
fn is_literal_bind(s: &Stmt) -> bool {
    let StmtKind::Bind { value, .. } = &s.kind else {
        return false;
    };
    match &value.kind {
        ExprKind::Number(_) | ExprKind::Bool(_) => true,
        ExprKind::Text(parts) => parts
            .iter()
            .all(|p| matches!(p, ms_syntax::ast::TextPart::Lit(_))),
        _ => false,
    }
}

/// What an in-place walk of a map or set binds to the loop variable.
#[derive(Clone, Copy)]
pub(crate) enum Walk {
    /// A `MapEntry` of the borrowed key and value.
    Entries,
    /// The borrowed value.
    Values,
    /// The borrowed key (a set's element).
    Keys,
}
