//! Lambdas and calls through function values.

use crate::Error;
use crate::cx::{BoundNativeJob, Cx, Job, JobKind, LambdaJob, NativeThunkJob};
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
    let args: Vec<crate::native::NArg> = job
        .params
        .iter()
        .zip(params.iter().skip(1))
        .map(|(p, v)| crate::native::NArg {
            name: p.name,
            val: Val { v: *v, own: false },
            wrapped: false,
        })
        .collect();
    let ret = fl.ret_ty;
    let out = fl.native_call(&job.native, &job.params, &args, ret)?;
    fl.emit_return(Some(out));
    Ok(())
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
    let args: Vec<crate::native::NArg> = job
        .method
        .ty
        .params
        .iter()
        .zip(params.iter().skip(1))
        .map(|(p, v)| crate::native::NArg {
            name: p.name,
            val: Val { v: *v, own: false },
            wrapped: false,
        })
        .collect();
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
