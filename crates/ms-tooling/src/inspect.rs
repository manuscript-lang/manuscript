//! Source inspection: entities, call sites, locals and statements of a checked
//! program. The `ms inspect` document and the
//! mermaid call graph are rendered from it; facts, views and diagrams read it
//! through [`Inspection::rows`].

use crate::collect::{CallRow, EntityRow, InspectionRows};
use crate::json::Json;
use crate::sha256;
use crate::walk::walk_module;
use ms_check::syntax::{DeclRef, FuncRef};
use ms_check::types::{BindingRef, MethodRef, n, show};
use ms_check::{ModuleData, Program};
use ms_syntax::Pos;
use ms_syntax::ast::*;
use ms_syntax::visit::{Visitor, walk_callable};
use std::collections::HashMap;

/// A line-bounded source range.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Span {
    pub file: String,
    pub start: usize,
    pub end: usize,
    pub line: usize,
    pub column: usize,
}

/// One source file and the digest of its text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Source {
    pub file: String,
    pub sha256: String,
}

/// A declaration or method.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Entity {
    pub id: String,
    pub checker_id: String,
    pub kind: String,
    pub name: String,
    pub ty: String,
    pub span: Span,
    pub exported: bool,
    pub effects: Vec<String>,
}

/// A call, construction, operation or cleanup site.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CallSite {
    pub id: String,
    pub owner: String,
    pub target: String,
    pub kind: String,
    pub span: Span,
}

/// A local binding.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Local {
    pub checker_id: String,
    pub name: String,
    pub ty: String,
    pub span: Span,
}

/// The inspection of one checked program.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Inspection {
    pub locals: Vec<Local>,
    pub build_id: String,
    pub sources: Vec<Source>,
    pub entities: Vec<Entity>,
    pub calls: Vec<CallSite>,
    pub statements: Vec<Span>,
}

/// Delimiter offsets are indexed once per module, shared by every span.
struct LineEnds {
    offsets: Vec<usize>,
    len: usize,
}

impl LineEnds {
    fn new(source: &str) -> Self {
        Self {
            offsets: source
                .bytes()
                .enumerate()
                .filter_map(|(i, b)| matches!(b, b'\n' | b'\r').then_some(i))
                .collect(),
            len: source.len(),
        }
    }

    fn end(&self, start: usize) -> usize {
        let index = self.offsets.partition_point(|&offset| offset < start);
        self.offsets
            .get(index)
            .copied()
            .unwrap_or(self.len)
            .max(start)
    }
}

fn source_span(module: &ModuleData, pos: Pos, ends: &LineEnds) -> Span {
    let start = pos.offset as usize;
    Span {
        file: module.file.as_str().to_string(),
        start,
        end: ends.end(start),
        line: pos.line as usize,
        column: pos.column as usize,
    }
}

fn entity_kind(decl: &DeclRef) -> &'static str {
    match &decl.decl().kind {
        DeclKind::Fn(_) => "fn",
        DeclKind::Const(_) => "constant",
        DeclKind::Record(_) => "record",
        DeclKind::Alternative(_) => "alternative",
        DeclKind::Interface(_) => "interface",
        DeclKind::Impl(_) => "impl",
        DeclKind::Test(t) if t.bench => "bench",
        DeclKind::Test(_) => "test",
    }
}

fn decl_name(decl: &DeclRef) -> String {
    match &decl.decl().kind {
        DeclKind::Test(t) => t.name.to_string(),
        DeclKind::Impl(i) => i.display_name(decl.decl().synthetic),
        _ => decl.name().as_str().to_string(),
    }
}

/// Inspects a checked program: every module of it, bundled standard source
/// modules included.
pub fn inspect(program: &Program) -> Inspection {
    let mut result = Inspection::default();
    let modules: Vec<_> = program
        .modules
        .iter()
        .map(|m| (&**m, LineEnds::new(&m.source)))
        .collect();

    for (module, ends) in &modules {
        locals(module, ends, &mut result);
    }
    result
        .locals
        .sort_by(|a, b| a.checker_id.cmp(&b.checker_id));

    let mut symbol_ids: HashMap<usize, String> = HashMap::new();
    for (module, _) in &modules {
        for decl in &module.decls {
            if matches!(decl.decl().kind, DeclKind::Test(_) | DeclKind::Impl(_)) {
                continue;
            }
            if let Some(symbol) = symbol_of(program, module, decl.name().as_str()) {
                symbol_ids.insert(
                    symbol.key(),
                    format!(
                        "{}#{}#{}",
                        module.file.as_str(),
                        entity_kind(decl),
                        decl.name().as_str()
                    ),
                );
            }
        }
    }
    let mut method_ids: HashMap<&str, String> = HashMap::new();
    let mut methods: HashMap<(String, u32), MethodRef> = HashMap::new();
    for method in &program.methods {
        let Some(decl) = &method.decl else {
            continue;
        };
        methods.insert(
            (method.module.as_str().to_string(), decl.id().0),
            method.clone(),
        );
        method_ids.insert(
            method.id.as_str(),
            format!("{}#method#{}", method.module.as_str(), decl.pos().offset),
        );
    }

    for (module, ends) in &modules {
        result.sources.push(Source {
            file: module.file.as_str().to_string(),
            sha256: sha256::hex(module.source.as_bytes()),
        });
        for decl in &module.decls {
            if decl.decl().synthetic && matches!(decl.decl().kind, DeclKind::Interface(_)) {
                continue;
            }
            let kind = entity_kind(decl);
            let name = decl_name(decl);
            let file = module.file.as_str();
            let mut entity = Entity {
                id: format!("{file}#{kind}#{}", decl.name().as_str()),
                checker_id: String::new(),
                kind: kind.to_string(),
                name: name.clone(),
                ty: String::new(),
                span: source_span(module, decl.pos(), ends),
                exported: decl.decl().export,
                effects: Vec::new(),
            };
            if let DeclKind::Test(t) = &decl.decl().kind {
                let kind = if t.bench { "bench" } else { "test" };
                entity.id = format!("{file}#{kind}#{name}");
            }
            if let Some(symbol) = symbol_of(program, module, decl.decl_name_for_symbol().as_str())
                && symbol.decl.as_ref().is_some_and(|d| d.same(decl))
            {
                entity.checker_id = symbol.id.as_str().to_string();
                entity.ty = show(&symbol.value_type());
                entity.effects = effects_of(program, symbol.id.as_str());
            }
            if let DeclKind::Impl(_) = decl.decl().kind {
                entity.id = format!("{file}#impl#{}", decl.pos().offset);
                entity.name = name.clone();
            }
            result.entities.push(entity.clone());
            let mut sites = Sites {
                module,
                ends,
                owner: entity.id.clone(),
                symbol_ids: &symbol_ids,
                method_ids: &method_ids,
                calls: &mut result.calls,
                statements: &mut result.statements,
            };
            sites.declaration(decl);
            for (index, method) in decl.methods().iter().enumerate() {
                if method.func.body.is_empty() {
                    continue;
                }
                let Some(checked) = methods.get(&(file.to_string(), method.id.0)) else {
                    continue;
                };
                let owner = method_ids
                    .get(checked.id.as_str())
                    .cloned()
                    .unwrap_or_default();
                let _ = index;
                result.entities.push(Entity {
                    id: owner.clone(),
                    checker_id: checked.id.as_str().to_string(),
                    kind: "method".to_string(),
                    name: format!("{name}.{}", method.func.name.as_str()),
                    ty: checked.ty.to_string(),
                    span: source_span(module, method.pos, ends),
                    exported: false,
                    effects: effects_of(program, checked.id.as_str()),
                });
                let mut sites = Sites {
                    module,
                    ends,
                    owner,
                    symbol_ids: &symbol_ids,
                    method_ids: &method_ids,
                    calls: &mut result.calls,
                    statements: &mut result.statements,
                };
                walk_callable(&mut sites, &method.func.params, &method.func.body);
            }
        }
    }
    result.sources.sort_by(|a, b| a.file.cmp(&b.file));
    result.entities.sort_by(|a, b| a.id.cmp(&b.id));
    result.calls.sort_by(|a, b| a.id.cmp(&b.id));
    result.build_id = sha256::hex(result.to_json().compact(ms_json::Escape::GoHtml).as_bytes());
    result
}

fn symbol_of(
    program: &Program,
    module: &ModuleData,
    name: &str,
) -> Option<ms_check::types::SymRef> {
    program
        .symbols
        .get(&module.file)
        .and_then(|names| names.borrow().get(&n(name)).cloned())
}

fn effects_of(program: &Program, id: &str) -> Vec<String> {
    program
        .effects
        .get(&n(id))
        .map(|list| list.iter().map(|s| s.to_string()).collect())
        .unwrap_or_default()
}

trait DeclSymbolName {
    fn decl_name_for_symbol(&self) -> ms_check::types::Name;
}

impl DeclSymbolName for DeclRef {
    /// Tests are looked up by their written name.
    fn decl_name_for_symbol(&self) -> ms_check::types::Name {
        match &self.decl().kind {
            DeclKind::Test(t) => n(&t.name),
            _ => self.name(),
        }
    }
}

// ---------------------------------------------------------------- call sites

struct Sites<'a> {
    module: &'a ModuleData,
    ends: &'a LineEnds,
    owner: String,
    symbol_ids: &'a HashMap<usize, String>,
    method_ids: &'a HashMap<&'a str, String>,
    calls: &'a mut Vec<CallSite>,
    statements: &'a mut Vec<Span>,
}

impl Sites<'_> {
    /// Walks what a declaration itself executes: a function or test body, or a
    /// constant's initializer (a synthetic `return`).
    fn declaration(&mut self, decl: &DeclRef) {
        match &decl.decl().kind {
            DeclKind::Fn(f) => walk_callable(self, &f.params, &f.body),
            DeclKind::Test(t) => walk_callable(self, &[], &t.body),
            DeclKind::Const(c) => {
                self.statements
                    .push(source_span(self.module, c.init_pos, self.ends));
                ms_syntax::visit::walk_expr(self, &c.value);
            }
            _ => {}
        }
    }

    fn call_site(&mut self, e: &Expr) {
        let const_use = self.module.facts().const_use.contains(&e.id);
        let ExprKind::Call { callee, .. } = &e.kind else {
            if const_use {
                self.site(e, None);
            }
            return;
        };
        self.site(e, Some(callee));
    }

    fn site(&mut self, e: &Expr, callee: Option<&Expr>) {
        let file = self.module.file.as_str();
        let mut site = CallSite {
            id: format!("{file}#call#{}", e.pos.offset),
            owner: self.owner.clone(),
            target: "indirect".to_string(),
            kind: "function".to_string(),
            span: source_span(self.module, e.pos, self.ends),
        };
        if self.module.facts().const_use.contains(&e.id) {
            site.kind = "constant".to_string();
        }
        let info = self.module.facts().info(e.id).cloned();
        if let Some(info) = info {
            if let Some(symbol) = &info.symbol {
                site.target = match self.symbol_ids.get(&symbol.key()) {
                    Some(id) => id.clone(),
                    None => format!("{}#{}", symbol.module.as_str(), symbol.name.as_str()),
                };
            }
            if let Some(method) = &info.method {
                site.kind = "operation".to_string();
                site.target = match self.method_ids.get(method.id.as_str()) {
                    Some(id) => id.clone(),
                    None => format!(
                        "{}.{}",
                        method.receiver,
                        callee.map(callee_text).unwrap_or_default()
                    ),
                };
            }
            if let Some(constructor) = &info.constructor {
                site.kind = "construct".to_string();
                site.target = constructor.to_string();
            }
            if info.native_str() == "http_serve" {
                site.kind = "http_serve".to_string();
                site.target = "http_serve".to_string();
            }
        }
        self.calls.push(site);
    }
}

fn callee_text(callee: &Expr) -> String {
    match &callee.kind {
        ExprKind::Name(name) | ExprKind::Member { name, .. } => name.as_str().to_string(),
        _ => String::new(),
    }
}

impl Visitor for Sites<'_> {
    fn expr(&mut self, e: &Expr) {
        self.call_site(e);
    }

    fn stmt(&mut self, s: &Stmt) {
        self.statements
            .push(source_span(self.module, s.pos, self.ends));
        if let StmtKind::Bind { .. } = s.kind
            && let Some(method) = self
                .module
                .facts()
                .stmts
                .get(&s.id)
                .and_then(|f| f.cleanup.clone())
        {
            let target = match self.method_ids.get(method.id.as_str()) {
                Some(id) => id.clone(),
                None => format!("{}.close", method.receiver),
            };
            self.calls.push(CallSite {
                id: format!("{}#cleanup#{}", self.module.file.as_str(), s.pos.offset),
                owner: self.owner.clone(),
                target,
                kind: "cleanup".to_string(),
                span: source_span(self.module, s.pos, self.ends),
            });
        }
    }
}

// -------------------------------------------------------------------- locals

fn locals(module: &ModuleData, ends: &LineEnds, out: &mut Inspection) {
    let mut add = |binding: &BindingRef, pos: Pos| {
        out.locals.push(Local {
            checker_id: binding.id.as_str().to_string(),
            name: binding.name.as_str().to_string(),
            ty: binding.ty.to_string(),
            span: source_span(module, pos, ends),
        });
    };
    let facts = module.facts();
    for decl in &module.decls {
        // The interface synthesized for an inherent `impl` shares node ids with
        // the impl's own methods.
        if decl.decl().synthetic && matches!(decl.decl().kind, DeclKind::Interface(_)) {
            continue;
        }
        let mut callable = |func: FuncRef, params: &[Param]| {
            let Some(df) = facts.decls.get(&func.id()) else {
                return;
            };
            if let Some(b) = &df.fixture {
                add(b, func.pos());
            }
            if let Some(b) = &df.self_binding {
                add(b, func.pos());
            }
            for (index, b) in df.parameters.iter().enumerate() {
                if let Some(p) = params.get(index) {
                    add(b, p.pos);
                }
            }
        };
        let params: &[Param] = match &decl.decl().kind {
            DeclKind::Record(r) => &r.fields,
            DeclKind::Fn(f) => &f.params,
            _ => &[],
        };
        callable(FuncRef::of_decl(decl.clone()), params);
        for (index, method) in decl.methods().iter().enumerate() {
            callable(
                FuncRef {
                    decl: decl.clone(),
                    index: Some(index),
                },
                &method.func.params,
            );
        }
    }
    let mut scan = LocalScan {
        module,
        add: &mut add,
    };
    walk_module(module, &mut scan);
}

struct LocalScan<'a> {
    module: &'a ModuleData,
    add: &'a mut dyn FnMut(&BindingRef, Pos),
}

impl LocalScan<'_> {
    fn pattern(&mut self, p: &Pattern) {
        if let Some(b) = self.module.facts().patterns.get(&p.id) {
            (self.add)(b, p.pos);
        }
        match &p.kind {
            PatternKind::Name(_) => {}
            PatternKind::List(items) => items.iter().for_each(|i| self.pattern(i)),
            PatternKind::Record(fields) => fields.iter().for_each(|f| self.pattern(&f.pattern)),
        }
    }
}

impl Visitor for LocalScan<'_> {
    fn stmt(&mut self, s: &Stmt) {
        let facts = self.module.facts();
        if let Some(b) = facts.stmts.get(&s.id).and_then(|f| f.loop_binding.as_ref()) {
            (self.add)(b, s.pos);
        }
        match &s.kind {
            StmtKind::Bind { pattern, .. } => self.pattern(pattern),
            StmtKind::If {
                binding: Some(pattern),
                ..
            } => self.pattern(pattern),
            _ => {}
        }
    }

    fn expr(&mut self, e: &Expr) {
        let facts = self.module.facts();
        match &e.kind {
            ExprKind::Lambda(l) => {
                if let Some(bindings) = facts.lambda_params.get(&e.id) {
                    for (index, b) in bindings.iter().enumerate() {
                        if let Some(p) = l.params.get(index) {
                            (self.add)(b, p.pos);
                        }
                    }
                }
            }
            ExprKind::Match { arms, .. } => {
                for arm in arms {
                    if let Some(arm_facts) = facts.arms.get(&arm.id) {
                        for b in arm_facts.bindings.iter().flatten() {
                            (self.add)(b, arm.pos);
                        }
                    }
                }
            }
            _ => {}
        }
    }
}

// ------------------------------------------------------------------- outputs

impl Span {
    fn to_json(&self) -> Json {
        Json::Obj(vec![
            ("file".into(), Json::str(&self.file)),
            ("start".into(), Json::int(self.start as i64)),
            ("end".into(), Json::int(self.end as i64)),
            ("line".into(), Json::int(self.line as i64)),
            ("column".into(), Json::int(self.column as i64)),
        ])
    }
}

impl Inspection {
    /// The `ms inspect` document.
    pub fn to_json(&self) -> Json {
        let locals = self.locals.iter().map(|l| {
            Json::Obj(vec![
                ("checker_id".into(), Json::str(&l.checker_id)),
                ("name".into(), Json::str(&l.name)),
                ("type".into(), Json::str(&l.ty)),
                ("span".into(), l.span.to_json()),
            ])
        });
        let sources = self.sources.iter().map(|s| {
            Json::Obj(vec![
                ("file".into(), Json::str(&s.file)),
                ("sha256".into(), Json::str(&s.sha256)),
            ])
        });
        let entities = self.entities.iter().map(|e| {
            let mut fields = vec![("id".to_string(), Json::str(&e.id))];
            if !e.checker_id.is_empty() {
                fields.push(("checker_id".into(), Json::str(&e.checker_id)));
            }
            fields.push(("kind".into(), Json::str(&e.kind)));
            fields.push(("name".into(), Json::str(&e.name)));
            if !e.ty.is_empty() {
                fields.push(("type".into(), Json::str(&e.ty)));
            }
            fields.push(("span".into(), e.span.to_json()));
            fields.push(("exported".into(), Json::Bool(e.exported)));
            if !e.effects.is_empty() {
                fields.push(("effects".into(), Json::strings(&e.effects)));
            }
            Json::Obj(fields)
        });
        let calls = self.calls.iter().map(|c| {
            Json::Obj(vec![
                ("id".into(), Json::str(&c.id)),
                ("owner".into(), Json::str(&c.owner)),
                ("target".into(), Json::str(&c.target)),
                ("kind".into(), Json::str(&c.kind)),
                ("span".into(), c.span.to_json()),
            ])
        });
        Json::Obj(vec![
            ("locals".to_string(), Json::Arr(locals.collect())),
            ("format".into(), Json::int(2)),
            ("build_id".into(), Json::str(&self.build_id)),
            ("sources".into(), Json::Arr(sources.collect())),
            ("entities".into(), Json::Arr(entities.collect())),
            ("calls".into(), Json::Arr(calls.collect())),
            (
                "statements".into(),
                Json::Arr(self.statements.iter().map(Span::to_json).collect()),
            ),
        ])
    }

    /// The entity and call rows that facts, views and diagrams are built from.
    pub fn rows(&self) -> InspectionRows {
        InspectionRows {
            entities: self
                .entities
                .iter()
                .map(|e| EntityRow {
                    id: e.id.clone(),
                    kind: e.kind.clone(),
                    name: e.name.clone(),
                    ty: e.ty.clone(),
                    file: e.span.file.clone(),
                    line: e.span.line,
                    exported: e.exported,
                    effects: e.effects.clone(),
                })
                .collect(),
            calls: self
                .calls
                .iter()
                .map(|c| CallRow {
                    id: c.id.clone(),
                    owner: c.owner.clone(),
                    target: c.target.clone(),
                    kind: c.kind.clone(),
                })
                .collect(),
        }
    }

    /// The mermaid call graph (`Diagram`).
    pub fn mermaid(&self) -> String {
        let mut out = String::from("flowchart TD\n");
        let mut nodes: HashMap<String, String> = HashMap::new();
        let mut node = |out: &mut String, id: &str, label: &str| -> String {
            let key = format!("n{}", &sha256::hex(id.as_bytes())[..16]);
            if !nodes.contains_key(id) {
                nodes.insert(id.to_string(), key.clone());
                let label = label
                    .replace('&', "&amp;")
                    .replace('"', "&quot;")
                    .replace('<', "&lt;")
                    .replace('>', "&gt;")
                    .replace('\n', " ");
                out.push_str(&format!("    {key}[\"{label}\"]\n"));
            }
            key
        };
        for e in &self.entities {
            node(&mut out, &e.id, &format!("{}::{}", e.span.file, e.name));
        }
        for c in &self.calls {
            let owner = node(&mut out, &c.owner, &c.owner);
            let target = node(&mut out, &c.target, &c.target);
            out.push_str(&format!("    {owner} -->|{}| {target}\n", c.kind));
        }
        out
    }
}

#[cfg(test)]
mod span_tests {
    use super::LineEnds;

    #[test]
    fn indexed_ends_match_byte_scan_for_every_offset() {
        for text in [
            "",
            "no newline",
            "αβ\n🙂\r\nlast",
            "\r\n\r\n",
            "a\rb\nc\r\nd\n",
            "é",
        ] {
            let ends = LineEnds::new(text);
            for start in 0..=text.len() + 2 {
                let mut expected = start;
                while expected < text.len() && !matches!(text.as_bytes()[expected], b'\r' | b'\n') {
                    expected += 1;
                }
                assert_eq!(ends.end(start), expected, "{text:?} offset {start}");
            }
        }
    }
}
