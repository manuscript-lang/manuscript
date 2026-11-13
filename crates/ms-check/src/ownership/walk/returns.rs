//! Return analysis: what a returned value borrows, wraps or moves out of its callee.

use super::*;

impl Walker<'_> {
    /// Evaluates a value handed back to the caller.
    pub(super) fn returned(&mut self, e: &Expr) {
        if !self.captured.is_empty() {
            // A lambda never returns_borrow: an escaping closure owns its captures.
            self.expr(e, Demand::Move);
            return;
        }
        self.returned_promises_own_captures(e);
        let reads = self.returned_promise_reads(e);
        if !reads.is_empty() {
            let names: Vec<&str> = reads.iter().map(|n| self.syms.str(n)).collect();
            self.error(
                e.pos,
                format!(
                    "this promise reads `{}`, which ends with this function; wait for the promise before returning, or start it from values that outlive the call",
                    names.join("`, `")
                ),
            );
        }
        // Each branch of a conditional or match expression is a returned value of its own.
        if let ExprKind::Match { scrutinee, arms } = &e.kind
            && arms.iter().all(|a| a.value.is_some())
        {
            self.match_expr(e, scrutinee, arms, Demand::Move, true);
            return;
        }
        // A borrowed value converted to an interface on the way out (`return cause` as `Error`,
        // `error(cause)` as `Int!`, a widened borrow-returning call), a view returner's result or a local
        // holding a view: the result is an owned view whose payload stays in the arguments.
        if !self.implements_contract() && self.view_return_source(e) {
            return;
        }
        // A resource is never borrowed: returning one hands it to the caller, which closes it.
        let wrapped = self.wrapped_borrow(e).is_some();
        if self.class_of(e) == Class::Move
            && (self.returns_as_declared(e) || wrapped)
            && !self.implements_contract()
            && !self.moves_withdrawn_borrow(e)
        {
            // A function that borrows some cases of its `Result` returned whole (`return
            // expect_ok(actual)`): this function borrows the same cases from the same sources and
            // owns the others.
            if let Some(src) = self.borrow_source(e).filter(|s| s.cases != 0)
                && self.result_is_result()
            {
                self.borrowed_return.get_or_insert(e.pos);
                self.borrowed_cases |= src.cases;
                self.owned_cases |= 3 & !src.cases;
                self.borrow_receiver |= src.receiver;
                for p in src.params {
                    if !self.borrow_params.contains(&p) {
                        self.borrow_params.push(p);
                    }
                }
                self.borrow_path = Some(None);
                self.expr(e, Demand::Read);
                return;
            }
            if let Some(src) = self.borrow_source(e).filter(|s| s.cases == 0) {
                // A part of an argument comes back as a reference into it: nothing moves. A
                // wrapper around it (`x?`, `ok(x)`) adds no storage and stays a reference too.
                self.borrowed_return.get_or_insert(e.pos);
                if wrapped {
                    self.facts.view_wraps.insert(e.id);
                    self.wrap_returns.push((e.id, self.wrap_case(e)));
                    self.borrowed_cases |= self.wrap_case(e);
                    // A part that cannot be copied is moved out once the borrow is withdrawn
                    // (`moves_withdrawn_borrow`), which a caller's temporary source needs.
                    if let Some(inner) = self.wrapped_borrow(e)
                        && !self.cx.classes.clonable(self.syms, &self.cx.m.ty(inner))
                    {
                        self.borrow_not_clonable = true;
                    }
                    if self.result_case(e).is_some() {
                        self.ret_ctors.push(e.id);
                    }
                } else if self.cx.m.ty(e).is(Builtin::Result) && self.result_is_result() {
                    // A whole Result reference lends both payload cases. If cleanup adds an
                    // owned error path, only the overlapping cases need boundary normalization.
                    self.borrowed_cases |= BORROWED_OK | BORROWED_ERROR;
                    self.plain_borrowed = true;
                    self.plain_result_borrowed = true;
                    self.borrow_not_clonable |=
                        !self.cx.classes.clonable(self.syms, &self.cx.m.ty(e));
                } else if !self.list_get(e) && !self.map_get(e) {
                    // `xs.get(i)` beside a new value is withdrawn like a wrapper, and the
                    // element is copied out; any other reference has no owned form.
                    self.plain_borrowed = true;
                }
                self.borrow_receiver |= src.receiver;
                for p in src.params {
                    if !self.borrow_params.contains(&p) {
                        self.borrow_params.push(p);
                    }
                }
                self.borrow_path = Some(match (self.borrow_path.take(), src.path) {
                    (None, path) => path,
                    (Some(Some(a)), Some(b)) if a == b => Some(a),
                    _ => None,
                });
                self.expr(e, Demand::Read);
                return;
            }
            // A bare `none` owns nothing, so a borrow-returning function can hand it back beside its references.
            if self.cx.m.data.default_form(self.syms, e) != crate::syntax::DefaultForm::None {
                self.owned_return.get_or_insert(e.pos);
                self.owned_cases |= self.owned_case(e);
                if self.result_case(e).is_some() {
                    self.ret_ctors.push(e.id);
                }
            }
        }
        // A returned `Bytes` or `String` is owned, and a view only borrows its receiver.
        if let Some(local) = self.returned_bytes_view(e) {
            let kind = if self.cx.m.ty(e).is(Builtin::Bytes) {
                "Bytes"
            } else {
                "String"
            };
            self.error(
                e.pos,
                format!(
                    "cannot return a view of `{0}`: a returned `{kind}` is owned and a view only borrows `{0}`; copy it with `.{CLONE}()` after the view",
                    self.syms.str(local)
                ),
            );
            return;
        }
        // A reference converted on the way out (a borrow-returning call widened to another error type or
        // an interface) is read: the conversion builds the new value from it.
        let converted = self.cx.m.info(e).interface_source.is_some()
            && matches!(e.kind, ExprKind::Call { .. })
            && self.returns_borrow(e);
        self.expr(
            e,
            if converted {
                Demand::Read
            } else {
                Demand::Move
            },
        );
    }

    /// Whether a returned part is moved out instead of borrowed: an earlier round found this
    /// function returning a new value on another path and withdrew the borrow (`mixed_returns`), so
    /// the part would be copied out, and a value with one owner and no `clone` cannot be. Moving
    /// it moving_params the argument it came from, which the caller then hands over.
    pub(super) fn moves_withdrawn_borrow(&self, e: &Expr) -> bool {
        let key = (self.cx.c.module.file, self.cx.c.id());
        self.cx
            .summaries
            .get(&key)
            .is_some_and(|s| !s.result.returns_borrow)
            && !self.cx.classes.clonable(self.syms, &self.cx.m.ty(e))
    }

    /// The fields from a variable to a place written as a plain chain of them.
    pub(super) fn field_path(&self, e: &Expr) -> Option<Vec<Name>> {
        match &e.kind {
            ExprKind::Name(_) => Some(Vec::new()),
            ExprKind::Member { left, name } => {
                let mut f = self.field_path(left)?;
                f.push(*name);
                Some(f)
            }
            _ => None,
        }
    }

    /// Classifies `e` as a returned interface view when it is one, recording the sources and
    /// walking it; `false` when `e` is not a view (a plain reference or a new value).
    pub(super) fn view_return_source(&mut self, e: &Expr) -> bool {
        let via = self.view_source(e);
        let src = match via {
            Some(x) => self.borrow_source(x),
            None => self.borrow_source(e).filter(|s| s.view),
        };
        let Some(src) = src else {
            return false;
        };
        self.borrowed_return.get_or_insert(e.pos);
        self.view_return = true;
        self.borrow_receiver |= src.receiver;
        for p in src.params {
            if !self.borrow_params.contains(&p) {
                self.borrow_params.push(p);
            }
        }
        self.borrow_path = Some(None);
        // The payload of `ok(x)` / `error(x)` is read into the view, not consumed.
        if self.result_payload(e).is_some() {
            self.view_calls.insert(e.id);
        }
        // A local holding a view is moved out: the box it owns becomes the result. The same
        // when a returner hands the local back whole (`return relay(e)`): the box moves into the
        // call and comes back as the result instead of being copied.
        let moved = via.unwrap_or(e);
        let moved = self.result_payload(moved).unwrap_or(moved);
        if let Some(operand) = self.whole_borrowed_operand(moved) {
            // The call reads its argument; lowering moves the box in and keeps it as the result.
            self.facts.view_moves.insert(operand.id);
            self.expr(e, Demand::Read);
        } else if let ExprKind::Name(_) = &moved.kind
            && let Resolution::Local(b) = self.cx.m.resolution(moved)
            && self.view_locals.contains(&b.uid)
            && b.ty.kind == Kind::Contract
        {
            self.view_calls.remove(&e.id);
            self.facts.view_moves.insert(moved.id);
            self.view_move = Some(moved.id);
            self.expr(e, Demand::Move);
            self.view_move = None;
        } else {
            self.expr(e, Demand::Read);
        }
        true
    }

    /// The one operand a plain borrow-returning call `e` hands back whole (`relay(x)` for
    /// `relay(e: Error) Error: return e`), when it is a name of an interface view local at its
    /// last use: moving the local into the call lets the caller keep its box as the result.
    pub(super) fn whole_borrowed_operand<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        if !matches!(e.kind, ExprKind::Call { .. }) {
            return None;
        }
        let ret_borrow = result_borrow(self.cx.m, e, self.cx.summaries);
        if !ret_borrow.returns_borrow || ret_borrow.view {
            return None;
        }
        let operands = self.borrow_operands(e, &ret_borrow)?;
        let [operand] = operands.as_slice() else {
            return None;
        };
        let Some((_, fields)) = &ret_borrow.path else {
            return None;
        };
        let Resolution::Local(b) = self.cx.m.resolution(operand) else {
            return None;
        };
        (fields.is_empty()
            && matches!(operand.kind, ExprKind::Name(_))
            && self.view_locals.contains(&b.uid)
            && b.ty.kind == Kind::Contract
            && self.is_last(operand.id, &b))
        .then_some(*operand)
    }

    /// The expression a conversion to an interface reads, when `e` converts a `Move`-class
    /// value: `e` itself (`cause` as `Error`, a widened borrow-returning call, `cause` as `Error?`), or
    /// the payload of `ok(x)` / `error(x)`. `None` when nothing is converted or the source is a
    /// scalar, which the interface copies.
    pub(super) fn view_source<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let converted = |x: &Expr| {
            // A conversion to an interface with a `var fn` copies: a call through the view
            // could change leaves the view only borrows.
            let target = self.cx.m.ty(x);
            let iface = if target.is(Builtin::Result) {
                target.args.get(1).cloned()
            } else {
                Some(target)
            };
            if iface.is_none_or(|t| crate::types::contract_mutates(&t)) {
                return false;
            }
            self.cx
                .m
                .info(x)
                .interface_source
                .as_ref()
                .is_some_and(|src| self.cx.classes.class(self.syms, src) == Class::Move)
        };
        if converted(e) {
            return Some(e);
        }
        let x = self.result_payload(e)?;
        converted(x).then_some(x)
    }

    /// Whether `e` is an interface view or holds one: a conversion of a borrowed value, a view
    /// returner's call, or a local holding a view.
    pub(super) fn is_view(&self, e: &Expr) -> bool {
        self.view_source(e).is_some() || self.borrow_source(e).is_some_and(|s| s.view)
    }

    /// Whether this callable implements an interface method. A call through the interface
    /// cannot know which implementation runs, so every implementation owns its result.
    pub(super) fn implements_contract(&self) -> bool {
        let c = self.cx.c;
        if c.func.index.is_none() {
            return false;
        }
        let DeclKind::Impl(i) = &c.func.decl.0.decl.kind else {
            return false;
        };
        // A type's own methods are checked as an implementation of a synthesized interface;
        // the desugaring marks that impl synthetic.
        i.contract.is_some() && !c.func.decl.0.decl.synthetic
    }

    /// Whether the declared result type is an interface.
    pub(super) fn result_is_result(&self) -> bool {
        let c = self.cx.c;
        let result = match (c.func.method(), c.func.func()) {
            (Some(m), _) => m.func.result.id,
            (None, Some(f)) => f.result.id,
            (None, None) => return false,
        };
        self.cx
            .m
            .type_ref(result)
            .is_some_and(|t| t.is(Builtin::Result))
    }

    /// A scope close can return a fresh Error even when every written return borrows.
    /// An error type variable can instantiate Error; incompatible concrete errors fault.
    pub(super) fn implicit_close_return(&mut self) {
        if self.facts.implicit_closes.is_empty() {
            return;
        }
        let result = match (self.cx.c.func.method(), self.cx.c.func.func()) {
            (Some(m), _) => m.func.result.id,
            (None, Some(f)) => f.result.id,
            (None, None) => return,
        };
        if !self.cx.m.type_ref(result).is_some_and(|t| {
            t.is(Builtin::Result)
                && t.args
                    .get(1)
                    .is_some_and(|e| e.is(Builtin::Error) || e.kind == Kind::Variable)
        }) {
            return;
        }
        let mut handled = self.close_completions.clone();
        handled.extend(
            self.facts
                .uses
                .values()
                .filter(|u| u.access == Access::Move)
                .map(|u| (u.node, u.binding)),
        );
        // `implicit_closes` includes moved bindings for paths that retain them. Use the
        // existing lifetime proof to exclude only transfers or handled closes on every path.
        let retained = super::moved::conditional(self.cx.m, self.cx.c, &handled);
        let handled_bindings: HashSet<_> = handled.iter().map(|(_, uid)| *uid).collect();
        self.facts
            .handled_scope_closes
            .extend(self.facts.implicit_closes.iter().copied().filter(|uid| {
                handled_bindings.contains(uid)
                    && !retained.contains(uid)
                    && self.meta.get(uid).is_some_and(|m| !m.in_lambda)
            }));
        if !self.facts.implicit_closes.iter().any(|uid| {
            !self.facts.handled_scope_closes.contains(uid)
                && self
                    .meta
                    .get(uid)
                    .is_some_and(|m| !m.in_lambda && self.close_returns_error(&m.binding.ty))
        }) {
            return;
        }
        self.owned_cases |= BORROWED_ERROR;
        self.close_error_return = true;
    }

    /// Direct closes can return Error. A generated holder close returns Unit and faults on
    /// failed parts, so it contributes no owned Result.error path to this callable.
    pub(super) fn close_returns_error(&self, ty: &Ty) -> bool {
        if ty.kind == Kind::Variable {
            return true;
        }
        if ty.kind == Kind::Contract {
            return ty.def.as_ref().is_some_and(|d| {
                let s = substitution(ty);
                d.operations.borrow().iter().any(|op| {
                    op.name == n("close")
                        && is_close_result(self.syms, &sub(&op.ty, &s).result_ty())
                })
            });
        }
        if !self.cx.classes.closes_itself(ty) {
            return false;
        }
        let resource = |t: &Ty| self.cx.classes.class(self.syms, t) == Class::Resource;
        if ty.kind == Kind::Type && fields(ty).iter().any(|f| resource(&f.ty)) {
            return false;
        }
        if ty.kind == Kind::Alternative
            && ty.def.as_ref().is_some_and(|d| {
                let s = substitution(ty);
                d.cases
                    .borrow()
                    .iter()
                    .any(|c| c.fields.iter().any(|f| resource(&sub(&f.ty, &s))))
            })
        {
            return false;
        }
        let held = if ty.is(Builtin::List) || ty.is(Builtin::Optional) {
            ty.args.first()
        } else if ty.is(Builtin::Map) {
            ty.args.get(1)
        } else {
            None
        };
        !held.is_some_and(resource)
    }

    pub(super) fn result_is_interface(&self) -> bool {
        let c = self.cx.c;
        let result = match (c.func.method(), c.func.func()) {
            (Some(m), _) => m.func.result.id,
            (None, Some(f)) => f.result.id,
            (None, None) => return false,
        };
        self.cx
            .m
            .type_ref(result)
            .is_some_and(|t| t.kind == Kind::Contract)
    }

    /// Whether a returned expression has the declared result type itself: a value converted on
    /// the way out (`Door` returned as `Door?`, a type as an interface) is a new value.
    pub(super) fn returns_as_declared(&self, e: &Expr) -> bool {
        let c = self.cx.c;
        let result = match (c.func.method(), c.func.func()) {
            (Some(m), _) => m.func.result.id,
            (None, Some(f)) => f.result.id,
            (None, None) => return false,
        };
        let Some(declared) = self.cx.m.type_ref(result) else {
            return false;
        };
        self.cx.m.info(e).interface_source.is_none() && same(&self.cx.m.ty(e), &declared)
    }

    /// Reports a function that returns a reference on one path and an owned value on another:
    /// the caller could not tell whether to hold or drop the result.
    pub(super) fn mixed_returns(&mut self) {
        // A source-level whole-reference/new-value mix keeps its existing diagnostic.
        // Only the hidden close outcome requires adapting an otherwise borrowing Result.
        if self.plain_result_borrowed && self.close_error_return && self.owned_return.is_none() {
            self.plain_borrowed = false;
        }
        if self.view_return {
            // Every path of a view returner returns an owned value. A plain reference to an
            // interface value is handed on as a view that owns nothing; a wrapper of a part
            // becomes a new value of its own, as beside an owned path; any other plain
            // reference has no owned form.
            for (n, _) in std::mem::take(&mut self.wrap_returns) {
                self.facts.view_wraps.remove(&n);
            }
            if self.plain_borrowed && !self.result_is_interface() {
                let borrowed = self.borrowed_return.unwrap_or_default();
                self.error(
                    borrowed,
                    format!(
                        "this function returns an interface view of its arguments on another path but a reference here; return `.{CLONE}()` of the part, or convert it on every path"
                    ),
                );
            }
            return;
        }
        let Some(borrowed) = self.borrowed_return else {
            return;
        };
        if self.owned_return.is_none() && self.owned_cases == 0 {
            return;
        }
        // Forwarded mixed Results and implicit closes contribute owned cases without a
        // written owned return. Source positions locate diagnostics, not semantic outcomes.
        let owned = self
            .owned_return
            .unwrap_or_else(|| self.cx.c.func.decl.pos());
        // A wrapper of a part is a reference only when every path returns a borrow; beside a new value it
        // is built as a new value of its own (its payload copied), as before.
        if !self.plain_borrowed {
            // The borrowed cases of a `Result` stay references when no owned path builds the same
            // case: the caller drops only the cases the function owns.
            let mask = self.borrowed_cases & !self.owned_cases;
            if self.borrowed_cases & 4 == 0
                && !self.borrow_not_clonable
                && mask != 0
                && self.result_is_result()
            {
                self.borrowed_mask = mask;
                for &(node, case) in &self.wrap_returns {
                    if case & mask == 0 {
                        self.facts.view_wraps.remove(&node);
                    }
                }
                return;
            }
            self.borrowed_return = None;
            for (n, _) in std::mem::take(&mut self.wrap_returns) {
                self.facts.view_wraps.remove(&n);
            }
            return;
        }
        self.error(
            owned,
            format!(
                "this function returns a reference into its arguments at {}:{} but a new value here; return `.clone()` of the part there, or build a new value on every path",
                borrowed.line, borrowed.column
            ),
        );
    }

    /// The arguments a borrow-returning call returns a reference into: the receiver and the parameters
    /// `ret_borrow` names, as written. `None` when one of them is converted on the way in (wrapped
    /// into an `Optional`, widened to an interface or another error type): the callee then returns a borrow
    /// a temporary, and the result is a new value of the caller's.
    pub(super) fn borrow_operands<'e>(
        &self,
        e: &'e Expr,
        ret_borrow: &ResultBorrow,
    ) -> Option<Vec<&'e Expr>> {
        let ExprKind::Call { callee, args } = &e.kind else {
            return Some(Vec::new());
        };
        let mut out = Vec::new();
        let member = method_callee(self.syms, self.cx.m, callee);
        if ret_borrow.receiver
            && let (ExprKind::Member { left, .. }, Resolution::Method(_)) =
                (&member.kind, self.cx.m.resolution(e))
        {
            out.push(&**left);
        }
        let slots = self.cx.m.info(e).arguments.clone().unwrap_or_default();
        for (i, a) in args.iter().enumerate() {
            if slots
                .get(i)
                .is_some_and(|s| ret_borrow.params.contains(&s.name))
            {
                // A borrowed value converted to an interface on the way in is a view of it: what
                // the callee returns a borrow of the view is a reference into the value.
                if self.converted_argument(e, &a.value) && !self.converted_borrow(&a.value) {
                    return None;
                }
                out.push(&a.value);
            }
        }
        // A copied argument is never borrowed from, whatever an optimistic summary says.
        out.retain(|a| self.class_of(a) != Class::Copy);
        Some(out)
    }

    /// Whether `arg` is a `Move`-class reference converted to an interface on the way in
    /// (`relay(cause)` for `relay(e: Error)`): the converted temporary is a view of it.
    pub(super) fn converted_borrow(&self, arg: &Expr) -> bool {
        self.view_source(arg).is_some_and(|x| std::ptr::eq(x, arg))
            && self.borrow_source(arg).is_some()
    }

    /// Whether a borrowed operand of call `e` is a converted view temporary: the caller owns what
    /// the callee returns a borrow of it (the temporary itself when handed back whole, else a copy) and
    /// still holds the value it views.
    pub(super) fn returns_borrow_through_view(&self, e: &Expr, ret_borrow: &ResultBorrow) -> bool {
        self.borrow_operands(e, ret_borrow).is_some_and(|ops| {
            ops.iter()
                .any(|o| self.converted_borrow(o) || self.is_view(o))
        })
    }

    /// Whether argument `arg` of call `e` is converted to its parameter's type on the way in.
    /// An argument whose type does not unify with the parameter's is converted; so is one
    /// wrapped into an `Optional`.
    pub(super) fn converted_argument(&self, e: &Expr, arg: &Expr) -> bool {
        let Some(view) = self.cx.m.call(e) else {
            return true;
        };
        let Some(a) = view.arguments.iter().find(|a| a.expr.id == arg.id) else {
            return true;
        };
        // A widened error or interface value is recorded with its source type.
        if a.wrap_optional.is_some() || self.cx.m.info(arg).interface_source.is_some() {
            return true;
        }
        let (sig, variables): (Option<Ty>, Vec<Ty>) = match &view.target {
            Resolution::Function(s) | Resolution::Constant(s) => {
                (s.ty.borrow().clone(), s.variables.borrow().clone())
            }
            Resolution::Method(m) => (Some(m.ty.clone()), m.variables.clone()),
            _ => return true,
        };
        let Some(sig) = sig else {
            return true;
        };
        let Some(p) = sig.params.iter().find(|p| p.name == a.slot.name) else {
            return true;
        };
        let mut vars = variable_set(&variables);
        vars.extend(variable_set(&sig.args));
        let mut bound = Subst::default();
        !unify(&p.ty, &self.cx.m.ty(arg), &vars, &mut bound)
    }

    /// Whether `r` is an `Optional` or `Result`: a payload of unbounded type read out of one
    /// is the wrapper's one owner handing it over, since a copy would need `Clonable`.
    pub(super) fn wrapper_receiver(&self, r: &Expr) -> bool {
        let t = self.cx.m.ty(r);
        t.is(Builtin::Optional) || t.is(Builtin::Result)
    }

    /// The label of the parameter written at argument `i` of call `e`.
    pub(super) fn argument_label(&self, e: &Expr, i: usize) -> Option<Name> {
        self.cx.m.info(e).arguments.as_ref()?.get(i).map(|s| s.name)
    }

    /// The value `e` wraps without adding storage on its way to a binding or a return: `e`
    /// itself when it is wrapped into an `Optional` (`x` as `x?`), or the payload of `ok(x)` /
    /// `error(x)`. `None` when the value is converted (an interface, a widened error).
    pub(super) fn wrapped_borrow<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let info = self.cx.m.info(e);
        if info.interface_source.is_some() {
            return None;
        }
        if info.wrap_some.is_some() {
            return Some(e);
        }
        let inner = self.result_payload(e)?;
        let inner_info = self.cx.m.info(inner);
        (inner_info.interface_source.is_none()
            && inner_info.wrap_some.is_none()
            // `ok(x)` into a `T?` field builds a new `some(x)`; it does not lend `x`.
            && inner_info.optional_argument.is_none()
            && self.class_of(inner) != Class::Copy)
            .then_some(inner)
    }

    /// The case of a `Result` a returned wrapper lends: `ok(x)` or `error(x)`; 4 for any other
    /// wrapper (`x?`), which keeps the copy.
    pub(super) fn wrap_case(&self, e: &Expr) -> u8 {
        self.result_case(e).unwrap_or(4)
    }

    /// The cases of a `Result` an owned returned expression can build.
    pub(super) fn owned_case(&self, e: &Expr) -> u8 {
        self.result_case(e).unwrap_or(7)
    }

    /// The case an `ok(..)` or `error(..)` constructor call builds.
    pub(super) fn result_case(&self, e: &Expr) -> Option<u8> {
        self.result_payload(e)?;
        let Resolution::Constructor { case: Some(c), .. } = self.cx.m.resolution(e) else {
            return None;
        };
        match self.syms.str(c) {
            "ok" => Some(BORROWED_OK),
            "error" => Some(BORROWED_ERROR),
            _ => None,
        }
    }

    /// The error path of `try operand` returns the operand's error: a reference when the operand
    /// returns a borrow of it from the arguments as it is, otherwise a new value, like any `return`.
    pub(super) fn try_return(&mut self, e: &Expr, operand: &Expr) {
        if !self.captured.is_empty() || self.implements_contract() {
            return;
        }
        let result = match (self.cx.c.func.method(), self.cx.c.func.func()) {
            (Some(m), _) => m.func.result.id,
            (None, Some(f)) => f.result.id,
            (None, None) => return,
        };
        let Some(declared) = self.cx.m.type_ref(result) else {
            return;
        };
        if self.cx.classes.class(self.syms, &declared) == Class::Copy {
            return;
        }
        if self.class_of(operand) == Class::Move
            && let Some(src) = self.borrow_source(operand)
            && (src.cases == 0 || src.cases & BORROWED_ERROR != 0)
        {
            self.borrowed_return.get_or_insert(e.pos);
            if src.view {
                // The error leaves as an interface view (converted on the way out, or a view
                // already): an owned value whose payload stays in the operand's sources.
                self.view_return = true;
            } else {
                self.facts.view_wraps.insert(e.id);
                self.wrap_returns.push((e.id, BORROWED_ERROR));
                self.borrowed_cases |= BORROWED_ERROR;
                if let Some(err) = self.cx.m.ty(operand).args.get(1)
                    && !self.cx.classes.clonable(self.syms, err)
                {
                    self.borrow_not_clonable = true;
                }
            }
            self.borrow_receiver |= src.receiver;
            for p in src.params {
                if !self.borrow_params.contains(&p) {
                    self.borrow_params.push(p);
                }
            }
            // The error is one case of the result, never a field chain of a source.
            self.borrow_path = Some(None);
            return;
        }
        self.owned_return.get_or_insert(e.pos);
        self.owned_cases |= BORROWED_ERROR;
    }

    /// The payload expression of an `ok(x)` or `error(x)` constructor call.
    pub(super) fn result_payload<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let ExprKind::Call { args, .. } = &e.kind else {
            return None;
        };
        let Resolution::Constructor { ty, case: Some(_) } = self.cx.m.resolution(e) else {
            return None;
        };
        (ty.is(Builtin::Result) && args.len() == 1 && args[0].name.is_none())
            .then(|| &args[0].value)
    }

    /// The parameters and receiver a returned expression is a part of, when it is one: a place
    /// rooted in a parameter or the receiver, or a borrow-returning call whose sources all are. `None`
    /// for an owned value, including a part of a local, a temporary or a default argument.
    pub(super) fn borrow_source(&self, e: &Expr) -> Option<BorrowSource> {
        // `ok(x)` and `error(x)` are references when `x` is: the wrapper adds no storage. A
        // payload converted on the way in (`error(cause)` as `Error`) or copied is a new value.
        if let Some(payload) = self.result_payload(e) {
            let wrapped = self.wrapped_borrow(e)?;
            // `ok(x)` returned as an `Optional` of a `Result` is itself the wrapped value; its
            // reference is `x`, which must be tested for conversion and copy the same way.
            if std::ptr::eq(wrapped, e) {
                let info = self.cx.m.info(payload);
                if info.interface_source.is_some()
                    || info.wrap_some.is_some()
                    || self.class_of(payload) == Class::Copy
                {
                    return None;
                }
                return self.borrow_source(payload);
            }
            return self.borrow_source(wrapped);
        }
        // A field or element of what a borrow-returning call returns (`self.head().tags[0]`) is a part of
        // the same sources; a field chain extends the path, an element ends it.
        if let Some((call, fields)) = self.part_of_call(e) {
            let mut src = self.borrow_source(call)?;
            // A part of an owned view is a part of a temporary.
            if src.view {
                return None;
            }
            src.path = match (src.path.take(), fields) {
                (Some((root, mut path)), Some(more)) => {
                    path.extend(more);
                    Some((root, path))
                }
                _ => None,
            };
            return Some(src);
        }
        if self.is_place(e) {
            let root = match &e.kind {
                ExprKind::Name(_) => e,
                _ => self.root_name(e)?,
            };
            let Resolution::Local(b) = self.cx.m.resolution(root) else {
                return None;
            };
            let m = self.meta.get(&b.uid)?;
            if self.consumed.contains(&b.uid) {
                return None;
            }
            let path = self.field_path(e);
            if matches!(m.perm, Perm::Borrowed | Perm::MutBorrowed) {
                // A reference held by a local: a part of whatever it borrows, if those are all
                // parameters or the receiver.
                let mut out = BorrowSource {
                    receiver: false,
                    params: Vec::new(),
                    path: None,
                    view: self.view_locals.contains(&b.uid),
                    cases: 0,
                };
                let places = self.pure_places(e)?;
                for place in places {
                    let origin = self.meta.get(&place.root)?;
                    match (origin.role, origin.parameter) {
                        (Role::SelfValue, _) => out.receiver = true,
                        (Role::Parameter, Some(i)) => {
                            let label = self.parameter_label(i)?;
                            if !out.params.contains(&label) {
                                out.params.push(label);
                            }
                        }
                        _ => return None,
                    }
                }
                return Some(out);
            }
            return match (m.role, m.parameter) {
                (Role::SelfValue, _) => Some(BorrowSource {
                    receiver: true,
                    params: Vec::new(),
                    path: path.map(|f| (None, f)),
                    view: false,
                    cases: 0,
                }),
                (Role::Parameter, Some(i)) => {
                    let label = self.parameter_label(i)?;
                    Some(BorrowSource {
                        receiver: false,
                        params: vec![label],
                        path: path.map(|f| (Some(label), f)),
                        view: false,
                        cases: 0,
                    })
                }
                _ => None,
            };
        }
        // `xs.get(i)` is the element itself and `m.get(k)` its entry in an `Optional` view: parts
        // of the receiver's sources whose field chain ends there, so a function returning one
        // returns a borrow (Chinmay, 2026-11-07). `xs.first()` / `xs.last()` wrap the element in
        // an `Optional` the caller owns, so a function returning one owns its result.
        if let Some(recv) = self.native_borrow_receiver(e)
            && (self.list_get(e) || self.map_get(e))
        {
            let mut src = self.borrow_source(recv)?;
            if src.view {
                return None;
            }
            src.path = None;
            return Some(src);
        }
        if let ExprKind::Call { .. } = &e.kind {
            let ret_borrow = result_borrow(self.cx.m, e, self.cx.summaries);
            if !ret_borrow.returns_borrow {
                return None;
            }
            let operands = self.borrow_operands(e, &ret_borrow)?;
            if operands.is_empty() {
                return None;
            }
            let mut out = BorrowSource {
                receiver: false,
                params: Vec::new(),
                path: None,
                view: ret_borrow.view && ret_borrow.borrowed_cases == 0,
                cases: ret_borrow.borrowed_cases,
            };
            let mut paths: Vec<Option<(Option<Name>, Vec<Name>)>> = Vec::new();
            for (k, operand) in operands.iter().enumerate() {
                let src = self.borrow_source(operand)?;
                out.view |= src.view || self.view_source(operand).is_some();
                out.receiver |= src.receiver;
                for p in src.params {
                    if !out.params.contains(&p) {
                        out.params.push(p);
                    }
                }
                // The callee's one field chain, continued from this operand's own chain.
                let through = match (&ret_borrow.path, k, &src.path) {
                    (Some((None, fields)), 0, Some((root, mine))) if ret_borrow.receiver => {
                        Some((*root, [mine.clone(), fields.clone()].concat()))
                    }
                    (Some((Some(label), fields)), _, Some((root, mine)))
                        if self.borrow_operand_label(e, operand) == Some(*label) =>
                    {
                        Some((*root, [mine.clone(), fields.clone()].concat()))
                    }
                    _ => None,
                };
                paths.push(through);
            }
            out.path = if operands.len() == 1 {
                paths.pop().flatten()
            } else {
                None
            };
            return Some(out);
        }
        None
    }

    /// The borrow-returning call a projection chain starts from, with the fields from it when the chain
    /// is fields only (`None` for an element).
    pub(super) fn part_of_call<'e>(&self, e: &'e Expr) -> Option<(&'e Expr, Option<Vec<Name>>)> {
        match &e.kind {
            ExprKind::Member { left, name } => {
                if let ExprKind::Call { .. } = &left.kind {
                    return self
                        .returns_borrow(left)
                        .then_some((&**left, Some(vec![*name])));
                }
                let (call, fields) = self.part_of_call(left)?;
                Some((
                    call,
                    fields.map(|mut f| {
                        f.push(*name);
                        f
                    }),
                ))
            }
            ExprKind::Index { left, .. }
            | ExprKind::Apply {
                left,
                value: Some(_),
                ..
            } => {
                if let ExprKind::Call { .. } = &left.kind {
                    return self.returns_borrow(left).then_some((&**left, None));
                }
                let (call, _) = self.part_of_call(left)?;
                Some((call, None))
            }
            _ => None,
        }
    }

    /// Whether a call hands back a reference into its operands.
    pub(super) fn returns_borrow(&self, call: &Expr) -> bool {
        self.class_of(call) != Class::Copy
            && (self.native_borrow_receiver(call).is_some()
                || result_borrow(self.cx.m, call, self.cx.summaries).returns_borrow)
    }

    /// The label of the parameter `operand` is written for in call `e`.
    pub(super) fn borrow_operand_label(&self, e: &Expr, operand: &Expr) -> Option<Name> {
        let ExprKind::Call { args, .. } = &e.kind else {
            return None;
        };
        let i = args.iter().position(|a| a.value.id == operand.id)?;
        self.argument_label(e, i)
    }

    /// The label of parameter `i` of this callable.
    pub(super) fn parameter_label(&self, i: usize) -> Option<Name> {
        let c = self.cx.c;
        let params: &[ms_syntax::ast::Param] = match (c.func.method(), c.func.func()) {
            (Some(m), _) => &m.func.params,
            (None, Some(f)) => &f.params,
            (None, None) => &[],
        };
        params.get(i).map(|p| p.name)
    }

    /// Whether `e` is a native read that lowering borrows in place (`crates/ms-lower/src/borrow_shape.rs`):
    /// the receiver of a call `native_borrow` names, with the receiver written.
    pub(super) fn native_borrow_receiver<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        self.native_borrow_of(e).map(|(_, recv)| recv)
    }

    /// The kind of native borrow call `e` is and its receiver. The one place a name decides is
    /// `native_borrow` (`crates/ms-check/src/ownership/native_borrow.rs`).
    pub(super) fn native_borrow_of<'e>(&self, e: &'e Expr) -> Option<(NativeBorrow, &'e Expr)> {
        let ExprKind::Call { callee, args } = &e.kind else {
            return None;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return None;
        };
        let Resolution::Method(method) = self.cx.m.resolution(e) else {
            return None;
        };
        if method.native == Native::Source {
            return None;
        }
        let kind = native_borrow(&self.cx.m.ty(left), self.syms.str(name), args.len())?;
        // `get()` on the last use of an owned local hands its payload over instead of borrowing it.
        let takes_payload = kind == NativeBorrow::PayloadGet && self.owned_local_at_last_use(left);
        (!takes_payload).then_some((kind, &**left))
    }

    /// The variable whose `Bytes.view` the call `e` is, when it is returned: a function returns
    /// bytes it owns, so a view of a local or a parameter must be copied first.
    pub(super) fn returned_bytes_view(&self, e: &Expr) -> Option<Name> {
        let recv = self.native_borrow_receiver(e)?;
        let ExprKind::Call { callee, .. } = &e.kind else {
            return None;
        };
        let ExprKind::Member { name, .. } = &callee.kind else {
            return None;
        };
        let ty = self.cx.m.ty(e);
        if self.syms.str(name) != "view" || !(ty.is(Builtin::Bytes) || ty.is_string()) {
            return None;
        }
        let root = self.root_name(recv)?;
        let Resolution::Local(b) = self.cx.m.resolution(root) else {
            return None;
        };
        Some(b.name)
    }

    /// Whether `e` is `xs.get(i)` on a `List`, without a default: the element read in place.
    pub(super) fn list_get(&self, e: &Expr) -> bool {
        self.native_borrow_of(e)
            .is_some_and(|(k, _)| k == NativeBorrow::ListGet)
    }

    /// Whether `e` is `map.get(key)` on a `Map`: an entry read in place.
    pub(super) fn map_get(&self, e: &Expr) -> bool {
        self.native_borrow_of(e)
            .is_some_and(|(k, _)| k == NativeBorrow::MapGet)
    }

    /// `value` is `map.get(key).get()`: the `map.get(key)` call whose payload it reads.
    pub(super) fn entry_get<'e>(&self, value: &'e Expr) -> Option<&'e Expr> {
        let ExprKind::Call { callee, args } = &value.kind else {
            return None;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return None;
        };
        (self.syms.str(name) == "get"
            && args.is_empty()
            && self.cx.m.ty(left).is(Builtin::Optional)
            && self.map_get(left))
        .then_some(&**left)
    }

    pub(super) fn receiver_consumed(&self) -> bool {
        self.cx
            .c
            .self_binding
            .as_ref()
            .is_some_and(|b| self.consumed.contains(&b.uid))
    }
}
