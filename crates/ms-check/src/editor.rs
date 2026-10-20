//! Editor queries over a checked program: the members a receiver offers and
//! the standard exports import completion may suggest.

use crate::checker::{CheckOptions, Checker};
use crate::contracts::native_method;
use crate::stdlib;
use crate::syntax::{FuncRef, ModuleData};
use crate::types::*;
use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::rc::Rc;

/// Whether a member is a field or a method.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum MemberKind {
    /// A record field (or a duration unit of `Int`).
    Field,
    /// A method resolved with the same rules as calls.
    Method,
}

/// A member of a receiver type.
#[derive(Clone)]
pub struct Member {
    /// Member name.
    pub name: Name,
    /// Field or method.
    pub kind: MemberKind,
    /// Field type or method signature.
    pub ty: Ty,
    /// The method's declaration, when it has source.
    pub declaration: Option<FuncRef>,
}

/// The fields and methods available on `receiver`, sorted by name. Local
/// extensions are included only when `module` names the asking module.
pub fn members(program: &crate::Program, receiver: &Ty, module: Option<Name>) -> Vec<Member> {
    stdlib::ensure_standard();
    let mut checker = Checker::new(&CheckOptions::default());
    checker.p.methods = program.methods.clone();
    if let Some(file) = module {
        checker.module = Some(Rc::new(ModuleData::empty(file)));
    }
    let mut candidates: BTreeSet<Name> = BTreeSet::new();
    candidates.insert(n("to_string"));
    if native_method(receiver, n("clone")).is_some() {
        candidates.insert(n("clone"));
    }
    let mut seen: Vec<Ty> = Vec::new();
    let mut collect = |t: &Ty, candidates: &mut BTreeSet<Name>| {
        let mut stack = vec![t.clone()];
        while let Some(t) = stack.pop() {
            if seen.iter().any(|s| Rc::ptr_eq(s, &t)) {
                continue;
            }
            seen.push(t.clone());
            if let Some(def) = &t.def {
                candidates.extend(def.operations.borrow().iter().map(|op| op.name));
            }
            stack.extend(t.bounds());
        }
    };
    collect(receiver, &mut candidates);
    candidates.extend(program.methods.iter().filter_map(|m| m.name()));
    if let Some(intrinsic) = stdlib::intrinsic_operations(receiver.id) {
        collect(&intrinsic, &mut candidates);
    }
    let mut result: Vec<Member> = Vec::new();
    let mut field_names: HashSet<Name> = HashSet::new();
    if receiver.kind == Kind::Record {
        for field in fields(receiver) {
            if field.name == n("to_string") {
                continue;
            }
            field_names.insert(field.name);
            result.push(Member {
                name: field.name,
                kind: MemberKind::Field,
                ty: field.ty,
                declaration: None,
            });
        }
    }
    if receiver.id == n("Int") {
        for unit in ["seconds", "milliseconds", "minutes"] {
            result.push(Member {
                name: n(unit),
                kind: MemberKind::Field,
                ty: standard("Duration", Vec::new()),
                declaration: None,
            });
        }
    }
    for name in candidates {
        if field_names.contains(&name) {
            continue;
        }
        let methods = checker.methods(receiver, name);
        if let [m] = methods.as_slice() {
            result.push(Member {
                name,
                kind: MemberKind::Method,
                ty: m.ty.clone(),
                declaration: m.decl.clone(),
            });
        }
    }
    result.sort_by(|a, b| a.name.as_str().cmp(b.name.as_str()));
    result
}

/// Every exported standard declaration by module path, sorted by name, for
/// import completion without introducing ambient names.
pub fn standard_export_inventory() -> BTreeMap<String, Vec<SymRef>> {
    stdlib::ensure_standard();
    let mut inventory = BTreeMap::new();
    for path in stdlib::standard_module_names() {
        let mut exports: Vec<SymRef> = stdlib::standard_exports(path)
            .into_values()
            .filter(|s| s.export)
            .collect();
        if exports.is_empty() {
            continue;
        }
        exports.sort_by(|a, b| a.name.as_str().cmp(b.name.as_str()));
        inventory.insert(path.to_string(), exports);
    }
    inventory
}

/// Every type name available without an import.
pub fn prelude_type_names() -> Vec<&'static str> {
    stdlib::PRIMITIVE_NAMES
        .iter()
        .chain(stdlib::STANDARD_PRELUDE_NAMES.iter())
        .copied()
        .collect()
}
