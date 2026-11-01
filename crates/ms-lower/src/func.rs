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
use std::collections::{HashMap, HashSet};
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
    /// The address of the variable's storage when a closure changes it through a reference.
    pub slot: Option<Value>,
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
    /// Temporaries pending at loop entry; those above belong to statements around a `break`.
    pub temps: usize,
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
    /// Logical source frame for defaults evaluated in their caller.
    pub source_scope: u32,
    pub locals: HashMap<usize, Local>,
    /// Locals needing a drop, per lexical scope.
    pub scopes: Vec<Vec<usize>>,
    /// Bindings closed at scope end and how each is closed when its scope is left.
    pub closers: HashMap<usize, crate::close::Closer>,
    /// Loops that own their elements: how an element closes, the list and the loop index, by
    /// the scope entry that closes the unreached ones when the loop is left.
    pub rest_closers: HashMap<
        usize,
        (
            crate::close::CloseKind,
            ms_mir::builder::Var,
            ms_mir::builder::Var,
        ),
    >,
    /// Hidden owned scrutinees whose payload closes when the scope is left, by hidden uid.
    pub hidden_closers: HashMap<usize, crate::close::CloseKind>,
    /// Owned temporaries borrowed by the current statement.
    pub temps: Vec<Value>,
    pub loops: Vec<LoopCtx>,
    /// The current position is unreachable.
    pub dead: bool,
    pub ret_ty: MTy,
    /// The body is bracketed by `depth.enter` / `depth.leave` (the optimizer removes it for non-recursive functions).
    pub counts_depth: bool,
    /// The value `return` is carrying while the scopes unwind, which a close error replaces.
    pub pending_return: Option<Value>,
    /// `return` already ran its var-slot, temporary and fixture handling on this path.
    pub prologue_done: bool,
    /// Bindings whose close already ran on the path that is returning a close error.
    pub closed_on_path: HashSet<usize>,
    /// A close error is being returned, so a further close failure is dropped.
    pub returning_close_error: bool,
    /// Bindings of the scope being left whose close and drop already ran.
    pub scope_done: Vec<usize>,
    /// Record to build on return and the binding uids of the `var` parameters it carries.
    pub var_slots: Vec<VarSlot>,
    /// The expression statement being lowered, whose value nothing reads (by address).
    pub discard: Option<usize>,
    /// The start of the statement being lowered.
    pub stmt_pos: Option<Pos>,
    /// The fixture hooks a test runs after its body, on every exit.
    pub fixture: Option<crate::fixture::Hooks>,
    /// The `err` slot of the runtime call whose `Failed` text the next status error reads.
    pub err_slot: Option<Value>,
    /// The `for` iterable whose `String.split` call may become a piece iterator (see `for_stmt`).
    pub split_iter_for: Option<*const ms_syntax::ast::Expr>,
    /// The `for` iterable whose `String.chars` call becomes a byte scan (see `chars_loop`).
    pub chars_iter_for: Option<*const ms_syntax::ast::Expr>,
    /// The expression whose `Shared` handle is being lowered before it stands for its payload.
    pub handle_of: Option<*const ms_syntax::ast::Expr>,
    /// The `Shared` handles a call in progress holds, by `shared_key`: their payload changes
    /// without another check of the hold.
    pub held: Vec<String>,
    /// The expression being lowered before its conversion to an interface: its own type, not the
    /// interface the checker recorded for it, is the type of its value.
    pub converting: Option<*const ms_syntax::ast::Expr>,
    /// The scanned `for` iterable came from `String.scalar_values`: it yields scalar values.
    pub scalars_scan: bool,
    /// Exclusive borrows in scope: the place each names.
    pub aliases: HashMap<usize, crate::alias::Alias>,
    /// Locals a closure of this body changes: they live in memory so the closure shares them.
    pub slotted: HashSet<usize>,
    /// Immutable bindings whose local is stored to again (a closing binding is replaced by what its
    /// close leaves behind), so they cannot be single-definition builder variables.
    pub redefined: HashSet<usize>,
    /// Values that are views into another string: no drop, and an immutable `let` may hold one.
    pub views: HashSet<Value>,
    /// Parameters the body only reads: the caller keeps them alive and unchanged for the whole
    /// call, so anything read out of them may be held without a copy.
    pub borrowed_params: HashSet<usize>,
    /// Values read in place out of a borrowed parameter (`p.m.get(k).get()`): an immutable `let`
    /// may hold one without a copy.
    pub stable_reads: HashSet<Value>,
    /// The iterable of the `for` being lowered when it may yield views of a map's keys.
    pub keys_view_for: Option<*const ms_syntax::ast::Expr>,
    /// The iterable of the `for` being lowered when it may walk a map or set in place: the
    /// `entries()`, `values()` or `keys()` call that would otherwise build a list.
    pub map_walk_for: Option<*const ms_syntax::ast::Expr>,
    /// Which part of each entry the in-place walk yields, set when `map_walk_for` was taken.
    pub map_walk: Option<crate::stmt::Walk>,
    /// The `split` call of a `let` whose list the rest of the block only reads in place.
    pub split_view_for: Option<*const ms_syntax::ast::Expr>,
    /// The module whose local implementations the expression being lowered uses, when it
    /// is the evidence of an enclosing generic instance's caller rather than this module.
    pub scope_override: Option<ct::Name>,
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

/// The substitution entry marking an instance that takes its consumed parameters owned.
pub(crate) const OWNED: &str = "$own";

/// The substitution entry marking an instance whose `var` parameters work in the caller's memory:
/// every change is in place at once, so a call cancelled while it waits leaves the changes it made.
pub(crate) const IN_MEMORY: &str = "$mem";

impl Cx {
    /// The parameters a direct call hands over owned: those the body consumes (moves, stores or
    /// returns), for a function or method whose parameters all pass by value; a method's mask
    /// starts with its receiver. Every other callable, and every call through a function value or
    /// interface, uses the borrowed signature.
    pub(crate) fn owned_mask(&self, c: &Callable) -> Option<Vec<bool>> {
        if !matches!(c.kind, CallableKind::Function | CallableKind::Method) {
            return None;
        }
        let f = c.func.func()?;
        if f.body.is_empty() {
            return None;
        }
        let key = (c.module.file, c.id());
        let mask = self.consumes.get(&key)?;
        (mask.len() == c.parameters.len() + c.self_binding.iter().count()).then(|| mask.clone())
    }

    /// The instance of `c` that takes the parameters `owned_mask` names owned.
    pub(crate) fn function_owned(
        &mut self,
        m: &mut Module,
        c: &Rc<Callable>,
        subst: &Subst,
        scope: ct::Name,
    ) -> Result<FuncId, Error> {
        let mut owned = subst.clone();
        owned.insert(ct::n(OWNED), ct::primitive("owned"));
        self.function_in(m, c, &owned, scope)
    }

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
        let owned_mask = subst
            .contains_key(&ct::n(OWNED))
            .then(|| self.owned_mask(c))
            .flatten();
        for (i, b) in bindings.into_iter().enumerate() {
            let t = ct::sub(&b.ty, subst);
            let ty = self.lower_ty(m, &t)?;
            // A changed parameter travels as the address of a slot the callee takes the value
            // from and puts the final value back into.
            let ty = if vars.contains(&i) { MTy::PTR } else { ty };
            let owned = owned_mask.as_ref().is_some_and(|mask| mask[i]);
            params.push(Param {
                ty,
                mode: if owned { Mode::Own } else { Mode::Borrow },
            });
        }
        let result = ct::sub(&self.callable_result(c)?, subst);
        let ret = self.lower_ty(m, &result)?;
        let name = if let ms_syntax::ast::DeclKind::Test(t) = &c.func.decl.decl().kind {
            format!("{} {}", if t.bench { "bench" } else { "test" }, t.name)
        } else if c.name.as_str().is_empty() {
            "test".to_string()
        } else if let ms_syntax::ast::DeclKind::Impl(i) = &c.func.decl.decl().kind {
            // Fault traces name a method after its receiver type.
            format!("{}.{}", i.receiver.name(), c.name)
        } else {
            c.name.to_string()
        };
        let mut f = ms_mir::ir::Func::new(&name, params, ret);
        // The checker keeps a `var` argument from overlapping any other argument.
        f.noalias = vars.iter().map(|&i| i as u32).collect();
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

/// Lowers the tests of every project module (not the bundled standard library) with a runner
/// as the entry; returns each test's `module::name` identity.
pub(crate) fn lower_tests(
    program: &Program,
    _options: &Options,
    bench: bool,
) -> Result<(Module, Vec<String>), Error> {
    let mut cx = Cx::new(program);
    let mut m = Module::new("main");
    let mut tests: Vec<(ct::Name, Rc<Callable>)> = Vec::new();
    for module in &program.modules {
        let file = module.file;
        if file.as_str().starts_with("@std/") {
            continue;
        }
        for c in cx.module(file)?.callables() {
            if c.kind == CallableKind::Test && is_bench(&c) == bench {
                tests.push((file, cx.callables[&(file, c.id())].clone()));
            }
        }
    }
    let mut ids = Vec::new();
    let mut names = Vec::new();
    for (file, c) in &tests {
        if let ms_syntax::ast::DeclKind::Test(t) = &c.func.decl.decl().kind {
            names.push(format!("{file}::{}", t.name));
        }
        ids.push(cx.function_for(&mut m, c, &Subst::new())?);
    }
    if bench && !tests.is_empty() {
        // Each bench runs under the standard driver, which repeats and times its body.
        let driver = cx
            .callables
            .values()
            .find(|c| {
                c.module.file.as_str() == "@std/test/bench.ms"
                    && c.name.as_str() == "run_bench_block"
            })
            .cloned()
            .ok_or_else(|| Error::new("the bench driver @std/test/bench.ms is not loaded"))?;
        let driver = cx.function_for(&mut m, &driver, &Subst::new())?;
        let per: Vec<i64> = tests
            .iter()
            .map(|(_, c)| match &c.func.decl.decl().kind {
                ms_syntax::ast::DeclKind::Test(t) => t.per,
                _ => 1,
            })
            .collect();
        ids = crate::runner::bench_entries(&mut m, &ids, &per, driver);
    }
    drain(&mut cx, &mut m)?;
    m.entry = Some(crate::runner::build_runner(&mut m, &ids)?);
    Ok((m, names))
}

/// Whether a test callable is a `bench` block.
fn is_bench(c: &Callable) -> bool {
    matches!(&c.func.decl.decl().kind, ms_syntax::ast::DeclKind::Test(t) if t.bench)
}

/// Lowers queued jobs until none remain. The text of an interface value tests every table of
/// the interface, so it waits until no other job can still add one.
fn drain(cx: &mut Cx, m: &mut Module) -> Result<(), Error> {
    let deferred = |m: &Module, j: &Job| {
        matches!(&j.kind, JobKind::Category(_))
            || matches!(&j.kind, JobKind::Format(t, _) if matches!(m.types.kind(*t), ms_mir::types::TyKind::Iface(_)))
    };
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
        JobKind::Equal(t, scope) => return crate::eq::build_eq(cx, m, job.func, *t, *scope),
        JobKind::HandleMethod(j) => {
            return crate::natiface::build_method(cx, m, job.func, j);
        }
        JobKind::Codec(j) => {
            return crate::codecstream::build_codec_method(cx, m, job.func, j);
        }
        JobKind::Lambda(l) => return crate::closure::build_lambda(cx, m, job.func, l),
        JobKind::BoundNative(n) => return crate::closure::build_bound_native(cx, m, job.func, n),
        JobKind::BoundAlias(n) => return crate::bound_alias::build_bound_alias(cx, m, job.func, n),
        JobKind::DefaultThunk(n) => return crate::closure::build_default_thunk(cx, m, job.func, n),
        JobKind::NativeThunk(n) => return crate::closure::build_native_thunk(cx, m, job.func, n),
        JobKind::Json(j) => return crate::json::build_json(cx, m, job.func, j),
        JobKind::FnAdapt(j) => return crate::closure::build_fn_adapter(cx, m, job.func, j),
        JobKind::IfaceThunk(j) => return crate::closure::build_iface_thunk(cx, m, job.func, j),
        JobKind::Category(t) => return crate::category::build_category(cx, m, job.func, *t),
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
    func.noalias = proto.noalias;
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
            rest_closers: HashMap::new(),
            hidden_closers: HashMap::new(),
            temps: Vec::new(),
            loops: Vec::new(),
            dead: false,
            ret_ty,
            counts_depth: false,
            pending_return: None,
            prologue_done: false,
            closed_on_path: HashSet::new(),
            returning_close_error: false,
            scope_done: Vec::new(),
            var_slots: Vec::new(),
            slotted: HashSet::new(),
            redefined: HashSet::new(),
            views: HashSet::new(),
            borrowed_params: HashSet::new(),
            stable_reads: HashSet::new(),
            keys_view_for: None,
            map_walk_for: None,
            map_walk: None,
            split_view_for: None,
            discard: None,
            stmt_pos: None,
            source_scope: 0,
            fixture: None,
            err_slot: None,
            split_iter_for: None,
            chars_iter_for: None,
            converting: None,
            handle_of: None,
            held: Vec::new(),
            scalars_scan: false,
            aliases: HashMap::new(),
            scope_override: None,
        }
    }

    /// The source position as a MIR location.
    pub fn loc(&self, pos: Pos) -> Loc {
        Loc {
            scope: self.source_scope,
            ..Loc::new(self.file, pos.line, pos.column)
        }
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

    /// Whether values of `t` are resources, which must be closed whatever their storage.
    pub fn is_resource(&self, t: MTy) -> bool {
        self.cx
            .source_tys
            .get(&t)
            .is_some_and(|ty| self.cx.classes.class(ty) == ms_check::ownership::Class::Resource)
    }

    /// Whether an owned value of `t` carries a duty: storage to free or a resource to close.
    /// Ownership is tracked for both; a resource with no storage still has to be closed.
    pub fn holds(&self, t: MTy) -> bool {
        self.needs_drop(t) || self.is_resource(t)
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
        let t = self.ty_of(x.v);
        if x.own && self.holds(t) {
            self.temps.push(x.v);
        }
        x.v
    }

    /// Stops treating `v` as a pending temporary once it is consumed.
    pub fn unhold_temp(&mut self, v: Value) {
        if let Some(at) = self.temps.iter().rposition(|t| *t == v) {
            self.temps.remove(at);
        }
    }

    /// Drops the owned temporaries registered after `mark`.
    pub fn flush_temps(&mut self, mark: usize) {
        while self.temps.len() > mark {
            let v = self.temps.pop().expect("temp");
            if !self.dead {
                self.close_temp(v);
                self.drop_value(v);
            }
        }
    }

    /// Drops the pending temporaries from index `from` on, keeping them for the paths that
    /// stay in the statement: a loop exit leaves the enclosing statements' temporaries behind.
    pub fn drop_temps_from(&mut self, from: usize) {
        if self.dead {
            return;
        }
        for i in (from..self.temps.len()).rev() {
            let v = self.temps[i];
            self.close_temp(v);
            self.drop_value(v);
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
            own: own && self.holds(self.ty_of(v)),
        }
    }

    // -------------------------------------------------------------- locals

    /// Whether the ownership checker vetted this function, so a lexical borrow cannot outlive a
    /// change to its source. Standard-library modules not yet vetted are exempt.
    pub fn ownership_checked(&self) -> bool {
        ms_check::ownership::is_vetted(self.hir.data.file)
    }

    /// Declares `binding` as a borrow of `v`: no copy, and nothing to drop at scope exit.
    pub fn bind_lent(&mut self, binding: &BindingRef, v: Value) {
        let ty = self.ty_of(v);
        let var = if binding.mutable || self.redefined.contains(&binding.uid) {
            self.b.declare_var(ty, Mode::Borrow)
        } else {
            self.b.declare_single(ty, Mode::Borrow)
        };
        self.b.def_var(var, v);
        self.locals.insert(
            binding.uid,
            Local {
                var,
                ty,
                slot: None,
            },
        );
    }

    /// Declares the local of `binding` holding `value`.
    pub fn bind_local(&mut self, binding: &BindingRef, x: Val) {
        let ty = self.ty_of(x.v);
        // An immutable `let` of a string read from a list element or record field is a lexical
        // borrow (the checker rejects changing the container while it lives): no copy, no drop.
        // Standard-library source is not ownership checked, so it always copies.
        let lent = ty == MTy::STR
            && self.ownership_checked()
            && !x.own
            && self.cx.shared(binding.uid)
            && !self.slotted.contains(&binding.uid)
            && self.temps.is_empty()
            && (self.views.contains(&x.v)
                || matches!(
                    self.b.defining_op(x.v),
                    Some(Op::ListGet | Op::ListGetNn | Op::ListGetU | Op::RecGet)
                ));
        // A pattern variable the checker proved a read-only borrow of its scrutinee stays where it
        // is: a lending function can hand it back, and a reader skips the copy.
        let lent = lent
            || (self.cx.shared(binding.uid)
                && self.ownership_checked()
                && !x.own
                && !binding.mutable
                && !self.slotted.contains(&binding.uid)
                && self.temps.is_empty()
                && self.needs_drop(ty)
                && matches!(
                    self.b.defining_op(x.v),
                    Some(
                        Op::AltGet
                            | Op::OptGet
                            | Op::RecGet
                            | Op::ListGet
                            | Op::ListGetNn
                            | Op::ListGetU
                    )
                )
                // Its parent must outlive the binding: an owned scrutinee is dropped as soon as
                // its payload has been copied out.
                && self
                    .b
                    .defining_operand(x.v)
                    .is_some_and(|parent| self.b.is_borrowed(parent)));
        if lent {
            self.bind_lent(binding, x.v);
            return;
        }
        let owned = self.needs_drop(ty);
        let mode = if owned { Mode::Own } else { Mode::Borrow };
        let var = if binding.mutable || self.redefined.contains(&binding.uid) {
            self.b.declare_var(ty, mode)
        } else {
            self.b.declare_single(ty, mode)
        };
        let v = self.owned(x);
        self.b.def_var(var, v);
        self.locals.insert(
            binding.uid,
            Local {
                var,
                ty,
                slot: None,
            },
        );
        self.slotify(binding.uid);
        if owned {
            self.scopes.last_mut().expect("scope").push(binding.uid);
        }
    }

    /// Moves the local `uid` into memory when a closure changes it, so the closure shares it.
    pub fn slotify(&mut self, uid: usize) {
        if !self.slotted.contains(&uid) {
            return;
        }
        let Some(l) = self.locals.get(&uid).copied() else {
            return;
        };
        if l.slot.is_some() {
            return;
        }
        let v = self.b.use_var(l.var);
        let ptr = self
            .b
            .emit(Op::Slot, &[], ms_mir::ir::Imm::Ty(l.ty), Some(MTy::PTR))
            .expect("slot");
        self.move_into(ptr, v);
        self.locals.insert(
            uid,
            Local {
                slot: Some(ptr),
                ..l
            },
        );
    }

    /// Whether this instance's `var` parameters work in the caller's memory (`IN_MEMORY`).
    pub(crate) fn in_memory(&self) -> bool {
        self.subst.contains_key(&ct::n(IN_MEMORY))
    }

    /// The current value of a local, as a borrow.
    pub fn local_get(&mut self, l: &Local) -> Value {
        match l.slot {
            Some(p) => self
                .b
                .emit(Op::Load, &[p], ms_mir::ir::Imm::Ty(l.ty), Some(l.ty))
                .expect("load"),
            None => self.b.use_var(l.var),
        }
    }

    /// Moves the value out of a local, which must be stored to again.
    pub fn local_take(&mut self, l: &Local) -> Value {
        match l.slot {
            Some(p) => self.move_out(p, l.ty),
            None => self.b.use_var(l.var),
        }
    }

    /// Stores an owned value into a local; the old value is not dropped.
    pub fn local_put(&mut self, l: &Local, v: Value) {
        match l.slot {
            Some(p) => self.move_into(p, v),
            None => self.b.def_var(l.var, v),
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
    pub fn adopt_hidden(&mut self, var: ms_mir::builder::Var, ty: MTy) -> usize {
        let uid = usize::MAX - self.locals.len();
        self.locals.insert(
            uid,
            Local {
                var,
                ty,
                slot: None,
            },
        );
        if self.needs_drop(ty) {
            self.scopes.last_mut().expect("scope").push(uid);
        }
        uid
    }

    /// Declares a borrowed local (a parameter or a borrowing binding): no drop at scope end.
    pub fn bind_borrowed(&mut self, binding: &BindingRef, v: Value) {
        let ty = self.ty_of(v);
        let var = self.b.declare_var(ty, Mode::Borrow);
        self.b.def_var(var, v);
        self.locals.insert(
            binding.uid,
            Local {
                var,
                ty,
                slot: None,
            },
        );
    }

    pub fn local(&mut self, binding: &BindingRef) -> Result<Local, Error> {
        self.locals
            .get(&binding.uid)
            .copied()
            .ok_or_else(|| Error::new(format!("unbound variable {}", binding.name)))
    }

    /// The current value of a local as a borrow.
    pub fn read_local(&mut self, binding: &BindingRef) -> Result<Val, Error> {
        if let Some(a) = self.aliases.get(&binding.uid).cloned() {
            return self.alias_read(&a);
        }
        let l = self.local(binding)?;
        let v = self.local_get(&l);
        Ok(Val { v, own: false })
    }

    // --------------------------------------------------------------- scopes

    pub fn push_scope(&mut self) {
        self.scopes.push(Vec::new());
    }

    fn drop_scope_locals(&mut self, depth: usize) {
        let outer_done = std::mem::take(&mut self.scope_done);
        for i in (depth..self.scopes.len()).rev() {
            let uids = self.scopes[i].clone();
            for uid in uids.iter().rev() {
                if self.closed_on_path.contains(uid) {
                    continue;
                }
                if let Some((kind, list, idx)) = self.rest_closers.get(uid).cloned() {
                    self.close_rest(&kind, list, idx);
                    continue;
                }
                if let Some(closer) = self.closers.get(uid).cloned() {
                    self.close_at_scope_end(*uid, &closer);
                }
                let l = self.locals[uid];
                if let Some(kind) = self.hidden_closers.get(uid).cloned() {
                    let v = self.local_get(&l);
                    self.close_discarded_kind(&kind, v);
                }
                if self.closers.get(uid).is_some_and(|c| c.split.is_some()) {
                    self.release_split(*uid);
                } else if self.needs_drop(l.ty) {
                    let v = self.local_take(&l);
                    self.b.emit(Op::Drop, &[v], ms_mir::ir::Imm::None, None);
                }
                self.scope_done.push(*uid);
            }
        }
        self.scope_done = outer_done;
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
        // A close error returned from inside this unwinding re-enters here with the prologue done.
        let nested = self.prologue_done;
        if !nested {
            for slot in self.var_slots.clone() {
                let l = self.locals[&slot.uid];
                if l.slot == Some(slot.ptr) {
                    continue;
                }
                let x = self.local_take(&l);
                self.move_into(slot.ptr, x);
            }
            // The temporaries stay registered: a conditional return leaves the others running.
            for t in self.temps.clone().into_iter().rev() {
                self.close_temp(t);
                self.drop_value(t);
            }
            self.end_fixture();
        }
        let outer_pending =
            std::mem::replace(&mut self.pending_return, if nested { None } else { v });
        self.prologue_done = true;
        self.unwind_to(0);
        self.prologue_done = nested;
        self.pending_return = outer_pending;
        if self.counts_depth {
            self.b
                .emit(Op::DepthLeave, &[], ms_mir::ir::Imm::None, None);
        }
        self.b.ret(v);
        self.terminated();
    }

    // --------------------------------------------------------------- bodies

    fn lower_callable(&mut self, c: &Rc<Callable>) -> Result<(), Error> {
        // Inline/default frames must return to this declaration's file, even
        // when every surviving instruction originates in another module.
        self.b.func_mut().loc = self.loc(c.func.decl.decl().pos);
        let params = self.b.params();
        let bindings: Vec<BindingRef> = c
            .self_binding
            .iter()
            .chain(c.parameters.iter())
            .cloned()
            .collect();
        let vars = self.cx.var_positions(c);
        let owned_mask = self
            .subst
            .contains_key(&ct::n(OWNED))
            .then(|| self.cx.owned_mask(c))
            .flatten();
        if let ms_check::hir::Body::Block(stmts) = c.body() {
            self.slotted = crate::closure::slotted_in(self, stmts);
        }
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
            if vars.contains(&i) && self.in_memory() {
                // The value stays in the caller's slot; the body changes it there.
                let ty = self.mty(&b.ty)?;
                let var = self.b.declare_var(ty, Mode::Borrow);
                self.locals.insert(
                    b.uid,
                    Local {
                        var,
                        ty,
                        slot: Some(v),
                    },
                );
                self.var_slots.push(VarSlot { uid: b.uid, ptr: v });
                continue;
            }
            if vars.contains(&i) {
                // The callee owns the value it takes from the slot and puts back on return.
                let ty = self.mty(&b.ty)?;
                let owned = self.needs_drop(ty);
                let var = self
                    .b
                    .declare_var(ty, if owned { Mode::Own } else { Mode::Borrow });
                let x = self.move_out(v, ty);
                self.b.def_var(var, x);
                self.locals.insert(
                    b.uid,
                    Local {
                        var,
                        ty,
                        slot: None,
                    },
                );
                self.slotify(b.uid);
                self.var_slots.push(VarSlot { uid: b.uid, ptr: v });
                continue;
            }
            if owned_mask.as_ref().is_some_and(|mask| mask[i]) && self.needs_drop(self.ty_of(v)) {
                // The caller handed the value over: the callee owns it and drops it at scope end.
                if self.cx.implicit_closes.contains(&b.uid) {
                    // A resource the callee keeps on some path closes on the others.
                    let cleanup = self.hir.binding_cleanup(b.uid);
                    if let Some(kind) = self.closer_opt(cleanup.as_ref(), &b.ty)? {
                        self.bind_closing_kind(b, Val { v, own: true }, kind)?;
                        continue;
                    }
                }
                let ty = self.ty_of(v);
                let var = self.b.declare_var(ty, Mode::Own);
                self.b.def_var(var, v);
                self.locals.insert(
                    b.uid,
                    Local {
                        var,
                        ty,
                        slot: None,
                    },
                );
                self.slotify(b.uid);
                self.scopes.last_mut().expect("scope").push(b.uid);
                continue;
            }
            let own_copy = mutated.contains(&b.uid) && self.needs_drop(self.ty_of(v));
            if own_copy {
                // A parameter the body changes is the callee's own copy.
                let ty = self.ty_of(v);
                let var = self.b.declare_var(ty, Mode::Own);
                let o = self.owned(Val { v, own: false });
                self.b.def_var(var, o);
                self.locals.insert(
                    b.uid,
                    Local {
                        var,
                        ty,
                        slot: None,
                    },
                );
                self.slotify(b.uid);
                self.scopes.last_mut().expect("scope").push(b.uid);
            } else {
                self.bind_borrowed(b, v);
                if !self.slotted.contains(&b.uid) {
                    self.borrowed_params.insert(b.uid);
                }
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
