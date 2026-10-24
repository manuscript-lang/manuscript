//! Implementations, contracts and their evidence.

use crate::checker::{Checker, Scope};
use crate::hints::{list, signature_text};
use crate::stdlib;
use crate::syntax::*;
use crate::types::Method;
use crate::types::*;
use ms_syntax::Pos;
use ms_syntax::ast::*;
use std::cell::Cell;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

thread_local! {
    /// Synthetic declarations need ids that never collide with parsed nodes.
    static SYNTHETIC_ID: Cell<u32> = const { Cell::new(0x8000_0000) };
}

fn synthetic_id() -> NodeId {
    SYNTHETIC_ID.with(|c| {
        let id = c.get();
        c.set(id + 1);
        NodeId(id)
    })
}

/// Visit state of a structural property query.
#[derive(Default)]
pub(crate) struct PropertyState {
    active: HashSet<String>,
    completed: HashMap<String, bool>,
}

/// Whether two implementations could apply to one receiver and contract.
fn overlap(a: &Ty, b: &Ty, x: &Ty, y: &Ty, vars: &[Ty]) -> bool {
    struct Unifier {
        variable: VarSet,
        sub: Subst,
    }
    impl Unifier {
        fn deref(&self, t: &Ty) -> Ty {
            let mut seen: HashSet<Name> = HashSet::new();
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
                    if p.name != q.name || !self.matches(&p.ty, &q.ty) {
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
        sub: Subst::new(),
    };
    u.matches(a, x) && u.matches(b, y)
}

/// Standard types whose native compare operation satisfies Comparable without
/// an impl.
fn builtin_comparable(t: &Ty) -> bool {
    matches!(
        t.id.as_str(),
        "Int"
            | "Float"
            | "String"
            | "@std/Decimal"
            | "@std/BigInt"
            | "@std/Duration"
            | "@std/Instant"
            | "@std/Timestamp"
    )
}

fn operation_names(ops: &[Operation]) -> Vec<String> {
    ops.iter().map(|o| o.name.to_string()).collect()
}

impl Checker {
    /// Declares the methods of one `impl` block.
    pub(crate) fn implementation(&mut self, d: &DeclRef) {
        let DeclKind::Impl(imp) = &d.decl().kind else {
            return;
        };
        let old = std::mem::replace(&mut self.scope, Scope::new(None));
        // Implementations inherit names and bounds from the nominal receiver declaration.
        let mut vars: Vec<Ty> = Vec::new();
        let receiver_name = n(imp.receiver.name());
        if let Some(symbol) = self.sym(receiver_name)
            && symbol.decl.is_some()
            && symbol.kind == SymKind::Type
        {
            // Copy resolved bounds: their names belong to the receiver's module and
            // need not be imported by a module extending that receiver.
            let mut substitution = Subst::new();
            for parameter in symbol.variables() {
                let id = self.unique("typevar");
                let v: Ty = Rc::new(Type::new(parameter.name, id, Kind::Variable));
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
        // A bundled module may add methods to the `extern type` it declares.
        let own_extern = receiver.kind == Kind::Native
            && nominal
                .as_ref()
                .is_some_and(|s| s.module == self.current_file());
        let foreign_native = nominal
            .as_ref()
            .is_some_and(|s| !s.native.as_str().is_empty())
            && !self.standard_declarations
            && !own_extern;
        if nominal.is_none()
            || foreign_native
            || !(own_extern || matches!(receiver.kind, Kind::Record | Kind::Alternative))
        {
            if receiver.id != "<invalid>" {
                self.type_error(
                    d.pos(),
                    "implementation receiver must be nominal source data; implement interfaces for a type or alternative you declare, such as 'impl Show for Point:', not for built-in or function types",
                );
            }
            // An impl whose receiver is not valid nominal data must not become
            // evidence for later conversions; report the receiver's own faults only.
            self.well_formed(&receiver, d.pos(), &mut HashSet::new());
            self.scope = old;
            return;
        }
        let mut occurs: HashSet<Name> = HashSet::new();
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
        let mut specialized = Subst::new();
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
        if contract.kind != Kind::Contract && contract.id != "<invalid>" {
            self.type_error(
                d.pos(),
                "implementation target must be an interface; write 'impl <Interface> for <Type>:' where the interface is declared with 'interface'",
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
        let overlapping = self.p.methods.iter().any(|m| {
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
                    "duplicate or overlapping implementation; {contract} is already implemented for {receiver} (or an overlapping type), so remove one impl"
                ),
            );
        }
        let mut seen: HashSet<Name> = HashSet::new();
        let mut ops: Vec<Operation> = Vec::new();
        if let Some(def) = &contract.def {
            let s = substitution(&contract);
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
                .is_some_and(|s| s.module != this.current_file())
        };
        for (index, method) in imp.methods.iter().enumerate() {
            if !seen.insert(method.func.name) {
                self.type_error(
                    method.pos,
                    format!(
                        "duplicate implementation operation {}; define each operation once per impl",
                        method.func.name
                    ),
                );
            }
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
                        .map(|d| (**d).clone())
                        .unwrap_or_default();
                    if let Some(allowed) = &op.ty.defaults {
                        merged.extend(allowed.iter().copied());
                    }
                    t.defaults = Some(Rc::new(merged));
                }
                if !same(&Rc::new(t.clone()), &op.ty) {
                    self.type_error(
                        method.pos,
                        format!(
                            "implementation operation signature does not match contract; {} must be declared as fn {}{}",
                            method.func.name,
                            method.func.name,
                            signature_text(&op.ty)
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
                        "implementation of {} is declared {have} but {contract} declares it {want}; an operation that changes its receiver is declared `var fn` in the interface too",
                        method.func.name
                    ),
                );
            }
            if !found {
                self.type_error(
                    method.pos,
                    format!(
                        "extra operation {}; {} declares: {} (remove it or add it to the interface)",
                        method.func.name,
                        contract,
                        list(&operation_names(&ops), 12)
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
                variables: vars.clone(),
                decl: Some(FuncRef {
                    decl: d.clone(),
                    index: Some(index),
                }),
                native: n(""),
            };
            self.p.methods.push(Rc::new(m));
        }
        for op in &ops {
            if seen.contains(&op.name) {
                continue;
            }
            if contract.is_std("TestHooks") {
                // This standard lifecycle contract has no-op defaults; retain ordinary
                // checked methods so interface calls and generic bounds use normal dispatch.
                let decl = DeclRef::new(Decl {
                    id: synthetic_id(),
                    pos: d.pos(),
                    export: false,
                    synthetic: true,
                    kind: DeclKind::Fn(Func {
                        name: op.name,
                        type_params: Vec::new(),
                        params: Vec::new(),
                        result: TypeRef {
                            id: synthetic_id(),
                            pos: d.pos(),
                            kind: TypeKind::Named {
                                name: n("Unit"),
                                args: Vec::new(),
                            },
                        },
                        result_ref: false,
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
                    native: n(""),
                };
                self.p.methods.push(Rc::new(m));
            } else {
                self.type_error(
                    d.pos(),
                    format!(
                        "missing implementation operation {}; add fn {}{} to this impl",
                        op.name,
                        op.name,
                        signature_text(&op.ty)
                    ),
                );
            }
        }
        self.well_formed(&receiver, d.pos(), &mut HashSet::new());
        self.well_formed(&contract, d.pos(), &mut HashSet::new());
        self.scope = old;
    }

    /// Whether `receiver` implements `contract`.
    pub(crate) fn implements(&self, receiver: &Ty, contract: &Ty) -> bool {
        if receiver.id == contract.id {
            return same(receiver, contract);
        }
        if contract.is_std("Equal") || contract.is_std("Hashable") || contract.is_std("Clonable") {
            return self.property(receiver, contract.name.as_str(), None);
        }
        if receiver.kind == Kind::Variable {
            return receiver.bounds().iter().any(|b| same(b, contract));
        }
        for m in &self.p.methods {
            if !self.method_visible(m) {
                continue;
            }
            let Some(mc) = &m.contract else {
                continue;
            };
            let mut s = Subst::new();
            if unify(&m.receiver, receiver, &variable_set(&m.variables), &mut s)
                && same(&sub(mc, &s), contract)
                && self.bounds_satisfied(&m.variables, &s)
            {
                return true;
            }
        }
        contract.is_std("Comparable") && builtin_comparable(receiver)
    }

    /// Whether `.clone()` is available for `t`: plain data is, resource handles and functions are not.
    fn clonable(&self, t: &Ty, state: &mut PropertyState) -> bool {
        match t.kind {
            Kind::Variable => return t.bounds().iter().any(|b| b.is_std("Clonable")),
            Kind::Contract => return false,
            Kind::Function | Kind::Primitive => return true,
            _ => {}
        }
        if t.is_std("List") || t.is_std("Map") || t.is_std("Set") {
            return t
                .args
                .iter()
                .all(|a| self.property_in(a, "Clonable", state));
        }
        if t.is_std("Regex") {
            return false;
        }
        if t.kind == Kind::Native {
            return t.is_std("Bytes")
                || t.is_std("Decimal")
                || t.is_std("BigInt")
                || t.is_std("Duration")
                || t.is_std("Instant")
                || t.is_std("Timestamp");
        }
        if t.def.is_some() {
            return fields(t)
                .iter()
                .all(|f| self.property_in(&f.ty, "Clonable", state));
        }
        true
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
        if bound.is_std("Equal") || bound.is_std("Hashable") || bound.is_std("Clonable") {
            return self.property(t, bound.name.as_str(), None);
        }
        self.implements(t, bound)
    }

    /// Structural Equal/Hashable evidence.
    pub(crate) fn property(
        &self,
        t: &Ty,
        property: &str,
        state: Option<&mut PropertyState>,
    ) -> bool {
        match state {
            Some(s) => self.property_in(t, property, s),
            None => self.property_in(t, property, &mut PropertyState::default()),
        }
    }

    fn property_in(&self, t: &Ty, property: &str, state: &mut PropertyState) -> bool {
        if t.id == "<invalid>" {
            return true;
        }
        let key = format!("{}{}", type_key(t), property);
        if let Some(&r) = state.completed.get(&key) {
            return r;
        }
        if state.active.contains(&key) {
            // Equality handles cycles; structural hashing requires an acyclic shape.
            return property != "Hashable";
        }
        if state.active.len() > 200 {
            return false;
        }
        state.active.insert(key.clone());
        let result = self.property_compute(t, property, state);
        state.active.remove(&key);
        state.completed.insert(key, result);
        result
    }

    fn property_compute(&self, t: &Ty, property: &str, state: &mut PropertyState) -> bool {
        if property == "Clonable" {
            return self.clonable(t, state);
        }
        if t.kind == Kind::Variable {
            return t
                .bounds()
                .iter()
                .any(|b| b.is_std(property) || (b.is_std("Hashable") && property == "Equal"));
        }
        // Explicit implementations take precedence over structural data semantics.
        for m in &self.p.methods {
            if !self.method_visible(m) || !m.contract.as_ref().is_some_and(|c| c.is_std(property)) {
                continue;
            }
            let mut s = Subst::new();
            if unify(&m.receiver, t, &variable_set(&m.variables), &mut s)
                && self.bounds_satisfied(&m.variables, &s)
            {
                return property != "Hashable" || self.property(t, "Equal", None);
            }
        }
        if property == "Hashable" {
            for m in &self.p.methods {
                if !self.method_visible(m)
                    || !m.contract.as_ref().is_some_and(|c| c.is_std("Equal"))
                {
                    continue;
                }
                let mut s = Subst::new();
                if unify(&m.receiver, t, &variable_set(&m.variables), &mut s)
                    && self.bounds_satisfied(&m.variables, &s)
                {
                    return false;
                }
            }
        }
        match t.kind {
            Kind::Function | Kind::Contract => return false,
            Kind::Primitive => return t.id != "Float" || property != "Hashable",
            _ => {}
        }
        if t.is_std("Decimal") || t.is_std("Bytes") || t.is_std("Duration") || t.is_std("Instant") {
            return true;
        }
        if t.is_std("List") || t.is_std("Map") || t.is_std("Set") {
            if property == "Hashable" {
                return false;
            }
            return t.args.iter().all(|a| self.property_in(a, property, state));
        }
        if t.is_std("BigInt") || t.is_std("Regex") || t.is_std("Timestamp") {
            return property == "Equal" && !t.is_std("Regex");
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

    /// Methods named `name` available on `receiver`.
    pub(crate) fn methods(&self, receiver: &Ty, name: Name) -> Vec<MethodRef> {
        if let Some(m) = native_method(receiver, name)
            && self.native_receiver_available(receiver, name)
        {
            return vec![Rc::new(m)];
        }
        if receiver.kind == Kind::Contract
            && let Some(def) = &receiver.def
        {
            let found = def
                .operations
                .borrow()
                .iter()
                .find(|o| o.name == name)
                .cloned();
            if let Some(op) = found {
                return vec![Rc::new(Method {
                    id: n(""),
                    module: n(""),
                    local: false,
                    receiver: receiver.clone(),
                    contract: Some(receiver.clone()),
                    ty: sub(&op.ty, &substitution(receiver)),
                    variables: stdlib::operation_variables(&format!("{}/{}", receiver.id, name)),
                    decl: op.decl.clone(),
                    native: n("contract"),
                })];
            }
        }
        if receiver.kind == Kind::Variable {
            let mut result: Vec<MethodRef> = Vec::new();
            for b in receiver.bounds() {
                if b.kind == Kind::Contract {
                    result.extend(self.methods(&b, name));
                }
            }
            return result;
        }
        let mut result: Vec<MethodRef> = Vec::new();
        for m in &self.p.methods {
            if !self.method_visible(m) || m.name() != Some(name) {
                continue;
            }
            let mut s = Subst::new();
            if unify(&m.receiver, receiver, &variable_set(&m.variables), &mut s)
                && self.bounds_satisfied(&m.variables, &s)
            {
                let mut r = (**m).clone();
                r.ty = sub(&m.ty, &s);
                r.contract = m.contract.as_ref().map(|c| sub(c, &s));
                r.receiver = receiver.clone();
                r.variables = Vec::new(); // Implementation variables are fixed by the receiver.
                result.push(Rc::new(r));
            }
        }
        if result.is_empty() && (name == "equals" || name == "hash") {
            let property = if name == "hash" { "Hashable" } else { "Equal" };
            if self.property(receiver, property, None) {
                let contract = standard(property, vec![]);
                let operation = contract
                    .def
                    .as_ref()
                    .map(|d| d.operations.borrow()[0].clone())
                    .expect("operation");
                return vec![Rc::new(Method {
                    id: n(""),
                    module: n(""),
                    local: false,
                    receiver: receiver.clone(),
                    contract: Some(contract.clone()),
                    ty: operation.ty,
                    variables: Vec::new(),
                    decl: stdlib::standard_method_declaration(&contract, name),
                    native: name,
                })];
            }
        }
        result
    }

    /// Whether a method is usable from the module being checked.
    pub(crate) fn method_visible(&self, m: &Method) -> bool {
        m.visible_in(self.current_file())
    }

    /// Whether a value of `t` can be bound by `with`.
    pub(crate) fn closeable(&self, t: &Ty) -> bool {
        if t.kind == Kind::Contract || t.kind == Kind::Variable {
            return self
                .methods(t, n("close"))
                .iter()
                .any(|m| m.ty.params.is_empty() && m.ty.result_ty().id == "Unit");
        }
        self.implements(t, &standard("Closeable", vec![]))
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
                    self.type_error(pos, msg);
                }
            }
        }
    }

    /// Well-formedness and visibility checks of a module's declarations.
    pub(crate) fn declaration_checks(&mut self, module: &ModRef) {
        for d in &module.decls {
            if matches!(d.decl().kind, DeclKind::Test(_) | DeclKind::Impl(_)) {
                continue;
            }
            let Some(s) = self.own_symbol(d) else {
                continue;
            };
            let old = self.scope.clone();
            self.scope = self.variable_scope(&s.variables());
            if s.kind == SymKind::Fn {
                self.check_declared(&s.ty(), d.pos(), s.export);
            } else {
                let t = s.ty();
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
                }
            }
            for v in s.variables() {
                for b in v.bounds() {
                    self.check_declared(&b, d.pos(), s.export);
                }
            }
            self.scope = old;
        }
    }

    fn check_declared(&mut self, t: &Ty, pos: Pos, export: bool) {
        self.well_formed(t, pos, &mut HashSet::new());
        if export {
            self.public(t, pos, &mut HashSet::new());
        }
    }

    fn public(&mut self, t: &Ty, pos: Pos, seen: &mut HashSet<String>) {
        if !seen.insert(type_key(t)) {
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
                        t.name
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
        let prefix = format!("{t} does not satisfy {bound}; ");
        if bound.is_std("Hashable") && t.id == "Float" {
            return format!(
                "{t} does not satisfy Hashable; Float has no Hashable implementation, so wrap it in a record with an Int or String key, or use Decimal"
            );
        }
        if bound.is_std("Hashable") && (t.is_std("List") || t.is_std("Map") || t.is_std("Set")) {
            return format!(
                "{prefix}collections have no Hashable implementation, so use a record key or join the elements into a String"
            );
        }
        if matches!(t.kind, Kind::Record | Kind::Alternative)
            && let Some(symbol) = t.symbol()
            && (symbol.native.as_str().is_empty() || self.standard_declarations)
        {
            return format!("{prefix}add 'impl {bound} for {t}:' or {alternative}");
        }
        format!("{prefix}{alternative}")
    }

    /// Explains a failed `with` binding. Built-in and wrapper types cannot
    /// receive an implementation, so they are told to unwrap the value first.
    pub(crate) fn with_not_closeable_message(&self, t: &Ty) -> String {
        let name = t.to_string();
        if t.is_std("Result") || t.is_std("Optional") {
            return format!(
                "with needs a Closeable value, but this expression is {name}; unwrap it first with 'try' (inside a function that returns a compatible Result) or 'if let'"
            );
        }
        let nominal = t.symbol().is_some_and(|s| s.native.as_str().is_empty())
            && matches!(t.kind, Kind::Record | Kind::Alternative);
        if !nominal {
            return format!(
                "with needs a Closeable value, but this expression is {name}, which cannot implement Closeable; bind a source type that has 'impl Closeable' or declares close() Unit"
            );
        }
        format!(
            "with requires an explicit Closeable implementation or a contract declaring close() Unit; {name} has none, so add 'impl Closeable for {name}:' with var fn close() Unit"
        )
    }

    /// Whether the Error boundary accepts `actual` where `expected` is written.
    pub(crate) fn error_assignable(&self, actual: &Ty, expected: &Ty) -> bool {
        if expected.is_std("Error") {
            return self.implements(actual, expected);
        }
        actual.is_std("Result")
            && expected.is_std("Result")
            && actual.args.len() == 2
            && expected.args.len() == 2
            && same(&actual.args[0], &expected.args[0])
            && expected.args[1].is_std("Error")
            && self.implements(&actual.args[1], &expected.args[1])
    }

    /// Whether crossing an Error boundary with `receiver` needs dispatch
    /// evidence. Ordinary domain errors pass through unchanged; local
    /// implementations and generic receivers retain the evidence needed outside
    /// this module.
    pub(crate) fn error_needs_scope(&self, receiver: &Ty) -> bool {
        if receiver.kind == Kind::Variable || !receiver.args.is_empty() {
            return true;
        }
        self.methods(receiver, n("message"))
            .iter()
            .any(|m| m.contract.as_ref().is_some_and(|c| c.is_std("Error")) && m.local)
    }
}

/// A standard method that exists without an impl.
pub(crate) fn native_method(t: &Ty, name: Name) -> Option<Method> {
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
            native,
        };
    if name == "clone"
        && (matches!(t.kind, Kind::Record | Kind::Alternative)
            || (t.kind == Kind::Variable && t.bounds().iter().any(|b| b.is_std("Clonable")))
            || (t.kind == Kind::Primitive && t.id.as_str() == "String")
            || t.is_std("List")
            || t.is_std("Map")
            || t.is_std("Set")
            || t.is_std("Bytes"))
    {
        let mut owner = t.clone();
        if matches!(
            t.kind,
            Kind::Record | Kind::Alternative | Kind::Primitive | Kind::Variable
        ) {
            owner = stdlib::standard_symbol("CloneOperations")?.ty();
        }
        let decl = stdlib::standard_method_declaration(&owner, name);
        return Some(native_of(
            name,
            t,
            function(Vec::new(), t.clone()),
            Vec::new(),
            decl,
        ));
    }
    if name == "to_string" {
        let owner = stdlib::standard_symbol("ValueOperations")?.ty();
        let ty = owner.def.as_ref()?.operations.borrow()[0].ty.clone();
        let decl = stdlib::standard_method_declaration(&owner, name);
        return Some(native_of(name, t, ty, Vec::new(), decl));
    }
    let mut receiver = t.clone();
    if let Some(intrinsic) = stdlib::intrinsic_operations(t.id) {
        receiver = intrinsic;
    }
    let key = format!("{}/{}", receiver.id, name);
    let binding = stdlib::receiver_binding(&key);
    let opaque_alternative = receiver.kind == Kind::Alternative
        && receiver
            .symbol()
            .is_some_and(|s| !s.native.as_str().is_empty());
    if receiver.kind == Kind::Native
        || !Rc::ptr_eq(&receiver, t)
        || binding.is_some()
        || opaque_alternative
    {
        let def = receiver.def.as_ref()?;
        let operations = def.operations.borrow();
        for operation in operations.iter() {
            if operation.name == name {
                let native = binding.unwrap_or(name);
                return Some(native_of(
                    native,
                    t,
                    sub(&operation.ty, &substitution(t)),
                    stdlib::operation_variables(&key),
                    operation.decl.clone(),
                ));
            }
        }
    }
    None
}
