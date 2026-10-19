//! Conservative potential effects of callables (`pkg/checker/effects.go`,
//! `mutation.go`).

use crate::checker::Checker;
use crate::syntax::*;
use crate::types::Method;
use crate::types::*;
use ms_syntax::ast::*;
use ms_syntax::visit::{self, Visitor};
use std::collections::{BTreeSet, HashMap, HashSet};

/// Whether a standard collection method mutates its receiver.
pub fn collection_mutation(receiver: &Ty, name: &str) -> bool {
    if receiver.is_std("List") {
        return matches!(
            name,
            "append"
                | "prepend"
                | "insert"
                | "pop"
                | "set"
                | "remove"
                | "splice"
                | "fill"
                | "copy_within"
                | "reverse_in_place"
        );
    }
    if receiver.is_std("Map") {
        return matches!(
            name,
            "add" | "remove" | "add_default" | "add_default_from" | "merge" | "clear"
        );
    }
    if receiver.is_std("StringBuilder") || receiver.is_std("BytesBuilder") {
        return matches!(name, "append" | "freeze");
    }
    receiver.is_std("Set") && matches!(name, "add" | "remove" | "clear")
}

enum Target {
    Decl(DeclRef),
    Method(FuncRef),
}

/// One callable's own effects and the callables it reaches.
struct EffectNode {
    module: Option<ModRef>,
    target: Target,
    effects: BTreeSet<&'static str>,
    edges: HashSet<Name>,
}

struct Scan<'a> {
    module: &'a ModRef,
    ids: &'a HashSet<Name>,
    effects: BTreeSet<&'static str>,
    edges: HashSet<Name>,
}

impl Scan<'_> {
    fn info(&self, e: &Expr) -> Option<Info> {
        self.module.facts().info(e.id).cloned()
    }

    fn scan_call(&mut self, e: &Expr, callee: &Expr) {
        let Some(info) = self.info(e) else {
            self.effects.insert("unknown");
            return;
        };
        if let Some(constructor) = &info.constructor {
            if let Some(s) = constructor.symbol()
                && self.ids.contains(&s.id)
            {
                self.edges.insert(s.id);
            }
            return;
        }
        if info.native_str() == "to_string" || info.native_str() == "clone" {
            self.effects.insert("read");
            return;
        }
        if let Some(s) = &info.symbol {
            if s.native.as_str().is_empty() {
                self.edges.insert(s.id);
                return;
            }
            match s.native.as_str() {
                "panic" => {}
                "sleep" => {
                    self.effects.insert("read");
                }
                _ => {
                    self.effects.insert("unknown");
                }
            }
            return;
        }
        if let Some(m) = &info.method {
            self.scan_method_call(callee, m);
            return;
        }
        self.effects.insert("unknown");
    }

    /// Adds the effects of a method call: an edge for source methods, or the
    /// known effects of the native receiver.
    fn scan_method_call(&mut self, callee: &Expr, method: &Method) {
        if !method.id.as_str().is_empty() {
            self.edges.insert(method.id);
            return;
        }
        let mut receiver = method.receiver.clone();
        if let Some(c) = &method.contract
            && !c.id.as_str().is_empty()
        {
            receiver = c.clone();
        }
        let name = match &callee.kind {
            ExprKind::Member { name, .. } => name.as_str(),
            ExprKind::Name(nm) => nm.as_str(),
            _ => "",
        };
        let add =
            |s: &mut BTreeSet<&'static str>, list: &[&'static str]| s.extend(list.iter().copied());
        match receiver.id.as_str() {
            "@std/Clock" => add(&mut self.effects, &["read"]),
            "@std/Files" | "@std/File" | "@std/ReadStream" => {
                add(&mut self.effects, &["external-call", "read"]);
                if name == "close" {
                    add(&mut self.effects, &["write"]);
                }
            }
            "@std/WriteStream" => add(&mut self.effects, &["external-call", "write"]),
            "@std/Network" | "@std/HttpServer" | "@std/Commands" | "@std/Subprocess" => {
                add(&mut self.effects, &["external-call", "read", "write"]);
            }
            "@std/Queue" => {
                if name != "enqueue" {
                    add(&mut self.effects, &["read"]);
                }
                if name == "enqueue" || name == "dequeue" {
                    add(&mut self.effects, &["write"]);
                }
            }
            "@std/List" | "@std/Map" | "@std/Set" => {
                add(&mut self.effects, &["read"]);
                if collection_mutation(&receiver, name) {
                    add(&mut self.effects, &["write"]);
                }
                if method.ty.params.iter().any(|p| p.ty.kind == Kind::Function) {
                    add(&mut self.effects, &["unknown"]);
                }
            }
            _ => {
                if receiver.name.as_str().ends_with("Builder") {
                    add(&mut self.effects, &["write"]);
                } else if matches!(receiver.kind, Kind::Contract | Kind::Variable) {
                    add(&mut self.effects, &["unknown"]);
                }
            }
        }
    }
}

impl Visitor for Scan<'_> {
    fn stmt(&mut self, s: &Stmt) {
        match &s.kind {
            StmtKind::Assign {
                target: AssignTarget::Member(_),
                ..
            } => {
                self.effects.insert("write");
            }
            StmtKind::With { .. } => {
                let cleanup = self
                    .module
                    .facts()
                    .stmts
                    .get(&s.id)
                    .and_then(|f| f.cleanup.clone());
                match cleanup {
                    Some(m) if !m.id.as_str().is_empty() => {
                        self.edges.insert(m.id);
                    }
                    _ => {
                        self.effects.insert("unknown");
                    }
                }
            }
            _ => {}
        }
    }

    fn expr(&mut self, e: &Expr) {
        if self.info(e).is_some_and(|i| i.native_str() == "index") {
            self.effects.insert("read");
        }
        // A constant is a nullary function in Go: each use is a call to it.
        if self.module.facts().const_use.contains(&e.id) {
            self.scan_call(e, e);
            return;
        }
        match &e.kind {
            ExprKind::Member { left, .. } => {
                let receiver_record = self
                    .info(left)
                    .is_some_and(|r| r.ty.as_ref().is_some_and(|t| t.kind == Kind::Record));
                if receiver_record && self.info(e).is_some_and(|i| i.method.is_none()) {
                    self.effects.insert("read");
                }
            }
            ExprKind::Map(entries) if entries.len() > 1 => {
                // Duplicate-key insertion may dispatch user-defined equality.
                self.effects.insert("unknown");
            }
            ExprKind::Call { callee, .. } => self.scan_call(e, callee),
            _ => {}
        }
    }
}

impl Checker {
    /// Computes each callable's potential effects, nested closure bodies
    /// included. An indirect or unclassified operation contributes unknown
    /// rather than claiming purity.
    pub(crate) fn effect_summaries(&mut self) {
        let modules: HashMap<Name, ModRef> =
            self.p.modules.iter().map(|m| (m.file, m.clone())).collect();
        let mut order: Vec<Name> = Vec::new();
        let mut nodes: HashMap<Name, EffectNode> = HashMap::new();
        let mut add = |id: Name, module: Option<ModRef>, target: Target| {
            if !nodes.contains_key(&id) {
                order.push(id);
            }
            nodes.insert(
                id,
                EffectNode {
                    module,
                    target,
                    effects: BTreeSet::new(),
                    edges: HashSet::new(),
                },
            );
        };
        for module in &self.p.modules {
            let Some(names) = self.p.symbols.get(&module.file) else {
                continue;
            };
            for d in &module.decls {
                if !matches!(
                    d.decl().kind,
                    DeclKind::Fn(_) | DeclKind::Record(_) | DeclKind::Const(_)
                ) {
                    continue;
                }
                if let Some(symbol) = names.borrow().get(&d.name()) {
                    add(symbol.id, Some(module.clone()), Target::Decl(d.clone()));
                }
            }
        }
        for method in &self.p.methods {
            if let Some(decl) = &method.decl {
                add(
                    method.id,
                    modules.get(&method.module).cloned(),
                    Target::Method(decl.clone()),
                );
            }
        }
        let ids: HashSet<Name> = nodes.keys().copied().collect();
        for node in nodes.values_mut() {
            let Some(module) = node.module.clone() else {
                continue;
            };
            let mut scan = Scan {
                module: &module,
                ids: &ids,
                effects: BTreeSet::new(),
                edges: HashSet::new(),
            };
            match &node.target {
                Target::Decl(d) => {
                    visit::walk_decl(&mut scan, d.decl());
                    for m in &d.0.folded {
                        visit::walk_callable(&mut scan, &m.func.params, &m.func.body);
                    }
                }
                Target::Method(f) => {
                    if let Some(func) = f.func() {
                        visit::walk_callable(&mut scan, &func.params, &func.body);
                    }
                }
            }
            node.effects = scan.effects;
            node.edges = scan.edges;
        }
        propagate_effects(&order, &mut nodes);
        self.p.effects = nodes
            .into_iter()
            .map(|(id, node)| (id, node.effects.into_iter().collect()))
            .collect();
    }
}

/// Folds each callee's effects into its callers until stable. Only callers of a
/// changed node need revisiting; repeatedly scanning every edge made chains
/// quadratic. Calls without a node contribute unknown.
fn propagate_effects(order: &[Name], nodes: &mut HashMap<Name, EffectNode>) {
    let mut work: Vec<Name> = Vec::new();
    for id in order {
        let missing = nodes[id].edges.iter().any(|e| !nodes.contains_key(e));
        let node = nodes.get_mut(id).expect("node");
        if missing {
            node.effects.insert("unknown");
        }
        if !node.effects.is_empty() {
            work.push(*id);
        }
    }
    if work.is_empty() {
        return;
    }
    let mut callers: HashMap<Name, Vec<Name>> = HashMap::new();
    for id in order {
        for edge in &nodes[id].edges {
            if nodes.contains_key(edge) {
                callers.entry(*edge).or_default().push(*id);
            }
        }
    }
    let mut pending: HashSet<Name> = work.iter().copied().collect();
    while let Some(callee) = work.pop() {
        pending.remove(&callee);
        let effects: Vec<&'static str> = nodes[&callee].effects.iter().copied().collect();
        for caller in callers.get(&callee).cloned().unwrap_or_default() {
            let node = nodes.get_mut(&caller).expect("caller");
            let mut changed = false;
            for effect in &effects {
                changed |= node.effects.insert(effect);
            }
            if changed && pending.insert(caller) {
                work.push(caller);
            }
        }
    }
}
