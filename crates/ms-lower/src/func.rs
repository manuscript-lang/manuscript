//! Function instances and the per-function lowering state.

use crate::cx::{Cx, InstKey, Job, JobKind, Variant};
use crate::{Error, Options};
use ms_check::Program;
use ms_check::api::Pos;
use ms_check::api::hir::{Callable, CallableKind, ModuleHir};
use ms_check::api::types::{self as ct, BindingRef, Subst};
use ms_check::fxmap::{HashMap, HashSet};
use ms_mir::builder::{FuncBuilder, Var};
use ms_mir::ir::{Block, FuncId, Linkage, Loc, Mode, Module, Op, Param, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use std::rc::Rc;

/// An evaluated operand: the SSA value and whether it is an owned temporary.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Val {
    pub v: Value,
    /// The value carries a reference the holder must consume.
    pub own: bool,
}

/// The marker state of one lexical scope (`proposals/elaborate-drops.md`).
/// A closing binding in memory whose scope end the elaborate pass closes.
#[derive(Clone)]
pub(crate) struct RawSlot {
    pub slot: Value,
    pub kind: crate::close::CloseKind,
}

#[derive(Clone, Copy)]
pub(crate) struct ScopeMark {
    id: u32,
    /// The enclosing scope's number plus one, 0 for the function's outermost scope.
    parent: u32,
    /// `scope.begin` was emitted.
    begun: bool,
}

impl ScopeMark {
    fn new(id: u32, parent: Option<u32>) -> ScopeMark {
        ScopeMark {
            id,
            parent: parent.map_or(0, |p| p + 1),
            begun: false,
        }
    }
}

/// A source variable bound to an SSA variable.
#[derive(Clone, Copy)]
pub(crate) struct Local {
    pub var: Var,
    /// The type of the value the local holds.
    pub ty: MTy,
    /// The address of the variable's storage when a closure changes it through a reference.
    pub slot: Option<Value>,
    /// The variable holds `ty?`: a move leaves it `none`, and the scope end drops what it still
    /// holds. Present for an owned binding some path moves out of and another path keeps.
    pub opt: bool,
}

/// The default-argument frame of a call: the copies of earlier `var` arguments the default may
/// change, and the bindings of this function it shadows while the default runs (the callee's
/// parameters are this function's own when it calls itself).
pub(crate) struct DefaultFrame {
    pub copies: Vec<Var>,
    pub shadowed: Vec<(usize, Option<Local>)>,
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

/// Stable identity of a selected place index, including defaults from another module.
pub(crate) type PlaceKey = (ct::Name, ms_check::api::NodeId, Pos);

/// Per-function lowering state.
pub(crate) struct FnLower<'a> {
    pub syms: ms_check::api::Names,
    pub cx: &'a mut Cx,
    pub b: FuncBuilder<'a>,
    pub hir: Rc<ModuleHir>,
    pub subst: Subst,
    /// Ownership and evidence the instance being lowered was requested with.
    pub variant: Variant,
    pub file: u32,
    /// Logical source frame for defaults evaluated in their caller.
    pub source_scope: u32,
    pub locals: HashMap<usize, Local>,
    /// Locals needing a drop, per lexical scope.
    pub scopes: Vec<Vec<usize>>,
    /// Per scope (parallel to `scopes`): its marker number and whether a Raw owner (see
    /// [`Self::own_raw`]) joined it, so its exits emit `scope.end`.
    pub scope_marks: Vec<ScopeMark>,
    /// The next scope marker number.
    pub next_scope: u32,
    /// Raw owners are off while a binding is declared with a closer of its own.
    pub raw_owners: bool,
    /// Locals whose drop is left to `elaborate`.
    pub raw_owned: ms_check::fxmap::HashSet<usize>,
    /// Reassigned locals of a scope that nothing moves: no marker until a path leaves the scope,
    /// where the value the variable holds then is registered (see `drop_scope_locals`).
    pub raw_vars: HashMap<usize, ms_mir::builder::Var>,
    /// Reassigned locals every path moves, with the index of their scope: each value the
    /// variable gets is owned there (`local_put`) and disowned when it leaves (`local_take`).
    pub tracked_vars: HashMap<ms_mir::builder::Var, usize>,
    /// Resources in memory the elaborate pass closes: the slot address and how the value closes.
    /// A move of the value disowns the slot.
    pub raw_slots: HashMap<usize, RawSlot>,
    /// The address of each resource field a binding's paths move out, by binding and field path.
    pub split_places: HashMap<(usize, Vec<ct::Name>), Value>,
    /// Every owner of a binding with moved fields, which a move of the whole binding disowns.
    pub split_owners: HashMap<usize, Vec<Value>>,
    /// Whether an owned local some path moves out of still holds its value, by binding: the
    /// scope end drops it only where it does.
    pub held: HashMap<usize, ms_mir::builder::Var>,
    /// Owned locals every path moves out of before leaving their scope: the move moving_params
    /// them, and the scope end has nothing to drop.
    pub must_move: HashSet<usize>,
    /// Owned temporaries borrowed by the current statement.
    pub temps: Vec<Value>,
    /// The pending temporaries `elaborate` also owns (see `pend_temp`).
    pub pass_temps: ms_check::fxmap::HashMap<Value, u32>,
    /// The copies of earlier `var` arguments a default being evaluated may change, innermost last.
    pub default_frames: Vec<DefaultFrame>,
    /// Checked place indices retained through the final writeback.
    pub prepared_indices: HashMap<PlaceKey, Value>,
    /// Only receiver-chain indices are captured during a checked place read.
    pub capture_indices: HashSet<PlaceKey>,
    /// Intact resource temporaries: their slots own the values while later expressions run.
    /// The keys are borrowed views, consumed only by `take_resource_temp`.
    pub resource_temps: HashMap<Value, crate::close::ResourceTemp>,
    pub loops: Vec<LoopCtx>,
    /// The current position is unreachable.
    pub dead: bool,
    pub ret_ty: MTy,
    /// In a JSON decoder: the document, the node and the type name a failure reports.
    pub jnode: Option<(Value, Value, String)>,
    /// Why the next JSON decoder failure happens, as `(code, text)` (see `Doc::mismatch_text`).
    pub jwhy: Option<(i64, String)>,
    /// The body is bracketed by `depth.enter` / `depth.leave` (the optimizer removes it for non-recursive functions).
    pub counts_depth: bool,
    /// The value `return` is carrying while the scopes unwind, which a close error replaces.
    pub pending_return: Option<Val>,
    /// `return` already ran its var-slot, temporary and fixture handling on this path.
    pub prologue_done: bool,
    /// Bindings whose close already ran on the path that is returning a close error.
    pub closed_on_path: HashSet<usize>,
    /// While a mutator discards entries: set by a failed close, which faults after the mutation
    /// removed the entry, so the unwind does not close it a second time.
    pub deferred_close: Option<ms_mir::builder::Var>,
    /// Type to build on return and the binding uids of the `var` parameters it carries.
    pub var_slots: Vec<VarSlot>,
    /// Some binding of the function closes a resource when its scope ends.
    pub closing_fn: bool,
    /// The expression statement being lowered, whose value nothing reads (by address).
    pub discard: Option<usize>,
    /// The start of the statement being lowered.
    pub stmt_pos: Option<Pos>,
    /// The `err` slot of the runtime call whose `Failed` text the next status error reads.
    pub err_slot: Option<Value>,
    /// The `for` iterable whose `String.split` call may become a piece iterator (see `for_stmt`).
    pub split_iter_for: Option<*const ms_check::api::ast::Expr>,
    /// The `for` iterable whose `String.chars` call becomes a byte scan (see `chars_loop`).
    pub chars_iter_for: Option<*const ms_check::api::ast::Expr>,
    /// The expression being lowered before its conversion to an interface: its own type, not the
    /// interface the checker recorded for it, is the type of its value.
    pub converting: Option<*const ms_check::api::ast::Expr>,
    /// The scanned `for` iterable came from `String.scalar_values`: it yields scalar values.
    pub scalars_scan: bool,
    /// Locals some use needs as a `String` (see `scalar.rs`).
    pub string_needed: HashSet<usize>,
    /// Locals kept as the code point of the one-scalar `String` they stand for.
    pub scalar_locals: HashMap<usize, Value>,
    /// Lowering a function value's thunk: its arguments are borrowed by the language's call
    /// rule, so one a native consumes is copied, and that copy is declared (`owned_arg`).
    pub in_thunk: bool,
    /// This instance is the borrowed-signature adapter of a function that moves a parameter.
    pub adapter: bool,
    /// The scrutinee `hold` just evaluated is a declared read (see `boundary_reads`).
    pub hold_declared: bool,
    /// Values whose copy on storing is declared: the payload an `Optional`/`Result` read (`get()`,
    /// `err()`) borrows, which these types copy by rule, and a payload of a last-use scrutinee the
    /// checker moves out (`owned` does not report it).
    pub boundary_reads: ms_check::fxmap::HashSet<Value>,
    /// Exclusive borrows in scope: the place each names.
    pub aliases: HashMap<usize, crate::alias::Alias>,
    /// Locals a closure of this body changes: they live in memory so the closure shares them.
    pub slotted: HashSet<usize>,
    /// Set while a match arm binds the payload of a scrutinee that stays in its own local for the
    /// whole arm (no hidden temporary): the payload then outlives the binding.
    pub scrutinee_lives: bool,
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
    pub keys_view_for: Option<*const ms_check::api::ast::Expr>,
    /// The iterable of the `for` being lowered when it may walk a map or set in place: the
    /// `entries()`, `values()` or `keys()` call that would otherwise build a list.
    pub map_walk_for: Option<*const ms_check::api::ast::Expr>,
    /// Constant list literals built before the outermost loop that iterates them, by node.
    pub hoisted: HashMap<ms_check::api::NodeId, ms_mir::builder::Var>,
    /// Which part of each entry the in-place walk yields, set when `map_walk_for` was taken.
    pub map_walk: Option<crate::stmt::Walk>,
    /// The `split` call of a `let` whose list the rest of the block only reads in place.
    pub split_view_for: Option<*const ms_check::api::ast::Expr>,
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

/// The instance key of a callable under a substitution and variant. Entries are ordered by
/// variable name, which is unique within a substitution, so the key does not depend on the order
/// types were first interned.
fn instance_key(
    syms: ms_check::api::Names,
    tys: &mut ms_check::api::tytable::TyTable,
    c: &Callable,
    subst: &Subst,
    variant: Variant,
) -> InstKey {
    let mut vars: Vec<(ct::Name, _)> = subst.iter().map(|(k, v)| (*k, tys.intern(v))).collect();
    vars.sort_by(|a, b| syms.str(a.0).cmp(syms.str(b.0)));
    InstKey {
        file: c.module.file,
        node: c.id(),
        subst: vars,
        variant,
    }
}

impl Cx {
    /// The parameters a direct call hands over owned: those the body moving_params (moves, stores or
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
        let mask = self.ownership.moving_params.get(&key)?;
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
        self.function_in_as(m, c, subst, scope, true)
    }

    /// The checked result type of a callable (generic-open).
    pub(crate) fn callable_result(&self, c: &Callable) -> Result<ct::Ty, Error> {
        let hir = self.module(c.module.file)?;
        if let Some(f) = c.func.func() {
            return hir.type_ref(f.result.id).ok_or_else(|| {
                Error::new(format!("no result type for {}", self.syms.str(c.name)))
            });
        }
        match c.kind {
            CallableKind::Constant => {
                let d = c.func.decl.constant().expect("constant");
                Ok(hir.ty(&d.value))
            }
            CallableKind::Test => Ok(self.session.test_outcome()),
            _ => Err(Error::new("callable without result")),
        }
    }

    /// The result type of `c`: the borrowing variant of its `Result` when the checker found some
    /// cases borrowed from the arguments and the others owned (`Fact::BorrowedOk`, `Fact::BorrowedError`).
    fn borrowing_result_ty(&self, m: &mut Module, c: &Callable, ret: MTy) -> MTy {
        use ms_check::api::ownership::Fact;
        let (file, id) = (c.module.file, c.id());
        let TyKind::Alt(a) = m.types.kind(ret).clone() else {
            return ret;
        };
        let mut mask = 0u64;
        for (fact, name) in [(Fact::BorrowedOk, "ok"), (Fact::BorrowedError, "error")] {
            if self.fact(file, id, fact)
                && let Some(i) = m.alts[a.index()].cases.iter().position(|k| k.name == name)
            {
                mask |= 1 << i;
            }
        }
        if mask == 0 {
            return ret;
        }
        m.borrowing_alt(a, mask).1
    }

    /// Reserves (and queues) the instance of `c` under `subst`.
    pub(crate) fn function_for(
        &mut self,
        m: &mut Module,
        c: &Rc<Callable>,
        subst: &Subst,
    ) -> Result<FuncId, Error> {
        self.function_variant(m, c, subst, Variant::default())
    }

    /// Reserves (and queues) the instance of `c` under `subst` and `variant`.
    pub(crate) fn function_variant(
        &mut self,
        m: &mut Module,
        c: &Rc<Callable>,
        subst: &Subst,
        variant: Variant,
    ) -> Result<FuncId, Error> {
        let key = instance_key(self.syms, &mut self.tys, c, subst, variant);
        if let Some(id) = self.insts.get(&key) {
            return Ok(*id);
        }
        let mut params = Vec::new();
        let bindings: Vec<&BindingRef> = c.self_binding.iter().chain(c.parameters.iter()).collect();
        let vars = self.var_positions(c);
        let owned_mask = variant.owned.then(|| self.owned_mask(c)).flatten();
        let takes_function = bindings.iter().any(|b| b.ty.kind == ct::Kind::Function);
        for (i, b) in bindings.into_iter().enumerate() {
            let t = ct::sub(&b.ty, subst);
            let ty = self.lower_ty(m, &t)?;
            // A changed parameter travels as the address of a slot the callee takes the value
            // from and puts the final value back into.
            let ty = if vars.contains(&i) { MTy::PTR } else { ty };
            let owned = owned_mask.as_ref().is_some_and(|mask| mask[i]);
            params.push(Param {
                ty,
                mode: if owned { Mode::Move } else { Mode::Borrow },
            });
        }
        // A test of a file with `make_fixture` changes the file's one fixture in place.
        let fixture_param = c.fixture.is_some();
        if fixture_param {
            params.push(Param {
                ty: MTy::PTR,
                mode: Mode::Borrow,
            });
        }
        let result = ct::sub(&self.callable_result(c)?, subst);
        let ret = self.lower_ty(m, &result)?;
        let ret = self.borrowing_result_ty(m, c, ret);
        let name = if let ms_check::api::ast::DeclKind::Test(t) = &c.func.decl.decl().kind {
            format!("{} {}", if t.bench { "bench" } else { "test" }, t.name)
        } else if self.syms.str(c.name).is_empty() {
            "test".to_string()
        } else if let ms_check::api::ast::DeclKind::Impl(i) = &c.func.decl.decl().kind {
            // Fault traces name a method after its receiver type.
            format!("{}.{}", i.receiver.name(self.syms), self.syms.str(c.name))
        } else {
            self.syms.str(c.name).to_string()
        };
        let params_len = params.len();
        let mut f = ms_mir::ir::Func::new(&name, params, ret);
        // The checker keeps a `var` argument from overlapping any other argument.
        f.noalias = vars.iter().map(|&i| i as u32).collect();
        if fixture_param {
            f.noalias.push((params_len - 1) as u32);
        }
        // The checker found every result a reference into the arguments. An optional that holds
        // its payload in a heap block cannot be a view (`opt.view` of a boxed optional), so that
        // instance returns a copy the caller owns; the checker still treats the call as a borrow,
        // which a copy of an unchanged value cannot be told apart from.
        f.ret_borrowed = self.fact(
            c.module.file,
            c.id(),
            ms_check::api::ownership::Fact::ReturnsBorrow,
        ) && !m.opt_inner(ret).is_some_and(|inner| m.opt_is_boxed(inner));
        // The checker found the result an interface view of the arguments: owned, dropped by
        // the caller, held as a borrow of the arguments while it lives.
        f.ret_view = self.fact(
            c.module.file,
            c.id(),
            ms_check::api::ownership::Fact::ReturnsView,
        );
        // A function that returns a promise from a closure it is given keeps that closure alive.
        f.keeps_scoped = result.is_source_type(self.syms, "@std/concurrency/promise.ms", "Promise")
            && takes_function;
        let id = m.add_func(f);
        self.insts.insert(key, id);
        self.queue.push(Job {
            func: id,
            kind: JobKind::Source {
                callable: c.clone(),
                subst: subst.clone(),
                variant,
            },
        });
        Ok(id)
    }
}

/// Lowers the program rooted at `options.entry`.
pub(crate) fn lower_program(
    syms: ms_check::api::Names,
    program: &Program,
    options: &Options,
) -> Result<Module, Error> {
    let mut cx = Cx::new(syms, program);
    let mut m = Module::new("main");
    let entry_file = ct::n(&options.entry);
    let main = cx
        .callables
        .values()
        .find(|c| {
            c.module.file == entry_file
                && c.kind == CallableKind::Function
                && syms.str(c.name) == "main"
        })
        .cloned()
        .ok_or_else(|| Error::new("no main function"))?;
    let main_id = cx.function_for(&mut m, &main, &Subst::default())?;
    drain(syms, &mut cx, &mut m)?;
    cx.check_strict_copies()?;
    let entry = if m.funcs[main_id.index()].ret == MTy::INT {
        m.funcs[main_id.index()].linkage = Linkage::Export;
        main_id
    } else {
        let wrapper = crate::runner::build_main_wrapper(&mut m, main_id)?;
        m.add_func(wrapper)
    };
    m.entry = Some(entry);
    Ok(m)
}

/// Lowers the tests of every project module (not the bundled standard library) with a runner
/// as the entry; returns each test's `module::name` identity.
pub(crate) fn lower_tests(
    syms: ms_check::api::Names,
    program: &Program,
    _options: &Options,
    bench: bool,
) -> Result<(Module, Vec<String>), Error> {
    let mut cx = Cx::new(syms, program);
    let mut m = Module::new("main");
    let mut tests: Vec<(ct::Name, Rc<Callable>)> = Vec::new();
    for module in &program.modules {
        let file = module.file;
        if syms.str(file).starts_with("@std/") {
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
        if let ms_check::api::ast::DeclKind::Test(t) = &c.func.decl.decl().kind {
            names.push(format!("{file_t}::{}", t.name, file_t = syms.str(file)));
        }
        ids.push(cx.function_for(&mut m, c, &Subst::default())?);
    }
    if bench && !tests.is_empty() {
        // Each bench runs under the standard driver, which repeats and times its body.
        let driver = cx
            .callables
            .values()
            .find(|c| {
                syms.str(c.module.file) == "@std/test/bench.ms"
                    && syms.str(c.name) == "run_bench_block"
            })
            .cloned()
            .ok_or_else(|| Error::new("the bench driver @std/test/bench.ms is not loaded"))?;
        let driver = cx.function_for(&mut m, &driver, &Subst::default())?;
        let per: Vec<i64> = tests
            .iter()
            .map(|(_, c)| match &c.func.decl.decl().kind {
                ms_check::api::ast::DeclKind::Test(t) => t.per,
                _ => 1,
            })
            .collect();
        ids = crate::runner::bench_entries(&mut m, &ids, &per, driver);
    }
    if bench || tests.is_empty() {
        drain(syms, &mut cx, &mut m)?;
        cx.check_strict_copies()?;
        m.entry = Some(crate::runner::build_runner(&mut m, &ids)?);
        return Ok((m, names));
    }
    // Test files run as promises under `@std/internal/test_runner.ms`, each file's tests in order.
    const RUNNER: &str = "@std/internal/test_runner.ms";
    let find = |cx: &Cx, name: &str| {
        cx.callables
            .values()
            .find(|c| syms.str(c.module.file) == RUNNER && syms.str(c.name) == name)
            .cloned()
            .ok_or_else(|| Error::new("the test runner @std/internal/test_runner.ms is not loaded"))
    };
    let run_files = find(&cx, "run_test_files")?;
    let run_files = cx.function_for(&mut m, &run_files, &Subst::default())?;
    let mut order: Vec<ct::Name> = Vec::new();
    for (file, _) in &tests {
        if !order.contains(file) {
            order.push(*file);
        }
    }
    let mut files = Vec::new();
    for file in &order {
        let members: Vec<(FuncId, i64)> = tests
            .iter()
            .zip(&ids)
            .enumerate()
            .filter(|(_, ((f, _), _))| f == file)
            .map(|(i, (_, id))| (*id, i as i64))
            .collect();
        let fixture = cx.fixtures.get(file).cloned();
        let Some(fixture) = fixture else {
            let plain = find(&cx, "run_plain_file")?;
            files.push(crate::runner::TestFile {
                tests: members,
                harness: cx.function_for(&mut m, &plain, &Subst::default())?,
                fixture: None,
            });
            continue;
        };
        let generic = find(&cx, "run_fixture_file")?;
        // `make: fn() F` names the fixture type variable.
        let variable = generic
            .parameters
            .get(1)
            .map(|b| b.ty.result_ty())
            .ok_or_else(|| Error::new("run_fixture_file takes the fixture type"))?;
        let mut subst = Subst::default();
        subst.insert(variable.id, fixture.ty.clone());
        let harness = cx.function_for(&mut m, &generic, &subst)?;
        let factory = fixture
            .factory
            .decl
            .as_ref()
            .and_then(|d| cx.callables.get(&(fixture.factory.module, d.id())).cloned())
            .ok_or_else(|| Error::new("make_fixture not found"))?;
        let make = cx.function_for(&mut m, &factory, &Subst::default())?;
        let mut hooks = [None; 4];
        for (i, name) in ["before_all", "before_each", "after_each", "after_all"]
            .iter()
            .enumerate()
        {
            if let Some(hook) = cx.fixture_hook(&fixture.ty, name) {
                hooks[i] = Some(cx.function_for(&mut m, &hook, &Subst::default())?);
            }
        }
        files.push(crate::runner::TestFile {
            tests: members,
            harness,
            fixture: Some((make, hooks)),
        });
    }
    drain(syms, &mut cx, &mut m)?;
    cx.check_strict_copies()?;
    m.entry = Some(crate::runner::build_file_runners(
        &mut m, &files, run_files,
    )?);
    Ok((m, names))
}

/// Whether a test callable is a `bench` block.
fn is_bench(c: &Callable) -> bool {
    matches!(&c.func.decl.decl().kind, ms_check::api::ast::DeclKind::Test(t) if t.bench)
}

/// Lowers queued jobs until none remain. The text of an interface value tests every table of
/// the interface, so it waits until no other job can still add one.
fn drain(syms: ms_check::api::Names, cx: &mut Cx, m: &mut Module) -> Result<(), Error> {
    let deferred = |m: &Module, j: &Job| matches!(&j.kind, JobKind::Format(t, _) if matches!(m.types.kind(*t), ms_mir::types::TyKind::Iface(_)));
    loop {
        let next = match cx.queue.iter().rposition(|j| !deferred(m, j)) {
            Some(i) => cx.queue.remove(i),
            None => match cx.queue.pop() {
                Some(j) => j,
                // Every function is lowered: place the Raw functions' scope-exit drops.
                None => return ms_mir::elaborate::run(m).map_err(Error::new),
            },
        };
        lower_job(syms, cx, m, next)?;
    }
}

fn lower_job(
    syms: ms_check::api::Names,
    cx: &mut Cx,
    m: &mut Module,
    job: Job,
) -> Result<(), Error> {
    let (c, jsubst, variant) = match &job.kind {
        JobKind::Source {
            callable,
            subst,
            variant,
        } => (callable.clone(), subst.clone(), *variant),
        JobKind::Format(t, repr) => {
            return crate::text::build_format(cx, m, job.func, *t, *repr);
        }
        JobKind::Equal(t, scope) => return crate::eq::build_eq(cx, m, job.func, *t, *scope),
        JobKind::HandleMethod(j) => {
            return crate::natiface::build_method(cx, m, job.func, j);
        }
        JobKind::Lambda(l) => return crate::closure::build_lambda(syms, cx, m, job.func, l),
        JobKind::BoundNative(n) => {
            return crate::closure::build_bound_native(syms, cx, m, job.func, n);
        }
        JobKind::IfaceNative(n) => {
            return crate::closure::build_iface_native(syms, cx, m, job.func, n);
        }
        JobKind::BoundAlias(n) => {
            return crate::bound_alias::build_bound_alias(syms, cx, m, job.func, n);
        }
        JobKind::DefaultThunk(n) => {
            return crate::closure::build_default_thunk(syms, cx, m, job.func, n);
        }
        JobKind::NativeThunk(n) => {
            return crate::closure::build_native_thunk(syms, cx, m, job.func, n);
        }
        JobKind::Json(j) => return crate::json::build_json(syms, cx, m, job.func, j),
        JobKind::FnAdapt(j) => return crate::closure::build_fn_adapter(syms, cx, m, job.func, j),
        JobKind::IfaceThunk(j) => {
            return crate::closure::build_iface_thunk(syms, cx, m, job.func, j);
        }
    };
    let hir = cx.module(c.module.file)?;
    let file = m.add_file(syms.str(c.module.file));
    let proto = m.funcs[job.func.index()].clone();
    let b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    let mut fl = FnLower::new(cx, b, hir, jsubst, file, proto.ret);
    fl.variant = variant;
    // A borrow-returning function returns references as they are; `emit_return` reads the flag.
    fl.b.func_mut().ret_borrowed = proto.ret_borrowed;
    fl.b.func_mut().ret_view = proto.ret_view;
    // Closures made here inherit the flag (see `lambda`).
    fl.b.func_mut().keeps_scoped = proto.keeps_scoped;
    let result = fl.lower_callable(&c);
    let mut func = fl.b.into_func();
    result?;
    func.noalias = proto.noalias;
    func.ret_borrowed = proto.ret_borrowed;
    func.ret_view = proto.ret_view;
    func.keeps_scoped = proto.keeps_scoped;
    func.compact_blocks();
    m.funcs[job.func.index()] = func;
    Ok(())
}

impl<'a> FnLower<'a> {
    /// Binds a `var` parameter: `v` is the address of a slot the caller filled; the callee owns
    /// the value it takes out and puts the final value back on return (`var_slots`).
    pub(crate) fn bind_var_parameter(&mut self, b: &BindingRef, v: Value) -> Result<(), Error> {
        let ty = self.mty(&b.ty)?;
        let owned = self.needs_drop(ty);
        let var = self
            .b
            .declare_var(ty, if owned { Mode::Move } else { Mode::Borrow });
        if (self.closing_fn || matches!(self.b.m.types.kind(ty), TyKind::Type(_)))
            && !self.slotted.contains(&b.uid)
        {
            // A function whose scopes close resources keeps every `var` parameter in the
            // caller's slot, so the pass's error exit has nothing to put back. A type stays in the caller's slot: field reads and writes touch only the fields
            // they name, instead of moving every field out at entry and back at each return.
            self.locals.insert(
                b.uid,
                Local {
                    var,
                    ty,
                    slot: Some(v),
                    opt: false,
                },
            );
            self.var_slots.push(VarSlot { uid: b.uid, ptr: v });
            return Ok(());
        }
        let x = self.move_out(v, ty);
        self.b.def_var(var, x);
        self.locals.insert(
            b.uid,
            Local {
                var,
                ty,
                slot: None,
                opt: false,
            },
        );
        self.slotify(b.uid);
        self.var_slots.push(VarSlot { uid: b.uid, ptr: v });
        Ok(())
    }

    pub(crate) fn new(
        cx: &'a mut Cx,
        b: FuncBuilder<'a>,
        hir: Rc<ModuleHir>,
        subst: Subst,
        file: u32,
        ret_ty: MTy,
    ) -> FnLower<'a> {
        FnLower {
            syms: cx.syms,
            cx,
            b,
            hir,
            subst,
            variant: Variant::default(),
            file,
            locals: HashMap::default(),
            scopes: vec![Vec::new()],
            scope_marks: vec![ScopeMark::new(0, None)],
            next_scope: 1,
            raw_owners: true,
            raw_owned: std::collections::HashSet::default(),
            raw_vars: HashMap::default(),
            tracked_vars: HashMap::default(),
            raw_slots: HashMap::default(),
            split_places: HashMap::default(),
            split_owners: HashMap::default(),
            held: HashMap::default(),
            must_move: HashSet::default(),
            temps: Vec::new(),
            pass_temps: std::collections::HashMap::default(),
            default_frames: Vec::new(),
            prepared_indices: HashMap::default(),
            capture_indices: HashSet::default(),
            resource_temps: HashMap::default(),
            loops: Vec::new(),
            dead: false,
            ret_ty,
            jnode: None,
            jwhy: None,
            counts_depth: false,
            pending_return: None,
            prologue_done: false,
            closed_on_path: HashSet::default(),
            deferred_close: None,
            var_slots: Vec::new(),
            closing_fn: false,
            slotted: HashSet::default(),
            scrutinee_lives: false,
            redefined: HashSet::default(),
            views: HashSet::default(),
            borrowed_params: HashSet::default(),
            stable_reads: HashSet::default(),
            keys_view_for: None,
            map_walk_for: None,
            hoisted: HashMap::default(),
            map_walk: None,
            split_view_for: None,
            discard: None,
            stmt_pos: None,
            source_scope: 0,
            err_slot: None,
            split_iter_for: None,
            chars_iter_for: None,
            converting: None,
            scalars_scan: false,
            string_needed: HashSet::default(),
            scalar_locals: HashMap::default(),
            in_thunk: false,
            adapter: false,
            hold_declared: false,
            boundary_reads: Default::default(),
            aliases: HashMap::default(),
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
    /// Whether `v` is an interface value.
    pub fn is_iface(&self, v: ms_mir::ir::Value) -> bool {
        matches!(
            self.b.m.types.kind(self.ty_of(v)),
            ms_mir::types::TyKind::Iface(_)
        )
    }

    pub fn is_resource(&self, t: MTy) -> bool {
        self.cx.source_tys.get(t.0 as usize).is_some_and(|ty| {
            self.cx.classes.class(self.syms, ty) == ms_check::api::ownership::Class::Resource
        })
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
    /// Whether this function returns a borrowing variant: some cases of its `Result` borrow from the
    /// arguments and the others are owned.
    pub fn ret_borrowing(&self) -> bool {
        matches!(self.b.m.types.kind(self.ret_ty),
            TyKind::Alt(a) if self.b.m.alts[a.index()].borrowed != 0)
    }

    /// Whether this function returns an `Optional` or a `Result`: a borrowed part it wraps into the
    /// result is a copy the types' rule declares (`owned_boundary`).
    pub fn ret_boundary(&self) -> bool {
        match self.b.m.types.kind(self.ret_ty) {
            TyKind::Opt(_) => true,
            TyKind::Alt(a) => self.b.m.alts[a.index()].std == ms_mir::types::Std::Result,
            _ => false,
        }
    }

    pub fn result_ty(&self) -> MTy {
        self.ret_ty
    }

    pub fn ty_of(&self, v: Value) -> MTy {
        self.b.ty(v)
    }

    // ----------------------------------------------------------- ownership

    /// An owned reference to the operand: the temporary itself, or a copy of a borrow.
    #[track_caller]
    pub fn owned(&mut self, x: Val) -> Value {
        if x.own || !self.needs_drop(self.ty_of(x.v)) {
            return x.v;
        }
        if !self.adapter
            && !self.boundary_reads.contains(&x.v)
            // A `trim` view kept as a value is the allocation `trim` would have made.
            && !self.views.contains(&x.v)
            && !matches!(
                self.b.defining_op_anywhere(x.v),
                Some(Op::StrLit | Op::BytesLit | Op::OptNone)
            )
        {
            let at = std::panic::Location::caller();
            let loc = self.b.loc();
            let file = self
                .b
                .m
                .files
                .get(loc.file as usize)
                .map(|f| f.rsplit('/').next().unwrap_or("?"))
                .unwrap_or("?");
            let site = format!(
                "{}:{} ({:?}) @{}:{}:{}",
                at.file().rsplit('/').next().unwrap_or("?"),
                at.line(),
                self.b.defining_op_anywhere(x.v),
                file,
                loc.line,
                loc.col
            );
            self.cx.copy_gaps.push(site);
        }
        self.clone_value(x.v)
    }

    /// The alternative `v` is a value of: the borrowing variant when it is one, else `plain`.
    fn alt_of(&self, v: Value, plain: ms_mir::types::AltId) -> ms_mir::types::AltId {
        match self.b.m.types.kind(self.ty_of(v)) {
            TyKind::Alt(a) => *a,
            _ => plain,
        }
    }

    /// An owned value at the `Optional`/`Result` boundary: a read with a default (`get(default)`),
    /// a payload passed through a combinator, a part wrapped into `some(..)`/`ok(..)`, an optional
    /// chain, or a `find` item. These types own what they hold, so a borrowed part is copied, and
    /// the copy is declared by the type's rule so the strict gate does not report it. Chinmay
    /// (2026-11-04): they are simple helpers that need not follow other types' allocation rules and
    /// the codebase must not be littered with `.clone()`.
    pub fn owned_boundary(&mut self, x: Val) -> Value {
        if x.own {
            return x.v;
        }
        self.clone_value(x.v)
    }

    /// An argument a native consumes: in a function value's thunk the argument is borrowed by
    /// the call rule, so the declared copy is made here; elsewhere a borrowed one is a gap.
    pub fn owned_arg(&mut self, x: Val) -> Value {
        if self.in_thunk && !x.own {
            return self.clone_value(x.v);
        }
        self.owned(x)
    }

    /// The payload `field` of the active `case` of the alternative `obj`, owned by the caller,
    /// which moving_params `obj`: an owned temporary hands the payload over and releases the rest; a
    /// borrowed one is a gap in the checker's facts (`owned` types it in strict mode).
    pub fn take_alt_field(
        &mut self,
        alt: ms_mir::types::AltId,
        case: u32,
        field: u32,
        obj: Val,
    ) -> Value {
        self.take_alt_field_as(alt, case, field, obj, false)
    }

    /// `take_alt_field` for a combinator that passes a case through unchanged into a new
    /// `Result` (`map` over an error): from a borrow the copy is declared, because the new
    /// result owns its payload.
    pub fn take_alt_field_through(
        &mut self,
        alt: ms_mir::types::AltId,
        case: u32,
        field: u32,
        obj: Val,
    ) -> Value {
        self.take_alt_field_as(alt, case, field, obj, true)
    }

    fn take_alt_field_as(
        &mut self,
        alt: ms_mir::types::AltId,
        case: u32,
        field: u32,
        obj: Val,
        declared: bool,
    ) -> Value {
        let alt = self.alt_of(obj.v, alt);
        let ty = self.b.m.alts[alt.index()].cases[case as usize].fields[field as usize].1;
        // A borrowed case stays in its owner: its payload is copied out, as from any borrow.
        let borrowed = self.b.m.alts[alt.index()].borrows(case as usize);
        if obj.own && self.needs_drop(ty) && !borrowed {
            let p = self.b.alt_take(alt, case, field, obj.v);
            self.b.alt_release(alt, case, 1 << field, obj.v);
            return p;
        }
        let p = self.b.alt_get(alt, case, field, obj.v);
        let o = if declared {
            self.owned_boundary(Val { v: p, own: false })
        } else {
            self.owned(Val { v: p, own: false })
        };
        self.finish(obj);
        o
    }

    /// The copy a written `.clone()` makes of the borrowed `v` (`copy 1`): the one copy of an
    /// object value a program may write, which the copy sweep leaves out.
    pub fn clone_value(&mut self, v: Value) -> Value {
        let t = self.ty_of(v);
        // A copy of a borrowing variant owns every case: it is an ordinary alternative.
        if let TyKind::Alt(a) = self.b.m.types.kind(t).clone()
            && self.b.m.alts[a.index()].borrowed != 0
        {
            let plain = self.plain_of(a).1;
            return self.b.alt_own(v, plain);
        }
        if !self.needs_drop(t) {
            return v;
        }
        self.b
            .emit(Op::Clone, &[v], ms_mir::ir::Imm::Int(1), Some(t))
            .expect("copy result")
    }

    /// An owned `none` of optional type `t` (a bare `opt.none` is a borrow; its copy owns
    /// nothing, so the copy costs a null check and never touches an object).
    pub fn none_owned(&mut self, t: MTy) -> Value {
        let n = self.b.opt_none(t);
        self.owned(Val { v: n, own: false })
    }

    /// The operand for a borrowing use; owned temporaries are dropped by `flush_temps`.
    pub fn borrow(&mut self, x: Val) -> Value {
        let t = self.ty_of(x.v);
        if x.own && self.holds(t) {
            self.pend_temp(x.v);
        }
        x.v
    }

    /// Registers the owned `v` as a pending temporary. One that needs a plain drop is also
    /// owned by the innermost scope's Raw cleanup, so a path that leaves the statement early
    /// (`return`, `break`, an error) drops it in `elaborate`; the statement end drops it itself.
    pub fn pend_temp(&mut self, v: Value) {
        self.temps.push(v);
        if self.needs_drop(self.ty_of(v))
            && !self.resource_temps.contains_key(&v)
            && !self.is_resource_temp(v)
        {
            let id = self.own_raw_value(v, 0);
            self.pass_temps.insert(v, id);
        }
    }

    /// Stops treating `v` as a pending temporary once it is consumed.
    pub fn unhold_temp(&mut self, v: Value) {
        if let Some(at) = self.temps.iter().rposition(|t| *t == v) {
            self.temps.remove(at);
            if !self.temps.contains(&v) && self.pass_temps.remove(&v).is_some() && !self.dead {
                let (owner, _) = self.temp_owner(v);
                self.b
                    .emit(Op::ScopeDisown, &[owner], ms_mir::ir::Imm::None, None);
            }
        }
    }

    /// Takes the pending temporaries registered after `mark` over from the statement: whoever
    /// receives them owns them.
    pub fn take_temps(&mut self, mark: usize) -> Vec<Value> {
        let taken = self.temps.split_off(mark);
        for t in &taken {
            if self.pass_temps.remove(t).is_some() && !self.dead {
                let (owner, _) = self.temp_owner(*t);
                self.b
                    .emit(Op::ScopeDisown, &[owner], ms_mir::ir::Imm::None, None);
            }
        }
        taken
    }

    /// Drops the owned temporaries registered after `mark`.
    pub fn flush_temps(&mut self, mark: usize) {
        while self.temps.len() > mark {
            let v = self.temps.pop().expect("temp");
            self.pass_temps.remove(&v);
            if !self.dead {
                self.drop_temp(v);
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
            // The scopes the exit leaves drop the temporaries they own.
            if !self.pass_temps.contains_key(&v) {
                self.drop_temp(v);
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
            own: own && self.holds(self.ty_of(v)),
        }
    }

    // -------------------------------------------------------------- locals

    /// Declares `binding` as a borrow of `v`: no copy, and nothing to drop at scope exit.
    pub fn bind_borrow_of(&mut self, binding: &BindingRef, v: Value) {
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
                opt: false,
            },
        );
    }

    /// Declares the local of `binding` holding `value`.
    pub fn bind_local(&mut self, binding: &BindingRef, x: Val) {
        let ty = self.ty_of(x.v);
        // An immutable `let` of a string read from a list element or type field is a lexical
        // borrow (the checker rejects changing the container while it lives): no copy, no drop.
        // Standard-library source is not ownership checked, so it always copies.
        let borrowed = ty == MTy::STR
            && !x.own
            && self.cx.shared(binding.uid)
            && !self.slotted.contains(&binding.uid)
            && self.temps.is_empty()
            && (self.views.contains(&x.v)
                || matches!(
                    self.b.defining_op(x.v),
                    Some(Op::ListGet | Op::ListGetNn | Op::ListGetU | Op::TypeGet)
                ));
        // A pattern variable the checker proved a read-only borrow of its scrutinee stays where it
        // is: a borrow-returning function can hand it back, and a reader skips the copy.
        let borrowed = borrowed
            || (self.cx.shared(binding.uid)
                && !x.own
                && !binding.mutable
                && !self.slotted.contains(&binding.uid)
                && !self.temp_rooted(x.v, 0)
                && self.needs_drop(ty)
                && matches!(
                    self.b.defining_op(x.v),
                    Some(
                        Op::AltGet
                            | Op::OptGet
                            | Op::TypeGet
                            | Op::ListGet
                            | Op::ListGetNn
                            | Op::ListGetU
                            | Op::Load
                    )
                )
                // Its parent must outlive the binding: an owned scrutinee is dropped as soon as
                // its payload has been copied out. A payload loaded out of an interface value
                // (`iface.data`) is held by the interface value itself, so that must be borrowed.
                && self
                    .b
                    .defining_operand(x.v)
                    .is_some_and(|parent| {
                        (self.scrutinee_lives || self.b.is_borrowed(parent))
                            && self.holder_borrowed(x.v, parent)
                    }));
        // A `let` of a borrow-returning call's result the checker holds as a borrow of the arguments.
        let borrowed = borrowed
            || (self.cx.shared(binding.uid)
                && !x.own
                && !binding.mutable
                && !self.slotted.contains(&binding.uid)
                && self.temps.is_empty()
                && self.needs_drop(ty)
                && self.b.defining_op(x.v) == Some(Op::Call)
                && self.b.is_borrowed(x.v));
        if borrowed {
            self.bind_borrow_of(binding, x.v);
            return;
        }
        let owned = self.needs_drop(ty);
        let mode = if owned { Mode::Move } else { Mode::Borrow };
        let var = if binding.mutable || self.redefined.contains(&binding.uid) {
            self.b.declare_var(ty, mode)
        } else {
            self.b.declare_single(ty, mode)
        };
        let v = self.owned(x);
        self.b.def_var(var, v);
        self.own_local(binding.uid, var, ty);
    }

    /// Declares the local `uid` holding `var`, dropped at scope end when its type needs it. A
    /// binding some path moves out of also gets a flag saying whether the local still holds its
    /// value, so the scope end drops it only on the paths that kept it.
    pub fn own_local(&mut self, uid: usize, var: ms_mir::builder::Var, ty: MTy) {
        // A local of one definition that nothing closes or shares is owned by its scope's Raw
        // cleanup: the elaborate pass tracks its moves, so it needs no flag or optional box.
        let single = self.b.var_is_single(var) && !self.redefined.contains(&uid);
        // A reassigned local that nothing moves is owned at each exit instead of at its
        // declaration: the value it holds is only known there.
        let reassigned = !single && !self.cx.ownership.moves.contains_key(&uid);
        if self.raw_owners
            && !self.dead
            && self.needs_drop(ty)
            && (single || reassigned)
            && !self.slotted.contains(&uid)
        {
            self.locals.insert(
                uid,
                Local {
                    var,
                    ty,
                    slot: None,
                    opt: false,
                },
            );
            if single {
                let v = self.b.use_var(var);
                self.own_raw(uid, v);
            } else {
                self.raw_vars.insert(uid, var);
                self.scopes.last_mut().expect("scope").push(uid);
            }
            return;
        }
        let moved = self.needs_drop(ty) && self.cx.ownership.moves.contains_key(&uid);
        let conditional = moved
            && self
                .cx
                .ownership
                .binding_facts
                .has(uid, ms_check::api::ownership::BindingFact::ConditionalMove);
        if moved && !conditional {
            // Every path moves it: the move moving_params the local, and the scope drops nothing.
            self.must_move.insert(uid);
        }
        if moved
            && !conditional
            && self.raw_owners
            && !self.dead
            && !self.slotted.contains(&uid)
            && !self.redefined.contains(&uid)
        {
            // The pass owns each value the variable holds, so an exit before the move releases it.
            self.locals.insert(
                uid,
                Local {
                    var,
                    ty,
                    slot: None,
                    opt: false,
                },
            );
            self.tracked_vars.insert(var, self.scope_marks.len() - 1);
            let v = self.b.use_var(var);
            self.own_raw_value(v, 0);
            return;
        }
        // A conditional move empties the local on its path only. In a variable, the local holds
        // `ty?` and a move leaves `none`; in memory (a closure shares it, or a boxed optional
        // would allocate), the slot keeps its stale bits and a flag says whether they are held.
        let opt = conditional
            && !self.slotted.contains(&uid)
            && !ms_mir::ir::Boxing::default().opt(self.b.m, ty);
        if conditional && !opt {
            self.slotted.insert(uid);
        }
        let var = if opt {
            let v = self.b.use_var(var);
            let some = self.b.opt_some(v);
            let opt_ty = self.ty_of(some);
            let held = self.b.declare_var(opt_ty, Mode::Move);
            self.b.def_var(held, some);
            held
        } else {
            var
        };
        self.locals.insert(
            uid,
            Local {
                var,
                ty,
                slot: None,
                opt,
            },
        );
        if opt && self.raw_owners && !self.dead {
            // The held optional is `none` once a path moved the value out: owning it at each
            // exit drops what is still there.
            self.raw_vars.insert(uid, var);
        }
        self.slotify(uid);
        if !self.needs_drop(ty) {
            return;
        }
        self.scopes.last_mut().expect("scope").push(uid);
        if conditional && !opt {
            let flag = self.b.declare_var(MTy::BOOL, Mode::Borrow);
            let yes = self.b.bconst(true);
            self.b.def_var(flag, yes);
            self.held.insert(uid, flag);
        }
    }

    /// Whether the name expression (or lambda) `node` moves the binding `uid` out of its local,
    /// which must own its value: a borrowed local (a function value's parameter, a loop variable
    /// reading a list in place) hands out a copy instead.
    pub fn moves_at(&self, uid: usize, node: ms_check::api::ast::NodeId) -> bool {
        self.cx
            .ownership
            .moves
            .get(&uid)
            .is_some_and(|n| n.contains(&node))
            && !self.aliases.contains_key(&uid)
            && self.locals.get(&uid).is_some_and(|l| self.local_owned(l))
    }

    /// Whether the local owns the value it holds (a slot always does).
    pub fn local_owned(&self, l: &Local) -> bool {
        l.slot.is_some() || self.b.var_mode(l.var) == Mode::Move
    }

    /// Takes the value of the local `l` of binding `uid` out: the local is empty until it is
    /// stored to again, and the scope end drops nothing for it on this path.
    pub fn take_local(&mut self, uid: usize, l: &Local) -> Value {
        let v = self.local_take(l);
        if l.opt {
            let opt_ty = self.b.var_ty(l.var);
            let none = self.none_owned(opt_ty);
            self.b.def_var(l.var, none);
        }
        if let Some(flag) = self.held.get(&uid).copied() {
            let no = self.b.bconst(false);
            self.b.def_var(flag, no);
        }
        self.disown_raw(uid, v);
        v
    }

    /// Stores `v` into the local `l` of binding `uid`, which holds its value again.
    pub fn refill_local(&mut self, uid: usize, l: &Local, v: Value) {
        self.local_put(l, v);
        if let Some(flag) = self.held.get(&uid).copied() {
            let yes = self.b.bconst(true);
            self.b.def_var(flag, yes);
        }
    }

    /// Drops what the local `l` of binding `uid` holds at scope end: nothing on a path that
    /// moved it out.
    pub fn drop_local(&mut self, uid: usize, l: &Local) {
        if !self.needs_drop(l.ty) || self.must_move.contains(&uid) {
            return;
        }
        if l.opt {
            // Dropping `none` releases nothing.
            let held = self.b.use_var(l.var);
            self.b.emit(Op::Drop, &[held], ms_mir::ir::Imm::None, None);
            return;
        }
        let v = self.local_take(l);
        let flag = self.held.get(&uid).copied();
        match flag {
            Some(flag) => {
                let held = self.b.use_var(flag);
                self.b
                    .emit(Op::DropIf, &[held, v], ms_mir::ir::Imm::None, None);
            }
            None => {
                self.b.emit(Op::Drop, &[v], ms_mir::ir::Imm::None, None);
            }
        }
    }

    /// Whether `v` is, or borrows from, an owned temporary that is still pending: the statement
    /// end drops it, so a binding must not keep pointing into it. A value owned by a local (or a
    /// borrowed parameter) is not pending, whatever else is.
    fn temp_rooted(&self, v: Value, depth: u32) -> bool {
        if self.temps.is_empty() {
            return false;
        }
        if self.temps.contains(&v) {
            return true;
        }
        if depth > 32 || !self.b.is_borrowed(v) {
            return depth > 32;
        }
        self.b
            .defining_args_anywhere(v)
            .is_some_and(|args| args.iter().any(|a| self.temp_rooted(*a, depth + 1)))
    }

    /// Whether the value `parent` that `v` was read from is itself borrowed, looking through the
    /// `iface.data` pointer a type pattern loads its payload from.
    fn holder_borrowed(&self, v: Value, parent: Value) -> bool {
        if self.b.defining_op(v) != Some(Op::Load) {
            return true;
        }
        match self.b.defining_operand(parent) {
            Some(iface) => self.b.is_borrowed(iface),
            None => false,
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

    /// The current value of a local, as a borrow.
    pub fn local_get(&mut self, l: &Local) -> Value {
        match l.slot {
            Some(p) => self
                .b
                .emit(Op::Load, &[p], ms_mir::ir::Imm::Ty(l.ty), Some(l.ty))
                .expect("load"),
            None if l.opt => {
                let held = self.b.use_var(l.var);
                self.b.opt_get(held)
            }
            None => self.b.use_var(l.var),
        }
    }

    /// Moves the value out of a local, which must be stored to again.
    pub fn local_take(&mut self, l: &Local) -> Value {
        match l.slot {
            Some(p) => self.move_out(p, l.ty),
            None if l.opt => {
                let held = self.b.use_var(l.var);
                self.b.opt_unbox(held)
            }
            None => {
                let v = self.b.use_var(l.var);
                if self.tracked_vars.contains_key(&l.var) && !self.dead {
                    self.b
                        .emit(Op::ScopeDisown, &[v], ms_mir::ir::Imm::None, None);
                }
                v
            }
        }
    }

    /// Stores an owned value into a local; the old value is not dropped.
    pub fn local_put(&mut self, l: &Local, v: Value) {
        match l.slot {
            Some(p) => self.move_into(p, v),
            None if l.opt => {
                let some = self.b.opt_some(v);
                self.b.def_var(l.var, some);
            }
            None => {
                self.b.def_var(l.var, v);
                if let Some(i) = self.tracked_vars.get(&l.var).copied()
                    && !self.dead
                {
                    self.own_raw_value_in(i, v, 0);
                }
            }
        }
    }

    /// Holds an operand for the rest of the enclosing scope (a loop's iterable).
    pub fn bind_hidden(&mut self, x: Val) -> ms_mir::builder::Var {
        let ty = self.ty_of(x.v);
        let owned = self.needs_drop(ty);
        let var = self
            .b
            .declare_var(ty, if owned { Mode::Move } else { Mode::Borrow });
        let v = self.owned(x);
        self.b.def_var(var, v);
        let uid = self.adopt_hidden(var, ty);
        self.own_hidden(uid, None, true);
        var
    }

    /// `bind_hidden` for a loop iterable, which the loop decides how to release.
    pub fn bind_hidden_iterable(&mut self, x: Val) -> ms_mir::builder::Var {
        let ty = self.ty_of(x.v);
        let owned = self.needs_drop(ty);
        // Nothing rewrites the iterable, so it is defined once.
        let var = self
            .b
            .declare_single(ty, if owned { Mode::Move } else { Mode::Borrow });
        let v = self.owned(x);
        self.b.def_var(var, v);
        self.adopt_hidden(var, ty);
        var
    }

    /// Hands the hidden value of `uid` (a held scrutinee or loop iterable) to the elaborate pass,
    /// which closes it with `closer` when there is one and drops it where the scope ends.
    /// `whole` says nothing takes the value apart, so a value rewritten in place may be owned at
    /// each exit. Returns whether the pass owns it now; a value that lives in memory, or whose close changes
    /// it, stays with lowering.
    pub fn own_hidden(
        &mut self,
        uid: usize,
        closer: Option<&crate::close::CloseKind>,
        whole: bool,
    ) -> bool {
        let l = self.locals[&uid];
        if !(self.raw_owners
            && !self.dead
            && l.slot.is_none()
            && self.needs_drop(l.ty)
            && !self.slotted.contains(&uid))
        {
            return false;
        }
        if !self.b.var_is_single(l.var) {
            // A hidden value rewritten in place (the piece of a split loop) is owned at each exit,
            // where the value it holds is known; nothing takes it apart.
            if closer.is_some() || !whole {
                return false;
            }
            self.raw_vars.insert(uid, l.var);
            return true;
        }
        let kind = match closer {
            Some(c) if c.in_value() => self.close_thunk(c, l.ty, false).index() as u32 + 2,
            Some(_) => return false,
            None => 0,
        };
        if let Some(scope) = self.scopes.last_mut() {
            scope.retain(|u| *u != uid);
        }
        let v = self.b.use_var(l.var);
        self.own_raw_kind(uid, v, kind);
        true
    }

    /// Hands the held scrutinee `uid`, which lives in memory, to the pass to close with `closer`
    /// (shielded, errors dropped) where its scope ends.
    pub fn own_hidden_slot(&mut self, uid: usize, closer: &crate::close::CloseKind) {
        let l = self.locals[&uid];
        let (Some(ptr), true) = (l.slot, self.raw_owners && !self.dead) else {
            return;
        };
        let thunk = self.close_thunk(closer, l.ty, true);
        if let Some(scope) = self.scopes.last_mut() {
            scope.retain(|u| *u != uid);
        }
        self.own_raw_kind(uid, ptr, thunk.index() as u32 + 2);
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
                opt: false,
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
                opt: false,
            },
        );
    }

    pub fn local(&mut self, binding: &BindingRef) -> Result<Local, Error> {
        self.locals
            .get(&binding.uid)
            .copied()
            .ok_or_else(|| Error::new(format!("unbound variable {}", self.syms.str(binding.name))))
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
        let parent = self.scope_marks.last().map(|m| m.id);
        self.scopes.push(Vec::new());
        self.scope_marks
            .push(ScopeMark::new(self.next_scope, parent));
        self.next_scope += 1;
    }

    /// Removes the innermost scope without dropping anything (control never reached its end).
    pub fn discard_scope(&mut self) {
        self.scopes.pop();
        self.scope_marks.pop();
    }

    /// Hands the owned `v` of the local `uid` to the innermost scope's Raw cleanup: `elaborate`
    /// drops it wherever a path leaves the scope still holding it. Only for a local of one
    /// definition that nothing moves, flags or closes (the other kinds still drop themselves).
    fn own_raw(&mut self, uid: usize, v: Value) {
        self.own_raw_kind(uid, v, 0);
    }

    /// `own_raw` with the owner's cleanup `kind` (`scope.own S K v`).
    pub fn own_raw_kind(&mut self, uid: usize, v: Value, kind: u32) {
        self.own_raw_value(v, kind);
        self.raw_owned.insert(uid);
    }

    /// `scope.own` of `v` in the innermost scope, beginning the enclosing scopes first.
    pub(crate) fn own_raw_value(&mut self, v: Value, kind: u32) -> u32 {
        let i = self.scope_marks.len() - 1;
        self.own_raw_value_in(i, v, kind)
    }

    /// `scope.own` of `v` in scope `i`.
    fn own_raw_value_in(&mut self, i: usize, v: Value, kind: u32) -> u32 {
        // The enclosing scopes begin first: an error exit of the pass walks the chain.
        for mark in &mut self.scope_marks {
            if !mark.begun {
                mark.begun = true;
                let imm = ms_mir::ir::Imm::Scope(mark.id, mark.parent);
                self.b.emit(Op::ScopeBegin, &[], imm, None);
            }
        }
        let imm = ms_mir::ir::Imm::Scope(self.scope_marks[i].id, kind);
        self.b.emit(Op::ScopeOwn, &[v], imm, None);
        self.scope_marks[i].id
    }

    /// A Raw-owned local's value moved on without an op that consumes it: it is no longer the
    /// scope's to drop on this path.
    pub fn disown_raw(&mut self, uid: usize, v: Value) {
        // A resource in memory is owned by its slot: the slot is what leaves the scope.
        let v = self.raw_slots.get(&uid).map_or(v, |r| r.slot);
        if self.raw_owned.contains(&uid) {
            self.b
                .emit(Op::ScopeDisown, &[v], ms_mir::ir::Imm::None, None);
        }
    }

    /// Ends the Raw cleanup of scope `i`: the point `elaborate` places its drops.
    fn end_raw(&mut self, i: usize) {
        let mark = self.scope_marks[i];
        if mark.begun {
            let imm = ms_mir::ir::Imm::Scope(mark.id, 0);
            self.b.emit(Op::ScopeEnd, &[], imm, None);
        }
    }

    fn drop_scope_locals(&mut self, depth: usize) {
        for i in (depth..self.scopes.len()).rev() {
            let uids = self.scopes[i].clone();
            for uid in uids.iter().rev() {
                if self.closed_on_path.contains(uid) {
                    continue;
                }
                if let Some(var) = self.raw_vars.get(uid).copied() {
                    let cur = self.b.use_var(var);
                    self.own_raw_value_in(i, cur, 0);
                    continue;
                }
                let l = self.locals[uid];
                self.drop_local(*uid, &l);
            }
            self.end_raw(i);
        }
    }

    /// Ends a scope, dropping its locals when control reaches the end.
    pub fn pop_scope(&mut self) {
        let mut carried = Vec::new();
        if !self.dead {
            // A temporary of the statement this scope ends inside (a `for` over `f().split(..)`)
            // outlives the scope: its owner moves to the enclosing one.
            let id = self.scope_marks.last().map(|m| m.id);
            carried = self
                .temps
                .iter()
                .copied()
                .filter(|t| self.pass_temps.get(t).copied() == id)
                .collect();
            for t in &carried {
                let (owner, _) = self.temp_owner(*t);
                self.b
                    .emit(Op::ScopeDisown, &[owner], ms_mir::ir::Imm::None, None);
            }
            let d = self.scopes.len() - 1;
            self.drop_scope_locals(d);
        }
        self.discard_scope();
        for t in carried {
            let (owner, kind) = self.temp_owner(t);
            let id = self.own_raw_value(owner, kind);
            self.pass_temps.insert(t, id);
        }
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
        // A borrow-returning function returns the reference itself; the caller never releases it.
        let borrowed = self.b.func_mut().ret_borrowed;
        let views = self.b.func_mut().ret_view;
        let value = value.map(|x| self.result_return(x));
        let v = value.map(|x| {
            if borrowed {
                x.v
            } else if views && !x.own && self.is_iface(x.v) {
                // A view returner hands a plain reference to an interface value on as a value that
                // owns nothing (`iface.view`); the caller drops it like the views it builds.
                self.b.iface_view(x.v)
            } else if self.ret_boundary() {
                self.owned_boundary(x)
            } else {
                self.owned(x)
            }
        });
        // A close error returned from inside this unwinding re-enters here with the prologue done.
        let nested = self.prologue_done;
        let mut default_bindings = Vec::new();
        if !nested {
            default_bindings = self.leave_default_frames();
            for slot in self.var_slots.clone() {
                let l = self.locals[&slot.uid];
                if l.slot == Some(slot.ptr) {
                    // Changed in place: nothing to put back.
                    continue;
                }
                let x = self.local_take(&l);
                self.move_into(slot.ptr, x);
            }
            // The temporaries stay registered: a conditional return leaves the others running.
            for t in self.temps.clone().into_iter().rev() {
                if !self.pass_temps.contains_key(&t) {
                    self.drop_temp(t);
                }
            }
        }
        // The returned value leaves its owner before the scopes end, so their cleanup does not
        // drop it.
        if let Some(v) = v
            && !borrowed
            && self.scope_marks.iter().any(|m| m.begun)
            && self.needs_drop(self.ty_of(v))
        {
            self.b
                .emit(Op::ScopeDisown, &[v], ms_mir::ir::Imm::None, None);
        }
        let pending = v.map(|v| Val { v, own: !borrowed });
        let outer_pending = std::mem::replace(
            &mut self.pending_return,
            if nested { None } else { pending },
        );
        self.prologue_done = true;
        self.unwind_to(0);
        self.prologue_done = nested;
        self.pending_return = outer_pending;
        if self.counts_depth {
            self.b
                .emit(Op::DepthLeave, &[], ms_mir::ir::Imm::None, None);
        }
        self.b.ret(v);
        self.restore_shadowed(default_bindings);
        self.terminated();
    }

    /// An early return from inside a default argument: the copies the default was still holding
    /// are released on this path, and the bindings it shadowed are visible again for the
    /// writeback and scope drops that follow. Returns what `restore_shadowed` needs to put the
    /// default's bindings back for the paths that continue.
    pub(crate) fn leave_default_frames(&mut self) -> Vec<(usize, Option<Local>)> {
        let mut changed = Vec::new();
        for i in (0..self.default_frames.len()).rev() {
            for var in self.default_frames[i].copies.clone().into_iter().rev() {
                let v = self.b.use_var(var);
                self.drop_value(v);
            }
            for (uid, saved) in self.default_frames[i].shadowed.clone().into_iter().rev() {
                changed.push((uid, self.locals.get(&uid).copied()));
                match saved {
                    Some(l) => {
                        self.locals.insert(uid, l);
                    }
                    None => {
                        self.locals.remove(&uid);
                    }
                }
            }
        }
        changed
    }

    /// Puts back the bindings a default frame replaced.
    pub(crate) fn restore_shadowed(&mut self, shadowed: Vec<(usize, Option<Local>)>) {
        for (uid, local) in shadowed.into_iter().rev() {
            match local {
                Some(l) => {
                    self.locals.insert(uid, l);
                }
                None => {
                    self.locals.remove(&uid);
                }
            }
        }
    }

    /// A forwarded Result may borrow a case this function must own (an implicit close can
    /// return a fresh Error). Move owned cases and copy only newly-owned borrowed payloads.
    fn result_return(&mut self, x: Val) -> Val {
        if self.b.func_mut().ret_borrowed {
            return x;
        }
        let (TyKind::Alt(src), TyKind::Alt(dst)) = (
            self.b.m.types.kind(self.ty_of(x.v)).clone(),
            self.b.m.types.kind(self.ret_ty).clone(),
        ) else {
            return x;
        };
        let (from, to) = (&self.b.m.alts[src.index()], &self.b.m.alts[dst.index()]);
        let available = if x.own { from.borrowed } else { 3 };
        if (src == dst && (x.own || from.borrowed == 0))
            || (x.own && from.borrowed == to.borrowed)
            || from.std != ms_mir::types::Std::Result
            || to.std != ms_mir::types::Std::Result
            || from.name != to.name
            || from.cases != to.cases
            || to.borrowed & !available != 0
        {
            return x;
        }
        let borrowed = to.borrowed;
        let mode = if self.needs_drop(self.ret_ty) {
            Mode::Move
        } else {
            Mode::Borrow
        };
        let out = self.b.declare_var(self.ret_ty, mode);
        let held = self.b.declare_var(
            self.ty_of(x.v),
            if x.own { Mode::Move } else { Mode::Borrow },
        );
        self.b.def_var(held, x.v);
        let tag = self.b.alt_tag(x.v);
        let error = self.b.iconst(ms_mir::types::Std::ERROR as i64);
        let is_error = self.b.icmp(ms_mir::ir::Cc::Eq, tag, error);
        let (ok, err, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br_if(is_error, err, &[], ok, &[]);
        self.b.seal_block(ok);
        self.b.seal_block(err);
        for (block, case) in [
            (ok, ms_mir::types::Std::OK),
            (err, ms_mir::types::Std::ERROR),
        ] {
            self.enter(block);
            let cur = Val {
                v: self.b.use_var(held),
                own: x.own,
            };
            let v = if borrowed & (1 << case) != 0 {
                let payload = self.b.alt_get(src, case as u32, 0, cur.v);
                let v = self.b.alt_view(dst, case as u32, &[payload]);
                self.finish(cur);
                v
            } else {
                let payload = self.take_alt_field_through(src, case as u32, 0, cur);
                self.b.alt_new(dst, case as u32, &[payload])
            };
            self.b.def_var(out, v);
            self.b.br(join, &[]);
        }
        self.b.seal_block(join);
        self.enter(join);
        Val {
            v: self.b.use_var(out),
            own: true,
        }
    }

    // --------------------------------------------------------------- bodies

    fn lower_callable(&mut self, c: &Rc<Callable>) -> Result<(), Error> {
        // Inline/default frames must return to this declaration's file, even
        // when every surviving instruction originates in another module.
        self.b.func_mut().loc = self.loc(c.func.decl.decl().pos);
        let params = self.b.params();
        // The recursion check comes before the parameters are bound: a check that finds the
        // stack short re-invokes the function on a new segment with the caller's values, so
        // nothing the prologue owns (a cloned parameter, a closer) may precede it.
        self.counts_depth = true;
        self.b
            .emit(Op::DepthEnter, &[], ms_mir::ir::Imm::None, None);
        let bindings: Vec<BindingRef> = c
            .self_binding
            .iter()
            .chain(c.parameters.iter())
            .cloned()
            .collect();
        let vars = self.cx.var_positions(c);
        let owned_mask = self.variant.owned.then(|| self.cx.owned_mask(c)).flatten();
        if let ms_check::api::hir::Body::Block(stmts) = c.body() {
            self.slotted = crate::closure::slotted_in(self.syms, self, stmts);
            self.closing_fn = crate::closure::closes_resources(self, c, stmts);
            self.string_needed = crate::scalar::string_uses(self, stmts);
        }
        // Parameters the body changes are the callee's own copies.
        let mutated = match c.body() {
            ms_check::api::hir::Body::Block(stmts) => crate::mutation::mutated_locals(
                self.syms,
                &self.hir,
                ms_check::api::hir::Body::Block(stmts),
                &self.cx.callables,
                &self.cx.mutated,
            ),
            ms_check::api::hir::Body::Expr(_) => Default::default(),
        };
        // The borrowed instance (reached through an interface or a function value) of a function
        // that moves a parameter is the copying adapter for the borrowed signature: its copies
        // are the declared adaptation, not hidden ones.
        self.adapter = !self.variant.owned && self.cx.owned_mask(c).is_some();
        for (i, (b, v)) in bindings.iter().zip(params).enumerate() {
            if vars.contains(&i) {
                self.bind_var_parameter(b, v)?;
                continue;
            }
            if owned_mask.as_ref().is_some_and(|mask| mask[i]) && self.needs_drop(self.ty_of(v)) {
                // The caller handed the value over: the callee owns it and drops it at scope end.
                if self
                    .cx
                    .ownership
                    .binding_facts
                    .has(b.uid, ms_check::api::ownership::BindingFact::ImplicitClose)
                {
                    // A resource the callee keeps on some path closes on the others.
                    let cleanup = self.hir.binding_cleanup(b.uid);
                    if let Some(kind) = self.closer_opt(cleanup.as_ref(), &b.ty)? {
                        self.bind_closing_kind(b, Val { v, own: true }, kind)?;
                        continue;
                    }
                }
                let ty = self.ty_of(v);
                let var = self.b.declare_var(ty, Mode::Move);
                self.b.def_var(var, v);
                self.own_local(b.uid, var, ty);
                continue;
            }
            let own_copy = mutated.contains(&b.uid) && self.needs_drop(self.ty_of(v));
            if own_copy {
                // A parameter the body changes is the callee's own copy.
                let ty = self.ty_of(v);
                let var = self.b.declare_var(ty, Mode::Move);
                let o = self.owned(Val { v, own: false });
                self.b.def_var(var, o);
                self.own_local(b.uid, var, ty);
            } else {
                self.bind_borrowed(b, v);
                if !self.slotted.contains(&b.uid) {
                    self.borrowed_params.insert(b.uid);
                }
            }
        }
        if let Some(f) = &c.fixture {
            // The file's fixture arrives as the last parameter, changed in place.
            let v = *self.b.params().last().expect("fixture parameter");
            self.bind_var_parameter(f, v)?;
        }
        match c.body() {
            ms_check::api::hir::Body::Block(stmts) => {
                if let Some(first) = stmts.first() {
                    self.at(first.pos);
                }
                self.stmts(stmts)?;
                if !self.dead {
                    // Falling off the end returns Unit.
                    let u = self.b.unit();
                    let ret = self.ret_ty;
                    if let TyKind::Alt(a) = self.b.m.types.kind(ret).clone() {
                        // A test, or a `Unit!` function, that finishes returns `ok(unit)`.
                        let ok = self.b.m.alts[a.index()].ok_case().ok_or_else(|| {
                            Error::new("a test or Unit! function must return a Result")
                        })?;
                        let v = self.b.alt_new(a, ok as u32, &[u]);
                        self.emit_return(Some(Val { v, own: true }));
                        return Ok(());
                    }
                    if c.kind == CallableKind::Test {
                        return Err(Error::new("a test must return a Result"));
                    }
                    if ret != MTy::UNIT {
                        return Err(Error::new(format!(
                            "function {} can fall off its end",
                            self.syms.str(c.name)
                        )));
                    }
                    self.emit_return(Some(Val { v: u, own: false }));
                }
            }
            ms_check::api::hir::Body::Expr(e) => {
                let moved_before = self.closed_on_path.clone();
                let x = self.returned_expr(e)?;
                self.emit_return(Some(x));
                self.closed_on_path = moved_before;
            }
        }
        Ok(())
    }
}
