//! Function instances and the per-function lowering state.

use crate::cx::{Cx, Job, JobKind};
use crate::{Error, Options};
use ms_check::Program;
use ms_check::hir::{Callable, CallableKind, ModuleHir};
use ms_check::types::{self as ct, BindingRef, Subst};
use ms_mir::builder::{FuncBuilder, Var};
use ms_mir::ir::{Block, FuncId, Linkage, Loc, Mode, Module, Op, Param, Value};
use ms_mir::types::Ty as MTy;
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
        let ret = self.lower_ty(m, &result)?;
        let name = if c.name.as_str().is_empty() {
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

fn lower_job(cx: &mut Cx, m: &mut Module, job: Job) -> Result<(), Error> {
    let (c, jsubst) = match &job.kind {
        JobKind::Source { callable, subst } => (callable.clone(), subst.clone()),
        JobKind::Format(t) => return crate::text::build_format(cx, m, job.func, *t),
    };
    let hir = cx.module(c.module.file)?;
    let file = m.add_file(c.module.file.as_str());
    let proto = m.funcs[job.func.index()].clone();
    let b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    let mut fl = FnLower {
        cx,
        b,
        hir,
        subst: jsubst,
        file,
        locals: HashMap::new(),
        scopes: vec![Vec::new()],
        temps: Vec::new(),
        loops: Vec::new(),
        dead: false,
        ret_ty: proto.ret,
    };
    let result = fl.lower_callable(&c);
    let mut func = fl.b.into_func();
    result?;
    func.compact_blocks();
    m.funcs[job.func.index()] = func;
    Ok(())
}

impl<'a> FnLower<'a> {
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
        let v = value.map(|x| self.owned(x));
        let mark = 0;
        self.flush_temps(mark);
        self.unwind_to(0);
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
        for (b, v) in bindings.iter().zip(params) {
            self.bind_borrowed(b, v);
        }
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
                    let ret = self.ret_ty;
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
