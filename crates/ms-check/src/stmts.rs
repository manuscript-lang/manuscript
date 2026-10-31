//! Statements, patterns and `match`.

use crate::checker::{Checker, Scope};
use crate::hints::*;
use crate::suggestions;
use crate::syntax::*;
use crate::types::*;
use crate::types::{Case, Param};
use ms_syntax::Pos;
use ms_syntax::ast::*;
use std::collections::HashSet;
use std::rc::Rc;

/// The case or type name an arm path stands for.
pub(crate) fn path_text(path: &Expr) -> Name {
    match &path.kind {
        ExprKind::Name(nm) => *nm,
        ExprKind::Member { name, .. } => *name,
        _ => n(""),
    }
}

/// The identity of a literal match arm: its spelling, or `None` for anything else.
fn literal_key(path: &Expr) -> Option<String> {
    match &path.kind {
        ExprKind::Number(n) => Some(ms_syntax::number::canonical(n.as_str()).into_owned()),
        ExprKind::Bool(b) => Some(b.to_string()),
        ExprKind::Text(parts) => match parts.as_slice() {
            [TextPart::Lit(s)] => Some(format!("{s:?}")),
            _ => None,
        },
        ExprKind::Unary {
            op: UnaryOp::Neg,
            operand,
        } => match &operand.kind {
            ExprKind::Number(n) => {
                let value = ms_syntax::number::canonical(n.as_str());
                // Zero has no sign: `-0` and `-0x0` repeat `0`.
                let zero = value.bytes().all(|b| b == b'0');
                Some(if zero {
                    "0".into()
                } else {
                    format!("-{value}")
                })
            }
            _ => None,
        },
        _ => None,
    }
}

impl Checker {
    pub(crate) fn info_of(&self, e: &Expr) -> Option<Info> {
        self.m().facts().info(e.id).cloned()
    }

    pub(crate) fn set_info(&self, e: &Expr, info: Info) {
        self.m().facts_mut().set_info(e.id, info);
    }

    /// Marks the stored fact of an expression as written.
    pub(crate) fn mark_write(&self, e: &Expr) {
        let m = self.m();
        let mut facts = m.facts_mut();
        if let Some(Some(info)) = facts.exprs.get_mut(e.id.index()) {
            info.write = true;
        }
    }

    pub(crate) fn result_ty(&self) -> Ty {
        self.result.clone().unwrap_or_else(invalid)
    }

    /// Checks a statement list; reports whether control falls through and
    /// whether it breaks.
    pub(crate) fn block(&mut self, body: &[Stmt], nested: bool) -> (bool, bool) {
        let old = self.scope.clone();
        if nested {
            self.scope = Scope::new(Some(old.clone()));
        }
        let locks = self.held_locks.len();
        let mut fall = true;
        let mut breaks = false;
        for s in body {
            let (normal, br) = self.statement(s);
            if fall {
                breaks = breaks || br;
                fall = normal;
            }
        }
        self.scope = old;
        self.held_locks.truncate(locks);
        (fall, breaks)
    }

    pub(crate) fn statement(&mut self, s: &Stmt) -> (bool, bool) {
        let (fall, breaks) = self.check_statement(s);
        self.set_flow(s.id, fall);
        (fall, breaks)
    }

    fn check_statement(&mut self, s: &Stmt) -> (bool, bool) {
        match &s.kind {
            StmtKind::Bind {
                mutable,
                pattern,
                ty,
                value,
                ..
            } => self.check_bind(s, *mutable, pattern, ty.as_ref(), value),
            StmtKind::Assign { target, value, .. } => self.check_assign(s, target, value),
            StmtKind::Return(value) => self.check_return(s, value.as_ref()),
            StmtKind::Call(value) => self.check_call_statement(s.pos, value),
            StmtKind::Break | StmtKind::Continue => {
                let is_break = matches!(s.kind, StmtKind::Break);
                if self.loops == 0 {
                    let word = if is_break { "break" } else { "continue" };
                    self.type_error(
                        s.pos,
                        format!(
                            "{word} requires an enclosing loop; use it only inside 'for' or 'while' bodies"
                        ),
                    );
                }
                (false, is_break)
            }
            StmtKind::If {
                binding,
                mutable,
                cond,
                body,
                else_body,
            } => match binding {
                Some(p) => self.check_if_let(s, p, *mutable, cond, body, else_body),
                None => self.check_if(cond, body, else_body),
            },
            StmtKind::While { cond, body } => self.check_while(cond, body),
            StmtKind::For {
                name, iter, body, ..
            } => self.check_for(s, *name, iter, body),
        }
    }

    fn check_bind(
        &mut self,
        s: &Stmt,
        mutable: bool,
        pattern: &Pattern,
        ty: Option<&TypeRef>,
        value: &Expr,
    ) -> (bool, bool) {
        let mut expected: Option<Ty> = None;
        if let Some(t) = ty {
            let resolved = self.resolve(Some(t));
            self.well_formed(&resolved, t.pos, &mut HashSet::new());
            expected = Some(resolved);
        }
        let before = self.p.diagnostics.len();
        let mut info = match (&pattern.kind, &expected) {
            (PatternKind::Name(name), Some(_)) => self.expression_in(
                value,
                expected.as_ref(),
                format!("the initializer of '{name}'"),
            ),
            _ => self.expression(value, expected.as_ref()),
        };
        let mut bound = info.wrap_some.clone().unwrap_or_else(|| info.t());
        if let Some(exp) = &expected
            && self.p.diagnostics.len() > before
            && matches!(pattern.kind, PatternKind::Name(_))
        {
            // A failed initializer must not retype the annotated binding.
            bound = exp.clone();
        }
        if mutable && bound.kind == Kind::Function {
            bound = required_type(&bound);
            info = self.check_expression(value, info, Some(&bound));
        }
        self.pattern(pattern, &bound, mutable, Some(value));
        if let PatternKind::Name(name) = &pattern.kind {
            self.begin_lock(s, *name, value, &bound);
        }
        self.release_guard(value);
        // The scope closes a resource nothing takes; ownership decides which bindings that is.
        if matches!(pattern.kind, PatternKind::Name(_))
            && !is_invalid_id(&bound)
            && self.closeable(&bound)
        {
            let mut close = self.close_method(&bound);
            if close.len() == 1 {
                self.m().facts_mut().stmts.entry(s.id).or_default().cleanup = close.pop();
            }
        }
        (!info.no_return, info.breaks)
    }

    fn check_assign(&mut self, s: &Stmt, target: &AssignTarget, value: &Expr) -> (bool, bool) {
        match target {
            AssignTarget::Member(t) => {
                let tinfo = self.expression(t, None);
                self.mark_write(t);
                let (left, name) = match &t.kind {
                    ExprKind::Member { left, name } => (Some(&**left), *name),
                    _ => (None, n("")),
                };
                let receiver = left.and_then(|l| self.info_of(l));
                if !self.opaque_field(receiver.as_ref(), name) {
                    let bad = match &receiver {
                        None => true,
                        Some(r) => match &r.ty {
                            None => true,
                            Some(rt) => {
                                rt.kind != Kind::Record
                                    || r.symbol.as_ref().is_some_and(|s| s.kind == SymKind::Type)
                                    || tinfo.method.is_some()
                            }
                        },
                    };
                    if bad {
                        self.type_error(
                            t.pos,
                            "assignment requires a record field; only fields of a record value can be assigned with 'x.field = ...'",
                        );
                    }
                }
                let tty = tinfo.t();
                let v = self.expression(value, Some(&tty));
                (!tinfo.no_return && !v.no_return, tinfo.breaks || v.breaks)
            }
            AssignTarget::Name(name) => {
                let name = *name;
                let Some(b) = self.scope.binding(name) else {
                    if let Some(symbol) = self.sym(name) {
                        let what = self.symbol_description(&symbol);
                        self.type_error(
                            s.pos,
                            format!(
                                "cannot assign to {what} {name}; assignment targets are 'var' bindings and record fields"
                            ),
                        );
                    } else {
                        let msg = self.unknown_name(name);
                        self.res_error_name(s.pos, name.len(), msg);
                    }
                    self.expression(value, None);
                    return (true, false);
                };
                self.m().facts_mut().assigned.insert(value.id, b.clone());
                // A write-only assignment still captures the variable.
                if b.function != self.function
                    && let Some(captured) = self.captures.get_mut(&self.function)
                {
                    captured.insert(b.uid, b.clone());
                }
                if !b.mutable {
                    let fix = suggestions::let_to_var(&self.m().source, b.decl);
                    self.type_error_with_fix(
                        s.pos,
                        format!(
                            "cannot assign immutable binding {name}; declare it with 'var {name} = ...' instead of 'let'"
                        ),
                        fix,
                    );
                }
                let i = self.expression(value, Some(&b.ty));
                (!i.no_return, i.breaks)
            }
        }
    }

    fn check_return(&mut self, s: &Stmt, value: Option<&Expr>) -> (bool, bool) {
        if self.return_inference.is_some() {
            let mut typ = unit();
            let mut breaks = false;
            if let Some(v) = value {
                let context = self
                    .return_inference
                    .as_ref()
                    .and_then(|r| r.context.clone());
                let inferred = self.infer(v, context.as_ref());
                let required =
                    (inferred.t().kind == Kind::Function).then(|| required_type(&inferred.t()));
                let info = self.check_expression(v, inferred, required.as_ref());
                typ = info.t();
                breaks = info.breaks;
            }
            self.return_add(&typ, s.pos);
            return (false, breaks);
        }
        let in_test = self.test_function != 0 && self.function == self.test_function;
        match value {
            None => {
                let result = self.result_ty();
                if result.id != "Unit" && !in_test {
                    self.type_error(
                        s.pos,
                        format!(
                            "bare return requires Unit; this function returns {result}, so write 'return <value>'"
                        ),
                    );
                }
            }
            Some(v) if matches!(v.kind, ExprKind::Unit) && in_test => {
                self.expression(v, None); // returning unit from a test is success
            }
            Some(v) => {
                let result = self.result.clone();
                let i = match &result {
                    Some(r) => self.expression_in(v, Some(r), "the return value".to_string()),
                    None => self.expression(v, None),
                };
                return (false, i.breaks);
            }
        }
        (false, false)
    }

    /// `guard.close()` releases the lock the guard holds, also as `try guard.close()`,
    /// `guard.close().get(none)` or the value of a `let`.
    pub(crate) fn release_guard(&mut self, value: &Expr) {
        let mut e = value;
        loop {
            match &e.kind {
                ExprKind::Unary {
                    op: UnaryOp::Try,
                    operand,
                } => e = operand,
                ExprKind::Call { callee, .. } => {
                    let ExprKind::Member { left, name } = &callee.kind else {
                        return;
                    };
                    if name.as_str() == "close" {
                        let ExprKind::Name(guard) = &left.kind else {
                            return;
                        };
                        if let Some(at) = self.held_locks.iter().rposition(|(_, _, g)| g == guard) {
                            self.held_locks.remove(at);
                        }
                        return;
                    }
                    // `.get(none)` and the like wrap the close.
                    e = left;
                }
                _ => return,
            }
        }
    }

    fn check_call_statement(&mut self, pos: Pos, value: &Expr) -> (bool, bool) {
        self.release_guard(value);
        let i = if matches!(value.kind, ExprKind::Match { .. }) {
            // A match used as a statement discards its result, so its arms need
            // not agree on a value.
            self.capture_scope(value);
            let info = self.match_expression(value, None, true);
            self.check_expression(value, info, None)
        } else {
            self.expression(value, None)
        };
        if matches!(
            &value.kind,
            ExprKind::Unary {
                op: UnaryOp::Try,
                ..
            }
        ) {
            let t = i.t();
            if t.id != "Unit" && t.id != "<invalid>" {
                self.type_error(
                    value.pos,
                    format!(
                        "standalone try requires a Unit success value, found {t}; use 'let name = try ...' to keep the value or 'return try ...' to return it"
                    ),
                );
            }
        }
        let t = i.t();
        if t.is_std("Result")
            && !matches!(
                &value.kind,
                ExprKind::Unary {
                    op: UnaryOp::Try,
                    ..
                }
            )
        {
            self.type_error(
                pos,
                format!(
                    "this statement discards {t}, so a failure would be lost; write 'try ...' to propagate it, 'if let' or 'match' to handle it, or 'let _ = ...' to drop it on purpose"
                ),
            );
        }
        (!i.no_return, i.breaks)
    }

    fn check_if(&mut self, cond: &Expr, body: &[Stmt], else_body: &[Stmt]) -> (bool, bool) {
        let i = self.expression_in(cond, Some(&bool_()), "an if condition".to_string());
        let (a, ab) = self.block(body, true);
        let (mut b, mut bb) = (true, false);
        if !else_body.is_empty() {
            (b, bb) = self.block(else_body, true);
        }
        (!i.no_return && (a || b), i.breaks || ab || bb)
    }

    /// `if let name = optional` or `if let name = result` binds the present or
    /// Ok payload in the then-branch only. A Result's error is not captured.
    fn check_if_let(
        &mut self,
        s: &Stmt,
        pattern: &Pattern,
        mutable: bool,
        cond: &Expr,
        body: &[Stmt],
        else_body: &[Stmt],
    ) -> (bool, bool) {
        let i = self.expression(cond, None);
        let t = i.t();
        let mut payload = invalid();
        if (t.is_std("Optional") && t.args.len() == 1) || (t.is_std("Result") && t.args.len() == 2)
        {
            payload = t.args[0].clone();
        } else if t.id != "<invalid>" {
            self.type_error(
                cond.pos,
                format!(
                    "if let requires an Optional or Result, found {t}; use 'if' for a Bool condition or 'match' for other alternatives"
                ),
            );
        }
        let old = self.scope.clone();
        self.scope = Scope::new(Some(old.clone()));
        self.pattern(pattern, &payload, mutable, Some(cond));
        // The branch closes a resource payload nothing takes; ownership decides which it is.
        if matches!(pattern.kind, PatternKind::Name(_))
            && !is_invalid_id(&payload)
            && self.closeable(&payload)
        {
            let mut close = self.close_method(&payload);
            if close.len() == 1 {
                self.m().facts_mut().stmts.entry(s.id).or_default().cleanup = close.pop();
            }
        }
        let (a, ab) = self.block(body, true);
        self.scope = old;
        let (mut b, mut bb) = (true, false);
        if !else_body.is_empty() {
            (b, bb) = self.block(else_body, true);
        }
        (!i.no_return && (a || b), i.breaks || ab || bb)
    }

    fn check_while(&mut self, cond: &Expr, body: &[Stmt]) -> (bool, bool) {
        let i = self.expression_in(cond, Some(&bool_()), "a while condition".to_string());
        self.loops += 1;
        let (_, br) = self.block(body, true);
        self.loops -= 1;
        let literal_true = matches!(cond.kind, ExprKind::Bool(true));
        (!i.no_return && (!literal_true || br), i.breaks)
    }

    fn check_for(&mut self, s: &Stmt, name: Name, iter: &Expr, body: &[Stmt]) -> (bool, bool) {
        let i = self.expression(iter, None);
        let t = i.t();
        let mut element = invalid();
        if t.is_std("List") || t.is_std("Set") {
            if !t.args.is_empty() {
                element = t.args[0].clone();
            }
        } else if t.is_std("Map") {
            if t.args.len() == 2 {
                element = standard("MapEntry", t.args.clone());
            }
        } else if self.iterator_item(&t).is_some() {
            return self.check_iterator_for(s, name, iter, body, Vec::new());
        } else if self.is_iterable(&t) {
            return self.check_iterable_for(s, name, iter, body);
        } else {
            self.type_error(
                s.pos,
                format!(
                    "for requires List, Set, Map, an Iterator, or an Iterable, found {t}; iterate a collection, e.g. a list literal [1, 2, 3], or implement Iterator with 'var fn next() T?', or Iterable with 'fn length() Int' and 'fn at(index: Int) T?'"
                ),
            );
        }
        let old = self.scope.clone();
        self.scope = Scope::new(Some(old.clone()));
        let b = self.bind(name, &element, false, s.pos);
        self.record_cleanup(&b);
        self.m()
            .facts_mut()
            .stmts
            .entry(s.id)
            .or_default()
            .loop_binding = Some(b);
        self.loops += 1;
        self.block(body, false);
        self.loops -= 1;
        self.scope = old;
        (!i.no_return, i.breaks)
    }

    /// The item type of `t` when it implements `Iterator[T]`.
    fn iterator_item(&self, t: &Ty) -> Option<Ty> {
        self.methods(t, n("next")).into_iter().find_map(|m| {
            let contract = m.contract.as_ref()?;
            if !contract.is_std("Iterator") || !m.ty.params.is_empty() {
                return None;
            }
            let result = m.ty.result_ty();
            (result.is_std("Optional") && result.args.len() == 1).then(|| result.args[0].clone())
        })
    }

    /// `for name in iterator:` is checked, lowered and analysed as
    /// `while True: if let name = iterator.next(): body else: break`. A variable or field path
    /// is advanced in place, so it keeps the iterator's final state (`error()` of a reader);
    /// any other expression is held in a hidden `var` for the loop.
    fn check_iterator_for(
        &mut self,
        s: &Stmt,
        name: Name,
        iter: &Expr,
        body: &[Stmt],
        mut expansion: Vec<Stmt>,
    ) -> (bool, bool) {
        let pos = s.pos;
        let id = |c: &Self| c.m().facts_mut().fresh_id();
        let place = is_place_path(iter);
        let holder = if place {
            iter.clone()
        } else {
            let hidden = n(&format!("$iterator{}", s.id.0));
            let pattern = Pattern {
                id: id(self),
                pos,
                kind: PatternKind::Name(hidden),
            };
            expansion.push(Stmt {
                id: id(self),
                pos,
                kind: StmtKind::Bind {
                    mutable: true,
                    pattern,
                    ty: None,
                    value: iter.clone(),
                    group: None,
                },
            });
            Expr {
                id: id(self),
                pos: iter.pos,
                end: iter.pos,
                kind: ExprKind::Name(hidden),
            }
        };
        let callee = Expr {
            id: id(self),
            pos: iter.pos,
            end: iter.pos,
            kind: ExprKind::Member {
                left: Box::new(holder),
                name: n("next"),
            },
        };
        let call = Expr {
            id: id(self),
            pos: iter.pos,
            end: iter.pos,
            kind: ExprKind::Call {
                callee: Box::new(callee),
                args: Vec::new(),
            },
        };
        let binding = Pattern {
            id: id(self),
            pos,
            kind: PatternKind::Name(name),
        };
        let leave = Stmt {
            id: id(self),
            pos,
            kind: StmtKind::Break,
        };
        let step = Stmt {
            id: id(self),
            pos,
            kind: StmtKind::If {
                binding: Some(binding),
                mutable: false,
                cond: call,
                body: body.to_vec(),
                else_body: vec![leave],
            },
        };
        let forever = Expr {
            id: id(self),
            pos,
            end: pos,
            kind: ExprKind::Bool(true),
        };
        expansion.push(Stmt {
            id: id(self),
            pos,
            kind: StmtKind::While {
                cond: forever,
                body: vec![step],
            },
        });
        let expansion = Rc::new(expansion);
        self.m()
            .facts_mut()
            .stmts
            .entry(s.id)
            .or_default()
            .expansion = Some(expansion.clone());
        self.block(&expansion, false)
    }

    /// Whether `t` implements `Iterable[T]`, the contract of iterating a container by position.
    fn is_iterable(&self, t: &Ty) -> bool {
        self.methods(t, n("at")).into_iter().any(|m| {
            m.contract
                .as_ref()
                .is_some_and(|contract| contract.is_std("Iterable"))
        })
    }

    /// `for name in container:` over an `Iterable` container is checked as
    /// `for $i in 0..container.length(): if let name = container.at($i): body`, so the container is
    /// read in place and never copied. A container that is not a place is held in a hidden `let`
    /// first.
    fn check_iterable_for(
        &mut self,
        s: &Stmt,
        name: Name,
        iter: &Expr,
        body: &[Stmt],
    ) -> (bool, bool) {
        let pos = s.pos;
        let id = |c: &Self| c.m().facts_mut().fresh_id();
        let expr = |c: &Self, kind: ExprKind| Expr {
            id: id(c),
            pos: iter.pos,
            end: iter.pos,
            kind,
        };
        let mut expansion: Vec<Stmt> = Vec::new();
        let holder = |c: &Self, hidden: Name| {
            if is_place_path(iter) {
                iter.clone()
            } else {
                expr(c, ExprKind::Name(hidden))
            }
        };
        let hidden = n(&format!("$iterable{}", s.id.0));
        if !is_place_path(iter) {
            let pattern = Pattern {
                id: id(self),
                pos,
                kind: PatternKind::Name(hidden),
            };
            expansion.push(Stmt {
                id: id(self),
                pos,
                kind: StmtKind::Bind {
                    mutable: false,
                    pattern,
                    ty: None,
                    value: iter.clone(),
                    group: None,
                },
            });
        }
        let index = n(&format!("$index{}", s.id.0));
        let method = |c: &Self, member: &str, args: Vec<Expr>| {
            let callee = expr(
                c,
                ExprKind::Member {
                    left: Box::new(holder(c, hidden)),
                    name: n(member),
                },
            );
            expr(
                c,
                ExprKind::Call {
                    callee: Box::new(callee),
                    args: args
                        .into_iter()
                        .map(|value| Argument {
                            pos: value.pos,
                            name: None,
                            value,
                            mutable: false,
                        })
                        .collect(),
                },
            )
        };
        expansion.push(Stmt {
            id: id(self),
            pos,
            kind: StmtKind::For {
                name: index,
                iter: {
                    let callee = expr(self, ExprKind::Name(n("..")));
                    let zero = expr(self, ExprKind::Number(n("0")));
                    let length = method(self, "length", Vec::new());
                    expr(
                        self,
                        ExprKind::Call {
                            callee: Box::new(callee),
                            args: [zero, length]
                                .into_iter()
                                .map(|value| Argument {
                                    pos: value.pos,
                                    name: None,
                                    value,
                                    mutable: false,
                                })
                                .collect(),
                        },
                    )
                },
                body: vec![Stmt {
                    id: id(self),
                    pos,
                    kind: StmtKind::If {
                        binding: Some(Pattern {
                            id: id(self),
                            pos,
                            kind: PatternKind::Name(name),
                        }),
                        mutable: false,
                        cond: {
                            let position = expr(self, ExprKind::Name(index));
                            method(self, "at", vec![position])
                        },
                        body: body.to_vec(),
                        else_body: Vec::new(),
                    },
                }],
            },
        });
        let expansion = Rc::new(expansion);
        self.m()
            .facts_mut()
            .stmts
            .entry(s.id)
            .or_default()
            .expansion = Some(expansion.clone());
        self.block(&expansion, false)
    }

    /// The `close() -> Result[Unit, Error]` operations of `t`: the standard `Closeable` one when it has it.
    /// Records the close operation a parameter or loop variable of a closeable type gets at
    /// scope end, when it turns out to own its value.
    pub(crate) fn record_cleanup(&mut self, b: &BindingRef) {
        if is_invalid_id(&b.ty) || !self.closeable(&b.ty) {
            return;
        }
        let mut close = self.close_method(&b.ty);
        if close.len() == 1 {
            self.m()
                .facts_mut()
                .cleanups
                .insert(b.uid, close.pop().expect("one"));
        }
    }

    pub(crate) fn close_method(&mut self, t: &Ty) -> Vec<MethodRef> {
        let mut candidates: Vec<MethodRef> = Vec::new();
        for method in self.methods(t, n("close")) {
            if method.ty.params.is_empty() && is_close_result(&method.ty.result_ty()) {
                if method
                    .contract
                    .as_ref()
                    .is_some_and(|c| c.is_std("Closeable"))
                {
                    return vec![method];
                }
                candidates.push(method);
            }
        }
        candidates
    }

    pub(crate) fn pattern(&mut self, p: &Pattern, t: &Ty, mutable: bool, source: Option<&Expr>) {
        match &p.kind {
            PatternKind::Name(name) => {
                let b = self.bind(*name, t, mutable, p.pos);
                self.m().facts_mut().patterns.insert(p.id, b);
            }
            PatternKind::Record(pfields) => {
                if t.kind != Kind::Record {
                    self.type_error(
                        p.pos,
                        "record binding requires a record; destructure only record values, or bind the whole value to one name",
                    );
                    return;
                }
                self.opaque_denied(p.pos, t, "its fields cannot be destructured here");
                let fs = fields(t);
                let mut seen: HashSet<Name> = HashSet::new();
                for f in pfields {
                    if !seen.insert(f.name) {
                        self.type_error(
                            f.pos,
                            format!("duplicate record field {}; bind each field once", f.name),
                        );
                    }
                    let mut found = false;
                    for field in &fs {
                        if field.name == f.name {
                            self.pattern(&f.pattern, &field.ty, mutable, None);
                            found = true;
                        }
                    }
                    if !found {
                        self.type_error(
                            f.pos,
                            format!(
                                "unknown record field {}; fields: {}",
                                f.name,
                                list(&names_of(&fs), 12)
                            ),
                        );
                    }
                }
            }
            PatternKind::List(elements) => {
                if t.is_std("List") && t.args.len() == 1 {
                    if let Some(src) = source
                        && let ExprKind::List(items) = &src.kind
                        && items.len() != elements.len()
                    {
                        self.type_error(
                                    p.pos,
                                    "statically known list length does not match binding; bind exactly as many names as the list has elements",
                                );
                    }
                    for child in elements {
                        self.pattern(child, &t.args[0], mutable, None);
                    }
                } else {
                    self.type_error(
                        p.pos,
                        "positional binding requires a list; use [a, b] patterns only with List values",
                    );
                }
            }
        }
    }

    // ------------------------------------------------------------------ match

    /// Checks the arms of a `match`; `body` checks one arm's statements in the
    /// arm's scope.
    pub(crate) fn match_arms<'a>(
        &mut self,
        pos: Pos,
        value: &Expr,
        arms: &'a [Arm],
        body: &mut dyn FnMut(&mut Checker, &'a Arm) -> (bool, bool),
    ) -> (bool, bool) {
        let info = self.expression(value, None);
        let t = info.t();
        if t.kind == Kind::Contract {
            return self.match_contract(pos, arms, &info, body);
        }
        if t.id == "<invalid>" {
            return (false, false);
        }
        if arms.first().is_some_and(|a| a.from_if) && t.id != "Bool" {
            self.type_error(
                pos,
                format!(
                    "an if condition must be Bool, found {t}; compare explicitly, e.g. 'x != 0'"
                ),
            );
            return (true, false);
        }
        if matches!(t.id.as_str(), "Int" | "String" | "Bool") {
            return self.match_literals(pos, &t, arms, &info, body);
        }
        if t.kind != Kind::Alternative {
            self.type_error(
                pos,
                format!(
                    "match requires an alternative, contract view, Int, String or Bool, found {t}; match on a type with cases, or use if/else"
                ),
            );
            return (true, false);
        }
        self.opaque_denied(pos, &t, "its cases cannot be matched here");
        let all_cases = cases(&t);
        let mut seen: HashSet<Name> = HashSet::new();
        let (mut fall, mut breaks) = (false, false);
        let (mut wildcard, mut unknown_case) = (false, false);
        for (index, arm) in arms.iter().enumerate() {
            self.set_arm_bindings(arm, Vec::new());
            let name = path_text(&arm.path);
            let mut arm_fields: Vec<Param> = Vec::new();
            let mut unknown_arm = false;
            if name == "_" {
                if wildcard || index != arms.len() - 1 || seen.len() == all_cases.len() {
                    self.type_error(
                        arm.pos,
                        "unreachable wildcard or wildcard is not last; keep one '_' arm at the end, and only when cases remain",
                    );
                }
                wildcard = true;
            } else {
                if let ExprKind::Member { left, .. } = &arm.path.kind {
                    let qualified = self.type_expression(left);
                    if qualified.as_ref().is_none_or(|q| {
                        !same_qualifier(q, &t, matches!(left.kind, ExprKind::Apply { .. }))
                    }) {
                        self.type_error(
                            arm.pos,
                            format!(
                                "pattern belongs to a different alternative; qualify arms with the matched type, {}.<case>",
                                t.name
                            ),
                        );
                    }
                }
                let mut found = false;
                for cs in &all_cases {
                    if cs.name == name {
                        arm_fields = cs.fields.clone();
                        found = true;
                    }
                }
                if !found {
                    unknown_case = true;
                    unknown_arm = true;
                    let upper = name
                        .as_str()
                        .bytes()
                        .next()
                        .is_some_and(|b| b.is_ascii_uppercase());
                    let names = case_names(&t);
                    if arm.bare {
                        let binding = arm.bindings[0].name;
                        self.res_error(
                            arm.pos,
                            format!(
                                "'{binding}' is not a case of {}; a lone lowercase name binds an Optional's payload, but this is not an Optional; use '_' for a catch-all arm, or one of the cases: {}",
                                t.name,
                                list(&names, 12)
                            ),
                        );
                    } else if arm.bindings.is_empty() && !name.is_empty() && !upper {
                        self.res_error(
                            arm.pos,
                            format!(
                                "'{name}' is not a case of {}; use '_' for a catch-all arm (it cannot bind a name); cases: {}",
                                t.name,
                                list(&names, 12)
                            ),
                        );
                    } else {
                        self.res_error(
                            arm.pos,
                            format!(
                                "unknown case {name} of {}; cases: {}{}",
                                t.name,
                                list(&names, 12),
                                did_you_mean(name.as_str(), &names)
                            ),
                        );
                    }
                }
                if seen.contains(&name) || wildcard {
                    self.type_error(
                        arm.pos,
                        format!(
                            "duplicate or unreachable case {name}; each case may be matched once and before any '_' arm"
                        ),
                    );
                }
                seen.insert(name);
                if found && arm_fields.len() != arm.bindings.len() {
                    self.type_error(
                        arm.pos,
                        format!(
                            "case payload arity mismatch; {name} has {} payload fields, found {} bindings (use _ to ignore one)",
                            arm_fields.len(),
                            arm.bindings.len()
                        ),
                    );
                }
            }
            self.match_binding_names(arm, &arm_fields);
            let old = self.scope.clone();
            self.scope = Scope::new(Some(old.clone()));
            for (i, binding) in arm.bindings.iter().enumerate() {
                let mut b: Option<BindingRef> = None;
                if binding.name != "_" && i < arm_fields.len() {
                    b = Some(self.bind(binding.name, &arm_fields[i].ty, false, arm.pos));
                } else if binding.name != "_" && unknown_arm {
                    // the unknown case was already reported; keep its names bound
                    b = Some(self.bind(binding.name, &invalid(), false, arm.pos));
                }
                self.push_arm_binding(arm, b);
            }
            let (a, br) = body(self, arm);
            fall = fall || a;
            breaks = breaks || br;
            self.scope = old;
        }
        if !wildcard && !unknown_case && seen.len() != all_cases.len() {
            self.type_error(
                pos,
                format!(
                    "non-exhaustive match; missing cases: {}, or add a final '_:' arm; add the arms {}",
                    list(&missing_cases(&all_cases, &seen), 12),
                    missing_arms(&all_cases, &seen)
                ),
            );
        }
        (!info.no_return && fall, info.breaks || breaks)
    }

    /// A `match` over Int, String or Bool: literal arms and a final `_`.
    fn match_literals<'a>(
        &mut self,
        pos: Pos,
        t: &Ty,
        arms: &'a [Arm],
        info: &Info,
        body: &mut dyn FnMut(&mut Checker, &'a Arm) -> (bool, bool),
    ) -> (bool, bool) {
        let mut seen: HashSet<String> = HashSet::new();
        let (mut fall, mut breaks, mut wildcard) = (false, false, false);
        for (index, arm) in arms.iter().enumerate() {
            self.set_arm_bindings(arm, Vec::new());
            if path_text(&arm.path) == "_" {
                if wildcard || index != arms.len() - 1 || (t.id == "Bool" && seen.len() == 2) {
                    self.type_error(
                        arm.pos,
                        "unreachable wildcard or wildcard is not last; keep one '_' arm at the end, and only when values remain",
                    );
                }
                wildcard = true;
            } else if let Some(key) = literal_key(&arm.path) {
                self.expression(&arm.path, Some(t));
                if !seen.insert(key.clone()) || wildcard {
                    self.type_error(
                        arm.pos,
                        format!("duplicate or unreachable pattern {key}; each value may be matched once and before any '_' arm"),
                    );
                }
            } else {
                self.type_error(
                    arm.pos,
                    format!("a match on {t} takes literal arms such as 1, \"text\" or true, and a final '_:' arm; to bind or compare computed values use if/else"),
                );
            }
            if !arm.bindings.is_empty() {
                self.type_error(arm.pos, "a literal arm has no payload to bind");
            }
            let old = self.scope.clone();
            self.scope = Scope::new(Some(old.clone()));
            let (a, br) = body(self, arm);
            fall = fall || a;
            breaks = breaks || br;
            self.scope = old;
        }
        let covered = wildcard || (t.id == "Bool" && seen.len() == 2);
        if !covered {
            self.type_error(
                pos,
                format!("non-exhaustive match on {t}; add a final '_:' arm"),
            );
        }
        (!info.no_return && fall, info.breaks || breaks)
    }

    fn match_contract<'a>(
        &mut self,
        pos: Pos,
        arms: &'a [Arm],
        info: &Info,
        body: &mut dyn FnMut(&mut Checker, &'a Arm) -> (bool, bool),
    ) -> (bool, bool) {
        let contract = info.t();
        let mut seen: HashSet<String> = HashSet::new();
        let (mut wildcard, mut fall, mut breaks) = (false, false, false);
        for (index, arm) in arms.iter().enumerate() {
            self.set_arm_bindings(arm, Vec::new());
            let mut target: Option<Ty> = None;
            if path_text(&arm.path) == "_" {
                if wildcard || index != arms.len() - 1 {
                    self.type_error(
                        arm.pos,
                        "wildcard must appear once and be last; keep a single '_' arm at the end",
                    );
                }
                wildcard = true;
            } else {
                target = self.type_expression(&arm.path);
                match &target {
                    Some(t) if matches!(t.kind, Kind::Record | Kind::Alternative) => {
                        let t = t.clone();
                        let has_variables = t.def.as_ref().is_some_and(|d| d.arity() > 0);
                        if has_variables && !matches!(arm.path.kind, ExprKind::Apply { .. }) {
                            self.type_error(
                                arm.pos,
                                "concrete type pattern requires explicit type arguments; write e.g. Box[Int]",
                            );
                        }
                        self.well_formed(&t, arm.pos, &mut HashSet::new());
                        if !self.implements(&t, &contract) {
                            self.type_error(arm.pos, format!("{t} does not implement {contract}"));
                        }
                        let key = type_key(&t);
                        if seen.contains(&key) || wildcard {
                            self.type_error(
                                arm.pos,
                                "duplicate or unreachable concrete type pattern; match each type once and before '_'",
                            );
                        }
                        seen.insert(key);
                        self.m()
                            .facts_mut()
                            .arms
                            .entry(arm.id)
                            .or_default()
                            .contract = Some(t.clone());
                        let name_expr = match &arm.path.kind {
                            ExprKind::Apply { left, .. } => &**left,
                            _ => &arm.path,
                        };
                        self.set_info(
                            name_expr,
                            Info {
                                ty: Some(t.clone()),
                                symbol: t.symbol(),
                                ..Info::default()
                            },
                        );
                    }
                    _ => {
                        self.type_error(
                            arm.pos,
                            "contract pattern requires a concrete record or alternative type; name an implementing type like Circle, or use '_'",
                        );
                        target = None;
                    }
                }
                if arm.bindings.len() != 1 {
                    self.type_error(
                        arm.pos,
                        "concrete type pattern requires exactly one receiver binding; write 'Type(name):' or 'Type(_):'",
                    );
                }
            }
            let placeholder = Param {
                name: n(""),
                ty: target.clone().unwrap_or_else(invalid),
            };
            self.match_binding_names(arm, &[placeholder]);
            let old = self.scope.clone();
            self.scope = Scope::new(Some(old.clone()));
            for binding in &arm.bindings {
                let mut b: Option<BindingRef> = None;
                if binding.name != "_"
                    && let Some(t) = &target
                {
                    b = Some(self.bind(binding.name, t, false, arm.pos));
                }
                self.push_arm_binding(arm, b);
            }
            let (a, br) = body(self, arm);
            fall = fall || a;
            breaks = breaks || br;
            self.scope = old;
        }
        if !wildcard {
            self.type_error(
                pos,
                "contract match requires a final wildcard for other implementations; add a last '_' arm",
            );
        }
        (!info.no_return && fall, info.breaks || breaks)
    }

    fn set_arm_bindings(&self, arm: &Arm, bindings: Vec<Option<BindingRef>>) {
        let m = self.m();
        let mut facts = m.facts_mut();
        let f = facts.arms.entry(arm.id).or_default();
        f.bindings = bindings;
        f.has_bindings = true;
    }

    fn push_arm_binding(&self, arm: &Arm, b: Option<BindingRef>) {
        let m = self.m();
        let mut facts = m.facts_mut();
        let f = facts.arms.entry(arm.id).or_default();
        f.bindings.push(b);
        f.has_bindings = true;
    }

    /// Resolves payload names before introducing sibling payload bindings.
    /// This is advisory evidence only: every non-placeholder name still
    /// creates its ordinary binding.
    fn match_binding_names(&mut self, arm: &Arm, fields: &[Param]) {
        let mut conflicts: Vec<Option<Info>> = vec![None; arm.bindings.len()];
        for (index, binding) in arm.bindings.iter().enumerate() {
            let name = binding.name;
            if name == "_"
                || index >= fields.len()
                || self.scope.binding(name).is_some()
                || self.scope.typ(name).is_some()
            {
                continue;
            }
            if let Some(symbol) = self.sym(name) {
                if symbol.kind == SymKind::Type {
                    conflicts[index] = Some(Info {
                        ty: symbol.ty_opt(),
                        symbol: Some(symbol.clone()),
                        ..Info::default()
                    });
                }
                continue;
            }
            // A nested match can name cases of its scrutinee even when the
            // payload's defining type was not imported.
            let payload = &fields[index].ty;
            if payload.kind == Kind::Alternative && case_of(payload, name).is_some() {
                conflicts[index] = Some(Info {
                    ty: Some(payload.clone()),
                    case: Some(name),
                    ..Info::default()
                });
                continue;
            }
            // Otherwise retain visible case evidence, omitting the owner when
            // ambiguous. Do not issue resolution errors or choose by map order.
            let mut owner: Option<Ty> = None;
            let mut ambiguous = false;
            let symbols: Vec<(Name, SymRef)> = self
                .names
                .borrow()
                .iter()
                .map(|(k, v)| (*k, v.clone()))
                .collect();
            for (type_name, symbol) in symbols {
                let Some(st) = symbol.ty_opt() else {
                    continue;
                };
                if symbol.kind != SymKind::Type
                    || st.kind != Kind::Alternative
                    || self.scope.binding(type_name).is_some()
                    || self.scope.typ(type_name).is_some()
                {
                    continue;
                }
                if case_of(&st, name).is_some() {
                    if owner.as_ref().is_some_and(|o| o.id != st.id) {
                        ambiguous = true;
                        break;
                    }
                    owner = Some(st);
                }
            }
            if ambiguous {
                conflicts[index] = Some(Info {
                    case: Some(name),
                    ..Info::default()
                });
            } else if let Some(owner) = owner {
                conflicts[index] = Some(Info {
                    ty: Some(owner),
                    case: Some(name),
                    ..Info::default()
                });
            }
        }
        self.m()
            .facts_mut()
            .arms
            .entry(arm.id)
            .or_default()
            .conflicts = conflicts;
    }

    // --------------------------------------------------------- type expressions

    pub(crate) fn resolve_arguments(&mut self, args: &[TypeRef]) -> Vec<Ty> {
        let mut result = Vec::new();
        for a in args {
            let t = self.resolve(Some(a));
            self.well_formed(&t, a.pos, &mut HashSet::new());
            result.push(t);
        }
        result
    }

    /// The function symbol a name expression stands for, if any.
    pub(crate) fn function_symbol(&self, e: &Expr) -> Option<SymRef> {
        if let ExprKind::Name(name) = &e.kind
            && self.scope.binding(*name).is_none()
            && let Some(s) = self.sym(*name)
            && s.kind == SymKind::Fn
        {
            return Some(s);
        }
        None
    }

    /// Reads an expression as a type (constructor and qualified-case names
    /// bypass expression inference).
    pub(crate) fn type_expression(&mut self, e: &Expr) -> Option<Ty> {
        if let ExprKind::Name(name) = &e.kind
            && self.scope.binding(*name).is_none()
        {
            if let Some(v) = self.scope.typ(*name) {
                return Some(v);
            }
            if let Some(s) = self.sym(*name)
                && s.kind == SymKind::Type
            {
                // Retain the resolved identity for import usage and navigation.
                self.set_info(
                    e,
                    Info {
                        ty: s.ty_opt(),
                        symbol: Some(s.clone()),
                        ..Info::default()
                    },
                );
                return s.ty_opt();
            }
        }
        if let ExprKind::Apply { left, types, .. } = &e.kind
            && let Some(t) = self.type_expression(left)
        {
            let mut r = (*t).clone();
            r.args = self.resolve_arguments(types);
            if let Some(def) = &r.def {
                let vars = def.variables();
                if r.args.len() < vars.len() && r.args.len() >= required_type_arguments(&vars) {
                    r.args = with_default_arguments(&vars, &r.args);
                }
            }
            if r.def.as_ref().is_none_or(|d| r.args.len() != d.arity()) {
                self.type_error(
                        e.pos,
                        "generic type arity mismatch; supply the type arguments the declaration lists, omitting only trailing ones that have defaults",
                    );
            }
            return Some(Rc::new(r));
        }
        None
    }

    /// Resolves an unqualified case name. `ambiguous` reports that the failure
    /// was already diagnosed, so callers must not add an unknown-name error.
    pub(crate) fn find_case(&mut self, name: Name, pos: Pos) -> (Option<Ty>, Option<Case>, bool) {
        let mut found: Option<Ty> = None;
        let mut cs: Option<Case> = None;
        let symbols: Vec<SymRef> = self.names.borrow().values().cloned().collect();
        for s in symbols {
            let Some(st) = s.ty_opt() else {
                continue;
            };
            if s.kind == SymKind::Type
                && st.kind == Kind::Alternative
                && let Some(candidate) = case_of(&st, name)
            {
                if found.is_some() {
                    self.res_error(
                            pos,
                            format!(
                                "ambiguous alternative case {name}; qualify it with its type, e.g. Type.{name}"
                            ),
                        );
                    return (None, None, true);
                }
                found = Some(st);
                cs = Some(candidate);
            }
        }
        (found, cs, false)
    }

    /// Whether an expression's type is decided by its context.
    pub(crate) fn contextual(&self, e: &Expr) -> bool {
        match &e.kind {
            ExprKind::Lambda(l) => {
                if l.result.is_none() || l.params.iter().any(|p| p.ty.is_none()) {
                    return true;
                }
                false
            }
            ExprKind::List(items) => items.is_empty() || items.iter().all(|a| self.contextual(a)),
            ExprKind::Map(entries) => {
                entries.is_empty()
                    || entries
                        .iter()
                        .all(|en| self.contextual(&en.key) && self.contextual(&en.value))
            }
            ExprKind::Name(name) => {
                self.scope.binding(*name).is_none() && self.sym(*name).is_none()
            }
            ExprKind::Call { callee, .. } => {
                if let ExprKind::Name(name) = &callee.kind
                    && (name == "ok" || name == "error")
                {
                    return self.sym(*name).is_none() && self.scope.binding(*name).is_none();
                }
                false
            }
            _ => false,
        }
    }

    /// `receiver[index]` over a List, Map or Bytes.
    pub(crate) fn index(&mut self, e: &Expr, left: &Expr, right: &Expr) -> Info {
        let receiver = self.expression(left, None);
        let rt = receiver.t();
        if rt.id == "<invalid>" && matches!(right.kind, ExprKind::Name(_)) {
            // An unresolved receiver was reported; its bracket argument is probably a type argument.
            return Info {
                ty: Some(invalid()),
                native: Some(n("index")),
                no_return: receiver.no_return,
                ..Info::default()
            };
        }
        let list = rt.is_std("List") && rt.args.len() == 1;
        let map = rt.is_std("Map") && rt.args.len() == 2;
        let bytes = rt.is_std("Bytes");
        // A Map key keeps its own type; Lists and Bytes are indexed by Int.
        let expected = if map {
            Some(rt.args[0].clone())
        } else {
            (list || bytes).then(int)
        };
        let index = self.expression(right, expected.as_ref());
        let mut info = Info {
            ty: Some(invalid()),
            native: Some(n("index")),
            no_return: receiver.no_return || index.no_return,
            ..Info::default()
        };
        if rt.id == "<invalid>" {
            return info;
        }
        if list {
            self.constant_index(e, left, right);
            info.ty = Some(rt.args[0].clone());
        } else if map {
            info.ty = Some(rt.args[1].clone());
        } else if bytes {
            info.ty = Some(primitive("UInt8"));
        } else {
            let hint = if rt.id == "String" {
                "indexing a String by scalar position is not supported; use s.get(index) or for c in s.chars()"
            } else {
                "indexing requires List[T], Map[K, V] or Bytes; use the receiver's lookup method for other types"
            };
            self.type_error(e.pos, hint);
        }
        info
    }

    /// `target?` where `target` is `left[index]`: the entry of a map or list, when present.
    pub(crate) fn probe(&mut self, e: &Expr, target: &Expr) -> Info {
        let left = match &target.kind {
            ExprKind::Index { left, .. } => left,
            ExprKind::Apply {
                left,
                value: Some(_),
                ..
            } => left,
            _ => {
                return Info {
                    ty: Some(invalid()),
                    ..Info::default()
                };
            }
        };
        let mut info = self.expression(target, None);
        let receiver = self.info_of(left).and_then(|i| i.ty);
        let entries = receiver.is_some_and(|r| {
            (r.is_std("List") && r.args.len() == 1) || (r.is_std("Map") && r.args.len() == 2)
        });
        info.ty = match info.ty {
            Some(t) if entries => Some(standard("Optional", vec![t])),
            Some(t) if t.id == "<invalid>" => Some(t),
            _ => {
                self.type_error(
                    e.pos,
                    "`?` after an index tests whether a List or Map entry exists; use it as `if var name = place[key]?`",
                );
                Some(invalid())
            }
        };
        info
    }

    pub(crate) fn match_expression<'a>(
        &mut self,
        e: &'a Expr,
        expected: Option<&Ty>,
        statement: bool,
    ) -> Info {
        struct ArmState<'a> {
            arm: &'a Arm,
            scope: Rc<Scope>,
            normal: bool,
            breaks: bool,
            info: Option<Info>,
        }
        let ExprKind::Match { scrutinee, arms } = &e.kind else {
            return Info {
                ty: Some(invalid()),
                ..Info::default()
            };
        };
        let mut states: Vec<ArmState> = Vec::new();
        let mut result_at = Pos::default();
        {
            let mut collect = |c: &mut Checker, arm: &'a Arm| {
                let (normal, breaks) = c.block(&arm.body, false);
                states.push(ArmState {
                    arm,
                    scope: c.scope.clone(),
                    normal,
                    breaks,
                    info: None,
                });
                (normal, breaks)
            };
            self.match_arms(e.pos, scrutinee, arms, &mut collect);
        }
        let outer = self.scope.clone();
        let checkpoint = self.p.diagnostics.len();
        let scrutinee_info = self.info_of(scrutinee).unwrap_or_default();
        let known = |c: &Checker, t: &Option<Ty>| -> bool {
            t.as_ref()
                .is_some_and(|t| crate::inference::inference_type_known(t, &c.inference_variables))
        };
        let mut result: Option<Ty> = expected.cloned();
        if !known(self, &result) {
            result = None;
        }
        // Infer from independently typed, reachable arms before checking
        // contextual values such as none or []. Keep each arm's checked lexical scope.
        // Each pass reads and updates one arm's state while `self` is borrowed mutably.
        #[allow(clippy::needless_range_loop)]
        for si in 0..states.len() {
            self.scope = states[si].scope.clone();
            if !states[si].normal {
                continue;
            }
            let arm = states[si].arm;
            match &arm.value {
                None => {
                    if result.is_none() {
                        result = Some(unit());
                    }
                }
                Some(value) => {
                    if !self.contextual(value) {
                        let info = self.arm_value(value, result.as_ref(), expected);
                        let t = info.t();
                        if result.is_none()
                            && t.id != "Never"
                            && crate::inference::inference_type_known(&t, &self.inference_variables)
                        {
                            result = Some(required_type(&t));
                            result_at = value.pos;
                        }
                        states[si].info = Some(info);
                    }
                }
            }
        }
        let (mut fall, mut breaks) = (false, false);
        // Each pass reads and updates one arm's state while `self` is borrowed mutably.
        #[allow(clippy::needless_range_loop)]
        for si in 0..states.len() {
            self.scope = states[si].scope.clone();
            let mut normal = states[si].normal;
            breaks = breaks || states[si].breaks;
            let arm = states[si].arm;
            if let Some(value) = &arm.value {
                let info = match states[si].info.take() {
                    Some(info) if info.t().kind == Kind::Function => {
                        self.check_expression(value, info, result.as_ref())
                    }
                    Some(info) => info,
                    None => self.arm_value(value, result.as_ref(), expected),
                };
                states[si].info = Some(info);
                if normal {
                    let info = states[si].info.as_ref().expect("arm info");
                    breaks = breaks || info.breaks;
                    normal = !info.no_return;
                }
            } else if normal
                && let Some(r) = &result
                && !compatible(&Some(unit()), r)
            {
                self.type_error(
                            arm.pos,
                            format!(
                                "match arm requires a final value of type {r}, because the arm at line {} ends in an expression and makes this match a value; end every arm with a value, or bind the unused result with 'let ignored = ...' so the match stays a statement",
                                result_at.line
                            ),
                        );
            }
            fall = fall || normal;
        }
        let result = match result {
            Some(r) => r,
            None => {
                if fall {
                    if !self.unknown_type {
                        self.type_error(
                            e.pos,
                            "cannot infer match result type; annotate the binding or give an arm an independently known type",
                        );
                    }
                    invalid()
                } else {
                    never()
                }
            }
        };
        if statement && self.p.diagnostics.len() > checkpoint {
            self.p.diagnostics.truncate(checkpoint);
            // A statement match discards its value. Arms that agree keep the
            // common type; arms that do not are checked independently.
            let (mut fall, mut breaks) = (false, false);
            for state in &states {
                self.scope = state.scope.clone();
                let mut normal = state.normal;
                breaks = breaks || state.breaks;
                if normal && let Some(value) = &state.arm.value {
                    let v = self.expression(value, None);
                    breaks = breaks || v.breaks;
                    normal = !v.no_return;
                }
                fall = fall || normal;
            }
            self.scope = outer;
            return Info {
                ty: Some(unit()),
                no_return: scrutinee_info.no_return || !fall,
                breaks: scrutinee_info.breaks || (!scrutinee_info.no_return && breaks),
                ..Info::default()
            };
        }
        self.scope = outer;
        Info {
            ty: Some(result),
            no_return: scrutinee_info.no_return || !fall,
            breaks: scrutinee_info.breaks || (!scrutinee_info.no_return && breaks),
            ..Info::default()
        }
    }

    fn arm_value(&mut self, value: &Expr, result: Option<&Ty>, expected: Option<&Ty>) -> Info {
        if let Some(r) = result {
            return self.expression(value, Some(r));
        }
        // Generic callback contexts can supply partial evidence, such as the
        // error type in Result[T, String], without fixing the match result.
        let inferred = self.infer(value, expected);
        self.check_expression(value, inferred, None)
    }

    /// Names what a module-level declaration is, for diagnostics about using
    /// it where a variable is required.
    pub(crate) fn symbol_description(&self, s: &SymRef) -> &'static str {
        let imported = s.module != self.current_file();
        if s.is_constant() && imported {
            "imported constant"
        } else if s.is_constant() {
            "constant"
        } else if s.kind == SymKind::Fn && imported {
            "imported function"
        } else if s.kind == SymKind::Fn {
            "function"
        } else if s.kind == SymKind::Type && imported {
            "imported type"
        } else if s.kind == SymKind::Type {
            "type"
        } else {
            "declaration"
        }
    }

    /// A declared field of a non-record standard type, whose member diagnostic
    /// already says the field cannot be reached.
    fn opaque_field(&self, receiver: Option<&Info>, name: Name) -> bool {
        let Some(r) = receiver else {
            return false;
        };
        let Some(t) = &r.ty else {
            return false;
        };
        if t.kind == Kind::Record {
            return false;
        }
        fields(t).iter().any(|f| f.name == name)
    }

    /// Records the scope at a requested name expression (editor queries).
    pub(crate) fn capture_scope(&mut self, e: &Expr) {
        let Some(marker) = &self.scope_marker else {
            return;
        };
        let text = match &e.kind {
            ExprKind::Name(t) => t.as_str(),
            ExprKind::Member { name, .. } => name.as_str(),
            ExprKind::Number(t) => t.as_str(),
            _ => return,
        };
        if text != marker {
            return;
        }
        let mut state = ScopeState::default();
        let mut hidden: HashSet<Name> = HashSet::new();
        let mut s = Some(self.scope.clone());
        while let Some(sc) = s {
            for (name, b) in sc.bindings.borrow().iter() {
                if hidden.insert(*name) {
                    state.bindings.insert(*name, b.clone());
                }
            }
            for (name, t) in sc.types.borrow().iter() {
                if hidden.insert(*name) {
                    state.types.insert(*name, t.clone());
                }
            }
            s = sc.parent.clone();
        }
        for (name, sym) in self.names.borrow().iter() {
            if !hidden.contains(name) {
                state.symbols.insert(*name, sym.clone());
            }
        }
        self.m().facts_mut().scopes.insert(e.id, state);
    }
}

/// The case names of an alternative type.
pub(crate) fn case_names(t: &Ty) -> Vec<String> {
    cases(t).iter().map(|c| c.name.to_string()).collect()
}

/// A case qualifier naming the matched alternative. A bare generic name
/// (Choice.Found) stands for every instantiation of Choice, while an explicit
/// one (Choice[Int].Found) must be the matched type.
fn same_qualifier(qualifier: &Ty, matched: &Ty, explicit: bool) -> bool {
    if explicit {
        return same(qualifier, matched);
    }
    qualifier.id == matched.id
}

/// A variable or a field path of variables: evaluating it again has no effect.
fn is_place_path(e: &Expr) -> bool {
    match &e.kind {
        ExprKind::Name(_) => true,
        ExprKind::Member { left, .. } => is_place_path(left),
        _ => false,
    }
}
