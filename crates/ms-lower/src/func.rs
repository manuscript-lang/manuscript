//! Function instances and the per-function lowering state.

use crate::cx::{Cx, Job, JobKind};
use crate::{Error, Options};
use ms_check::Program;
use ms_check::hir::{Callable, CallableKind, ModuleHir};
use ms_check::types::{self as ct, BindingRef, Subst};
use ms_mir::builder::{FuncBuilder, Var};
use ms_mir::ir::{Block, FuncId, Linkage, Loc, Mode, Module, Op, Param, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::Pos;
use std::collections::HashMap;
use std::rc::Rc;

/// An evaluated operand: the SSA value and whether it is an owned temporary.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Val {
    pub v: Value,
    /// The value carries a reference the holder must consume.
    pub own: bool,
}

/// A source variable bound to an SSA variable.
#[derive(Clone, Copy)]
pub(crate) struct Local {
    pub var: Var,
    pub ty: MTy,
}

/// A changed parameter: the slot address it arrives in and leaves through.
#[derive(Clone, Copy)]
pub(crate) struct VarSlot {
    pub uid: usize,
    pub ptr: Value,
}

/// Targets of `break` and `continue`.
pub(crate) struct LoopCtx {
    pub brk: Block,
    pub cont: Block,
    /// Scope depth at loop entry.
    pub depth: usize,
    /// A `continue` branches to `cont`.
    pub cont_used: bool,
    /// A `break` branches to `brk`.
    pub brk_used: bool,
}

/// Per-function lowering state.
pub(crate) struct FnLower<'a> {
    pub cx: &'a mut Cx,
    pub b: FuncBuilder<'a>,
    pub hir: Rc<ModuleHir>,
    pub subst: Subst,
    pub file: u32,
    pub locals: HashMap<usize, Local>,
    /// Locals needing a drop, per lexical scope.
    pub scopes: Vec<Vec<usize>>,
    /// `with` bindings and how each is closed when its scope is left.
    pub closers: HashMap<usize, crate::with::Closer>,
    /// Owned temporaries borrowed by the current statement.
    pub temps: Vec<Value>,
    pub loops: Vec<LoopCtx>,
    /// The current position is unreachable.
    pub dead: bool,
    pub ret_ty: MTy,
    /// The body is bracketed by `depth.enter` / `depth.leave` (the optimizer removes it for non-recursive functions).
    pub counts_depth: bool,
    /// Record to build on return and the binding uids of the `var` parameters it carries.
    pub var_slots: Vec<VarSlot>,
    /// The expression statement being lowered, whose value nothing reads (by address).
    pub discard: Option<usize>,
    /// The start of the statement being lowered.
    pub stmt_pos: Option<Pos>,
    /// The fixture hooks a test runs after its body, on every exit.
    pub fixture: Option<crate::fixture::Hooks>,
}

impl Cx {
    /// Positions (receiver first) of the parameters a callable hands back changed.
    pub(crate) fn var_positions(&self, c: &Callable) -> Vec<usize> {
        let key = (c.module.file, c.id());
        let count = c.self_binding.iter().len() + c.parameters.len();
        (0..count)
            .filter(|i| self.mutated.contains(&(key, *i)))
            .collect()
    }
}

/// The reserved instance key of a callable under a substitution.
fn instance_key(c: &Callable, subst: &Subst) -> String {
    let mut vars: Vec<(&str, String)> = subst
        .iter()
        .map(|(k, v)| (k.as_str(), ct::type_key(v)))
        .collect();
    vars.sort();
    let mut key = format!("{}#{}", c.module.file, c.id().0);
    for (k, v) in vars {
        key.push_str(&format!("|{k}={v}"));
    }
    key
}

impl Cx {
    /// The checked result type of a callable (generic-open).
    pub(crate) fn callable_result(&self, c: &Callable) -> Result<ct::Ty, Error> {
        let hir = self.module(c.module.file)?;
        if let Some(f) = c.func.func() {
            return hir
                .type_ref(f.result.id)
                .ok_or_else(|| Error::new(format!("no result type for {}", c.name)));
        }
        match c.kind {
            CallableKind::Constant => {
                let d = c.func.decl.constant().expect("constant");
                Ok(hir.ty(&d.value))
            }
            CallableKind::Test => Ok(ct::test_outcome()),
            _ => Err(Error::new("callable without result")),
        }
    }

    /// Reserves (and queues) the instance of `c` under `subst`.
    pub(crate) fn function_for(
        &mut self,
        m: &mut Module,
        c: &Rc<Callable>,
        subst: &Subst,
    ) -> Result<FuncId, Error> {
        let key = instance_key(c, subst);
        if let Some(id) = self.insts.get(&key) {
            return Ok(*id);
        }
        let mut params = Vec::new();
        let bindings: Vec<&BindingRef> = c.self_binding.iter().chain(c.parameters.iter()).collect();
        let vars = self.var_positions(c);
        for (i, b) in bindings.into_iter().enumerate() {
            let t = ct::sub(&b.ty, subst);
            let ty = self.lower_ty(m, &t)?;
            // A changed parameter travels as the address of a slot the callee takes the value
            // from and puts the final value back into.
            let ty = if vars.contains(&i) { MTy::PTR } else { ty };
            params.push(Param {
                ty,
                mode: Mode::Borrow,
            });
        }
        let result = ct::sub(&self.callable_result(c)?, subst);
        let ret = self.lower_ty(m, &result)?;
        let name = if let ms_syntax::ast::DeclKind::Test(t) = &c.func.decl.decl().kind {
            format!("test {}", t.name)
        } else if c.name.as_str().is_empty() {
            "test".to_string()
        } else if let ms_syntax::ast::DeclKind::Impl(i) = &c.func.decl.decl().kind {
            // Fault traces name a method after its receiver type.
            format!("{}.{}", i.receiver.name(), c.name)
        } else {
            c.name.to_string()
        };
        let f = ms_mir::ir::Func::new(&name, params, ret);
        let id = m.add_func(f);
        self.insts.insert(key, id);
        self.queue.push(Job {
            func: id,
            kind: JobKind::Source {
                callable: c.clone(),
                subst: subst.clone(),
            },
        });
        Ok(id)
    }
}

/// Lowers the program rooted at `options.entry`.
pub(crate) fn lower_program(program: &Program, options: &Options) -> Result<Module, Error> {
    let mut cx = Cx::new(program);
    let mut m = Module::new("main");
    let entry_file = ct::n(&options.entry);
    let main = cx
        .callables
        .values()
        .find(|c| {
            c.module.file == entry_file
                && c.kind == CallableKind::Function
                && c.name.as_str() == "main"
        })
        .cloned()
        .ok_or_else(|| Error::new("no main function"))?;
    let main_id = cx.function_for(&mut m, &main, &Subst::new())?;
    drain(&mut cx, &mut m)?;
    let f = &mut m.funcs[main_id.index()];
    f.linkage = Linkage::Export;
    m.entry = Some(main_id);
    Ok(m)
}

/// Lowers the tests of `options.entry` with a runner as the entry; returns the test names.
pub(crate) fn lower_tests(
    program: &Program,
    options: &Options,
) -> Result<(Module, Vec<String>), Error> {
    let mut cx = Cx::new(program);
    let mut m = Module::new("main");
    let entry_file = ct::n(&options.entry);
    let tests: Vec<Rc<Callable>> = cx
        .module(entry_file)?
        .callables()
        .into_iter()
        .filter(|c| c.kind == CallableKind::Test)
        .map(|c| cx.callables[&(entry_file, c.id())].clone())
        .collect();
    let mut ids = Vec::new();
    let mut names = Vec::new();
    for c in &tests {
        if let ms_syntax::ast::DeclKind::Test(t) = &c.func.decl.decl().kind {
            names.push(t.name.to_string());
        }
        ids.push(cx.function_for(&mut m, c, &Subst::new())?);
    }
    drain(&mut cx, &mut m)?;
    m.entry = Some(crate::runner::build_runner(&mut m, &ids)?);
    Ok((m, names))
}

/// Lowers queued jobs until none remain. The text of an interface value tests every table of
/// the interface, so it waits until no other job can still add one.
fn drain(cx: &mut Cx, m: &mut Module) -> Result<(), Error> {
    let deferred = |m: &Module, j: &Job| matches!(&j.kind, JobKind::Format(t, _) if matches!(m.types.kind(*t), ms_mir::types::TyKind::Iface(_)));
    loop {
        let next = match cx.queue.iter().rposition(|j| !deferred(m, j)) {
            Some(i) => cx.queue.remove(i),
            None => match cx.queue.pop() {
                Some(j) => j,
                None => return Ok(()),
            },
        };
        lower_job(cx, m, next)?;
    }
}

fn lower_job(cx: &mut Cx, m: &mut Module, job: Job) -> Result<(), Error> {
    let (c, jsubst) = match &job.kind {
        JobKind::Source { callable, subst } => (callable.clone(), subst.clone()),
        JobKind::Format(t, repr) => {
            return crate::text::build_format(cx, m, job.func, *t, *repr);
        }
        JobKind::Equal(t) => return crate::eq::build_eq(cx, m, job.func, *t),
        JobKind::HandleMethod(j) => {
            return crate::natiface::build_method(cx, m, job.func, j);
        }
        JobKind::Codec(j) => {
            return crate::codecstream::build_codec_method(cx, m, job.func, j);
        }
        JobKind::Lambda(l) => return crate::closure::build_lambda(cx, m, job.func, l),
        JobKind::BoundNative(n) => return crate::closure::build_bound_native(cx, m, job.func, n),
        JobKind::DefaultThunk(n) => return crate::closure::build_default_thunk(cx, m, job.func, n),
        JobKind::NativeThunk(n) => return crate::closure::build_native_thunk(cx, m, job.func, n),
        JobKind::Json(j) => return crate::json::build_json(cx, m, job.func, j),
        JobKind::Html(j) => return crate::html::build_html(cx, m, job.func, j),
    };
    let hir = cx.module(c.module.file)?;
    let file = m.add_file(c.module.file.as_str());
    let proto = m.funcs[job.func.index()].clone();
    let b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    let mut fl = FnLower::new(cx, b, hir, jsubst, file, proto.ret);
    let result = fl.lower_callable(&c);
    let mut func = fl.b.into_func();
    result?;
    func.compact_blocks();
    m.funcs[job.func.index()] = func;
    Ok(())
}

impl<'a> FnLower<'a> {
    pub(crate) fn new(
        cx: &'a mut Cx,
        b: FuncBuilder<'a>,
        hir: Rc<ModuleHir>,
        subst: Subst,
        file: u32,
        ret_ty: MTy,
    ) -> FnLower<'a> {
        FnLower {
            cx,
            b,
            hir,
            subst,
            file,
            locals: HashMap::new(),
            scopes: vec![Vec::new()],
            closers: HashMap::new(),
            temps: Vec::new(),
            loops: Vec::new(),
            dead: false,
            ret_ty,
            counts_depth: false,
            var_slots: Vec::new(),
            discard: None,
            stmt_pos: None,
            fixture: None,
        }
    }

    /// The source position as a MIR location.
    pub fn loc(&self, pos: Pos) -> Loc {
        Loc::new(self.file, pos.line, pos.column)
    }

    /// Sets the location of subsequent instructions.
    pub fn at(&mut self, pos: Pos) {
        let pos = self.stmt_pos.unwrap_or(pos);
        let l = self.loc(pos);
        self.b.set_loc(l);
    }

    /// The MIR type of a checker type under the instance substitution.
    pub fn mty(&mut self, t: &ct::Ty) -> Result<MTy, Error> {
        let t = ct::sub(t, &self.subst);
        self.cx.lower_ty(self.b.m, &t)
    }

    /// Whether values of `t` need a drop.
    pub fn needs_drop(&self, t: MTy) -> bool {
        self.b.m.needs_drop(t)
    }

    /// The declared result type (without the `var` parameters a function hands back).
    pub fn result_ty(&self) -> MTy {
        self.ret_ty
    }

    pub fn ty_of(&self, v: Value) -> MTy {
        self.b.ty(v)
    }

    // ----------------------------------------------------------- ownership

    /// An owned reference to the operand: the temporary itself, or a copy of a borrow.
    pub fn owned(&mut self, x: Val) -> Value {
        if x.own || !self.needs_drop(self.ty_of(x.v)) {
            return x.v;
        }
        let t = self.ty_of(x.v);
        self.b
            .emit(Op::Copy, &[x.v], ms_mir::ir::Imm::None, Some(t))
            .expect("copy result")
    }

    /// An owned `none` of optional type `t` (a bare `opt.none` is a borrow).
    pub fn none_owned(&mut self, t: MTy) -> Value {
        let n = self.b.opt_none(t);
        self.owned(Val { v: n, own: false })
    }

    /// The operand for a borrowing use; owned temporaries are dropped by `flush_temps`.
    pub fn borrow(&mut self, x: Val) -> Value {
        if x.own && self.needs_drop(self.ty_of(x.v)) {
            self.temps.push(x.v);
        }
        x.v
    }

    /// Drops the owned temporaries registered after `mark`.
    pub fn flush_temps(&mut self, mark: usize) {
        while self.temps.len() > mark {
            let v = self.temps.pop().expect("temp");
            if !self.dead {
                self.b.emit(Op::Drop, &[v], ms_mir::ir::Imm::None, None);
            }
        }
    }

    /// Moves an owned value into the slot at `ptr`.
    pub fn move_into(&mut self, ptr: Value, x: Value) {
        let op = if self.needs_drop(self.ty_of(x)) {
            Op::Put
        } else {
            Op::Store
        };
        self.b.emit(op, &[ptr, x], ms_mir::ir::Imm::None, None);
    }

    /// Moves the value of type `t` out of the slot at `ptr`.
    pub fn move_out(&mut self, ptr: Value, t: MTy) -> Value {
        let op = if self.needs_drop(t) {
            Op::Take
        } else {
            Op::Load
        };
        self.b
            .emit(op, &[ptr], ms_mir::ir::Imm::Ty(t), Some(t))
            .expect("slot value")
    }

    /// Drops an owned value now.
    pub fn drop_value(&mut self, v: Value) {
        if self.needs_drop(self.ty_of(v)) && !self.dead {
            self.b.emit(Op::Drop, &[v], ms_mir::ir::Imm::None, None);
        }
    }

    /// Wraps a value known to be owned or not needing ownership.
    pub fn val(&self, v: Value, own: bool) -> Val {
        Val {
            v,
            own: own && self.needs_drop(self.ty_of(v)),
        }
    }

    // -------------------------------------------------------------- locals

    /// Declares the local of `binding` holding `value`.
    pub fn bind_local(&mut self, binding: &BindingRef, x: Val) {
        let ty = self.ty_of(x.v);
        let owned = self.needs_drop(ty);
        let var = self
            .b
            .declare_var(ty, if owned { Mode::Own } else { Mode::Borrow });
        let v = self.owned(x);
        self.b.def_var(var, v);
        self.locals.insert(binding.uid, Local { var, ty });
        if owned {
            self.scopes.last_mut().expect("scope").push(binding.uid);
        }
    }

    /// Holds an operand for the rest of the enclosing scope (a loop's iterable).
    pub fn bind_hidden(&mut self, x: Val) -> ms_mir::builder::Var {
        let ty = self.ty_of(x.v);
        let owned = self.needs_drop(ty);
        let var = self
            .b
            .declare_var(ty, if owned { Mode::Own } else { Mode::Borrow });
        let v = self.owned(x);
        self.b.def_var(var, v);
        self.adopt_hidden(var, ty);
        var
    }

    /// Makes the innermost scope drop `var`, so a `return` or `break` leaving it releases it too.
    pub fn adopt_hidden(&mut self, var: ms_mir::builder::Var, ty: MTy) {
        let uid = usize::MAX - self.locals.len();
        self.locals.insert(uid, Local { var, ty });
        if self.needs_drop(ty) {
            self.scopes.last_mut().expect("scope").push(uid);
        }
    }

    /// Declares a borrowed local (a parameter or a borrowing binding): no drop at scope end.
    pub fn bind_borrowed(&mut self, binding: &BindingRef, v: Value) {
        let ty = self.ty_of(v);
        let var = self.b.declare_var(ty, Mode::Borrow);
        self.b.def_var(var, v);
        self.locals.insert(binding.uid, Local { var, ty });
    }

    pub fn local(&mut self, binding: &BindingRef) -> Result<Local, Error> {
        self.locals
            .get(&binding.uid)
            .copied()
            .ok_or_else(|| Error::new(format!("unbound variable {}", binding.name)))
    }

    /// The current value of a local as a borrow.
    pub fn read_local(&mut self, binding: &BindingRef) -> Result<Val, Error> {
        let l = self.local(binding)?;
        let v = self.b.use_var(l.var);
        Ok(Val { v, own: false })
    }

    // --------------------------------------------------------------- scopes

    pub fn push_scope(&mut self) {
        self.scopes.push(Vec::new());
    }

    fn drop_scope_locals(&mut self, depth: usize) {
        for i in (depth..self.scopes.len()).rev() {
            let uids = self.scopes[i].clone();
            for uid in uids.iter().rev() {
                if let Some(closer) = self.closers.get(uid).cloned() {
                    self.emit_close(*uid, &closer);
                }
                let l = self.locals[uid];
                if self.needs_drop(l.ty) {
                    let v = self.b.use_var(l.var);
                    self.b.emit(Op::Drop, &[v], ms_mir::ir::Imm::None, None);
                }
            }
        }
    }

    /// Ends a scope, dropping its locals when control reaches the end.
    pub fn pop_scope(&mut self) {
        if !self.dead {
            let d = self.scopes.len() - 1;
            self.drop_scope_locals(d);
        }
        self.scopes.pop();
    }

    /// Drops the locals of every scope at or above `depth` (for `break`, `continue`, `return`).
    pub fn unwind_to(&mut self, depth: usize) {
        if !self.dead {
            self.drop_scope_locals(depth);
        }
    }

    // ------------------------------------------------------------- control

    /// Marks the position unreachable after a terminator.
    pub fn terminated(&mut self) {
        self.dead = true;
    }

    /// Starts emitting in `b`, which has at least one live predecessor.
    pub fn enter(&mut self, b: Block) {
        self.b.switch_to(b);
        self.dead = false;
    }

    /// Returns `value` (owned) from the function after dropping every local.
    pub fn emit_return(&mut self, value: Option<Val>) {
        if self.dead {
            return;
        }
        let v = value.map(|x| self.owned(x));
        for slot in self.var_slots.clone() {
            let var = self.locals[&slot.uid].var;
            let x = self.b.use_var(var);
            self.move_into(slot.ptr, x);
        }
        // The temporaries stay registered: a conditional return leaves the others running.
        for t in self.temps.clone().into_iter().rev() {
            self.b.emit(Op::Drop, &[t], ms_mir::ir::Imm::None, None);
        }
        self.end_fixture();
        self.unwind_to(0);
        if self.counts_depth {
            self.b
                .emit(Op::DepthLeave, &[], ms_mir::ir::Imm::None, None);
        }
        self.b.ret(v);
        self.terminated();
    }

    // --------------------------------------------------------------- bodies

    fn lower_callable(&mut self, c: &Rc<Callable>) -> Result<(), Error> {
        let params = self.b.params();
        let bindings: Vec<BindingRef> = c
            .self_binding
            .iter()
            .chain(c.parameters.iter())
            .cloned()
            .collect();
        let vars = self.cx.var_positions(c);
        // Parameters the body changes are the callee's own copies.
        let mutated = match c.body() {
            ms_check::hir::Body::Block(stmts) => crate::mutation::mutated_locals(
                &self.hir,
                ms_check::hir::Body::Block(stmts),
                &self.cx.callables,
                &self.cx.mutated,
            ),
            ms_check::hir::Body::Expr(_) => Default::default(),
        };
        for (i, (b, v)) in bindings.iter().zip(params).enumerate() {
            if vars.contains(&i) {
                // The callee owns the value it takes from the slot and puts back on return.
                let ty = self.mty(&b.ty)?;
                let owned = self.needs_drop(ty);
                let var = self
                    .b
                    .declare_var(ty, if owned { Mode::Own } else { Mode::Borrow });
                let x = self.move_out(v, ty);
                self.b.def_var(var, x);
                self.locals.insert(b.uid, Local { var, ty });
                self.var_slots.push(VarSlot { uid: b.uid, ptr: v });
                continue;
            }
            let own_copy = mutated.contains(&b.uid) && self.needs_drop(self.ty_of(v));
            if own_copy {
                // A parameter the body changes is the callee's own copy.
                let ty = self.ty_of(v);
                let var = self.b.declare_var(ty, Mode::Own);
                let o = self.owned(Val { v, own: false });
                self.b.def_var(var, o);
                self.locals.insert(b.uid, Local { var, ty });
                self.scopes.last_mut().expect("scope").push(b.uid);
            } else {
                self.bind_borrowed(b, v);
            }
        }
        self.counts_depth = true;
        self.b
            .emit(Op::DepthEnter, &[], ms_mir::ir::Imm::None, None);
        if let Some(f) = &c.fixture {
            self.begin_fixture(c, f)?;
        }
        match c.body() {
            ms_check::hir::Body::Block(stmts) => {
                if let Some(first) = stmts.first() {
                    self.at(first.pos);
                }
                self.stmts(stmts)?;
                if !self.dead {
                    // Falling off the end returns Unit.
                    let u = self.b.unit();
                    let ret = self.ret_ty;
                    if c.kind == CallableKind::Test {
                        // A test that finishes passes.
                        let TyKind::Alt(a) = self.b.m.types.kind(ret).clone() else {
                            return Err(Error::new("a test must return a Result"));
                        };
                        let ok = self.b.m.alts[a.index()]
                            .cases
                            .iter()
                            .position(|k| k.name == "ok")
                            .ok_or_else(|| Error::new("a test must return a Result"))?;
                        let v = self.b.alt_new(a, ok as u32, &[u]);
                        self.emit_return(Some(Val { v, own: true }));
                        return Ok(());
                    }
                    if ret != MTy::UNIT {
                        return Err(Error::new(format!(
                            "function {} can fall off its end",
                            c.name
                        )));
                    }
                    self.emit_return(Some(Val { v: u, own: false }));
                }
            }
            ms_check::hir::Body::Expr(e) => {
                let x = self.expr(e)?;
                self.emit_return(Some(x));
            }
        }
        Ok(())
    }
}
