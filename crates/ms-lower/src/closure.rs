//! Lambdas and calls through function values.

use crate::Error;
use crate::cx::{BoundNativeJob, Cx, Job, JobKind, LambdaJob, NativeThunkJob};
use crate::func::{FnLower, Val};
use ms_check::hir::CallView;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncId, FuncKind, Imm, Mode, Module, Op, Param, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::*;
use std::rc::Rc;

/// Captures use environment indices, never SSA values from the enclosing function.
pub(crate) enum LambdaCapture {
    Local(ct::BindingRef, usize),
    Alias {
        binding: ct::BindingRef,
        root: ct::BindingRef,
        slot: usize,
        steps: Vec<CapturedStep>,
    },
}

pub(crate) enum CapturedStep {
    Field(ct::Name),
    Index(usize),
    Key(usize),
}

impl FnLower<'_> {
    /// A lambda: captures are copied into the closure object.
    pub fn lambda(&mut self, e: &Expr) -> Result<Val, Error> {
        let ExprKind::Lambda(lam) = &e.kind else {
            return Err(Error::new("not a lambda"));
        };
        let captures = self.hir.captures(e);
        let fty = self.emty(e)?;
        let TyKind::Fn(params, ret) = self.b.m.types.kind(fty).clone() else {
            return Err(Error::new("lambda without function type"));
        };
        let mut cap_tys = Vec::new();
        let mut cap_vals = Vec::new();
        let mut saved = Vec::new();
        let changed = lambda_changes(self, lam, &captures);
        for b in &captures {
            if changed.contains(&b.uid)
                && let Some(alias) = self.aliases.get(&b.uid).cloned()
            {
                saved.push(self.capture_alias(b, alias, &mut cap_tys, &mut cap_vals)?);
                continue;
            }
            saved.push(LambdaCapture::Local(b.clone(), cap_vals.len()));
            if changed.contains(&b.uid) {
                // The closure changes this variable: it shares the variable's storage.
                let slot = self
                    .locals
                    .get(&b.uid)
                    .and_then(|l| l.slot)
                    .ok_or_else(|| {
                        Error::new(format!(
                        "a closure here cannot change the captured variable {}: a closure inside a parameter default can only read what it captures",
                        b.name
                    ))
                    })?;
                cap_tys.push(MTy::PTR);
                cap_vals.push(slot);
                continue;
            }
            let x = self.read_local(b)?;
            cap_tys.push(self.ty_of(x.v));
            cap_vals.push(self.owned(x));
        }
        let mut ps = vec![Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        }];
        ps.extend(params.iter().map(|t| Param {
            ty: *t,
            mode: Mode::Borrow,
        }));
        let mut f = ms_mir::ir::Func::new("<anonymous>", ps, ret);
        f.kind = FuncKind::Closure { captures: cap_tys };
        let id = self.b.m.add_func(f);
        let _ = lam;
        self.cx.queue.push(Job {
            func: id,
            kind: JobKind::Lambda(Rc::new(LambdaJob {
                expr: e.clone(),
                hir: self.hir.clone(),
                subst: self.subst.clone(),
                captures: saved,
            })),
        });
        let v = self
            .b
            .emit(Op::ClosureNew, &cap_vals, Imm::Func(id), Some(fty))
            .expect("closure");
        Ok(Val { v, own: true })
    }

    pub(crate) fn capture_alias(
        &mut self,
        b: &ct::BindingRef,
        alias: crate::alias::Alias,
        cap_tys: &mut Vec<MTy>,
        cap_vals: &mut Vec<Value>,
    ) -> Result<LambdaCapture, Error> {
        let slot = self
            .local(&alias.root)?
            .slot
            .ok_or_else(|| Error::new("a captured mutable borrow needs its origin's storage"))?;
        let index = cap_vals.len();
        cap_tys.push(MTy::PTR);
        cap_vals.push(slot);
        let mut steps = Vec::new();
        for step in alias.steps {
            let (value, is_key) = match step {
                crate::alias::AStep::Field(name) => {
                    steps.push(CapturedStep::Field(name));
                    continue;
                }
                crate::alias::AStep::Index(value) => (value, false),
                crate::alias::AStep::Key(var, _) => (self.b.use_var(var), true),
            };
            let index = cap_vals.len();
            cap_tys.push(self.ty_of(value));
            cap_vals.push(self.owned(Val {
                v: value,
                own: false,
            }));
            steps.push(if is_key {
                CapturedStep::Key(index)
            } else {
                CapturedStep::Index(index)
            });
        }
        Ok(LambdaCapture::Alias {
            binding: b.clone(),
            root: alias.root,
            slot: index,
            steps,
        })
    }

    /// A named source function used as a value: a closure forwarding to the instance.
    pub fn function_value(&mut self, e: &Expr, sym: &ct::SymRef) -> Result<Val, Error> {
        let callee = self.callable_of_decl(sym.module, sym.decl.as_ref().map(|d| d.id()))?;
        let vars = ct::variable_set(&sym.variables());
        let mut subst = ct::Subst::new();
        if !vars.is_empty() {
            let want = self.ety(e);
            if !ct::unify(&sym.ty(), &want, &vars, &mut subst) {
                return Err(Error::new(
                    "cannot infer the function value's type arguments",
                ));
            }
        }
        let fid = self.instance(&callee, &subst)?;
        if let Some(thunk) = self.default_thunk(e, fid, &callee, &subst, None, None)? {
            let fty = self.emty(e)?;
            let v = self
                .b
                .emit(Op::ClosureNew, &[], Imm::Func(thunk), Some(fty))
                .expect("closure");
            return Ok(Val { v, own: true });
        }
        let key = format!("thunk:{}", fid.index());
        let thunk = match self.cx.helpers.get(&key) {
            Some(t) => *t,
            None => {
                let proto = self.b.m.funcs[fid.index()].clone();
                let mut ps = vec![Param {
                    ty: MTy::PTR,
                    mode: Mode::Borrow,
                }];
                ps.extend(proto.params.iter().cloned());
                let mut b = FuncBuilder::new(self.b.m, &proto.name, ps, proto.ret);
                b.func_mut().kind = FuncKind::Closure {
                    captures: Vec::new(),
                };
                let args: Vec<_> = b.params().into_iter().skip(1).collect();
                let r = b.call(fid, &args);
                b.ret(Some(r));
                let f = b.into_func();
                let id = self.b.m.add_func(f);
                self.cx.helpers.insert(key, id);
                id
            }
        };
        let fty = self.emty(e)?;
        let v = self
            .b
            .emit(Op::ClosureNew, &[], Imm::Func(thunk), Some(fty))
            .expect("closure");
        Ok(Val { v, own: true })
    }

    /// The thunk of a source callable whose function type takes some parameters as optionals
    /// (the omittable ones): it fills each omitted parameter with its default. `None` when the
    /// function type matches the callable's own parameters.
    fn default_thunk(
        &mut self,
        e: &Expr,
        fid: FuncId,
        callee: &Rc<ms_check::hir::Callable>,
        subst: &ct::Subst,
        recv: Option<MTy>,
        shared: Option<MTy>,
    ) -> Result<Option<FuncId>, Error> {
        let fty = self.emty(e)?;
        let TyKind::Fn(ptys, ret) = self.b.m.types.kind(fty).clone() else {
            return Ok(None);
        };
        let own: Vec<MTy> = self.b.m.funcs[fid.index()]
            .params
            .iter()
            .skip(usize::from(recv.is_some()))
            .map(|p| p.ty)
            .collect();
        if own.len() != ptys.len() || own == ptys {
            return Ok(None);
        }
        let key = format!(
            "default-thunk:{}:{}:{}",
            fid.index(),
            fty.0,
            shared.is_some()
        );
        Ok(Some(self.queue_default_thunk(
            key, fid, &ptys, ret, callee, subst, recv, shared,
        )))
    }

    /// Queues (once per key) the thunk of `callee` taking `ptys`, with optionals for the
    /// parameters whose defaults it fills in its own frame.
    #[allow(clippy::too_many_arguments)]
    fn queue_default_thunk(
        &mut self,
        key: String,
        fid: FuncId,
        ptys: &[MTy],
        ret: MTy,
        callee: &Rc<ms_check::hir::Callable>,
        subst: &ct::Subst,
        recv: Option<MTy>,
        shared: Option<MTy>,
    ) -> FuncId {
        if let Some(t) = self.cx.helpers.get(&key) {
            return *t;
        }
        let mut ps = vec![Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        }];
        ps.extend(ptys.iter().map(|t| Param {
            ty: *t,
            mode: Mode::Borrow,
        }));
        let mut f = ms_mir::ir::Func::new(&self.b.m.funcs[fid.index()].name.clone(), ps, ret);
        f.kind = FuncKind::Closure {
            captures: recv.into_iter().collect(),
        };
        let id = self.b.m.add_func(f);
        self.cx.queue.push(Job {
            func: id,
            kind: JobKind::DefaultThunk(Rc::new(crate::cx::DefaultThunkJob {
                callable: callee.clone(),
                subst: subst.clone(),
                recv,
                shared,
            })),
        });
        self.cx.helpers.insert(key, id);
        id
    }

    /// A direct call omitting a default that contains `try`: the default runs in the callee's
    /// frame, so the call goes through the default thunk. `None` for any other call.
    pub(crate) fn try_default_call(
        &mut self,
        view: &ms_check::hir::CallView<'_>,
        c: &Rc<ms_check::hir::Callable>,
        subst: &ct::Subst,
        e: &Expr,
    ) -> Result<Option<Val>, Error> {
        let Some(func) = c.func.func() else {
            return Ok(None);
        };
        let omits = |i: usize| {
            let name = c.parameters[i].name;
            !view.arguments.iter().any(|a| a.slot.name == name)
        };
        let needs = (0..c.parameters.len()).any(|i| {
            omits(i)
                && func
                    .params
                    .get(i)
                    .and_then(|p| p.default.as_ref())
                    .is_some_and(crate::mutation::has_try)
        });
        if !needs || !self.cx.var_positions(c).is_empty() || c.self_binding.is_some() {
            return Ok(None);
        }
        let fid = self.instance(c, subst)?;
        let ret = self.b.m.funcs[fid.index()].ret;
        let mut ptys = Vec::new();
        for (i, p) in c.parameters.iter().enumerate() {
            let t = self.mty(&ct::sub(&p.ty, subst))?;
            let has_default = func.params.get(i).is_some_and(|q| q.default.is_some());
            ptys.push(if has_default {
                self.b.m.types.opt(t)
            } else {
                t
            });
        }
        let key = format!("direct-default:{}", fid.index());
        let thunk = self.queue_default_thunk(key, fid, &ptys, ret, c, subst, None, None);
        let fty = self.b.m.types.func(ptys.clone(), ret);
        let mut slots: Vec<Option<Value>> = vec![None; ptys.len()];
        for a in view.arguments.iter() {
            let x = self.expr(a.expr)?;
            if self.dead {
                return Ok(Some(x));
            }
            let x = match &a.wrap_optional {
                Some(_) => {
                    let o = self.owned(x);
                    let v = self.b.opt_some(o);
                    Val { v, own: true }
                }
                None => x,
            };
            let at = c
                .parameters
                .iter()
                .position(|p| p.name == a.slot.name)
                .ok_or_else(|| Error::new(format!("no parameter {}", a.slot.name)))?;
            let x = self.lift_argument(x, ptys[at]);
            slots[at] = Some(self.borrow(x));
        }
        let mut args = Vec::new();
        for (i, s) in slots.into_iter().enumerate() {
            args.push(match s {
                Some(v) => v,
                None => self.b.opt_none(ptys[i]),
            });
        }
        let fv = self
            .b
            .emit(Op::ClosureNew, &[], Imm::Func(thunk), Some(fty))
            .expect("closure");
        self.at(e.pos);
        let v = self.b.call_ind(fv, &args);
        self.drop_value(fv);
        Ok(Some(self.val(v, true)))
    }

    /// The slot of the variable `left` names, and its type: a method value that changes its
    /// receiver shares that variable. `None` when `left` is not a whole variable in memory.
    fn shared_receiver(&self, left: &Expr) -> Option<(Value, MTy)> {
        let ms_check::hir::Resolution::Local(b) = self.hir.resolution(left) else {
            return None;
        };
        let l = self.locals.get(&b.uid)?;
        Some((l.slot?, l.ty))
    }

    /// Queues (once per key) the thunk of a source method that changes its receiver, which
    /// the closure holds as the address of the variable.
    fn shared_method_thunk(
        &mut self,
        key: String,
        name: &str,
        fid: FuncId,
        params: &[MTy],
        ret: MTy,
    ) -> FuncId {
        if let Some(t) = self.cx.helpers.get(&key) {
            return *t;
        }
        let mut ps = vec![Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        }];
        ps.extend(params.iter().map(|t| Param {
            ty: *t,
            mode: Mode::Borrow,
        }));
        let mut b = FuncBuilder::new(self.b.m, &format!("<{name}>"), ps, ret);
        b.func_mut().kind = FuncKind::Closure {
            captures: vec![MTy::PTR],
        };
        let args = b.params();
        let slot = b
            .emit(Op::ClosureCap, &[args[0]], Imm::Idx(0), Some(MTy::PTR))
            .expect("capture");
        let mut all = vec![slot];
        all.extend_from_slice(&args[1..]);
        let r = b.call(fid, &all);
        b.ret(Some(r));
        let f = b.into_func();
        let id = self.b.m.add_func(f);
        self.cx.helpers.insert(key, id);
        id
    }

    /// A method used as a value (`view.read`): a closure holding a copy of the receiver.
    pub fn bound_method(&mut self, e: &Expr, left: &Expr, m: &ct::MethodRef) -> Result<Val, Error> {
        if let Some(value) = self.bound_alias_method(e, left, m)? {
            return Ok(value);
        }
        let fty = self.emty(e)?;
        let TyKind::Fn(params, ret) = self.b.m.types.kind(fty).clone() else {
            return Err(Error::new("method value without function type"));
        };
        let recv_ty = self.ety(left);
        let recv_mty = self.mty(&recv_ty)?;
        let name = m.name().map(|n| n.to_string()).unwrap_or_default();
        // How the thunk reaches the method.
        let (key, callee) = if let TyKind::Iface(iface) = self.b.m.types.kind(recv_mty).clone() {
            let k = self.b.m.ifaces[iface.index()]
                .methods
                .iter()
                .position(|s| s.name == name)
                .ok_or_else(|| Error::new(format!("no interface method {name}")))?;
            let shared = if crate::mutation::method_changes_receiver(m, &self.cx.mutated) {
                self.shared_receiver(left)
            } else {
                None
            };
            let held_ty = if shared.is_some() { MTy::PTR } else { recv_mty };
            // A function type that takes optionals the interface method takes plainly.
            if self.b.m.ifaces[iface.index()].methods[k].params != params {
                let key = format!("iface-thunk:{}:{k}:{}:{}", iface.0, fty.0, shared.is_some());
                let thunk = match self.cx.helpers.get(&key) {
                    Some(t) => *t,
                    None => {
                        let mut ps = vec![Param {
                            ty: MTy::PTR,
                            mode: Mode::Borrow,
                        }];
                        ps.extend(params.iter().map(|t| Param {
                            ty: *t,
                            mode: Mode::Borrow,
                        }));
                        let mut f = ms_mir::ir::Func::new(&format!("<{name}>"), ps, ret);
                        f.kind = FuncKind::Closure {
                            captures: vec![held_ty],
                        };
                        let id = self.b.m.add_func(f);
                        self.cx.queue.push(Job {
                            func: id,
                            kind: JobKind::IfaceThunk(Rc::new(crate::cx::IfaceThunkJob {
                                iface,
                                index: k as u32,
                                method: m.clone(),
                                hir: self.hir.clone(),
                                shared: shared.is_some(),
                            })),
                        });
                        self.cx.helpers.insert(key, id);
                        id
                    }
                };
                if let Some((slot, _)) = shared {
                    let v = self
                        .b
                        .emit(Op::ClosureNew, &[slot], Imm::Func(thunk), Some(fty))
                        .expect("closure");
                    return Ok(Val { v, own: true });
                }
                let recv = self.expr(left)?;
                if self.dead {
                    return Ok(recv);
                }
                let held = self.owned(recv);
                let v = self
                    .b
                    .emit(Op::ClosureNew, &[held], Imm::Func(thunk), Some(fty))
                    .expect("closure");
                return Ok(Val { v, own: true });
            }
            if let Some((slot, _)) = shared {
                let key = format!("bound-shared:iface{}:{k}:{}", iface.0, fty.0);
                let thunk = match self.cx.helpers.get(&key) {
                    Some(t) => *t,
                    None => {
                        let mut ps = vec![Param {
                            ty: MTy::PTR,
                            mode: Mode::Borrow,
                        }];
                        ps.extend(params.iter().map(|t| Param {
                            ty: *t,
                            mode: Mode::Borrow,
                        }));
                        let mut b = FuncBuilder::new(self.b.m, &format!("<{name}>"), ps, ret);
                        b.func_mut().kind = FuncKind::Closure {
                            captures: vec![MTy::PTR],
                        };
                        let args = b.params();
                        let ptr = b
                            .emit(Op::ClosureCap, &[args[0]], Imm::Idx(0), Some(MTy::PTR))
                            .expect("capture");
                        let this = b
                            .emit(Op::Load, &[ptr], Imm::Ty(recv_mty), Some(recv_mty))
                            .expect("load");
                        let r = b.call_method(iface, k as u32, this, &args[1..]);
                        b.ret(Some(r));
                        let f = b.into_func();
                        let id = self.b.m.add_func(f);
                        self.cx.helpers.insert(key, id);
                        id
                    }
                };
                let v = self
                    .b
                    .emit(Op::ClosureNew, &[slot], Imm::Func(thunk), Some(fty))
                    .expect("closure");
                return Ok(Val { v, own: true });
            }
            (
                format!("bound:iface{}:{k}", iface.0),
                Err((iface, k as u32)),
            )
        } else {
            let im = if m.native.as_str() == "contract" {
                self.contract_impl(m, &recv_ty)
                    .ok_or_else(|| Error::new(format!("{recv_ty} has no method {name}")))?
            } else {
                m.clone()
            };
            if !im.native.is_empty() {
                return Err(Error::new(format!("unsupported member access .{name}")));
            }
            let decl = im
                .decl
                .as_ref()
                .ok_or_else(|| Error::new("method without declaration"))?;
            let c = self.callable_of_decl(im.module, Some(decl.id()))?;
            let declared = self
                .cx
                .methods
                .iter()
                .find(|d| {
                    d.module == im.module && d.decl.as_ref().map(|x| x.id()) == Some(decl.id())
                })
                .cloned()
                .unwrap_or_else(|| im.clone());
            let mut subst = ct::Subst::new();
            if !ct::unify(
                &declared.receiver,
                &recv_ty,
                &ct::variable_set(&declared.variables),
                &mut subst,
            ) {
                return Err(Error::new("cannot bind method receiver type"));
            }
            let vars = self.cx.var_positions(&c);
            if vars.iter().any(|v| *v != 0) {
                return Err(Error::new("method value with changed parameters"));
            }
            let fid = self.instance(&c, &subst)?;
            let shared = if vars.is_empty() {
                None
            } else {
                self.shared_receiver(left)
            };
            if let Some((slot, _)) = shared {
                // The value shares the variable: the thunk changes it in place.
                let ptr_ty = Some(MTy::PTR);
                let thunk = match self.default_thunk(e, fid, &c, &subst, ptr_ty, Some(recv_mty))? {
                    Some(t) => t,
                    None => {
                        let key = format!("bound-shared:{}:{}", fid.index(), fty.0);
                        self.shared_method_thunk(key, &name, fid, &params, ret)
                    }
                };
                let v = self
                    .b
                    .emit(Op::ClosureNew, &[slot], Imm::Func(thunk), Some(fty))
                    .expect("closure");
                return Ok(Val { v, own: true });
            }
            if let Some(thunk) = self.default_thunk(e, fid, &c, &subst, Some(recv_mty), None)? {
                let recv = self.expr(left)?;
                if self.dead {
                    return Ok(recv);
                }
                let held = self.owned(recv);
                let v = self
                    .b
                    .emit(Op::ClosureNew, &[held], Imm::Func(thunk), Some(fty))
                    .expect("closure");
                return Ok(Val { v, own: true });
            }
            (
                format!("bound:{}", fid.index()),
                Ok((fid, !vars.is_empty())),
            )
        };
        let recv = self.expr(left)?;
        if self.dead {
            return Ok(recv);
        }
        let held = self.owned(recv);
        let key = format!("{key}:{}", fty.0);
        let thunk = match self.cx.helpers.get(&key) {
            Some(t) => *t,
            None => {
                let mut ps = vec![Param {
                    ty: MTy::PTR,
                    mode: Mode::Borrow,
                }];
                ps.extend(params.iter().map(|t| Param {
                    ty: *t,
                    mode: Mode::Borrow,
                }));
                let mut b = FuncBuilder::new(self.b.m, &format!("<{name}>"), ps, ret);
                b.func_mut().kind = FuncKind::Closure {
                    captures: vec![recv_mty],
                };
                let args = b.params();
                let this = b
                    .emit(Op::ClosureCap, &[args[0]], Imm::Idx(0), Some(recv_mty))
                    .expect("capture");
                let rest = &args[1..];
                let r = match callee {
                    Err((iface, k)) => b.call_method(iface, k, this, rest),
                    Ok((fid, false)) => {
                        let mut all = vec![this];
                        all.extend_from_slice(rest);
                        b.call(fid, &all)
                    }
                    Ok((fid, true)) => call_changing_receiver(&mut b, fid, this, recv_mty, rest),
                };
                b.ret(Some(r));
                let f = b.into_func();
                let id = self.b.m.add_func(f);
                self.cx.helpers.insert(key, id);
                id
            }
        };
        let v = self
            .b
            .emit(Op::ClosureNew, &[held], Imm::Func(thunk), Some(fty))
            .expect("closure");
        Ok(Val { v, own: true })
    }

    /// A native function used as a value: a closure forwarding to the native.
    pub fn native_function_value(&mut self, e: &Expr, sym: &ct::SymRef) -> Result<Val, Error> {
        let want = self.ety(e);
        let declared = sym.ty();
        let vars = ct::variable_set(&sym.variables());
        let mut subst = ct::Subst::new();
        if !vars.is_empty() && !ct::unify(&declared, &want, &vars, &mut subst) {
            return Err(Error::new(
                "cannot infer the function value's type arguments",
            ));
        }
        let fty = self.emty(e)?;
        let TyKind::Fn(ptys, ret) = self.b.m.types.kind(fty).clone() else {
            return Err(Error::new("native function value without function type"));
        };
        let key = format!("native-thunk:{}:{}", sym.native, fty.0);
        let thunk = match self.cx.helpers.get(&key) {
            Some(f) => *f,
            None => {
                let mut ps = vec![Param {
                    ty: MTy::PTR,
                    mode: Mode::Borrow,
                }];
                ps.extend(ptys.iter().map(|t| Param {
                    ty: *t,
                    mode: Mode::Borrow,
                }));
                let mut f = ms_mir::ir::Func::new(sym.name.as_str(), ps, ret);
                f.kind = FuncKind::Closure {
                    captures: Vec::new(),
                };
                let id = self.b.m.add_func(f);
                let params = declared
                    .params
                    .iter()
                    .map(|p| ct::Param {
                        name: p.name,
                        ty: ct::sub(&p.ty, &subst),
                    })
                    .collect();
                self.cx.queue.push(Job {
                    func: id,
                    kind: JobKind::NativeThunk(Rc::new(NativeThunkJob {
                        native: sym.native.to_string(),
                        params,
                        result: ct::sub(&declared.result_ty(), &subst),
                        sym: sym.clone(),
                        hir: self.hir.clone(),
                    })),
                });
                self.cx.helpers.insert(key, id);
                id
            }
        };
        let v = self
            .b
            .emit(Op::ClosureNew, &[], Imm::Func(thunk), Some(fty))
            .expect("closure");
        Ok(Val { v, own: true })
    }

    /// `value.method` of a native method without a call: a closure holding the receiver.
    pub fn bound_native_method(
        &mut self,
        e: &Expr,
        left: &Expr,
        m: &ct::MethodRef,
    ) -> Result<Val, Error> {
        if let Some(value) = self.bound_alias_method(e, left, m)? {
            return Ok(value);
        }
        let shared = if ms_check::effects::collection_mutation(m) {
            self.shared_receiver(left)
        } else {
            None
        };
        let recv = match shared {
            Some((slot, _)) => Val {
                v: slot,
                own: false,
            },
            None => self.expr(left)?,
        };
        if self.dead {
            return Ok(recv);
        }
        // A shared receiver is the address of the variable the closure changes.
        let rty = shared.map_or_else(|| self.ty_of(recv.v), |(_, t)| t);
        let held = if shared.is_some() { MTy::PTR } else { rty };
        let fty = self.emty(e)?;
        let TyKind::Fn(ptys, ret) = self.b.m.types.kind(fty).clone() else {
            return Err(Error::new("method value without function type"));
        };
        let scope = self
            .evidence_of(&[self.hir.ty(left)])
            .unwrap_or(self.hir.data.file);
        let key = format!(
            "bound-native:{}:{}:{}:{}{}",
            m.native,
            rty.0,
            fty.0,
            shared.is_some(),
            if self.cx.holds_extension(self.b.m, rty) || self.cx.holds_extension(self.b.m, fty) {
                format!("@{scope}")
            } else {
                String::new()
            }
        );
        let thunk = match self.cx.helpers.get(&key) {
            Some(f) => *f,
            None => {
                let mut ps = vec![Param {
                    ty: MTy::PTR,
                    mode: Mode::Borrow,
                }];
                ps.extend(ptys.iter().map(|t| Param {
                    ty: *t,
                    mode: Mode::Borrow,
                }));
                let mut f = ms_mir::ir::Func::new(m.native.as_str(), ps, ret);
                f.kind = FuncKind::Closure {
                    captures: vec![held],
                };
                let id = self.b.m.add_func(f);
                self.cx.queue.push(Job {
                    func: id,
                    kind: JobKind::BoundNative(Rc::new(BoundNativeJob {
                        method: m.clone(),
                        hir: self.hir.clone(),
                        shared: shared.map(|(_, t)| t),
                        scope,
                    })),
                });
                self.cx.helpers.insert(key, id);
                id
            }
        };
        let captured = if shared.is_some() {
            recv.v
        } else {
            self.owned(recv)
        };
        let v = self
            .b
            .emit(Op::ClosureNew, &[captured], Imm::Func(thunk), Some(fty))
            .expect("closure");
        Ok(Val { v, own: true })
    }

    /// `value.to_string` without a call: a closure holding the receiver that renders it.
    pub fn bound_to_string(&mut self, left: &Expr) -> Result<Val, Error> {
        let recv = self.expr(left)?;
        if self.dead {
            return Ok(recv);
        }
        let t = self.ty_of(recv.v);
        let key = format!("tostring-thunk:{}", t.0);
        let thunk = match self.cx.helpers.get(&key) {
            Some(f) => *f,
            None => {
                let ps = vec![Param {
                    ty: MTy::PTR,
                    mode: Mode::Borrow,
                }];
                let mut b = FuncBuilder::new(self.b.m, "to_string", ps, MTy::STR);
                b.func_mut().kind = FuncKind::Closure { captures: vec![t] };
                let env = b.params()[0];
                let cap = b
                    .emit(Op::ClosureCap, &[env], Imm::Idx(0), Some(t))
                    .expect("capture");
                let text = match crate::text::scalar_text(&mut b, t, cap, false) {
                    Some((v, true)) => v,
                    Some((v, false)) => b
                        .emit(Op::Copy, &[v], Imm::None, Some(MTy::STR))
                        .expect("copy"),
                    None => {
                        let fmt = self.cx.format_fn(b.m, t, false);
                        let top = b.iconst(0);
                        b.call(fmt, &[cap, top])
                    }
                };
                b.ret(Some(text));
                let f = b.into_func();
                let id = self.b.m.add_func(f);
                self.cx.helpers.insert(key, id);
                id
            }
        };
        let captured = self.owned(recv);
        let fty = self.b.m.types.func(Vec::new(), MTy::STR);
        let v = self
            .b
            .emit(Op::ClosureNew, &[captured], Imm::Func(thunk), Some(fty))
            .expect("closure");
        Ok(Val { v, own: true })
    }

    /// A supplied argument for a parameter that crosses function values as an optional.
    fn lift_argument(&mut self, x: Val, want: MTy) -> Val {
        if self.ty_of(x.v) == want {
            return x;
        }
        let TyKind::Opt(inner) = self.b.m.types.kind(want).clone() else {
            return x;
        };
        if self.ty_of(x.v) != inner {
            return x;
        }
        let o = self.owned(x);
        let v = self.b.opt_some(o);
        Val { v, own: true }
    }

    /// An optional parameter of a function value read as its plain value: the supplied one, or
    /// the default.
    pub(crate) fn unlift_param(
        &mut self,
        opt: Value,
        default: &mut dyn FnMut(&mut Self) -> Result<Val, Error>,
    ) -> Result<Val, Error> {
        let TyKind::Opt(inner) = self.b.m.types.kind(self.ty_of(opt)).clone() else {
            return Err(Error::new("parameter is not optional"));
        };
        let has = self.b.opt_is_some(opt);
        self.two_ways(
            has,
            inner,
            &mut |s| {
                let u = s.b.opt_get(opt);
                Ok(Some(s.owned(Val { v: u, own: false })))
            },
            &mut |s| {
                let d = default(s)?;
                Ok(Some(s.owned(d)))
            },
        )
    }

    /// A call whose callee is a function value.
    pub fn call_value(&mut self, e: &Expr, view: &CallView<'_>) -> Result<Val, Error> {
        let ExprKind::Call { callee, .. } = &e.kind else {
            return Err(Error::new("not a call"));
        };
        let f = self.expr(callee)?;
        if self.dead {
            return Ok(f);
        }
        // The callee is fixed before the arguments run, which may reassign its variable.
        let f = if !f.own
            && matches!(
                self.hir.resolution(callee),
                ms_check::hir::Resolution::Local(_)
            ) {
            let v = self.owned(f);
            Val { v, own: true }
        } else {
            f
        };
        let fv = self.borrow(f);
        let declared = self.ety(callee).params.clone();
        let ftype = self.ty_of(f.v);
        let TyKind::Fn(ptys, _) = self.b.m.types.kind(ftype).clone() else {
            return Err(Error::new("call of a non-function value"));
        };
        let mut slots: Vec<Option<Value>> = vec![None; ptys.len()];
        for (i, a) in view.arguments.iter().enumerate() {
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
            let at = declared
                .iter()
                .position(|p| p.name == a.slot.name)
                .unwrap_or(i);
            let x = self.lift_argument(x, ptys[at]);
            slots[at] = Some(self.borrow(x));
        }
        // An omitted parameter of a function type is an optional one: it is `none`.
        let mut args = Vec::new();
        for (i, s) in slots.into_iter().enumerate() {
            args.push(match s {
                Some(v) => v,
                None if matches!(self.b.m.types.kind(ptys[i]), TyKind::Opt(_)) => {
                    self.b.opt_none(ptys[i])
                }
                None => return Err(Error::new("missing argument in a call of a function value")),
            });
        }
        self.at(e.pos);
        let cleanups = self.protect_call_temps();
        let v = self.b.call_ind(fv, &args);
        self.discard_call_temps(cleanups)?;
        Ok(self.val(v, true))
    }
}

/// Calls a method that changes its receiver: the closure's copy goes into a slot the callee
/// takes from and puts back into, and takes the change.
fn call_changing_receiver(
    b: &mut FuncBuilder<'_>,
    fid: FuncId,
    this: Value,
    recv_ty: MTy,
    rest: &[Value],
) -> Value {
    let drops = b.m.needs_drop(recv_ty);
    let own = if drops {
        b.emit(Op::Copy, &[this], Imm::None, Some(recv_ty))
            .expect("copy")
    } else {
        this
    };
    let slot = b
        .emit(Op::Slot, &[], Imm::Ty(recv_ty), Some(MTy::PTR))
        .expect("slot");
    let put = if drops { Op::Put } else { Op::Store };
    b.emit(put, &[slot, own], Imm::None, None);
    let mut all = vec![slot];
    all.extend_from_slice(rest);
    let r = b.call(fid, &all);
    let take = if drops { Op::Take } else { Op::Load };
    let after = b
        .emit(take, &[slot], Imm::Ty(recv_ty), Some(recv_ty))
        .expect("take");
    if drops {
        b.emit(Op::Drop, &[after], Imm::None, None);
    }
    r
}

/// Lowers a thunk that fills the defaults of the parameters a function value takes as optionals.
pub(crate) fn build_default_thunk(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &crate::cx::DefaultThunkJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let hir = cx.module(job.callable.module.file)?;
    let file = m.add_file(job.callable.module.file.as_str());
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    let mut fl = FnLower::new(cx, b, hir, job.subst.clone(), file, proto.ret);
    let result = lower_default_thunk(&mut fl, job);
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

fn lower_default_thunk(
    fl: &mut FnLower<'_>,
    job: &crate::cx::DefaultThunkJob,
) -> Result<(), Error> {
    let params = fl.b.params();
    let mut recv = job.recv.map(|t| Val {
        v: fl
            .b
            .emit(Op::ClosureCap, &[params[0]], Imm::Idx(0), Some(t))
            .expect("capture"),
        own: false,
    });
    // A shared receiver is the variable's address; the defaults read its current value.
    let slot = job.shared.and(recv).map(|r| r.v);
    if let (Some(t), Some(ptr)) = (job.shared, slot) {
        let v =
            fl.b.emit(Op::Load, &[ptr], Imm::Ty(t), Some(t))
                .expect("load");
        recv = Some(Val { v, own: false });
    }
    let callee = job.callable.clone();
    let vars = fl.cx.var_positions(&callee);
    let changes_receiver = vars == [0] && job.recv.is_some();
    if !vars.is_empty() && !changes_receiver {
        return Err(Error::new(
            "a function value with defaults cannot change its parameters",
        ));
    }
    let mut slots: Vec<Option<Val>> = vec![None; callee.parameters.len()];
    for i in 0..slots.len() {
        let v = params[i + 1];
        let declared = fl.mty(&callee.parameters[i].ty)?;
        slots[i] = Some(if fl.ty_of(v) == declared {
            Val { v, own: false }
        } else {
            let earlier = slots.clone();
            fl.unlift_param(v, &mut |s| {
                let mut earlier = earlier.clone();
                s.default_argument(&callee, i, &job.subst, &mut earlier, recv)
            })?
        });
    }
    let fid = fl.instance(&callee, &job.subst)?;
    let mut vals: Vec<Value> = Vec::new();
    for s in slots.into_iter().flatten() {
        vals.push(fl.borrow(s));
    }
    let r = match (recv, changes_receiver) {
        (Some(_), true) if slot.is_some() => {
            let mut all = vec![slot.expect("slot")];
            all.extend(vals);
            fl.b.call(fid, &all)
        }
        (Some(this), true) => {
            let recv_ty = fl.ty_of(this.v);
            call_changing_receiver(&mut fl.b, fid, this.v, recv_ty, &vals)
        }
        _ => {
            let mut all: Vec<Value> = recv.iter().map(|r| r.v).collect();
            all.extend(vals);
            fl.b.call(fid, &all)
        }
    };
    let out = fl.val(r, true);
    fl.emit_return(Some(out));
    Ok(())
}

/// Lowers the body of a queued interface method value.
pub(crate) fn build_iface_thunk(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &crate::cx::IfaceThunkJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let FuncKind::Closure { captures } = proto.kind.clone() else {
        return Err(Error::new("interface method value without closure kind"));
    };
    let file = m.add_file(job.hir.data.file.as_str());
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    let mut fl = FnLower::new(cx, b, job.hir.clone(), ct::Subst::new(), file, proto.ret);
    let result = lower_iface_thunk(&mut fl, job, captures[0]);
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

fn lower_iface_thunk(
    fl: &mut FnLower<'_>,
    job: &crate::cx::IfaceThunkJob,
    recv_ty: MTy,
) -> Result<(), Error> {
    let params = fl.b.params();
    let held = if job.shared { MTy::PTR } else { recv_ty };
    let mut this =
        fl.b.emit(Op::ClosureCap, &[params[0]], Imm::Idx(0), Some(held))
            .expect("capture");
    if job.shared {
        // The closure shares the variable: the call sees its current value.
        this =
            fl.b.emit(Op::Load, &[this], Imm::Ty(recv_ty), Some(recv_ty))
                .expect("load");
    }
    let func = job.method.decl.as_ref().and_then(|d| d.func());
    let args =
        fl.thunk_native_args(job.method.module, func, &job.method.ty.params, &params[1..])?;
    let vals: Vec<Value> = args.iter().map(|a| fl.borrow(a.val)).collect();
    let r = fl.b.call_method(job.iface, job.index, this, &vals);
    let out = fl.val(r, true);
    fl.emit_return(Some(out));
    Ok(())
}

/// Lowers the body of a queued native function value.
pub(crate) fn build_native_thunk(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &NativeThunkJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let file = m.add_file(job.hir.data.file.as_str());
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    let mut fl = FnLower::new(cx, b, job.hir.clone(), ct::Subst::new(), file, proto.ret);
    let result = lower_native_thunk(&mut fl, job);
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

fn lower_native_thunk(fl: &mut FnLower<'_>, job: &NativeThunkJob) -> Result<(), Error> {
    let params = fl.b.params();
    let func = job.sym.decl.as_ref().and_then(|d| d.func());
    let mut args = fl.thunk_native_args(job.sym.module, func, &job.params, &params[1..])?;
    let ret = fl.ret_ty;
    match crate::native::json_native(job.native.as_str()) {
        "json/parse" | "json/stringify" => {
            // Generic natives with their own lowering: the type argument comes from the instance.
            fl.fill_native_defaults(job.sym.module, func, &job.params, &mut args)?;
            let have = fl.mty(&job.result)?;
            let r = if crate::native::json_native(&job.native) == "json/parse" {
                let t = job.result.args.first().cloned();
                let t = t.ok_or_else(|| Error::new("parse without a result type"))?;
                fl.json_parse(&t, have, &args)?
            } else {
                let value = job.params.iter().find(|p| p.name.as_str() == "value");
                let t = value.map(|p| p.ty.clone());
                let t = t.ok_or_else(|| Error::new("stringify without a value"))?;
                fl.json_stringify(t, have, &args)?
            };
            let out = fl.fit_ty(r, &job.result, ret)?;
            fl.emit_return(Some(out));
            return Ok(());
        }
        "html/parse" => {
            fl.fill_native_defaults(job.sym.module, func, &job.params, &mut args)?;
            let node = job.result.args.first().cloned();
            let node = node.ok_or_else(|| Error::new("parse without a node type"))?;
            let out = fl.html_parse(&node, ret, &args)?;
            fl.emit_return(Some(out));
            return Ok(());
        }
        "random/secure_int" | "random/uuid_v4" | "random/float" | "random/shuffle"
        | "random/choice" => {
            let out = fl.random_with(&job.native, &args, ret)?;
            fl.emit_return(Some(out));
            return Ok(());
        }
        "io/stdout" | "io/stderr" => {
            let out = fl.std_stream(ret, job.native == "io/stderr")?;
            fl.emit_return(Some(out));
            return Ok(());
        }
        "time/clock" | "time/wall_clock" => {
            let out = fl.time_clock(ret, job.native == "time/wall_clock")?;
            fl.emit_return(Some(out));
            return Ok(());
        }
        "io/read_all" | "io/copy" => {
            fl.fill_native_defaults(job.sym.module, func, &job.params, &mut args)?;
            let kind = if job.native == "io/copy" {
                crate::streamloop::Loop::Copy
            } else {
                crate::streamloop::Loop::ReadAll
            };
            let out = fl.stream_with(kind, &args, ret)?;
            fl.emit_return(Some(out));
            return Ok(());
        }
        other => {
            let handle = crate::natiface::HANDLE_FUNCTIONS
                .iter()
                .find(|f| f.0 == other);
            if let Some(&(_, module, make, constant)) = handle {
                let out = fl.handle_interface(&job.result, ret, module, make, constant)?;
                fl.emit_return(Some(out));
                return Ok(());
            }
        }
    }
    let out = fl.native_call(&job.native, &job.params, &args, ret)?;
    fl.emit_return(Some(out));
    Ok(())
}

impl FnLower<'_> {
    /// The arguments of a native called through a function value: a parameter the function type
    /// made optional is read as its supplied value or the declared default.
    fn thunk_native_args(
        &mut self,
        module: ct::Name,
        func: Option<&ms_syntax::ast::Func>,
        params: &[ct::Param],
        vals: &[Value],
    ) -> Result<Vec<crate::native::NArg>, Error> {
        let mut args: Vec<crate::native::NArg> = Vec::new();
        for (i, (p, v)) in params.iter().zip(vals).enumerate() {
            let lifted = !p.ty.is_std("Optional")
                && matches!(self.b.m.types.kind(self.ty_of(*v)), TyKind::Opt(_));
            let val = if lifted {
                self.unlift_param(*v, &mut |s| {
                    let mut tmp: Vec<crate::native::NArg> = params
                        .iter()
                        .enumerate()
                        .filter(|(j, _)| *j != i)
                        .map(|(_, q)| crate::native::NArg {
                            name: q.name,
                            val: Val { v: *v, own: false },
                            wrapped: false,
                        })
                        .collect();
                    let before = tmp.len();
                    s.fill_native_defaults(module, func, params, &mut tmp)?;
                    tmp.get(before)
                        .map(|a| a.val)
                        .ok_or_else(|| Error::new("omitted parameter without a default"))
                })?
            } else {
                Val { v: *v, own: false }
            };
            args.push(crate::native::NArg {
                name: p.name,
                val,
                wrapped: false,
            });
        }
        Ok(args)
    }
}

/// Lowers the body of a queued bound native method.
pub(crate) fn build_bound_native(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &BoundNativeJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let FuncKind::Closure { captures } = proto.kind.clone() else {
        return Err(Error::new("bound method without closure kind"));
    };
    let file = m.add_file(job.hir.data.file.as_str());
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    let mut fl = FnLower::new(cx, b, job.hir.clone(), ct::Subst::new(), file, proto.ret);
    fl.scope_override = Some(job.scope);
    let result = lower_bound_native(&mut fl, job, job.shared.unwrap_or(captures[0]));
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

fn lower_bound_native(
    fl: &mut FnLower<'_>,
    job: &BoundNativeJob,
    recv_ty: MTy,
) -> Result<(), Error> {
    let params = fl.b.params();
    let env = params[0];
    let held = if job.shared.is_some() {
        MTy::PTR
    } else {
        recv_ty
    };
    let cap =
        fl.b.emit(Op::ClosureCap, &[env], Imm::Idx(0), Some(held))
            .expect("capture");
    let recv = Val { v: cap, own: false };
    let func = job.method.decl.as_ref().and_then(|d| d.func());
    let args =
        fl.thunk_native_args(job.method.module, func, &job.method.ty.params, &params[1..])?;
    let ret = fl.ret_ty;
    if job.shared.is_some() {
        let out = fl.shared_native_call(&job.method, cap, recv_ty, &args, ret)?;
        fl.emit_return(Some(out));
        return Ok(());
    }
    let out = fl.bound_native_call(&job.method, recv, &args, ret)?;
    fl.emit_return(Some(out));
    Ok(())
}

/// Lowers the body of a queued lambda.
pub(crate) fn build_lambda(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &LambdaJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let FuncKind::Closure { captures } = proto.kind.clone() else {
        return Err(Error::new("lambda function without closure kind"));
    };
    let file = m.add_file(job.hir.data.file.as_str());
    let mut b = FuncBuilder::new(m, "<anonymous>", proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    let mut fl = FnLower::new(cx, b, job.hir.clone(), job.subst.clone(), file, proto.ret);
    let result = lower_lambda_body(&mut fl, job, &captures);
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

pub(crate) fn restore_alias_capture(
    fl: &mut FnLower<'_>,
    capture: &LambdaCapture,
    values: &[Value],
) -> Result<bool, Error> {
    let LambdaCapture::Alias {
        binding,
        root,
        slot,
        steps,
    } = capture
    else {
        return Ok(false);
    };
    let ty = fl.mty(&root.ty)?;
    let var = fl.b.declare_var(ty, Mode::Borrow);
    fl.locals.insert(
        root.uid,
        crate::func::Local {
            var,
            ty,
            slot: Some(values[*slot]),
        },
    );
    let steps = steps
        .iter()
        .map(|step| match step {
            CapturedStep::Field(name) => crate::alias::AStep::Field(*name),
            CapturedStep::Index(index) => crate::alias::AStep::Index(values[*index]),
            CapturedStep::Key(index) => {
                let value = values[*index];
                let var = fl.b.declare_var(fl.ty_of(value), Mode::Borrow);
                fl.b.def_var(var, value);
                crate::alias::AStep::Key(var, None)
            }
        })
        .collect();
    fl.aliases.insert(
        binding.uid,
        crate::alias::Alias {
            root: root.clone(),
            steps,
        },
    );
    Ok(true)
}

fn lower_lambda_body(fl: &mut FnLower<'_>, job: &LambdaJob, captures: &[MTy]) -> Result<(), Error> {
    let ExprKind::Lambda(lam) = &job.expr.kind else {
        return Err(Error::new("not a lambda"));
    };
    let params = fl.b.params();
    let env = params[0];
    let mutated = lambda_mutated(fl, lam);
    fl.slotted = slotted_in(fl, &lam.body);
    let values: Vec<_> = captures
        .iter()
        .enumerate()
        .map(|(i, t)| {
            fl.b.emit(Op::ClosureCap, &[env], Imm::Idx(i as u32), Some(*t))
                .expect("capture")
        })
        .collect();
    for capture in &job.captures {
        if restore_alias_capture(fl, capture, &values)? {
            continue;
        }
        let LambdaCapture::Local(b, index) = capture else {
            unreachable!()
        };
        let v = values[*index];
        let t = &captures[*index];
        if mutated.contains(&b.uid) && *t == MTy::PTR && fl.mty(&b.ty).is_ok() {
            // The closure shares the variable's storage with its maker.
            let ty = fl.mty(&b.ty)?;
            let var = fl.b.declare_var(ty, Mode::Borrow);
            fl.locals.insert(
                b.uid,
                crate::func::Local {
                    var,
                    ty,
                    slot: Some(v),
                },
            );
        } else if mutated.contains(&b.uid) {
            // The closure changes its own snapshot: work on an owned copy.
            fl.bind_local(b, Val { v, own: false });
        } else {
            fl.bind_borrowed(b, v);
        }
    }
    let bindings = fl.hir.lambda_parameters(&job.expr);
    for (i, (b, v)) in bindings.iter().zip(params.iter().skip(1)).enumerate() {
        let lifted =
            matches!(fl.b.m.types.kind(fl.ty_of(*v)), TyKind::Opt(_)) && !b.ty.is_std("Optional");
        if lifted {
            let d = lam.params.get(i).and_then(|p| p.default.as_ref());
            let Some(d) = d else {
                return Err(Error::new("optional parameter without a default"));
            };
            let x = fl.unlift_param(*v, &mut |s| s.expr(d))?;
            fl.bind_local(b, x);
        } else if mutated.contains(&b.uid) && fl.needs_drop(fl.ty_of(*v)) {
            // A parameter the body changes is the lambda's own copy.
            fl.bind_local(b, Val { v: *v, own: false });
        } else {
            fl.bind_borrowed(b, *v);
        }
    }
    fl.stmts(&lam.body)?;
    if !fl.dead {
        if fl.ret_ty != MTy::UNIT {
            return Err(Error::new("lambda can fall off its end"));
        }
        let u = fl.b.unit();
        fl.emit_return(Some(Val { v: u, own: false }));
    }
    Ok(())
}

/// The locals a lambda's body changes.
fn lambda_mutated(fl: &FnLower<'_>, lam: &Lambda) -> std::collections::HashSet<usize> {
    let scan =
        |body| crate::mutation::mutated_locals(&fl.hir, body, &fl.cx.callables, &fl.cx.mutated);
    let mut changed = scan(ms_check::hir::Body::Block(&lam.body));
    // A default runs in the lambda's frame, so what it changes counts too.
    for d in lam.params.iter().filter_map(|p| p.default.as_ref()) {
        changed.extend(scan(ms_check::hir::Body::Expr(d)));
    }
    with_alias_origins(fl, &lam.body, changed)
}

/// The captured locals the lambda `lam` changes: they are shared by reference.
fn lambda_changes(
    fl: &FnLower<'_>,
    lam: &Lambda,
    captures: &[ct::BindingRef],
) -> std::collections::HashSet<usize> {
    let mutated = lambda_mutated(fl, lam);
    captures
        .iter()
        .map(|b| b.uid)
        .filter(|uid| mutated.contains(uid))
        .collect()
}

/// The locals a closure written in `body` changes: they must live in memory.
pub(crate) fn slotted_in(fl: &FnLower<'_>, body: &[Stmt]) -> std::collections::HashSet<usize> {
    struct Scan<'a, 'b> {
        fl: &'a FnLower<'b>,
        found: std::collections::HashSet<usize>,
    }
    impl ms_syntax::visit::Visitor for Scan<'_, '_> {
        fn expr(&mut self, e: &Expr) {
            if let ExprKind::Lambda(lam) = &e.kind {
                let captures = self.fl.hir.captures(e);
                self.found.extend(lambda_changes(self.fl, lam, &captures));
            }
        }
    }
    let mut scan = Scan {
        fl,
        found: Default::default(),
    };
    ms_syntax::visit::walk_block(&mut scan, body);
    scan.found.extend(crate::mutation::changing_method_roots(
        &fl.hir,
        ms_check::hir::Body::Block(body),
        &fl.cx.mutated,
    ));
    // Resolve reborrows before any branch is lowered: their owning roots must
    // have storage on every incoming path, not just where the closure is made.
    with_alias_origins(fl, body, scan.found)
}

/// Mutation through a locally declared alias also changes its owning root.
fn with_alias_origins(
    fl: &FnLower<'_>,
    body: &[Stmt],
    mut changed: std::collections::HashSet<usize>,
) -> std::collections::HashSet<usize> {
    struct Origins<'a, 'b> {
        fl: &'a FnLower<'b>,
        roots: std::collections::HashMap<usize, usize>,
    }
    impl ms_syntax::visit::Visitor for Origins<'_, '_> {
        fn stmt(&mut self, s: &Stmt) {
            let (pattern, value) = match &s.kind {
                StmtKind::Bind { pattern, value, .. } => (pattern, value),
                StmtKind::If {
                    binding: Some(pattern),
                    cond,
                    ..
                } => (pattern, cond),
                _ => return,
            };
            let Some(binding) = self.fl.hir.pattern_binding(pattern) else {
                return;
            };
            if self.fl.cx.exclusive.contains(&binding.uid)
                && let Some(root) = alias_origin(self.fl, value)
            {
                self.roots.insert(binding.uid, root);
            }
        }
    }
    let mut origins = Origins {
        fl,
        roots: Default::default(),
    };
    ms_syntax::visit::walk_block(&mut origins, body);
    let mut pending: Vec<_> = changed.iter().copied().collect();
    while let Some(uid) = pending.pop() {
        if let Some(root) = origins.roots.get(&uid)
            && changed.insert(*root)
        {
            pending.push(*root);
        }
    }
    changed
}

fn alias_origin(fl: &FnLower<'_>, e: &Expr) -> Option<usize> {
    match &e.kind {
        ExprKind::Name(_) => {
            let ms_check::hir::Resolution::Local(b) = fl.hir.resolution(e) else {
                return None;
            };
            Some(b.uid)
        }
        ExprKind::Member { left, .. } => alias_origin(fl, left),
        ExprKind::Call { callee, args } => {
            let source = match (&callee.kind, fl.hir.resolution(e)) {
                (ExprKind::Member { left, .. }, ms_check::hir::Resolution::Method(_)) => &**left,
                _ => &args.first()?.value,
            };
            alias_origin(fl, source)
        }
        _ => crate::mutation::index_parts(&fl.hir, e).and_then(|(left, _)| alias_origin(fl, left)),
    }
}

impl FnLower<'_> {
    /// A function value read where the checker expects the plain form of its type: a held value
    /// whose omittable parameters are optionals goes through an adapter that supplies them.
    pub(crate) fn fit_function_value(&mut self, e: &Expr, x: Val) -> Result<Val, Error> {
        let want = self.emty(e)?;
        let have = self.ty_of(x.v);
        if want == have {
            return Ok(x);
        }
        let (TyKind::Fn(hp, hr), TyKind::Fn(wp, wr)) = (
            self.b.m.types.kind(have).clone(),
            self.b.m.types.kind(want).clone(),
        ) else {
            return Ok(x);
        };
        let lifts = hp.len() == wp.len()
            && hr == wr
            && hp.iter().zip(&wp).all(|(h, w)| {
                h == w || matches!(self.b.m.types.kind(*h).clone(), TyKind::Opt(i) if i == *w)
            });
        if !lifts {
            return Ok(x);
        }
        let mut ps = vec![Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        }];
        ps.extend(wp.iter().map(|t| Param {
            ty: *t,
            mode: Mode::Borrow,
        }));
        let mut f = ms_mir::ir::Func::new("<function adapter>", ps, wr);
        f.kind = FuncKind::Closure {
            captures: vec![have],
        };
        let id = self.b.m.add_func(f);
        self.cx.queue.push(Job {
            func: id,
            kind: JobKind::FnAdapt(Rc::new(crate::cx::FnAdaptJob {
                hir: self.hir.clone(),
                have,
            })),
        });
        let held = self.owned(x);
        let v = self
            .b
            .emit(Op::ClosureNew, &[held], Imm::Func(id), Some(want))
            .expect("closure");
        Ok(Val { v, own: true })
    }
}

/// Lowers the body of a function adapter: it calls the held value, wrapping plain arguments in
/// the optionals the held value takes.
pub(crate) fn build_fn_adapter(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &crate::cx::FnAdaptJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let file = m.add_file(job.hir.data.file.as_str());
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    let mut fl = FnLower::new(cx, b, job.hir.clone(), ct::Subst::new(), file, proto.ret);
    let result = lower_fn_adapter(&mut fl, job.have);
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

fn lower_fn_adapter(fl: &mut FnLower<'_>, have: MTy) -> Result<(), Error> {
    let params = fl.b.params();
    let held =
        fl.b.emit(Op::ClosureCap, &[params[0]], Imm::Idx(0), Some(have))
            .expect("capture");
    let TyKind::Fn(hp, _) = fl.b.m.types.kind(have).clone() else {
        return Err(Error::new("function adapter without a function type"));
    };
    let mut args = Vec::new();
    for (i, h) in hp.iter().enumerate() {
        let v = params[i + 1];
        if fl.ty_of(v) == *h {
            args.push(v);
            continue;
        }
        let o = fl.owned(Val { v, own: false });
        let some = fl.b.opt_some(o);
        args.push(fl.borrow(Val { v: some, own: true }));
    }
    let r = fl.b.call_ind(held, &args);
    let out = fl.val(r, true);
    fl.emit_return(Some(out));
    Ok(())
}
