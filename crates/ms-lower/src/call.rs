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
        let Some(view) = self.hir.call(e) else {
            return Err(Error::new("call without resolution"));
        };
        let out = match &view.target {
            Resolution::Function(sym) if sym.native.as_str().is_empty() => {
                let c = self.callable_of_decl(sym.module, sym.decl.as_ref().map(|d| d.id()))?;
                let vars = sym.variables();
                let subst = self.callee_subst(&vars, &view.type_args)?;
                let names = self.param_names(&c);
                let args = self.eval_args(&view, &names, &c, &subst)?;
                self.call_callable(&c, &subst, args, e)?
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
                self.native_function(e, &view, sym.native.as_str(), &params)?
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
    ) -> Result<Args, Error> {
        let mut slots: Vec<Option<Val>> = vec![None; names.len()];
        let mut places: Vec<Option<Expr>> = vec![None; names.len()];
        let vars = self.cx.var_positions(callee);
        let offset = usize::from(callee.self_binding.is_some());
        for (n, a) in view.arguments.iter().enumerate() {
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
        }
        for i in 0..slots.len() {
            if slots[i].is_none() {
                slots[i] = Some(self.default_argument(callee, i, subst, &slots)?);
            }
        }
        Ok(Args { slots, places })
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
    fn default_argument(
        &mut self,
        callee: &Callable,
        i: usize,
        subst: &Subst,
        earlier: &[Option<Val>],
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
        for (j, v) in earlier.iter().enumerate().take(i) {
            if let Some(v) = v {
                self.bind_borrowed(&callee.parameters[j].clone(), v.v);
            }
        }
        let r = self.expr(d);
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
        let fid = self.cx.function_for(self.b.m, c, subst)?;
        let vars = self.cx.var_positions(c);
        // A changed parameter is moved into a slot the callee takes from and puts back into.
        let mut slots_out: Vec<(usize, Value, MTy, bool)> = Vec::new();
        let mut vals: Vec<Value> = Vec::new();
        for (i, a) in args.slots.into_iter().flatten().enumerate() {
            if !vars.contains(&i) {
                vals.push(self.borrow(a));
                continue;
            }
            let ty = self.ty_of(a.v);
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
                        let owned = self
                            .locals
                            .get(&uid)
                            .is_some_and(|l| self.b.var_mode(l.var) == Mode::Own);
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
        let v = self.b.call(fid, &vals);
        for (p, slot, ty, moved) in slots_out {
            let new = self.move_out(slot, ty);
            let target = args.places.get(p).cloned().flatten();
            match target {
                Some(place) if self.is_place(&place) => {
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
        Ok(self.val(v, true))
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
        if ms_check::effects::collection_mutation(&self.ety(recv_expr), &method) {
            return self.mutator_call(e, view, m, recv_expr, &method);
        }
        let recv = self.expr(recv_expr)?;
        if self.dead {
            return Ok(recv);
        }
        self.native_method(e, view, m, recv_expr, recv)
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
        let vars = ct::variable_set(&m.variables);
        if !ct::unify(&m.receiver, &rt, &vars, &mut subst) {
            return Err(Error::new("cannot bind method receiver type"));
        }
        for (i, v) in m.variables.iter().enumerate() {
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
        let args = self.eval_args(view, &names, &c, &subst)?;
        if self.dead {
            return Ok(recv);
        }
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

    fn contract_call(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        m: &ct::MethodRef,
        recv_expr: &Expr,
    ) -> Result<Val, Error> {
        let recv = self.expr(recv_expr)?;
        if self.dead {
            return Ok(recv);
        }
        let rty = self.ty_of(recv.v);
        let TyKind::Iface(iface) = self.b.m.types.kind(rty).clone() else {
            return Err(Error::new(
                "static dispatch through a contract is not supported yet",
            ));
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
        for a in &view.arguments {
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
                        return Err(Error::new("missing argument"));
                    }
                }
            };
            args.push(self.borrow(x));
        }
        let r = self.borrow(recv);
        self.at(e.pos);
        let v = self.b.call_method(iface, k as u32, r, &args);
        Ok(self.val(v, true))
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
        if crate::mapset::is_map_or_set(self.b.m, mt)
            || matches!(self.b.m.types.kind(mt), TyKind::List(_))
            || t.is_std("Bytes")
            || t.is_std("StringBuilder")
            || t.is_std("BytesBuilder")
        {
            return self.construct_collection(view, mt);
        }
        if matches!(self.b.m.types.kind(mt), TyKind::Iface(_)) {
            // `Shape(value: x)`: an explicit interface view.
            let [a] = view.arguments.as_slice() else {
                return Err(Error::new("an interface view takes one value"));
            };
            let x = self.expr(a.expr)?;
            let from = self.ety(a.expr);
            return self.fit_ty(x, &from, mt);
        }
        // Parameter names and types of the constructor.
        let params: Vec<ct::Param> = match case {
            Some(c) => ct::case_of(&t, c)
                .map(|c| c.fields)
                .ok_or_else(|| Error::new("unknown case"))?,
            None => ct::fields(&t),
        };
        let mut slots: Vec<Option<Value>> = vec![None; params.len()];
        for a in &view.arguments {
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
            let idx = params
                .iter()
                .position(|p| p.name == a.slot.name)
                .ok_or_else(|| Error::new(format!("no field {}", a.slot.name)))?;
            slots[idx] = Some(self.owned(x));
        }
        let mut vals = Vec::new();
        for (i, s) in slots.into_iter().enumerate() {
            match s {
                Some(v) => vals.push(v),
                None => vals.push(self.field_default(&t, case, i)?),
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

    fn field_default(
        &mut self,
        t: &ct::Ty,
        case: Option<ct::Name>,
        i: usize,
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
                return Ok(self.b.opt_none(fm));
            }
            return Err(Error::new(format!("missing field {}", field.name)));
        };
        if matches!(&d.kind, ExprKind::Name(n) if n.as_str() == "none") && ft.is_std("Optional") {
            return Ok(self.b.opt_none(fm));
        }
        let saved_hir = self.hir.clone();
        let saved_subst = std::mem::replace(&mut self.subst, ct::substitution(t));
        let saved_file = self.file;
        self.hir = self.cx.module(sym.module)?;
        self.file = self.b.m.add_file(sym.module.as_str());
        let r = self.expr(d);
        self.hir = saved_hir;
        self.subst = saved_subst;
        self.file = saved_file;
        let x = r?;
        Ok(self.owned(x))
    }
}
