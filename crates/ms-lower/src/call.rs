//! Calls: source functions and methods, constructors, natives.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::hir::{CallView, Callable, Resolution};
use ms_check::types::{self as ct, Subst};
use ms_mir::ir::{Mode, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::*;
use std::rc::Rc;

/// Arguments evaluated in written order and placed by parameter position.
pub(crate) struct Args {
    pub slots: Vec<Option<Val>>,
    /// For `var` parameters: the written place that receives the updated value.
    pub places: Vec<Option<Expr>>,
}

impl<'a> FnLower<'a> {
    pub fn call_expr(&mut self, e: &Expr) -> Result<Val, Error> {
        let saved = self.scope_override;
        self.scope_override = self.call_evidence(e);
        let out = self.call_expr_in_scope(e);
        self.scope_override = saved;
        out
    }

    /// The module providing the evidence of a call written with the instance's type
    /// variables: its type arguments, receiver, arguments and result decide.
    fn call_evidence(&self, e: &Expr) -> Option<ct::Name> {
        let view = self.hir.call(e)?;
        let mut pre: Vec<ct::Ty> = view.type_args.iter().flatten().cloned().collect();
        pre.push(self.hir.ty(e));
        if let Some(r) = self.receiver_expr(e) {
            pre.push(self.hir.ty(r));
        }
        pre.extend(view.arguments.iter().map(|a| self.hir.ty(a.expr)));
        self.evidence_of(&pre)
    }

    fn call_expr_in_scope(&mut self, e: &Expr) -> Result<Val, Error> {
        let Some(view) = self.hir.call(e) else {
            return Err(Error::new("call without resolution"));
        };
        let out = match &view.target {
            Resolution::Function(sym) if sym.native.as_str().is_empty() => {
                let c = self.callable_of_decl(sym.module, sym.decl.as_ref().map(|d| d.id()))?;
                let vars = sym.variables();
                let subst = self.callee_subst(&vars, &view.type_args)?;
                if let Some(v) = self.try_default_call(&view, &c, &subst, e)? {
                    v
                } else {
                    let names = self.param_names(&c);
                    let args = self.eval_args(&view, &names, &c, &subst, None, e.pos)?;
                    self.call_callable(&c, &subst, args, e)?
                }
            }
            Resolution::Constant(sym) => {
                let c = self.callable_of_decl(sym.module, sym.decl.as_ref().map(|d| d.id()))?;
                self.call_callable(
                    &c,
                    &Subst::new(),
                    Args {
                        slots: Vec::new(),
                        places: Vec::new(),
                    },
                    e,
                )?
            }
            Resolution::Function(sym) => {
                let params = sym
                    .ty
                    .borrow()
                    .as_ref()
                    .map(|t| t.params.clone())
                    .unwrap_or_default();
                self.native_function(e, &view, sym.native.as_str(), &params, sym)?
            }
            // `x.get()(7)`: the callee is itself a call, so this one calls its function value.
            Resolution::Method(_) if self.receiver_expr(e).is_none() => {
                self.call_value(e, &view)?
            }
            Resolution::Method(m) => self.method_call(e, &view, m)?,
            Resolution::Constructor { ty, case } => self.construct(e, &view, ty, *case)?,
            Resolution::Local(_) | Resolution::Value => self.call_value(e, &view)?,
            _ => return Err(Error::new("unsupported call target")),
        };
        if !self.dead && self.ety(e).id == "Never" {
            self.b.unreachable();
            self.terminated();
        }
        Ok(out)
    }

    pub fn callable_of_decl(
        &self,
        module: ct::Name,
        id: Option<ms_syntax::NodeId>,
    ) -> Result<Rc<Callable>, Error> {
        let id = id.ok_or_else(|| Error::new("symbol without declaration"))?;
        self.cx
            .callables
            .get(&(module, id))
            .cloned()
            .ok_or_else(|| Error::new("callee not found"))
    }

    /// Binds the callee's type variables to the (caller-substituted) type arguments.
    pub fn callee_subst(
        &mut self,
        vars: &[ct::Ty],
        type_args: &[Option<ct::Ty>],
    ) -> Result<Subst, Error> {
        let mut s = Subst::new();
        for (i, v) in vars.iter().enumerate() {
            let Some(Some(a)) = type_args.get(i) else {
                return Err(Error::new(format!("cannot infer type argument {}", v.name)));
            };
            s.insert(v.id, ct::sub(a, &self.subst));
        }
        Ok(s)
    }

    pub fn param_names(&self, c: &Callable) -> Vec<ct::Name> {
        c.parameters.iter().map(|b| b.name).collect()
    }

    /// Evaluates the written arguments and places them by parameter name.
    pub fn eval_args(
        &mut self,
        view: &CallView<'_>,
        names: &[ct::Name],
        callee: &Callable,
        subst: &Subst,
        recv: Option<Val>,
        call_pos: ms_syntax::Pos,
    ) -> Result<Args, Error> {
        let mut slots: Vec<Option<Val>> = vec![None; names.len()];
        let mut places: Vec<Option<Expr>> = vec![None; names.len()];
        let vars = self.cx.var_positions(callee);
        let offset = usize::from(callee.self_binding.is_some());
        let mut read_at = Vec::new();
        for (n, a) in view.arguments.iter().enumerate() {
            let at = self.b.current();
            let x = self.expr(a.expr)?;
            if self.dead {
                return Ok(Args { slots, places });
            }
            let later_try = view.arguments[n + 1..]
                .iter()
                .any(|l| crate::mutation::has_try(l.expr));
            let x = match &a.wrap_optional {
                Some(opt) => {
                    let o = self.owned(x);
                    let _ = opt;
                    let v = self.b.opt_some(o);
                    Val { v, own: true }
                }
                None => x,
            };
            let x = if later_try { self.hold_temp(x) } else { x };
            let idx = names
                .iter()
                .position(|n| *n == a.slot.name)
                .ok_or_else(|| Error::new(format!("no parameter {}", a.slot.name)))?;
            if vars.contains(&(idx + offset)) {
                places[idx] = Some(a.expr.clone());
            }
            slots[idx] = Some(x);
            read_at.push((idx, a.expr, at));
        }
        for (idx, expr, at) in read_at {
            let Some(x) = slots[idx] else {
                continue;
            };
            // A `var` argument is the variable itself: it sees what its siblings changed.
            slots[idx] = Some(
                if vars.contains(&(idx + offset)) && !x.own && self.is_place(expr) {
                    self.expr(expr)?
                } else {
                    self.refresh(expr, x, at)?
                },
            );
        }
        for i in 0..slots.len() {
            if slots[i].is_none() {
                // Defaults execute in the callee's lexical frame even though their
                // instructions live in the caller. Reuse inline-frame metadata so
                // faults retain both frames without runtime call bookkeeping.
                let parent = self.source_scope;
                let file = self.b.m.add_file(callee.module.file.as_str());
                let name = if let DeclKind::Impl(implementation) = &callee.func.decl.decl().kind {
                    format!("{}.{}", implementation.receiver.name(), callee.name)
                } else {
                    callee.name.to_string()
                };
                let call_line = self.stmt_pos.unwrap_or(call_pos).line;
                let scopes = &mut self.b.func_mut().scopes;
                scopes.push(ms_mir::ir::Scope {
                    name,
                    file,
                    parent,
                    call_line,
                });
                self.source_scope = scopes.len() as u32;
                let result = self.default_argument(callee, i, subst, &mut slots, recv);
                self.source_scope = parent;
                let d = result?;
                slots[i] = Some(d);
            }
        }
        Ok(Args { slots, places })
    }

    /// Whether a place permits writeback: an owned local or shared mutable storage.
    /// A read-only borrow (a parameter of a default frame) takes no update.
    fn place_is_owned(&mut self, place: &Expr) -> bool {
        let Some(uid) = crate::mutation::place_root(&self.hir, place) else {
            return false;
        };
        let uid = self.aliases.get(&uid).map_or(uid, |a| a.root.uid);
        self.locals.get(&uid).is_some_and(|l| {
            l.slot.is_some() || !self.needs_drop(l.ty) || self.b.var_mode(l.var) == Mode::Own
        })
    }

    /// Reads a borrowed place again after evaluating a sibling: a branch passes the variable's
    /// value along, and a call that took the variable (moved it into a slot) replaced it, so the
    /// earlier read no longer stands.
    pub(crate) fn refresh(
        &mut self,
        e: &Expr,
        x: Val,
        at: ms_mir::ir::Block,
    ) -> Result<Val, Error> {
        // A value that needs no drop stays valid, and keeps the value of its written position.
        let _ = at;
        if x.own || self.dead || !self.needs_drop(self.ty_of(x.v)) || !self.is_place(e) {
            return Ok(x);
        }
        self.expr(e)
    }

    /// Registers an owned value as a temporary and views it as a borrow, so a `try` evaluated
    /// later in the same call that returns early still releases it.
    pub(crate) fn hold_temp(&mut self, x: Val) -> Val {
        Val {
            v: self.borrow(x),
            own: false,
        }
    }

    /// The default of an omitted parameter, written in the callee's scope.
    pub(crate) fn default_argument(
        &mut self,
        callee: &Callable,
        i: usize,
        subst: &Subst,
        earlier: &mut [Option<Val>],
        recv: Option<Val>,
    ) -> Result<Val, Error> {
        let params = callee
            .func
            .func()
            .map(|f| f.params.as_slice())
            .unwrap_or(&[]);
        let binding = &callee.parameters[i];
        let default = params.get(i).and_then(|p| p.default.as_ref());
        let ty = ct::sub(&binding.ty, subst);
        let mty = self.cx.lower_ty(self.b.m, &ty)?;
        let Some(d) = default else {
            if ty.is_std("Optional") {
                let v = self.b.opt_none(mty);
                return Ok(Val { v, own: false });
            }
            if let Some((decl, sig)) = self.contract_operation(callee) {
                return self.contract_default(decl.as_ref(), &sig, i);
            }
            return Err(Error::new(format!("missing argument {}", binding.name)));
        };
        // `none` in a bundled declaration carries no checked expression.
        if matches!(&d.kind, ExprKind::Name(n) if n.as_str() == "none") && ty.is_std("Optional") {
            let v = self.b.opt_none(mty);
            return Ok(Val { v, own: false });
        }
        let saved_hir = self.hir.clone();
        let saved_subst = std::mem::replace(&mut self.subst, subst.clone());
        let saved_file = self.file;
        self.hir = self.cx.module(callee.module.file)?;
        self.file = self.b.m.add_file(callee.module.file.as_str());
        if let (Some(b), Some(r)) = (&callee.self_binding, recv) {
            self.bind_borrowed(b, r.v);
        }
        // A `var` parameter is a copy the default may change; the changed value is what the
        // call passes on.
        let offset = usize::from(callee.self_binding.is_some());
        let vars = self.cx.var_positions(callee);
        let mut changed = Vec::new();
        for (j, slot) in earlier.iter().enumerate().take(i) {
            let Some(v) = *slot else {
                continue;
            };
            let binding = callee.parameters[j].clone();
            if vars.contains(&(j + offset)) {
                let ty = self.ty_of(v.v);
                let o = self.owned(v);
                let var = self.b.declare_var(ty, Mode::Own);
                self.b.def_var(var, o);
                self.locals.insert(
                    binding.uid,
                    crate::func::Local {
                        var,
                        ty,
                        slot: None,
                    },
                );
                changed.push((j, var));
            } else {
                self.bind_borrowed(&binding, v.v);
            }
        }
        // A default reports its own position, not the caller statement\'s.
        let saved_stmt = self.stmt_pos.take();
        let r = self.expr(d);
        for (j, var) in changed {
            if !self.dead {
                let v = self.b.use_var(var);
                earlier[j] = Some(Val { v, own: true });
            }
        }
        self.stmt_pos = saved_stmt;
        self.hir = saved_hir;
        self.subst = saved_subst;
        self.file = saved_file;
        r
    }

    /// Calls an instance of a source callable with borrowed arguments.
    pub fn call_callable(
        &mut self,
        c: &Rc<Callable>,
        subst: &Subst,
        args: Args,
        e: &Expr,
    ) -> Result<Val, Error> {
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        // A `ref` function the checker proved lends on every path hands back a borrow of its
        // argument instead of a copy.
        let lent = self.cx.lenders.contains(&(c.module.file, c.id()))
            && c.func.func().is_some_and(|f| !f.body.is_empty());
        let owned_mask = if lent { None } else { self.cx.owned_mask(c) };
        let fid = if lent {
            let scope = self.evidence();
            self.cx.function_lent(self.b.m, c, subst, scope)?
        } else if owned_mask.is_some() {
            let scope = self.evidence();
            self.cx.function_owned(self.b.m, c, subst, scope)?
        } else {
            self.instance(c, subst)?
        };
        let vars = self.cx.var_positions(c);
        // A changed parameter is moved into a slot the callee takes from and puts back into.
        let mut slots_out: Vec<(usize, Value, MTy, bool)> = Vec::new();
        let mut vals: Vec<Value> = Vec::new();
        // The only changed parameter is a field or list element of an owned variable: the callee
        // takes it out of its place and puts it back, instead of working on a copy.
        let mut in_place: Option<(usize, Expr, MTy)> = None;
        for (i, a) in args.slots.into_iter().flatten().enumerate() {
            if !vars.contains(&i) {
                // A consumed parameter takes the value itself: a copy only when `a` is a borrow.
                if owned_mask.as_ref().is_some_and(|mask| mask[i]) {
                    vals.push(self.owned(a));
                } else {
                    vals.push(self.borrow(a));
                }
                continue;
            }
            let ty = self.ty_of(a.v);
            // A variable that lives in memory (a closure shares it) is passed by its own slot:
            // the callee changes it in place, so nothing is copied in or written back.
            if !a.own
                && let Some(slot) = args
                    .places
                    .get(i)
                    .cloned()
                    .flatten()
                    .filter(|p| matches!(p.kind, ExprKind::Name(_)))
                    .and_then(|p| match self.hir.resolution(&p) {
                        ms_check::hir::Resolution::Local(b)
                            if !self.aliases.contains_key(&b.uid) =>
                        {
                            self.locals.get(&b.uid).and_then(|l| l.slot)
                        }
                        _ => None,
                    })
            {
                vals.push(slot);
                continue;
            }
            if vars.len() == 1
                && !a.own
                && let Some(place) = args.places.get(i).cloned().flatten()
                && !matches!(place.kind, ExprKind::Name(_))
                && self.is_place(&place)
                && self.place_is_owned(&place)
            {
                vals.push(a.v);
                in_place = Some((i, place, ty));
                continue;
            }
            let moved = !a.own
                && args
                    .places
                    .get(i)
                    .cloned()
                    .flatten()
                    .and_then(|p| match self.hir.resolution(&p) {
                        ms_check::hir::Resolution::Local(b)
                            if matches!(p.kind, ExprKind::Name(_)) =>
                        {
                            Some(b.uid)
                        }
                        _ => None,
                    })
                    .is_some_and(|uid| {
                        // A variable in memory (a closure shares it) has no value to move.
                        let owned = self.locals.get(&uid).is_some_and(|l| {
                            l.slot.is_none() && self.b.var_mode(l.var) == Mode::Own
                        });
                        owned && crate::mutation::uses_of(&self.hir, e, uid) == 1
                    });
            let x = if moved { a.v } else { self.owned(a) };
            let slot = self
                .b
                .emit(Op::Slot, &[], ms_mir::ir::Imm::Ty(ty), Some(MTy::PTR))
                .expect("slot");
            self.move_into(slot, x);
            slots_out.push((i, slot, ty, moved));
            vals.push(slot);
        }
        self.at(e.pos);
        let v = if let Some((i, place, ty)) = in_place {
            let mut result = None;
            self.place_update(&place, &mut |s, old| {
                let slot =
                    s.b.emit(Op::Slot, &[], ms_mir::ir::Imm::Ty(ty), Some(MTy::PTR))
                        .expect("slot");
                s.move_into(slot, old);
                vals[i] = slot;
                result = Some(s.b.call(fid, &vals));
                Ok(s.move_out(slot, ty))
            })?;
            result.expect("call emitted")
        } else {
            self.b.call(fid, &vals)
        };
        for (p, slot, ty, moved) in slots_out {
            let new = self.move_out(slot, ty);
            let target = args.places.get(p).cloned().flatten();
            match target {
                Some(place) if self.is_place(&place) && self.place_is_owned(&place) => {
                    let mut new = Some(new);
                    self.place_update(&place, &mut |s, old| {
                        // A moved value has already left the variable.
                        if !moved {
                            s.drop_value(old);
                        }
                        Ok(new.take().expect("single use"))
                    })?;
                }
                _ => self.drop_value(new),
            }
        }
        Ok(self.val(v, !lent))
    }

    // ------------------------------------------------------------- methods

    /// The receiver expression of a method call.
    pub fn receiver_expr<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let ExprKind::Call { callee, .. } = &e.kind else {
            return None;
        };
        let mut c: &Expr = callee;
        if let ExprKind::Apply { left, .. } = &c.kind {
            c = left;
        }
        match &c.kind {
            ExprKind::Member { left, .. } => Some(left),
            _ => None,
        }
    }

    fn method_call(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        m: &ct::MethodRef,
    ) -> Result<Val, Error> {
        let recv_expr = self
            .receiver_expr(e)
            .ok_or_else(|| Error::new("method call without receiver"))?;
        let native = m.native.as_str();
        if native.is_empty() {
            return self.source_method_call(e, view, m, recv_expr);
        }
        if native == "contract" {
            return self.contract_call(e, view, m, recv_expr);
        }
        let method = m
            .name()
            .map(|n| n.to_string())
            .unwrap_or_else(|| native.rsplit('/').next().unwrap_or(native).to_string());
        if crate::sharedbuilder::builder_kind(&m.receiver).is_some() {
            return self.builder_method(e, view, m, recv_expr, &method);
        }
        if ms_check::effects::is_text_builder(&m.receiver) && method == "build" {
            return self.text_builder_build(e, recv_expr);
        }
        if m.receiver.is_std("Shared") {
            return self.shared_method(e, view, recv_expr, &method);
        }
        if ms_check::effects::collection_mutation(m) {
            return self.mutator_call(e, view, m, recv_expr, &method);
        }
        if let Some(v) = self.lent_result(e)? {
            return Ok(v);
        }
        if let Some(v) = self.list_end_lent(e, recv_expr, &method)? {
            return Ok(v);
        }
        if let Some(v) = self.map_get_chain(e, view, recv_expr, &method)? {
            return Ok(v);
        }
        let recv = self.expr(recv_expr)?;
        if self.dead {
            return Ok(recv);
        }
        let trim_view = match native {
            "string/trim" => Some("msrt_string_trim_view"),
            "string/trim_start" => Some("msrt_string_trim_start_view"),
            "string/trim_end" => Some("msrt_string_trim_end_view"),
            _ => None,
        };
        if let Some(sym) = trim_view
            && !recv.own
            && self.is_place(recv_expr)
        {
            return Ok(self.trim_view(sym, recv));
        }
        self.native_method(e, view, m, recv_expr, recv)
    }

    /// `xs.first()` or `xs.last()` lent by a `ref` function: a view of the element, not a copy.
    fn list_end_lent(
        &mut self,
        e: &Expr,
        recv_expr: &Expr,
        name: &str,
    ) -> Result<Option<Val>, Error> {
        if !matches!(name, "first" | "last")
            || !self.lent_return
            || self.lent_expr != Some(e as *const Expr as usize)
            || !self.ety(recv_expr).is_std("List")
        {
            return Ok(None);
        }
        let opt_ty = self.emty(e)?;
        let lv = self.expr(recv_expr)?;
        if self.dead {
            return Ok(Some(lv));
        }
        let lv = self.borrow(lv);
        let len = self.b.list_len(lv);
        let zero = self.b.iconst(0);
        let empty = self.b.icmp(ms_mir::ir::Cc::Eq, len, zero);
        let out = self.b.declare_var(opt_ty, ms_mir::ir::Mode::Borrow);
        let (absent, present, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br_if(empty, absent, &[], present, &[]);
        self.b.seal_block(absent);
        self.b.seal_block(present);
        self.enter(absent);
        let none = self.b.opt_none(opt_ty);
        self.b.def_var(out, none);
        self.b.br(join, &[]);
        self.enter(present);
        let at = self.b.iconst(if name == "first" { 0 } else { -1 });
        let elem = self.b.list_get(lv, at);
        let some = self.b.opt_view(elem);
        self.b.def_var(out, some);
        self.b.br(join, &[]);
        self.b.seal_block(join);
        self.enter(join);
        let v = self.b.use_var(out);
        Ok(Some(Val { v, own: false }))
    }

    /// `text.trim()` (or `trim_start`, `trim_end`) on a string that stays where it is: a view into it, nothing allocated. The
    /// checker keeps `text` unchanged while the result lives and asks for `.clone()` wherever
    /// the result would be kept.
    fn trim_view(&mut self, sym: &str, text: Val) -> Val {
        let s = self.borrow(text);
        let slot = self
            .b
            .emit(Op::Slot, &[], ms_mir::ir::Imm::Ty(MTy::STR), Some(MTy::PTR))
            .expect("slot");
        self.call_runtime(sym, &[s, slot], MTy::UNIT)
            .expect("trim view");
        let v = self
            .b
            .emit(
                Op::Load,
                &[slot],
                ms_mir::ir::Imm::Ty(MTy::STR),
                Some(MTy::STR),
            )
            .expect("load");
        self.views.insert(v);
        Val { v, own: false }
    }

    fn source_method_call(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        m: &ct::MethodRef,
        recv_expr: &Expr,
    ) -> Result<Val, Error> {
        let decl = m
            .decl
            .as_ref()
            .ok_or_else(|| Error::new("method without declaration"))?;
        let c = self.callable_of_decl(m.module, Some(decl.id()))?;
        let rt = self.ety(recv_expr);
        let mut subst = Subst::new();
        // The checked reference fixes an implementation's variables; its declaration keeps them.
        let declared = self
            .cx
            .methods
            .iter()
            .find(|d| d.module == m.module && d.decl.as_ref().map(|x| x.id()) == Some(decl.id()))
            .unwrap_or(m);
        let vars = ct::variable_set(&declared.variables);
        if !ct::unify(&declared.receiver, &rt, &vars, &mut subst) {
            return Err(Error::new("cannot bind method receiver type"));
        }
        // The method's own type parameters come last; the call's type arguments bind them in order.
        let own = declared.variables.len() - c.func.func().map_or(0, |f| f.type_params.len());
        for (i, v) in declared.variables[own..].iter().enumerate() {
            if let (false, Some(Some(a))) = (subst.contains_key(&v.id), view.type_args.get(i)) {
                subst.insert(v.id, ct::sub(a, &self.subst));
            }
        }
        let recv = self.expr(recv_expr)?;
        if self.dead {
            return Ok(recv);
        }
        let recv = if view
            .arguments
            .iter()
            .any(|a| crate::mutation::has_try(a.expr))
        {
            self.hold_temp(recv)
        } else {
            recv
        };
        let names = self.param_names(&c);
        let at = self.b.current();
        let args = self.eval_args(view, &names, &c, &subst, Some(recv), e.pos)?;
        if self.dead {
            return Ok(recv);
        }
        let recv = self.refresh(recv_expr, recv, at)?;
        let mut all = vec![Some(recv)];
        all.extend(args.slots);
        let mut places = vec![
            self.cx
                .var_positions(&c)
                .contains(&0)
                .then(|| recv_expr.clone()),
        ];
        places.extend(args.places);
        self.call_callable(&c, &subst, Args { slots: all, places }, e)
    }

    /// The implementation of a contract operation for a concrete receiver type.
    pub(crate) fn contract_impl(&self, m: &ct::MethodRef, recv: &ct::Ty) -> Option<ct::MethodRef> {
        let name = m.name()?;
        let contract = m.contract.as_ref()?;
        let scope = self.evidence();
        self.cx
            .methods
            .iter()
            .find(|mm| {
                mm.name() == Some(name)
                    && !mm.id.as_str().is_empty()
                    && mm.visible_in(scope)
                    && mm.contract.as_ref().is_some_and(|c| c.id == contract.id)
                    && ct::unify(
                        &mm.receiver,
                        recv,
                        &ct::variable_set(&mm.variables),
                        &mut ct::Subst::new(),
                    )
            })
            .cloned()
    }

    fn contract_call(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        m: &ct::MethodRef,
        recv_expr: &Expr,
    ) -> Result<Val, Error> {
        let static_ty = self.ety(recv_expr);
        let want = self.mty(&static_ty)?;
        let contract = m
            .contract
            .clone()
            .ok_or_else(|| Error::new("contract call without a contract"))?;
        if !matches!(self.b.m.types.kind(want), TyKind::Iface(_)) {
            // A concrete receiver (a generic instance): call its implementation directly.
            let Some(im) = self.contract_impl(m, &static_ty) else {
                // Hashing is derived for every hashable type.
                if m.name().is_some_and(|n| n.as_str() == "hash") {
                    let recv = self.expr(recv_expr)?;
                    if self.dead {
                        return Ok(recv);
                    }
                    return self.derived_hash(recv);
                }
                // Equality is derived for every type that has no implementation of its own.
                if m.name().is_some_and(|n| n.as_str() == "equals")
                    && contract.is_std("Equal")
                    && let [other] = view.arguments.as_slice()
                {
                    let recv = self.expr(recv_expr)?;
                    if self.dead {
                        return Ok(recv);
                    }
                    let raw = self.expr_value(other.expr)?;
                    if self.dead {
                        return Ok(raw);
                    }
                    let t = self.ty_of(recv.v);
                    let v = self.equal(t, recv, raw)?;
                    return Ok(Val { v, own: false });
                }
                // Built-in scalars order themselves against another of their own type.
                if m.name().is_some_and(|n| n.as_str() == "compare")
                    && contract.is_std("Comparable")
                    && let [other] = view.arguments.as_slice()
                {
                    let recv = self.expr(recv_expr)?;
                    if self.dead {
                        return Ok(recv);
                    }
                    let a = self.borrow(recv);
                    let raw = self.expr_value(other.expr)?;
                    if self.dead {
                        return Ok(raw);
                    }
                    let b = self.borrow(raw);
                    let r = self.order(want, &static_ty, a, b)?;
                    return Ok(Val { v: r, own: false });
                }
                // A resource closed through its parts (a record holding one) has no `close` of
                // its own: closing it closes what it holds.
                if m.name().is_some_and(|n| n.as_str() == "close")
                    && contract.is_std("Closeable")
                    && let Some(kind) = self.part_closer(&static_ty)?
                {
                    let recv = self.expr(recv_expr)?;
                    if self.dead {
                        return Ok(recv);
                    }
                    self.close_with(&kind, recv.v, want);
                    let v = self.b.unit();
                    return Ok(Val { v, own: false });
                }
                return Err(Error::new(format!(
                    "{static_ty} has no implementation of {}",
                    m.name().map(|n| n.to_string()).unwrap_or_default()
                )));
            };
            return self.method_call(e, view, &im);
        }
        let recv = self.expr(recv_expr)?;
        if self.dead {
            return Ok(recv);
        }
        // A `try` in an argument may return early: what was evaluated before it is released then.
        let any_try = view
            .arguments
            .iter()
            .any(|a| crate::mutation::has_try(a.expr));
        let recv = if recv.own && any_try {
            self.hold_temp(recv)
        } else {
            recv
        };
        let rty = self.ty_of(recv.v);
        let TyKind::Iface(iface) = self.b.m.types.kind(rty).clone() else {
            return Err(Error::new("contract receiver is not an interface value"));
        };
        let name = m.name().map(|n| n.to_string()).unwrap_or_default();
        let k = self.b.m.ifaces[iface.index()]
            .methods
            .iter()
            .position(|s| s.name == name)
            .ok_or_else(|| Error::new(format!("no interface method {name}")))?;
        let sig = self.b.m.ifaces[iface.index()].methods[k].clone();
        let params = m.ty.params.clone();
        let mut slots: Vec<Option<Val>> = vec![None; params.len()];
        for (n, a) in view.arguments.iter().enumerate() {
            let x = self.expr(a.expr)?;
            if self.dead {
                return Ok(x);
            }
            let x = match &a.wrap_optional {
                Some(_) => {
                    let o = self.owned(x);
                    let v = self.b.opt_some(o);
                    Val { v, own: true }
                }
                None => x,
            };
            let later_try = view.arguments[n + 1..]
                .iter()
                .any(|l| crate::mutation::has_try(l.expr));
            let x = if later_try && x.own {
                self.hold_temp(x)
            } else {
                x
            };
            let idx = params
                .iter()
                .position(|p| p.name == a.slot.name)
                .ok_or_else(|| Error::new(format!("no parameter {}", a.slot.name)))?;
            slots[idx] = Some(x);
        }
        let mut args = Vec::new();
        for (i, s) in slots.into_iter().enumerate() {
            let x = match s {
                Some(x) => x,
                None => {
                    let t = sig.params[i];
                    if matches!(self.b.m.types.kind(t), TyKind::Opt(_)) {
                        let v = self.b.opt_none(t);
                        Val { v, own: false }
                    } else {
                        self.contract_default(m.decl.as_ref(), &m.ty, i)?
                    }
                }
            };
            args.push(self.borrow(x));
        }
        let r = self.borrow(recv);
        self.at(e.pos);
        let v = self.b.call_method(iface, k as u32, r, &args);
        // A `ref` operation lends: the result is a borrow of the receiver or an argument.
        Ok(self.val(v, !sig.ret_borrowed))
    }

    /// The contract operation an implementation method fulfils: its parameters without a
    /// default of their own take the contract's.
    fn contract_operation(
        &self,
        callee: &Callable,
    ) -> Option<(Option<ms_check::syntax::FuncRef>, ct::Ty)> {
        let im = self.cx.methods.iter().find(|m| {
            !m.id.as_str().is_empty() && m.decl.as_ref().is_some_and(|d| d.id() == callee.func.id())
        })?;
        let def = im.contract.as_ref()?.def.as_ref()?;
        let ops = def.operations.borrow();
        let op = ops.iter().find(|o| Some(o.name) == im.name())?;
        Some((op.decl.clone(), op.ty.clone()))
    }

    /// The bytes default `"".to_bytes()` of a bundled declaration.
    pub(crate) fn empty_bytes(&mut self) -> Result<Val, Error> {
        let empty = self.b.str_lit("");
        let v = self.call_runtime("msrt_string_to_bytes", &[empty], MTy::BYTES)?;
        Ok(Val { v, own: true })
    }

    /// The default written on parameter `i` of a contract operation. Bundled declarations
    /// carry no checked expressions, so only literal defaults are understood: `false`, a
    /// number, a text literal, and `"".to_bytes()`.
    fn contract_default(
        &mut self,
        decl: Option<&ms_check::syntax::FuncRef>,
        sig: &ct::Ty,
        i: usize,
    ) -> Result<Val, Error> {
        let missing = || Error::new("missing argument");
        let default = decl
            .and_then(|d| d.func())
            .and_then(|f| f.params.get(i))
            .and_then(|p| p.default.as_ref())
            .ok_or_else(missing)?;
        let param_ty = sig.params.get(i).ok_or_else(missing)?.ty.clone();
        self.literal_default(default, &param_ty)?
            .ok_or_else(missing)
    }

    // --------------------------------------------------------- constructors

    fn construct(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        ty: &ct::Ty,
        case: Option<ct::Name>,
    ) -> Result<Val, Error> {
        let t = ct::sub(ty, &self.subst);
        let mt = self.cx.lower_ty(self.b.m, &t)?;
        if crate::sharedbuilder::builder_kind(&t).is_some() {
            return self.construct_builder(mt);
        }
        if crate::mapset::is_map_or_set(self.b.m, mt)
            || matches!(self.b.m.types.kind(mt), TyKind::List(_))
            || t.is_std("Bytes")
            || ms_check::effects::is_text_builder(&t)
        {
            return self.construct_collection(view, mt);
        }
        // Parameter names and types of the constructor.
        let params: Vec<ct::Param> = match case {
            Some(c) => ct::case_of(&t, c)
                .map(|c| c.fields)
                .ok_or_else(|| Error::new("unknown case"))?,
            None => ct::fields(&t),
        };
        let mut slots: Vec<Option<Val>> = vec![None; params.len()];
        // `return some(part)` of a lending function wraps the borrow itself.
        let view_only = self.lent_return
            && self.lent_expr == Some(e as *const Expr as usize)
            && matches!(self.b.m.types.kind(mt), TyKind::Opt(_))
            && view.arguments.len() == 1;
        for (n, a) in view.arguments.iter().enumerate() {
            let x = self.expr(a.expr)?;
            if self.dead {
                return Ok(x);
            }
            if view_only && a.wrap_optional.is_none() && !x.own {
                let v = self.b.opt_view(x.v);
                return Ok(Val { v, own: false });
            }
            let later_try = view.arguments[n + 1..]
                .iter()
                .any(|l| crate::mutation::has_try(l.expr));
            let x = match &a.wrap_optional {
                Some(_) => {
                    let o = self.owned(x);
                    let v = self.b.opt_some(o);
                    Val { v, own: true }
                }
                None => x,
            };
            let is_ref_field =
                case.is_none() && ct::field_is_ref(&t, a.slot.name) && a.wrap_optional.is_none();
            // A later field may return early (`try`): hold this one as a temporary until then.
            let x = if is_ref_field {
                x
            } else if later_try {
                self.hold_temp(x)
            } else {
                let v = self.owned(x);
                Val {
                    v,
                    own: self.holds(self.ty_of(v)),
                }
            };
            let idx = params
                .iter()
                .position(|p| p.name == a.slot.name)
                .ok_or_else(|| Error::new(format!("no field {}", a.slot.name)))?;
            slots[idx] = Some(x);
        }
        let mut vals = Vec::new();
        for (i, s) in slots.into_iter().enumerate() {
            match s {
                // A `ref` field holds a view of its argument: nothing is copied or moved in.
                Some(x) if case.is_none() && ct::field_is_ref(&t, params[i].name) => {
                    vals.push(self.b.ref_new(x.v));
                }
                Some(x) => {
                    let v = self.owned(x);
                    vals.push(v);
                }
                None => {
                    let earlier: Vec<(ct::Name, Value)> = params
                        .iter()
                        .zip(&vals)
                        .map(|(p, v)| (p.name, *v))
                        .collect();
                    let v = self.field_default(&t, case, i, &earlier)?;
                    vals.push(v);
                }
            }
        }
        let v = match (self.b.m.types.kind(mt).clone(), case) {
            (TyKind::Rec(r), None) => self.b.rec_new(r, &vals),
            (TyKind::Opt(_), Some(_)) => self.b.opt_some(vals[0]),
            (TyKind::Alt(a), Some(c)) => {
                let idx = self.b.m.alts[a.index()]
                    .cases
                    .iter()
                    .position(|x| x.name == c.as_str())
                    .ok_or_else(|| Error::new("unknown case"))?;
                self.b.alt_new(a, idx as u32, &vals)
            }
            _ => return Err(Error::new(format!("cannot construct {t}"))),
        };
        let _ = e;
        Ok(Val { v, own: true })
    }

    /// The default of field `i`; `earlier` are the values of the fields before it, which the
    /// default may read.
    pub(crate) fn field_default(
        &mut self,
        t: &ct::Ty,
        case: Option<ct::Name>,
        i: usize,
        earlier: &[(ct::Name, Value)],
    ) -> Result<Value, Error> {
        let _ = case;
        let sym = t
            .symbol()
            .ok_or_else(|| Error::new("constructor of a type without declaration"))?;
        let decl = sym
            .decl
            .as_ref()
            .ok_or_else(|| Error::new("type without declaration"))?;
        let field = decl
            .record_fields()
            .get(i)
            .ok_or_else(|| Error::new("missing field"))?;
        let ft = ct::fields(t)[i].ty.clone();
        let fm = self.cx.lower_ty(self.b.m, &ft)?;
        let Some(d) = &field.default else {
            if ft.is_std("Optional") {
                return Ok(self.none_owned(fm));
            }
            return Err(Error::new(format!("missing field {}", field.name)));
        };
        if matches!(&d.kind, ExprKind::Name(n) if n.as_str() == "none") && ft.is_std("Optional") {
            return Ok(self.none_owned(fm));
        }
        if self.cx.module(sym.module).is_err() {
            // Bundled declarations carry no checked facts: build literal defaults directly.
            return match self.literal_default(d, &ft)? {
                Some(v) => Ok(self.owned(v)),
                None => Err(Error::new(format!(
                    "unsupported default of field {}",
                    field.name
                ))),
            };
        }
        let saved_hir = self.hir.clone();
        let saved_subst = std::mem::replace(&mut self.subst, ct::substitution(t));
        let saved_file = self.file;
        self.hir = self.cx.module(sym.module)?;
        self.file = self.b.m.add_file(sym.module.as_str());
        self.bind_field_reads(d, earlier);
        // A default reports its own position, not the caller statement\'s.
        let saved_stmt = self.stmt_pos.take();
        let r = self.expr(d);
        self.stmt_pos = saved_stmt;
        self.hir = saved_hir;
        self.subst = saved_subst;
        self.file = saved_file;
        let x = r?;
        Ok(self.owned(x))
    }

    /// A default written as a literal, `none`, an empty list or a constructor call of literals in a
    /// declaration module without checked facts; none when `d` is anything else.
    pub(crate) fn literal_default(&mut self, d: &Expr, t: &ct::Ty) -> Result<Option<Val>, Error> {
        let mt = self.cx.lower_ty(self.b.m, t)?;
        let val = |v| Val { v, own: false };
        Ok(match &d.kind {
            ExprKind::Bool(b) => Some(val(self.b.bconst(*b))),
            ExprKind::Name(n) if n.as_str() == "none" && t.is_std("Optional") => {
                Some(val(self.b.opt_none(mt)))
            }
            ExprKind::Number(n) if t.id.as_str() == "Int" => {
                ms_syntax::number::canonical(n.as_str())
                    .parse::<i64>()
                    .ok()
                    .map(|n| val(self.b.iconst(n)))
            }
            ExprKind::Text(parts) if parts.iter().all(|p| matches!(p, TextPart::Lit(_))) => {
                let text: String = parts
                    .iter()
                    .map(|p| match p {
                        TextPart::Lit(s) => s.as_ref(),
                        TextPart::Interp(_) => "",
                    })
                    .collect();
                Some(self.lit(&text))
            }
            ExprKind::Call { .. } if matches!(self.b.m.types.kind(mt), TyKind::Bytes) => {
                Some(self.empty_bytes()?)
            }
            // `Stdio.Pipe`: a payload-free case of the parameter's own alternative.
            ExprKind::Member { left, name } if matches!(left.kind, ExprKind::Name(_)) => {
                let TyKind::Alt(a) = self.b.m.types.kind(mt).clone() else {
                    return Ok(None);
                };
                let case = self.b.m.alts[a.index()]
                    .cases
                    .iter()
                    .position(|c| c.name == name.as_str() && c.fields.is_empty());
                case.map(|c| Val {
                    v: self.b.alt_new(a, c as u32, &[]),
                    own: true,
                })
            }
            ExprKind::List(items) if items.is_empty() => {
                let v = self.call_runtime("msrt_list_new", &[], mt)?;
                Some(Val { v, own: true })
            }
            ExprKind::Call { args, .. } if args.iter().all(|a| a.name.is_some()) => {
                let (Some(sym), TyKind::Rec(rid)) = (t.symbol(), self.b.m.types.kind(mt).clone())
                else {
                    return Ok(None);
                };
                let Some(decl) = &sym.decl else {
                    return Ok(None);
                };
                let types = ct::fields(t);
                let mut vals = Vec::new();
                for (field, ft) in decl.record_fields().iter().zip(&types) {
                    let given = args
                        .iter()
                        .find(|a| {
                            a.name
                                .as_ref()
                                .is_some_and(|n| n.as_str() == field.name.as_str())
                        })
                        .map(|a| &a.value)
                        .or(field.default.as_ref());
                    let Some(e) = given else {
                        return Ok(None);
                    };
                    let Some(x) = self.literal_default(e, &ft.ty)? else {
                        return Ok(None);
                    };
                    vals.push(self.owned(x));
                }
                Some(Val {
                    v: self.b.rec_new(rid, &vals),
                    own: true,
                })
            }
            _ => None,
        })
    }

    /// Binds the fields `earlier` that the default expression `d` reads by name.
    fn bind_field_reads(&mut self, d: &Expr, earlier: &[(ct::Name, Value)]) {
        let mut found: Vec<Expr> = Vec::new();
        struct Collect<'f>(&'f mut Vec<Expr>);
        impl ms_syntax::visit::Visitor for Collect<'_> {
            fn expr(&mut self, e: &Expr) {
                if matches!(e.kind, ExprKind::Name(_)) {
                    self.0.push(e.clone());
                }
            }
        }
        ms_syntax::visit::walk_expr(&mut Collect(&mut found), d);
        for e in &found {
            let Resolution::Local(b) = self.hir.resolution(e) else {
                continue;
            };
            if let Some((_, v)) = earlier.iter().find(|(n, _)| *n == b.name) {
                self.bind_borrowed(&b, *v);
            }
        }
    }
}
