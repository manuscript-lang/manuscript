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
    /// Owned temporaries borrowed by the current statement.
    pub temps: Vec<Value>,
    pub loops: Vec<LoopCtx>,
    /// The current position is unreachable.
    pub dead: bool,
    pub ret_ty: MTy,
    /// The body is bracketed by `depth.enter` / `depth.leave` (the optimizer removes it for non-recursive functions).
    pub counts_depth: bool,
    /// Record to build on return and the binding uids of the `var` parameters it carries.
    pub var_ret: Option<(ms_mir::types::RecId, Vec<usize>)>,
    /// The expression statement being lowered, whose value nothing reads (by address).
    pub discard: Option<usize>,
}

impl Cx {
    /// Positions (receiver first) of the `var` parameters a callable may change.
    pub(crate) fn var_positions(&self, c: &Callable) -> Vec<usize> {
        let mut out = Vec::new();
        let mut base = 0;
        if c.self_binding.is_some() {
            if self.mutating.contains(&(c.module.file, c.id())) {
                out.push(0);
            }
            base = 1;
        }
        if let Some(func) = c.func.func() {
            for (i, p) in func.params.iter().enumerate() {
                if p.mutable {
                    out.push(base + i);
                }
            }
        }
        out
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
        for b in bindings {
            let t = ct::sub(&b.ty, subst);
            let ty = self.lower_ty(m, &t)?;
            params.push(Param {
                ty,
                mode: Mode::Borrow,
            });
        }
        let result = ct::sub(&self.callable_result(c)?, subst);
        let mut ret = self.lower_ty(m, &result)?;
        let vars = self.var_positions(c);
        if !vars.is_empty() {
            let mut fields = vec![("result".to_string(), ret)];
            for (n, p) in vars.iter().enumerate() {
                fields.push((format!("var{n}"), params[*p].ty));
            }
            ret = m.add_record(&format!("{}.vars", c.name), fields).1;
        }
        let name = if let ms_syntax::ast::DeclKind::Test(t) = &c.func.decl.decl().kind {
            format!("test {}", t.name)
        } else if c.name.as_str().is_empty() {
            "test".to_string()
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
    while let Some(job) = cx.queue.pop() {
        lower_job(&mut cx, &mut m, job)?;
    }
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
    while let Some(job) = cx.queue.pop() {
        lower_job(&mut cx, &mut m, job)?;
    }
    m.entry = Some(crate::runner::build_runner(&mut m, &ids)?);
    Ok((m, names))
}

fn lower_job(cx: &mut Cx, m: &mut Module, job: Job) -> Result<(), Error> {
    let (c, jsubst) = match &job.kind {
        JobKind::Source { callable, subst } => (callable.clone(), subst.clone()),
        JobKind::Format(t, repr) => {
            return crate::text::build_format(cx, m, job.func, *t, *repr);
        }
        JobKind::Equal(t) => return crate::eq::build_eq(cx, m, job.func, *t),
        JobKind::Lambda(l) => return crate::closure::build_lambda(cx, m, job.func, l),
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
            temps: Vec::new(),
            loops: Vec::new(),
            dead: false,
            ret_ty,
            counts_depth: false,
            var_ret: None,
            discard: None,
        }
    }

    /// The source position as a MIR location.
    pub fn loc(&self, pos: Pos) -> Loc {
        Loc::new(self.file, pos.line, pos.column)
    }

    /// Sets the location of subsequent instructions.
    pub fn at(&mut self, pos: Pos) {
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
        let uid = usize::MAX - self.locals.len();
        self.locals.insert(uid, Local { var, ty });
        if owned {
            self.scopes.last_mut().expect("scope").push(uid);
        }
        var
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
                let l = self.locals[uid];
                let v = self.b.use_var(l.var);
                self.b.emit(Op::Drop, &[v], ms_mir::ir::Imm::None, None);
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
        let mut v = value.map(|x| self.owned(x));
        if let (Some((rid, uids)), Some(r)) = (self.var_ret.clone(), v) {
            let mut fields = vec![r];
            for u in uids {
                let var = self.locals[&u].var;
                fields.push(self.b.use_var(var));
            }
            v = Some(self.b.rec_new(rid, &fields));
        }
        // The temporaries stay registered: a conditional return leaves the others running.
        for t in self.temps.clone().into_iter().rev() {
            self.b.emit(Op::Drop, &[t], ms_mir::ir::Imm::None, None);
        }
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
        let mut var_uids = Vec::new();
        // Parameters the body changes are the callee's own copies.
        let mutated = match c.body() {
            ms_check::hir::Body::Block(stmts) => {
                crate::closure::mutated_captures(&self.hir, stmts, &self.cx.mutating)
            }
            ms_check::hir::Body::Expr(_) => Default::default(),
        };
        for (i, (b, v)) in bindings.iter().zip(params).enumerate() {
            let own_copy =
                vars.contains(&i) || (mutated.contains(&b.uid) && self.needs_drop(self.ty_of(v)));
            if own_copy {
                // A `var` parameter is a local the callee owns and hands back on return.
                let ty = self.ty_of(v);
                let owned = self.needs_drop(ty);
                let var = self
                    .b
                    .declare_var(ty, if owned { Mode::Own } else { Mode::Borrow });
                let o = self.owned(Val { v, own: false });
                self.b.def_var(var, o);
                self.locals.insert(b.uid, Local { var, ty });
                if vars.contains(&i) {
                    var_uids.push(b.uid);
                } else if owned {
                    self.scopes.last_mut().expect("scope").push(b.uid);
                }
            } else {
                self.bind_borrowed(b, v);
            }
        }
        if !var_uids.is_empty() {
            let TyKind::Rec(rid) = self.b.m.types.kind(self.ret_ty).clone() else {
                return Err(Error::new("var parameters without a result record"));
            };
            self.var_ret = Some((rid, var_uids));
        }
        self.counts_depth = true;
        self.b
            .emit(Op::DepthEnter, &[], ms_mir::ir::Imm::None, None);
        if let Some(f) = &c.fixture {
            return Err(Error::new(format!(
                "fixtures are not supported ({})",
                f.name
            )));
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
                    let ret = match &self.var_ret {
                        Some((rid, _)) => self.b.m.records[rid.index()].fields[0].1,
                        None => self.ret_ty,
                    };
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
