//! Calls: source functions and methods, constructors, natives.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::api::ast::*;
use ms_check::api::hir::{CallView, Callable, Resolution};
use ms_check::api::syntax::DefaultForm;
use ms_check::api::types::{self as ct, Builtin, Subst};
use ms_mir::ir::{Mode, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use std::rc::Rc;

/// Arguments evaluated in written order and placed by parameter position.
pub(crate) struct Args {
    pub slots: Vec<Option<Val>>,
    /// For `var` parameters: the written place that receives the updated value.
    pub places: Vec<Option<Expr>>,
    /// An implicit optional made from a borrowed payload owns transport storage only.
    /// It must not acquire the original resource's close obligation.
    pub borrowed_optional_payloads: Vec<bool>,
}

/// A changed argument moved into a slot for a call: its position, the slot, the value's type and
/// the variable it was taken from (refilled after the call), if any.
pub(crate) type VarArgument = (usize, Value, MTy, Option<usize>);

/// The variable whose fields a call changes, its value with those fields moved out, and per
/// field: type, index, slot, type and whether the field was moved out (refilled afterwards).
type JointFields = (
    crate::func::Local,
    Value,
    Vec<(ms_mir::types::TypeId, u32, Value, MTy, bool)>,
);

impl<'a> FnLower<'a> {
    pub fn call_expr(&mut self, e: &Expr) -> Result<Val, Error> {
        if let Some(v) = self.scalar_parse_int(e)? {
            return Ok(v);
        }
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
            Resolution::Function(sym) if sym.native == ct::Native::Source => {
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
                    &Subst::default(),
                    Args {
                        slots: Vec::new(),
                        places: Vec::new(),
                        borrowed_optional_payloads: Vec::new(),
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
                self.native_function(e, &view, sym.native, &params, sym)?
            }
            // `x.get()(7)`: the callee is itself a call, so this one calls its function value.
            Resolution::Method(_) if self.receiver_expr(e).is_none() => {
                self.call_value(e, &view)?
            }
            Resolution::Method(m) => {
                let out = self.method_call(e, &view, m)?;
                if m.name().is_some_and(|n| self.syms.str(n) == "close")
                    && let Some(recv) = self.receiver_expr(e)
                {
                    self.note_explicit_close(recv);
                }
                out
            }
            Resolution::Constructor { ty, case } => self.construct(e, &view, ty, *case)?,
            Resolution::Local(_) | Resolution::Value => self.call_value(e, &view)?,
            _ => return Err(Error::new("unsupported call target")),
        };
        if !self.dead && self.ety(e).is_never() {
            self.b.unreachable();
            self.terminated();
        }
        Ok(out)
    }

    pub fn callable_of_decl(
        &self,
        module: ct::Name,
        id: Option<ms_check::api::NodeId>,
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
        let mut s = Subst::default();
        for (i, v) in vars.iter().enumerate() {
            let Some(Some(a)) = type_args.get(i) else {
                return Err(Error::new(format!(
                    "cannot infer type argument {}",
                    self.syms.str(v.name)
                )));
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
        call_pos: ms_check::api::Pos,
    ) -> Result<Args, Error> {
        let mut slots: Vec<Option<Val>> = vec![None; names.len()];
        let mut places: Vec<Option<Expr>> = vec![None; names.len()];
        let mut borrowed_optional_payloads = vec![false; names.len()];
        let vars = self.cx.var_positions(callee);
        let offset = usize::from(callee.self_binding.is_some());
        let mut read_at = Vec::new();
        let has_defaults = names.len() > view.arguments.len();
        for (n, a) in view.arguments.iter().enumerate() {
            let idx = names
                .iter()
                .position(|n| *n == a.slot.name)
                .ok_or_else(|| {
                    Error::new(format!("no parameter {}", self.syms.str(a.slot.name)))
                })?;
            let at = self.b.current();
            // The checked read selects the place once, including faults before later arguments.
            let x = if vars.contains(&(idx + offset)) {
                self.read_place(a.expr)?
            } else {
                self.expr(a.expr)?
            };
            if self.dead {
                self.finish_places(&places);
                return Ok(Args {
                    slots,
                    places,
                    borrowed_optional_payloads,
                });
            }
            borrowed_optional_payloads[idx] = !x.own && a.wrap_optional.is_some();
            let later_try = view.arguments[n + 1..]
                .iter()
                .any(|l| crate::mutation::has_try(l.expr));
            let x = match &a.wrap_optional {
                Some(opt) => {
                    let o = self.owned_boundary(x);
                    let _ = opt;
                    let v = self.b.opt_some(o);
                    Val { v, own: true }
                }
                None => x,
            };
            let x = if n + 1 < view.arguments.len() || has_defaults {
                if borrowed_optional_payloads[idx] {
                    if later_try {
                        self.borrow(x);
                    }
                    x
                } else {
                    self.hold_source_arg(x, later_try)?
                }
            } else {
                x
            };
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
        let mut defaults_left = slots.iter().filter(|slot| slot.is_none()).count();
        for i in 0..slots.len() {
            if slots[i].is_none() {
                defaults_left -= 1;
                // Defaults execute in the callee's lexical frame even though their
                // instructions live in the caller. Reuse inline-frame metadata so
                // faults retain both frames without runtime call bookkeeping.
                let parent = self.source_scope;
                let file = self.b.m.add_file(self.syms.str(callee.module.file));
                let name = if let DeclKind::Impl(implementation) = &callee.func.decl.decl().kind {
                    format!(
                        "{}.{}",
                        implementation.receiver.name(self.syms),
                        self.syms.str(callee.name)
                    )
                } else {
                    self.syms.str(callee.name).to_string()
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
                let result =
                    self.default_argument(callee, i, subst, &mut slots, recv, Some(call_pos));
                self.source_scope = parent;
                let d = result?;
                slots[i] = Some(if defaults_left > 0 {
                    self.hold_source_arg(d, true)?
                } else {
                    d
                });
                if self.dead {
                    self.finish_places(&places);
                    return Ok(Args {
                        slots,
                        places,
                        borrowed_optional_payloads,
                    });
                }
            }
        }
        Ok(Args {
            slots,
            places,
            borrowed_optional_payloads,
        })
    }

    /// The owned local that every changed parameter of a call names a distinct field of
    /// (`f(var self.a, var self.b)`), when there are several and each is `local.field`.
    fn joint_var_root(
        &mut self,
        vars: &[usize],
        places: &[Option<Expr>],
    ) -> Option<crate::func::Local> {
        if vars.len() < 2 {
            return None;
        }
        let mut root = None;
        let mut fields = Vec::new();
        for i in vars {
            let place = places.get(*i)?.as_ref()?;
            let ExprKind::Member { left, name, .. } = &place.kind else {
                return None;
            };
            if !matches!(left.kind, ExprKind::Name(_)) || fields.contains(name) {
                return None;
            }
            let ms_check::api::hir::Resolution::Local(b) = self.hir.resolution(left) else {
                return None;
            };
            if self.aliases.contains_key(&b.uid) || root.is_some_and(|uid| uid != b.uid) {
                return None;
            }
            root = Some(b.uid);
            fields.push(*name);
            if !self.is_place(place) || !self.place_is_owned(place) {
                return None;
            }
        }
        self.locals.get(&root?).copied()
    }

    /// Moves each changed field out of the owned variable into a slot the callee takes from
    /// and puts back into. Returns the variable and, per field, its slot and how to refill it.
    fn take_joint_fields(
        &mut self,
        root: crate::func::Local,
        fields: &[(usize, Expr, MTy)],
        vals: &mut [Value],
    ) -> Result<JointFields, Error> {
        let obj = self.local_take(&root);
        let mut taken = Vec::new();
        for (i, place, ty) in fields {
            let ExprKind::Member { name, .. } = &place.kind else {
                unreachable!("joint_var_root admits only fields")
            };
            let TyKind::Type(rid) = self.b.m.types.kind(self.ty_of(obj)).clone() else {
                return Err(Error::new("field mutation on a non-type"));
            };
            let idx = self.b.m.type_defs[rid.index()]
                .fields
                .iter()
                .position(|f| f.0 == self.syms.str(name))
                .ok_or_else(|| Error::new("no such field"))? as u32;
            let cur = self.b.type_get(rid, idx, obj);
            let (own, moved) = self.take_projection(cur);
            let slot = self
                .b
                .emit(Op::Slot, &[], ms_mir::ir::Imm::Ty(*ty), Some(MTy::PTR))
                .expect("slot");
            self.move_into(slot, own);
            vals[*i] = slot;
            taken.push((rid, idx, slot, *ty, moved));
        }
        Ok((root, obj, taken))
    }

    /// After the call: each field's final value moves back into the variable.
    fn put_joint_fields(&mut self, (root, mut obj, taken): JointFields) {
        for (rid, idx, slot, ty, moved) in taken {
            let new = self.move_out(slot, ty);
            obj = if moved {
                self.b.type_fill(rid, idx, obj, new)
            } else {
                self.b.type_set(rid, idx, obj, new)
            };
        }
        self.local_put(&root, obj);
    }

    /// Whether a place permits writeback: an owned local or shared mutable storage.
    /// A read-only borrow (a parameter of a default frame) takes no update.
    fn place_is_owned(&mut self, place: &Expr) -> bool {
        let Some(uid) = crate::mutation::place_root(self.syms, &self.hir, place) else {
            return false;
        };
        let uid = self.aliases.get(&uid).map_or(uid, |a| a.root.uid);
        self.locals.get(&uid).is_some_and(|l| {
            l.slot.is_some() || !self.needs_drop(l.ty) || self.b.var_mode(l.var) == Mode::Move
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
        // Evaluating a place again would repeat a call in its index (`xs[f()]`).
        if x.own
            || self.dead
            || !self.needs_drop(self.ty_of(x.v))
            || !self.is_place(e)
            || crate::mutation::has_call(e)
        {
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

    /// Stages a source argument without forgetting that the caller owns it. Intact resource
    /// wrappers need their payload closer if a later argument returns early or faults.
    fn hold_source_arg(&mut self, x: Val, later_try: bool) -> Result<Val, Error> {
        if x.own
            && let Some(key) = self.hold_resource_temp(x.v)?
        {
            return Ok(Val { v: key, own: true });
        }
        if later_try {
            self.borrow(x);
        }
        Ok(x)
    }

    /// The default of an omitted parameter, written in the callee's scope.
    pub(crate) fn default_argument(
        &mut self,
        callee: &Callable,
        i: usize,
        subst: &Subst,
        earlier: &mut [Option<Val>],
        recv: Option<Val>,
        call_pos: Option<ms_check::api::Pos>,
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
            if ty.is(Builtin::Optional) {
                let v = self.b.opt_none(mty);
                return Ok(Val { v, own: false });
            }
            if let Some((decl, sig, module)) = self.contract_operation(callee) {
                return self.contract_default(module, decl.as_ref(), &sig, i);
            }
            return Err(Error::new(format!(
                "missing argument {}",
                self.syms.str(binding.name)
            )));
        };
        let form = callee.module.default_form(self.syms, d);
        if form == DefaultForm::CallerSite {
            // The position of the call that omitted the argument, not of the default.
            let pos = call_pos
                .ok_or_else(|| Error::new("a function with a caller_site() default can only be called directly, not used as a function value"))?;
            let file = self
                .b
                .m
                .files
                .get(self.file as usize)
                .cloned()
                .unwrap_or_default();
            // As for any instruction, the enclosing statement names the site.
            let pos = self.stmt_pos.unwrap_or(pos);
            let v = self
                .b
                .str_lit(&format!("{file}:{}:{}", pos.line, pos.column));
            return Ok(Val { v, own: false });
        }
        if form == DefaultForm::None {
            let v = self.b.opt_none(mty);
            return Ok(Val { v, own: false });
        }
        let saved_hir = self.hir.clone();
        let saved_subst = std::mem::replace(&mut self.subst, subst.clone());
        let saved_variant = std::mem::take(&mut self.variant);
        let saved_file = self.file;
        self.hir = self.cx.module(callee.module.file)?;
        self.file = self.b.m.add_file(self.syms.str(callee.module.file));
        if let (Some(b), Some(r)) = (&callee.self_binding, recv) {
            self.bind_borrowed(b, r.v);
        }
        // A `var` parameter is a copy the default may change; the changed value is what the
        // call passes on.
        let offset = usize::from(callee.self_binding.is_some());
        let vars = self.cx.var_positions(callee);
        let mut changed = Vec::new();
        let mut frame = crate::func::DefaultFrame {
            copies: Vec::new(),
            shadowed: Vec::new(),
        };
        for (j, slot) in earlier.iter().enumerate().take(i) {
            let Some(v) = *slot else {
                continue;
            };
            let binding = callee.parameters[j].clone();
            if vars.contains(&(j + offset)) {
                let ty = self.ty_of(v.v);
                // An earlier `var` argument is the call's copy-in, as in `var_argument`.
                let o = self.owned_boundary(v);
                let var = self.b.declare_var(ty, Mode::Move);
                self.b.def_var(var, o);
                frame
                    .shadowed
                    .push((binding.uid, self.locals.get(&binding.uid).copied()));
                self.locals.insert(
                    binding.uid,
                    crate::func::Local {
                        var,
                        ty,
                        slot: None,
                        opt: false,
                    },
                );
                frame.copies.push(var);
                changed.push((j, var));
            } else {
                self.bind_borrowed(&binding, v.v);
            }
        }
        self.default_frames.push(frame);
        // A default reports its own position, not the caller statement\'s.
        let saved_stmt = self.stmt_pos.take();
        let r = self.expr(d);
        for (j, var) in changed {
            if !self.dead {
                let v = self.b.use_var(var);
                earlier[j] = Some(Val { v, own: true });
            }
        }
        if let Some(frame) = self.default_frames.pop() {
            self.restore_shadowed(frame.shadowed);
        }
        self.stmt_pos = saved_stmt;
        self.hir = saved_hir;
        self.subst = saved_subst;
        self.variant = saved_variant;
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
            self.finish_places(&args.places);
            return Ok(self.dummy(MTy::UNIT));
        }
        let owned_mask = self.cx.owned_mask(c);
        let fid = if owned_mask.is_some() {
            let scope = self.evidence();
            self.cx.function_owned(self.b.m, c, subst, scope)?
        } else {
            self.instance(c, subst)?
        };
        let vars = self.cx.var_positions(c);
        // A changed parameter is moved into a slot the callee takes from and puts back into.
        let mut slots_out: Vec<VarArgument> = Vec::new();
        let mut vals: Vec<Value> = Vec::new();
        // Which borrowed arguments were owned temporaries, for a returner that hands one back whole.
        let mut owned_args: Vec<bool> = Vec::new();
        // The only changed parameter is a field or list element of an owned variable: the callee
        // takes it out of its place and puts it back, instead of working on a copy.
        let mut in_place: Option<(usize, Expr, MTy)> = None;
        // Several changed parameters that are distinct fields of one owned variable: each field
        // moves out of the variable, and the callee's results move back into it.
        let joint_root = self.joint_var_root(&vars, &args.places);
        let mut joint: Vec<(usize, Expr, MTy)> = Vec::new();
        for (i, a) in args.slots.into_iter().flatten().enumerate() {
            // An intact borrowed argument keeps its original registration and acquisition
            // order. Only a consuming/changed parameter takes its value out of that slot.
            let guarded = a.own && self.resource_temps.contains_key(&a.v);
            let taking = vars.contains(&i) || owned_mask.as_ref().is_some_and(|mask| mask[i]);
            let a = if a.own && (!guarded || taking) {
                self.unhold_temp(a.v);
                let v = if self.resource_temps.contains_key(&a.v) {
                    self.take_resource_temp(a.v).0
                } else {
                    a.v
                };
                Val { v, own: true }
            } else {
                a
            };
            // A temporary held across a later `try` in the same call is ours again once every
            // argument is evaluated: a consumed parameter takes it instead of a copy.
            let a = if !a.own
                && owned_mask.as_ref().is_some_and(|mask| mask[i])
                && self.temps.contains(&a.v)
            {
                self.unhold_temp(a.v);
                Val { v: a.v, own: true }
            } else {
                a
            };
            owned_args.push(a.own && !vars.contains(&i));
            if !vars.contains(&i) {
                // A consumed parameter takes the value itself: a copy only when `a` is a borrow.
                if owned_mask.as_ref().is_some_and(|mask| mask[i]) {
                    // An `Optional` is passed on under the type's boundary rule.
                    let v = if matches!(self.b.m.types.kind(self.ty_of(a.v)), TyKind::Opt(_)) {
                        self.owned_boundary(a)
                    } else {
                        self.owned(a)
                    };
                    vals.push(v);
                } else if guarded {
                    vals.push(a.v);
                } else if a.own
                    && !args.borrowed_optional_payloads[i]
                    && let Some(key) = self.hold_resource_temp(a.v)?
                {
                    // Borrow the intact caller-owned resource through a registered slot.
                    // Its payload remains ours, unlike a wrapper whose payload was moved.
                    vals.push(key);
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
                        ms_check::api::hir::Resolution::Local(b)
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
            if !a.own
                && let Some(at) = args
                    .places
                    .get(i)
                    .cloned()
                    .flatten()
                    .and_then(|p| self.alias_payload_addr(&p))
            {
                vals.push(at);
                continue;
            }
            if vars.len() == 1
                && !a.own
                && let Some(place) = args.places.get(i).cloned().flatten()
                && (!matches!(place.kind, ExprKind::Name(_)) || self.is_alias_name(&place))
                && self.is_place(&place)
                && self.place_is_owned(&place)
            {
                vals.push(a.v);
                in_place = Some((i, place, ty));
                continue;
            }
            if joint_root.is_some()
                && !a.own
                && let Some(place) = args.places.get(i).cloned().flatten()
            {
                vals.push(a.v);
                joint.push((i, place, ty));
                continue;
            }
            let place = args.places.get(i).cloned().flatten();
            let slot = self.var_argument(e, i, a, place.as_ref(), &mut slots_out);
            vals.push(slot);
        }
        self.at(e.pos);
        let joint_slots = match joint_root {
            Some(root) if !joint.is_empty() => {
                Some(self.take_joint_fields(root, &joint, &mut vals)?)
            }
            _ => None,
        };
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
        if let Some(taken) = joint_slots {
            self.put_joint_fields(taken);
        }
        self.restore_var_arguments(slots_out, |p| args.places.get(p).cloned().flatten())?;
        if self.b.m.funcs[fid.index()].ret_borrowed {
            // A borrow-returning callee: the result points into the arguments. When one of them is a
            // temporary, the caller owns the result: the temporary itself when the callee hands
            // it back whole, otherwise a copy taken before the temporary is dropped.
            let Some(how) = self
                .cx
                .ownership
                .owned_borrows
                .get(&(self.hir.data.file, e.id))
            else {
                return Ok(Val { v, own: false });
            };
            if let ms_check::api::ownership::OwnedBorrow::Whole(source) = how {
                let offset = usize::from(c.self_binding.is_some());
                let slot = match source {
                    None => Some(0),
                    Some(label) => c
                        .parameters
                        .iter()
                        .position(|p| p.name == *label)
                        .map(|i| i + offset),
                };
                if let Some(k) = slot
                    && owned_args.get(k).copied().unwrap_or(false)
                    && let Some(&arg) = vals.get(k)
                    && self.ty_of(arg) == self.ty_of(v)
                {
                    // The result is that temporary: use the argument value itself, which the
                    // MIR knows as owned, and stop dropping it with the statement.
                    self.unhold_temp(arg);
                    let arg = if self.resource_temps.contains_key(&arg) {
                        self.take_resource_temp(arg).0
                    } else {
                        arg
                    };
                    return Ok(self.val(arg, true));
                }
            }
            // The callee wrapped the whole temporary (`ok(value)`): the caller's result owns that
            // temporary, moved into the ordinary alternative, so no resource is copied.
            if let Some(owned) = self.wrapped_temporary_result(c, owned_args, &vals, v, *how) {
                return owned;
            }
            // The checker recorded this as a clone of a part of the temporary (`OwnedBorrow::Clone`).
            let copy = self.clone_value(v);
            return Ok(self.val(copy, true));
        }
        // A function that borrows some cases of its `Result` over a temporary source: the
        // borrowed cases would end with the temporary, so the caller owns a copy of the whole
        // result (the part of the temporary is copied out before it is dropped).
        if self
            .cx
            .ownership
            .owned_borrows
            .contains_key(&(self.hir.data.file, e.id))
            && let TyKind::Alt(a) = self.b.m.types.kind(self.ty_of(v)).clone()
            && self.b.m.alts[a.index()].borrowed != 0
        {
            let (base, plain) = self.plain_of(a);
            let _ = base;
            let copy = self.b.alt_own(v, plain);
            self.drop_value(v);
            return Ok(self.val(copy, true));
        }
        Ok(self.val(v, true))
    }

    /// A borrow-returning callee that wraps one whole temporary argument in a borrowed case of
    /// its `Result` (`ok(value)`): the result built from that temporary, taken out of the
    /// statement's temporaries. `None` when the call is not of that shape.
    fn wrapped_temporary_result(
        &mut self,
        c: &Rc<Callable>,
        owned_args: Vec<bool>,
        vals: &[Value],
        v: Value,
        how: ms_check::api::ownership::OwnedBorrow,
    ) -> Option<Result<Val, Error>> {
        let ms_check::api::ownership::OwnedBorrow::Whole(source) = &how else {
            return None;
        };
        let offset = usize::from(c.self_binding.is_some());
        let k = match source {
            None => 0,
            Some(label) => c.parameters.iter().position(|p| p.name == *label)? + offset,
        };
        let arg = *vals.get(k)?;
        if !owned_args.get(k).copied().unwrap_or(false) {
            return None;
        }
        let arg_ty = self.ty_of(arg);
        if let TyKind::Opt(inner) = self.b.m.types.kind(self.ty_of(v)).clone()
            && inner == arg_ty
        {
            // The callee converted the whole temporary to an optional (`fn f[T](x: T) T?: x`).
            self.unhold_temp(arg);
            let arg = if self.resource_temps.contains_key(&arg) {
                self.take_resource_temp(arg).0
            } else {
                arg
            };
            // The callee may also return `none` on another path (`if flag: return x` then
            // `return none`): the argument is the result only when the callee's result is some,
            // and is dropped (closing a resource) otherwise.
            let optty = self.ty_of(v);
            let has = self.b.opt_is_some(v);
            let out = self.two_ways(has, optty, &mut |s| Ok(Some(s.b.opt_some(arg))), &mut |s| {
                s.drop_temp(arg);
                Ok(Some(s.none_owned(optty)))
            });
            return Some(out);
        }
        let TyKind::Alt(a) = self.b.m.types.kind(self.ty_of(v)).clone() else {
            return None;
        };
        let def = self.b.m.alts[a.index()].clone();
        let mut cases = (0..def.cases.len())
            .filter(|&i| matches!(def.cases[i].fields.as_slice(), [(_, t)] if *t == arg_ty));
        let case = cases.next()?;
        if cases.next().is_some() {
            return None;
        }
        let (plain, _) = self.plain_of(a);
        self.unhold_temp(arg);
        let arg = if self.resource_temps.contains_key(&arg) {
            self.take_resource_temp(arg).0
        } else {
            arg
        };
        let out = self.b.alt_new(plain, case as u32, &[arg]);
        Some(Ok(self.val(out, true)))
    }

    /// The ordinary alternative a borrowing variant `a` is a variant of.
    pub(crate) fn plain_of(&mut self, a: ms_mir::types::AltId) -> (ms_mir::types::AltId, MTy) {
        let def = self.b.m.alts[a.index()].clone();
        let id = self
            .b
            .m
            .alts
            .iter()
            .position(|x| x.borrowed == 0 && x.name == def.name && x.cases == def.cases)
            .map(|i| ms_mir::types::AltId(i as u32))
            .unwrap_or(a);
        (id, self.b.m.types.alt(id))
    }

    /// Moves a changed argument into a slot the callee takes from and puts back into, and
    /// returns the slot's address: the value a `var` position is passed. A variable that already
    /// lives in memory (a closure shares it) is passed by its own slot and changed in place.
    /// Every slot made here goes on `slots_out` for `restore_var_arguments` after the call.
    pub(crate) fn var_argument(
        &mut self,
        e: &Expr,
        i: usize,
        a: Val,
        place: Option<&Expr>,
        slots_out: &mut Vec<VarArgument>,
    ) -> Value {
        let ty = self.ty_of(a.v);
        if !a.own
            && let Some(at) = place.and_then(|p| self.alias_payload_addr(p))
        {
            return at;
        }
        if !a.own
            && let Some(slot) = place
                .filter(|p| matches!(p.kind, ExprKind::Name(_)))
                .and_then(|p| match self.hir.resolution(p) {
                    ms_check::api::hir::Resolution::Local(b)
                        if !self.aliases.contains_key(&b.uid) =>
                    {
                        self.locals.get(&b.uid).and_then(|l| l.slot)
                    }
                    _ => None,
                })
        {
            return slot;
        }
        // The variable's own value moves into the slot and the callee's result moves back.
        // A variable in memory (a closure shares it) has no value to move.
        let moved = place
            .and_then(|p| match self.hir.resolution(p) {
                ms_check::api::hir::Resolution::Local(b)
                    if !a.own && matches!(p.kind, ExprKind::Name(_)) =>
                {
                    Some(b.uid)
                }
                _ => None,
            })
            .filter(|uid| {
                let owned = self
                    .locals
                    .get(uid)
                    .is_some_and(|l| l.slot.is_none() && self.b.var_mode(l.var) == Mode::Move);
                owned && crate::mutation::uses_of(&self.hir, e, *uid) == 1
            });
        let x = match moved {
            Some(uid) => {
                // The result refills the variable right after the call, so no path reads
                // it empty in between.
                let l = self.locals[&uid];
                self.local_take(&l)
            }
            // A field or element place the callee changes: the value is copied into the slot and the
            // original is dropped when the result is written back, so this copy is the call's
            // copy-in, not a stored duplicate (interim: take the place's value out instead).
            // A variable another argument of the same call reads is copied in the same way:
            // taking it would leave that read an empty slot.
            None if !a.own && place.is_some_and(|p| self.is_place(p)) => self.clone_value(a.v),
            None => self.owned(a),
        };
        let slot = self
            .b
            .emit(Op::Slot, &[], ms_mir::ir::Imm::Ty(ty), Some(MTy::PTR))
            .expect("slot");
        self.move_into(slot, x);
        slots_out.push((i, slot, ty, moved));
        slot
    }

    /// After the call: the final values move out of the slots `var_argument` made, back into the
    /// variables they came from, or into the places `place_of` names.
    pub(crate) fn restore_var_arguments(
        &mut self,
        slots_out: Vec<VarArgument>,
        place_of: impl Fn(usize) -> Option<Expr>,
    ) -> Result<(), Error> {
        for (p, slot, ty, moved) in slots_out {
            let new = self.move_out(slot, ty);
            if let Some(uid) = moved {
                // The value left the variable before the call; the result refills it.
                let l = self.locals[&uid];
                self.local_put(&l, new);
                continue;
            }
            match place_of(p) {
                Some(place) if self.is_place(&place) && self.place_is_owned(&place) => {
                    let mut new = Some(new);
                    self.place_update(&place, &mut |s, old| {
                        s.drop_value(old);
                        Ok(new.take().expect("single use"))
                    })?;
                }
                // A changed copy of a place nobody owns is only dropped; a computed value
                // (`open().advance()`) is a temporary that nothing else closes.
                Some(place) if self.is_place(&place) => {
                    self.drop_value(new);
                    self.finish_place(&place);
                }
                _ => self.drop_temp(new),
            }
        }
        Ok(())
    }

    /// Whether `e` names an exclusive borrow of another place (`if var x = ...`, `c?.f()`).
    fn is_alias_name(&self, e: &Expr) -> bool {
        matches!(self.hir.resolution(e), ms_check::api::hir::Resolution::Local(b) if self.aliases.contains_key(&b.uid))
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
        if let Some(v) = self.fused_chain(e, m, recv_expr)? {
            return Ok(v);
        }
        if let Some(v) = self.fused_scalar_scan(e, m, recv_expr)? {
            return Ok(v);
        }
        let native = match m.native {
            ct::Native::Source => return self.source_method_call(e, view, m, recv_expr),
            ct::Native::Contract => return self.contract_call(e, view, m, recv_expr),
            native => native.text(self.syms),
        };
        let method = m
            .name()
            .map(|n| self.syms.str(n).to_string())
            .unwrap_or_else(|| native.rsplit('/').next().unwrap_or(native).to_string());
        if ms_check::api::ownership::is_text_builder(self.syms, &m.receiver) && method == "build" {
            return self.text_builder_build(e, recv_expr);
        }
        if ms_check::api::ownership::collection_mutation(self.syms, m) {
            return self.mutator_call(e, view, m, recv_expr, &method);
        }
        if let Some(v) = self.map_get_chain(e, view, recv_expr, &method)? {
            return Ok(v);
        }
        if let Some(v) = self.const_map_method(recv_expr, view, &method)? {
            return Ok(v);
        }
        let recv = self.expr(recv_expr)?;
        if self.dead {
            return Ok(recv);
        }
        let str_recv = matches!(self.b.m.types.kind(self.ty_of(recv.v)), TyKind::Str);
        let trim_view = match native {
            _ if !str_recv => None,
            "trim" => Some("msrt_string_trim_view"),
            "trim_start" => Some("msrt_string_trim_start_view"),
            "trim_end" => Some("msrt_string_trim_end_view"),
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
        let mut subst = Subst::default();
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
        let recv = if self.cx.var_positions(&c).contains(&0) {
            self.read_place(recv_expr)?
        } else {
            self.expr(recv_expr)?
        };
        if self.dead {
            return Ok(recv);
        }
        let recv = if !c.parameters.is_empty() {
            let later_try = view
                .arguments
                .iter()
                .any(|a| crate::mutation::has_try(a.expr));
            self.hold_source_arg(recv, later_try)?
        } else {
            recv
        };
        let names = self.param_names(&c);
        let at = self.b.current();
        let args = self.eval_args(view, &names, &c, &subst, Some(recv), e.pos)?;
        if self.dead {
            self.finish_place(recv_expr);
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
        let mut borrowed_optional_payloads = vec![false];
        borrowed_optional_payloads.extend(args.borrowed_optional_payloads);
        self.call_callable(
            &c,
            &subst,
            Args {
                slots: all,
                places,
                borrowed_optional_payloads,
            },
            e,
        )
    }

    /// The implementation of a contract operation for a concrete receiver type.
    pub(crate) fn contract_impl(&self, m: &ct::MethodRef, recv: &ct::Ty) -> Option<ct::MethodRef> {
        let name = m.name()?;
        let contract = m.contract.as_ref()?;
        let scope = self.evidence();
        // A receiver may implement one generic contract at several applications
        // (`Scorer[String]` and `Scorer[Int]`), so the arguments choose among them.
        let wanted = ct::sub(contract, &self.subst);
        let named = |mm: &&ct::MethodRef| {
            mm.name() == Some(name) && !self.syms.str(mm.id).is_empty() && mm.visible_in(scope)
        };
        let written = self.cx.methods.iter().filter(named).find(|mm| {
            mm.contract.as_ref().is_some_and(|c| {
                let vars = ct::variable_set(&mm.variables);
                let mut bound = ct::Subst::default();
                c.id == contract.id
                    && ct::unify(&mm.receiver, recv, &vars, &mut bound)
                    && ct::unify(c, &wanted, &vars, &mut bound)
            })
        });
        // Without a written `impl`, the type's own method of that name satisfies the operation.
        written
            .or_else(|| {
                self.cx.methods.iter().filter(named).find(|mm| {
                    mm.is_inherent(self.syms)
                        && ct::unify(
                            &mm.receiver,
                            recv,
                            &ct::variable_set(&mm.variables),
                            &mut ct::Subst::default(),
                        )
                })
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
                if contract.is(Builtin::Hashable) {
                    let recv = self.expr(recv_expr)?;
                    if self.dead {
                        return Ok(recv);
                    }
                    return self.derived_hash(recv);
                }
                // Equality is derived for every type that has no implementation of its own.
                if contract.is(Builtin::Equal)
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
                if contract.is(Builtin::Comparable)
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
                // A resource closed through its parts (a type holding one) has no `close` of
                // its own: closing it closes what it holds.
                if m.name().is_some_and(|n| self.syms.str(n) == "close")
                    && contract.is(Builtin::Closeable)
                    && let Some(kind) = self.part_closer(&static_ty)?
                {
                    let recv = self.expr(recv_expr)?;
                    if self.dead {
                        return Ok(recv);
                    }
                    self.close_receiver(&kind, recv_expr, recv)?;
                    // The call is checked as `Unit!`: it succeeds, since a part that fails faults.
                    let result = self.mty(&self.cx.session.test_outcome())?;
                    let TyKind::Alt(alt) = self.b.m.types.kind(result).clone() else {
                        return Err(Error::new("a close returns a Result"));
                    };
                    let ok = self.b.m.alts[alt.index()]
                        .ok_case()
                        .ok_or_else(|| Error::new("a close returns a Result"))?;
                    let unit = self.b.unit();
                    let v = self.b.alt_new(alt, ok as u32, &[unit]);
                    return Ok(Val { v, own: true });
                }
                return Err(Error::new(format!(
                    "{static_ty_t} has no implementation of {}",
                    m.name()
                        .map(|n| self.syms.str(n).to_string())
                        .unwrap_or_default(),
                    static_ty_t = static_ty.display(self.syms)
                )));
            };
            // The checker saw an operation of the contract, whose result owns; the instance's
            // method may return a borrow of its receiver, so the call copies it.
            let result = self.method_call(e, view, &im)?;
            if self.dead || result.own || !self.needs_drop(self.ty_of(result.v)) {
                return Ok(result);
            }
            let copy = self.clone_value(result.v);
            return Ok(self.val(copy, true));
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
        let name = m
            .name()
            .map(|n| self.syms.str(n).to_string())
            .unwrap_or_default();
        let k = self.b.m.ifaces[iface.index()]
            .methods
            .iter()
            .position(|s| s.name == name)
            .ok_or_else(|| Error::new(format!("no interface method {name}")))?;
        let sig = self.b.m.ifaces[iface.index()].methods[k].clone();
        let op_vars = self.cx.iface_op_vars(iface, &name);
        let params = m.ty.params.clone();
        let mut slots: Vec<Option<Val>> = vec![None; params.len()];
        let mut places: Vec<Option<Expr>> = vec![None; params.len()];
        for (n, a) in view.arguments.iter().enumerate() {
            let idx = params
                .iter()
                .position(|p| p.name == a.slot.name)
                .ok_or_else(|| {
                    Error::new(format!("no parameter {}", self.syms.str(a.slot.name)))
                })?;
            let x = if op_vars.get(idx).copied().unwrap_or(false) {
                self.read_place(a.expr)?
            } else {
                self.expr(a.expr)?
            };
            if self.dead {
                self.finish_places(&places);
                return Ok(x);
            }
            let owned_payload = x.own;
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
            // Interface parameters borrow too: keep intact resources registered in
            // written order through later operands and through the dispatch itself.
            let x = if owned_payload && let Some(key) = self.hold_resource_temp(x.v)? {
                Val { v: key, own: true }
            } else if later_try && x.own {
                self.hold_temp(x)
            } else {
                x
            };
            if op_vars.get(idx).copied().unwrap_or(false) {
                places[idx] = Some(a.expr.clone());
            }
            slots[idx] = Some(x);
        }
        let mut args = Vec::new();
        // A `var` argument moves into a slot the implementation changes, then back.
        let mut slots_out: Vec<VarArgument> = Vec::new();
        let lone_var = places.iter().filter(|p| p.is_some()).count() == 1;
        let mut in_place: Option<(usize, Expr, MTy)> = None;
        for (i, s) in slots.into_iter().enumerate() {
            let x = match s {
                Some(x) => x,
                None => {
                    let t = sig.params[i];
                    if matches!(self.b.m.types.kind(t), TyKind::Opt(_)) {
                        let v = self.b.opt_none(t);
                        Val { v, own: false }
                    } else {
                        let module = m
                            .contract
                            .as_ref()
                            .and_then(|c| c.symbol())
                            .map_or(m.module, |s| s.module);
                        self.contract_default(module, m.decl.as_ref(), &m.ty, i)?
                    }
                }
            };
            if self.dead {
                self.finish_places(&places);
                return Ok(x);
            }
            if op_vars.get(i).copied().unwrap_or(false) {
                // A lone `var` field argument changes in place, as for a source function.
                if lone_var
                    && !x.own
                    && let Some(place) = places[i].clone()
                    && (!matches!(place.kind, ExprKind::Name(_)) || self.is_alias_name(&place))
                    && self.is_place(&place)
                    && self.place_is_owned(&place)
                {
                    args.push(x.v);
                    in_place = Some((i, place, self.ty_of(x.v)));
                    continue;
                }
                let x = if x.own && self.resource_temps.contains_key(&x.v) {
                    self.unhold_temp(x.v);
                    Val {
                        v: self.take_resource_temp(x.v).0,
                        own: true,
                    }
                } else {
                    x
                };
                let slot = self.var_argument(e, i, x, places[i].as_ref(), &mut slots_out);
                args.push(slot);
                continue;
            }
            args.push(if x.own && self.resource_temps.contains_key(&x.v) {
                x.v
            } else {
                self.borrow(x)
            });
        }
        let r = self.borrow(recv);
        self.at(e.pos);
        let v = if let Some((i, place, ty)) = in_place {
            let mut result = None;
            self.place_update(&place, &mut |s, old| {
                let slot =
                    s.b.emit(Op::Slot, &[], ms_mir::ir::Imm::Ty(ty), Some(MTy::PTR))
                        .expect("slot");
                s.move_into(slot, old);
                args[i] = slot;
                result = Some(s.b.call_method(iface, k as u32, r, &args));
                Ok(s.move_out(slot, ty))
            })?;
            result.expect("call emitted")
        } else {
            self.b.call_method(iface, k as u32, r, &args)
        };
        self.restore_var_arguments(slots_out, |p| places.get(p).cloned().flatten())?;
        Ok(self.val(v, true))
    }

    /// The contract operation an implementation method fulfils: its parameters without a
    /// default of their own take the contract's.
    fn contract_operation(
        &self,
        callee: &Callable,
    ) -> Option<(Option<ms_check::api::syntax::FuncRef>, ct::Ty, ct::Name)> {
        // Node ids repeat across modules, so the module must match too.
        let im = self.cx.methods.iter().find(|m| {
            !self.syms.str(m.id).is_empty()
                && m.module == callee.module.file
                && m.decl.as_ref().is_some_and(|d| d.id() == callee.func.id())
        })?;
        let def = im.contract.as_ref()?.def.as_ref()?;
        let module = def.symbol()?.module;
        let ops = def.operations.borrow();
        let op = ops.iter().find(|o| Some(o.name) == im.name())?;
        Some((op.decl.clone(), op.ty.clone(), module))
    }

    /// The checked module declared in `file`: a program module or a bundled one.
    pub(crate) fn decl_module(
        &self,
        file: ct::Name,
    ) -> Result<ms_check::api::syntax::ModRef, Error> {
        if let Ok(m) = self.cx.module(file) {
            return Ok(m.data.clone());
        }
        self.cx
            .session
            .bundled_module(file)
            .ok_or_else(|| Error::new(format!("no checked module {}", self.syms.str(file))))
    }

    /// The checked module declaring `f`, found by the declaration itself: a native method of the
    /// standard library and an interface operation viewed through a contract name no file.
    pub(crate) fn func_decl_module(
        &self,
        file: ct::Name,
        f: &ms_check::api::ast::Func,
    ) -> Result<ms_check::api::syntax::ModRef, Error> {
        if let Some(m) = self.cx.session.func_module(f) {
            return Ok(m);
        }
        // An operation of a program interface is viewed through a method that names no file.
        if let Some(m) = self.cx.mods.values().find(|m| m.data.declares(f)) {
            return Ok(m.data.clone());
        }
        self.decl_module(file)
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
        module: ct::Name,
        decl: Option<&ms_check::api::syntax::FuncRef>,
        sig: &ct::Ty,
        i: usize,
    ) -> Result<Val, Error> {
        let missing = || Error::new("missing argument");
        let func = decl.and_then(|d| d.func()).ok_or_else(missing)?;
        let default = func
            .params
            .get(i)
            .and_then(|p| p.default.as_ref())
            .ok_or_else(missing)?;
        let param_ty = sig.params.get(i).ok_or_else(missing)?.ty.clone();
        let module = self.func_decl_module(module, func)?;
        self.literal_default(&module, default, &param_ty)?
            .ok_or_else(missing)
    }

    // --------------------------------------------------------- constructors

    /// The alternative a constructor in return position builds: the borrowing variant this function
    /// returns when the checker marked the node (`Fact::RetCtor`), else `a`.
    fn ret_variant(&self, e: &Expr, a: ms_mir::types::AltId) -> ms_mir::types::AltId {
        if !self.cx.fact(
            self.hir.data.file,
            e.id,
            ms_check::api::ownership::Fact::RetCtor,
        ) {
            return a;
        }
        match self.b.m.types.kind(self.ret_ty) {
            TyKind::Alt(v)
                if self.b.m.alts[v.index()].borrowed != 0
                    && self.b.m.alts[v.index()].name == self.b.m.alts[a.index()].name =>
            {
                *v
            }
            _ => a,
        }
    }

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
            || t.is(Builtin::Bytes)
            || ms_check::api::ownership::is_text_builder(self.syms, &t)
        {
            return self.construct_collection(view, mt);
        }
        // `ok(x)` / `error(x)` of a reference the checker keeps one: `alt.view` of the payload.
        if let (TyKind::Alt(a), Some(c), [arg]) = (
            self.b.m.types.kind(mt).clone(),
            case,
            view.arguments.as_slice(),
        ) && self.cx.fact(
            self.hir.data.file,
            e.id,
            ms_check::api::ownership::Fact::ViewWrap,
        ) {
            let x = self.expr(arg.expr)?;
            if self.dead {
                return Ok(x);
            }
            let idx = self.b.m.alts[a.index()]
                .cases
                .iter()
                .position(|x| x.name == self.syms.str(c))
                .ok_or_else(|| Error::new("unknown case"))?;
            let variant = self.ret_variant(e, a);
            if !x.own && arg.wrap_optional.is_none() {
                let v = self.b.alt_view(variant, idx as u32, &[x.v]);
                // In a borrowing variant the borrowed case is part of an owned result.
                return Ok(Val {
                    v,
                    own: variant != a,
                });
            }
            let o = if self.b.m.alts[a.index()].std == ms_mir::types::Std::Result {
                self.owned_boundary(x)
            } else {
                self.owned(x)
            };
            let v = self.b.alt_new(a, idx as u32, &[o]);
            return Ok(Val { v, own: true });
        }
        // Parameter names and types of the constructor.
        let params: Vec<ct::Param> = match case {
            Some(c) => ct::case_of(&t, c)
                .map(|c| c.fields)
                .ok_or_else(|| Error::new("unknown case"))?,
            None => ct::fields(&t),
        };
        let mut slots: Vec<Option<Val>> = vec![None; params.len()];
        let mut held: Vec<Value> = Vec::new();
        let mut resources = Vec::new();
        let has_defaults = params.len() > view.arguments.len();
        for (n, a) in view.arguments.iter().enumerate() {
            let x = self.expr(a.expr)?;
            if self.dead {
                return Ok(x);
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
            let idx = params
                .iter()
                .position(|p| p.name == a.slot.name)
                .ok_or_else(|| Error::new(format!("no field {}", self.syms.str(a.slot.name))))?;
            // Every later operand can fault or suspend, and defaults run after the written
            // arguments. An acquired resource stays owned until all that evaluation succeeds.
            if x.own
                && (n + 1 < view.arguments.len() || has_defaults)
                && let Some(key) = self.hold_resource_temp(x.v)?
            {
                resources.push((idx, key));
                slots[idx] = Some(Val { v: key, own: false });
                continue;
            }
            // A later field may return early (`try`): hold this one as a temporary until then.
            let x = if later_try {
                if x.own && self.holds(self.ty_of(x.v)) {
                    // An owned part waits as a temporary until the field takes it.
                    held.push(x.v);
                    Val {
                        v: self.borrow(x),
                        own: true,
                    }
                } else {
                    self.hold_temp(x)
                }
            } else {
                let v = if matches!(self.b.m.types.kind(mt), TyKind::Alt(a)
                    if self.b.m.alts[a.index()].std == ms_mir::types::Std::Result)
                {
                    self.owned_boundary(x)
                } else {
                    self.owned(x)
                };
                Val {
                    v,
                    own: self.holds(self.ty_of(v)),
                }
            };
            slots[idx] = Some(x);
        }
        // `ok(x)` / `error(x)` of a borrow is the `Result` boundary copy the type declares.
        let result_case = matches!(self.b.m.types.kind(mt), TyKind::Alt(a)
            if self.b.m.alts[a.index()].std == ms_mir::types::Std::Result);
        let mut vals = Vec::new();
        let mut defaults_left = slots.iter().filter(|s| s.is_none()).count();
        for (i, s) in slots.into_iter().enumerate() {
            match s {
                Some(x) if self.resource_temps.contains_key(&x.v) => vals.push(x.v),
                Some(x) if held.contains(&x.v) => {
                    // Every `try` of the fields has passed: the field takes the temporary.
                    self.unhold_temp(x.v);
                    vals.push(x.v);
                }
                Some(x) => {
                    let v = if result_case {
                        self.owned_boundary(x)
                    } else {
                        self.owned(x)
                    };
                    vals.push(v);
                }
                None => {
                    defaults_left -= 1;
                    let earlier: Vec<(ct::Name, Value)> = params
                        .iter()
                        .zip(&vals)
                        .map(|(p, v)| (p.name, *v))
                        .collect();
                    let v = self.field_default(&t, case, i, &earlier)?;
                    if defaults_left > 0
                        && let Some(key) = self.hold_resource_temp(v)?
                    {
                        resources.push((i, key));
                        vals.push(key);
                    } else {
                        vals.push(v);
                    }
                }
            }
        }
        // Commit the fields only after every argument and default has succeeded. Retire
        // registrations last acquired first, then immediately consume their owned values.
        for (i, key) in resources.into_iter().rev() {
            vals[i] = self.take_resource_temp(key).0;
            self.unhold_temp(key);
        }
        let v = match (self.b.m.types.kind(mt).clone(), case) {
            (TyKind::Type(r), None) => self.b.type_new(r, &vals),
            (TyKind::Opt(_), Some(_)) => self.b.opt_some(vals[0]),
            (TyKind::Alt(a), Some(c)) => {
                let idx = self.b.m.alts[a.index()]
                    .cases
                    .iter()
                    .position(|x| x.name == self.syms.str(c))
                    .ok_or_else(|| Error::new("unknown case"))?;
                let a = self.ret_variant(e, a);
                self.b.alt_new(a, idx as u32, &vals)
            }
            _ => {
                return Err(Error::new(format!(
                    "cannot construct {t_t}",
                    t_t = t.display(self.syms)
                )));
            }
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
            .type_fields()
            .get(i)
            .ok_or_else(|| Error::new("missing field"))?;
        let ft = ct::fields(t)[i].ty.clone();
        let fm = self.cx.lower_ty(self.b.m, &ft)?;
        let Some(d) = &field.default else {
            if ft.is(Builtin::Optional) {
                return Ok(self.none_owned(fm));
            }
            return Err(Error::new(format!(
                "missing field {}",
                self.syms.str(field.name)
            )));
        };
        let module = self.decl_module(sym.module)?;
        if module.default_form(self.syms, d) == DefaultForm::None {
            return Ok(self.none_owned(fm));
        }
        if self.cx.module(sym.module).is_err() {
            // Bundled declarations carry no checked facts: build literal defaults directly.
            return match self.literal_default(&module, d, &ft)? {
                Some(v) => Ok(self.owned(v)),
                None => Err(Error::new(format!(
                    "unsupported default of field {}",
                    self.syms.str(field.name)
                ))),
            };
        }
        let saved_hir = self.hir.clone();
        let saved_subst = std::mem::replace(&mut self.subst, ct::substitution(t));
        let saved_variant = std::mem::take(&mut self.variant);
        let saved_file = self.file;
        self.hir = self.cx.module(sym.module)?;
        self.file = self.b.m.add_file(self.syms.str(sym.module));
        self.bind_field_reads(d, earlier);
        // A default reports its own position, not the caller statement\'s.
        let saved_stmt = self.stmt_pos.take();
        let r = self.expr(d);
        self.stmt_pos = saved_stmt;
        self.hir = saved_hir;
        self.subst = saved_subst;
        self.variant = saved_variant;
        self.file = saved_file;
        let x = r?;
        // The default's value is the argument's own: a borrowed one is the declared copy.
        Ok(self.owned_boundary(x))
    }

    /// A default written as a literal, `none`, an empty list or map, or a constructor call of literals in a
    /// declaration module without checked facts; none when `d` is anything else.
    pub(crate) fn literal_default(
        &mut self,
        module: &ms_check::api::syntax::ModRef,
        d: &Expr,
        t: &ct::Ty,
    ) -> Result<Option<Val>, Error> {
        let mt = self.cx.lower_ty(self.b.m, t)?;
        let val = |v| Val { v, own: false };
        Ok(match &d.kind {
            ExprKind::Bool(b) => Some(val(self.b.bconst(*b))),
            ExprKind::Name(_) if module.default_form(self.syms, d) == DefaultForm::None => {
                Some(val(self.b.opt_none(mt)))
            }
            ExprKind::Number(n) if t.is(ct::Builtin::Int) => {
                ms_check::api::number::canonical(self.syms.str(n))
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
                    .position(|c| c.name == self.syms.str(name) && c.fields.is_empty());
                case.map(|c| Val {
                    v: self.b.alt_new(a, c as u32, &[]),
                    own: true,
                })
            }
            ExprKind::List(items) if items.is_empty() => {
                let v = self.call_runtime("msrt_list_new", &[], mt)?;
                Some(Val { v, own: true })
            }
            // `Map[K, V]()`: an empty map.
            ExprKind::Call { args, .. }
                if args.is_empty()
                    && crate::mapset::is_map_or_set(self.b.m, mt)
                    && t.is(Builtin::Map) =>
            {
                let v = self.map_new(mt)?;
                Some(Val { v, own: true })
            }
            ExprKind::Call { args, .. } if args.iter().all(|a| a.name.is_some()) => {
                let (Some(sym), TyKind::Type(rid)) = (t.symbol(), self.b.m.types.kind(mt).clone())
                else {
                    return Ok(None);
                };
                let Some(decl) = &sym.decl else {
                    return Ok(None);
                };
                let types = ct::fields(t);
                let mut vals = Vec::new();
                for (field, ft) in decl.type_fields().iter().zip(&types) {
                    let given = args
                        .iter()
                        .find(|a| {
                            a.name
                                .as_ref()
                                .is_some_and(|n| self.syms.str(n) == self.syms.str(field.name))
                        })
                        .map(|a| &a.value)
                        .or(field.default.as_ref());
                    let Some(e) = given else {
                        return Ok(None);
                    };
                    let Some(x) = self.literal_default(module, e, &ft.ty)? else {
                        return Ok(None);
                    };
                    vals.push(self.owned(x));
                }
                Some(Val {
                    v: self.b.type_new(rid, &vals),
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
        impl ms_check::api::visit::Visitor for Collect<'_> {
            fn expr(&mut self, e: &Expr) {
                if matches!(e.kind, ExprKind::Name(_)) {
                    self.0.push(e.clone());
                }
            }
        }
        ms_check::api::visit::walk_expr(&mut Collect(&mut found), d);
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
