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
        for b in &captures {
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
                captures,
            })),
        });
        let v = self
            .b
            .emit(Op::ClosureNew, &cap_vals, Imm::Func(id), Some(fty))
            .expect("closure");
        Ok(Val { v, own: true })
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
        let fid = self.cx.function_for(self.b.m, &callee, &subst)?;
        if let Some(thunk) = self.default_thunk(e, fid, &callee, &subst, None)? {
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
        let key = format!("default-thunk:{}:{}", fid.index(), fty.0);
        Ok(Some(self.queue_default_thunk(
            key, fid, &ptys, ret, callee, subst, recv,
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
        let fid = self.cx.function_for(self.b.m, c, subst)?;
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
        let thunk = self.queue_default_thunk(key, fid, &ptys, ret, c, subst, None);
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

    /// A method used as a value (`view.read`): a closure holding a copy of the receiver.
    pub fn bound_method(&mut self, e: &Expr, left: &Expr, m: &ct::MethodRef) -> Result<Val, Error> {
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
            // A function type that takes optionals the interface method takes plainly.
            if self.b.m.ifaces[iface.index()].methods[k].params != params {
                let key = format!("iface-thunk:{}:{k}:{}", iface.0, fty.0);
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
                            captures: vec![recv_mty],
                        };
                        let id = self.b.m.add_func(f);
                        self.cx.queue.push(Job {
                            func: id,
                            kind: JobKind::IfaceThunk(Rc::new(crate::cx::IfaceThunkJob {
                                iface,
                                index: k as u32,
                                method: m.clone(),
                                hir: self.hir.clone(),
                            })),
                        });
                        self.cx.helpers.insert(key, id);
                        id
                    }
                };
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
            let fid = self.cx.function_for(self.b.m, &c, &subst)?;
            if vars.is_empty()
                && let Some(thunk) = self.default_thunk(e, fid, &c, &subst, Some(recv_mty))?
            {
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
                    Ok((fid, true)) => {
                        // The method changes its receiver; the closure's copy takes the change.
                        let own = if b.m.needs_drop(recv_mty) {
                            b.emit(Op::Copy, &[this], Imm::None, Some(recv_mty))
                                .expect("copy")
                        } else {
                            this
                        };
                        let slot = b
                            .emit(Op::Slot, &[], Imm::Ty(recv_mty), Some(MTy::PTR))
                            .expect("slot");
                        let put = if b.m.needs_drop(recv_mty) {
                            Op::Put
                        } else {
                            Op::Store
                        };
                        b.emit(put, &[slot, own], Imm::None, None);
                        let mut all = vec![slot];
                        all.extend_from_slice(rest);
                        let r = b.call(fid, &all);
                        let take = if b.m.needs_drop(recv_mty) {
                            Op::Take
                        } else {
                            Op::Load
                        };
                        let after = b
                            .emit(take, &[slot], Imm::Ty(recv_mty), Some(recv_mty))
                            .expect("take");
                        if b.m.needs_drop(recv_mty) {
                            b.emit(Op::Drop, &[after], Imm::None, None);
                        }
                        r
                    }
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
        let recv = self.expr(left)?;
        if self.dead {
            return Ok(recv);
        }
        let rty = self.ty_of(recv.v);
        let fty = self.emty(e)?;
        let TyKind::Fn(ptys, ret) = self.b.m.types.kind(fty).clone() else {
            return Err(Error::new("method value without function type"));
        };
        let key = format!("bound-native:{}:{}:{}", m.native, rty.0, fty.0);
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
                    captures: vec![rty],
                };
                let id = self.b.m.add_func(f);
                self.cx.queue.push(Job {
                    func: id,
                    kind: JobKind::BoundNative(Rc::new(BoundNativeJob {
                        method: m.clone(),
                        hir: self.hir.clone(),
                    })),
                });
                self.cx.helpers.insert(key, id);
                id
            }
        };
        let captured = self.owned(recv);
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
                        b.call(fmt, &[cap])
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
        let v = self.b.call_ind(fv, &args);
        Ok(self.val(v, true))
    }
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
    let recv = job.recv.map(|t| Val {
        v: fl
            .b
            .emit(Op::ClosureCap, &[params[0]], Imm::Idx(0), Some(t))
            .expect("capture"),
        own: false,
    });
    let callee = job.callable.clone();
    if !fl.cx.var_positions(&callee).is_empty() {
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
    let fid = fl.cx.function_for(fl.b.m, &callee, &job.subst)?;
    let mut vals: Vec<Value> = recv.iter().map(|r| r.v).collect();
    for s in slots.into_iter().flatten() {
        vals.push(fl.borrow(s));
    }
    let r = fl.b.call(fid, &vals);
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
    let this =
        fl.b.emit(Op::ClosureCap, &[params[0]], Imm::Idx(0), Some(recv_ty))
            .expect("capture");
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
    let args = fl.thunk_native_args(job.sym.module, func, &job.params, &params[1..])?;
    let ret = fl.ret_ty;
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
    let result = lower_bound_native(&mut fl, job, captures[0]);
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
    let cap =
        fl.b.emit(Op::ClosureCap, &[env], Imm::Idx(0), Some(recv_ty))
            .expect("capture");
    let recv = Val { v: cap, own: false };
    let func = job.method.decl.as_ref().and_then(|d| d.func());
    let args =
        fl.thunk_native_args(job.method.module, func, &job.method.ty.params, &params[1..])?;
    let ret = fl.ret_ty;
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

fn lower_lambda_body(fl: &mut FnLower<'_>, job: &LambdaJob, captures: &[MTy]) -> Result<(), Error> {
    let ExprKind::Lambda(lam) = &job.expr.kind else {
        return Err(Error::new("not a lambda"));
    };
    let params = fl.b.params();
    let env = params[0];
    let mutated = crate::mutation::mutated_locals(
        &fl.hir,
        ms_check::hir::Body::Block(&lam.body),
        &fl.cx.callables,
        &fl.cx.mutated,
    );
    for (i, (b, t)) in job.captures.iter().zip(captures).enumerate() {
        let v =
            fl.b.emit(Op::ClosureCap, &[env], Imm::Idx(i as u32), Some(*t))
                .expect("capture");
        if mutated.contains(&b.uid) {
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
