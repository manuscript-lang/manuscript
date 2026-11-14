//! Implementations, contracts and their evidence.

use crate::checker::{Checker, Scope};
use crate::fxmap::{HashMap, HashSet};
use crate::hints::{list, signature_text};
use crate::stdlib;
use crate::syntax::*;
use crate::types::Method;
use crate::types::*;
use crate::tytable::TyId;
use ms_syntax::Pos;
use ms_syntax::ast::*;
use std::rc::Rc;

/// Whether an interface declares an operation with type parameters of its own. Such an operation
/// dispatches statically, so the interface works as a bound but not as the type of a value.
pub(crate) fn has_generic_operation(contract: &Ty) -> bool {
    contract.def.as_ref().is_some_and(|d| {
        d.operations.borrow().iter().any(|o| {
            o.decl
                .as_ref()
                .and_then(|f| f.func())
                .is_some_and(|f| !f.type_params.is_empty())
        })
    })
}

/// A structural property the language derives from a type's shape.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub(crate) enum Property {
    Equal,
    Hashable,
    Clonable,
    Data,
}

impl Property {
    /// The property a standard contract names, if it is one.
    pub(crate) fn of(contract: &Ty) -> Option<Property> {
        match contract.builtin? {
            Builtin::Equal => Some(Property::Equal),
            Builtin::Hashable => Some(Property::Hashable),
            Builtin::Clonable => Some(Property::Clonable),
            Builtin::Data => Some(Property::Data),
            _ => None,
        }
    }

    /// The standard contract this property is.
    pub(crate) fn builtin(self) -> Builtin {
        match self {
            Property::Equal => Builtin::Equal,
            Property::Hashable => Builtin::Hashable,
            Property::Clonable => Builtin::Clonable,
            Property::Data => Builtin::Data,
        }
    }

    /// The standard contract's name.
    pub(crate) fn name(self) -> &'static str {
        match self {
            Property::Equal => "Equal",
            Property::Hashable => "Hashable",
            Property::Clonable => "Clonable",
            Property::Data => "Data",
        }
    }
}

/// Visit state of a structural property query.
#[derive(Default)]
pub(crate) struct PropertyState {
    active: HashSet<(TyId, Property)>,
    completed: HashMap<(TyId, Property), bool>,
}

/// Whether two implementations could apply to one receiver and contract.
fn overlap(a: &Ty, b: &Ty, x: &Ty, y: &Ty, vars: &[Ty]) -> bool {
    struct Unifier {
        variable: VarSet,
        sub: Subst,
    }
    impl Unifier {
        fn deref(&self, t: &Ty) -> Ty {
            let mut seen: HashSet<Name> = HashSet::default();
            let mut t = t.clone();
            while let Some(next) = self.sub.get(&t.id) {
                if !seen.insert(t.id) {
                    break;
                }
                t = next.clone();
            }
            t
        }

        fn occurs(&self, id: Name, t: &Ty) -> bool {
            let t = self.deref(t);
            t.id == id
                || t.args.iter().any(|a| self.occurs(id, a))
                || t.params.iter().any(|p| self.occurs(id, &p.ty))
                || t.result.as_ref().is_some_and(|r| self.occurs(id, r))
        }

        fn matches(&mut self, a: &Ty, b: &Ty) -> bool {
            let a = self.deref(a);
            let b = self.deref(b);
            if a.id == b.id && self.variable.contains(&a.id) {
                return true;
            }
            if self.variable.contains(&a.id) {
                if self.occurs(a.id, &b) {
                    return false;
                }
                self.sub.insert(a.id, b);
                return true;
            }
            if self.variable.contains(&b.id) {
                if self.occurs(b.id, &a) {
                    return false;
                }
                self.sub.insert(b.id, a);
                return true;
            }
            if a.id != b.id || a.args.len() != b.args.len() {
                return false;
            }
            for (x, y) in a.args.iter().zip(&b.args) {
                if !self.matches(x, y) {
                    return false;
                }
            }
            if a.kind == Kind::Function {
                if a.params.len() != b.params.len() {
                    return false;
                }
                for (p, q) in a.params.iter().zip(&b.params) {
                    if p.mutable != q.mutable || !self.matches(&p.ty, &q.ty) {
                        return false;
                    }
                }
                return match (&a.result, &b.result) {
                    (Some(r), Some(s)) => self.matches(r, s),
                    _ => false,
                };
            }
            true
        }
    }
    let mut u = Unifier {
        variable: variable_set(vars),
        sub: Subst::default(),
    };
    u.matches(a, x) && u.matches(b, y)
}

/// Binds an interface's `Self` to the type implementing it.
pub(crate) fn self_binding(syms: ms_syntax::Names, contract: &Ty, implementor: &Ty) -> Subst {
    let mut s = Subst::default();
    s.insert(
        crate::checker::self_variable(syms, contract.id).id,
        implementor.clone(),
    );
    s
}

/// Fixes receiver-dependent bounds and defaults while keeping method variables open.
fn instantiate_operation_variables(variables: &[Ty], bindings: &Subst) -> Vec<Ty> {
    if bindings.is_empty() {
        return variables.to_vec();
    }
    variables
        .iter()
        .map(|variable| {
            let instantiated = (**variable).clone();
            *instantiated.bounds.borrow_mut() = variable
                .bounds()
                .iter()
                .map(|bound| sub(bound, bindings))
                .collect();
            *instantiated.default.borrow_mut() =
                variable.default_ty().map(|default| sub(&default, bindings));
            Rc::new(instantiated)
        })
        .collect()
}

/// The operation `name` of `contract` as called on a value of type `implementor`.
fn contract_operation(
    syms: ms_syntax::Names,
    session: &Rc<crate::stdlib::Session>,
    contract: &Ty,
    name: Name,
    implementor: &Ty,
) -> Option<MethodRef> {
    let def = contract.def.as_ref()?;
    let op = def
        .operations
        .borrow()
        .iter()
        .find(|o| o.name == name)
        .cloned()?;
    let mut s = substitution(contract);
    s.extend(self_binding(syms, contract, implementor));
    Some(Rc::new(Method {
        id: n(""),
        module: n(""),
        local: false,
        receiver: contract.clone(),
        contract: Some(contract.clone()),
        ty: sub(&op.ty, &s),
        variables: instantiate_operation_variables(
            &session.operation_variables(&format!("{}/{}", syms.str(contract.id), syms.str(name))),
            &s,
        ),
        decl: op.decl.clone(),
        native: Native::Contract,
    }))
}

/// Why a type is not `Data`.
pub(crate) enum DataReason {
    Resource,
    Function,
    Interface,
    Handle,
    Unbounded,
    Collection,
    Never,
    Opaque,
}

/// The first part of a type that is not `Data`, with the field path that reaches it.
pub(crate) struct DataBlocker {
    path: String,
    ty: Ty,
    reason: DataReason,
}

impl DataBlocker {
    /// The diagnostic for a failed `Data` bound, naming the part and a fix.
    pub(crate) fn message(&self, syms: ms_syntax::Names, t: &Ty) -> String {
        let (what, fix) = match self.reason {
            DataReason::Resource => (
                "a resource (Closeable)".to_string(),
                "send a path or an id and reopen it on the other side".to_string(),
            ),
            DataReason::Function => (
                "a function".to_string(),
                "send the data the function would compute".to_string(),
            ),
            DataReason::Interface => (
                "an interface value".to_string(),
                "send the plain data behind it".to_string(),
            ),
            DataReason::Handle => (
                "a runtime handle".to_string(),
                "send plain data instead".to_string(),
            ),
            DataReason::Unbounded => (
                "a type parameter with no Data bound".to_string(),
                format!(
                    "add `{}: Data` to the type parameter",
                    self.ty.display(syms)
                ),
            ),
            DataReason::Collection => (
                "a Set or a Map whose key is not a String, which has no portable form".to_string(),
                "send a List, a Map[String, T], or a JsonValue object".to_string(),
            ),
            DataReason::Opaque => (
                "opaque".to_string(),
                "return a plain value from the module that declares it".to_string(),
            ),
            DataReason::Never => (
                "Never, which has no value".to_string(),
                "use Unit or a real type".to_string(),
            ),
        };
        if self.path.is_empty() {
            format!(
                "{t_t} does not satisfy Data; it is {what}; {fix}",
                t_t = t.display(syms)
            )
        } else {
            format!(
                "{t_t} does not satisfy Data; field {} is {}, {what}; {fix}",
                self.path,
                self.ty.display(syms),
                t_t = t.display(syms)
            )
        }
    }
}

/// Standard types whose native compare operation satisfies Comparable without
/// an impl.
/// Whether `t` is a member of the type set `set`, or a type parameter bounded by a set whose members
/// are all members of it.
fn type_set_admits(t: &Ty, set: &Ty) -> bool {
    if t.kind == Kind::Variable {
        return t.bounds().iter().any(|b| {
            b.is(Builtin::TypeSet)
                && !b.args.is_empty()
                && b.args.iter().all(|m| set.args.iter().any(|x| same(x, m)))
        });
    }
    set.args.iter().any(|m| same(m, t))
}

fn builtin_comparable(t: &Ty) -> bool {
    t.builtin.is_some_and(|b| {
        b.is_int()
            || b.is_float()
            || matches!(
                b,
                Builtin::String
                    | Builtin::Decimal
                    | Builtin::BigInt
                    | Builtin::Duration
                    | Builtin::Instant
                    | Builtin::Timestamp
            )
    })
}

fn operation_names(syms: ms_syntax::Names, ops: &[Operation]) -> Vec<String> {
    ops.iter().map(|o| syms.str(o.name).to_string()).collect()
}

impl Checker {
    /// Register every source, synthetic and cached standard method in the same order.
    pub(crate) fn add_method(&mut self, method: MethodRef) {
        let at = self.p.methods.len();
        self.methods_by_receiver
            .entry(method.receiver.id)
            .or_default()
            .push(at);
        if let Some(name) = method.name() {
            self.methods_by_name
                .entry((method.receiver.id, name))
                .or_default()
                .push(at);
        }
        if let Some(contract) = &method.contract {
            if contract.kind == Kind::Variable {
                self.generic_contract_methods.push(at);
            } else if method.variables.iter().any(|v| v.id == method.receiver.id) {
                self.variable_receiver_contract_methods
                    .entry(contract.id)
                    .or_default()
                    .push(at);
            } else {
                self.methods_by_contract
                    .entry((contract.id, method.receiver.id))
                    .or_default()
                    .push(at);
            }
        }
        self.p.methods.push(method);
    }

    /// Declares the methods of one `impl` block.
    pub(crate) fn implementation(&mut self, d: &DeclRef) {
        let DeclKind::Impl(imp) = &d.decl().kind else {
            return;
        };
        let old = std::mem::replace(&mut self.scope, Scope::new(None));
        // Implementations inherit names and bounds from the nominal receiver declaration.
        let mut vars: Vec<Ty> = Vec::new();
        let receiver_name = n(imp.receiver.name(self.syms));
        if let Some(symbol) = self.sym(receiver_name)
            && symbol.decl.is_some()
            && symbol.kind == SymKind::Type
        {
            // Copy resolved bounds: their names belong to the receiver's module and
            // need not be imported by a module extending that receiver.
            let mut substitution = Subst::default();
            for parameter in symbol.variables() {
                let id = self.unique("typevar");
                let v: Ty = Rc::new(Type::new(self.syms, parameter.name, id, Kind::Variable));
                vars.push(v.clone());
                self.scope.types.borrow_mut().insert(v.name, v.clone());
                substitution.insert(parameter.id, v);
            }
            for (i, parameter) in symbol.variables().iter().enumerate() {
                for bound in parameter.bounds() {
                    vars[i].bounds.borrow_mut().push(sub(&bound, &substitution));
                }
            }
        }
        let mut receiver = self.resolve(Some(&imp.receiver));
        let nominal = receiver.def.as_ref().and_then(|d| d.symbol());
        if self.opaque_denied(
            d.pos(),
            &receiver,
            "it takes no new methods or interfaces here",
        ) {
            self.scope = old;
            return;
        }
        // A bundled module may add methods to the `extern type` it declares.
        let own_extern = receiver.kind == Kind::Native
            && nominal
                .as_ref()
                .is_some_and(|s| s.module == self.current_file());
        let foreign_native = nominal.as_ref().is_some_and(|s| s.native != Native::Source)
            && !self.standard_declarations
            && !own_extern
            && !self.m().is_standard(self.syms);
        // A bundled module may add source-written methods to a built-in scalar or String.
        let scalar_extension = self.m().is_standard(self.syms) && builtin_comparable(&receiver);
        if !scalar_extension
            && (nominal.is_none()
                || foreign_native
                || !(own_extern
                    || matches!(receiver.kind, Kind::Type | Kind::Alternative)
                    || (self.m().is_standard(self.syms) && receiver.kind == Kind::Native)))
        {
            if !receiver.is_invalid() {
                self.type_error(
                    d.pos(),
                    "implementation receiver must be nominal source data; declare methods on a type or enum you declare, such as 'fn Point.show() String:', not on built-in or function types",
                );
            }
            // An impl whose receiver is not valid nominal data must not become
            // evidence for later conversions; report the receiver's own faults only.
            self.well_formed(&receiver, d.pos(), &mut HashSet::default());
            self.scope = old;
            return;
        }
        let mut occurs: HashSet<Name> = HashSet::default();
        fn visit(t: &Ty, occurs: &mut HashSet<Name>) {
            occurs.insert(t.id);
            for a in &t.args {
                visit(a, occurs);
            }
            for p in &t.params {
                visit(&p.ty, occurs);
            }
            if let Some(r) = &t.result {
                visit(r, occurs);
            }
        }
        visit(&receiver, &mut occurs);
        let mut active: Vec<Ty> = Vec::new();
        let mut specialized = Subst::default();
        for (i, v) in vars.iter().enumerate() {
            if occurs.contains(&v.id) {
                active.push(v.clone());
            } else {
                self.scope.types.borrow_mut().remove(&v.name);
                if i < receiver.args.len() {
                    specialized.insert(v.id, receiver.args[i].clone());
                }
            }
        }
        let vars = active;
        for v in &vars {
            let rewritten: Vec<Ty> = v.bounds().iter().map(|b| sub(b, &specialized)).collect();
            *v.bounds.borrow_mut() = rewritten;
        }
        let mut contract = self.resolve(imp.contract.as_ref());
        if contract.kind != Kind::Contract && !contract.is_invalid() {
            self.type_error(
                d.pos(),
                "implementation target must be an interface declared with 'interface'",
            );
        }
        // An interface argument that is a receiver parameter carries the interface's
        // declared bounds into this implementation, without changing the data type.
        if let Some(def) = &contract.def
            && contract.args.len() == def.arity()
        {
            let substitution = substitution(&contract);
            for (i, parameter) in def.variables().iter().enumerate() {
                let argument = &contract.args[i];
                for v in &vars {
                    if argument.id == v.id {
                        for bound in parameter.bounds() {
                            v.bounds.borrow_mut().push(sub(&bound, &substitution));
                        }
                    }
                }
            }
        }
        // Resolution copies variable types, so refresh applications after adding bounds.
        receiver = self.resolve(Some(&imp.receiver));
        contract = self.resolve(imp.contract.as_ref());
        // Valid implementation receivers are nominal: generic applications share
        // their declaration id. Keep argument unification and visibility below.
        let overlapping = self
            .methods_by_receiver
            .get(&receiver.id)
            .into_iter()
            .flatten()
            .any(|&at| {
                let m = &self.p.methods[at];
                if !self.method_visible(m) {
                    return false;
                }
                let Some(mc) = &m.contract else {
                    return false;
                };
                let mut all = vars.clone();
                all.extend(m.variables.iter().cloned());
                overlap(&receiver, &contract, &m.receiver, mc, &all)
            });
        if overlapping {
            self.type_error(
                d.pos(),
                format!(
                    "duplicate or overlapping implementation; {contract_t} is already implemented for {receiver_t} (or an overlapping type), so remove one impl"
                , contract_t = contract.display(self.syms), receiver_t = receiver.display(self.syms)),
            );
        }
        let mut seen: HashSet<Name> = HashSet::default();
        let mut ops: Vec<Operation> = Vec::new();
        // Interface arguments and `Self`, applied to operation signatures and bounds alike.
        let mut interface_substitution = Subst::default();
        if let Some(def) = &contract.def {
            let mut s = substitution(&contract);
            s.extend(self_binding(self.syms, &contract, &receiver));
            interface_substitution = s.clone();
            for op in def.operations.borrow().iter() {
                let mut op = op.clone();
                op.ty = sub(&op.ty, &s);
                ops.push(op);
            }
        }
        let receiver_module_differs = |this: &Checker, receiver: &Ty| {
            receiver
                .def
                .as_ref()
                .and_then(|d| d.symbol())
                .is_some_and(|s| {
                    // A bundled module's methods on a native standard type apply wherever it is used.
                    let extends_native =
                        this.m().is_standard(this.syms) && s.native != Native::Source;
                    s.module != this.current_file() && !extends_native
                })
        };
        self.scope
            .types
            .borrow_mut()
            .insert(n("Self"), receiver.clone());
        for (index, method) in imp.methods.iter().enumerate() {
            if !seen.insert(method.func.name) {
                self.type_error(
                    method.pos,
                    format!(
                        "duplicate implementation operation {}; define each operation once per impl",
                        self.syms.str(method.func.name)
                    ),
                );
            }
            // An inherent method is reachable only as `value.name()`, which a field of the
            // same name always shadows; an interface operation stays reachable through a view.
            if d.decl().synthetic
                && receiver
                    .def
                    .as_ref()
                    .is_some_and(|d| d.fields.borrow().iter().any(|f| f.name == method.func.name))
            {
                let name = self.syms.str(method.func.name);
                self.type_error(
                    method.pos,
                    format!(
                        "operation {name} has the same name as a field of {}; `value.{name}` always reads the field, so rename one of them",
                        receiver.display(self.syms)
                    ),
                );
            }
            let own = self.method_variables(method);
            self.type_defaults(&method.func.type_params, &own);
            let mut t = (*self.signature(&method.func.params, Some(&method.func.result))).clone();
            let mut found = false;
            for op in &ops {
                if op.name != method.func.name {
                    continue;
                }
                found = true;
                if op.ty.defaults.as_ref().is_some_and(|d| !d.is_empty()) {
                    let mut merged: HashSet<Name> = t
                        .defaults
                        .as_ref()
                        .map(|d| d.iter().copied().collect())
                        .unwrap_or_default();
                    if let Some(allowed) = &op.ty.defaults {
                        merged.extend(allowed.iter().copied());
                    }
                    t.defaults = Some(Rc::new(ParameterDefaults::new(merged)));
                }
                let declared = self.session.operation_variables(&format!(
                    "{}/{}",
                    self.syms.str(contract.id),
                    self.syms.str(op.name)
                ));
                let renamed: Subst = declared
                    .iter()
                    .zip(&own)
                    .map(|(d, o)| (d.id, o.clone()))
                    .collect();
                let bounds_match = declared.len() == own.len()
                    && declared.iter().zip(&own).all(|(d, o)| {
                        let (db, ob) = (d.bounds(), o.bounds());
                        db.len() == ob.len()
                            && db.iter().zip(&ob).all(|(x, y)| {
                                same(&sub(&sub(x, &interface_substitution), &renamed), y)
                            })
                    });
                if !bounds_match {
                    self.type_error(
                        method.pos,
                        format!(
                            "implementation operation type parameters do not match contract; {} must declare the type parameters of the interface operation, with the same bounds",
                            self.syms.str(method.func.name)
                        ),
                    );
                } else if let Some(declared_names) = op
                    .decl
                    .as_ref()
                    .and_then(|f| f.decl.methods().get(f.index?))
                    .map(|m| m.func.params.iter().map(|p| p.name).collect::<Vec<_>>())
                    .filter(|names| {
                        let written: Vec<_> = method.func.params.iter().map(|p| p.name).collect();
                        written.len() == names.len() && written != *names
                    })
                    && same(&Rc::new(t.clone()), &sub(&op.ty, &renamed))
                {
                    let names: Vec<String> = declared_names
                        .iter()
                        .map(|n| self.syms.str(n).to_string())
                        .collect();
                    self.type_error(
                        method.pos,
                        format!(
                            "implementation operation parameter names do not match contract; {} must name its parameters ({}) like the interface, since a call through the interface labels arguments by those names",
                            self.syms.str(method.func.name),
                            names.join(", ")
                        ),
                    );
                } else if !same(&Rc::new(t.clone()), &sub(&op.ty, &renamed)) {
                    self.type_error(
                        method.pos,
                        format!(
                            "implementation operation signature does not match contract; {} must be declared as {} {}{}",
                            self.syms.str(method.func.name),
                            if op
                                .decl
                                .as_ref()
                                .and_then(|f| f.decl.methods().get(f.index?))
                                .is_some_and(|m| m.mutating)
                            {
                                "var fn"
                            } else {
                                "fn"
                            },
                            self.syms.str(method.func.name),
                            signature_text(self.syms, &op.ty)
                        ),
                    );
                }
            }
            let declared_mutating = |op: &Operation| {
                let f = op.decl.as_ref()?;
                Some(f.decl.methods().get(f.index?)?.mutating)
            };
            if let Some(contract_mutates) = ops
                .iter()
                .find(|op| op.name == method.func.name)
                .and_then(declared_mutating)
                && method.mutating
                && !contract_mutates
            {
                let (have, want) = ("var fn", "fn");
                self.type_error(
                    method.pos,
                    format!(
                        "implementation of {} is declared {have} but {contract_t} declares it {want}; an operation that changes its receiver is declared `var fn` in the interface too",
                        self.syms.str(method.func.name)
                    , contract_t = contract.display(self.syms)),
                );
            }
            // A target that is not an interface was already reported; it has no operations to match.
            if !found && contract.kind == Kind::Contract {
                self.type_error(
                    method.pos,
                    format!(
                        "extra operation {}; {} declares: {} (remove it or add it to the interface)",
                        self.syms.str(method.func.name),
                        contract.display(self.syms),
                        list(&operation_names(self.syms, &ops), 12)
                    ),
                );
            }
            let local = receiver_module_differs(self, &receiver);
            let id = self.unique("method");
            let m = Method {
                id,
                module: self.current_file(),
                local,
                receiver: receiver.clone(),
                contract: Some(contract.clone()),
                ty: Rc::new(t),
                variables: vars.iter().chain(&own).cloned().collect(),
                decl: Some(FuncRef {
                    decl: d.clone(),
                    index: Some(index),
                }),
                native: Native::Source,
            };
            for v in &own {
                self.scope.types.borrow_mut().remove(&v.name);
            }
            self.add_method(Rc::new(m));
        }
        self.scope.types.borrow_mut().remove(&n("Self"));
        if ops.is_empty() && imp.methods.is_empty() && contract.kind == Kind::Contract {
            // A property without operations has no method to carry its evidence, so record the
            // implementation itself.
            if contract.is(Builtin::Data)
                && receiver.kind != Kind::Native
                && !self.m().is_standard(self.syms)
            {
                self.type_error(
                    d.pos(),
                    format!(
                        "{receiver_t} is Data when its parts are; only an extern type or the standard library declares Data, so remove this impl"
                    , receiver_t = receiver.display(self.syms)),
                );
            }
            let id = self.unique("method");
            self.add_method(Rc::new(Method {
                id,
                module: self.current_file(),
                local: receiver_module_differs(self, &receiver),
                receiver: receiver.clone(),
                contract: Some(contract.clone()),
                ty: contract.clone(),
                variables: vars.clone(),
                decl: None,
                native: Native::Source,
            }));
        }
        for op in &ops {
            if seen.contains(&op.name) {
                continue;
            }
            if contract.is_test_hooks(self.syms) {
                // This standard lifecycle contract has no-op defaults; retain ordinary
                // checked methods so interface calls and generic bounds use normal dispatch.
                let decl_id = self.m().facts_mut().fresh_id();
                let result_id = self.m().facts_mut().fresh_id();
                let decl = DeclRef::new(Decl {
                    id: decl_id,
                    pos: d.pos(),
                    export: false,
                    synthetic: true,
                    kind: DeclKind::Fn(Func {
                        name: op.name,
                        type_params: Vec::new(),
                        params: Vec::new(),
                        result: TypeRef {
                            id: result_id,
                            pos: d.pos(),
                            kind: TypeKind::Named {
                                name: n("Unit"),
                                args: Vec::new(),
                            },
                        },
                        body: Vec::new(),
                        external: false,
                    }),
                });
                let local = receiver_module_differs(self, &receiver);
                let id = self.unique("method");
                let m = Method {
                    id,
                    module: self.current_file(),
                    local,
                    receiver: receiver.clone(),
                    contract: Some(contract.clone()),
                    ty: op.ty.clone(),
                    variables: vars.clone(),
                    decl: Some(FuncRef::of_decl(decl)),
                    native: Native::Source,
                };
                self.add_method(Rc::new(m));
            } else {
                self.type_error(
                    d.pos(),
                    format!(
                        "missing implementation operation {}; add fn {}{} to this impl",
                        self.syms.str(op.name),
                        self.syms.str(op.name),
                        signature_text(self.syms, &op.ty)
                    ),
                );
            }
        }
        self.well_formed(&receiver, d.pos(), &mut HashSet::default());
        self.well_formed(&contract, d.pos(), &mut HashSet::default());
        self.scope = old;
    }

    /// Declares a method's own type parameters in the current scope.
    fn method_variables(&mut self, method: &ms_syntax::ast::Method) -> Vec<Ty> {
        let mut own: Vec<Ty> = Vec::new();
        for param in &method.func.type_params {
            if self.scope.types.borrow().contains_key(&param.name) {
                self.type_error(
                    param.pos,
                    format!(
                        "type parameter {} shadows a type parameter of the impl; choose a different name",
                        self.syms.str(param.name)
                    ),
                );
            } else if self.intrinsic_type_parameter(param.name) {
                self.res_error(
                    param.pos,
                    format!(
                        "duplicate or intrinsic type parameter {}; choose a different type parameter name",
                        self.syms.str(param.name)
                    ),
                );
            }
            let id = self.unique("typevar");
            let v: Ty = Rc::new(Type::new(self.syms, param.name, id, Kind::Variable));
            own.push(v.clone());
            self.scope.types.borrow_mut().insert(param.name, v);
        }
        self.resolve_type_bounds(&method.func.type_params, &own);
        own
    }

    /// The structural identity of `t`.
    pub(crate) fn shape(&self, t: &Ty) -> TyId {
        self.tys.borrow_mut().shape(t)
    }

    /// Whether `receiver` implements `contract`.
    pub(crate) fn implements(&self, receiver: &Ty, contract: &Ty) -> bool {
        if receiver.id == contract.id {
            return same(receiver, contract);
        }
        if let Some(property) = Property::of(contract) {
            return self.property(receiver, property, None);
        }
        if contract.is(Builtin::TypeSet) {
            return type_set_admits(receiver, contract);
        }
        if receiver.kind == Kind::Variable {
            return receiver.bounds().iter().any(|b| same(b, contract));
        }
        let exact = self
            .methods_by_contract
            .get(&(contract.id, receiver.id))
            .map_or(&[][..], |v| v);
        let by_variable = self
            .variable_receiver_contract_methods
            .get(&contract.id)
            .map_or(&[][..], |v| v);
        for &at in exact
            .iter()
            .chain(by_variable)
            .chain(&self.generic_contract_methods)
        {
            let m = &self.p.methods[at];
            if !self.method_visible(m) {
                continue;
            }
            let Some(mc) = &m.contract else {
                continue;
            };
            let mut s = Subst::default();
            if unify(&m.receiver, receiver, &variable_set(&m.variables), &mut s)
                && same(&sub(mc, &s), contract)
                && self.bounds_satisfied(m.split_variables().0, &s)
            {
                return true;
            }
        }
        contract.is(Builtin::Comparable) && builtin_comparable(receiver)
            || self.shape_implements(receiver, contract)
    }

    /// Whether `receiver`'s own methods supply every operation of `contract` with its exact
    /// signature, labels and `var`-ness. A type satisfies an interface by having its operations;
    /// no `impl` names the relationship.
    fn shape_implements(&self, receiver: &Ty, contract: &Ty) -> bool {
        self.shape_gap(receiver, contract)
            .is_some_and(|gap| gap.is_empty())
    }

    /// Why `receiver`'s own methods do not satisfy `contract` by shape: the first operation that is
    /// missing or differs. `Some("")` when they satisfy it; `None` when shape does not apply.
    pub(crate) fn shape_gap(&self, receiver: &Ty, contract: &Ty) -> Option<String> {
        self.shape_gap_with(receiver, contract, false)
    }

    /// [`Self::shape_gap`], where `optional` lets the receiver leave operations out (the optional
    /// `TestHooks`); the ones it declares must still match.
    pub(crate) fn shape_gap_with(
        &self,
        receiver: &Ty,
        contract: &Ty,
        optional: bool,
    ) -> Option<String> {
        if !matches!(
            receiver.kind,
            Kind::Type | Kind::Alternative | Kind::Native | Kind::Primitive
        ) || contract.kind != Kind::Contract
        {
            return None;
        }
        let def = contract.def.as_ref()?;
        let ops = def.operations.borrow();
        if ops.is_empty() || contract.args.len() != def.arity() {
            return None;
        }
        let mut s = substitution(contract);
        s.extend(self_binding(self.syms, contract, receiver));
        let declared = |f: &Option<FuncRef>| {
            let f = f.as_ref()?;
            let m = f.decl.methods().get(f.index?)?;
            Some((
                m.mutating,
                m.func.params.iter().map(|p| p.name).collect::<Vec<_>>(),
            ))
        };
        for op in ops.iter() {
            let name = self.syms.str(op.name);
            let key = format!("{}/{}", self.syms.str(contract.id), name);
            let op_variables = self.session.operation_variables(&key);
            let own: Vec<MethodRef> = self
                .implemented_methods(receiver, op.name)
                .into_iter()
                .filter(|m| m.is_inherent(self.syms))
                .collect();
            if optional && own.is_empty() {
                continue;
            }
            // An operation's own type parameters are met by the method's, position by position.
            let mut s = s.clone();
            let mut own_variables_match = true;
            if let [m] = own.as_slice() {
                let own_variables = m.split_variables().1;
                if own_variables.len() != op_variables.len() {
                    return Some(format!(
                        "{name} must declare the same type parameters as the interface"
                    ));
                }
                for (ov, mv) in op_variables.iter().zip(own_variables) {
                    s.insert(ov.id, mv.clone());
                }
                own_variables_match = op_variables.iter().zip(own_variables).all(|(ov, mv)| {
                    let (want, have) = (ov.bounds(), mv.bounds());
                    want.len() == have.len()
                        && want.iter().zip(&have).all(|(w, h)| same(&sub(w, &s), h))
                });
            } else if !op_variables.is_empty() {
                return Some(format!("{name} is missing"));
            }
            if !own_variables_match {
                return Some(format!(
                    "{name} must bound its type parameters like the interface"
                ));
            }
            // Methods of one name may differ by their receiver's bounds (`sorted()` and
            // `sorted(compare)`): the one whose signature the interface asks for is the match.
            let wanted = sub(&op.ty, &s);
            let fits: Vec<&MethodRef> = own.iter().filter(|m| same(&m.ty, &wanted)).collect();
            let m = match (fits.as_slice(), own.as_slice()) {
                ([m], _) => *m,
                (_, [m]) => m,
                _ => return Some(format!("{name} is missing")),
            };
            if !same(&m.ty, &sub(&op.ty, &s)) {
                return Some(format!(
                    "{name} must be declared as fn {name}{}",
                    signature_text(self.syms, &sub(&op.ty, &s))
                ));
            }
            match (declared(&m.decl), declared(&op.decl)) {
                // An operation declared `var fn` may be met by a method that does not change `self`.
                (Some((own, own_names)), Some((want, want_names))) => {
                    if own_names != want_names {
                        return Some(format!(
                            "{name} must name its parameters like the interface"
                        ));
                    }
                    if own && !want {
                        return Some(format!("{name} must not be `var fn`"));
                    }
                }
                _ => return Some(format!("{name} has no declaration to compare")),
            }
        }
        Some(String::new())
    }

    /// Whether `.clone()` is available for `t`: every value but a resource, which has one owner.
    fn clonable(&self, t: &Ty, state: &mut PropertyState) -> bool {
        match t.kind {
            Kind::Variable => return t.bounds().iter().any(implies_clonable),
            // The payload of an interface value has a type the interface does not name; one over
            // a native without a `clone` faults when copied (`ownership::Classifier::clonable`).
            Kind::Contract => return !t.is(Builtin::Closeable),
            // A function value owns its captures and has no `clone`; a type holding one is
            // not Clonable either (`ownership::Classifier::clonable`).
            Kind::Function => return false,
            Kind::Primitive => return true,
            _ => {}
        }
        if self.closeable(t) {
            return false;
        }
        if t.kind == Kind::Native {
            // A native owns storage the runtime cannot duplicate blindly: it is cloned only
            // through the `clone` it declares (`List`, `Bytes`, `BigInt`), unless it is plain
            // words (`Decimal`). `ownership::Classifier::clonable` applies the same rule.
            return (self.copy_native(t) || self.declares_clone(t))
                && t.args
                    .iter()
                    .all(|a| self.property_in(a, Property::Clonable, state));
        }
        if t.def.is_some() {
            return fields(t)
                .iter()
                .all(|f| self.property_in(&f.ty, Property::Clonable, state));
        }
        true
    }

    /// Whether the native `t` is plain words (`Decimal`), like the primitives.
    fn copy_native(&self, t: &Ty) -> bool {
        t.is(Builtin::Decimal)
    }

    /// Whether the native `t` declares an infallible `clone` of its own, as an operation of its
    /// definition or as an implemented method.
    fn declares_clone(&self, t: &Ty) -> bool {
        if native_declares_clone(self.syms, t) {
            return true;
        }
        // The bounds of a generic `clone` ask again whether `t`'s element is clonable; a cycle
        // through a recursive type is assumed clonable, as `property_in` does for `active`.
        let key = self.shape(t);
        if self.clone_probes.borrow().contains(&key) {
            return true;
        }
        self.clone_probes.borrow_mut().push(key);
        let found = self
            .implemented_methods(t, n("clone"))
            .iter()
            .any(|m| m.ty.result_ty().id == t.id);
        self.clone_probes.borrow_mut().pop();
        found
    }

    /// Whether `t` is, or holds, a `Closeable` value. Such a value is an identity to close once,
    /// not a key to file by hash, and a set or map would drop a duplicate without closing it.
    fn holds_resource(&self, t: &Ty, seen: &mut Vec<TyId>) -> bool {
        let key = self.shape(t);
        if seen.contains(&key) {
            return false;
        }
        seen.push(key);
        let closeable = self.p.methods.iter().any(|m| {
            self.method_visible(m)
                && m.closes(self.syms)
                && unify(
                    &m.receiver,
                    t,
                    &variable_set(&m.variables),
                    &mut Subst::default(),
                )
        });
        closeable
            || t.args.iter().any(|a| self.holds_resource(a, seen))
            || (t.def.is_some()
                && (fields(t).iter().any(|f| self.holds_resource(&f.ty, seen))
                    || cases(t)
                        .iter()
                        .any(|c| c.fields.iter().any(|f| self.holds_resource(&f.ty, seen)))))
    }

    /// Whether an `impl Data for` the type exists.
    fn declares_data(&self, t: &Ty) -> bool {
        self.p.methods.iter().any(|m| {
            self.method_visible(m)
                && m.decl.is_none()
                && m.contract.as_ref().is_some_and(|c| c.is(Builtin::Data))
                && m.receiver.id == t.id
        })
    }

    /// Whether `t` has a visible `JsonEncode` implementation.
    fn has_json_encoder(&self, t: &Ty) -> bool {
        self.p.methods.iter().any(|m| {
            self.method_visible(m)
                && (m.contract.as_ref().is_some_and(|c| {
                    c.is_source_type(self.syms, "@std/data/json.ms", "JsonEncode")
                }) || (m.is_inherent(self.syms)
                    && m.name().is_some()
                    && m.name()
                        == self
                            .session
                            .sole_operation("@std/data/json.ms", "JsonEncode")))
                && {
                    let mut s = Subst::default();
                    unify(&m.receiver, t, &variable_set(&m.variables), &mut s)
                }
        })
    }

    /// The first part of `t` that keeps it from being `Data`, or `None` when `t` is plain data:
    /// no resource, behavior, or runtime handle anywhere inside it. `visiting` holds the types
    /// being checked on the current path, so a recursive type is assumed plain only while its own
    /// check is open.
    pub(crate) fn data_blocker(
        &self,
        t: &Ty,
        visiting: &mut Vec<TyId>,
        path: &mut Vec<String>,
    ) -> Option<DataBlocker> {
        let blocked = |reason: DataReason, path: &[String]| {
            Some(DataBlocker {
                path: path.join("."),
                ty: t.clone(),
                reason,
            })
        };
        if t.is_invalid() {
            return None;
        }
        match t.kind {
            Kind::Variable => {
                return if t.bounds().iter().any(|b| b.is(Builtin::Data)) {
                    None
                } else {
                    blocked(DataReason::Unbounded, path)
                };
            }
            Kind::Primitive if t.is_never() => return blocked(DataReason::Never, path),
            Kind::Primitive => return None,
            Kind::Function => return blocked(DataReason::Function, path),
            Kind::Contract => return blocked(DataReason::Interface, path),
            _ => {}
        }
        if t.is(Builtin::List) {
            return t
                .args
                .first()
                .and_then(|a| self.data_blocker(a, visiting, path));
        }
        if t.is(Builtin::Map) && t.args.first().is_some_and(|k| k.is(Builtin::String)) {
            // A `Map[String, T]` is a JSON object.
            return t
                .args
                .get(1)
                .and_then(|a| self.data_blocker(a, visiting, path));
        }
        if t.is(Builtin::Map) || t.is(Builtin::Set) {
            return blocked(DataReason::Collection, path);
        }
        if t.kind == Kind::Native {
            return if self.declares_data(t) {
                None
            } else {
                blocked(DataReason::Handle, path)
            };
        }
        if t.opaque_module().is_some() {
            return blocked(DataReason::Opaque, path);
        }
        if self.closeable(t) {
            return blocked(DataReason::Resource, path);
        }
        if self.declares_data(t) {
            // The standard library vouches for the type, as for `JsonValue`.
            return None;
        }
        if self.has_json_encoder(t) {
            // The type's own `JsonEncode` decides its JSON form, whatever its fields hold.
            return None;
        }
        let key = self.shape(t);
        if visiting.contains(&key) {
            return None;
        }
        visiting.push(key);
        let mut found = None;
        for f in fields(t) {
            path.push(self.syms.str(f.name).to_string());
            found = self.data_blocker(&f.ty, visiting, path);
            if found.is_some() {
                break;
            }
            path.pop();
        }
        if found.is_none() {
            'cases: for c in cases(t) {
                for f in &c.fields {
                    path.push(self.syms.str(f.name).to_string());
                    found = self.data_blocker(&f.ty, visiting, path);
                    if found.is_some() {
                        break 'cases;
                    }
                    path.pop();
                }
            }
        }
        visiting.pop();
        found
    }

    fn bounds_satisfied(&self, vars: &[Ty], s: &Subst) -> bool {
        for v in vars {
            let Some(a) = s.get(&v.id) else {
                return false;
            };
            for b in v.bounds() {
                if !self.satisfies(a, &sub(&b, s)) {
                    return false;
                }
            }
        }
        true
    }

    /// Whether `t` meets `bound`.
    pub(crate) fn satisfies(&self, t: &Ty, bound: &Ty) -> bool {
        if let Some(property) = Property::of(bound) {
            return self.property(t, property, None);
        }
        self.implements(t, bound)
    }

    /// Structural Equal/Hashable evidence.
    pub(crate) fn property(
        &self,
        t: &Ty,
        property: Property,
        state: Option<&mut PropertyState>,
    ) -> bool {
        match state {
            Some(s) => self.property_in(t, property, s),
            None => self.property_in(t, property, &mut PropertyState::default()),
        }
    }

    fn property_in(&self, t: &Ty, property: Property, state: &mut PropertyState) -> bool {
        if t.is_invalid() {
            return true;
        }
        if property == Property::Data {
            // Not cached: a result computed under an assumed ancestor must not outlive it.
            return self
                .data_blocker(t, &mut Vec::new(), &mut Vec::new())
                .is_none();
        }
        // A resource anywhere in the value (a field, an alternative case, a type argument) has
        // one owner: it is never hashed as a key or duplicated.
        if (property == Property::Hashable || property == Property::Clonable)
            && self.holds_resource(t, &mut Vec::new())
        {
            return false;
        }
        let key = (self.shape(t), property);
        if let Some(&r) = state.completed.get(&key) {
            return r;
        }
        if state.active.contains(&key) {
            // Equality handles cycles; structural hashing requires an acyclic shape.
            return property != Property::Hashable;
        }
        state.active.insert(key);
        let result = self.property_compute(t, property, state);
        state.active.remove(&key);
        state.completed.insert(key, result);
        result
    }

    fn property_compute(&self, t: &Ty, property: Property, state: &mut PropertyState) -> bool {
        if property == Property::Clonable {
            return self.clonable(t, state);
        }
        if t.kind == Kind::Variable {
            return t.bounds().iter().any(|b| {
                b.is(property.builtin()) || (b.is(Builtin::Hashable) && property == Property::Equal)
            });
        }
        // Explicit implementations take precedence over structural data semantics.
        for m in &self.p.methods {
            if !self.method_visible(m)
                || !(m
                    .contract
                    .as_ref()
                    .is_some_and(|c| c.is(property.builtin()))
                    || m.overrides(self.syms, property.builtin()))
            {
                continue;
            }
            let mut s = Subst::default();
            if unify(&m.receiver, t, &variable_set(&m.variables), &mut s)
                && self.bounds_satisfied(&m.variables, &s)
            {
                if property == Property::Hashable && self.holds_resource(t, &mut Vec::new()) {
                    return false;
                }
                return property != Property::Hashable || self.property(t, Property::Equal, None);
            }
        }
        if property == Property::Hashable {
            for m in &self.p.methods {
                if !self.method_visible(m)
                    || !(m.contract.as_ref().is_some_and(|c| c.is(Builtin::Equal))
                        || m.overrides(self.syms, Builtin::Equal))
                {
                    continue;
                }
                let mut s = Subst::default();
                if unify(&m.receiver, t, &variable_set(&m.variables), &mut s)
                    && self.bounds_satisfied(&m.variables, &s)
                {
                    return false;
                }
            }
        }
        match t.kind {
            Kind::Function | Kind::Contract => return false,
            Kind::Primitive => {
                return float_bits(t).is_none() || property != Property::Hashable;
            }
            _ => {}
        }
        if t.is(Builtin::Decimal)
            || t.is(Builtin::Bytes)
            || t.is(Builtin::Duration)
            || t.is(Builtin::Instant)
        {
            return true;
        }
        if t.is(Builtin::List) || t.is(Builtin::Map) || t.is(Builtin::Set) {
            if property == Property::Hashable {
                return false;
            }
            return t.args.iter().all(|a| self.property_in(a, property, state));
        }
        if t.is(Builtin::BigInt) || t.is(Builtin::Regex) || t.is(Builtin::Timestamp) {
            return property == Property::Equal && !t.is(Builtin::Regex);
        }
        if t.kind == Kind::Native {
            return false;
        }
        if t.def.is_some() {
            if !fields(t)
                .iter()
                .all(|f| self.property_in(&f.ty, property, state))
            {
                return false;
            }
            return cases(t).iter().all(|c| {
                c.fields
                    .iter()
                    .all(|f| self.property_in(&f.ty, property, state))
            });
        }
        false
    }

    /// Implemented methods named `name` that apply to `receiver` and are visible here.
    pub(crate) fn implemented_methods(&self, receiver: &Ty, name: Name) -> Vec<MethodRef> {
        let mut result: Vec<MethodRef> = Vec::new();
        for &at in self
            .methods_by_name
            .get(&(receiver.id, name))
            .into_iter()
            .flatten()
        {
            let m = &self.p.methods[at];
            if !self.method_visible(m) {
                continue;
            }
            let mut s = Subst::default();
            let (shared, own) = m.split_variables();
            if unify(&m.receiver, receiver, &variable_set(shared), &mut s)
                && self.bounds_satisfied(shared, &s)
            {
                let mut r = (**m).clone();
                r.ty = sub(&m.ty, &s);
                r.contract = m.contract.as_ref().map(|c| sub(c, &s));
                r.receiver = receiver.clone();
                // Implementation variables are fixed by the receiver; the method's own stay open.
                r.variables = instantiate_operation_variables(own, &s);
                result.push(Rc::new(r));
            }
        }
        result
    }

    /// Methods named `name` available on `receiver`.
    pub(crate) fn methods(&self, receiver: &Ty, name: Name) -> Vec<MethodRef> {
        // A type's own `clone` replaces the structural one: a resource's clone duplicates its
        // handle and returns a `Result`.
        if self.syms.str(name) == "clone" && matches!(receiver.kind, Kind::Type | Kind::Alternative)
        {
            let own = self.implemented_methods(receiver, name);
            if !own.is_empty() {
                return own;
            }
        }
        if let Some(m) = native_method(self.syms, &self.session, receiver, name) {
            return vec![Rc::new(m)];
        }
        if receiver.kind == Kind::Contract
            && let Some(method) =
                contract_operation(self.syms, &self.session, receiver, name, receiver)
        {
            return vec![method];
        }
        if receiver.kind == Kind::Variable {
            let mut result: Vec<MethodRef> = Vec::new();
            let mut seen_bounds: Vec<Ty> = Vec::new();
            for b in receiver.bounds() {
                // A bound inherited from both the receiver declaration and the
                // implementation must not make its operations ambiguous.
                if b.kind != Kind::Contract || seen_bounds.iter().any(|s| s.id == b.id) {
                    continue;
                }
                seen_bounds.push(b.clone());
                // `Self` in a bound's operation is the bounded variable itself.
                match contract_operation(self.syms, &self.session, &b, name, receiver) {
                    Some(method) => result.push(method),
                    None => result.extend(self.methods(&b, name)),
                }
            }
            return result;
        }
        let result = self.implemented_methods(receiver, name);
        let derived =
            |contract: &str| self.session.sole_operation("@std/core.ms", contract) == Some(name);
        let derivable = if derived("Hashable") {
            Some(Property::Hashable)
        } else if derived("Equal") {
            Some(Property::Equal)
        } else {
            None
        };
        if let Some(property) = derivable.filter(|_| result.is_empty())
            && self.property(receiver, property, None)
        {
            let contract = self.session.standard(property.name(), vec![]);
            let mut operation = contract
                .def
                .as_ref()
                .map(|d| d.operations.borrow()[0].clone())
                .expect("operation");
            operation.ty = sub(&operation.ty, &self_binding(self.syms, &contract, receiver));
            return vec![Rc::new(Method {
                id: n(""),
                module: n(""),
                local: false,
                receiver: receiver.clone(),
                contract: Some(contract.clone()),
                ty: operation.ty,
                variables: Vec::new(),
                decl: stdlib::standard_method_declaration(&contract, name),
                native: Native::Builtin(name),
            })];
        }
        result
    }

    /// Whether a method is usable from the module being checked.
    pub(crate) fn method_visible(&self, m: &Method) -> bool {
        m.visible_in(self.current_file())
    }

    /// Whether a value of `t` is closed when its scope ends.
    pub(crate) fn closeable(&self, t: &Ty) -> bool {
        if t.kind == Kind::Contract || t.kind == Kind::Variable {
            return self
                .methods(t, n("close"))
                .iter()
                .any(|m| m.ty.params.is_empty() && is_close_result(self.syms, &m.ty.result_ty()));
        }
        self.implements(t, &self.session.standard("Closeable", vec![]))
    }

    /// Checks every bound reachable from `t`. `seen` is keyed by pointer: a
    /// structural key costs the whole subtree at each level, which made deeply
    /// nested inferred types cubic.
    pub(crate) fn well_formed(&mut self, t: &Ty, pos: Pos, seen: &mut HashSet<usize>) {
        if !seen.insert(Rc::as_ptr(t) as usize) {
            return;
        }
        self.bounds_hold(t, pos);
        for a in &t.args {
            self.well_formed(a, pos, seen);
        }
        for p in &t.params {
            self.well_formed(&p.ty, pos, seen);
        }
        if let Some(r) = &t.result {
            self.well_formed(r, pos, seen);
        }
    }

    /// Checks `t`'s own type arguments against its definition's bounds,
    /// without descending into those arguments.
    pub(crate) fn bounds_hold(&mut self, t: &Ty, pos: Pos) {
        let Some(def) = &t.def else {
            return;
        };
        if t.args.len() != def.arity() {
            return;
        }
        let s = substitution(t);
        for v in def.variables() {
            let Some(actual) = s.get(&v.id) else {
                continue;
            };
            for b in v.bounds() {
                let bound = sub(&b, &s);
                if !self.satisfies(actual, &bound) {
                    let msg =
                        self.unsatisfied_message(actual, &bound, "use a type that implements it");
                    if self.in_declaration_checks && self.reported_bounds.contains(&msg) {
                        continue;
                    }
                    self.reported_bounds.insert(msg.clone());
                    self.type_error(pos, msg);
                }
            }
        }
    }

    /// Well-formedness and visibility checks of a module's declarations.
    pub(crate) fn declaration_checks(&mut self, module: &ModRef) {
        self.in_declaration_checks = true;
        self.declaration_checks_inner(module);
        self.in_declaration_checks = false;
    }

    fn declaration_checks_inner(&mut self, module: &ModRef) {
        for d in &module.decls {
            if matches!(d.decl().kind, DeclKind::Test(_) | DeclKind::Impl(_)) {
                continue;
            }
            let Some(s) = self.own_symbol(d) else {
                continue;
            };
            let old = self.scope.clone();
            self.scope = self.variable_scope(&s.variables());
            self.declared_refs_bounds(d.decl());
            if s.kind == SymKind::Fn || s.kind == SymKind::Alias {
                self.check_declared(&s.ty(self.syms), d.pos(), s.export);
            } else {
                let t = s.ty(self.syms);
                let def = t.def.clone().expect("def");
                for f in def.fields.borrow().clone() {
                    self.check_declared(&f.ty, d.pos(), s.export);
                }
                for cs in def.cases.borrow().clone() {
                    for f in cs.fields {
                        self.check_declared(&f.ty, d.pos(), s.export);
                    }
                }
                for op in def.operations.borrow().clone() {
                    self.check_declared(&op.ty, d.pos(), s.export);
                    for v in self.session.operation_variables(&format!(
                        "{}/{}",
                        self.syms.str(t.id),
                        self.syms.str(op.name)
                    )) {
                        for b in v.bounds() {
                            self.check_declared(&b, d.pos(), s.export);
                        }
                        if s.export
                            && let Some(default) = v.default_ty()
                        {
                            self.public(&default, d.pos(), &mut HashSet::default());
                        }
                    }
                }
            }
            for v in s.variables() {
                for b in v.bounds() {
                    self.check_declared(&b, d.pos(), s.export);
                }
                if s.export
                    && let Some(default) = v.default_ty()
                {
                    self.public(&default, d.pos(), &mut HashSet::default());
                }
            }
            self.scope = old;
        }
    }

    /// Checks the bounds of every type written in a declaration at the written type's own position,
    /// so a violation points at `Map[K, V]` in a signature instead of at the declaration's start.
    /// `check_declared` then finds each message already reported.
    fn declared_refs_bounds(&mut self, decl: &ms_syntax::ast::Decl) {
        use ms_syntax::ast::DeclKind;
        let mut refs: Vec<&ms_syntax::ast::TypeRef> = Vec::new();
        fn params(ps: &[ms_syntax::ast::Param]) -> impl Iterator<Item = &ms_syntax::ast::TypeRef> {
            ps.iter().filter_map(|p| p.ty.as_ref())
        }
        match &decl.kind {
            DeclKind::Fn(f) => {
                refs.extend(params(&f.params));
                refs.push(&f.result);
            }
            DeclKind::Type(r) => refs.extend(params(&r.fields)),
            DeclKind::Alternative(a) => {
                for c in &a.cases {
                    refs.extend(params(&c.fields));
                }
            }
            DeclKind::Interface(i) => {
                for m in &i.methods {
                    refs.extend(params(&m.func.params));
                    refs.push(&m.func.result);
                }
            }
            _ => {}
        }
        for t in refs {
            self.type_ref_bounds(t);
        }
    }

    fn type_ref_bounds(&mut self, t: &ms_syntax::ast::TypeRef) {
        use ms_syntax::ast::TypeKind;
        match &t.kind {
            TypeKind::Named { args, .. } => {
                for a in args {
                    self.type_ref_bounds(a);
                }
            }
            TypeKind::Fn { params, result } => {
                for p in params {
                    if let Some(pt) = &p.ty {
                        self.type_ref_bounds(pt);
                    }
                }
                self.type_ref_bounds(result);
            }
        }
        let resolved = self.m().facts().type_refs.get(&t.id).cloned();
        if let Some(resolved) = resolved {
            // Each written type is its own site: report it even when the same message came up elsewhere.
            let declaration_checks = std::mem::replace(&mut self.in_declaration_checks, false);
            self.bounds_hold(&resolved, t.pos);
            self.in_declaration_checks = declaration_checks;
        }
    }

    fn check_declared(&mut self, t: &Ty, pos: Pos, export: bool) {
        self.well_formed(t, pos, &mut HashSet::default());
        if export {
            self.public(t, pos, &mut HashSet::default());
        }
    }

    fn public(&mut self, t: &Ty, pos: Pos, seen: &mut HashSet<TyId>) {
        if !seen.insert(self.shape(t)) {
            return;
        }
        if let Some(symbol) = t.symbol()
            && symbol.module == self.current_file()
            && !symbol.export
        {
            self.type_error(
                    pos,
                    format!(
                        "public signature exposes private type {}; add 'export' to its declaration or keep the function private",
                        self.syms.str(t.name)
                    ),
                );
        }
        for a in &t.args {
            self.public(a, pos, seen);
        }
        for p in &t.params {
            self.public(&p.ty, pos, seen);
        }
        if let Some(r) = &t.result {
            self.public(r, pos, seen);
        }
    }

    /// Explains a failed bound with a fix the writer can apply. An impl is
    /// suggested only for data the module may declare an impl for; built-in and
    /// collection types cannot take one, so they are told what to use instead.
    pub(crate) fn unsatisfied_message(&self, t: &Ty, bound: &Ty, alternative: &str) -> String {
        let prefix = format!(
            "{t_t} does not satisfy {bound_t}; ",
            t_t = t.display(self.syms),
            bound_t = bound.display(self.syms)
        );
        if bound.is(Builtin::TypeSet) {
            let members: Vec<String> = bound
                .args
                .iter()
                .map(|m| m.display(self.syms).to_string())
                .collect();
            return format!(
                "{t_t} is not a member of the type set {}; its members are {}",
                self.syms.str(bound.name),
                members.join(", "),
                t_t = t.display(self.syms)
            );
        }
        if bound.is(Builtin::Data)
            && let Some(blocker) = self.data_blocker(t, &mut Vec::new(), &mut Vec::new())
        {
            return blocker.message(self.syms, t);
        }
        if bound.is(Builtin::Hashable) && float_bits(t).is_some() {
            return format!(
                "{t_t} does not satisfy Hashable; Float has no Hashable implementation, so wrap it in a type with an Int or String key, or use Decimal",
                t_t = t.display(self.syms)
            );
        }
        if bound.is(Builtin::Hashable)
            && (t.is(Builtin::List) || t.is(Builtin::Map) || t.is(Builtin::Set))
        {
            return format!(
                "{prefix}collections have no Hashable implementation, so use a type as the key or join the elements into a String"
            );
        }
        if bound.is(Builtin::Hashable) && self.holds_resource(t, &mut Vec::new()) {
            return format!(
                "{prefix}it is or holds a Closeable resource, which is closed once by its owner and cannot be a set element or map key; key on a plain value such as an Int id instead"
            );
        }
        if bound.is(Builtin::Clonable) && t.kind != Kind::Variable {
            let what = if self.holds_resource(t, &mut Vec::new()) {
                "a Closeable resource, which has one owner and closes once"
            } else if holds_function(t) {
                "a function value, which owns its captures and has one owner"
            } else {
                "a native value without a `clone` of its own, which has one owner"
            };
            return format!(
                "{prefix}it is or holds {what}, so it cannot be cloned; move it, or use it in place"
            );
        }
        if matches!(t.kind, Kind::Type | Kind::Alternative)
            && let Some(symbol) = t.symbol()
            && (symbol.native == Native::Source || self.standard_declarations)
        {
            return format!(
                "{prefix}give {t_t} the methods {bound_t} declares, or {alternative}",
                bound_t = bound.display(self.syms),
                t_t = t.display(self.syms)
            );
        }
        format!("{prefix}{alternative}")
    }

    /// Whether a concrete `actual` converts implicitly to the interface `expected`.
    pub(crate) fn interface_assignable(&self, actual: &Ty, expected: &Ty) -> bool {
        expected.kind == Kind::Contract
            && actual.kind != Kind::Contract
            && !has_generic_operation(expected)
            && self.implements(actual, expected)
    }
}

/// The intrinsic interface declaring `to_string`, which every value has.
const VALUE_OPERATIONS: &str = "ValueOperations";
/// The intrinsic interface declaring `clone`, which every data value has.
const CLONE_OPERATIONS: &str = "CloneOperations";

impl Method {
    /// Whether the method is declared for every receiver type (`to_string`, `clone`) instead of
    /// one numeric family, so it runs on a sized number at its own width. A family method
    /// (`Float.to_fixed`, `Int.to_hex`) runs on the 64-bit kind.
    pub fn is_width_generic(&self, syms: ms_syntax::Names) -> bool {
        self.decl.as_ref().is_some_and(|d| {
            let owner = syms.str(d.decl.name());
            owner == VALUE_OPERATIONS || owner == CLONE_OPERATIONS
        })
    }
}

/// A standard method that exists without an impl.
pub(crate) fn native_method(
    syms: ms_syntax::Names,
    session: &Rc<crate::stdlib::Session>,
    t: &Ty,
    name: Name,
) -> Option<Method> {
    let native_of =
        |native: Name, receiver: &Ty, ty: Ty, variables: Vec<Ty>, decl: Option<FuncRef>| Method {
            id: n(""),
            module: n(""),
            local: false,
            receiver: receiver.clone(),
            contract: None,
            ty,
            variables,
            decl,
            native: Native::Builtin(native),
        };
    if syms.str(name) == "clone"
        && (matches!(t.kind, Kind::Type | Kind::Alternative)
            || (t.kind == Kind::Variable && t.bounds().iter().any(implies_clonable))
            || t.kind == Kind::Primitive
            || t.is(Builtin::List)
            || t.is(Builtin::Map)
            || t.is(Builtin::Set)
            || t.is(Builtin::Bytes))
    {
        let mut owner = t.clone();
        if matches!(
            t.kind,
            Kind::Type | Kind::Alternative | Kind::Primitive | Kind::Variable
        ) {
            owner = session.standard_symbol(CLONE_OPERATIONS)?.ty(syms);
        }
        let decl = stdlib::standard_method_declaration(&owner, name);
        return Some(native_of(
            name,
            t,
            function(syms, Vec::new(), t.clone()),
            Vec::new(),
            decl,
        ));
    }
    if syms.str(name) == "to_string" {
        let owner = session.standard_symbol(VALUE_OPERATIONS)?.ty(syms);
        let ty = owner.def.as_ref()?.operations.borrow()[0].ty.clone();
        let decl = stdlib::standard_method_declaration(&owner, name);
        return Some(native_of(name, t, ty, Vec::new(), decl));
    }
    let intrinsic = session.intrinsic_operations(t.id);
    if intrinsic.len() > 1 {
        // A primitive has its own interface and the shared ones for its family; the first with the
        // operation answers.
        return intrinsic
            .iter()
            .find_map(|interface| native_method_of(syms, session, t, name, interface, &native_of));
    }
    let receiver = intrinsic.into_iter().next().unwrap_or_else(|| t.clone());
    native_method_of(syms, session, t, name, &receiver, &native_of)
}

type NativeOf<'a> = dyn Fn(Name, &Ty, Ty, Vec<Ty>, Option<FuncRef>) -> Method + 'a;

/// The operation `name` of the standard `receiver` interface (or type) as a method of `t`.
fn native_method_of(
    syms: ms_syntax::Names,
    session: &Rc<crate::stdlib::Session>,
    t: &Ty,
    name: Name,
    receiver: &Ty,
    native_of: &NativeOf,
) -> Option<Method> {
    let receiver = receiver.clone();
    let key = format!("{}/{}", syms.str(receiver.id), syms.str(name));
    let binding = session.is_receiver_native(&key);
    let bindings = substitution(&receiver);
    let opaque_alternative = receiver.kind == Kind::Alternative
        && receiver.symbol().is_some_and(|s| s.native.is_bodiless());
    if receiver.kind == Kind::Native || !Rc::ptr_eq(&receiver, t) || binding || opaque_alternative {
        let def = receiver.def.as_ref()?;
        let operations = def.operations.borrow();
        for operation in operations.iter() {
            if operation.name == name {
                let native = name;
                return Some(native_of(
                    native,
                    t,
                    sub(&operation.ty, &bindings),
                    instantiate_operation_variables(&session.operation_variables(&key), &bindings),
                    operation.decl.clone(),
                ));
            }
        }
    }
    None
}

#[cfg(test)]
#[path = "method_candidates_tests.rs"]
mod method_candidates_tests;

#[cfg(test)]
#[path = "method_parameter_names_tests.rs"]
mod method_parameter_names_tests;
