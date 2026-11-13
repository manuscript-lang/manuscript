//! Statements: blocks, bindings, assignment and loops.

use super::*;

impl Walker<'_> {
    // --------------------------------------------------- statements

    pub(super) fn block(&mut self, body: &[Stmt]) {
        let mark = self.declared.len();
        // Borrows the enclosing statement released at their last use stay held until that
        // statement ends: a closure body in an argument must not release them early.
        let outer = std::mem::take(&mut self.pending);
        for s in body {
            self.stmt(s);
            self.release_pending();
        }
        self.pending.extend(outer);
        let ended: Vec<usize> = self.declared.drain(mark..).collect();
        self.promises_outliving(&ended);
        self.active.release(&ended, |_| true);
    }

    /// A promise kept by a binding that outlives the block must not read a local that ends with it.
    pub(super) fn promises_outliving(&mut self, ended: &[usize]) {
        let mut found: Vec<(Pos, String, String)> = Vec::new();
        for a in self.active.iter() {
            if a.why != PROMISE_WHY || ended.contains(&a.holder) {
                continue;
            }
            for (place, _) in &a.origins {
                if ended.contains(&place.root) {
                    found.push((
                        a.pos,
                        self.syms.str(a.holder_name).to_string(),
                        self.syms.str(self.name_of(place.root)).to_string(),
                    ));
                }
            }
        }
        for (pos, holder, name) in found {
            self.error(
                pos,
                format!(
                    "this promise reads `{name}`, which ends before `{holder}` does; start the promise from a value that outlives `{holder}`, or wait for it before the block ends"
                ),
            );
        }
    }

    /// Hands the borrows of promises moved since the statement began to `holder`, keeping the
    /// places that are still in scope.
    pub(super) fn take_carried(&mut self, holder: usize, holder_name: Name) {
        for mut a in std::mem::take(&mut self.carried) {
            a.origins.retain(|(p, _)| self.declared.contains(&p.root));
            if a.origins.is_empty() || a.holder == holder {
                continue;
            }
            a.holder = holder;
            a.holder_name = holder_name;
            self.active.push(a);
        }
    }

    pub(super) fn stmt(&mut self, s: &Stmt) {
        self.carried.clear();
        match &s.kind {
            StmtKind::Bind {
                mutable,
                pattern,
                value,
                ..
            } => self.bind(s, *mutable, pattern, value),
            StmtKind::Assign { target, value, .. } => self.assign(s, target, value),
            StmtKind::Call(e) => self.expr(e, Demand::Discard),
            StmtKind::Return(e) => {
                if let Some(e) = e {
                    self.returned(e);
                }
            }
            StmtKind::Break | StmtKind::Continue => {}
            StmtKind::If {
                binding,
                mutable,
                cond,
                body,
                else_body,
            } => self.if_stmt(s, binding.as_ref(), *mutable, cond, body, else_body),
            StmtKind::While { cond, body } => {
                self.expr(cond, Demand::Read);
                self.release_pending();
                let entry = self.active.clone();
                self.block(body);
                self.active = Self::join_active(entry, std::mem::take(&mut self.active));
            }
            StmtKind::For { iter, body, .. } => match self.cx.m.stmt(s).expansion {
                // A `for` over an `Iterator` is the loop the checker expanded it into.
                Some(expansion) => self.block(&expansion),
                None => self.for_stmt(s, iter, body),
            },
        }
    }

    pub(super) fn if_stmt(
        &mut self,
        s: &Stmt,
        binding: Option<&Pattern>,
        mutable: bool,
        cond: &Expr,
        body: &[Stmt],
        else_body: &[Stmt],
    ) {
        let mark = self.declared.len();
        match binding {
            Some(p) => {
                // A scalar entry is copied out of the map, so the entry's place is the map itself.
                let probed = match &cond.kind {
                    ExprKind::Probe(target) if mutable => Some(&**target),
                    ExprKind::Call { callee, .. } if mutable && self.map_get(cond) => {
                        match &callee.kind {
                            ExprKind::Member { left, .. } => Some(&**left),
                            _ => None,
                        }
                    }
                    _ => None,
                };
                let scrutinee = self.scrutinee(probed.unwrap_or(cond));
                if mutable {
                    self.mutable_payload(p, cond, &scrutinee);
                    self.payload_resource(s, p, &scrutinee);
                } else {
                    self.pattern_bindings(p, &scrutinee, Role::Pattern);
                    self.payload_resource(s, p, &scrutinee);
                }
            }
            None => self.expr(cond, Demand::Read),
        }
        self.release_pending();
        let entry = self.active.clone();
        self.block(body);
        let then_state = std::mem::replace(&mut self.active, entry);
        // The payload bindings and their borrows end with the then-branch.
        let ended: Vec<usize> = self.declared.drain(mark..).collect();
        self.active.release(&ended, |_| true);
        self.block(else_body);
        let else_state = std::mem::take(&mut self.active);
        let then_state: super::active::ActiveBorrows = then_state
            .into_iter()
            .filter(|a| !ended.contains(&a.holder))
            .collect();
        self.active = Self::join_active(then_state, else_state);
    }

    /// An `if let name = value` that owns a resource payload closes it when the branch ends,
    /// unless the branch moves it on.
    pub(super) fn payload_resource(&mut self, s: &Stmt, p: &Pattern, source: &Scrutinee) {
        if !source.owned || !matches!(p.kind, PatternKind::Name(_)) {
            return;
        }
        let Some(b) = self.cx.m.pattern_binding(p) else {
            return;
        };
        if self.may_close(&b.ty) {
            let closable = self.closable(s, &b.ty);
            self.resources.push((b.uid, b.name, p.pos, closable));
        }
    }

    pub(super) fn for_stmt(&mut self, s: &Stmt, iter: &Expr, body: &[Stmt]) {
        let mark = self.declared.len();
        let source = self.scrutinee(iter);
        self.release_pending();
        // The iterable stays unchanged for the whole loop.
        let hidden = usize::MAX - self.hidden;
        self.hidden += 1;
        if !source.origins.is_empty() {
            self.active.push(Borrow {
                holder: hidden,
                holder_name: n("for"),
                origins: source.origins.iter().cloned().map(|p| (p, false)).collect(),
                pos: iter.pos,
                why: "the loop is iterating it".to_string(),
            });
        }
        if let Some(b) = self.cx.m.stmt(s).loop_binding {
            let class = self.cx.classes.class(self.syms, &b.ty);
            if class == Class::Copy || source.owned {
                self.declare(&b, Role::Loop, Perm::Immutable, None, false);
                if let Some(f) = self.facts.bindings.get_mut(&b.uid) {
                    f.owned = false;
                }
                // An owned iteration hands each resource element to the loop variable, which
                // closes it at the end of the iteration unless the body moves it on.
                if class == Class::Resource
                    && source.owned
                    && matches!(b.ty.kind, Kind::Type | Kind::Alternative | Kind::Native)
                {
                    self.resources.push((b.uid, b.name, iter.pos, true));
                }
            } else {
                self.declare_borrow(
                    &b,
                    Role::Loop,
                    source.origins.clone(),
                    iter.pos,
                    "loop variable",
                );
                self.defer(&b, &source);
            }
        }
        let entry = self.active.clone();
        self.block(body);
        let end = std::mem::take(&mut self.active);
        let ended: Vec<usize> = self.declared.drain(mark..).collect();
        self.active = Self::join_active(entry, end)
            .into_iter()
            .filter(|a| a.holder != hidden && !ended.contains(&a.holder))
            .collect();
    }

    pub(super) fn bind(&mut self, s: &Stmt, mutable: bool, pattern: &Pattern, value: &Expr) {
        let PatternKind::Name(_) = pattern.kind else {
            let scrutinee = self.scrutinee(value);
            let role = if mutable { Role::Var } else { Role::Pattern };
            self.pattern_bindings(pattern, &scrutinee, role);
            if scrutinee.owned {
                // The pattern owns the parts it names: a resource among them closes at the
                // scope end unless the scope moves it on, like any other owned binding.
                self.pattern_resources(pattern, s);
            }
            return;
        };
        let Some(b) = self.cx.m.pattern_binding(pattern) else {
            self.expr(value, Demand::Move);
            return;
        };
        let role = if mutable { Role::Var } else { Role::Let };
        if !mutable
            && let Some(fix) = crate::suggestions::binding_to_var(&self.cx.m.data.source, s.pos)
        {
            self.var_fixes.insert(b.uid, fix);
        }
        let class = self.cx.classes.class(self.syms, &b.ty);
        // A scalar copies, `let` or `var`; any other binding of a place borrows it, shared for
        // `let` and exclusive for `var`.
        if class != Class::Copy
            && let Some(origins) = self.projection_origins(value)
        {
            // Reading part of a value that stays where it is.
            if mutable && let Some(entry) = self.entry_get(value) {
                // `var x = map.get(key).get()`: the entry, borrowed exclusively like
                // `if var x = map.get(key)`; an absent key faults.
                if let ExprKind::Call { callee, args } = &entry.kind
                    && let ExprKind::Member { left, .. } = &callee.kind
                {
                    self.expr(&args[0].value, Demand::Read);
                    let scrutinee = self.scrutinee(left);
                    self.mutable_entry(&b, role, entry, &scrutinee, pattern.pos);
                }
                return;
            }
            if mutable && let ExprKind::Call { .. } = &value.kind {
                self.bind_getter(s, &b, role, value);
                return;
            }
            if mutable {
                if let Some((info, _)) = self.place(value) {
                    // The origin must itself be changeable and free of other borrows.
                    let before = self.diags.len();
                    self.mutate(pattern.pos, &info, "borrow mutably");
                    if self.diags.len() == before {
                        let parent = self.borrow_parent(&info.root);
                        self.declare_mut_borrow(&b, role, info.resolved, pattern.pos, parent);
                    } else {
                        // Already reported; an owned binding avoids a cascade.
                        self.declare(&b, role, Perm::Mutable, None, false);
                    }
                } else if class == Class::Copy {
                    // A scalar computed by a call has no place to borrow; the binding owns it.
                    self.expr(value, Demand::Read);
                    self.declare(&b, role, Perm::Mutable, None, false);
                } else {
                    let text = self.expr_text(value);
                    self.expr(value, Demand::Read);
                    self.error(
                        pattern.pos,
                        format!(
                            "`var {}` cannot borrow `{text}` mutably: it is a read-only result; clone it with `{text}.{CLONE}()` to own it",
                            self.syms.str(b.name)
                        ),
                    );
                    self.declare(&b, role, Perm::Mutable, None, false);
                }
            } else {
                // A part wrapped on the way in (`let o: String? = r.name`) stays a reference.
                if self.wrapped_borrow(value).is_some() {
                    self.facts.view_wraps.insert(value.id);
                }
                // A part converted to an interface (`let e: Error = r.cause`) or a view
                // returner's result: the binding owns the view's box and borrows the sources.
                if self.is_view(value) {
                    self.view_locals.insert(b.uid);
                    if self.result_payload(value).is_some() {
                        self.view_calls.insert(value.id);
                    }
                }
                self.expr(value, Demand::Read);
                self.declare_borrow(&b, role, origins, pattern.pos, "binding of a part of it");
            }
            return;
        }
        // A name converted to an interface on the way into the binding (`let e: Error = cause`,
        // `let r: Int! = error(cause)`) is a view of it: the binding owns the view's box and
        // borrows the name, whether or not this is the name's last use.
        if !mutable
            && class != Class::Copy
            && let Some(inner) = self.view_source(value)
            && let ExprKind::Name(_) = &inner.kind
            && let Resolution::Local(src) = self.cx.m.resolution(inner)
            && self.meta.contains_key(&src.uid)
        {
            let origins = self.resolve(&Place::local(src.uid));
            self.view_locals.insert(b.uid);
            if self.result_payload(value).is_some() {
                self.view_calls.insert(value.id);
            }
            self.expr(value, Demand::Read);
            self.declare_borrow(&b, role, origins, pattern.pos, "binding of a view of it");
            return;
        }
        // A name wrapped on the way into the binding (`let o: Item? = item`, `let r = ok(x)`)
        // is a reference to it, as a plain name is, unless this is the source's last use.
        if !mutable
            && class != Class::Copy
            && let Some(inner) = self.wrapped_borrow(value)
            && let ExprKind::Name(_) = &inner.kind
            && let Resolution::Local(src) = self.cx.m.resolution(inner)
            && let Some(src_meta) = self.meta.get(&src.uid)
            && self.cx.classes.class(self.syms, &src.ty) != Class::Copy
            && (!self.is_last(inner.id, &src)
                || matches!(src_meta.perm, Perm::Borrowed | Perm::MutBorrowed))
        {
            let origins = self.resolve(&Place::local(src.uid));
            self.facts.view_wraps.insert(value.id);
            self.expr(value, Demand::Read);
            self.declare_borrow(
                &b,
                role,
                origins,
                pattern.pos,
                "binding of a borrowed value",
            );
            return;
        }
        if let ExprKind::Lambda(_) = &value.kind {
            self.expr_lambda_binding(value, &b, role, mutable);
            return;
        }
        if let Some(recv) = self.changing_method_value(value) {
            self.method_value_binding(value, recv, &b, role, mutable, true);
            return;
        }
        if let Some(recv) = self.method_value(value) {
            self.method_value_binding(value, recv, &b, role, mutable, false);
            return;
        }
        // A name bound to another name of the same type is a reference to it: shared for `let`,
        // exclusive for `var` when the source can change (a `var` binding or borrow), as for a
        // part of it. A `var` of an immutable source takes the value over instead (below). Only
        // a primitive copies, and a binding of another type converts.
        if class != Class::Copy
            && let ExprKind::Name(_) = &value.kind
            && let Resolution::Local(src) = self.cx.m.resolution(value)
            && let Some(src_meta) = self.meta.get(&src.uid)
            && same(&src.ty, &b.ty)
            && (!mutable || matches!(src_meta.perm, Perm::Mutable | Perm::MutBorrowed))
            // At the source's last use the value moves instead, as before: the reference would
            // be indistinguishable, and `let tmp = a; a = b` keeps working.
            && (!self.is_last(value.id, &src)
                || matches!(src_meta.perm, Perm::Borrowed | Perm::MutBorrowed))
        {
            let origins = self.resolve(&Place::local(src.uid));
            if mutable {
                if let Some((info, _)) = self.place(value) {
                    let before = self.diags.len();
                    self.mutate(pattern.pos, &info, "borrow mutably");
                    if self.diags.len() == before {
                        let parent = self.borrow_parent(&info.root);
                        self.declare_mut_borrow(&b, role, origins, pattern.pos, parent);
                    } else {
                        self.declare(&b, role, Perm::Mutable, None, false);
                    }
                    return;
                }
            } else {
                // A view local named for the last time hands its box on: the new name is the
                // view local now, borrowing the same origins, and the old one owns nothing.
                // Named again later, the new name is a plain reference to the box.
                if self.view_locals.contains(&src.uid) && self.is_last(value.id, &src) {
                    let origins = self.meta[&src.uid].origins.clone();
                    self.view_locals.insert(b.uid);
                    self.facts.view_moves.insert(value.id);
                    self.view_move = Some(value.id);
                    self.expr(value, Demand::Move);
                    self.view_move = None;
                    self.declare_borrow(&b, role, origins, pattern.pos, "binding of a view of it");
                    return;
                }
                // Named again later, the new name points at the view local's box, which ends
                // with it, not at what the view borrows.
                let origins = if self.view_locals.contains(&src.uid) {
                    vec![Place::local(src.uid)]
                } else {
                    origins
                };
                self.expr(value, Demand::Read);
                self.declare_borrow(
                    &b,
                    role,
                    origins,
                    pattern.pos,
                    "binding of a borrowed value",
                );
                return;
            }
        }
        self.expr(value, Demand::Move);
        self.declare(
            &b,
            role,
            if mutable {
                Perm::Mutable
            } else {
                Perm::Immutable
            },
            None,
            false,
        );
        // The binding owns the value (a call result among them: a resource a method on another
        // resource returns, `client.request(..)`, is the caller's to close), so a resource it holds
        // closes at the scope end unless the scope moves it on.
        if self.may_close(&b.ty) {
            let closable = self.closable(s, &b.ty);
            self.resources.push((b.uid, b.name, pattern.pos, closable));
        }
        if ty_holds_promise(self.syms, &b.ty) {
            self.take_carried(b.uid, b.name);
        }
        if self.entry_call(value) || self.holds_lambda_promises(value) {
            // The promise reads what its entry captures until it is dropped with its scope.
            let origins = self.entry_places(value);
            if !origins.is_empty() {
                self.active.push(Borrow {
                    holder: b.uid,
                    holder_name: b.name,
                    origins: origins.into_iter().map(|p| (p, false)).collect(),
                    pos: value.pos,
                    why: PROMISE_WHY.to_string(),
                });
            }
        }
    }

    /// `var x = f(b)` where `f` returns one chain of fields of one argument: an exclusive borrow of
    /// that place, which lowering names instead of calling `f` (`getter_borrows`). Any other
    /// reference result cannot be bound with `var`.
    pub(super) fn bind_getter(&mut self, s: &Stmt, b: &BindingRef, role: Role, value: &Expr) {
        let pos = s.pos;
        let text = self.expr_text(value);
        let ret_borrow = result_borrow(self.cx.m, value, self.cx.summaries);
        let operands = self.borrow_operands(value, &ret_borrow).unwrap_or_default();
        let target = match (&ret_borrow.path, operands.as_slice()) {
            (Some((None, fields)), [recv]) if ret_borrow.receiver => Some((*recv, fields.clone())),
            (Some((Some(label), fields)), [arg])
                if self.borrow_operand_label(value, arg) == Some(*label) =>
            {
                Some((*arg, fields.clone()))
            }
            _ => None,
        };
        let Some((operand, fields)) = target.filter(|(o, _)| self.is_place(o)) else {
            self.expr(value, Demand::Read);
            self.error(
                pos,
                format!(
                    "`var {}` cannot borrow `{text}` mutably: the result is a reference into more than one place; bind it with `let` to read it, or borrow the field it returns directly",
                    self.syms.str(b.name)
                ),
            );
            self.declare(b, role, Perm::Mutable, None, false);
            return;
        };
        let Some((mut info, _)) = self.place(operand) else {
            self.expr(value, Demand::Read);
            self.declare(b, role, Perm::Mutable, None, false);
            return;
        };
        info.resolved = info
            .resolved
            .iter()
            .map(|p| {
                fields
                    .iter()
                    .fold(p.clone(), |p, f| p.then(Step::Field(*f)))
            })
            .collect();
        info.text = text;
        let before = self.diags.len();
        self.mutate(pos, &info, "borrow mutably");
        if self.diags.len() == before {
            let parent = self.borrow_parent(&info.root);
            self.facts.getter_borrows.insert(value.id, fields);
            self.declare_mut_borrow(b, role, info.resolved, pos, parent);
        } else {
            self.declare(b, role, Perm::Mutable, None, false);
        }
    }

    /// `places` plus, for each one rooted in a local that holds borrows (a carrier or a closure),
    /// the sources it holds: a value derived from it (a call result, a binding of its `ref` field,
    /// a closure that captures it) must keep those sources unchanged too, even after the holder
    /// itself is gone.
    pub(super) fn with_held(&self, places: Vec<Place>) -> Vec<Place> {
        let mut out = places.clone();
        for p in &places {
            let borrowed = self
                .meta
                .get(&p.root)
                .is_some_and(|m| matches!(m.perm, Perm::Borrowed | Perm::MutBorrowed));
            if borrowed {
                continue;
            }
            for a in self.active.iter().filter(|a| a.holder == p.root) {
                for (o, _) in &a.origins {
                    if !out.contains(o) {
                        out.push(o.clone());
                    }
                }
            }
        }
        out
    }

    pub(super) fn expr_lambda_binding(
        &mut self,
        value: &Expr,
        b: &BindingRef,
        role: Role,
        mutable: bool,
    ) {
        let ExprKind::Lambda(l) = &value.kind else {
            return;
        };
        let escaping = self.escaped.contains(&value.id);
        let origins = self.lambda(value, l, escaping);
        self.declare(
            b,
            role,
            if mutable {
                Perm::Mutable
            } else {
                Perm::Immutable
            },
            None,
            false,
        );
        if let Some(m) = self.meta.get_mut(&b.uid) {
            m.lambda = Some(value.id);
        }
        if !escaping && !origins.is_empty() && self.used.contains(&b.uid) {
            self.active.push(Borrow {
                holder: b.uid,
                holder_name: b.name,
                origins,
                pos: value.pos,
                why: "closure capture".to_string(),
            });
        }
    }

    /// A method used as a value (`xs.append`, `re.find`, or specialized, `log.error[Unit]`):
    /// the method and its receiver expression.
    pub(super) fn method_value_parts<'e>(&self, e: &'e Expr) -> Option<(MethodRef, &'e Expr)> {
        let member = method_callee(self.syms, self.cx.m, e);
        let ExprKind::Member { left, .. } = &member.kind else {
            return None;
        };
        if self.cx.m.ty(e).kind != Kind::Function
            || self.callees.contains(&e.id)
            || self.callees.contains(&member.id)
        {
            return None;
        }
        let resolution = match self.cx.m.resolution(member) {
            Resolution::Value => self.cx.m.resolution(e),
            r => r,
        };
        let Resolution::Method(m) = resolution else {
            return None;
        };
        Some((m, &**left))
    }

    /// The receiver of a method value that changes it (`xs.append`).
    pub(super) fn changing_method_value<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let (m, left) = self.method_value_parts(e)?;
        (receiver_mode(self.syms, self.cx.summaries, &m) == Some(ParamMode::Mutate)).then_some(left)
    }

    /// Takes the receiver of a method value that changes it as a mutable borrow. The value
    /// shares the variable, so it cannot outlive the statement. Returns the place it holds.
    pub(super) fn changing_method_use(
        &mut self,
        e: &Expr,
        recv: &Expr,
        escaping: bool,
    ) -> Vec<(Place, bool)> {
        if let Some((m, _)) = self.method_value_parts(e)
            && native_method_argument_modes(self.syms, &m).contains(&ParamMode::Move)
        {
            // A function value borrows its arguments, so the stored one would be a copy.
            for held in self.cx.m.ty(recv).args.clone() {
                // A type parameter stays accepted, as before; only concrete types are checked.
                if held.kind == Kind::Variable {
                    continue;
                }
                self.require_clonable(
                    e,
                    &held,
                    "this method value stores its argument in the receiver, so it",
                );
            }
        }
        // A call closes a resource entry the mutator discards; a method value does not, so the
        // entry would leak. Source-defined methods with the same names keep their own semantics.
        if let Some((m, _)) = self.method_value_parts(e)
            && m.native != Native::Source
            && crate::std_ops::collection_mutation(self.syms, &m)
            && m.name()
                .is_some_and(|n| crate::std_ops::discards_entries(self.syms.str(n)))
            // An operation that also stores its argument was rejected above, with that reason.
            && !native_method_argument_modes(self.syms, &m).contains(&ParamMode::Move)
        {
            for held in self.cx.m.ty(recv).args.clone() {
                if held.kind != Kind::Variable && !self.cx.classes.clonable(self.syms, &held) {
                    self.error(
                        e.pos,
                        format!(
                            "this method value discards entries of the receiver, and a method value cannot close `{}`, which has one owner; call the method, or write a closure",
                            held.display(self.syms)
                        ),
                    );
                    return Vec::new();
                }
            }
        }
        // A temporary receiver has no variable to share, so its updates would be lost.
        let whole = matches!(recv.kind, ExprKind::Name(_));
        let Some((info, _)) = self.place(recv).filter(|_| whole && self.is_place(recv)) else {
            self.error(
                e.pos,
                "a method value that changes its receiver must come from a variable, like `xs.append`; call the method, or write a closure",
            );
            return Vec::new();
        };
        if escaping {
            self.error(
                e.pos,
                format!("this method value changes `{0}`, so it cannot be returned, stored or passed to a moving parameter; keep it local, or call the method instead", self.syms.str(info.root.name)),
            );
            return Vec::new();
        }
        self.mutate(e.pos, &info, "change");
        self.facts.bound_borrows.insert(e.id);
        info.resolved.into_iter().map(|p| (p, true)).collect()
    }

    /// The receiver of a method value that only reads it (`re.find`).
    pub(super) fn method_value<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let (m, left) = self.method_value_parts(e)?;
        (receiver_mode(self.syms, self.cx.summaries, &m) != Some(ParamMode::Mutate)).then_some(left)
    }

    /// Walks the receiver of a method value that only reads it. The value is a closure over the
    /// receiver, which has one owner: a value that stays local borrows the receiver's place while
    /// it lives (`bound_borrows`), and one that escapes takes the receiver over, moving it at its
    /// last use. A `Copy` receiver is copied, and a temporary one is owned by the value. Returns
    /// the places a borrowing value holds.
    pub(super) fn method_value_use(
        &mut self,
        e: &Expr,
        recv: &Expr,
        escaping: bool,
    ) -> Vec<(Place, bool)> {
        if let Some((m, _)) = self.method_value_parts(e)
            && let Some(payload) = wrapper_passthrough(&m, &self.cx.m.ty(recv))
        {
            // A function value can run repeatedly and cannot move out its captured receiver.
            // Only the preserved payload needs copying; callback inputs remain borrowed.
            self.require_clonable(
                e,
                &payload,
                "this method value keeps its receiver for repeated calls, so it",
            );
        }
        if let Some((m, _)) = self.method_value_parts(e)
            && let Some(element) = element_handed_out(self.syms, &m, &self.cx.m.ty(recv))
        {
            // The call borrows the entry; a method value returns an owned value, so it copies it.
            self.require_clonable(
                e,
                &element,
                "this method value hands out an element on each call, so it",
            );
        }
        if self.is_place(recv)
            && let Some((m, _)) = self.method_value_parts(e)
            && takes_element_mutator(&m)
        {
            self.error(
                e.pos,
                "this method takes a callback that can change the receiver's elements, so it cannot be used as a value; call it, or write a closure",
            );
            return Vec::new();
        }
        if self.class_of(recv) == Class::Copy || !self.is_place(recv) {
            self.expr(recv, Demand::Read);
            return Vec::new();
        }
        if escaping {
            self.expr(recv, Demand::Move);
            return Vec::new();
        }
        self.expr(recv, Demand::Read);
        self.facts.bound_borrows.insert(e.id);
        self.pure_places(recv)
            .unwrap_or_default()
            .into_iter()
            .map(|p| (p, false))
            .collect()
    }

    pub(super) fn method_value_binding(
        &mut self,
        value: &Expr,
        recv: &Expr,
        b: &BindingRef,
        role: Role,
        mutable: bool,
        changing: bool,
    ) {
        let escaping = self.escaped.contains(&value.id);
        let origins = if changing {
            self.changing_method_use(value, recv, escaping)
        } else {
            self.method_value_use(value, recv, escaping)
        };
        self.declare(
            b,
            role,
            if mutable {
                Perm::Mutable
            } else {
                Perm::Immutable
            },
            None,
            false,
        );
        if let Some(m) = self.meta.get_mut(&b.uid) {
            m.lambda = Some(value.id);
        }
        if !origins.is_empty() && self.used.contains(&b.uid) {
            self.active.push(Borrow {
                holder: b.uid,
                holder_name: b.name,
                origins,
                pos: value.pos,
                why: "method value".to_string(),
            });
        }
    }

    pub(super) fn assign(&mut self, s: &Stmt, target: &AssignTarget, value: &Expr) {
        let refilled = match target {
            AssignTarget::Name(_) => self.cx.m.assigned(value).filter(|b| {
                self.meta
                    .get(&b.uid)
                    .is_some_and(|m| m.parameter.is_some() && m.perm == Perm::Mutable)
            }),
            AssignTarget::Member(_) => None,
        };
        let saved = self.self_assign;
        self.self_assign = refilled.map(|b| b.uid);
        self.expr(value, Demand::Move);
        self.self_assign = saved;
        match target {
            AssignTarget::Name(name) => {
                let Some(b) = self.cx.m.assigned(value) else {
                    return;
                };
                self.check_store(s.pos, &b, *name);
                let places = vec![Place::local(b.uid)];
                self.check_change(s.pos, &places, "reassign", self.syms.str(b.name), None);
                self.mark_mutated(b.uid);
                self.record(s.id, &b, Access::Write);
                self.facts.drops_old.insert(s.id);
                // Replacing an old resource closes it under the fault policy. Only a
                // source exit while evaluating the RHS can still propagate its scope close.
                self.close_completions.insert((value.id, b.uid));
            }
            AssignTarget::Member(t) => {
                if let Some((info, _)) = self.place(t) {
                    self.mutate(t.pos, &info, "change");
                } else {
                    self.error(t.pos, "an assignment target must be a variable or a field path of one, like `p.x` or `rows[i].x`; `get(..)` and other calls return read-only views, so index the collection or bind the part with var first");
                }
            }
        }
    }

    /// Whole-binding reassignment needs a `var`.
    pub(super) fn check_store(&mut self, pos: Pos, b: &BindingRef, name: Name) {
        let Some(m) = self.meta.get(&b.uid) else {
            return;
        };
        match m.perm {
            // An escaping closure's captures are reported once by `lambda`.
            Perm::Mutable | Perm::ClosureOwned => {}
            // A scalar borrow is a name for its place: assigning writes through.
            Perm::MutBorrowed if m.class == Class::Copy => {}
            Perm::Immutable if m.parameter.is_some() => self.error(
                pos,
                format!("cannot assign to parameter `{name_t}`: it is not declared var; write `var {name_t}: <Type>` in the signature and `var` at every call", name_t = self.syms.str(name)),
            ),
            Perm::MutBorrowed => self.error(
                pos,
                format!("cannot reassign `{name_t}`: it is a mutable borrow of another value; assign to its fields, or clone with `{name_t}.{CLONE}()`", name_t = self.syms.str(name)),
            ),
            Perm::Immutable | Perm::Borrowed => self.error(
                pos,
                format!("cannot assign to `{name_t}`: it is not a var; declare it `var {name_t} = ...`", name_t = self.syms.str(name)),
            ),
        }
    }
}
