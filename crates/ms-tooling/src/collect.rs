//! Derives the review fact model from a checked program and its inspection.

use crate::facts::{Fact, Facts, Slot, append_unique, error_type, fact_key};
use crate::flow::{FlowBuilder, Site, StmtView};
use ms_check::syntax::DeclRef;
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
                error: error_type(&e.ty),
                ..Fact::default()
            },
        );
        id_to_key.insert(e.id.clone(), key);
    }
    // Borrow identities for membership; allocate an owned target only once per
    // distinct edge, including when many sites call the same target.
    let mut edges = HashSet::new();
    for call in &inspection.calls {
        let Some(owner_key) = id_to_key.get(&call.owner) else {
            continue;
        };
        let target_key = id_to_key.get(&call.target);
        let target = target_key.unwrap_or(&call.target);
        if !edges.insert((owner_key, target, target_key.is_some())) {
            continue;
        }
        let owner = facts.entities.get_mut(owner_key).expect("indexed owner");
        if target_key.is_some() {
            owner.calls.push(target.clone());
        } else {
            owner.external.push(target.clone());
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
                    .binding_facts
                    .has(b.uid, ms_check::ownership::BindingFact::ImplicitClose)
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
    resolve_type_refs(&mut facts);
    for fact in facts.entities.values_mut() {
        fact.calls.sort();
        fact.external.sort();
        fact.effects.sort();
    }
    for list in facts.imports.values_mut() {
        list.sort();
    }
    facts
}

/// The entity kind and name Go gives a declaration.
fn kind_and_name(syms: ms_syntax::Names, decl: &DeclRef) -> (&'static str, String) {
    let d = decl.decl();
    match &d.kind {
        DeclKind::Fn(f) => ("fn", syms.str(f.name).to_string()),
        DeclKind::Const(c) => ("constant", syms.str(c.name).to_string()),
        DeclKind::Record(r) => ("record", syms.str(r.name).to_string()),
        DeclKind::Alternative(a) => ("alternative", syms.str(a.name).to_string()),
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

fn is_type(kind: &str) -> bool {
    matches!(kind, "record" | "alternative" | "interface")
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
    let mut refs = Vec::new();
    type_names(syms, ty, &mut refs);
    Slot {
        name: name.to_string(),
        ty: type_text(syms, ty),
        var: false,
        refs,
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

/// Collects the last segment of every named type in `ty`.
fn type_names(syms: ms_syntax::Names, ty: &TypeRef, out: &mut Vec<String>) {
    match &ty.kind {
        TypeKind::Named { name, args } => {
            let text = syms.str(name);
            append_unique(out, text.rsplit('.').next().unwrap_or(text));
            for arg in args {
                type_names(syms, arg, out);
            }
        }
        TypeKind::Fn { params, result } => {
            for p in params {
                if let Some(t) = &p.ty {
                    type_names(syms, t, out);
                }
            }
            type_names(syms, result, out);
        }
    }
}

/// Fields, case payloads, or parameters, and the result, of one declaration.
fn declared_slots(syms: ms_syntax::Names, kind: &DeclKind) -> (Vec<Slot>, Option<Slot>) {
    match kind {
        DeclKind::Record(r) => (r.fields.iter().map(|p| slot(syms, p)).collect(), None),
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
        _ => (Vec::new(), None),
    }
}

/// Replaces written type names with the keys of the project types they name
/// (the same file's type first); names that are not project types drop out.
fn resolve_type_refs(facts: &mut Facts) {
    let mut by_name: HashMap<String, Vec<String>> = HashMap::new();
    for f in facts.entities.values() {
        if is_type(&f.kind) {
            by_name
                .entry(f.name.clone())
                .or_default()
                .push(f.key.clone());
        }
    }
    for f in facts.entities.values_mut() {
        let file = f.file.clone();
        let resolve = |slot: &mut Slot| {
            slot.refs = std::mem::take(&mut slot.refs)
                .iter()
                .filter_map(|name| {
                    let keys = by_name.get(name)?;
                    keys.iter()
                        .find(|k| k.starts_with(&format!("{file}#")))
                        .or_else(|| (keys.len() == 1).then(|| &keys[0]))
                        .cloned()
                })
                .collect();
        };
        f.slots.iter_mut().for_each(resolve);
        f.result.iter_mut().for_each(resolve);
    }
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
