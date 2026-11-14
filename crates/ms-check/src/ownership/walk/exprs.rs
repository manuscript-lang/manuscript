//! Expressions: how each use of a value is classified and moved.

use super::*;

impl Walker<'_> {
    // --------------------------------------------------- expressions

    /// Origins of an expression that reads part of a value in place: a
    /// projection or a native accessor on a place.
    pub(super) fn projection_origins(&mut self, e: &Expr) -> Option<Vec<Place>> {
        if self.is_place(e) {
            if matches!(e.kind, ExprKind::Name(_)) {
                return None;
            }
            // Resolve without evaluating index expressions twice.
            return self.pure_places(e);
        }
        self.pure_origins(e)
    }

    /// Whether `e` is the last use of a whole owned (not parameter or borrowed) local that holds more than plain words.
    pub(super) fn owned_local_at_last_use(&self, e: &Expr) -> bool {
        if !matches!(e.kind, ExprKind::Name(_)) || self.class_of(e) == Class::Copy {
            return false;
        }
        let Resolution::Local(b) = self.cx.m.resolution(e) else {
            return false;
        };
        self.is_last(e.id, &b)
            && self.meta.get(&b.uid).is_some_and(|m| {
                !matches!(m.perm, Perm::Borrowed | Perm::MutBorrowed)
                    && m.role != Role::Parameter
                    && m.role != Role::SelfValue
            })
    }

    /// The places a conditional's value is a reference into, when every arm yields one.
    pub(super) fn arm_origins(&self, arms: &[Arm]) -> Option<Vec<Place>> {
        let mut out: Vec<Place> = Vec::new();
        for arm in arms {
            let v = arm.value.as_ref()?;
            // An owned view joined with plain references would leak or dangle.
            if self.is_view(v) {
                return None;
            }
            let places = if self.is_place(v) {
                self.pure_places(v)?
            } else {
                self.pure_origins(v)?
            };
            for p in places {
                // A payload of this match is not declared yet: it may own its part, which
                // ends with the arm.
                self.meta.get(&p.root)?;
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        }
        Some(out)
    }

    /// The places a call result is a reference into, without evaluating it: the places of the
    /// arguments a borrow-returning callee returns a part of, or the container of a native read that is
    /// borrowed in place. `None` when the result owns, including when a source is a temporary.
    pub(super) fn pure_origins(&self, e: &Expr) -> Option<Vec<Place>> {
        if self.class_of(e) == Class::Copy {
            return None;
        }
        if let ExprKind::Match { arms, .. } = &e.kind {
            return self.arm_origins(arms);
        }
        // `try f(a)` yields the payload of what `f` returns_borrow: a reference into the same places.
        if let ExprKind::Unary {
            op: UnaryOp::Try,
            operand,
        } = &e.kind
        {
            // A function that borrows only its error leaves the `ok` payload an owned value.
            if matches!(operand.kind, ExprKind::Call { .. }) {
                let cases = result_borrow(self.cx.m, operand, self.cx.summaries).borrowed_cases;
                if cases != 0 && cases & BORROWED_OK == 0 {
                    return None;
                }
            }
            // `try r` at the last use of an owned local takes the payload out of `r`.
            if self.owned_local_at_last_use(operand) {
                return None;
            }
            return if self.is_place(operand) {
                self.pure_places(operand)
            } else {
                self.pure_origins(operand)
            };
        }
        let ExprKind::Call { .. } = &e.kind else {
            return None;
        };
        let operands = match self.native_borrow_receiver(e) {
            Some(recv) => vec![recv],
            None => {
                let ret_borrow = result_borrow(self.cx.m, e, self.cx.summaries);
                if !ret_borrow.returns_borrow {
                    return None;
                }
                self.borrow_operands(e, &ret_borrow)?
            }
        };
        if operands.is_empty() {
            return None;
        }
        let mut out = Vec::new();
        for operand in operands {
            let places = if self.is_place(operand) {
                self.pure_places(operand)?
            } else {
                self.pure_origins(operand)?
            };
            for p in places {
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        }
        Some(out)
    }

    /// Whether `e` starts a promise whose entry function is written here: a call of a source function
    /// or method that returns a `Promise` and is given a lambda. The promise reads the lambda's
    /// captures in place until it is dropped, so they must outlive it and stay unchanged (the
    /// declaration is the result type, not the callee's name).
    pub(super) fn entry_call(&self, e: &Expr) -> bool {
        let ExprKind::Call { args, .. } = &e.kind else {
            return false;
        };
        if !args
            .iter()
            .any(|a| matches!(a.value.kind, ExprKind::Lambda(_)))
        {
            return false;
        }
        if !self
            .cx
            .m
            .ty(e)
            .is_source_type(self.syms, PROMISE_MODULE, "Promise")
        {
            return false;
        }
        match self.cx.m.resolution(e) {
            Resolution::Function(s) => s.native == Native::Source,
            Resolution::Method(m) => m.native == Native::Source,
            _ => false,
        }
    }

    /// The promise-starting calls a lambda argument of `e` returns, when `e` itself yields promises
    /// (`xs.map(fn x: promise(fn: f(x)))`): the result holds them, so it keeps their borrows.
    pub(super) fn lambda_promises<'e>(&self, e: &'e Expr) -> Vec<&'e Expr> {
        let ExprKind::Call { args, .. } = &e.kind else {
            return Vec::new();
        };
        if !ty_holds_promise(self.syms, &self.cx.m.ty(e)) {
            return Vec::new();
        }
        args.iter()
            .filter_map(|a| match &a.value.kind {
                ExprKind::Lambda(l) => Some(l),
                _ => None,
            })
            .flat_map(|l| l.body.iter())
            .filter_map(|s| match &s.kind {
                StmtKind::Return(Some(r)) if self.entry_call(r) => Some(r),
                _ => None,
            })
            .collect()
    }

    pub(super) fn holds_lambda_promises(&self, e: &Expr) -> bool {
        !self.lambda_promises(e).is_empty()
    }

    /// The captured bindings of the lambda arguments of promise-starting call `e`, or of the
    /// promises its lambda arguments start.
    pub(super) fn entry_captures(&self, e: &Expr) -> Vec<BindingRef> {
        let ExprKind::Call { args, .. } = &e.kind else {
            return Vec::new();
        };
        if !self.entry_call(e) {
            // Bindings made inside the outer lambda (its parameters) are not the caller's to hold.
            return self
                .lambda_promises(e)
                .into_iter()
                .flat_map(|p| self.entry_captures(p))
                .filter(|b| {
                    args.iter()
                        .any(|a| self.cx.m.captures(&a.value).iter().any(|o| o.uid == b.uid))
                })
                .collect();
        }
        args.iter()
            .filter(|a| matches!(a.value.kind, ExprKind::Lambda(_)))
            .flat_map(|a| self.cx.m.captures(&a.value))
            .collect()
    }

    /// The places a promise-starting call `e` reads through its entry function.
    pub(super) fn entry_places(&self, e: &Expr) -> Vec<Place> {
        let mut out = Vec::new();
        for b in self.entry_captures(e) {
            // A resource is moved into the promise, which owns and closes it.
            if self.cx.classes.class(self.syms, &b.ty) == Class::Resource {
                continue;
            }
            // The promise reads the binding where it sits, so the binding's own place counts as
            // well as the places it borrows (`body := bodies[k]` ends with the loop body).
            let own = Place::local(b.uid);
            let places = self.with_held(self.resolve(&own));
            for p in std::iter::once(own).chain(places) {
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        }
        out
    }

    /// A promise started in a `return` outlives the function, so its lambda is an escaping closure: it
    /// owns what it captures and the function moves those bindings (the caller passes `.clone()` to
    /// keep a value), as for any other returned closure.
    pub(super) fn returned_promises_own_captures(&mut self, e: &Expr) {
        let mut parts = Vec::new();
        collect_parts(
            e,
            &|c| matches!(self.cx.m.resolution(c), Resolution::Constructor { .. }),
            &mut parts,
        );
        let lambdas: Vec<NodeId> = parts
            .into_iter()
            .filter(|p| self.entry_call(p))
            .filter_map(|p| match &p.kind {
                ExprKind::Call { args, .. } => Some(args),
                _ => None,
            })
            .flatten()
            .filter(|a| matches!(a.value.kind, ExprKind::Lambda(_)))
            .map(|a| a.value.id)
            .collect();
        self.escaped.extend(lambdas);
    }

    /// The names a returned promise would still read after the function ends: the captures of a
    /// promise started in the `return`, or the borrows of a local promise returned by name.
    pub(super) fn returned_promise_reads(&self, e: &Expr) -> Vec<Name> {
        // A promise returned inside a larger value (`Server(running: p)`, `[promise(..)]`) still
        // reads what it captured, so look at every part of the returned expression.
        let mut parts = Vec::new();
        collect_parts(
            e,
            &|c| matches!(self.cx.m.resolution(c), Resolution::Constructor { .. }),
            &mut parts,
        );
        let mut out: Vec<Name> = Vec::new();
        for part in parts {
            if self.entry_call(part) {
                // Its lambda owns its captures (`returned_promises_own_captures`).
                continue;
            } else if let Resolution::Local(b) = self.cx.m.resolution(part) {
                out.extend(
                    self.active
                        .iter()
                        .filter(|a| a.holder == b.uid && a.why == PROMISE_WHY)
                        .flat_map(|a| a.origins.iter().map(|(p, _)| p.root))
                        // A `Copy` capture is taken by value, so nothing is read after the call.
                        .filter(|uid| self.meta.get(uid).is_none_or(|m| m.class == Class::Move))
                        .map(|uid| self.name_of(uid)),
                );
            }
        }
        out.dedup();
        out
    }

    /// The resolved places of a place chain without evaluating it.
    pub(super) fn pure_places(&self, e: &Expr) -> Option<Vec<Place>> {
        match &e.kind {
            ExprKind::Name(_) => {
                let Resolution::Local(b) = self.cx.m.resolution(e) else {
                    return None;
                };
                Some(self.resolve(&Place::local(b.uid)))
            }
            ExprKind::Member { left, name } => {
                let lefts = self.pure_places(left)?;
                let out: Vec<Place> = lefts.iter().map(|p| p.then(Step::Field(*name))).collect();
                Some(out)
            }
            ExprKind::Index { left, index } => {
                let step = self.element_step(left, index);
                Some(
                    self.pure_places(left)?
                        .iter()
                        .map(|p| p.then(step))
                        .collect(),
                )
            }
            ExprKind::Apply {
                left,
                value: Some(v),
                ..
            } => {
                let step = self.element_step(left, v);
                Some(
                    self.pure_places(left)?
                        .iter()
                        .map(|p| p.then(step))
                        .collect(),
                )
            }
            _ => None,
        }
    }

    pub(super) fn expr_text(&self, e: &Expr) -> String {
        match &e.kind {
            ExprKind::Name(n) => self.syms.str(n).to_string(),
            ExprKind::Member { left, name } => {
                format!("{}.{}", self.expr_text(left), self.syms.str(name))
            }
            ExprKind::Index { left, .. }
            | ExprKind::Apply {
                left,
                value: Some(_),
                ..
            } => {
                format!("{}[..]", self.expr_text(left))
            }
            ExprKind::Call { callee, .. } => format!("{}(..)", self.expr_text(callee)),
            _ => "this value".to_string(),
        }
    }

    pub(super) fn expr(&mut self, e: &Expr, d: Demand) {
        if d == Demand::Move
            && let Some(src) = &self.cx.m.info(e).interface_source
            && self.cx.classes.class(self.syms, src) == Class::Resource
            && !declares_close(self.syms, &self.cx.m.ty(e))
        {
            // An interface value is never closed for its owner, so owning a resource through one
            // drops its close, unless the interface hands the duty on with a `close` operation.
            let text = self.expr_text(e);
            let target = self.cx.m.ty(e);
            self.error(
                e.pos,
                format!("`{text}` is the resource `{src_t}`, and the `{target_t}` it would become never closes it; keep it as a `{src_t}` so its owner closes it, or pass it where `{target_t}` is only read", src_t = src.display(self.syms), target_t = target.display(self.syms)),
            );
        }
        if let Some(src) = self.cx.m.info(e).interface_source.clone() {
            self.adapter_copies(e, &src);
        }
        match &e.kind {
            ExprKind::Number(_) | ExprKind::Bool(_) | ExprKind::Unit => {}
            ExprKind::Probe(_) => self.error(
                e.pos,
                "`?` after an index is only written as `if var name = place[key]?`, where it borrows the entry in place",
            ),
            ExprKind::Text(parts) => {
                let interps: Vec<&Expr> = parts
                    .iter()
                    .filter_map(|p| match p {
                        TextPart::Interp(i) => Some(i),
                        _ => None,
                    })
                    .collect();
                self.parts_overlap(e.pos, "this text", &interps);
                for i in interps {
                    self.expr(i, Demand::Read);
                }
            }
            ExprKind::Name(_) => match self.cx.m.resolution(e) {
                Resolution::Local(b) => self.use_local(e, &b, d),
                Resolution::Function(sym) if !self.callees.contains(&e.id) => {
                    if let Some(decl) = sym.decl.clone() {
                        let func = crate::syntax::FuncRef::of_decl(decl);
                        self.function_value_copies(e, sym.module, &func);
                    }
                }
                _ => {}
            },
            ExprKind::Member { .. } | ExprKind::Index { .. } | ExprKind::Apply { .. } => {
                if let (ExprKind::Member { .. }, Resolution::Method(m)) =
                    (&e.kind, self.cx.m.resolution(e))
                    && let Some(func) = m.decl.clone()
                {
                    // A method used as a value; calls take their receiver apart instead.
                    self.function_value_copies(e, m.module, &func);
                }
                // A generic function used as a value with its type arguments (`keep[T]`).
                if let ExprKind::Apply { .. } = &e.kind
                    && !self.callees.contains(&e.id)
                    && let Resolution::Function(sym) = self.cx.m.resolution(e)
                    && let Some(decl) = sym.decl.clone()
                {
                    let func = crate::syntax::FuncRef::of_decl(decl);
                    self.function_value_copies(e, sym.module, &func);
                }
                self.projection(e, d)
            }
            ExprKind::List(items) => {
                let parts: Vec<&Expr> = items.iter().collect();
                self.parts_overlap(e.pos, "this list", &parts);
                items.iter().for_each(|i| self.expr(i, Demand::Move))
            }
            ExprKind::Map(entries) => {
                let parts: Vec<&Expr> = entries.iter().flat_map(|en| [&en.key, &en.value]).collect();
                self.parts_overlap(e.pos, "this map", &parts);
                for entry in entries {
                    self.expr(&entry.key, Demand::Move);
                    self.expr(&entry.value, Demand::Move);
                }
            }
            ExprKind::Unary { op, operand } => {
                if *op == UnaryOp::Try {
                    self.try_return(e, operand);
                }
                // `try` hands its payload on with the position's demand; a copied payload only
                // reads the result it comes out of.
                // A function that borrows only its error leaves the payload an owned value the
                // `try` takes out of the temporary result; the borrowed error is relayed.
                let owns_ok = matches!(operand.kind, ExprKind::Call { .. }) && {
                    let cases = result_borrow(self.cx.m, operand, self.cx.summaries)
                        .borrowed_cases;
                    cases != 0 && cases & BORROWED_OK == 0
                };
                let inner = if *op == UnaryOp::Try && self.class_of(e) != Class::Copy && !owns_ok {
                    d
                } else {
                    Demand::Read
                };
                self.expr(operand, inner);
            }
            ExprKind::Binary { left, right, op } => {
                self.parts_overlap(e.pos, &format!("`{}`", op.as_str()), &[left, right]);
                self.expr(left, Demand::Read);
                self.expr(right, Demand::Read);
            }
            ExprKind::Lambda(l) => {
                let escaping = d == Demand::Move || self.escaped.contains(&e.id);
                self.lambda(e, l, escaping);
            }
            ExprKind::Call { callee, args } => self.call(e, callee, args, d),
            ExprKind::Match { scrutinee, arms } => self.match_expr(e, scrutinee, arms, d, false),
        }
        self.temporary(e, d);
    }

    /// An owned value nobody consumed is dropped at the end of the statement.
    pub(super) fn temporary(&mut self, e: &Expr, d: Demand) {
        if d == Demand::Move || self.is_place(e) || matches!(e.kind, ExprKind::Name(_)) {
            return;
        }
        if matches!(
            e.kind,
            ExprKind::Call { .. }
                | ExprKind::List(_)
                | ExprKind::Map(_)
                | ExprKind::Match { .. }
                | ExprKind::Lambda(_)
                | ExprKind::Binary { .. }
        ) && self.class_of(e) != Class::Copy
        {
            self.facts.temporaries.insert(e.id);
        }
    }

    pub(super) fn use_local(&mut self, e: &Expr, b: &BindingRef, d: Demand) {
        let Some(class) = self.meta.get(&b.uid).map(|m| m.class) else {
            return;
        };
        let place = Place::local(b.uid);
        let resolved = self.resolve(&place);
        if d != Demand::Move || class == Class::Copy {
            self.check_read(e.pos, &resolved, self.syms.str(b.name), b.uid);
            let access = if d == Demand::Move {
                Access::Copy
            } else {
                Access::Borrow
            };
            self.record(e.id, b, access);
            return;
        }
        self.move_out(e, b, &resolved);
    }

    /// Moves a whole binding out: it must own its value and never use it again.
    pub(super) fn move_out(&mut self, e: &Expr, b: &BindingRef, resolved: &[Place]) {
        let (perm, role, parameter, lambda, receiver) = {
            let m = &self.meta[&b.uid];
            (m.perm, m.role, m.parameter, m.lambda, m.is_receiver)
        };
        let name = b.name;
        // A `var` parameter is the caller's value; it may move only into the right side of an
        // assignment to itself, which refills it (`exchange = wrap(exchange)`).
        let var_param =
            parameter.is_some() && perm == Perm::Mutable && self.self_assign != Some(b.uid);
        if role == Role::LambdaParameter
            && self.cx.classes.class(self.syms, &b.ty) == Class::Resource
        {
            // A function value is called with its arguments borrowed, so taking one would copy it,
            // and the caller still closes the original.
            self.error(
                e.pos,
                format!("cannot move `{name_t}` out: a function value only borrows its arguments, and the resource `{}` stays with its caller, which closes it; use `{name_t}` in place here", b.ty.display(self.syms), name_t = self.syms.str(name)),
            );
            self.record(e.id, b, Access::Move);
            return;
        }
        if role == Role::LambdaParameter {
            // The borrowed argument is copied: in generic code its type must be `Clonable`.
            let t = b.ty.clone();
            self.require_clonable(
                e,
                &t,
                &format!(
                    "this function value keeps `{name_t}`, which it only borrows, so it",
                    name_t = self.syms.str(name)
                ),
            );
        }
        if self.captured.iter().any(|c| c.contains(&b.uid)) && perm != Perm::ClosureOwned {
            if b.ty.kind == Kind::Function {
                self.error(
                    e.pos,
                    format!("this closure would move the function `{name_t}` out of the variable it captured, but a closure can run more than once; functions cannot be cloned, so call `{name_t}` here or take it as a parameter of the closure", name_t = self.syms.str(name)),
                );
            } else if self.cx.classes.class(self.syms, &b.ty) == Class::Resource {
                self.error(
                    e.pos,
                    format!("this closure would move `{name_t}` out of the variable it captured, but a closure can run more than once, and a resource cannot be cloned; use `{name_t}` in place inside the closure", name_t = self.syms.str(name)),
                );
            } else {
                self.error(
                    e.pos,
                    format!("this closure would move `{name_t}` out of the variable it captured, but a closure can run more than once; return `{name_t}.{CLONE}()` instead", name_t = self.syms.str(name)),
                );
            }
            self.record(e.id, b, Access::Move);
            return;
        }
        if matches!(
            perm,
            Perm::Borrowed | Perm::MutBorrowed | Perm::ClosureOwned
        ) && self.view_move != Some(e.id)
        {
            // Moving a part out of a parameter's match or loop makes that scrutinee consume it;
            // the next pass of the fixpoint sees the parts as owned.
            if let Some(scrutinee) = self.meta[&b.uid].deferred {
                self.escaped.insert(scrutinee);
            }
            if self.cx.classes.class(self.syms, &b.ty) == Class::Resource {
                self.error(
                    e.pos,
                    format!("cannot move `{name_t}` out: it is borrowed, not owned ({}), and its owner closes it; a resource cannot be cloned, so use `{name_t}` in place", role_text(role, perm), name_t = self.syms.str(name)),
                );
            } else if let Some(why) = clone_blocker(&b.ty) {
                self.error(
                    e.pos,
                    format!("cannot move `{name_t}` out: it is borrowed, not owned ({}); {why}, so use `{name_t}` in place", role_text(role, perm), name_t = self.syms.str(name)),
                );
            } else {
                self.error(
                    e.pos,
                    format!("cannot move `{name_t}` out: it is borrowed, not owned ({}); borrow it in place or restructure to avoid the copy, and use `{name_t}.{CLONE}()` only if a second owner is needed", role_text(role, perm), name_t = self.syms.str(name)),
                );
            }
            self.record(e.id, b, Access::Move);
            return;
        } else if (var_param || (receiver && perm == Perm::Mutable))
            && self.cx.classes.class(self.syms, &b.ty) == Class::Resource
        {
            self.error(
                e.pos,
                format!("cannot move `{name_t}` out of the function: the caller keeps ownership of a var parameter and closes it; a resource cannot be cloned, so change it in place", name_t = self.syms.str(name)),
            );
        } else if var_param || (receiver && perm == Perm::Mutable) {
            self.error(
                e.pos,
                format!("cannot move `{name_t}` out of the function: the caller keeps ownership of a var parameter; return `{name_t}.{CLONE}()` or change the value in place", name_t = self.syms.str(name)),
            );
        } else if !self.is_last(e.id, b) {
            let later = self
                .next_use(e.id, b)
                .map(|n| self.later_at(e.id, n))
                .unwrap_or_default()
                + &self.consumed_note();
            if b.ty.kind == Kind::Function {
                self.error(
                    e.pos,
                    format!("`{name_t}` is moved here but used again{later}; a function value has one owner and cannot be cloned, so move it only at its last use or declare a named `fn`, which can be passed as often as needed", name_t = self.syms.str(name)),
                );
            } else if self.cx.classes.class(self.syms, &b.ty) == Class::Resource {
                self.error(
                    e.pos,
                    format!("`{name_t}` is moved here but used again{later}; a resource has one owner and cannot be cloned, so move it only at its last use, or pass it where it is only read", name_t = self.syms.str(name)),
                );
            } else if let Some(why) = clone_blocker(&b.ty) {
                self.error(
                    e.pos,
                    format!("`{name_t}` is moved here but used again{later}; {why}, so move it only at its last use", name_t = self.syms.str(name)),
                );
            } else {
                self.error(
                    e.pos,
                    format!("`{name_t}` is moved here but used again{later}; a value has one owner, so move it only at its last use, or pass `{name_t}.{CLONE}()` if the original is still needed", name_t = self.syms.str(name)),
                );
            }
        }
        self.check_change(e.pos, resolved, "move", self.syms.str(name), Some(b.uid));
        self.mark_mutated(b.uid);
        self.record(e.id, b, Access::Move);
        if parameter.is_some() || receiver {
            self.consumed.insert(b.uid);
            self.consumed_at.entry(b.uid).or_insert(e.pos);
        }
        if let Some(l) = lambda {
            self.escaped.insert(l);
        }
    }

    pub(super) fn projection(&mut self, e: &Expr, d: Demand) {
        let escaping = d == Demand::Move || self.escaped.contains(&e.id);
        if let Some(recv) = self.changing_method_value(e) {
            self.changing_method_use(e, recv, escaping);
            return;
        }
        if let Some(recv) = self.method_value(e) {
            self.method_value_use(e, recv, escaping);
            return;
        }
        if !self.is_place(e) {
            // A part of a computed value. Copying a `Copy` part leaves the whole where it is.
            let take = d == Demand::Move
                && self.class_of(e) != Class::Copy
                && self.cx.m.ty(e).kind != Kind::Function;
            if take
                && self.class_of(e) == Class::Resource
                && !matches!(
                    self.cx.m.resolution(e),
                    Resolution::Constructor { .. }
                        | Resolution::Function(_)
                        | Resolution::Constant(_)
                )
            {
                // Only a whole value moves: the resource would be copied out of a value that
                // still closes it.
                let text = self.expr_text(e);
                self.error(
                    e.pos,
                    format!("cannot move `{text}` out of a computed value: a resource has one owner, and the value it comes from still closes it; bind the whole value first, then use the part in place"),
                );
            }
            match &e.kind {
                ExprKind::Member { left, .. } => {
                    self.expr(left, if take { Demand::Move } else { Demand::Read })
                }
                ExprKind::Index { left, index } => {
                    self.parts_overlap(e.pos, "this index", &[left, index]);
                    self.expr(left, if take { Demand::Move } else { Demand::Read });
                    self.expr(index, Demand::Read);
                }
                ExprKind::Apply { left, value, .. } => {
                    if let Some(v) = value {
                        self.parts_overlap(e.pos, "this index", &[left, v]);
                    }
                    self.expr(left, Demand::Read);
                    if let Some(v) = value {
                        self.expr(v, Demand::Read);
                    }
                }
                _ => {}
            }
            return;
        }
        let Some((info, _)) = self.place(e) else {
            return;
        };
        let class = self.class_of(e);
        if d == Demand::Move && class != Class::Copy && self.partial_move(e, &info, class) {
            return;
        }
        if d == Demand::Move && class == Class::Resource {
            self.error(
                e.pos,
                format!(
                    "cannot move the resource `{0}` out of `{1}`: a resource cannot be cloned, and it leaves `{1}` only when `{1}` is a `let` or a parameter and no type on the path has a `close` of its own; use `{0}` in place, or move the whole `{1}`",
                    info.text, self.syms.str(info.root.name)
                ),
            );
        } else if d == Demand::Move && class != Class::Copy {
            let message = if self.syms.str(info.root.name).starts_with('?') {
                // The payload of an optional chain `a?.b`, which has no written name.
                format!(
                    "an optional chain `?.` cannot move a field out of the optional; take a clone by ending the access with `.{CLONE}()`"
                )
            } else {
                format!(
                    "cannot move `{0}` out of `{1}`: only a whole variable can move; borrow it in place or restructure to avoid the copy, and use `{0}.{CLONE}()` only if a second owner is needed",
                    info.text,
                    self.syms.str(info.root.name)
                )
            };
            // A member's position is its name, so the copy goes right after it.
            self.error(e.pos, message);
        }
        self.read_place(e.pos, &info);
    }

    /// A field of an owned local or parameter moves out at its last use (`return b.items`,
    /// `f(b.items)`): the place is dead until it is stored again, and the rest of the value is
    /// still the binding's. Returns whether the move is accepted; if not, the caller reports
    /// that only a whole variable can move.
    pub(super) fn partial_move(&mut self, e: &Expr, info: &PlaceInfo, class: Class) -> bool {
        let root = info.root.clone();
        let Some(meta) = self.meta.get(&root.uid) else {
            return false;
        };
        let owner = matches!(meta.perm, Perm::Immutable | Perm::Mutable)
            && !meta.is_receiver
            && !matches!(meta.role, Role::Fixture)
            && !(meta.parameter.is_some() && meta.perm == Perm::Mutable)
            && meta.lambda.is_none();
        let own_place = matches!(info.resolved.as_slice(), [only] if only.root == root.uid);
        if !owner
            || !own_place
            || class == Class::Copy
            || info.through_ref.is_some()
            || self.captured.iter().any(|c| c.contains(&root.uid))
        {
            return false;
        }
        // Only fields: an element of a collection stays where it is.
        let Some(path) = self.field_path(e) else {
            return false;
        };
        // A resource moves without a copy: only a `let` or a parameter, whose cleanup lowering
        // splits around the hole, and never a type parameter or a part of a closure capture.
        let resource = class == Class::Resource;
        if resource
            && (!matches!(meta.role, Role::Let | Role::Parameter)
                || meta.perm != Perm::Immutable
                || self.cx.m.ty(e).kind == Kind::Variable)
        {
            return false;
        }
        // A type that closes itself would close a type with a hole in it.
        let mut at = e;
        while let ExprKind::Member { left, .. } = &at.kind {
            let holder = self.cx.m.ty(left);
            if self.cx.classes.closes_itself(&holder) {
                return false;
            }
            at = left;
        }
        let last = self
            .cx
            .live
            .places
            .get(&(e.id, root.uid))
            .is_none_or(|u| u.last);
        if !last {
            let later = self
                .cx
                .live
                .places
                .get(&(e.id, root.uid))
                .and_then(|u| u.next)
                .map(|n| self.later_at(e.id, n))
                .unwrap_or_default();
            self.error(
                e.pos,
                format!("`{0}` is moved here but used again{later}; a value has one owner, so move it only at its last use, or use `{0}.{CLONE}()` if the original is still needed", info.text),
            );
            return true;
        }
        self.check_change(e.pos, &info.resolved, "move", &info.text, Some(root.uid));
        self.mark_mutated(root.uid);
        self.record(info.root_node, &root, Access::Borrow);
        if meta_is_parameter(self, root.uid) {
            self.consumed.insert(root.uid);
            self.consumed_at.entry(root.uid).or_insert(e.pos);
        }
        if resource {
            let at = self.facts.resource_moves.entry(root.uid).or_default();
            // The release at scope end tests one flag per moved place, so a place and a part of
            // it cannot both be moved.
            let clash = at.values().find(|o| {
                let n = o.len().min(path.len());
                o[..n] == path[..n] && o.len() != path.len()
            });
            if clash.is_some() {
                self.error(
                    e.pos,
                    format!(
                        "`{0}` and a part of it are both moved out of `{1}`: move the same field everywhere, or move the whole `{1}`",
                        info.text, self.syms.str(root.name)
                    ),
                );
                return true;
            }
            at.insert(e.id, path);
        }
        self.facts
            .partial_moves
            .insert(e.id, info.resolved[0].clone());
        true
    }
}
