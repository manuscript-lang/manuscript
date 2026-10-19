//! Value classes: how a value of a type moves.

use crate::checker::Program;
use crate::types::*;
use std::collections::HashSet;

/// How values of a type are passed around.
#[derive(Copy, Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Class {
    /// Duplicated implicitly: scalars, immutable strings, records of those,
    /// and handle types whose identity is shared (`Shared[T]`, native handles).
    Copy,
    /// One owner. Moves at its last use into a consuming position; `.copy()`
    /// duplicates it explicitly. Lists, maps, sets, bytes, records and
    /// alternatives holding any of those, recursive types, closures,
    /// interface values and unconstrained type parameters.
    Move,
    /// A unique resource (`Closeable`): moves, and cannot be copied.
    Resource,
}

/// Computes classes, caching nothing: types are small and shared.
pub struct Classifier {
    closeable: HashSet<Name>,
}

impl Classifier {
    /// A classifier for the types of one checked program.
    pub fn new(p: &Program) -> Classifier {
        let closeable = p
            .methods
            .iter()
            .filter(|m| m.contract.as_ref().is_some_and(|c| c.is_std("Closeable")))
            .map(|m| m.receiver.id)
            .collect();
        Classifier { closeable }
    }

    /// The class of values of `t`.
    pub fn class(&self, t: &Ty) -> Class {
        self.class_in(t, &mut Vec::new())
    }

    fn class_in(&self, t: &Ty, visiting: &mut Vec<Name>) -> Class {
        match t.kind {
            Kind::Primitive => Class::Copy,
            Kind::Variable => {
                if t.bounds().iter().any(|b| b.is_std("Closeable")) {
                    Class::Resource
                } else {
                    Class::Move
                }
            }
            Kind::Function | Kind::Contract => Class::Move,
            Kind::Native => self.native(t, visiting),
            Kind::Record | Kind::Alternative => self.nominal(t, visiting),
        }
    }

    fn native(&self, t: &Ty, visiting: &mut Vec<Name>) -> Class {
        if self.closeable.contains(&t.id) {
            Class::Resource
        } else if t.is_std("List") || t.is_std("Map") || t.is_std("Set") || t.is_std("Bytes") {
            Class::Move
        } else {
            // Immutable value natives and shared handles.
            let _ = visiting;
            Class::Copy
        }
    }

    fn nominal(&self, t: &Ty, visiting: &mut Vec<Name>) -> Class {
        if self.closeable.contains(&t.id) {
            return Class::Resource;
        }
        if visiting.contains(&t.id) {
            // A type containing itself is boxed: it cannot be copied implicitly.
            return Class::Move;
        }
        visiting.push(t.id);
        let mut class = Class::Copy;
        for f in fields(t) {
            class = class.max(self.class_in(&f.ty, visiting));
        }
        if let Some(def) = &t.def {
            let s = substitution(t);
            for case in def.cases.borrow().iter() {
                for f in &case.fields {
                    class = class.max(self.class_in(&sub(&f.ty, &s), visiting));
                }
            }
        }
        visiting.pop();
        // A recursive alternative or record reached its own id above and
        // returned Move, which max propagates.
        class
    }
}
