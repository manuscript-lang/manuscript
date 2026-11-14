//! How a callee treats its receiver and arguments.

use crate::fxmap::{HashMap, HashSet};
use crate::hir::*;
use crate::std_ops::{collection_mutation, is_text_builder};
use crate::syntax::*;
use crate::types::*;
use ms_syntax::Pos;
use ms_syntax::ast::*;

/// What a callable does with a value it is given.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum ParamMode {
    /// Reads it; the caller keeps ownership.
    Borrow,
    /// Changes it in place (`var`); the caller marks the argument `var`.
    Mutate,
    /// Takes ownership: the argument moves in.
    Move,
}

/// Where a callable's result comes from.
#[derive(Clone, PartialEq, Eq, Debug, Default)]
pub struct ResultBorrow {
    /// Every return path yields a part of the receiver or of a parameter, so the result is a
    /// reference into those arguments: the caller holds it as a borrow of them.
    pub returns_borrow: bool,
    /// The result is an owned interface view of the sources (a borrowed value converted to an
    /// interface on the way out): lowering returns an owned value the caller drops, and the
    /// caller still holds the sources. A path returning a new value is allowed beside it.
    pub view: bool,
    /// The receiver is a source.
    pub receiver: bool,
    /// The parameters that are sources, by label.
    pub params: Vec<Name>,
    /// Every path yields the same chain of fields of one source (`return self.items`): a `var`
    /// binding of the call is an exclusive borrow of that place. The source is a parameter by
    /// label, or the receiver.
    pub path: Option<(Option<Name>, Vec<Name>)>,
    /// A `Result` whose cases in this mask (`BORROWED_OK`, `BORROWED_ERROR`) lend their payload from
    /// the sources while the other cases are owned. With `returns_borrow` and `view`: the
    /// caller holds the sources and drops only the owned cases.
    pub borrowed_cases: u8,
}

/// The `ok` case of a `Result` in `ResultBorrow::borrowed_cases`.
pub const BORROWED_OK: u8 = 1;
/// The `error` case of a `Result` in `ResultBorrow::borrowed_cases`.
pub const BORROWED_ERROR: u8 = 2;

impl ResultBorrow {
    /// The optimistic start of the fixpoint: a body not yet walked may borrow from everything.
    /// Walking withdraws sources that are not returned and the claim when any path owns.
    fn optimistic(params: &[ms_syntax::ast::Param]) -> ResultBorrow {
        ResultBorrow {
            returns_borrow: true,
            view: false,
            receiver: true,
            params: params.iter().map(|p| p.name).collect(),
            path: None,
            borrowed_cases: 0,
        }
    }
}

/// The modes of a source callable.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Summary {
    /// The receiver of a method.
    pub receiver: ParamMode,
    /// Parameters by label.
    pub params: Vec<(Name, ParamMode)>,
    /// Where the body consumes each parameter (aligned with `params`).
    pub consumed_at: Vec<Option<Pos>>,
    /// Where the result comes from.
    pub result: ResultBorrow,
}

impl Summary {
    /// The mode declared in source: `var` is `Mutate`, anything else borrows.
    pub fn declared(f: &FuncRef) -> Summary {
        let (params, mutating): (&[ms_syntax::ast::Param], bool) = match (f.method(), f.func()) {
            (Some(m), _) => (&m.func.params, m.mutating),
            (None, Some(func)) => (&func.params, false),
            (None, None) => (&[], false),
        };
        Summary {
            receiver: if mutating {
                ParamMode::Mutate
            } else {
                ParamMode::Borrow
            },
            params: params
                .iter()
                .map(|p| {
                    (
                        p.name,
                        if p.mutable {
                            ParamMode::Mutate
                        } else {
                            ParamMode::Borrow
                        },
                    )
                })
                .collect(),
            consumed_at: Vec::new(),
            result: ResultBorrow::optimistic(params),
        }
    }

    fn param(&self, name: Name) -> Option<ParamMode> {
        self.params
            .iter()
            .find(|(n, _)| *n == name)
            .map(|(_, m)| *m)
    }
}

/// Identity of a source callable: its module file and declaration or method node.
pub type Key = (Name, NodeId);

/// The summaries of every source callable, and what each interface operation may hand back.
#[derive(Default)]
pub struct Summaries {
    pub decls: HashMap<Key, Summary>,
    /// The keys read since the last `take_reads`, so the fixpoint re-analyzes a callable only when
    /// a summary it read changed.
    reads: std::cell::RefCell<HashSet<Key>>,
}

impl Summaries {
    /// The summary of `key`, recording that the caller depends on it (present or not).
    pub fn get(&self, key: &Key) -> Option<&Summary> {
        self.reads.borrow_mut().insert(*key);
        self.decls.get(key)
    }

    /// The keys read since the previous call.
    pub fn take_reads(&self) -> HashSet<Key> {
        std::mem::take(&mut *self.reads.borrow_mut())
    }
}

impl std::ops::Deref for Summaries {
    type Target = HashMap<Key, Summary>;
    fn deref(&self) -> &Self::Target {
        &self.decls
    }
}

/// Where a source callee consumes one of its parameters.
#[derive(Clone, Copy, Debug)]
pub struct Consumed {
    /// The parameter's label.
    pub param: Name,
    /// The callee's module file.
    pub file: Name,
    /// The consuming expression in the callee's body.
    pub at: Pos,
}

/// The modes of one call.
#[derive(Clone, Debug)]
pub struct CallModes {
    /// The receiver, for a method call.
    pub receiver: Option<ParamMode>,
    /// Each written argument.
    pub arguments: Vec<ParamMode>,
    /// The call mutates a collection and returns that same collection.
    pub returns_receiver: bool,
    /// A source or native callee that runs its function arguments immediately
    /// and does not keep them.
    pub callbacks_borrowed: bool,
    /// Each written argument a native keeps or hands back in its result even though it takes the
    /// parameter as a borrow (`o.get(default)`, `xs.fold(initial, ..)`, a stored element): a
    /// function written there escapes.
    pub retained: Vec<bool>,
    /// Each written argument a source callee consumes: the callee, its parameter and where its
    /// body consumes it, for the diagnostic of a call that moves a variable it uses again.
    pub consumed_by: Vec<Option<Consumed>>,
}

/// Whether the method takes a callback that may change a parameter holding one of the
/// receiver's elements (`fn(var T)` on `List[T]`).
pub fn takes_element_mutator(method: &MethodRef) -> bool {
    method.ty.params.iter().any(|d| {
        d.ty.kind == Kind::Function
            && d.ty
                .params
                .iter()
                .any(|p| p.mutable && method.receiver.args.iter().any(|t| same(t, &p.ty)))
    })
}

/// Whether a callback argument of the method call changes a parameter that holds one of the
/// receiver's elements: the callee's declared callback type has a `var` position whose type is a
/// type argument of the receiver (`fn(var T)` on `List[T]`), and the argument itself takes that
/// parameter as `var`. A function that only reads it was converted to the declared type
/// (`Info.function_source`) and changes nothing.
fn callback_changes_receiver(m: &ModuleHir, call: &Expr, args: &[Argument]) -> bool {
    let Resolution::Method(method) = m.resolution(call) else {
        return false;
    };
    let slots = m.info(call).arguments.clone().unwrap_or_default();
    args.iter().enumerate().any(|(i, a)| {
        let Some(declared) = slots
            .get(i)
            .and_then(|s| method.ty.params.iter().find(|p| p.name == s.name))
        else {
            return false;
        };
        if declared.ty.kind != Kind::Function || m.info(&a.value).function_source.is_some() {
            return false;
        }
        let given = m.ty(&a.value);
        declared.ty.params.iter().enumerate().any(|(j, p)| {
            p.mutable
                && given.params.get(j).is_some_and(|g| g.mutable)
                && method.receiver.args.iter().any(|t| same(t, &p.ty))
        })
    })
}

/// Type application specializes a callable without creating a reusable method
/// value. Runtime indexing must remain an evaluated callee expression.
pub fn method_callee<'e>(syms: ms_syntax::Names, m: &ModuleHir, e: &'e Expr) -> &'e Expr {
    match &e.kind {
        ExprKind::Apply { left, .. } if m.info(e).native_str(syms) != "index" => left,
        _ => e,
    }
}

/// Resolves the modes of a call from its callee.
pub fn call_modes(
    syms: ms_syntax::Names,
    m: &ModuleHir,
    call: &Expr,
    args: &[Argument],
    summaries: &Summaries,
) -> CallModes {
    let mut modes = call_modes_declared(syms, m, call, args, summaries);
    if modes.receiver.is_some() && callback_changes_receiver(m, call, args) {
        modes.receiver = Some(ParamMode::Mutate);
    }
    modes
}

fn call_modes_declared(
    syms: ms_syntax::Names,
    m: &ModuleHir,
    call: &Expr,
    args: &[Argument],
    summaries: &Summaries,
) -> CallModes {
    let slots = m.info(call).arguments.clone().unwrap_or_default();
    let label = |i: usize| slots.get(i).map(|s| s.name);
    let borrow_all = |receiver: Option<ParamMode>| CallModes {
        receiver,
        arguments: vec![ParamMode::Borrow; args.len()],
        returns_receiver: false,
        callbacks_borrowed: true,
        retained: Vec::new(),
        consumed_by: Vec::new(),
    };
    // `x.get()(7)`: the callee is itself a call, so this one calls its function value.
    let value_call = match &call.kind {
        ExprKind::Call { callee, .. } => {
            !matches!(method_callee(syms, m, callee).kind, ExprKind::Member { .. })
        }
        _ => false,
    };
    match m.resolution(call) {
        Resolution::Constructor { .. } => CallModes {
            arguments: vec![ParamMode::Move; args.len()],
            ..borrow_all(None)
        },
        Resolution::Method(_) if value_call => function_value_modes(m, call, args.len(), label),
        Resolution::Function(s) | Resolution::Constant(s) => {
            let source = (s.native == Native::Source)
                .then_some(())
                .and(s.decl.as_ref());
            match source {
                Some(d) => {
                    let func = FuncRef::of_decl(d.clone());
                    from_summary(summaries, s.module, &func, args.len(), label, None)
                }
                None => {
                    // A native runs the function arguments it is given before it returns,
                    // unless it is a runtime function that declares it keeps them. A user extern's
                    // shim may keep its functions with ms_fn_retain.
                    let runtime = match s.native {
                        Native::Extern { symbol, bundled } => bundled.then(|| syms.str(symbol)),
                        _ => None,
                    };
                    let runs_now = match s.native {
                        Native::Extern { bundled, .. } => {
                            bundled && !runtime.is_some_and(crate::stdlib::keeps_callbacks)
                        }
                        _ => true,
                    };
                    let params = s.ty(syms).params.clone();
                    CallModes {
                        arguments: (0..args.len())
                            .map(|i| {
                                let p = label(i).and_then(|l| params.iter().find(|p| p.name == l));
                                match p {
                                    Some(p)
                                        if runtime.is_some_and(|r| {
                                            crate::stdlib::takes_argument(r, syms.str(p.name))
                                        }) =>
                                    {
                                        ParamMode::Move
                                    }
                                    Some(p) if p.ty.kind == Kind::Function && !runs_now => {
                                        ParamMode::Move
                                    }
                                    _ => ParamMode::Borrow,
                                }
                            })
                            .collect(),
                        callbacks_borrowed: runs_now,
                        retained: Vec::new(),
                        consumed_by: Vec::new(),
                        ..borrow_all(None)
                    }
                }
            }
        }
        Resolution::Method(method) => method_modes(syms, summaries, &method, args.len(), label),
        Resolution::Local(_) | Resolution::Value => {
            function_value_modes(m, call, args.len(), label)
        }
        Resolution::Native(_) | Resolution::Type(_) => borrow_all(None),
    }
}

/// The modes of a call through a function value: its type says which parameters it changes
/// (`fn(var List[Int]) Unit`); the rest it borrows.
fn function_value_modes(
    m: &ModuleHir,
    call: &Expr,
    count: usize,
    label: impl Fn(usize) -> Option<Name>,
) -> CallModes {
    let borrow_all = CallModes {
        receiver: None,
        arguments: vec![ParamMode::Borrow; count],
        returns_receiver: false,
        callbacks_borrowed: true,
        retained: Vec::new(),
        consumed_by: Vec::new(),
    };
    let ExprKind::Call { callee, .. } = &call.kind else {
        return borrow_all;
    };
    let fty = m.ty(callee);
    if fty.kind != Kind::Function {
        return borrow_all;
    }
    CallModes {
        arguments: (0..count)
            .map(|i| {
                let p = label(i)
                    .and_then(|l| fty.params.iter().find(|p| p.name == l))
                    .or_else(|| fty.params.get(i));
                match p {
                    Some(p) if p.mutable => ParamMode::Mutate,
                    _ => ParamMode::Borrow,
                }
            })
            .collect(),
        ..borrow_all
    }
}

/// Where the result of `call` comes from: a source callable's inferred borrow result, or nothing for
/// a native, an interface operation, a constructor or a function value, whose results own.
pub fn result_borrow(m: &ModuleHir, call: &Expr, summaries: &Summaries) -> ResultBorrow {
    match m.resolution(call) {
        Resolution::Function(s) | Resolution::Constant(s) => {
            if s.native != Native::Source {
                return ResultBorrow::default();
            }
            let Some(d) = s.decl.as_ref() else {
                return ResultBorrow::default();
            };
            let func = FuncRef::of_decl(d.clone());
            summaries
                .get(&(s.module, func.id()))
                .map(|k| k.result.clone())
                .unwrap_or_else(|| Summary::declared(&func).result)
        }
        Resolution::Method(method) => {
            if method.native != Native::Source {
                return ResultBorrow::default();
            }
            let Some(func) = &method.decl else {
                return ResultBorrow::default();
            };
            summaries
                .get(&(method.module, func.id()))
                .map(|k| k.result.clone())
                .unwrap_or_else(|| Summary::declared(func).result)
        }
        _ => ResultBorrow::default(),
    }
}

fn from_summary(
    summaries: &Summaries,
    module: Name,
    func: &FuncRef,
    count: usize,
    label: impl Fn(usize) -> Option<Name>,
    receiver: Option<()>,
) -> CallModes {
    let known = summaries.get(&(module, func.id())).cloned();
    let summary = known.unwrap_or_else(|| Summary::declared(func));
    // Most callees consume no parameter, so the per-argument table is built only for those that do.
    let consumed_by = if summary.consumed_at.iter().any(Option::is_some) {
        (0..count)
            .map(|i| {
                let param = label(i)?;
                let index = summary.params.iter().position(|(n, _)| *n == param)?;
                let at = summary.consumed_at.get(index).copied().flatten()?;
                Some(Consumed {
                    param,
                    file: module,
                    at,
                })
            })
            .collect()
    } else {
        Vec::new()
    };
    CallModes {
        consumed_by,
        receiver: receiver.map(|()| summary.receiver),
        arguments: (0..count)
            .map(|i| {
                label(i)
                    .and_then(|l| summary.param(l))
                    .unwrap_or(ParamMode::Borrow)
            })
            .collect(),
        returns_receiver: false,
        callbacks_borrowed: true,
        retained: Vec::new(),
    }
}

fn method_modes(
    syms: ms_syntax::Names,
    summaries: &Summaries,
    method: &MethodRef,
    count: usize,
    label: impl Fn(usize) -> Option<Name>,
) -> CallModes {
    if method.native == Native::Source {
        let Some(func) = &method.decl else {
            return native_unknown(count);
        };
        return from_summary(summaries, method.module, func, count, label, Some(()));
    }
    if method.native == Native::Contract {
        // Dynamic dispatch uses the interface's declared modes.
        return match &method.decl {
            Some(func) => {
                let declared = Summary::declared(func);
                CallModes {
                    receiver: Some(declared.receiver),
                    arguments: (0..count)
                        .map(|i| {
                            label(i)
                                .and_then(|l| declared.param(l))
                                .unwrap_or(ParamMode::Borrow)
                        })
                        .collect(),
                    returns_receiver: false,
                    callbacks_borrowed: false,
                    retained: Vec::new(),
                    consumed_by: Vec::new(),
                }
            }
            None => native_unknown(count),
        };
    }
    native_method_modes(syms, method, count, label)
}

/// The payload a checked native wrapper operation passes through unchanged: the first type
/// argument of the wrapper (`T?`, `T!E`) that the declared result mentions. It is read from the
/// declaration, so a new operation (`Result.get`, `Result.err`) cannot be left off a name list.
/// A callback's own type parameter (`map[U]`) is not an argument of the wrapper, so values the
/// callback creates do not imply passthrough.
pub fn wrapper_passthrough(method: &MethodRef, receiver: &Ty) -> Option<Ty> {
    // A contract operation (`clone`, `equals`) makes a new value; it does not hand out the payload.
    if method.contract.is_some()
        || !(method.receiver.is(Builtin::Optional) || method.receiver.is(Builtin::Result))
    {
        return None;
    }
    // The wrapper's operations are folded into its enum declaration (`Optional[T]`, `Result[T, E]`).
    let decl = method.decl.as_ref()?;
    let result = &decl.func()?.result;
    let params = decl.decl.type_params();
    if params.len() != method.receiver.args.len() {
        return None;
    }
    let index = params
        .iter()
        .position(|p| written_mentions(result, p.name))?;
    receiver.args.get(index).cloned()
}

/// The element a method value of a read-only collection operation hands out on each call: the
/// declared result is a receiver type parameter, or an optional of one (`Map.get`, `List.first`,
/// `List.get`). The direct call returns a borrow of the entry; a function value returns an owned
/// value, so it copies the element. Operations that change the receiver (`pop`) move the element
/// out instead, and an operation that returns a new collection clones through its own bound.
pub fn element_handed_out(syms: ms_syntax::Names, method: &MethodRef, receiver: &Ty) -> Option<Ty> {
    let collection = method.receiver.is(Builtin::List)
        || method.receiver.is(Builtin::Map)
        || method.receiver.is(Builtin::Set);
    if !collection || collection_mutation(syms, method) {
        return None;
    }
    let decl = method.decl.as_ref()?;
    let params = decl.decl.type_params();
    if params.len() != method.receiver.args.len() {
        return None;
    }
    let mut result = &decl.func()?.result;
    // `T?` is written as a one-argument named type around the parameter.
    if let TypeKind::Named { args, .. } = &result.kind
        && let [inner] = args.as_slice()
    {
        result = inner;
    }
    let TypeKind::Named { name, args } = &result.kind else {
        return None;
    };
    if !args.is_empty() {
        return None;
    }
    let index = params.iter().position(|p| p.name == *name)?;
    receiver.args.get(index).cloned()
}

/// Whether the written type `t` names `name` anywhere.
fn written_mentions(t: &TypeRef, name: ms_syntax::Symbol) -> bool {
    match &t.kind {
        TypeKind::Named { name: n, args } => {
            *n == name || args.iter().any(|a| written_mentions(a, name))
        }
        TypeKind::Fn { params, result } => {
            params
                .iter()
                .any(|p| p.ty.as_ref().is_some_and(|t| written_mentions(t, name)))
                || written_mentions(result, name)
        }
    }
}

/// How a method treats its receiver, for a method used as a value.
pub fn receiver_mode(
    syms: ms_syntax::Names,
    summaries: &Summaries,
    method: &MethodRef,
) -> Option<ParamMode> {
    method_modes(syms, summaries, method, 0, |_| None).receiver
}

fn native_unknown(count: usize) -> CallModes {
    CallModes {
        receiver: Some(ParamMode::Borrow),
        arguments: vec![ParamMode::Borrow; count],
        returns_receiver: false,
        callbacks_borrowed: false,
        retained: Vec::new(),
        consumed_by: Vec::new(),
    }
}

/// Declared native parameters consumed by an implementation, before callable adaptation.
/// Parameter order excludes the receiver and matches `method.ty.params`.
pub fn native_method_argument_modes(syms: ms_syntax::Names, method: &MethodRef) -> Vec<ParamMode> {
    native_method_modes(syms, method, method.ty.params.len(), |i| {
        Some(method.ty.params[i].name)
    })
    .arguments
}

fn native_method_modes(
    syms: ms_syntax::Names,
    method: &MethodRef,
    count: usize,
    label: impl Fn(usize) -> Option<Name>,
) -> CallModes {
    let receiver = &method.receiver;
    let mutator = collection_mutation(syms, method);
    // A native method runs its callbacks before it returns.
    let callbacks_borrowed = true;
    let params = &method.ty.params;
    let result = method.ty.result_ty();
    let mut retained = vec![false; count];
    let arguments = (0..count)
        .map(|i| {
            let Some(p) = label(i).and_then(|l| params.iter().find(|p| p.name == l)) else {
                return ParamMode::Borrow;
            };
            // An element a mutator stores, or a value of the receiver's or result's type.
            // An optional parameter (`default: T?`) holds a `T`.
            let held = match p.ty.args.first() {
                Some(inner) if p.ty.is(Builtin::Optional) => inner,
                _ => &p.ty,
            };
            let stored = p.ty.kind == Kind::Variable
                || same(&p.ty, receiver)
                || receiver.args.iter().any(|a| same(a, &p.ty));
            let value = held.kind == Kind::Variable
                || same(held, &result)
                || receiver.args.iter().any(|a| same(a, held));
            retained[i] = (mutator && stored) || value;
            // An element the mutator stores is owned by the collection, a function value
            // included; a callback the native runs and drops is only borrowed.
            if mutator && stored {
                return ParamMode::Move;
            }
            if p.ty.kind == Kind::Function && !callbacks_borrowed {
                return ParamMode::Move;
            }
            ParamMode::Borrow
        })
        .collect();
    CallModes {
        receiver: Some(if mutator {
            ParamMode::Mutate
        } else if is_text_builder(syms, receiver)
            && method.name().is_some_and(|n| syms.str(n) == "build")
        {
            ParamMode::Move
        } else {
            ParamMode::Borrow
        }),
        arguments,
        returns_receiver: mutator && same(&result, receiver),
        callbacks_borrowed,
        retained,
        consumed_by: Vec::new(),
    }
}
