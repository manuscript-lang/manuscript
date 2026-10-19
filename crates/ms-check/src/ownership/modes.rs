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
}

/// Resolves the modes of a call from its callee.
pub fn call_modes(
    m: &ModuleHir,
    call: &Expr,
    args: &[Argument],
    summaries: &HashMap<Key, Summary>,
) -> CallModes {
    let slots = m.info(call).arguments.unwrap_or_default();
    let label = |i: usize| slots.get(i).map(|s| s.name);
    let borrow_all = |receiver: Option<ParamMode>| CallModes {
        receiver,
        arguments: vec![ParamMode::Borrow; args.len()],
        accessor: false,
        returns_receiver: false,
        callbacks_borrowed: true,
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
                    // A native function keeps function arguments it is given.
                    let params = s.ty().params.clone();
                    CallModes {
                        arguments: (0..args.len())
                            .map(|i| {
                                let p = label(i).and_then(|l| params.iter().find(|p| p.name == l));
                                match p {
                                    Some(p) if p.ty.kind == Kind::Function => ParamMode::Consume,
                                    _ => ParamMode::Borrow,
                                }
                            })
                            .collect(),
                        callbacks_borrowed: false,
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
    summaries: &HashMap<Key, Summary>,
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
    }
}

fn method_modes(
    summaries: &HashMap<Key, Summary>,
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
                }
            }
            None => native_unknown(count),
        };
    }
    native_method_modes(method, count, label)
}

fn native_unknown(count: usize) -> CallModes {
    CallModes {
        receiver: Some(ParamMode::Borrow),
        arguments: vec![ParamMode::Borrow; count],
        accessor: false,
        returns_receiver: false,
        callbacks_borrowed: false,
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
    let name = method
        .name()
        .map(|n| n.as_str())
        .unwrap_or(method.native.as_str());
    let receiver = &method.receiver;
    let mutator = collection_mutation(receiver, name);
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
            if mutator && stored {
                ParamMode::Consume
            } else {
                ParamMode::Borrow
            }
        })
        .collect();
    let result = method.ty.result_ty();
    let element = |t: &Ty| receiver.args.iter().any(|a| same(a, t));
    let accessor = !mutator
        && receiver.kind != Kind::Primitive
        && (element(&result) || (result.is_std("Optional") && result.args.iter().any(element)));
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
    }
}
