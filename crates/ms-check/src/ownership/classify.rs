//! Value classes: how a value of a type moves.

use crate::checker::Program;
use crate::types::*;
use std::collections::HashSet;

/// How values of a type are passed around.
#[derive(Copy, Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Class {
    /// Duplicated implicitly: scalars, records of those,
    /// and handle types whose identity is shared (native handles and `Shared[T]`).
    Copy,
    /// One owner. Moves at its last use into a consuming position; `.clone()`
    /// duplicates it explicitly. Strings, lists, maps, sets, bytes, records and
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

    fn class_in(&self, t: &Ty, visiting: &mut Vec<String>) -> Class {
        match t.kind {
            Kind::Primitive if t.id.as_str() == "String" => Class::Move,
            Kind::Primitive => Class::Copy,
            Kind::Variable => {
                if t.bounds().iter().any(|b| b.is_std("Closeable")) {
                    Class::Resource
                } else {
                    Class::Move
                }
            }
            // A `Closeable` value owns what it was made from and closes it. Other interfaces
            // with a `close` (a channel's transport) are handles their holders close explicitly.
            Kind::Contract if t.is_std("Closeable") => Class::Resource,
            Kind::Function | Kind::Contract => Class::Move,
            Kind::Native => self.native(t, visiting),
            Kind::Record | Kind::Alternative => self.nominal(t, visiting),
        }
    }

    fn native(&self, t: &Ty, visiting: &mut Vec<String>) -> Class {
        if self.closeable.contains(&t.id) {
            Class::Resource
        } else if t.is_std("Shared") {
            // Copying shares the box; the payload is closed once the last holder releases it.
            Class::Copy
        } else if t.is_std("List") {
            // An owning collection of resources is itself a resource, closed with its elements.
            // A `Set` stays `Move`: a resource is not `Hashable`, so it is never an element.
            self.holds(t.args.first(), visiting)
        } else if t.is_std("Map") {
            self.holds(t.args.get(1), visiting)
        } else if t.is_std("Bytes") || t.is_std("HttpHeaders") || crate::effects::is_text_builder(t)
        {
            Class::Move
        } else {
            // Immutable value natives and shared handles.
            Class::Copy
        }
    }

    /// The class of a collection holding `element`: `Resource` when its elements are, else
    /// `Move`, so a collection of plain values stays as cheap as before.
    fn holds(&self, element: Option<&Ty>, visiting: &mut Vec<String>) -> Class {
        match element.map(|e| self.class_in(e, visiting)) {
            Some(Class::Resource) => Class::Resource,
            _ => Class::Move,
        }
    }

    fn nominal(&self, t: &Ty, visiting: &mut Vec<String>) -> Class {
        if self.closeable.contains(&t.id) {
            return Class::Resource;
        }
        // Keyed by the instance, so `Door??` looks inside its payload; a
        // generic type that grows without bound is cut off as boxed.
        let key = t.to_string();
        if visiting.contains(&key) || visiting.len() > 64 {
            // A type containing itself is boxed: it cannot be copied implicitly.
            return Class::Move;
        }
        visiting.push(key);
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
        // A value holding a borrow is never copied implicitly: the copy would hold nothing.
        if borrows(t) {
            class = class.max(Class::Move);
        }
        // A recursive alternative or record reached its own id above and
        // returned Move, which max propagates.
        class
    }
}

/// Whether the interface `t` declares a `close` operation.
pub(crate) fn declares_close(t: &Ty) -> bool {
    t.def.as_ref().is_some_and(|d| {
        d.operations
            .borrow()
            .iter()
            .any(|o| o.name.as_str() == "close")
    })
}
