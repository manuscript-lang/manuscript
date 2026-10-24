//! Derives the review fact model from a checked program and its inspection.

use crate::facts::{Fact, Facts, append_unique, error_type, fact_key};
use crate::flow::{FlowBuilder, Site, StmtView};
use ms_check::syntax::DeclRef;
use ms_check::{ModRef, Program};
use ms_syntax::visit::{Visitor, walk_callable, walk_expr};
use ms_syntax::{DeclKind, Expr, ExprKind, Method, Stmt, StmtKind, UnaryOp};
use std::collections::HashMap;

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
}

/// The slice of an inspection that facts are derived from.
#[derive(Clone, Debug, Default)]
pub struct InspectionRows {
    pub entities: Vec<EntityRow>,
    pub calls: Vec<CallRow>,
}

/// Derives the review fact model from a checked program.
pub fn collect_facts(inspection: &InspectionRows, program: &Program) -> Facts {
    let mut facts = Facts::default();
    let mut id_to_key: HashMap<String, String> = HashMap::new();
    for e in &inspection.entities {
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
    for call in &inspection.calls {
        let Some(owner) = id_to_key
            .get(&call.owner)
            .and_then(|k| facts.entities.get_mut(k))
        else {
            continue;
        };
        match id_to_key.get(&call.target) {
            Some(key) => append_unique(&mut owner.calls, key),
            None => append_unique(&mut owner.external, &call.target),
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
                },
            )
        })
        .collect();
    for module in &program.modules {
        for import in &module.imports {
            append_unique(
                facts
                    .imports
                    .entry(module.file.as_str().to_string())
                    .or_default(),
                &import.path,
            );
        }
        let source: &str = &module.source;
        let module_facts = module.facts();
        let flow = FlowBuilder {
            file: module.file.as_str(),
            lines: source.split('\n').collect(),
            sites: &sites,
            keys: &id_to_key,
            const_use: &module_facts.const_use,
        };
        collect_bodies(&mut facts, module, &flow);
    }
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
fn kind_and_name(decl: &DeclRef) -> (&'static str, String) {
    let d = decl.decl();
    match &d.kind {
        DeclKind::Fn(f) => ("fn", f.name.as_str().to_string()),
        DeclKind::Const(c) => ("constant", c.name.as_str().to_string()),
        DeclKind::Record(r) => ("type", r.name.as_str().to_string()),
        DeclKind::Alternative(a) => ("type", a.name.as_str().to_string()),
        DeclKind::Interface(i) => ("interface", i.name.as_str().to_string()),
        DeclKind::Impl(i) => ("impl", i.display_name(d.synthetic)),
        DeclKind::Test(t) => ("test", t.name.to_string()),
    }
}

/// Counts try and with sites and records each entity's line range.
fn collect_bodies(facts: &mut Facts, module: &ModRef, flow: &FlowBuilder) {
    let total = module.source.matches('\n').count() + 1;
    let decls = &module.decls;
    for (index, decl) in decls.iter().enumerate() {
        let last = match decls.get(index + 1) {
            Some(next) => next.pos().line as usize - 1,
            None => total,
        };
        let (kind, name) = kind_and_name(decl);
        let key = fact_key(module.file.as_str(), kind, &name);
        if let Some(fact) = facts.entities.get_mut(&key) {
            fact.first = decl.pos().line as usize;
            fact.last = last;
            (fact.tries, fact.withs) = count_declaration(decl);
            let steps = match &decl.decl().kind {
                DeclKind::Fn(f) => flow.body(&f.body),
                DeclKind::Test(t) => flow.body(&t.body),
                DeclKind::Const(c) => {
                    flow.statement(&StmtView::constant(c.init_pos, &c.value), None)
                }
                _ => Vec::new(),
            };
            facts.flows.insert(key, steps);
        }
        let methods = decl.methods();
        for (i, method) in methods.iter().enumerate() {
            let end = methods
                .get(i + 1)
                .map_or(last, |next| next.pos.line as usize - 1);
            let key = fact_key(
                module.file.as_str(),
                "method",
                &format!("{name}.{}", method.func.name.as_str()),
            );
            if let Some(fact) = facts.entities.get_mut(&key) {
                fact.first = method.pos.line as usize;
                fact.last = end;
                (fact.tries, fact.withs) = count_method(method);
                facts.flows.insert(key, flow.body(&method.func.body));
            }
        }
    }
}

#[derive(Default)]
struct Sites {
    tries: usize,
    withs: usize,
}

impl Visitor for Sites {
    fn stmt(&mut self, s: &Stmt) {
        if matches!(s.kind, StmtKind::With { .. }) {
            self.withs += 1;
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
fn count_declaration(decl: &DeclRef) -> (usize, usize) {
    let mut sites = Sites::default();
    match &decl.decl().kind {
        DeclKind::Fn(f) => walk_callable(&mut sites, &f.params, &f.body),
        DeclKind::Test(t) => walk_callable(&mut sites, &[], &t.body),
        DeclKind::Const(c) => walk_expr(&mut sites, &c.value),
        _ => {}
    }
    (sites.tries, sites.withs)
}

fn count_method(method: &Method) -> (usize, usize) {
    let mut sites = Sites::default();
    walk_callable(&mut sites, &method.func.params, &method.func.body);
    (sites.tries, sites.withs)
}
