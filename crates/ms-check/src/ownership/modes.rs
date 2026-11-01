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

/// The modes of a source callable.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Summary {
    /// The receiver of a method.
    pub receiver: ParamMode,
    /// Parameters by label.
    pub params: Vec<(Name, ParamMode)>,
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
        returns_receiver: false,
        callbacks_borrowed: true,
        retained: Vec::new(),
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
                    // A native runs the function arguments it is given before it returns,
                    // unless it is one of the externs that keep them.
                    let runs_now = !crate::stdlib::keeps_callbacks(s.native.as_str());
                    let params = s.ty().params.clone();
                    CallModes {
                        arguments: (0..args.len())
                            .map(|i| {
                                let p = label(i).and_then(|l| params.iter().find(|p| p.name == l));
                                match p {
                                    Some(p) if p.ty.kind == Kind::Function && !runs_now => {
                                        ParamMode::Consume
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
                    returns_receiver: false,
                    callbacks_borrowed: false,
                    retained: Vec::new(),
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
        returns_receiver: false,
        callbacks_borrowed: false,
        retained: Vec::new(),
    }
}

fn native_method_modes(
    method: &MethodRef,
    count: usize,
    label: impl Fn(usize) -> Option<Name>,
) -> CallModes {
    let receiver = &method.receiver;
    let mutator = collection_mutation(method);
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
                Some(inner) if p.ty.is_std("Optional") => inner,
                _ => &p.ty,
            };
            let stored = p.ty.kind == Kind::Variable
                || same(&p.ty, receiver)
                || receiver.args.iter().any(|a| same(a, &p.ty));
            let value = held.kind == Kind::Variable
                || same(held, &result)
                || receiver.args.iter().any(|a| same(a, held));
            retained[i] = (mutator && stored) || value;
            if p.ty.kind == Kind::Function {
                return if callbacks_borrowed {
                    ParamMode::Borrow
                } else {
                    ParamMode::Consume
                };
            }
            if mutator && stored {
                ParamMode::Consume
            } else {
                ParamMode::Borrow
            }
        })
        .collect();
    CallModes {
        receiver: Some(if mutator {
            ParamMode::Mutate
        } else if crate::effects::is_text_builder(receiver)
            && method.name().is_some_and(|n| n.as_str() == "build")
        {
            ParamMode::Consume
        } else {
            ParamMode::Borrow
        }),
        arguments,
        returns_receiver: mutator && same(&result, receiver),
        callbacks_borrowed,
        retained,
    }
}
