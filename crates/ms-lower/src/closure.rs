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
    let mutated = mutated_captures(&fl.hir, &lam.body, &fl.cx.mutating);
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

/// Finds the root local of a place expression (`a`, `a.b.c`).
fn place_root(hir: &ms_check::hir::ModuleHir, e: &Expr) -> Option<usize> {
    let mut cur = e;
    while let ExprKind::Member { left, .. } = &cur.kind {
        cur = left;
    }
    match hir.resolution(cur) {
        ms_check::hir::Resolution::Local(b) => Some(b.uid),
        _ => None,
    }
}

/// Collects the locals a lambda body assigns to or mutates in place.
struct Mutations<'h> {
    hir: &'h ms_check::hir::ModuleHir,
    roots: std::collections::HashSet<usize>,
    /// Source methods called on a local's place: (root local, module, declaration).
    calls: Vec<(usize, MethodKey)>,
}

/// A source method: module file and declaration node.
pub(crate) type MethodKey = (ms_check::types::Name, ms_syntax::NodeId);

impl ms_syntax::visit::Visitor for Mutations<'_> {
    fn stmt(&mut self, s: &Stmt) {
        if let StmtKind::Assign { target, value, .. } = &s.kind {
            let root = match target {
                AssignTarget::Name(_) => self.hir.assigned(value).map(|b| b.uid),
                AssignTarget::Member(t) => place_root(self.hir, t),
            };
            self.roots.extend(root);
        }
    }

    fn expr(&mut self, e: &Expr) {
        let ExprKind::Call { callee, .. } = &e.kind else {
            return;
        };
        let mut c: &Expr = callee;
        if let ExprKind::Apply { left, .. } = &c.kind {
            c = left;
        }
        let ExprKind::Member { left, name } = &c.kind else {
            return;
        };
        let ms_check::hir::Resolution::Method(m) = self.hir.resolution(e) else {
            return;
        };
        if !m.native.as_str().is_empty() {
            if ms_check::effects::collection_mutation(&self.hir.ty(left), name.as_str()) {
                self.roots.extend(place_root(self.hir, left));
            }
        } else if let (Some(root), Some(decl)) = (place_root(self.hir, left), &m.decl) {
            self.calls.push((root, (m.module, decl.id())));
        }
    }
}

/// The locals a body changes directly, and the source methods it calls on them.
pub(crate) fn body_mutations(
    hir: &ms_check::hir::ModuleHir,
    body: crate::closure::BodyRef<'_>,
) -> (std::collections::HashSet<usize>, Vec<(usize, MethodKey)>) {
    let mut v = Mutations {
        hir,
        roots: std::collections::HashSet::new(),
        calls: Vec::new(),
    };
    match body {
        BodyRef::Block(b) => ms_syntax::visit::walk_block(&mut v, b),
        BodyRef::Expr(e) => ms_syntax::visit::walk_expr(&mut v, e),
    }
    (v.roots, v.calls)
}

/// A body to scan for mutations.
pub(crate) enum BodyRef<'a> {
    Block(&'a [Stmt]),
    Expr(&'a Expr),
}

/// Locals of the enclosing function that the lambda body changes (their closure copy is mutable).
pub(crate) fn mutated_captures(
    hir: &ms_check::hir::ModuleHir,
    body: &[Stmt],
    mutating: &std::collections::HashSet<MethodKey>,
) -> std::collections::HashSet<usize> {
    let (mut roots, calls) = body_mutations(hir, BodyRef::Block(body));
    roots.extend(
        calls
            .into_iter()
            .filter(|(_, k)| mutating.contains(k))
            .map(|(r, _)| r),
    );
    roots
}

/// Methods that change their receiver: declared `var fn`, or assigning through `self`, using a
/// collection mutator on it, or calling such a method on it.
pub(crate) fn infer_mutating(
    mods: &std::collections::HashMap<ms_check::types::Name, std::rc::Rc<ms_check::hir::ModuleHir>>,
    callables: &std::collections::HashMap<MethodKey, std::rc::Rc<ms_check::hir::Callable>>,
) -> std::collections::HashSet<MethodKey> {
    let mut mutating = std::collections::HashSet::new();
    // Per method: the source methods it calls on `self`.
    let mut edges: Vec<(MethodKey, Vec<MethodKey>)> = Vec::new();
    for (key, c) in callables {
        let Some(me) = &c.self_binding else { continue };
        if c.func.method().is_some_and(|m| m.mutating) {
            mutating.insert(*key);
            continue;
        }
        let Some(hir) = mods.get(&c.module.file) else {
            continue;
        };
        let body = match c.body() {
            ms_check::hir::Body::Block(b) => BodyRef::Block(b),
            ms_check::hir::Body::Expr(e) => BodyRef::Expr(e),
        };
        let (roots, calls) = body_mutations(hir, body);
        if roots.contains(&me.uid) {
            mutating.insert(*key);
            continue;
        }
        let on_self: Vec<MethodKey> = calls
            .into_iter()
            .filter(|(r, _)| *r == me.uid)
            .map(|(_, k)| k)
            .collect();
        if !on_self.is_empty() {
            edges.push((*key, on_self));
        }
    }
    loop {
        let before = mutating.len();
        for (key, callees) in &edges {
            if !mutating.contains(key) && callees.iter().any(|k| mutating.contains(k)) {
                mutating.insert(*key);
            }
        }
        if mutating.len() == before {
            return mutating;
        }
    }
}
