//! Lambdas and calls through function values.

use crate::Error;
use crate::cx::{
    BoundNativeJob, Cx, Held, IfaceNativeJob, Job, JobKind, LambdaJob, NativeThunkJob,
};
use crate::cx::{BoundTarget, HelperKey};
use crate::func::{FnLower, Val};
use ms_check::api::ast::*;
use ms_check::api::hir::CallView;
use ms_check::api::types as ct;
use ms_check::api::types::Builtin;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncId, FuncKind, Imm, Mode, Module, Op, Param, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use std::rc::Rc;

/// The receiver a method value's closure is built from.
#[derive(Clone, Copy)]
enum Receiver {
    /// The address of the receiver's place in memory, and the receiver's type.
    Addr(Value, MTy),
    /// The receiver itself.
    Value(Val),
}

/// Captures use environment indices, never SSA values from the enclosing function.
pub(crate) enum LambdaCapture {
    Local(ct::BindingRef, usize),
    /// A variable the closure changes and owns: the capture lives in the closure's environment
    /// and the body works on it in place.
    Owned(ct::BindingRef, usize),
    /// A pointer to the maker's value of a variable the non-escaping closure only reads.
    Borrowed(ct::BindingRef, usize),
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
    Some,
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
        let mut closers = Vec::new();
        let changed = lambda_changes(self.syms, self, lam, &captures);
        // Whether the closure's environment points into this frame.
        let mut scoped = false;
        for b in &captures {
            if changed.contains(&b.uid)
                && let Some(alias) = self.aliases.get(&b.uid).cloned()
            {
                saved.push(self.capture_alias(b, alias, &mut cap_tys, &mut cap_vals)?);
                scoped = true;
                continue;
            }
            if !changed.contains(&b.uid)
                && self
                    .cx
                    .ownership
                    .borrowed_captures
                    .contains(&(self.hir.data.file, e.id, b.uid))
            {
                let x = self.read_local(b)?;
                let ty = self.ty_of(x.v);
                if self.needs_drop(ty) {
                    // The closure does not outlive its maker and the variable stays unchanged
                    // while it lives, so the closure reads the variable through a pointer
                    // instead of owning a copy.
                    let v = self.borrow(x);
                    let slot = self
                        .b
                        .emit(Op::Slot, &[], Imm::Ty(ty), Some(MTy::PTR))
                        .expect("slot");
                    self.b.emit(Op::Store, &[slot, v], Imm::None, None);
                    saved.push(LambdaCapture::Borrowed(b.clone(), cap_vals.len()));
                    scoped = true;
                    cap_tys.push(MTy::PTR);
                    cap_vals.push(slot);
                    continue;
                }
            }
            if changed.contains(&b.uid)
                && self.moves_at(b.uid, e.id)
                && let Some(l) = self.locals.get(&b.uid).copied()
                && l.slot.is_some()
                && let Some(close) = self.capture_closer(b.uid, e, l.ty)
            {
                // An escaping closure that changes a resource takes it: the environment holds
                // the value, the body changes it there, and dropping the closure closes it.
                saved.push(LambdaCapture::Owned(b.clone(), cap_vals.len()));
                let v = self.take_local(b.uid, &l);
                closers.push((cap_vals.len() as u32, close));
                cap_tys.push(l.ty);
                cap_vals.push(v);
                self.moved_closer(b.uid, e);
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
                        self.syms.str(b.name)
                    ))
                    })?;
                cap_tys.push(MTy::PTR);
                cap_vals.push(slot);
                scoped = true;
                // The checker counts an escaping closure as taking the variable, but this one
                // shares the variable's storage, so the scope still owns the value: it closes
                // and drops it at its end.
                if self.moves_at(b.uid, e.id) {
                    self.must_move.remove(&b.uid);
                }
                continue;
            }
            let x = if self.moves_at(b.uid, e.id) {
                // An escaping closure takes the variable with it.
                let l = self.local(b)?;
                let v = self.take_local(b.uid, &l);
                Val { v, own: true }
            } else {
                self.read_local(b)?
            };
            let cap_ty = self.ty_of(x.v);
            // A resource the closure takes over is closed when the closure is dropped, no
            // longer by this scope.
            if let Some(close) = self.capture_closer(b.uid, e, cap_ty) {
                closers.push((cap_vals.len() as u32, close));
            }
            cap_tys.push(cap_ty);
            // A closure holds its own copy of a borrowed value it captures: declared here.
            cap_vals.push(self.owned_boundary(x));
            self.moved_closer(b.uid, e);
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
        f.scoped = scoped;
        // A closure made inside a function that keeps scoped closures is what keeps them.
        f.keeps_scoped = self.b.func_mut().keeps_scoped;
        f.capture_closers = closers;
        let id = self.b.m.add_func(f);
        let _ = lam;
        self.cx.queue.push(Job {
            func: id,
            kind: JobKind::Lambda(Rc::new(LambdaJob {
                expr: e.clone(),
                hir: self.hir.clone(),
                subst: self.subst.clone(),
                variant: self.variant,
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
                crate::alias::AStep::Some => {
                    steps.push(CapturedStep::Some);
                    continue;
                }
                crate::alias::AStep::Index(value) => (value, false),
                crate::alias::AStep::Key(var, _) => (self.b.use_var(var), true),
            };
            let index = cap_vals.len();
            cap_tys.push(self.ty_of(value));
            // The captured key or index is the closure's own copy.
            cap_vals.push(self.clone_value(value));
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
        let mut subst = ct::Subst::default();
        if !vars.is_empty() {
            let want = self.ety(e);
            if !ct::unify(&sym.ty(self.syms), &want, &vars, &mut subst) {
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
        let key = HelperKey::Thunk(fid);
        let thunk = match self.cx.helpers.get(&key) {
            Some(t) => *t,
            None => {
                let proto = self.b.m.funcs[fid.index()].clone();
                let copy_result = self.borrowed_result_copy(fid, proto.ret, &proto.name)?;
                let result_ty = self.ety(e).result_ty();
                if copy_result && !self.cx.classes.concretely_clonable(self.syms, &result_ty) {
                    return Err(Error::new(
                        "a function value returns a non-Clonable borrow; call the function directly",
                    ));
                }
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
                let r = if copy_result {
                    b.emit(Op::Clone, &[r], Imm::Int(1), Some(proto.ret))
                        .expect("copy result")
                } else {
                    r
                };
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
        callee: &Rc<ms_check::api::hir::Callable>,
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
        let key = HelperKey::DefaultThunk {
            fid,
            fty,
            shared: shared.is_some(),
        };
        Ok(Some(self.queue_default_thunk(
            key, fid, &ptys, ret, callee, subst, recv, shared,
        )))
    }

    /// Queues (once per key) the thunk of `callee` taking `ptys`, with optionals for the
    /// parameters whose defaults it fills in its own frame.
    #[allow(clippy::too_many_arguments)]
    fn queue_default_thunk(
        &mut self,
        key: HelperKey,
        fid: FuncId,
        ptys: &[MTy],
        ret: MTy,
        callee: &Rc<ms_check::api::hir::Callable>,
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
        view: &ms_check::api::hir::CallView<'_>,
        c: &Rc<ms_check::api::hir::Callable>,
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
        let key = HelperKey::DirectDefault(fid);
        let thunk = self.queue_default_thunk(key, fid, &ptys, ret, c, subst, None, None);
        let fty = self.b.m.types.func(ptys.clone(), ret);
        let mut slots: Vec<Option<Value>> = vec![None; ptys.len()];
        for a in view.arguments.iter() {
            let x = self.expr(a.expr)?;
            if self.dead {
                return Ok(Some(x));
            }
            // A borrowed payload wrapped into an `Optional` stays its owner's; a temporary is ours.
            let borrowed_payload = !x.own && a.wrap_optional.is_some();
            let x = match &a.wrap_optional {
                // The thunk only borrows, so a borrowed payload is shown, not copied.
                Some(_) if borrowed_payload => Val {
                    v: self.b.opt_view(x.v),
                    own: false,
                },
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
                .ok_or_else(|| {
                    Error::new(format!("no parameter {}", self.syms.str(a.slot.name)))
                })?;
            // The thunk only borrows its arguments, so a temporary resource stays registered here
            // and closes with its statement, as in an ordinary call. The thunk sees it through an
            // `opt.view`, which neither copies nor drops the resource it shows.
            if x.own
                && !borrowed_payload
                && let Some(key) = self.hold_resource_temp(x.v)?
            {
                let shown = match self.b.m.types.kind(ptys[at]).clone() {
                    TyKind::Opt(inner) if inner == self.ty_of(key) => self.b.opt_view(key),
                    _ => key,
                };
                slots[at] = Some(shown);
                continue;
            }
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
        let ms_check::api::hir::Resolution::Local(b) = self.hir.resolution(left) else {
            return None;
        };
        let l = self.locals.get(&b.uid)?;
        Some((l.slot?, l.ty))
    }

    /// What a method value holds of its receiver: the address of a variable (one the method
    /// `changes`, or one a value that stays local only reads, `bound_borrows`), or the receiver
    /// itself. A borrowed receiver that is not a variable in memory is stored in a frame slot the
    /// closure points to; the checker keeps the place unchanged while the value lives.
    fn method_receiver(&mut self, e: &Expr, left: &Expr, changes: bool) -> Result<Receiver, Error> {
        let borrowed = self.cx.fact(
            self.hir.data.file,
            e.id,
            ms_check::api::ownership::Fact::BoundBorrow,
        );
        // A variable converted to an interface on the way is read as a view of it below.
        let want = self.emty(left)?;
        if (changes || borrowed)
            && let Some((slot, t)) = self.shared_receiver(left)
            && t == want
        {
            return Ok(Receiver::Addr(slot, t));
        }
        let recv = self.expr(left)?;
        if self.dead || !borrowed || recv.own {
            return Ok(Receiver::Value(recv));
        }
        let t = self.ty_of(recv.v);
        if !self.needs_drop(t) && self.part_closer_mir(t)?.is_none() {
            // A plain value is as cheap to copy as to point to. A resource with no drop glue
            // still has one owner that closes it, so a borrowed one stays an address.
            return Ok(Receiver::Value(recv));
        }
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
            .expect("slot");
        self.b.emit(Op::Store, &[slot, recv.v], Imm::None, None);
        Ok(Receiver::Addr(slot, t))
    }

    /// The capture of a method value's closure: the receiver's address, or the receiver owned.
    fn captured(&mut self, recv: Receiver) -> Value {
        match recv {
            Receiver::Addr(slot, _) => slot,
            Receiver::Value(v) => self.owned(v),
        }
    }

    /// A source method environment closes the receiver only when it owns the capture.
    /// The thunk identity already distinguishes owned captures from borrowed addresses.
    fn own_receiver_capture(&mut self, thunk: FuncId, recv: Receiver) -> Result<(), Error> {
        if let Receiver::Value(v) = recv {
            let ty = self.ty_of(v.v);
            if let Some(kind) = self.part_closer_mir(ty)? {
                let close = self.close_thunk(&kind, ty, true);
                self.b.m.funcs[thunk.index()].capture_closers = vec![(0, close)];
            }
        }
        Ok(())
    }

    /// Queues (once per key) the thunk of a source method that changes its receiver, which
    /// the closure holds as the address of the variable.
    fn shared_method_thunk(
        &mut self,
        key: HelperKey,
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
        let name = m
            .name()
            .map(|n| self.syms.str(n).to_string())
            .unwrap_or_default();
        // How the thunk reaches the method, and the receiver it holds.
        let (key, callee, recv) = if let TyKind::Iface(iface) =
            self.b.m.types.kind(recv_mty).clone()
        {
            let k = self.b.m.ifaces[iface.index()]
                .methods
                .iter()
                .position(|s| s.name == name)
                .ok_or_else(|| Error::new(format!("no interface method {name}")))?;
            let changes = crate::mutation::method_changes_receiver(self.syms, m, &self.cx.mutated);
            let recv = self.method_receiver(e, left, changes)?;
            if let Receiver::Value(v) = recv
                && self.dead
            {
                return Ok(v);
            }
            // The closure holds the address of the variable it changes or the receiver it only
            // reads; the thunk loads the current value.
            let addr = matches!(recv, Receiver::Addr(..));
            let held_ty = if addr { MTy::PTR } else { recv_mty };
            // A function type that takes optionals the interface method takes plainly.
            if self.b.m.ifaces[iface.index()].methods[k].params != params {
                let key = HelperKey::IfaceThunk {
                    iface: iface.0,
                    k,
                    fty,
                    addr,
                };
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
                                recv: recv_mty,
                                shared: addr,
                            })),
                        });
                        self.cx.helpers.insert(key, id);
                        id
                    }
                };
                let held = self.captured(recv);
                let v = self
                    .b
                    .emit(Op::ClosureNew, &[held], Imm::Func(thunk), Some(fty))
                    .expect("closure");
                return Ok(Val { v, own: true });
            }
            if let Receiver::Addr(slot, _) = recv {
                let key = HelperKey::BoundSharedIface {
                    iface: iface.0,
                    k,
                    fty,
                };
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
            (BoundTarget::Iface(iface.0, k), Err((iface, k as u32)), recv)
        } else {
            let im = if m.native == ct::Native::Contract {
                self.contract_impl(m, &recv_ty).ok_or_else(|| {
                    Error::new(format!(
                        "{recv_ty_t} has no method {name}",
                        recv_ty_t = recv_ty.display(self.syms)
                    ))
                })?
            } else {
                m.clone()
            };
            if im.native != ct::Native::Source {
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
            let mut subst = ct::Subst::default();
            if !ct::unify(
                &declared.receiver,
                &recv_ty,
                &ct::variable_set(&declared.variables),
                &mut subst,
            ) {
                return Err(Error::new("cannot bind method receiver type"));
            }
            // The method's own type parameters come from the value's checked type.
            let own_vars = ct::variable_set(&declared.variables);
            if declared
                .variables
                .iter()
                .any(|v| !subst.contains_key(&v.name))
            {
                let want = self.ety(e);
                if !ct::unify(&declared.ty, &want, &own_vars, &mut subst) {
                    return Err(Error::new("cannot infer the method value's type arguments"));
                }
            }
            let vars = self.cx.var_positions(&c);
            if vars.iter().any(|v| *v != 0) {
                return Err(Error::new("method value with changed parameters"));
            }
            let fid = self.instance(&c, &subst)?;
            let changes = !vars.is_empty();
            let recv = self.method_receiver(e, left, changes)?;
            if let Receiver::Value(v) = recv
                && self.dead
            {
                return Ok(v);
            }
            if let Receiver::Addr(slot, _) = recv {
                // The closure holds the variable's address: a thunk with defaults reads the
                // current value, and one of a changing method changes it in place.
                let ptr_ty = Some(MTy::PTR);
                let thunk = self.default_thunk(e, fid, &c, &subst, ptr_ty, Some(recv_mty))?;
                let thunk = match (thunk, changes) {
                    (Some(t), _) => Some(t),
                    (None, true) => {
                        let key = HelperKey::BoundSharedFunc { fid, fty };
                        Some(self.shared_method_thunk(key, &name, fid, &params, ret))
                    }
                    (None, false) => None,
                };
                if let Some(thunk) = thunk {
                    let v = self
                        .b
                        .emit(Op::ClosureNew, &[slot], Imm::Func(thunk), Some(fty))
                        .expect("closure");
                    return Ok(Val { v, own: true });
                }
            } else if let Some(thunk) =
                self.default_thunk(e, fid, &c, &subst, Some(recv_mty), None)?
            {
                if !changes {
                    self.own_receiver_capture(thunk, recv)?;
                }
                let held = self.captured(recv);
                let v = self
                    .b
                    .emit(Op::ClosureNew, &[held], Imm::Func(thunk), Some(fty))
                    .expect("closure");
                return Ok(Val { v, own: true });
            }
            (BoundTarget::Func(fid), Ok((fid, changes)), recv)
        };
        let addr = matches!(recv, Receiver::Addr(..));
        let held = self.captured(recv);
        let key = HelperKey::Bound {
            target: key,
            fty,
            addr,
        };
        let thunk = match self.cx.helpers.get(&key) {
            Some(t) => *t,
            None => {
                // A callee that returns a borrow of its receiver or arguments: the closure's
                // caller expects an owned result, so the thunk copies it.
                let copy_result = match callee {
                    Ok((fid, _)) => self.borrowed_result_copy(fid, ret, &name)?,
                    Err(_) => false,
                };
                let mut ps = vec![Param {
                    ty: MTy::PTR,
                    mode: Mode::Borrow,
                }];
                ps.extend(params.iter().map(|t| Param {
                    ty: *t,
                    mode: Mode::Borrow,
                }));
                let mut b = FuncBuilder::new(self.b.m, &format!("<{name}>"), ps, ret);
                let held_ty = if addr { MTy::PTR } else { recv_mty };
                b.func_mut().kind = FuncKind::Closure {
                    captures: vec![held_ty],
                };
                let args = b.params();
                let mut this = b
                    .emit(Op::ClosureCap, &[args[0]], Imm::Idx(0), Some(held_ty))
                    .expect("capture");
                if addr {
                    // The closure points at the receiver it only reads.
                    this = b
                        .emit(Op::Load, &[this], Imm::Ty(recv_mty), Some(recv_mty))
                        .expect("load");
                }
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
                let r = if copy_result {
                    b.emit(Op::Clone, &[r], Imm::Int(1), Some(ret))
                        .expect("copy result")
                } else {
                    r
                };
                b.ret(Some(r));
                let f = b.into_func();
                let id = self.b.m.add_func(f);
                self.cx.helpers.insert(key, id);
                id
            }
        };
        if matches!(callee, Ok((_, false))) {
            self.own_receiver_capture(thunk, recv)?;
        }
        let v = self
            .b
            .emit(Op::ClosureNew, &[held], Imm::Func(thunk), Some(fty))
            .expect("closure");
        Ok(Val { v, own: true })
    }

    /// Whether a source callable's thunk must copy the result of `fid`, a callee returning a borrow.
    /// A resource result cannot be copied, so that form is reported instead of miscompiled.
    fn borrowed_result_copy(&mut self, fid: FuncId, ret: MTy, name: &str) -> Result<bool, Error> {
        if !self.b.m.funcs[fid.index()].ret_borrowed || !self.needs_drop(ret) {
            return Ok(false);
        }
        if self.part_closer_mir(ret)?.is_some() {
            return Err(Error::new(format!(
                "callable value {name} returns a borrowed resource; call it directly instead"
            )));
        }
        Ok(true)
    }

    /// A native function used as a value: a closure forwarding to the native.
    pub fn native_function_value(&mut self, e: &Expr, sym: &ct::SymRef) -> Result<Val, Error> {
        let want = self.ety(e);
        let declared = sym.ty(self.syms);
        let vars = ct::variable_set(&sym.variables());
        let mut subst = ct::Subst::default();
        if !vars.is_empty() && !ct::unify(&declared, &want, &vars, &mut subst) {
            return Err(Error::new(
                "cannot infer the function value's type arguments",
            ));
        }
        let fty = self.emty(e)?;
        let TyKind::Fn(ptys, ret) = self.b.m.types.kind(fty).clone() else {
            return Err(Error::new("native function value without function type"));
        };
        let key = HelperKey::NativeThunk {
            native: sym.native,
            fty,
        };
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
                let mut f = ms_mir::ir::Func::new(self.syms.str(sym.name), ps, ret);
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
                        mutable: p.mutable,
                        positional: p.positional,
                    })
                    .collect();
                self.cx.queue.push(Job {
                    func: id,
                    kind: JobKind::NativeThunk(Rc::new(NativeThunkJob {
                        native: sym.native,
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
        let changes = ms_check::api::ownership::collection_mutation(self.syms, m);
        let recv = self.method_receiver(e, left, changes)?;
        if let Receiver::Value(v) = recv
            && self.dead
        {
            return Ok(v);
        }
        let (rty, held) = match recv {
            Receiver::Addr(_, t) if changes => (t, Held::Shared(t)),
            Receiver::Addr(_, t) => (t, Held::Borrowed(t)),
            Receiver::Value(v) => (self.ty_of(v.v), Held::Value),
        };
        let fty = self.emty(e)?;
        let TyKind::Fn(ptys, ret) = self.b.m.types.kind(fty).clone() else {
            return Err(Error::new("method value without function type"));
        };
        let scope = self
            .evidence_of(&[self.hir.ty(left)])
            .unwrap_or(self.hir.data.file);
        let key = HelperKey::BoundNative {
            native: m.native,
            rty,
            fty,
            held,
            scope: (self.cx.holds_extension(self.b.m, rty)
                || self.cx.holds_extension(self.b.m, fty))
            .then_some(scope),
        };
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
                let mut f = ms_mir::ir::Func::new(m.native.text(self.syms), ps, ret);
                f.kind = FuncKind::Closure {
                    captures: vec![held.capture(rty)],
                };
                // A receiver the closure owns is closed when the closure is dropped.
                if matches!(held, Held::Value)
                    && let Some(kind) = self.part_closer_mir(rty)?
                {
                    f.capture_closers = vec![(0, self.close_thunk(&kind, rty, true))];
                }
                let id = self.b.m.add_func(f);
                // Omission adaptation needs the declared payload types, including the
                // method's own type arguments fixed by its checked function-value type.
                let declared = ct::sub(&m.ty, &self.subst);
                let mut subst = ct::Subst::default();
                if !ct::unify(
                    &declared,
                    &self.ety(e),
                    &ct::variable_set(&m.variables),
                    &mut subst,
                ) {
                    return Err(Error::new("cannot infer the method value's type arguments"));
                }
                let mut method = (**m).clone();
                method.ty = ct::sub(&declared, &subst);
                self.cx.queue.push(Job {
                    func: id,
                    kind: JobKind::BoundNative(Rc::new(BoundNativeJob {
                        consumed_arguments: ms_check::api::ownership::native_method_argument_modes(
                            self.syms, m,
                        )
                        .into_iter()
                        .map(|mode| mode == ms_check::api::ownership::ParamMode::Move)
                        .collect(),
                        method: Rc::new(method),
                        hir: self.hir.clone(),
                        held,
                        scope,
                    })),
                });
                self.cx.helpers.insert(key, id);
                id
            }
        };
        let captured = self.captured(recv);
        let v = self
            .b
            .emit(Op::ClosureNew, &[captured], Imm::Func(thunk), Some(fty))
            .expect("closure");
        Ok(Val { v, own: true })
    }

    /// `value.to_string` without a call: a closure holding the receiver that renders it.
    pub fn bound_to_string(&mut self, e: &Expr, left: &Expr) -> Result<Val, Error> {
        let recv = self.method_receiver(e, left, false)?;
        if let Receiver::Value(v) = recv
            && self.dead
        {
            return Ok(v);
        }
        let (t, addr) = match recv {
            Receiver::Addr(_, t) => (t, true),
            Receiver::Value(v) => (self.ty_of(v.v), false),
        };
        let held_ty = if addr { MTy::PTR } else { t };
        let key = HelperKey::TostringThunk(t, addr);
        let thunk = match self.cx.helpers.get(&key) {
            Some(f) => *f,
            None => {
                let ps = vec![Param {
                    ty: MTy::PTR,
                    mode: Mode::Borrow,
                }];
                let mut b = FuncBuilder::new(self.b.m, "to_string", ps, MTy::STR);
                b.func_mut().kind = FuncKind::Closure {
                    captures: vec![held_ty],
                };
                let env = b.params()[0];
                let mut cap = b
                    .emit(Op::ClosureCap, &[env], Imm::Idx(0), Some(held_ty))
                    .expect("capture");
                if addr {
                    cap = b.emit(Op::Load, &[cap], Imm::Ty(t), Some(t)).expect("load");
                }
                let text = match crate::text::scalar_text(&mut b, t, cap, false) {
                    Some((v, true)) => v,
                    Some((v, false)) => b
                        .emit(Op::Clone, &[v], Imm::None, Some(MTy::STR))
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
        let captured = self.captured(recv);
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
        let o = self.owned_boundary(x);
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
                Ok(Some(s.clone_value(u)))
            },
            &mut |s| {
                let d = default(s)?;
                Ok(Some(s.owned_boundary(d)))
            },
        )
    }

    /// `unlift_param` for a value passed on to a borrowing callee: the supplied value is read
    /// in place and only an omitted parameter's default is built, held in the returned
    /// optional, which the caller drops once the callee has returned.
    pub(crate) fn unlift_param_borrowed(
        &mut self,
        opt: Value,
        default: &mut dyn FnMut(&mut Self) -> Result<Val, Error>,
    ) -> Result<(Val, Value), Error> {
        let optty = self.ty_of(opt);
        let TyKind::Opt(inner) = self.b.m.types.kind(optty).clone() else {
            return Err(Error::new("parameter is not optional"));
        };
        let has = self.b.opt_is_some(opt);
        let holder = self.b.declare_var(optty, Mode::Move);
        let out = self.two_ways_mode(
            has,
            inner,
            Mode::Borrow,
            &mut |s| {
                let none = s.none_owned(optty);
                s.b.def_var(holder, none);
                Ok(Some(s.b.opt_get(opt)))
            },
            &mut |s| {
                let d = default(s)?;
                let d = s.owned_boundary(d);
                let some = s.b.opt_some(d);
                s.b.def_var(holder, some);
                Ok(Some(s.b.opt_get(some)))
            },
        )?;
        let held = self.b.use_var(holder);
        Ok((out, held))
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
        // A function value a local holds is called in place: the checker rejects an argument
        // that changes or moves that local while the call runs.
        let fv = self.borrow(f);
        let checked = self.ety(callee);
        let declared = &checked.params;
        let ftype = self.ty_of(f.v);
        let TyKind::Fn(ptys, _) = self.b.m.types.kind(ftype).clone() else {
            return Err(Error::new("call of a non-function value"));
        };
        let mut slots: Vec<Option<Value>> = vec![None; ptys.len()];
        // A `var` position gets the address of a slot holding the argument; the final value
        // moves back after the call.
        let mut slots_out: Vec<crate::call::VarArgument> = Vec::new();
        let mut places: Vec<Option<Expr>> = vec![None; ptys.len()];
        for (i, a) in view.arguments.iter().enumerate() {
            let at = declared
                .iter()
                .position(|p| p.name == a.slot.name)
                .unwrap_or(i);
            let x = if declared.get(at).is_some_and(|p| p.mutable) {
                self.read_place(a.expr)?
            } else {
                self.expr(a.expr)?
            };
            if self.dead {
                self.finish_places(&places);
                return Ok(x);
            }
            if declared.get(at).is_some_and(|p| p.mutable) {
                places[at] = Some(a.expr.clone());
                slots[at] = Some(self.var_argument(e, at, x, Some(a.expr), &mut slots_out));
                continue;
            }
            let owned_payload = x.own;
            let x = match &a.wrap_optional {
                Some(_) => {
                    let o = self.owned_boundary(x);
                    let v = self.b.opt_some(o);
                    Val { v, own: true }
                }
                None => x,
            };
            // Resolve cleanup before the ABI lift: its extra optional has no checker
            // type, and a transport copy of a named borrow must not acquire close duty.
            let payload_ty = self.ty_of(x.v);
            let closer = if owned_payload {
                self.part_closer_mir(payload_ty)?
            } else {
                None
            };
            let x = self.lift_argument(x, ptys[at]);
            slots[at] = Some(if let Some(kind) = closer {
                let kind = if self.ty_of(x.v) != payload_ty {
                    self.optional_resource_closer(self.ty_of(x.v), payload_ty, kind)
                } else {
                    kind
                };
                self.hold_resource_temp_with(x.v, kind)
            } else {
                self.borrow(x)
            });
        }
        // Native invocation defaults are prepared here; other omissions cross as `none`.
        let mut args = Vec::new();
        let missing_value = checked
            .defaults
            .as_ref()
            .and_then(|d| d.missing_value_at_call());
        for (i, s) in slots.into_iter().enumerate() {
            args.push(match s {
                Some(v) => v,
                None if missing_value == Some(declared[i].name)
                    && declared[i].ty.is(Builtin::Optional)
                    && declared[i].ty.args[0].is(Builtin::Error) =>
                {
                    self.at(e.pos);
                    let cause_ty = self.mty(&declared[i].ty.args[0])?;
                    let cause = self.missing_value_at(cause_ty, e.pos)?;
                    let cause = self.owned(cause);
                    let present = self.b.opt_some(cause);
                    let supplied = self.lift_argument(
                        Val {
                            v: present,
                            own: true,
                        },
                        ptys[i],
                    );
                    self.borrow(supplied)
                }
                None if matches!(self.b.m.types.kind(ptys[i]), TyKind::Opt(_)) => {
                    self.b.opt_none(ptys[i])
                }
                None => return Err(Error::new("missing argument in a call of a function value")),
            });
        }
        self.at(e.pos);
        let v = self.b.call_ind(fv, &args);
        self.restore_var_arguments(slots_out, |p| places.get(p).cloned().flatten())?;
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
        b.emit(Op::Clone, &[this], Imm::None, Some(recv_ty))
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
    syms: ms_check::api::Names,
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &crate::cx::DefaultThunkJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let hir = cx.module(job.callable.module.file)?;
    let file = m.add_file(syms.str(job.callable.module.file));
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    b.func_mut().capture_closers = proto.capture_closers.clone();
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
    // The callee borrows its arguments: a supplied value is passed as it is, and an omitted
    // one's default lives in a holder until the callee returns.
    let mut slots: Vec<Option<Val>> = vec![None; callee.parameters.len()];
    let mut holders: Vec<Value> = Vec::new();
    for i in 0..slots.len() {
        let v = params[i + 1];
        let declared = fl.mty(&callee.parameters[i].ty)?;
        slots[i] = Some(if fl.ty_of(v) == declared {
            Val { v, own: false }
        } else {
            let earlier = slots.clone();
            let (val, held) = fl.unlift_param_borrowed(v, &mut |s| {
                let mut earlier = earlier.clone();
                s.default_argument(&callee, i, &job.subst, &mut earlier, recv, None)
            })?;
            // A `try` in a later default returns early: the holder must drop on that path too.
            fl.pend_temp(held);
            holders.push(held);
            val
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
    // A callee returning a borrow points into its receiver or a holder: copy it before the
    // holders drop.
    let r = if fl.b.m.funcs[fid.index()].ret_borrowed {
        let t = fl.ty_of(r);
        if fl.part_closer_mir(t)?.is_some() {
            return Err(Error::new(
                "a method value returns a borrowed resource; call the method instead",
            ));
        }
        fl.clone_value(r)
    } else {
        r
    };
    for held in holders {
        fl.unhold_temp(held);
        fl.drop_value(held);
    }
    let out = fl.val(r, true);
    fl.emit_return(Some(out));
    Ok(())
}

/// Lowers the body of a queued interface method value.
pub(crate) fn build_iface_thunk(
    syms: ms_check::api::Names,
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &crate::cx::IfaceThunkJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let file = m.add_file(syms.str(job.hir.data.file));
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    let mut fl = FnLower::new(
        cx,
        b,
        job.hir.clone(),
        ct::Subst::default(),
        file,
        proto.ret,
    );
    let result = lower_iface_thunk(&mut fl, job, job.recv);
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
    syms: ms_check::api::Names,
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &NativeThunkJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let file = m.add_file(syms.str(job.hir.data.file));
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    let mut fl = FnLower::new(
        cx,
        b,
        job.hir.clone(),
        ct::Subst::default(),
        file,
        proto.ret,
    );
    let result = lower_native_thunk(syms, &mut fl, job);
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

fn lower_native_thunk(
    syms: ms_check::api::Names,
    fl: &mut FnLower<'_>,
    job: &NativeThunkJob,
) -> Result<(), Error> {
    let params = fl.b.params();
    let func = job.sym.decl.as_ref().and_then(|d| d.func());
    let mut args = fl.thunk_native_args(job.sym.module, func, &job.params, &params[1..])?;
    let ret = fl.ret_ty;
    let identity = match job.native {
        ct::Native::Extern { symbol, .. } => {
            crate::stdnative::by_symbol(syms.str(symbol)).map_or("", |h| h.identity)
        }
        native => native.text(syms),
    };
    match identity {
        "json/parse" | "json/stringify" => {
            // Generic natives with their own lowering: the type argument comes from the instance.
            fl.fill_native_defaults(job.sym.module, func, &job.params, &mut args)?;
            let have = fl.mty(&job.result)?;
            let r = if identity == "json/parse" {
                let t = job.result.args.first().cloned();
                let t = t.ok_or_else(|| Error::new("parse without a result type"))?;
                fl.json_parse(&t, have, &args)?
            } else {
                let value = job.params.iter().find(|p| syms.str(p.name) == "value");
                let t = value.map(|p| p.ty.clone());
                let t = t.ok_or_else(|| Error::new("stringify without a value"))?;
                fl.json_stringify(t, have, &args)?
            };
            let out = fl.fit_ty(r, &job.result, ret)?;
            fl.emit_return(Some(out));
            return Ok(());
        }
        other => {
            if let Some(handle) = crate::stdnative::handle_of(other) {
                let out = fl.handle_interface(
                    &job.result,
                    ret,
                    handle.module,
                    handle.make,
                    handle.constant,
                )?;
                fl.emit_return(Some(out));
                return Ok(());
            }
        }
    }
    let out = match job.native {
        ct::Native::Extern {
            symbol,
            bundled: true,
        } => fl.rt_function(syms.str(symbol), &job.params, &args, ret)?,
        _ => fl.native_call(identity, &job.params, &args, ret)?,
    };
    fl.emit_return(Some(out));
    Ok(())
}

impl FnLower<'_> {
    /// The arguments of a native called through a function value: a parameter the function type
    /// made optional is read as its supplied value or the declared default.
    pub(crate) fn thunk_native_args(
        &mut self,
        module: ct::Name,
        func: Option<&ms_check::api::ast::Func>,
        params: &[ct::Param],
        vals: &[Value],
    ) -> Result<Vec<crate::native::NArg>, Error> {
        let mut args: Vec<crate::native::NArg> = Vec::new();
        for (i, (p, v)) in params.iter().zip(vals).enumerate() {
            let default = func.and_then(|f| f.params.get(i)?.default.as_ref());
            let omittable = default.is_some() || p.ty.is(Builtin::Optional);
            let passed = self.ty_of(*v);
            let declared = if omittable && matches!(self.b.m.types.kind(passed), TyKind::Opt(_)) {
                self.mty(&p.ty)?
            } else {
                passed
            };
            let lifted = passed != declared;
            let none_default = p.ty.is(Builtin::Optional)
                && match default {
                    None => true,
                    Some(d) => {
                        let f = func.expect("a default has a declaration");
                        self.func_decl_module(module, f)?.default_form(self.syms, d)
                            == ms_check::api::syntax::DefaultForm::None
                    }
                };
            let val = if lifted && none_default {
                // Native/interface arguments borrow their caller's values. A supplied payload and
                // the implicit none both live through this call; copying here would make
                // even an ignored cause pay copy/drop costs before the native reads it.
                let supplied = self.b.opt_is_some(*v);
                self.two_ways_mode(
                    supplied,
                    declared,
                    Mode::Borrow,
                    &mut |s| Ok(Some(s.b.opt_get(*v))),
                    &mut |s| Ok(Some(s.b.opt_none(declared))),
                )?
            } else if lifted {
                self.unlift_param(*v, &mut |s| {
                    let mut tmp: Vec<crate::native::NArg> = params
                        .iter()
                        .enumerate()
                        .filter(|(j, _)| *j != i)
                        .map(|(_, q)| crate::native::NArg {
                            name: q.name,
                            val: Val { v: *v, own: false },
                            wrapped: false,
                            reader: false,
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
                reader: false,
            });
        }
        Ok(args)
    }
}

/// Lowers the body of a queued bound native method.
pub(crate) fn build_bound_native(
    syms: ms_check::api::Names,
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &BoundNativeJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let FuncKind::Closure { captures } = proto.kind.clone() else {
        return Err(Error::new("bound method without closure kind"));
    };
    let file = m.add_file(syms.str(job.hir.data.file));
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    b.func_mut().capture_closers = proto.capture_closers.clone();
    let mut fl = FnLower::new(
        cx,
        b,
        job.hir.clone(),
        ct::Subst::default(),
        file,
        proto.ret,
    );
    fl.scope_override = Some(job.scope);
    let recv_ty = match job.held {
        Held::Value => captures[0],
        Held::Shared(t) | Held::Borrowed(t) => t,
    };
    let result = lower_bound_native(&mut fl, job, recv_ty);
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

/// Lowers the body of a native method behind an interface table entry.
pub(crate) fn build_iface_native(
    syms: ms_check::api::Names,
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &IfaceNativeJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let file = m.add_file(syms.str(job.hir.data.file));
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    b.func_mut().linkage = proto.linkage;
    let mut fl = FnLower::new(
        cx,
        b,
        job.hir.clone(),
        ct::Subst::default(),
        file,
        proto.ret,
    );
    fl.scope_override = Some(job.scope);
    let result = lower_iface_native(syms, &mut fl, job);
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

fn lower_iface_native(
    syms: ms_check::api::Names,
    fl: &mut FnLower<'_>,
    job: &IfaceNativeJob,
) -> Result<(), Error> {
    let params = fl.b.params();
    let func = job.method.decl.as_ref().and_then(|d| d.func());
    let ret = fl.ret_ty;
    let args =
        fl.thunk_native_args(job.method.module, func, &job.method.ty.params, &params[1..])?;
    let out = if ms_check::api::ownership::collection_mutation(syms, &job.method) {
        // The table entry receives the address of the value it changes.
        fl.shared_native_call(&job.method, params[0], job.data, &args, ret)?
    } else {
        let v =
            fl.b.emit(Op::Load, &[params[0]], Imm::Ty(job.data), Some(job.data))
                .expect("load");
        fl.bound_native_call(&job.method, Val { v, own: false }, &args, ret)?
    };
    fl.emit_return(Some(out));
    Ok(())
}

fn lower_bound_native(
    fl: &mut FnLower<'_>,
    job: &BoundNativeJob,
    recv_ty: MTy,
) -> Result<(), Error> {
    let params = fl.b.params();
    let env = params[0];
    let held = job.held.capture(recv_ty);
    fl.in_thunk = true;
    let mut cap =
        fl.b.emit(Op::ClosureCap, &[env], Imm::Idx(0), Some(held))
            .expect("capture");
    let func = job.method.decl.as_ref().and_then(|d| d.func());
    let ret = fl.ret_ty;
    let args =
        fl.thunk_native_args(job.method.module, func, &job.method.ty.params, &params[1..])?;
    debug_assert_eq!(args.len(), job.consumed_arguments.len());
    debug_assert_eq!(args.len(), job.method.ty.params.len());
    for ((arg, consumed), param) in args
        .iter()
        .zip(&job.consumed_arguments)
        .zip(&job.method.ty.params)
    {
        debug_assert_eq!(arg.name, param.name);
        if *consumed && !arg.val.own && fl.cx.classes.concretely_clonable(fl.syms, &param.ty) {
            fl.boundary_reads.insert(arg.val.v);
        }
    }
    if let Held::Shared(_) = job.held {
        let out = fl.shared_native_call(&job.method, cap, recv_ty, &args, ret)?;
        fl.emit_return(Some(out));
        return Ok(());
    }
    if let Held::Borrowed(_) = job.held {
        // The closure points at the receiver it only reads.
        cap =
            fl.b.emit(Op::Load, &[cap], Imm::Ty(recv_ty), Some(recv_ty))
                .expect("load");
    }
    let recv = Val { v: cap, own: false };
    let out = fl.bound_native_call(&job.method, recv, &args, ret)?;
    fl.emit_return(Some(out));
    Ok(())
}

/// Lowers the body of a queued lambda.
pub(crate) fn build_lambda(
    syms: ms_check::api::Names,
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &LambdaJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let FuncKind::Closure { captures } = proto.kind.clone() else {
        return Err(Error::new("lambda function without closure kind"));
    };
    let file = m.add_file(syms.str(job.hir.data.file));
    let mut b = FuncBuilder::new(m, "<anonymous>", proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    b.func_mut().scoped = proto.scoped;
    b.func_mut().keeps_scoped = proto.keeps_scoped;
    b.func_mut().capture_closers = proto.capture_closers.clone();
    let mut fl = FnLower::new(cx, b, job.hir.clone(), job.subst.clone(), file, proto.ret);
    fl.variant = job.variant;
    let result = lower_lambda_body(syms, &mut fl, job, &captures);
    let mut f = fl.b.into_func();
    result?;
    // Frames of callees inlined into the closure return to this file, not the callee's.
    f.loc = ms_mir::ir::Loc::new(file, job.expr.pos.line, job.expr.pos.column);
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
            opt: false,
        },
    );
    let steps = steps
        .iter()
        .map(|step| match step {
            CapturedStep::Field(name) => crate::alias::AStep::Field(*name),
            CapturedStep::Some => crate::alias::AStep::Some,
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

fn lower_lambda_body(
    syms: ms_check::api::Names,
    fl: &mut FnLower<'_>,
    job: &LambdaJob,
    captures: &[MTy],
) -> Result<(), Error> {
    let ExprKind::Lambda(lam) = &job.expr.kind else {
        return Err(Error::new("not a lambda"));
    };
    let params = fl.b.params();
    let env = params[0];
    let mutated = lambda_mutated(syms, fl, lam);
    fl.slotted = slotted_in(syms, fl, &lam.body);
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
        if let LambdaCapture::Borrowed(b, index) = capture {
            let ty = fl.mty(&b.ty)?;
            let v =
                fl.b.emit(Op::Load, &[values[*index]], Imm::Ty(ty), Some(ty))
                    .expect("load");
            fl.bind_borrowed(b, v);
            continue;
        }
        if let LambdaCapture::Owned(b, index) = capture {
            let ty = fl.mty(&b.ty)?;
            let addr =
                fl.b.emit(
                    Op::ClosureCapAddr,
                    &[env],
                    Imm::Idx(*index as u32),
                    Some(MTy::PTR),
                )
                .expect("capture address");
            let var = fl.b.declare_var(ty, Mode::Borrow);
            fl.locals.insert(
                b.uid,
                crate::func::Local {
                    var,
                    ty,
                    slot: Some(addr),
                    opt: false,
                },
            );
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
                    opt: false,
                },
            );
        } else if mutated.contains(&b.uid) {
            // The closure changes its own snapshot: work on a clone.
            fl.bind_local(b, Val { v, own: false });
        } else {
            fl.bind_borrowed(b, v);
        }
    }
    let bindings = fl.hir.lambda_parameters(&job.expr);
    // As for a named function: a `var` parameter stays in the caller's slot when the body's
    // scopes close resources, so the pass's error exit has nothing to put back.
    fl.closing_fn = closes_resources(fl, bindings.iter(), &lam.body);
    for (i, (b, v)) in bindings.iter().zip(params.iter().skip(1)).enumerate() {
        if lam.params.get(i).is_some_and(|p| p.mutable) {
            // A `var` parameter: the lambda owns the value it takes from the slot and puts back
            // on return, as a named function does.
            fl.bind_var_parameter(b, *v)?;
            continue;
        }
        let default = lam.params.get(i).and_then(|p| p.default.as_ref());
        // Only an extra ABI wrapper denotes omission; T itself may instantiate as Optional.
        let lifted = default.is_some()
            && matches!(fl.b.m.types.kind(fl.ty_of(*v)), TyKind::Opt(_))
            && fl.ty_of(*v) != fl.mty(&b.ty)?;
        if lifted {
            let d = default.expect("lifted parameter has a default");
            let x = fl.unlift_param(*v, &mut |s| s.expr(d))?;
            fl.bind_local(b, x);
        } else if mutated.contains(&b.uid) && fl.needs_drop(fl.ty_of(*v)) {
            // A parameter the body changes is the lambda's own copy.
            fl.bind_local(b, Val { v: *v, own: false });
        } else {
            // A function value borrows its arguments (the call rule), so a lambda that hands one
            // back (`fn acc, k, v: acc`) copies it: the declared adaptation of the borrowed
            // signature, which fold-style callers consume.
            fl.boundary_reads.insert(*v);
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
fn lambda_mutated(
    syms: ms_check::api::Names,
    fl: &FnLower<'_>,
    lam: &Lambda,
) -> ms_check::fxmap::HashSet<usize> {
    let scan = |body| {
        crate::mutation::mutated_locals(syms, &fl.hir, body, &fl.cx.callables, &fl.cx.mutated)
    };
    let mut changed = scan(ms_check::api::hir::Body::Block(&lam.body));
    // A default runs in the lambda's frame, so what it changes counts too.
    for d in lam.params.iter().filter_map(|p| p.default.as_ref()) {
        changed.extend(scan(ms_check::api::hir::Body::Expr(d)));
    }
    with_alias_origins(fl, &lam.body, changed)
}

/// The captured locals the lambda `lam` changes: they are shared by reference.
fn lambda_changes(
    syms: ms_check::api::Names,
    fl: &FnLower<'_>,
    lam: &Lambda,
    captures: &[ct::BindingRef],
) -> ms_check::fxmap::HashSet<usize> {
    let mutated = lambda_mutated(syms, fl, lam);
    captures
        .iter()
        .map(|b| b.uid)
        .filter(|uid| mutated.contains(uid))
        .collect()
}

/// Whether a parameter, `let`, loop variable or match payload of `body` closes a resource when
/// its scope ends.
pub(crate) fn closes_resources<'p>(
    fl: &FnLower<'_>,
    params: impl Iterator<Item = &'p ct::BindingRef>,
    body: &[Stmt],
) -> bool {
    use ms_check::api::ownership::BindingFact::ImplicitClose;
    struct Scan<'a, 'b> {
        fl: &'a FnLower<'b>,
        found: bool,
    }
    impl ms_check::api::visit::Visitor for Scan<'_, '_> {
        fn stmt(&mut self, s: &Stmt) {
            self.found |= self.fl.hir.stmt(s).cleanup.is_some();
        }
        fn expr(&mut self, e: &Expr) {
            if let ExprKind::Match { arms, .. } = &e.kind {
                for arm in arms {
                    for b in self.fl.hir.arm(arm).bindings.iter().flatten() {
                        self.found |= self.fl.cx.ownership.binding_facts.has(b.uid, ImplicitClose);
                    }
                }
            }
        }
    }
    let params = params
        .into_iter()
        .any(|b| fl.cx.ownership.binding_facts.has(b.uid, ImplicitClose));
    let mut scan = Scan { fl, found: params };
    ms_check::api::visit::walk_block(&mut scan, body);
    scan.found
}

/// The locals a closure written in `body` changes: they must live in memory.
pub(crate) fn slotted_in(
    syms: ms_check::api::Names,
    fl: &FnLower<'_>,
    body: &[Stmt],
) -> ms_check::fxmap::HashSet<usize> {
    struct Scan<'a, 'b> {
        fl: &'a FnLower<'b>,
        found: ms_check::fxmap::HashSet<usize>,
    }
    impl ms_check::api::visit::Visitor for Scan<'_, '_> {
        fn expr(&mut self, e: &Expr) {
            let syms = self.fl.syms;
            if let ExprKind::Lambda(lam) = &e.kind {
                let captures = self.fl.hir.captures(e);
                self.found
                    .extend(lambda_changes(syms, self.fl, lam, &captures));
            }
        }
    }
    let mut scan = Scan {
        fl,
        found: Default::default(),
    };
    ms_check::api::visit::walk_block(&mut scan, body);
    scan.found.extend(crate::mutation::changing_method_roots(
        syms,
        &fl.hir,
        ms_check::api::hir::Body::Block(body),
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
    mut changed: ms_check::fxmap::HashSet<usize>,
) -> ms_check::fxmap::HashSet<usize> {
    struct Origins<'a, 'b> {
        fl: &'a FnLower<'b>,
        roots: ms_check::fxmap::HashMap<usize, usize>,
    }
    impl ms_check::api::visit::Visitor for Origins<'_, '_> {
        fn expr(&mut self, e: &Expr) {
            let syms = self.fl.syms;
            // `c?.f()` borrows `c` for the payload binding of its chain.
            let ExprKind::Match { scrutinee, arms } = &e.kind else {
                return;
            };
            for arm in arms.iter().filter(|a| a.chain) {
                for b in self.fl.hir.arm(arm).bindings.iter().flatten() {
                    if self.fl.cx.exclusive(b.uid)
                        && let Some(root) = alias_origin(syms, self.fl, scrutinee)
                    {
                        self.roots.insert(b.uid, root);
                    }
                }
            }
        }

        fn stmt(&mut self, s: &Stmt) {
            let syms = self.fl.syms;
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
            if self.fl.cx.exclusive(binding.uid)
                && let Some(root) = alias_origin(syms, self.fl, value)
            {
                self.roots.insert(binding.uid, root);
            }
        }
    }
    let mut origins = Origins {
        fl,
        roots: Default::default(),
    };
    ms_check::api::visit::walk_block(&mut origins, body);
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

fn alias_origin(syms: ms_check::api::Names, fl: &FnLower<'_>, e: &Expr) -> Option<usize> {
    match &e.kind {
        ExprKind::Name(_) => {
            let ms_check::api::hir::Resolution::Local(b) = fl.hir.resolution(e) else {
                return None;
            };
            Some(b.uid)
        }
        ExprKind::Member { left, .. } => alias_origin(syms, fl, left),
        ExprKind::Probe(target) => alias_origin(syms, fl, target),
        ExprKind::Call { callee, args } => {
            let source = match (&callee.kind, fl.hir.resolution(e)) {
                (ExprKind::Member { left, .. }, ms_check::api::hir::Resolution::Method(_)) => {
                    &**left
                }
                _ => &args.first()?.value,
            };
            alias_origin(syms, fl, source)
        }
        _ => crate::mutation::index_parts(syms, &fl.hir, e)
            .and_then(|(left, _)| alias_origin(syms, fl, left)),
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
        self.make_fn_adapter(x, have, want, &wp, wr, Vec::new())
    }

    /// A function value that only reads a parameter, used where its type may change it
    /// (`fn(P)` for `fn(var P)`): the adapter takes the address of the caller's slot and passes
    /// the value there to the held function, which borrows it like any function value does.
    pub(crate) fn fit_reader_function(
        &mut self,
        e: &Expr,
        x: Val,
        src: &ct::Ty,
    ) -> Result<Val, Error> {
        let want_ty = self.hir.ty(e);
        let want = self.mty(&want_ty)?;
        let have = self.ty_of(x.v);
        let (TyKind::Fn(_, _), TyKind::Fn(wp, wr)) = (
            self.b.m.types.kind(have).clone(),
            self.b.m.types.kind(want).clone(),
        ) else {
            return Err(Error::new("a reader function without function types"));
        };
        let reads: Vec<bool> = want_ty
            .params
            .iter()
            .zip(&src.params)
            .map(|(w, s)| w.mutable && !s.mutable)
            .collect();
        self.make_fn_adapter(x, have, want, &wp, wr, reads)
    }

    fn make_fn_adapter(
        &mut self,
        x: Val,
        have: MTy,
        want: MTy,
        wp: &[MTy],
        wr: MTy,
        reads: Vec<bool>,
    ) -> Result<Val, Error> {
        let mut ps = vec![Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        }];
        ps.extend(wp.iter().map(|t| Param {
            ty: *t,
            mode: Mode::Borrow,
        }));
        let mut f = ms_mir::ir::Func::new("<function adapter>", ps, wr);
        // A held closure that points into this frame stays here: the adapter reads it through
        // a pointer to a slot, and is itself scoped.
        let scoped = self.b.is_scoped_closure(x.v);
        f.kind = FuncKind::Closure {
            captures: vec![if scoped { MTy::PTR } else { have }],
        };
        f.scoped = scoped;
        let id = self.b.m.add_func(f);
        self.cx.queue.push(Job {
            func: id,
            kind: JobKind::FnAdapt(Rc::new(crate::cx::FnAdaptJob {
                hir: self.hir.clone(),
                have,
                scoped,
                reads,
            })),
        });
        let held = if scoped {
            let slot = self
                .b
                .emit(Op::Slot, &[], Imm::Ty(have), Some(MTy::PTR))
                .expect("slot");
            self.b.emit(Op::Store, &[slot, x.v], Imm::None, None);
            // The adapter reads the value in place, so it stays alive to the end of the statement.
            if x.own {
                self.pend_temp(x.v);
            }
            slot
        } else {
            // The adapter holds the function value it adapts: it takes an owned one over and
            // copies a borrowed one.
            if x.own { x.v } else { self.owned_boundary(x) }
        };
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
    syms: ms_check::api::Names,
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &crate::cx::FnAdaptJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let file = m.add_file(syms.str(job.hir.data.file));
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    let mut fl = FnLower::new(
        cx,
        b,
        job.hir.clone(),
        ct::Subst::default(),
        file,
        proto.ret,
    );
    let result = lower_fn_adapter(&mut fl, job.have, job.scoped, &job.reads);
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

fn lower_fn_adapter(
    fl: &mut FnLower<'_>,
    have: MTy,
    scoped: bool,
    reads: &[bool],
) -> Result<(), Error> {
    let params = fl.b.params();
    let cap_ty = if scoped { MTy::PTR } else { have };
    let mut held =
        fl.b.emit(Op::ClosureCap, &[params[0]], Imm::Idx(0), Some(cap_ty))
            .expect("capture");
    if scoped {
        held =
            fl.b.emit(Op::Load, &[held], Imm::Ty(have), Some(have))
                .expect("load");
    }
    let TyKind::Fn(hp, _) = fl.b.m.types.kind(have).clone() else {
        return Err(Error::new("function adapter without a function type"));
    };
    let mut args = Vec::new();
    for (i, h) in hp.iter().enumerate() {
        let v = params[i + 1];
        if reads.get(i).copied().unwrap_or(false) {
            // The caller's slot holds the value; the held function only reads it.
            let loaded =
                fl.b.emit(Op::Load, &[v], Imm::Ty(*h), Some(*h))
                    .expect("load");
            args.push(loaded);
            continue;
        }
        if fl.ty_of(v) == *h {
            args.push(v);
            continue;
        }
        // A function value borrows its arguments; the adapter's copy is checked by `require_clonable`.
        let o = fl.clone_value(v);
        let some = fl.b.opt_some(o);
        args.push(fl.borrow(Val { v: some, own: true }));
    }
    let r = fl.b.call_ind(held, &args);
    let out = fl.val(r, true);
    fl.emit_return(Some(out));
    Ok(())
}
