//! Calls: receivers, arguments, overlap checks and borrows returned from callees.

use super::*;

impl Walker<'_> {
    // ---------------------------------------------------------- calls

    /// A copy of a value of `t` made by the language rather than by a call: a type parameter in
    /// `t` must be declared `Clonable`, as a call of a copying method requires.
    pub(super) fn require_clonable(&mut self, e: &Expr, t: &Ty, what: &str) {
        if let Some(v) = unbounded_parameter(t) {
            self.error(
                e.pos,
                format!("{what} clones values of `{v_t}`, which may be a resource; declare `{v_t}: Clonable`", v_t = v.display(self.syms)),
            );
            return;
        }
        if !self.cx.classes.clonable(self.syms, t) {
            // A concrete type with one owner: an interface value, or a native without a `clone`.
            self.error(
                e.pos,
                format!(
                    "{what} clones `{t_t}`, which has one owner and cannot be cloned; use it in place"
                , t_t = t.display(self.syms)),
            );
        }
    }

    /// A conversion of `src` to the interface `e` has: a call through the interface hands each
    /// argument over only where the operation says `move`, and takes its result as a new value.
    /// An implementation that keeps a parameter the operation borrows, or returns a part of its
    /// receiver or arguments, would need a hidden copy, so the conversion is rejected and the
    /// remedy names the marker or the `.clone()` to write.
    pub(super) fn adapter_copies(&mut self, e: &Expr, src: &Ty) {
        let target = self.cx.m.ty(e);
        let Some(def) = &target.def else { return };
        let ops = def.operations.borrow().clone();
        for m in self.cx.methods.of(target.id, src.id) {
            let Some(decl) = &m.decl else {
                continue;
            };
            let mut bound = Subst::default();
            if !unify(&m.receiver, src, &variable_set(&m.variables), &mut bound) {
                continue;
            }
            let Some(summary) = self.cx.summaries.get(&(m.module, decl.id())) else {
                continue;
            };
            let op = decl.name();
            if !ops.iter().any(|o| o.name == op) {
                continue;
            }
            let method_t = format!("{}.{}", src.display(self.syms), self.syms.str(op));
            let borrowed: Vec<Name> = ops
                .iter()
                .filter(|o| o.name == op)
                .filter_map(|o| o.decl.as_ref().and_then(|d| d.func()))
                .flat_map(|f| {
                    f.params
                        .iter()
                        .filter(|p| !p.mutable && !p.moving)
                        .map(|p| p.name)
                })
                .collect();
            // The interface value keeps owning its data, so an operation that does not take the
            // receiver borrows it to the implementation.
            let lends_receiver = ops
                .iter()
                .filter(|o| o.name == op)
                .filter_map(|o| o.decl.as_ref())
                .any(|d| Summary::declared(d).receiver != ParamMode::Move);
            if summary.receiver == ParamMode::Move && lends_receiver {
                let text = self.expr_text(e);
                self.error(
                    e.pos,
                    format!("`{text}` becomes a `{target_t}`, but `{method_t}` keeps its receiver, which the interface borrows; declare `move fn` in both the interface and `{method_t}`, or keep `self.clone()`", target_t = target.display(self.syms)),
                );
            }
            for (name, mode) in &summary.params {
                if *mode != ParamMode::Move || !borrowed.contains(name) {
                    continue;
                }
                let text = self.expr_text(e);
                self.error(
                    e.pos,
                    format!("`{text}` becomes a `{target_t}`, but `{method_t}` keeps its `{name_t}`, which the interface borrows; declare `move {name_t}` in both the interface and `{method_t}`, or keep `{name_t}.clone()`", target_t = target.display(self.syms), name_t = self.syms.str(name)),
                );
            }
            if summary.result.returns_borrow && !summary.result.view {
                let text = self.expr_text(e);
                self.error(
                    e.pos,
                    format!("`{text}` becomes a `{target_t}`, but `{method_t}` returns a part of its {from}, and a call through an interface gets a new value; return `.clone()` of that part", target_t = target.display(self.syms), from = if summary.result.receiver { "receiver" } else { "arguments" }),
                );
            }
        }
    }

    /// A method the language calls on a value it only borrows (to show, compare, hash or encode
    /// it) that keeps its receiver or an argument would need a hidden copy at every such call,
    /// so it is rejected and the remedy names the `.clone()` to write.
    pub(super) fn lent_property_keeps(&mut self, summary: &Summary) {
        let c = self.cx.c;
        let Some(property) = self.cx.methods.lent_property((c.module.file, c.id())) else {
            return;
        };
        let what = match property {
            Builtin::Stringable => "shows a value as text",
            Builtin::Equal => "compares values with `==`",
            Builtin::Hashable => "hashes a value",
            Builtin::Comparable => "orders values",
            _ => "encodes a value as JSON",
        };
        let receiver = (summary.receiver == ParamMode::Move).then(|| self.syms.intern("self"));
        let kept = summary
            .params
            .iter()
            .filter(|(_, mode)| *mode == ParamMode::Move)
            .map(|(name, _)| *name);
        let method = self.syms.str(c.func.name());
        for name in receiver.into_iter().chain(kept) {
            let name_t = self.syms.str(name);
            self.error(
                c.func.pos(),
                format!("`{method}` keeps `{name_t}`, but the language calls it when it {what} and only borrows the value; keep a copy instead, such as `{name_t}.clone()`"),
            );
        }
    }

    /// A named function used as a value whose type borrows a parameter the function keeps would
    /// need a hidden copy of every argument; it is rejected, and the remedy is a written
    /// `.clone()` in a closure, or a function type that says `move`.
    pub(super) fn function_value_copies(
        &mut self,
        e: &Expr,
        module: Name,
        func: &crate::syntax::FuncRef,
    ) {
        let Some(summary) = self.cx.summaries.get(&(module, func.id())) else {
            return;
        };
        let fty = self.cx.m.ty(e);
        for (i, (name, mode)) in summary.params.iter().enumerate() {
            if *mode != ParamMode::Move {
                continue;
            }
            let Some(p) = fty.params.get(i) else { continue };
            // The function type hands the argument over.
            if p.moving {
                continue;
            }
            let text = self.expr_text(e);
            let callee = text.trim_end_matches("[..]");
            let name_t = self.syms.str(name);
            let args: Vec<String> = (0..fty.params.len()).map(|k| format!("a{k}")).collect();
            let call = args
                .iter()
                .enumerate()
                .map(|(k, a)| {
                    if k == i {
                        format!("{a}.clone()")
                    } else {
                        a.clone()
                    }
                })
                .collect::<Vec<_>>()
                .join(", ");
            let remedy = if self.cx.classes.class(self.syms, &p.ty) == Class::Resource {
                format!(
                    "the resource `{}` cannot be copied, so declare `move {name_t}` on `{callee}` and use a function type that says `move`",
                    p.ty.display(self.syms)
                )
            } else {
                format!(
                    "pass `fn {}: {callee}({call})` to copy it where you can see it, or use a function type that says `move`",
                    args.join(", ")
                )
            };
            self.error(
                e.pos,
                format!("`{text}` keeps its parameter `{name_t}`, but this function type borrows its arguments, so every call would need a hidden copy; {remedy}"),
            );
        }
    }

    pub(super) fn call(&mut self, e: &Expr, callee: &Expr, args: &[Argument], d: Demand) {
        let cx = self.cx;
        let mut modes = call_modes(self.syms, cx.m, e, args, cx.summaries);
        // `ok(x)` / `error(x)` kept as a reference (`view_wraps`) only reads its payload.
        if self.facts.view_wraps.contains(&e.id) || self.view_calls.contains(&e.id) {
            modes
                .arguments
                .iter_mut()
                .for_each(|m| *m = ParamMode::Borrow);
        }
        self.facts.calls.insert(e.id, modes.clone());
        // A native read borrowed in place (`s.value.get()`) is not the receiver's to hand over: an owning
        // position would copy it, and a value with no `clone` has no copy, so the caller's owner and the new
        // owner would both close it.
        if d == Demand::Move
            && self.class_of(e) != Class::Copy
            && !self.cx.classes.clonable(self.syms, &self.cx.m.ty(e))
            && !self.projected.contains(&e.id)
            && let Some((NativeBorrow::PayloadGet, recv)) = self.native_borrow_of(e)
            && self.is_place(recv)
        {
            let (text, from) = (self.expr_text(e), self.expr_text(recv));
            self.error(
                e.pos,
                format!("cannot move `{text}` out: it is read in place from `{from}`, which keeps it; it has one owner and no `clone`, so use it in place (`if value := {from}:`) or move `{from}` itself"),
            );
        }
        let name = self.call_name(callee);
        let member = method_callee(self.syms, self.cx.m, callee);
        let receiver_expr = match (&member.kind, cx.m.resolution(e)) {
            (ExprKind::Member { left, .. }, Resolution::Method(_)) => Some(&**left),
            _ => None,
        };
        if let (ExprKind::Member { name, .. }, Some(r)) = (&member.kind, receiver_expr)
            && self.syms.str(name) == "close"
            && let Resolution::Local(b) = cx.m.resolution(r)
        {
            self.closed.insert(b.uid);
            self.close_completions.insert((e.id, b.uid));
            self.close_receivers.insert(r.id);
        }
        // Argument markers: `var` exactly where the callee changes the argument.
        let param_names: Vec<Name> =
            cx.m.info(e)
                .arguments
                .clone()
                .unwrap_or_default()
                .iter()
                .map(|s| s.name)
                .collect();
        for (i, a) in args.iter().enumerate() {
            let mode = modes.arguments.get(i).copied().unwrap_or(ParamMode::Borrow);
            let param = param_names.get(i).copied().unwrap_or_else(|| n("?"));
            // A function type names its parameters by position (`_0`): say which argument.
            let positional =
                self.syms.str(param).strip_prefix('_').is_some_and(|rest| {
                    !rest.is_empty() && rest.bytes().all(|b| b.is_ascii_digit())
                });
            let which = if positional {
                format!("argument {} of `{name}`", i + 1)
            } else {
                format!(
                    "parameter `{param_t}` of `{name}`",
                    param_t = self.syms.str(param)
                )
            };
            match (mode, a.mutable) {
                (ParamMode::Mutate, false) if positional => self.error_fix(
                    a.value.pos,
                    format!("{which} is var in its type `{}`, so the call must say so; write `var {}`", self.cx.m.ty(callee).display(self.syms), self.expr_text(&a.value)),
                    insert_at(a.value.pos, "var "),
                ),
                (ParamMode::Mutate, false) => self.error_fix(
                    a.value.pos,
                    format!("{which} is declared var, so the call must say so; write `var {}`", self.expr_text(&a.value)),
                    insert_at(a.value.pos, "var "),
                ),
                (ParamMode::Borrow | ParamMode::Move, true) if positional => self.error_fix(
                    a.value.pos,
                    format!("`{name}` does not change {}: its type is `{}`; remove `var` from the argument", which.trim_end_matches(&format!(" of `{name}`")), self.cx.m.ty(callee).display(self.syms)),
                    DiagnosticFix {
                        pos: back(a.value.pos, 4),
                        end: a.value.pos,
                        replacement: String::new(),
                    },
                ),
                (ParamMode::Borrow | ParamMode::Move, true) => self.error_fix(
                    a.value.pos,
                    format!("`{name}` does not change its parameter `{param_t}`; remove `var` from the argument", param_t = self.syms.str(param)),
                    DiagnosticFix {
                        pos: back(a.value.pos, 4),
                        end: a.value.pos,
                        replacement: String::new(),
                    },
                ),
                _ => {}
            }
        }
        // Evaluate in order. What an operand keeps hold of for the whole call
        // is checked against the others afterwards.
        let mut operands: Vec<Logged> = Vec::new();
        let reported = self.diags.len();
        if let Some(r) = receiver_expr {
            if self.cx.m.info(e).native_str(self.syms) == "clone"
                && self.class_of(r) == Class::Resource
            {
                let text = self.expr_text(r);
                self.error(
                    e.pos,
                    format!("`{text}` holds a resource, which has one owner and cannot be cloned: a clone would be closed a second time; move it instead"),
                );
            } else if self.cx.m.info(e).native_str(self.syms) == "clone"
                && holds_function(&self.cx.m.ty(r))
            {
                let text = self.expr_text(r);
                self.error(
                    e.pos,
                    format!("`{text}` holds a function value, which owns its captures and has one owner, so it cannot be cloned; move it, or build the value again"),
                );
            }
            if self.cx.m.info(e).native_str(self.syms) == "clone"
                && let Some(param) = unbounded_parameter(&self.cx.m.ty(r))
                && !self.cx.classes.clonable(self.syms, &self.cx.m.ty(r))
            {
                let text = self.expr_text(r);
                let param_t = param.display(self.syms);
                self.error(
                    e.pos,
                    format!("`{text}` holds `{param_t}`, which may be a resource with one owner, so it cannot be cloned; bound it with `{param_t}: Clonable` or move the value"),
                );
            }
            let mut mode = modes.receiver.unwrap_or(ParamMode::Borrow);
            // A value with one owner taken out of a receiver that holds it (`o.get(default)` of
            // a resource, or of a native without a `clone`) is the receiver's one owner handing
            // it over, not a copy. A read in place (`xs.first()`) stays a borrow, and a type
            // parameter copies as its bound allows.
            let result_ty = self.cx.m.ty(e);
            let passthrough = match self.cx.m.resolution(e) {
                Resolution::Method(m) => wrapper_passthrough(&m, &self.cx.m.ty(r)),
                _ => None,
            };
            // A source callable the summary found to return a borrow (`fn G[T].get() T: return
            // self.v`) borrows its result whatever `T` is: the receiver stays the owner and the
            // result is a view, so only natives take a payload out of their receiver.
            let lends = result_borrow(cx.m, e, cx.summaries).returns_borrow;
            let takes_payload = !lends
                && self.class_of(e) != Class::Copy
                && !self.cx.classes.clonable(self.syms, &result_ty)
                && (unbounded_parameter(&result_ty).is_none() || self.wrapper_receiver(r))
                && ty_contains(&self.cx.m.ty(r), &result_ty);
            let takes_preserved =
                passthrough.is_some_and(|t| !self.cx.classes.clonable(self.syms, &t));
            // `get()` at the last use of an owned local hands its payload over even when the
            // payload is `Clonable` (`native_borrow_of` reads the same rule): a copy would make a
            // cursor walk (`n := cur.get()`, `cur = n.next`) clone the rest of the list per step.
            let takes_last_use = args.is_empty()
                && native_borrow(&self.cx.m.ty(r), &name, 0) == Some(NativeBorrow::PayloadGet)
                && (self.owned_local_at_last_use(r) || self.param_payload_take(e, r));
            if mode == ParamMode::Borrow
                && (takes_payload || takes_preserved || takes_last_use)
                && self.native_borrow_receiver(e).is_none()
            {
                let in_collection = {
                    let held_in = self.cx.m.ty(r);
                    held_in.is(Builtin::List)
                        || held_in.is(Builtin::Map)
                        || held_in.is(Builtin::Set)
                };
                if takes_payload && in_collection {
                    // A collection keeps its other elements, so it cannot hand one over: the result
                    // would be a second owner of the entry.
                    let (text, why) = (
                        self.expr_text(r),
                        clone_blocker(&result_ty).unwrap_or("it has one owner and no `clone`"),
                    );
                    self.error(
                        e.pos,
                        format!("`{name}` would copy `{result_ty_t}` out of `{text}`, which keeps its elements; {why}, so read it in place (`first()` or `if value := optional:`)", result_ty_t = result_ty.display(self.syms)),
                    );
                }
                mode = ParamMode::Move;
                if (takes_preserved || !args.is_empty())
                    && let Some(source) = self.native_borrow_receiver(r)
                {
                    // The receiver is itself a native borrow (`m.get(k)`, `xs.first()`): the
                    // element stays in its collection. Taking its payload into an owning
                    // result would copy it; a plain `get()` still borrows it in place.
                    let (from, text) = (self.expr_text(source), self.expr_text(r));
                    let why =
                        clone_blocker(&result_ty).unwrap_or("it has one owner and no `clone`");
                    self.error(
                        e.pos,
                        format!("`{name}` would take `{result_ty_t}` out of `{text}`, which only borrows an element of `{from}`; {why}, so read it in place (`if value := optional:`)", result_ty_t = result_ty.display(self.syms)),
                    );
                }
            }
            let held = self.held(r, mode);
            // `xs[i] = v` is a call of `[]=`: on a value no variable holds, nothing would keep the
            // store.
            if mode == ParamMode::Mutate
                && !self.is_place(r)
                && self.constant_root(r).is_none()
                && self.borrowed_call_root(r).is_none()
                && matches!(&callee.kind, ExprKind::Member { name, .. }
                    if self.syms.str(name) == ms_syntax::parser::INDEX_SET)
            {
                self.error(
                    r.pos,
                    "an assignment target must be a variable or a field path of one, like `xs[i]` or `p.items[i]`; a call result or literal is dropped after the store, so bind it to a var first",
                );
            }
            let closes = matches!(&callee.kind, ExprKind::Member { name, .. }
                if self.syms.str(name) == "close");
            self.receiver(r, mode, closes);
            operands.push((Operand::Receiver(r), held, Vec::new()));
        } else {
            self.callees.insert(callee.id);
            self.expr(callee, Demand::Read);
            if let Resolution::Local(_) = cx.m.resolution(callee) {
                // The call reads the function value where the local holds it, so an argument
                // that changes or moves that local would leave the call a dangling callee.
                let held = self.held(callee, ParamMode::Borrow);
                operands.push((Operand::Callee(callee), held, Vec::new()));
            }
        }
        let starts_promise = self.entry_call(e);
        // The key of an index store is consumed after the value is evaluated, so the value
        // is walked first and may read the key.
        let mut order: Vec<usize> = (0..args.len()).collect();
        let is_store = crate::ownership::live::is_index_store(callee, args);
        if is_store {
            order.reverse();
        }
        for i in order {
            let a = &args[i];
            let mut mode = modes.arguments.get(i).copied().unwrap_or(ParamMode::Borrow);
            if mode == ParamMode::Borrow && modes.retained.get(i).copied().unwrap_or(false) {
                // A native that wraps this argument in its result (`ok_or(cause)`) or may hand it back (`get(default)`) cannot copy a value that has no `clone`: the argument moves into the result.
                let (arg_ty, result_ty) = (self.cx.m.ty(&a.value), self.cx.m.ty(e));
                if self.class_of(&a.value) != Class::Copy
                    && !holds_variable(&arg_ty)
                    && !self.cx.classes.clonable(self.syms, &arg_ty)
                    && (crate::types::same(&arg_ty, &result_ty) || ty_contains(&result_ty, &arg_ty))
                {
                    mode = ParamMode::Move;
                }
            }
            let mut held = self.held(&a.value, mode);
            if i == 0 && is_store {
                // The key is held in place until the store, so the value cannot change it.
                held.extend(self.held(&a.value, ParamMode::Borrow));
            }
            if starts_promise && let ExprKind::Lambda(l) = &a.value.kind {
                // The entry of a promise reads what it captures, in place, while the promise lives;
                // one that is returned owns them (`returned_promises_own_captures`).
                self.entry_lambda = Some(a.value.id);
                let owned = self.escaped.contains(&a.value.id);
                held.extend(self.lambda(&a.value, l, owned));
            } else {
                held.extend(self.argument(a, mode, &modes, i));
            }
            operands.push((Operand::Argument(&a.value), held, Vec::new()));
        }
        // A promise handed to a container (`tasks.append(promise(fn: ...))`, or a list inside a
        // record, `acc.tasks.append(...)`) is kept by the local that owns the container: it reads
        // its captures until that local's scope ends.
        if let Some(r) = receiver_expr
            && let Some(holder) = self.container_root(r)
        {
            self.take_carried(holder.uid, holder.name);
            for a in args {
                let mut parts = Vec::new();
                collect_parts(
                    &a.value,
                    &|c| matches!(self.cx.m.resolution(c), Resolution::Constructor { .. }),
                    &mut parts,
                );
                let starts: Vec<&Expr> = parts.into_iter().filter(|p| self.entry_call(p)).collect();
                for part in starts {
                    let origins = self.entry_places(part);
                    if !origins.is_empty() {
                        self.active.push(Borrow {
                            holder: holder.uid,
                            holder_name: holder.name,
                            origins: origins.into_iter().map(|p| (p, false)).collect(),
                            pos: part.pos,
                            why: PROMISE_WHY.to_string(),
                        });
                    }
                }
            }
        }
        // An operand that already failed its own check is not reported twice. Only a held
        // place can clash, so the operands' inner changes are collected only when one is held.
        if self.diags.len() == reported && operands.iter().any(|(_, held, _)| !held.is_empty()) {
            for (operand, _, passing) in &mut operands {
                let x = match operand {
                    Operand::Receiver(x)
                    | Operand::Callee(x)
                    | Operand::Argument(x)
                    | Operand::Part(x) => *x,
                };
                *passing = self.nested_writes(x);
                for p in self.arm_writes(x) {
                    if !passing.contains(&p) {
                        passing.push(p);
                    }
                }
            }
            self.check_overlap(e.pos, &format!("`{name}`"), &operands);
        }
        // A checked native container read used in place borrows from its held receiver. Keep
        // that result borrowed for inline lowering too; a temporary source or owning use
        // keeps its existing boundary handling.
        if d != Demand::Move
            && self.class_of(e) != Class::Copy
            && self.native_borrow_receiver(e).is_some()
            && self.pure_origins(e).is_some()
        {
            self.facts.borrowed_reads.insert(e.id);
        }
        // A native read that borrows an element of its receiver cannot hand it to an owner: the
        // collection keeps the element, so the new owner would be a second one. A resource has
        // no copy and closes twice; a plain value needs `.clone()` (a value whose type is still
        // generic is copied when the function is instantiated, as its bound allows).
        if d == Demand::Move
            && let Some((kind, recv)) = self.native_borrow_of(e)
            && (kind != NativeBorrow::PayloadGet
                || self.native_borrow_receiver(recv).is_some()
                || self.pure_origins(recv).is_some())
        {
            let ty = self.cx.m.ty(e);
            let class = self.class_of(e);
            let owned_twice = class == Class::Resource
                || (class == Class::Move
                    && kind == NativeBorrow::ListGet
                    && self.is_place(recv)
                    && !holds_variable(&ty));
            if owned_twice {
                let (from, text) = (self.expr_text(recv), self.expr_text(e));
                let advice = match clone_blocker(&ty) {
                    Some(why) => format!("{why}, so use it in place"),
                    None => format!("store `.{CLONE}()` of it, or use it in place"),
                };
                self.error(
                    e.pos,
                    format!("`{text}` reads an element that `{from}` keeps, and this position would own it too; {advice}"),
                );
            }
        }
        // Results. A borrow-returning callee returns a reference into its arguments: holding it is a
        // borrow of them, storing or returning it needs a copy, and when a source is a
        // temporary the caller owns the result (lowering copies it out before the temporary
        // is dropped).
        let ret_borrow = result_borrow(cx.m, e, cx.summaries);
        if ret_borrow.returns_borrow && self.class_of(e) != Class::Copy {
            match self.pure_origins(e) {
                Some(origins) if d == Demand::Move => {
                    let mut roots: Vec<String> = origins
                        .iter()
                        .map(|p| self.syms.str(self.name_of(p.root)).to_string())
                        .collect();
                    roots.sort();
                    roots.dedup();
                    let ty = self.cx.m.ty(e);
                    if let Some(why) = clone_blocker(&ty) {
                        self.error(
                            e.pos,
                            format!(
                                "`{name}` returns a reference into `{}`, which this position would keep; {why}, so use it in place",
                                roots.join("`, `")
                            ),
                        );
                    } else {
                        self.error(
                            e.pos,
                            format!(
                                "`{name}` returns a reference into `{}`, which this position would keep; store `.{CLONE}()` of it, or use it in place",
                                roots.join("`, `")
                            ),
                        );
                    }
                }
                Some(_) if self.returns_borrow_through_view(e, &ret_borrow) => {
                    // The callee returns a borrow of a view temporary of a held value: the caller owns
                    // the result (the view itself when it comes back whole) and holds the value.
                    let how = self.owned_borrow(e, &ret_borrow, true);
                    self.cloned_borrow(e, &name, how);
                    self.facts.owned_borrows.insert(e.id, how);
                }
                Some(_) => {}
                None => {
                    let how = self.owned_borrow(e, &ret_borrow, false);
                    self.cloned_borrow(e, &name, how);
                    self.facts.owned_borrows.insert(e.id, how);
                }
            }
        }
        // `String.view` and `Bytes.view` borrow their receiver: a position that would keep the view
        // needs an owner, so it takes a `.clone()` of the view. A temporary receiver is copied out.
        if d == Demand::Move
            && let Some((NativeBorrow::Derived, source)) = self.native_borrow_of(e)
            && self.is_place(source)
        {
            self.error(
                e.pos,
                format!(
                    "`{name}` borrows `{}`, which this position would keep; store `.{CLONE}()` of it, or use it in place",
                    self.expr_text(source)
                ),
            );
        }
        // `xs.slice(a, b).get()`: the payload is the borrowed slice, so keeping it needs a `.clone()`.
        if d == Demand::Move
            && (name == "get" && args.is_empty() || exprs::payload_passthrough(&name, args.len()))
            && let Some(inner) = receiver_expr
            && let Some((NativeBorrow::Derived, source)) = self.native_borrow_of(inner)
            && self.is_place(source)
        {
            self.error(
                e.pos,
                format!(
                    "`slice` borrows `{}`, which this position would keep; store `.{CLONE}()` of it, or use it in place",
                    self.expr_text(source)
                ),
            );
        }
        if modes.returns_receiver && d != Demand::Discard {
            let recv = receiver_expr.map(|r| self.expr_text(r)).unwrap_or_default();
            self.error(
                e.pos,
                format!("`{name}` changes `{recv}` in place and its result cannot be used, because the collection has one owner; call it as a statement and keep using `{recv}`"),
            );
        }
    }

    /// A borrow-returning call over a temporary whose result is a part of it: the caller copies the part
    /// out before the temporary is dropped, which a value with one owner and no `clone` cannot be.
    pub(super) fn cloned_borrow(&mut self, e: &Expr, name: &str, how: OwnedBorrow) {
        if how != OwnedBorrow::Clone {
            return;
        }
        let t = self.cx.m.ty(e);
        if self.cx.classes.clonable(self.syms, &t) {
            return;
        }
        self.error(
            e.pos,
            format!("`{name}` returns a part of a temporary argument, which would be cloned out as the argument is dropped; `{t_t}` has one owner and no `clone`, so bind the argument first and use the result while that binding lives", t_t = t.display(self.syms)),
        );
    }

    /// How the caller owns the result of a borrow-returning call over a temporary: the whole of one
    /// temporary operand comes back (`id(make())`, `choose(first, second)` over function values
    /// made from named functions, or `relay(cause)` through a view temporary when
    /// `through_view`), so the caller keeps that temporary as the result instead of copying it;
    /// otherwise a copy is taken before the temporary is dropped.
    pub(super) fn owned_borrow(
        &self,
        e: &Expr,
        lend: &ResultBorrow,
        through_view: bool,
    ) -> OwnedBorrow {
        let whole = match (&lend.path, self.borrow_operands(e, lend)) {
            (Some((source, fields)), Some(operands))
                if fields.is_empty()
                    && operands.len() == 1
                    && (through_view || !self.is_place(operands[0])) =>
            {
                Some(*source)
            }
            _ => None,
        };
        match whole {
            Some(source) => OwnedBorrow::Whole(source),
            None => OwnedBorrow::Clone,
        }
    }

    pub(super) fn call_name(&self, callee: &Expr) -> String {
        match &callee.kind {
            ExprKind::Name(n) => self.syms.str(n).to_string(),
            ExprKind::Member { name, .. } => self.syms.str(name).to_string(),
            ExprKind::Apply { left, .. } => self.call_name(left),
            _ => "the callee".to_string(),
        }
    }

    /// The places an operand keeps hold of while the call runs: a variable
    /// changed or moved by it, or a value that is read in place. Copies and
    /// computed values are finished before the call starts.
    pub(super) fn held(&self, e: &Expr, mode: ParamMode) -> Vec<(Place, bool)> {
        if matches!(e.kind, ExprKind::Lambda(_)) {
            return Vec::new();
        }
        let write = mode != ParamMode::Borrow;
        if mode != ParamMode::Mutate && self.class_of(e) == Class::Copy {
            return Vec::new();
        }
        let places = if self.is_place(e) {
            self.pure_places(e)
        } else {
            self.pure_origins(e)
        };
        let mut held: Vec<(Place, bool)> = places
            .unwrap_or_default()
            .into_iter()
            .map(|p| (p, write))
            .collect();
        if self.is_place(e) {
            self.selecting_keys(e, &mut held);
        }
        held
    }

    /// The keys that select an element of a held place stay read for the whole call: a later
    /// operand that replaces a borrowed (non-Copy) key would leave the selection dangling.
    fn selecting_keys(&self, e: &Expr, out: &mut Vec<(Place, bool)>) {
        match &e.kind {
            ExprKind::Member { left, .. } => self.selecting_keys(left, out),
            ExprKind::Index { left, index }
            | ExprKind::Apply {
                left,
                value: Some(index),
                ..
            } => {
                self.selecting_keys(left, out);
                if self.class_of(index) != Class::Copy
                    && self.is_place(index)
                    && let Some(places) = self.pure_places(index)
                {
                    out.extend(places.into_iter().map(|p| (p, false)));
                }
            }
            _ => {}
        }
    }

    /// The places changed or moved by the calls inside `e`, closures excluded: a `var` or
    /// consumed argument place, or a receiver changed in place.
    pub(super) fn nested_writes(&mut self, e: &Expr) -> Vec<Place> {
        if let Some(v) = self.nested_cache.get(&e.id) {
            return v.clone();
        }
        let mut out = self.own_writes(e);
        let children: Vec<&Expr> = match &e.kind {
            ExprKind::Number(_)
            | ExprKind::Bool(_)
            | ExprKind::Void
            | ExprKind::Name(_)
            | ExprKind::Lambda(_) => Vec::new(),
            ExprKind::Text(parts) => parts
                .iter()
                .filter_map(|p| match p {
                    TextPart::Interp(x) => Some(x),
                    _ => None,
                })
                .collect(),
            ExprKind::Member { left, .. } | ExprKind::Probe(left) => vec![left],
            ExprKind::Unary { operand, .. } => vec![operand],
            ExprKind::Apply { left, value, .. } => {
                std::iter::once(&**left).chain(value.as_deref()).collect()
            }
            ExprKind::Index { left, index }
            | ExprKind::Binary {
                left, right: index, ..
            } => {
                vec![left, index]
            }
            ExprKind::List(items) => items.iter().collect(),
            ExprKind::Map(entries) => entries.iter().flat_map(|en| [&en.key, &en.value]).collect(),
            ExprKind::Call { callee, args } => std::iter::once(&**callee)
                .chain(args.iter().map(|a| &a.value))
                .collect(),
            ExprKind::Match { scrutinee, arms } => std::iter::once(&**scrutinee)
                .chain(arms.iter().filter_map(|a| a.value.as_ref()))
                .collect(),
        };
        for child in children {
            for p in self.nested_writes(child) {
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        }
        self.nested_cache.insert(e.id, out.clone());
        out
    }

    /// The places the statements of the `match` arms inside `e` assign, change or move. They run
    /// while a call's receiver, callee and borrowed arguments are held in place, so a call
    /// counts them with [`Self::nested_writes`]; a literal's parts are finished before the next
    /// part runs, so a literal does not.
    pub(super) fn arm_writes(&mut self, e: &Expr) -> Vec<Place> {
        let mut out: Vec<Place> = Vec::new();
        let mut stack = vec![e];
        while let Some(e) = stack.pop() {
            match &e.kind {
                ExprKind::Number(_)
                | ExprKind::Bool(_)
                | ExprKind::Void
                | ExprKind::Name(_)
                | ExprKind::Lambda(_) => {}
                ExprKind::Text(parts) => {
                    for p in parts {
                        if let TextPart::Interp(x) = p {
                            stack.push(x);
                        }
                    }
                }
                ExprKind::Member { left, .. } | ExprKind::Probe(left) => stack.push(left),
                ExprKind::Unary { operand, .. } => stack.push(operand),
                ExprKind::Apply { left, value, .. } => {
                    stack.push(left);
                    stack.extend(value.as_deref());
                }
                ExprKind::Index { left, index }
                | ExprKind::Binary {
                    left, right: index, ..
                } => stack.extend([&**left, &**index]),
                ExprKind::List(items) => stack.extend(items.iter()),
                ExprKind::Map(entries) => {
                    stack.extend(entries.iter().flat_map(|en| [&en.key, &en.value]))
                }
                ExprKind::Call { callee, args } => {
                    stack.push(callee);
                    stack.extend(args.iter().map(|a| &a.value));
                }
                ExprKind::Match { scrutinee, arms } => {
                    stack.push(scrutinee);
                    for arm in arms {
                        stack.extend(arm.value.as_ref());
                        for p in self.block_writes(&arm.body) {
                            if !out.contains(&p) {
                                out.push(p);
                            }
                        }
                    }
                }
            }
        }
        out
    }

    /// The places the statements of a block assign, change or move.
    pub(super) fn block_writes(&mut self, body: &[Stmt]) -> Vec<Place> {
        let mut out: Vec<Place> = Vec::new();
        let add = |out: &mut Vec<Place>, places: Vec<Place>| {
            for p in places {
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        };
        for s in body {
            match &s.kind {
                StmtKind::Assign { target, value, .. } => {
                    let written = match target {
                        AssignTarget::Name(_) => self
                            .cx
                            .m
                            .assigned(value)
                            .map(|b| vec![Place::local(b.uid)])
                            .unwrap_or_default(),
                        AssignTarget::Member(t) => self.pure_places(t).unwrap_or_default(),
                    };
                    add(&mut out, written);
                    add(&mut out, self.nested_writes(value));
                }
                StmtKind::Bind { value, .. } | StmtKind::Call(value) => {
                    add(&mut out, self.nested_writes(value));
                }
                StmtKind::Return(value) => {
                    if let Some(v) = value {
                        add(&mut out, self.nested_writes(v));
                    }
                }
                StmtKind::If {
                    cond,
                    body,
                    else_body,
                    ..
                } => {
                    add(&mut out, self.nested_writes(cond));
                    add(&mut out, self.block_writes(body));
                    add(&mut out, self.block_writes(else_body));
                }
                StmtKind::While { cond, body } => {
                    add(&mut out, self.nested_writes(cond));
                    add(&mut out, self.block_writes(body));
                }
                StmtKind::For { iter, body, .. } => {
                    add(&mut out, self.nested_writes(iter));
                    add(&mut out, self.block_writes(body));
                }
                StmtKind::Break | StmtKind::Continue => {}
            }
        }
        out
    }

    /// The places one call changes or moves through its `var` and consumed operands.
    pub(super) fn own_writes(&self, call: &Expr) -> Vec<Place> {
        let ExprKind::Call { callee, args } = &call.kind else {
            return Vec::new();
        };
        let modes = call_modes(self.syms, self.cx.m, call, args, self.cx.summaries);
        let mut written: Vec<(&Expr, ParamMode)> = Vec::new();
        let member = method_callee(self.syms, self.cx.m, callee);
        if let (ExprKind::Member { left, .. }, Resolution::Method(_)) =
            (&member.kind, self.cx.m.resolution(call))
            && modes.receiver == Some(ParamMode::Mutate)
        {
            written.push((left, ParamMode::Mutate));
        }
        for (i, a) in args.iter().enumerate() {
            let mode = modes.arguments.get(i).copied().unwrap_or(ParamMode::Borrow);
            if mode != ParamMode::Borrow {
                written.push((&a.value, mode));
            }
        }
        let mut out = Vec::new();
        for (operand, mode) in written {
            if !self.is_place(operand)
                || (mode == ParamMode::Move && self.class_of(operand) == Class::Copy)
            {
                continue;
            }
            for p in self.pure_places(operand).unwrap_or_default() {
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        }
        out
    }

    /// The operands of one operator, index, literal or interpolation are computed in order,
    /// and one that borrows or reads a place is held while the next runs; a change or move of
    /// that place by a later operand would leave a dangling reference.
    pub(super) fn parts_overlap(&mut self, pos: Pos, name: &str, parts: &[&Expr]) {
        if parts.len() < 2 {
            return;
        }
        let mut operands: Vec<Logged> = parts
            .iter()
            .map(|p| {
                (
                    Operand::Part(p),
                    self.held(p, ParamMode::Borrow),
                    Vec::new(),
                )
            })
            .collect();
        // Only a held place can clash, so the operands' inner changes matter only then.
        if operands.iter().all(|(_, held, _)| held.is_empty()) {
            return;
        }
        for (part, _, passing) in &mut operands {
            let Operand::Part(p) = part else {
                unreachable!()
            };
            *passing = self.nested_writes(p);
        }
        self.check_overlap(pos, name, &operands);
    }

    pub(super) fn receiver(&mut self, r: &Expr, mode: ParamMode, closes: bool) {
        match mode {
            ParamMode::Borrow => self.expr(r, Demand::Read),
            // Closing a field of `self` from inside `self`'s own close works on the field in
            // place: the field stays in `self`, and what the body leaves open closes after it.
            ParamMode::Move if closes && self.is_part_closed_in_place(r) => {
                self.expr(r, Demand::Read)
            }
            ParamMode::Move => self.expr(r, Demand::Move),
            ParamMode::Mutate => {
                if self.is_place(r) {
                    if let Some((info, _)) = self.place(r) {
                        self.mutate(r.pos, &info, "change");
                    }
                } else if let Some(call) = self.borrowed_call_root(r) {
                    // The result is a reference into another value, not a temporary of its own:
                    // changing it would change (or copy out of) the lender.
                    let text = self.expr_text(call);
                    self.error(
                        r.pos,
                        format!(
                            "cannot change the result of `{text}`: it is a read-only reference into another value; change the owner itself, or copy it into a `var` first with `.{CLONE}()`"
                        ),
                    );
                    self.expr(r, Demand::Read);
                } else if let Some(constant) = self.constant_root(r) {
                    // Each use of a constant runs its initializer, so the change would land on a
                    // fresh value and vanish.
                    self.error(
                        r.pos,
                        format!(
                            "cannot change constant `{constant}`: every use of a constant evaluates a fresh value, so the change would be lost; copy it into a `var` first, as in `var copy = {constant}.{CLONE}()`"
                        ),
                    );
                    self.expr(r, Demand::Read);
                } else {
                    // A temporary changed in place: nothing keeps it.
                    self.expr(r, Demand::Read);
                }
            }
        }
    }

    /// Whether `e` is a field of a value this function owns or may change, as in `conn.output.close()`
    /// or `self.input.close()` inside a close. Closing a field works on it in place: the field stays
    /// where it is, closed, and what is left open closes with its owner. Only a whole binding is
    /// consumed by `close`.
    fn is_part_closed_in_place(&self, e: &Expr) -> bool {
        let ExprKind::Member { left, .. } = &e.kind else {
            return false;
        };
        let Resolution::Local(b) = self.cx.m.resolution(root_name(left)) else {
            return false;
        };
        // A holder without a close of its own lets the field move out whole instead.
        let in_own_close = self.cx.c.func.method().is_some_and(|m| {
            m.consuming && m.func.params.is_empty() && self.syms.str(m.func.name) == "close"
        }) && self
            .cx
            .c
            .self_binding
            .as_ref()
            .is_some_and(|s| s.uid == b.uid);
        // A `var` method may close what its receiver holds in place, as a fixture hook does.
        let var_receiver = self
            .meta
            .get(&b.uid)
            .is_some_and(|m| m.is_receiver && m.perm == Perm::Mutable);
        (in_own_close || var_receiver || self.cx.classes.closes_itself(&self.cx.m.ty(left)))
            && self.field_path(left).is_some()
            && self.meta.get(&b.uid).is_some_and(|m| {
                matches!(m.perm, Perm::Immutable | Perm::Mutable) && m.lambda.is_none()
            })
    }

    /// The borrow-returning call a field, element or whole-value chain starts from: `id(a).items`
    /// is a part of `id(a)`, which is a reference into `a`.
    fn borrowed_call_root<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        match &e.kind {
            ExprKind::Call { .. } => self.returns_borrow(e).then_some(e),
            ExprKind::Member { left, .. }
            | ExprKind::Index { left, .. }
            | ExprKind::Apply {
                left,
                value: Some(_),
                ..
            } => self.borrowed_call_root(left),
            ExprKind::Unary {
                op: UnaryOp::Try,
                operand,
            } if self.cx.m.ty(operand).is(Builtin::Optional) => self.borrowed_call_root(operand),
            _ => None,
        }
    }

    /// The module constant a field, element or whole-value chain starts from, as written.
    fn constant_root(&self, e: &Expr) -> Option<String> {
        match &e.kind {
            ExprKind::Name(n) => matches!(self.cx.m.resolution(e), Resolution::Constant(_))
                .then(|| self.syms.str(n).to_string()),
            ExprKind::Member { left, .. }
            | ExprKind::Index { left, .. }
            | ExprKind::Apply {
                left,
                value: Some(_),
                ..
            } => self.constant_root(left),
            ExprKind::Unary {
                op: UnaryOp::Try,
                operand,
            } if self.cx.m.ty(operand).is(Builtin::Optional) => self.constant_root(operand),
            _ => None,
        }
    }

    /// Evaluates an argument; returns what a closure argument holds.
    pub(super) fn argument(
        &mut self,
        a: &Argument,
        mode: ParamMode,
        modes: &CallModes,
        index: usize,
    ) -> Vec<(Place, bool)> {
        // A native keeps this argument or hands it back in its result.
        let retained = modes.retained.get(index).copied().unwrap_or(false);
        match mode {
            ParamMode::Borrow => {
                if let ExprKind::Lambda(l) = &a.value.kind {
                    // Callbacks the callee runs and drops do not escape.
                    let escaping =
                        !modes.callbacks_borrowed || retained || self.escaped.contains(&a.value.id);
                    return self.lambda(&a.value, l, escaping);
                }
                self.expr(&a.value, Demand::Read);
                if retained
                    && self.cx.m.ty(&a.value).kind == Kind::Function
                    && let Resolution::Local(b) = self.cx.m.resolution(&a.value)
                {
                    // A function held by name is copied, so it stays usable here, but what the
                    // callee keeps must outlive this statement: its lambda and parameter escape.
                    if self.meta[&b.uid].parameter.is_some() {
                        self.consumed.insert(b.uid);
                    }
                    if let Some(l) = self.meta[&b.uid].lambda {
                        self.escaped.insert(l);
                    }
                }
            }
            ParamMode::Move => {
                self.move_note = modes.consumed_by.get(index).copied().flatten();
                self.expr(&a.value, Demand::Move);
                self.move_note = None;
            }
            ParamMode::Mutate => {
                if self.is_place(&a.value) {
                    if let Some((info, _)) = self.place(&a.value) {
                        self.mutate(a.value.pos, &info, "change");
                    }
                } else {
                    self.error(
                        a.value.pos,
                        "a var argument must be a variable or a field of one, not a computed value; bind the value to a var first",
                    );
                    self.expr(&a.value, Demand::Read);
                }
            }
        }
        Vec::new()
    }

    /// A changed place may not overlap another operand of the same call.
    /// An operand's description, built only for a diagnostic: spelling a long call chain on every
    /// call would be quadratic in the chain.
    pub(super) fn operand_text(&self, o: &Operand) -> String {
        match o {
            Operand::Receiver(e) => format!("the receiver `{}`", self.expr_text(e)),
            Operand::Callee(e) => format!("the called value `{}`", self.expr_text(e)),
            Operand::Argument(e) if matches!(e.kind, ExprKind::Lambda(_)) => {
                format!("the closure at {}", self.at(e.id))
            }
            Operand::Argument(e) => format!("argument `{}`", self.expr_text(e)),
            Operand::Part(e) => format!("operand `{}`", self.expr_text(e)),
        }
    }

    /// `context` names the call or expression the operands belong to, already quoted. A place an
    /// operand holds for the whole call clashes with a change of it by another operand: one held
    /// for the call, or one finished while that operand was computed, which leaves a held read
    /// or a held part dangling (a whole variable passed `var` keeps its slot).
    pub(super) fn check_overlap(&mut self, pos: Pos, context: &str, operands: &[Logged]) {
        for (i, (label, log, passing)) in operands.iter().enumerate() {
            let writes = log
                .iter()
                .filter(|(_, w)| *w)
                .map(|(p, _)| (p, true))
                .chain(passing.iter().map(|p| (p, false)));
            for (place, held) in writes {
                let clash = operands.iter().enumerate().find(|(j, (_, other, _))| {
                    *j != i
                        && other
                            .iter()
                            .any(|(q, w)| q.overlaps(place) && (held || !*w || !q.path.is_empty()))
                });
                if let Some((_, (other, _, _))) = clash {
                    let (label, other) = (self.operand_text(label), self.operand_text(other));
                    self.error(
                        pos,
                        format!("{label} of {context} is moved or changed in place but overlaps {other}; a moved or changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first"),
                    );
                    return;
                }
            }
        }
    }
}

/// The name expression a chain of field accesses starts from.
fn root_name(mut e: &Expr) -> &Expr {
    while let ExprKind::Member { left, .. } = &e.kind {
        e = left;
    }
    e
}
