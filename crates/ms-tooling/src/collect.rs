//! Derives the review fact model from a checked program and its inspection.

use crate::facts::{
    Fact, Facts, ParameterOwnership, ResultOwnership, Slot, append_unique, error_type, fact_key,
};
use crate::flow::{FlowBuilder, Site, StmtView};
use ms_check::api::syntax::{DeclRef, FuncRef};
use ms_check::{ModRef, Program};
use ms_syntax::visit::{Visitor, walk_callable, walk_expr};
use ms_syntax::{
    DeclKind, Expr, ExprKind, Method, NodeId, Param, Stmt, StmtKind, TypeKind, TypeRef, UnaryOp,
};
use std::collections::{HashMap, HashSet};

/// An inspection entity, as far as facts need it.
#[derive(Clone, Debug, Default)]
pub struct EntityRow {
    pub id: String,
    pub kind: String,
    pub name: String,
    pub ty: String,
    pub file: String,
    pub line: usize,
    pub exported: bool,
    pub effects: Vec<String>,
    pub reach: Vec<String>,
    pub permits: Vec<String>,
}

/// An inspection call site, as far as facts need it.
#[derive(Clone, Debug, Default)]
pub struct CallRow {
    pub id: String,
    pub owner: String,
    pub target: String,
    pub kind: String,
    /// A `TaskGroup.spawn` call.
    pub spawn: bool,
}

/// The slice of an inspection that facts are derived from.
#[derive(Clone, Debug, Default)]
pub struct InspectionRows {
    pub entities: Vec<EntityRow>,
    pub calls: Vec<CallRow>,
}

/// Derives the review fact model from a checked program.
pub fn collect_facts(
    syms: ms_syntax::Names,
    inspection: &InspectionRows,
    program: &Program,
) -> Facts {
    let mut facts = Facts::default();
    let mut id_to_key: HashMap<String, String> = HashMap::new();
    for e in inspection
        .entities
        .iter()
        .filter(|e| !e.file.starts_with("@std/"))
    {
        let key = fact_key(&e.file, &e.kind, &e.name);
        facts.entities.insert(
            key.clone(),
            Fact {
                key: key.clone(),
                file: e.file.clone(),
                kind: e.kind.clone(),
                name: e.name.clone(),
                ty: e.ty.clone(),
                exported: e.exported,
                line: e.line,
                effects: e.effects.clone(),
                reach: e.reach.clone(),
                permits: e.permits.clone(),
                error: error_type(&e.ty),
                ..Fact::default()
            },
        );
        id_to_key.insert(e.id.clone(), key);
    }
    // A standard-library method has no fact, and its id embeds a source offset;
    // name it by receiver and method so external edges stay readable.
    let std_methods: HashMap<&str, &str> = inspection
        .entities
        .iter()
        .filter(|e| e.file.starts_with("@std/") && e.kind == "method")
        .map(|e| (e.id.as_str(), e.name.as_str()))
        .collect();
    // Borrow identities for membership; allocate an owned target only once per
    // distinct edge, including when many sites call the same target.
    let mut edges = HashSet::new();
    for call in &inspection.calls {
        let Some(owner_key) = id_to_key.get(&call.owner) else {
            continue;
        };
        let target_key = id_to_key.get(&call.target);
        let target = target_key.map(String::as_str).unwrap_or_else(|| {
            std_methods
                .get(call.target.as_str())
                .copied()
                .unwrap_or(&call.target)
        });
        if !edges.insert((owner_key, target, target_key.is_some())) {
            continue;
        }
        let owner = facts.entities.get_mut(owner_key).expect("indexed owner");
        if target_key.is_some() {
            owner.calls.push(target.to_string());
        } else {
            owner.external.push(target.to_string());
        }
    }
    let sites: HashMap<String, Site> = inspection
        .calls
        .iter()
        .map(|c| {
            (
                c.id.clone(),
                Site {
                    target: c.target.clone(),
                    kind: c.kind.clone(),
                    spawn: c.spawn,
                },
            )
        })
        .collect();
    for module in program.modules.iter().filter(|m| !m.is_standard(syms)) {
        facts
            .imports
            .entry(syms.str(module.file).to_string())
            .or_default();
        for import in &module.imports {
            append_unique(
                facts
                    .imports
                    .entry(syms.str(module.file).to_string())
                    .or_default(),
                &import.path,
            );
        }
        let source: &str = &module.source;
        facts
            .sources
            .insert(syms.str(module.file).to_string(), source.to_string());
        let module_facts = module.facts();
        let scoped: HashSet<NodeId> = module_facts
            .patterns
            .iter()
            .filter(|(_, b)| {
                program
                    .ownership
                    .binding_facts
                    .has(b.uid, ms_check::api::ownership::BindingFact::ImplicitClose)
            })
            .map(|(id, _)| *id)
            .collect();
        let flow = FlowBuilder {
            file: syms.str(module.file),
            lines: source.split('\n').collect(),
            sites: &sites,
            keys: &id_to_key,
            const_use: &module_facts.const_use,
            scoped: &scoped,
        };
        collect_bodies(syms, &mut facts, module, &flow);
    }
    collect_ownership(syms, &mut facts, program);
    resolve_type_refs(syms, &mut facts, program);
    for fact in facts.entities.values_mut() {
        fact.calls.sort();
        fact.external.sort();
        fact.effects.sort();
        fact.reach.sort();
        fact.permits.sort();
    }
    for list in facts.imports.values_mut() {
        list.sort();
    }
    facts
}

/// Reuse the checker contract instead of recognizing a short list of scalar spellings.
fn collect_ownership(syms: ms_syntax::Names, facts: &mut Facts, program: &Program) {
    let classes = ms_check::api::ownership::Classifier::new(program);
    for module in program
        .hir()
        .modules()
        .filter(|m| !m.data.is_standard(syms))
    {
        for decl in &module.data.decls {
            let (kind, name) = kind_and_name(syms, decl);
            if matches!(decl.decl().kind, DeclKind::Fn(_))
                && let Some(fact) =
                    facts
                        .entities
                        .get_mut(&fact_key(syms.str(module.data.file), kind, &name))
            {
                callable_ownership(
                    syms,
                    fact,
                    program,
                    &classes,
                    &module,
                    &FuncRef::of_decl(decl.clone()),
                );
            }
            for (index, method) in decl.methods().iter().enumerate() {
                let key = fact_key(
                    syms.str(module.data.file),
                    "method",
                    &format!("{name}.{}", syms.str(method.func.name)),
                );
                if let Some(fact) = facts.entities.get_mut(&key) {
                    callable_ownership(
                        syms,
                        fact,
                        program,
                        &classes,
                        &module,
                        &FuncRef {
                            decl: decl.clone(),
                            index: Some(index),
                        },
                    );
                }
            }
        }
    }
}

fn callable_ownership(
    syms: ms_syntax::Names,
    fact: &mut Fact,
    program: &Program,
    classes: &ms_check::api::ownership::Classifier,
    module: &ms_check::api::hir::ModuleHir,
    callable: &FuncRef,
) {
    use ms_check::api::ownership::{Class, Fact as OwnershipFact};
    let Some(func) = callable.func() else {
        return;
    };
    let node = callable.id();
    let method = callable.index.is_some();
    let file = module.data.file;
    let moving = program.ownership.moving_params.get(&(file, node));
    let checked = module.data.facts();
    for (index, (slot, param)) in fact.slots.iter_mut().zip(&func.params).enumerate() {
        let ty = param
            .ty
            .as_ref()
            .and_then(|t| module.type_ref(t.id))
            .or_else(|| {
                checked
                    .decls
                    .get(&node)
                    .and_then(|d| d.parameters.get(index))
                    .map(|b| b.ty.clone())
            });
        slot.ownership = if ty
            .as_ref()
            .is_some_and(|ty| classes.class(syms, ty) == Class::Copy)
        {
            ParameterOwnership::Copy
        } else if moving
            .and_then(|m| m.get(index + usize::from(method)))
            .copied()
            .unwrap_or(false)
        {
            ParameterOwnership::Move
        } else {
            ParameterOwnership::Borrow
        };
    }
    if let Some(index) = callable.index {
        fact.receiver = if callable.decl.methods()[index].mutating {
            "var"
        } else if moving.and_then(|m| m.first()).copied().unwrap_or(false) {
            "move"
        } else {
            "borrow"
        };
    }
    let has = |flag| program.ownership.node_facts.has(file, node, flag);
    fact.result_ownership = match (
        has(OwnershipFact::BorrowedOk),
        has(OwnershipFact::BorrowedError),
    ) {
        (true, true) => ResultOwnership::BorrowedBoth,
        (true, false) => ResultOwnership::BorrowedOk,
        (false, true) => ResultOwnership::BorrowedError,
        (false, false) if has(OwnershipFact::ReturnsBorrow) => ResultOwnership::Borrow,
        (false, false) if has(OwnershipFact::ReturnsView) => ResultOwnership::View,
        _ => ResultOwnership::Owned,
    };
}

/// The entity kind and name Go gives a declaration.
fn kind_and_name(syms: ms_syntax::Names, decl: &DeclRef) -> (&'static str, String) {
    let d = decl.decl();
    match &d.kind {
        DeclKind::Fn(f) => ("fn", syms.str(f.name).to_string()),
        DeclKind::Const(c) => ("constant", syms.str(c.name).to_string()),
        DeclKind::Type(r) => ("type", syms.str(r.name).to_string()),
        DeclKind::Alternative(a) => ("alternative", syms.str(a.name).to_string()),
        DeclKind::Alias(a) => ("alias", syms.str(a.name).to_string()),
        DeclKind::Interface(i) => ("interface", syms.str(i.name).to_string()),
        DeclKind::Impl(i) => ("impl", i.display_name(syms, d.synthetic)),
        DeclKind::Test(t) => (if t.bench { "bench" } else { "test" }, t.name.to_string()),
    }
}

/// Counts try and with sites and records each entity's line range.
fn collect_bodies(syms: ms_syntax::Names, facts: &mut Facts, module: &ModRef, flow: &FlowBuilder) {
    let total = module.source.matches('\n').count() + 1;
    let decls = &module.decls;
    for (index, decl) in decls.iter().enumerate() {
        let last = match decls.get(index + 1) {
            Some(next) => next.pos().line as usize - 1,
            None => total,
        };
        let (kind, name) = kind_and_name(syms, decl);
        let key = fact_key(syms.str(module.file), kind, &name);
        if let Some(fact) = facts.entities.get_mut(&key) {
            fact.first = decl.pos().line as usize;
            fact.last = last;
            (fact.tries, fact.scopes) = count_declaration(flow.scoped, decl);
            let steps = match &decl.decl().kind {
                DeclKind::Fn(f) => flow.body(&f.body),
                DeclKind::Test(t) => flow.body(&t.body),
                DeclKind::Const(c) => {
                    flow.statement(&StmtView::constant(c.init_pos, &c.value), None)
                }
                _ => Vec::new(),
            };
            facts.flows.insert(key, steps);
            let (slots, result) = declared_slots(syms, &decl.decl().kind);
            fact.slots = slots;
            fact.result = result;
        }
        let methods = decl.methods();
        for (i, method) in methods.iter().enumerate() {
            let end = methods
                .get(i + 1)
                .map_or(last, |next| next.pos.line as usize - 1);
            let key = fact_key(
                syms.str(module.file),
                "method",
                &format!("{name}.{}", syms.str(method.func.name)),
            );
            if let Some(fact) = facts.entities.get_mut(&key) {
                if let DeclKind::Impl(i) = &decl.decl().kind {
                    fact.label =
                        format!("{}.{}", i.receiver.name(syms), syms.str(method.func.name));
                }
                fact.first = method.pos.line as usize;
                fact.last = end;
                (fact.tries, fact.scopes) = count_method(flow.scoped, method);
                fact.slots = method.func.params.iter().map(|p| slot(syms, p)).collect();
                fact.result = Some(type_slot(syms, "", &method.func.result));
                facts.flows.insert(key, flow.body(&method.func.body));
            }
        }
    }
}

fn slot(syms: ms_syntax::Names, p: &Param) -> Slot {
    let mut slot = match &p.ty {
        Some(ty) => type_slot(syms, syms.str(p.name), ty),
        None => Slot {
            name: syms.str(p.name).to_string(),
            ..Slot::default()
        },
    };
    slot.var = p.mutable;
    slot
}

fn type_slot(syms: ms_syntax::Names, name: &str, ty: &TypeRef) -> Slot {
    Slot {
        name: name.to_string(),
        ty: type_text(syms, ty),
        var: false,
        ownership: ParameterOwnership::default(),
        refs: Vec::new(),
    }
}

/// The type as written, with its arguments.
fn type_text(syms: ms_syntax::Names, ty: &TypeRef) -> String {
    match &ty.kind {
        TypeKind::Named { name, args } if args.is_empty() => syms.str(name).to_string(),
        TypeKind::Named { name, args } => {
            let args: Vec<String> = args.iter().map(|a| type_text(syms, a)).collect();
            format!("{}[{}]", syms.str(name), args.join(", "))
        }
        TypeKind::Fn { params, result } => {
            let params: Vec<String> = params
                .iter()
                .filter_map(|p| p.ty.as_ref().map(|t| type_text(syms, t)))
                .collect();
            format!("fn({}) {}", params.join(", "), type_text(syms, result))
        }
    }
}

/// Fields, case payloads, or parameters, and the result, of one declaration.
fn declared_slots(syms: ms_syntax::Names, kind: &DeclKind) -> (Vec<Slot>, Option<Slot>) {
    match kind {
        DeclKind::Type(r) => (r.fields.iter().map(|p| slot(syms, p)).collect(), None),
        DeclKind::Alternative(a) => {
            let cases = a
                .cases
                .iter()
                .map(|c| {
                    let fields: Vec<Slot> = c.fields.iter().map(|p| slot(syms, p)).collect();
                    let text: Vec<String> = fields
                        .iter()
                        .map(|f| format!("{}: {}", f.name, f.ty))
                        .collect();
                    let mut refs = Vec::new();
                    for f in &fields {
                        for r in &f.refs {
                            append_unique(&mut refs, r);
                        }
                    }
                    Slot {
                        name: syms.str(c.name).to_string(),
                        ty: if text.is_empty() {
                            String::new()
                        } else {
                            format!("({})", text.join(", "))
                        },
                        var: false,
                        ownership: ParameterOwnership::default(),
                        refs,
                    }
                })
                .collect();
            (cases, None)
        }
        DeclKind::Interface(i) => (
            i.methods
                .iter()
                .map(|m| {
                    let params: Vec<Slot> = m.func.params.iter().map(|p| slot(syms, p)).collect();
                    let result = type_slot(syms, "", &m.func.result);
                    let text: Vec<String> = params
                        .iter()
                        .map(|p| format!("{}: {}", p.name, p.ty))
                        .collect();
                    let mut refs = result.refs.clone();
                    for p in &params {
                        for r in &p.refs {
                            append_unique(&mut refs, r);
                        }
                    }
                    Slot {
                        name: syms.str(m.func.name).to_string(),
                        ty: format!("({}) {}", text.join(", "), result.ty),
                        var: m.mutating,
                        ownership: ParameterOwnership::Unspecified,
                        refs,
                    }
                })
                .collect(),
            None,
        ),
        DeclKind::Fn(f) => (
            f.params.iter().map(|p| slot(syms, p)).collect(),
            Some(type_slot(syms, "", &f.result)),
        ),
        DeclKind::Alias(a) => {
            let targets: Vec<String> = a.targets.iter().map(|t| type_text(syms, t)).collect();
            let mut slot = type_slot(syms, "", &a.targets[0]);
            slot.ty = targets.join(" | ");
            (Vec::new(), Some(slot))
        }
        _ => (Vec::new(), None),
    }
}

/// Resolve relationships from checked type identities, including imported declarations and
/// local type variables, rather than guessing from a project's globally repeated spellings.
fn resolve_type_refs(syms: ms_syntax::Names, facts: &mut Facts, program: &Program) {
    use ms_check::api::types::Ty;

    let mut checked: HashMap<String, Ty> = HashMap::new();
    for module in program.modules.iter().filter(|m| !m.is_standard(syms)) {
        let Some(names) = program.symbols.get(&module.file) else {
            continue;
        };
        let names = names.borrow();
        for decl in &module.decls {
            let Some(symbol) = names.get(&decl.name()) else {
                continue;
            };
            if symbol.decl.as_ref().is_some_and(|d| d.same(decl))
                && let Some(ty) = symbol.ty_opt()
            {
                let (kind, name) = kind_and_name(syms, decl);
                checked.insert(fact_key(syms.str(module.file), kind, &name), ty);
            }
        }
    }
    for method in &program.methods {
        let Some(decl) = &method.decl else {
            continue;
        };
        let (_, owner) = kind_and_name(syms, &decl.decl);
        let key = fact_key(
            syms.str(method.module),
            "method",
            &format!("{owner}.{}", syms.str(decl.name())),
        );
        if facts.entities.contains_key(&key) {
            checked.insert(key, method.ty.clone());
        }
    }
    let project: HashSet<String> = facts.entities.keys().cloned().collect();
    for fact in facts.entities.values_mut() {
        let Some(ty) = checked.get(&fact.key) else {
            continue;
        };
        if fact.kind == "fn" || fact.kind == "method" {
            for (slot, param) in fact.slots.iter_mut().zip(&ty.params) {
                slot.refs = checked_type_refs(syms, &param.ty);
            }
            if let Some(slot) = &mut fact.result
                && let Some(result) = &ty.result
            {
                slot.refs = checked_type_refs(syms, result);
            }
        } else if let Some(def) = &ty.def {
            match fact.kind.as_str() {
                "type" => {
                    for (slot, field) in fact.slots.iter_mut().zip(def.fields.borrow().iter()) {
                        slot.refs = checked_type_refs(syms, &field.ty);
                    }
                }
                "alternative" => {
                    for (slot, case) in fact.slots.iter_mut().zip(def.cases.borrow().iter()) {
                        for field in &case.fields {
                            for key in checked_type_refs(syms, &field.ty) {
                                append_unique(&mut slot.refs, &key);
                            }
                        }
                    }
                }
                "interface" => {
                    for (slot, op) in fact.slots.iter_mut().zip(def.operations.borrow().iter()) {
                        slot.refs = checked_type_refs(syms, &op.ty);
                    }
                }
                _ => {}
            }
        }
        for slot in fact.slots.iter_mut().chain(fact.result.iter_mut()) {
            slot.refs.retain(|key| project.contains(key));
        }
    }
}

/// Follow the components of the written type, never the fields of its definition: a
/// recursive record remains one reference, while a function type includes its signature.
fn checked_type_refs(syms: ms_syntax::Names, ty: &ms_check::api::types::Ty) -> Vec<String> {
    let mut refs = Vec::new();
    let mut pending = vec![ty];
    let mut seen = HashSet::new();
    while let Some(ty) = pending.pop() {
        // Default generic arguments may share the same resolved type graph. Visit a
        // shared subtree once, without expanding it exponentially or recursing deeply.
        if !seen.insert(std::rc::Rc::as_ptr(ty)) {
            continue;
        }
        if let Some(symbol) = ty.def.as_ref().and_then(|def| def.symbol())
            && let Some(decl) = &symbol.decl
        {
            let (kind, name) = kind_and_name(syms, decl);
            append_unique(&mut refs, &fact_key(syms.str(symbol.module), kind, &name));
        }
        pending.extend(ty.result.iter());
        pending.extend(ty.params.iter().rev().map(|p| &p.ty));
        pending.extend(ty.args.iter().rev());
    }
    refs
}

struct Sites<'a> {
    scoped: &'a HashSet<NodeId>,
    tries: usize,
    /// Bindings the scope closes.
    scopes: usize,
}

impl<'a> Sites<'a> {
    fn new(scoped: &'a HashSet<NodeId>) -> Self {
        Sites {
            scoped,
            tries: 0,
            scopes: 0,
        }
    }
}

impl Visitor for Sites<'_> {
    fn stmt(&mut self, s: &Stmt) {
        if let StmtKind::Bind { pattern, .. } = &s.kind
            && self.scoped.contains(&pattern.id)
        {
            self.scopes += 1;
        }
    }

    fn expr(&mut self, e: &Expr) {
        if matches!(
            e.kind,
            ExprKind::Unary {
                op: UnaryOp::Try,
                ..
            }
        ) {
            self.tries += 1;
        }
    }
}

/// Counts one body. A declaration with methods reports only its own body;
/// each method counts its own.
fn count_declaration(scoped: &HashSet<NodeId>, decl: &DeclRef) -> (usize, usize) {
    let mut sites = Sites::new(scoped);
    match &decl.decl().kind {
        DeclKind::Fn(f) => walk_callable(&mut sites, &f.params, &f.body),
        DeclKind::Test(t) => walk_callable(&mut sites, &[], &t.body),
        DeclKind::Const(c) => walk_expr(&mut sites, &c.value),
        _ => {}
    }
    (sites.tries, sites.scopes)
}

fn count_method(scoped: &HashSet<NodeId>, method: &Method) -> (usize, usize) {
    let mut sites = Sites::new(scoped);
    walk_callable(&mut sites, &method.func.params, &method.func.body);
    (sites.tries, sites.scopes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn call_edges_deduplicate_resolved_identity_per_owner_and_boundary() {
        let syms = ms_syntax::Names::global();
        let program = ms_check::check(syms, Vec::new(), Default::default(), Default::default());
        let rows = InspectionRows {
            entities: vec![
                EntityRow {
                    id: "owner".into(),
                    file: "a.ms".into(),
                    kind: "fn".into(),
                    name: "owner".into(),
                    ..EntityRow::default()
                },
                EntityRow {
                    id: "other".into(),
                    file: "a.ms".into(),
                    kind: "fn".into(),
                    name: "other".into(),
                    ..EntityRow::default()
                },
                EntityRow {
                    id: "alias".into(),
                    file: "a.ms".into(),
                    kind: "fn".into(),
                    name: "other".into(),
                    ..EntityRow::default()
                },
                EntityRow {
                    id: "standard".into(),
                    file: "@std/example.ms".into(),
                    ..EntityRow::default()
                },
            ],
            calls: [
                ("owner", "other"),
                ("owner", "alias"),
                ("owner", "other"),
                ("owner", "standard"),
                ("owner", "standard"),
                ("owner", "a.ms#fn#other"), // same text as an internal key, external identity
                ("other", "other"),
                ("other", "standard"),
                ("missing", "other"),
                ("standard", "owner"),
            ]
            .into_iter()
            .enumerate()
            .map(|(i, (owner, target))| CallRow {
                id: i.to_string(),
                owner: owner.into(),
                target: target.into(),
                kind: "function".into(),
                spawn: false,
            })
            .collect(),
        };
        let facts = collect_facts(syms, &rows, &program);
        let owner = &facts.entities["a.ms#fn#owner"];
        assert_eq!(owner.calls, ["a.ms#fn#other"]);
        assert_eq!(owner.external, ["a.ms#fn#other", "standard"]);
        let other = &facts.entities["a.ms#fn#other"];
        assert_eq!(other.calls, ["a.ms#fn#other"]);
        assert_eq!(other.external, ["standard"]);
        assert_eq!(facts.entities.len(), 2);
    }
}
