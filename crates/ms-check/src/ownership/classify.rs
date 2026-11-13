//! Value classes: how a value of a type moves.

use crate::checker::Program;
use crate::types::*;
use std::collections::HashSet;
use std::rc::Rc;
#[cfg(test)]
thread_local! {
    static CLASS_QUERIES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

/// Active nominal instances, borrowed for the duration of one classification.
struct Visiting<'a> {
    ty: &'a Ty,
    parent: Option<&'a Visiting<'a>>,
    depth: usize,
}

fn same_instance(a: &Ty, b: &Ty) -> bool {
    a.id == b.id
        && a.kind == b.kind
        && a.args.len() == b.args.len()
        && a.args
            .iter()
            .zip(&b.args)
            .all(|(a, b)| Rc::ptr_eq(a, b) || same(a, b))
}

/// How values of a type are passed around.
#[derive(Copy, Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Class {
    /// Duplicated implicitly: scalars, types of those,
    /// and handle types whose identity is shared (native handles).
    Copy,
    /// One owner. Moves at its last use into a moving position; `.clone()`
    /// duplicates it explicitly. Strings, lists, maps, sets, bytes, types and
    /// alternatives holding any of those, recursive types, closures,
    /// interface values and unconstrained type parameters.
    Move,
    /// A unique resource (`Closeable`): moves, and cannot be copied.
    Resource,
}

/// Computes value classes from declarations and contained values, reusing exact siblings locally.
pub struct Classifier {
    closeable: HashSet<Name>,
    /// Natives that are plain words (`Decimal`), so a copy is a bit copy.
    copyable: HashSet<Name>,
    /// Natives whose infallible `clone` is implemented in source (`List`, `BigInt`); one declared
    /// as a native operation (`Bytes`, `Set`) is found on the type's definition.
    clonable: HashSet<Name>,
}

impl Classifier {
    /// A classifier for the types of one checked program.
    pub fn new(p: &Program) -> Classifier {
        let syms = ms_syntax::Names::global();
        let mut closeable = HashSet::new();
        let mut copyable = HashSet::new();
        let mut clonable = HashSet::new();
        let mut clone_name = None;
        for method in &p.methods {
            if method.contract.is_some() && method.closes(syms) {
                closeable.insert(method.receiver.id);
            }
            if method.receiver.is(Builtin::Decimal) {
                copyable.insert(method.receiver.id);
            }
            if method.receiver.kind != Kind::Native {
                continue;
            }
            let Some(name) = method.name() else {
                continue;
            };
            if name == *clone_name.get_or_insert_with(|| n("clone"))
                && method.ty.result_ty().id == method.receiver.id
            {
                clonable.insert(method.receiver.id);
            }
        }
        Classifier {
            closeable,
            copyable,
            clonable,
        }
    }

    /// Whether `.clone()` duplicates values of `t`: every value but a resource, a native without
    /// a declared `clone`, or a type parameter without a bound that implies `Clonable`. The same
    /// rule as the contract checker's `Clonable` property, for the ownership pass, which has no
    /// contract checker.
    pub fn clonable(&self, syms: ms_syntax::Names, t: &Ty) -> bool {
        self.clonable_in(syms, t, &mut Vec::new(), false)
    }

    /// Whether the concrete type proves a copy is available without an erased payload check.
    /// Unlike `clonable`, this does not admit interfaces or unresolved type parameters.
    pub fn concretely_clonable(&self, syms: ms_syntax::Names, t: &Ty) -> bool {
        self.clonable_in(syms, t, &mut Vec::new(), true)
    }

    fn clonable_in(
        &self,
        syms: ms_syntax::Names,
        t: &Ty,
        seen: &mut Vec<Name>,
        concrete: bool,
    ) -> bool {
        if self.class(syms, t) == Class::Resource {
            return false;
        }
        match t.kind {
            Kind::Variable => !concrete && t.bounds.borrow().iter().any(implies_clonable),
            // An interface value's payload has a type the interface does not name; one over a
            // native without a `clone` (an `HttpExchange`) faults when copied, a guard the
            // runtime keeps until wrappers can borrow (middleware `Tap`s copy their exchange).
            Kind::Contract => !concrete && !t.is_std(syms, "Closeable"),
            // A function value owns its captures and has no `clone`, so a type holding one
            // cannot be duplicated (walk.rs `no_clone`).
            Kind::Function => false,
            Kind::Native => {
                (self.copyable.contains(&t.id)
                    || self.clonable.contains(&t.id)
                    || native_declares_clone(syms, t))
                    && t.args
                        .iter()
                        .all(|a| self.clonable_in(syms, a, seen, concrete))
            }
            Kind::Type | Kind::Alternative => {
                if seen.contains(&t.id) {
                    // The concrete proof conservatively excludes recurring nominal types:
                    // a repeated generic declaration may hide a different payload type.
                    return !concrete;
                }
                seen.push(t.id);
                let fields_ok = fields(t)
                    .iter()
                    .all(|f| self.clonable_in(syms, &f.ty, seen, concrete));
                let cases_ok = t.def.as_ref().is_none_or(|def| {
                    let cases = def.cases.borrow();
                    let mut remaining = cases.iter();
                    if remaining.find(|case| !case.fields.is_empty()).is_none() {
                        return true;
                    }
                    let first = cases.len() - remaining.len() - 1;
                    let s = substitution(t);
                    cases[first..].iter().all(|case| {
                        case.fields
                            .iter()
                            .all(|f| self.clonable_in(syms, &sub(&f.ty, &s), seen, concrete))
                    })
                });
                seen.pop();
                fields_ok && cases_ok
            }
            _ => true,
        }
    }

    /// Whether `t` has a `Closeable` implementation of its own, which runs on the whole value.
    pub fn closes_itself(&self, t: &Ty) -> bool {
        self.closeable.contains(&t.id)
    }

    /// The class of values of `t`.
    pub fn class(&self, syms: ms_syntax::Names, t: &Ty) -> Class {
        self.class_in(syms, t, None)
    }

    #[inline(always)]
    fn class_in(&self, syms: ms_syntax::Names, t: &Ty, visiting: Option<&Visiting<'_>>) -> Class {
        #[cfg(test)]
        CLASS_QUERIES.with(|queries| queries.set(queries.get() + 1));
        match t.kind {
            Kind::Primitive if t.is(Builtin::String) => Class::Move,
            Kind::Primitive | Kind::Invalid | Kind::Inferred => Class::Copy,
            Kind::Variable => {
                if t.bounds.borrow().iter().any(|b| b.is(Builtin::Closeable)) {
                    Class::Resource
                } else {
                    Class::Move
                }
            }
            // A `Closeable` value owns what it was made from and closes it. Other interfaces
            // with a `close` (a channel's transport) are handles their holders close explicitly.
            Kind::Contract if t.is(Builtin::Closeable) => Class::Resource,
            Kind::Function | Kind::Contract => Class::Move,
            Kind::Native => self.native(syms, t, visiting),
            Kind::Type | Kind::Alternative => self.nominal(syms, t, visiting),
        }
    }

    fn native(&self, syms: ms_syntax::Names, t: &Ty, visiting: Option<&Visiting<'_>>) -> Class {
        let mut current = t;
        let mut held = false;
        loop {
            if self.closeable.contains(&current.id) {
                return Class::Resource;
            }
            if self.copyable.contains(&current.id) {
                return if held { Class::Move } else { Class::Copy };
            }
            let element = if current.is(Builtin::List) {
                current.args.first()
            } else if current.is(Builtin::Map) {
                current.args.get(1)
            } else {
                return Class::Move;
            };
            let Some(element) = element else {
                return Class::Move;
            };
            if element.kind != Kind::Native {
                return match self.class_in(syms, element, visiting) {
                    Class::Resource => Class::Resource,
                    _ => Class::Move,
                };
            }
            // Each owning collection maps Copy and Move to Move. Repeating
            // that map needs no Rust call frame or extra nominal ancestry.
            #[cfg(test)]
            CLASS_QUERIES.with(|queries| queries.set(queries.get() + 1));
            current = element;
            held = true;
        }
    }

    // Keep the compound sibling path out of ordinary unary/scalar classifications.
    #[inline(never)]
    fn shared_fields(&self, syms: ms_syntax::Names, fs: &[Param], current: &Visiting<'_>) -> Class {
        let first = &fs[0].ty;
        let completed = self.class_in(syms, first, Some(current));
        let mut class = completed;
        for f in &fs[1..] {
            let next = if Rc::ptr_eq(first, &f.ty) {
                #[cfg(test)]
                CLASS_QUERIES.with(|queries| queries.set(queries.get() + 1));
                completed
            } else {
                self.class_in(syms, &f.ty, Some(current))
            };
            class = class.max(next);
        }
        class
    }

    #[inline(never)]
    fn nominal(&self, syms: ms_syntax::Names, t: &Ty, visiting: Option<&Visiting<'_>>) -> Class {
        if self.closeable.contains(&t.id) {
            return Class::Resource;
        }
        // Identity includes the arguments: `Door??` must reach its payload, while
        // same-spelled declarations from different modules are distinct types.
        // Do not render arguments just to track ancestry: shared phantom arguments
        // can have exponentially large display strings.
        let depth = visiting.map_or(0, |v| v.depth);
        if depth > 64 {
            // A type containing itself is boxed: it cannot be copied implicitly.
            return Class::Move;
        }
        let mut ancestor = visiting;
        while let Some(active) = ancestor {
            if same_instance(active.ty, t) {
                return Class::Move;
            }
            ancestor = active.parent;
        }
        let current = Visiting {
            ty: t,
            parent: visiting,
            depth: depth + 1,
        };
        // A type is a container of its fields and has one owner whatever they are; an
        // alternative of primitives is a primitive.
        let mut class = if t.kind == Kind::Type {
            Class::Move
        } else {
            Class::Copy
        };
        {
            let fs = fields(t);
            if fs.len() > 1 && matches!(fs[0].ty.kind, Kind::Type | Kind::Alternative) {
                // These fields have already been substituted independently. Within
                // this one frame, an identical child has the same ancestry and depth.
                class = class.max(self.shared_fields(syms, &fs, &current));
            } else {
                for f in &fs {
                    class = class.max(self.class_in(syms, &f.ty, Some(&current)));
                }
            }
        }
        if let Some(def) = &t.def {
            let cases = def.cases.borrow();
            let mut remaining = cases.iter();
            // Consume empty cases once. Actual payloads share one binding map,
            // while each occurrence still gets its own substitution and query.
            if remaining.find(|case| !case.fields.is_empty()).is_some() {
                let first = cases.len() - remaining.len() - 1;
                let s = substitution(t);
                for case in &cases[first..] {
                    for f in &case.fields {
                        class = class.max(self.class_in(syms, &sub(&f.ty, &s), Some(&current)));
                    }
                }
            }
        }
        // A recursive alternative or type reached its own id above and
        // returned Move, which max propagates.
        class
    }
}

/// Whether the interface `t` declares a `close` operation.
pub(crate) fn declares_close(syms: ms_syntax::Names, t: &Ty) -> bool {
    t.def.as_ref().is_some_and(|d| {
        d.operations
            .borrow()
            .iter()
            .any(|o| syms.str(o.name) == "close")
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    fn pair(syms: ms_syntax::Names) -> (SymRef, Ty) {
        let a = Rc::new(Type::new(syms, n("A"), n("test/Pair/A"), Kind::Variable));
        let b = Rc::new(Type::new(syms, n("B"), n("test/Pair/B"), Kind::Variable));
        let sym = Rc::new(Sym {
            name: n("Pair"),
            id: n("test/Pair"),
            kind: SymKind::Type,
            module: n("test.ms"),
            native: Native::Source,
            export: true,
            ty: RefCell::new(None),
            variables: RefCell::new(vec![]),
            decl: None,
        });
        let def = Definition::new(&sym, Kind::Type);
        *def.variables.borrow_mut() = vec![a.clone(), b.clone()];
        *def.fields.borrow_mut() = vec![Param::new(n("left"), a), Param::new(n("right"), b)];
        let mut ty = Type::new(syms, sym.name, sym.id, Kind::Type);
        ty.def = Some(def);
        (sym, Rc::new(ty))
    }

    fn instance(template: &Ty, left: Ty, right: Ty) -> Ty {
        let mut ty = (**template).clone();
        ty.args = vec![left, right];
        Rc::new(ty)
    }

    #[test]
    fn concrete_clones_do_not_assume_erased_payloads_are_clonable() {
        let syms = ms_syntax::Names::global();
        let classifier = Classifier::new(&Program::default());
        let interface = Rc::new(Type::new(
            syms,
            n("Readable"),
            n("test/Readable"),
            Kind::Contract,
        ));
        let (_, template) = pair(syms);
        let aggregate = instance(&template, int(), interface.clone());
        assert!(classifier.clonable(syms, &interface));
        assert!(classifier.clonable(syms, &aggregate));
        assert!(!classifier.concretely_clonable(syms, &interface));
        assert!(!classifier.concretely_clonable(syms, &aggregate));
        let nested = instance(&template, aggregate, int());
        assert!(!classifier.concretely_clonable(syms, &nested));
        assert!(classifier.concretely_clonable(syms, &instance(&template, int(), int())));
    }

    #[test]
    fn shared_pair_graph_needs_bounded_classification_work() {
        let syms = ms_syntax::Names::global();
        let (_sym, template) = pair(syms);
        let mut ty = int();
        for _ in 0..16 {
            ty = instance(&template, ty.clone(), ty);
        }
        let classifier = Classifier::new(&Program::default());
        CLASS_QUERIES.with(|queries| queries.set(0));
        assert_eq!(classifier.class(syms, &ty), Class::Move);
        let queries = CLASS_QUERIES.with(|queries| queries.get());
        assert!(
            queries <= 64,
            "shared pair graph required {queries} classifications"
        );
    }

    #[test]
    fn first_sibling_results_do_not_cross_instances_or_queries() {
        let syms = ms_syntax::Names::global();
        let (_sym, template) = pair(syms);
        let variable = Rc::new(Type::new(syms, n("T"), n("test/T"), Kind::Variable));
        let independent = Rc::new((*variable).clone());
        let plain = instance(&template, variable.clone(), int());
        let other = instance(&template, independent.clone(), int());
        let root = instance(&template, plain.clone(), other);
        let classifier = Classifier::new(&Program::default());
        assert_eq!(classifier.class(syms, &root), Class::Move);
        let closeable = Rc::new(Type::new(
            syms,
            n("Closeable"),
            n("@std/Closeable"),
            Kind::Contract,
        ));
        independent.bounds.borrow_mut().push(closeable);
        assert_eq!(classifier.class(syms, &root), Class::Resource);
        assert_eq!(classifier.class(syms, &plain), Class::Move);
        let shared = instance(&template, plain.clone(), plain);
        assert_eq!(classifier.class(syms, &shared), Class::Move);
        variable.bounds.borrow_mut().push(Rc::new(Type::new(
            syms,
            n("Closeable"),
            n("@std/Closeable"),
            Kind::Contract,
        )));
        assert_eq!(classifier.class(syms, &shared), Class::Resource);
    }

    #[test]
    fn deep_native_collections_visit_every_selected_node() {
        let syms = ms_syntax::Names::global();
        let resource = Rc::new(Type::new(
            syms,
            n("Closeable"),
            n("@std/Closeable"),
            Kind::Contract,
        ));
        let mut nodes = vec![resource];
        for _ in 0..2048 {
            let mut ty = Type::new(syms, n("List"), n("@std/List"), Kind::Native);
            ty.args.push(nodes.last().unwrap().clone());
            nodes.push(Rc::new(ty));
        }
        let classifier = Classifier::new(&Program::default());
        CLASS_QUERIES.with(|queries| queries.set(0));
        assert_eq!(
            classifier.class(syms, nodes.last().unwrap()),
            Class::Resource
        );
        assert_eq!(CLASS_QUERIES.with(|queries| queries.get()), nodes.len());
        while nodes.pop().is_some() {}
    }
}
