//! Lambdas and calls through function values.

use crate::Error;
use crate::cx::{Cx, Job, JobKind, LambdaJob};
use crate::func::{FnLower, Val};
use ms_check::hir::CallView;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncId, FuncKind, Imm, Mode, Module, Op, Param};
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

    /// A call whose callee is a function value.
    pub fn call_value(&mut self, e: &Expr, view: &CallView<'_>) -> Result<Val, Error> {
        let ExprKind::Call { callee, .. } = &e.kind else {
            return Err(Error::new("not a call"));
        };
        let f = self.expr(callee)?;
        if self.dead {
            return Ok(f);
        }
        let mut args = Vec::new();
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
            args.push(self.borrow(x));
        }
        let fv = self.borrow(f);
        self.at(e.pos);
        let v = self.b.call_ind(fv, &args);
        Ok(self.val(v, true))
    }
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
    for (b, v) in bindings.iter().zip(params.iter().skip(1)) {
        fl.bind_borrowed(b, *v);
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
