//! How a callee treats its receiver and arguments.

use crate::effects::collection_mutation;
use crate::hir::*;
use crate::syntax::*;
use crate::types::*;
use ms_syntax::ast::*;
use std::collections::HashMap;

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
}

impl std::ops::Deref for Summaries {
    type Target = HashMap<Key, Summary>;
    fn deref(&self) -> &Self::Target {
        &self.decls
    }
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
}

/// Resolves the modes of a call from its callee.
pub fn call_modes(
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
    };
    // `x.get()(7)`: the callee is itself a call, so this one calls its function value.
    let value_call = match &call.kind {
        ExprKind::Call { callee, .. } => !matches!(callee.kind, ExprKind::Member { .. }),
        _ => false,
    };
    match m.resolution(call) {
        Resolution::Constructor { .. } => CallModes {
            arguments: vec![ParamMode::Move; args.len()],
            ..borrow_all(None)
        },
        Resolution::Method(_) if value_call => function_value_modes(m, call, args.len(), label),
        Resolution::Function(s) | Resolution::Constant(s) => {
            let source = syms
                .str(s.native)
                .is_empty()
                .then_some(())
                .and(s.decl.as_ref());
            match source {
                Some(d) => {
                    let func = FuncRef::of_decl(d.clone());
                    from_summary(summaries, s.module, &func, args.len(), label, None)
                }
                None => {
                    // A native runs the function arguments it is given before it returns,
                    // unless it is one of the externs that keep them. A user extern's shim may
                    // keep its functions with ms_fn_retain.
                    let user_extern = syms.str(s.native).starts_with("extern:")
                        && !syms.str(s.module).starts_with("@std/");
                    let runs_now =
                        !user_extern && !crate::stdlib::keeps_callbacks(syms.str(s.native));
                    let params = s.ty(syms).params.clone();
                    CallModes {
                        arguments: (0..args.len())
                            .map(|i| {
                                let p = label(i).and_then(|l| params.iter().find(|p| p.name == l));
                                match p {
                                    Some(p)
                                        if syms.str(p.name) == "value"
                                            && crate::stdlib::owns_value(syms.str(s.native)) =>
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
pub fn result_borrow(
    syms: ms_syntax::Names,
    m: &ModuleHir,
    call: &Expr,
    summaries: &Summaries,
) -> ResultBorrow {
    match m.resolution(call) {
        Resolution::Function(s) | Resolution::Constant(s) => {
            if !syms.str(s.native).is_empty() {
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
            if !syms.str(method.native).is_empty() {
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
    CallModes {
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
    if syms.str(method.native).is_empty() {
        let Some(func) = &method.decl else {
            return native_unknown(count);
        };
        return from_summary(summaries, method.module, func, count, label, Some(()));
    }
    if syms.str(method.native) == "contract" {
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
                }
            }
            None => native_unknown(count),
        };
    }
    native_method_modes(syms, method, count, label)
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
    }
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
        } else if crate::effects::is_text_builder(syms, receiver)
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
    }
}
