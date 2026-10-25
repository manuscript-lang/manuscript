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
    Consume,
}

/// An argument position of a source callable.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Slot {
    /// The receiver of a method.
    Receiver,
    /// A parameter, by label.
    Param(Name),
}

/// Where a call's result may come from: a read-only parameter whose part it returns.
#[derive(Clone, Default, PartialEq, Eq, Debug)]
pub struct ResultOrigin {
    /// The parameters a returned part belongs to.
    pub slots: Vec<Slot>,
    /// Every return is this one path of fields below a single parameter.
    pub plain: Option<(Slot, Vec<Name>)>,
    /// Some return gives back an owned value (an interface call, a closure call, or a call of
    /// a function that does): the result cannot be handed back as a borrow without a copy.
    pub owned: bool,
}

/// The modes of a source callable.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Summary {
    /// The receiver of a method.
    pub receiver: ParamMode,
    /// Parameters by label.
    pub params: Vec<(Name, ParamMode)>,
    /// What the result borrows from.
    pub result: ResultOrigin,
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
            result: ResultOrigin::default(),
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
    /// The call is a native method whose result is a borrowed projection of
    /// its receiver (`first`, `get`, ...).
    pub accessor: bool,
    /// The call mutates a collection and returns that same collection.
    pub returns_receiver: bool,
    /// A source or native callee that runs its function arguments immediately
    /// and does not keep them.
    pub callbacks_borrowed: bool,
    /// The source callee returns a part of these read-only arguments.
    pub origin: ResultOrigin,
}

/// Resolves the modes of a call from its callee.
pub fn call_modes(
    m: &ModuleHir,
    call: &Expr,
    args: &[Argument],
    summaries: &Summaries,
) -> CallModes {
    let slots = m.info(call).arguments.unwrap_or_default();
    let label = |i: usize| slots.get(i).map(|s| s.name);
    let borrow_all = |receiver: Option<ParamMode>| CallModes {
        receiver,
        arguments: vec![ParamMode::Borrow; args.len()],
        accessor: false,
        returns_receiver: false,
        callbacks_borrowed: true,
        origin: ResultOrigin::default(),
    };
    match m.resolution(call) {
        Resolution::Constructor { .. } => CallModes {
            arguments: vec![ParamMode::Consume; args.len()],
            ..borrow_all(None)
        },
        Resolution::Function(s) | Resolution::Constant(s) => {
            let source = s
                .native
                .as_str()
                .is_empty()
                .then_some(())
                .and(s.decl.as_ref());
            match source {
                Some(d) => {
                    let func = FuncRef::of_decl(d.clone());
                    from_summary(summaries, s.module, &func, args.len(), label, None)
                }
                None => {
                    // A native function keeps function arguments it is given, except the
                    // testing helpers, which run them at once.
                    let runs_now = s.module.as_str() == "@std/testing.ms";
                    let params = s.ty().params.clone();
                    CallModes {
                        arguments: (0..args.len())
                            .map(|i| {
                                let p = label(i).and_then(|l| params.iter().find(|p| p.name == l));
                                match p {
                                    // `share` stores its payload.
                                    Some(_) if s.native.as_str() == "shared/share" => {
                                        ParamMode::Consume
                                    }
                                    Some(p) if p.ty.kind == Kind::Function && !runs_now => {
                                        ParamMode::Consume
                                    }
                                    _ => ParamMode::Borrow,
                                }
                            })
                            .collect(),
                        callbacks_borrowed: runs_now,
                        ..borrow_all(None)
                    }
                }
            }
        }
        Resolution::Method(method) => method_modes(summaries, &method, args.len(), label),
        Resolution::Native(_) | Resolution::Local(_) | Resolution::Type(_) | Resolution::Value => {
            borrow_all(None)
        }
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
    let summary = summaries
        .get(&(module, func.id()))
        .cloned()
        .unwrap_or_else(|| Summary::declared(func));
    CallModes {
        receiver: receiver.map(|()| summary.receiver),
        arguments: (0..count)
            .map(|i| {
                label(i)
                    .and_then(|l| summary.param(l))
                    .unwrap_or(ParamMode::Borrow)
            })
            .collect(),
        accessor: false,
        returns_receiver: false,
        callbacks_borrowed: true,
        origin: summary.result,
    }
}

/// What a call through an interface hands back: a `ref` operation lends, as every
/// implementation does, from the receiver or any argument (the implementations may name their
/// parameters differently); any other operation returns an owned value.
fn contract_origin(declared: &Summary, func: &FuncRef) -> ResultOrigin {
    if !func.func().is_some_and(|f| f.result_ref) {
        return ResultOrigin {
            owned: true,
            ..ResultOrigin::default()
        };
    }
    let mut slots = vec![Slot::Receiver];
    slots.extend(declared.params.iter().map(|(name, _)| Slot::Param(*name)));
    ResultOrigin {
        slots,
        ..ResultOrigin::default()
    }
}

fn method_modes(
    summaries: &Summaries,
    method: &MethodRef,
    count: usize,
    label: impl Fn(usize) -> Option<Name>,
) -> CallModes {
    if method.native.as_str().is_empty() {
        let Some(func) = &method.decl else {
            return native_unknown(count);
        };
        return from_summary(summaries, method.module, func, count, label, Some(()));
    }
    if method.native == "contract" {
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
                    accessor: false,
                    returns_receiver: false,
                    callbacks_borrowed: false,
                    origin: contract_origin(&declared, func),
                }
            }
            None => native_unknown(count),
        };
    }
    native_method_modes(method, count, label)
}

/// How a method treats its receiver, for a method used as a value.
pub fn receiver_mode(summaries: &Summaries, method: &MethodRef) -> Option<ParamMode> {
    method_modes(summaries, method, 0, |_| None).receiver
}

fn native_unknown(count: usize) -> CallModes {
    CallModes {
        receiver: Some(ParamMode::Borrow),
        arguments: vec![ParamMode::Borrow; count],
        accessor: false,
        returns_receiver: false,
        callbacks_borrowed: false,
        origin: ResultOrigin::default(),
    }
}

/// Collections run their callbacks immediately; other natives may keep them.
fn runs_callbacks(receiver: &Ty) -> bool {
    receiver.is_std("List")
        || receiver.is_std("Map")
        || receiver.is_std("Set")
        || receiver.is_std("Optional")
        || receiver.is_std("Result")
        || receiver.is_std("String")
}

fn native_method_modes(
    method: &MethodRef,
    count: usize,
    label: impl Fn(usize) -> Option<Name>,
) -> CallModes {
    let receiver = &method.receiver;
    let mutator = collection_mutation(method);
    let callbacks_borrowed = runs_callbacks(receiver);
    let params = &method.ty.params;
    let arguments = (0..count)
        .map(|i| {
            let Some(p) = label(i).and_then(|l| params.iter().find(|p| p.name == l)) else {
                return ParamMode::Borrow;
            };
            if p.ty.kind == Kind::Function {
                return if callbacks_borrowed {
                    ParamMode::Borrow
                } else {
                    ParamMode::Consume
                };
            }
            // A mutator stores the elements it is given.
            let stored = p.ty.kind == Kind::Variable
                || same(&p.ty, receiver)
                || receiver.args.iter().any(|a| same(a, &p.ty));
            if (mutator && stored) || method.native.as_str() == "shared/put" {
                ParamMode::Consume
            } else {
                ParamMode::Borrow
            }
        })
        .collect();
    let result = method.ty.result_ty();
    // A native lends exactly when its standard-library declaration says so (`ref`), unless the
    // call gives a fallback (`o.get(default)`): the result is then an owned copy of either.
    let accessor = method
        .decl
        .as_ref()
        .and_then(|d| d.func())
        .is_some_and(|f| {
            f.result_ref
                && !(0..count).any(|i| {
                    label(i).is_some_and(|l| {
                        f.params
                            .iter()
                            .any(|p| p.default.is_some() && p.name.as_str() == l.as_str())
                    })
                })
        });
    CallModes {
        receiver: Some(if mutator {
            ParamMode::Mutate
        } else {
            ParamMode::Borrow
        }),
        arguments,
        accessor,
        returns_receiver: mutator && same(&result, receiver),
        callbacks_borrowed,
        origin: ResultOrigin::default(),
    }
}
