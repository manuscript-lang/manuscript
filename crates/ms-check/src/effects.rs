//! Conservative potential effects of callables.

use crate::checker::Checker;
use crate::effect_directives::Lines;
use crate::effect_reach::{ReachNode, resolve};
use crate::std_ops::{collection_mutation, is_text_builder};
use crate::syntax::*;
use crate::types::Method;
use crate::types::*;
use ms_syntax::Pos;
use ms_syntax::ast::*;
use ms_syntax::visit::{self, Visitor};
use std::collections::{BTreeSet, HashMap, HashSet};

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
    /// Position of the first reference to each callee, in source order.
    edge_pos: Vec<(Name, Pos)>,
}

struct Scan<'a> {
    syms: ms_syntax::Names,
    module: &'a ModRef,
    ids: &'a HashSet<Name>,
    effects: BTreeSet<&'static str>,
    edges: HashSet<Name>,
    edge_pos: Vec<(Name, Pos)>,
    /// Impl method ids per (interface id, concrete type id): what converting a value to the
    /// interface hands out.
    conversions: &'a HashMap<(Name, Name), Vec<Name>>,
    /// Interface-implementing method ids per concrete type id.
    by_receiver: &'a HashMap<Name, Vec<Name>>,
    /// A type's own methods as (operation name, id): converting to an interface hands out the
    /// ones its operations name, with no impl to say so.
    own_methods: &'a HashMap<Name, Vec<(Name, Name)>>,
}

impl Scan<'_> {
    /// Records a reference to callable `id`; the first one keeps its position.
    fn edge(&mut self, id: Name, pos: Pos) {
        if self.edges.insert(id) {
            self.edge_pos.push((id, pos));
        }
    }

    fn info(&self, e: &Expr) -> Option<Info> {
        self.module.facts().info(e.id).cloned()
    }

    fn scan_call(&mut self, e: &Expr) {
        let Some(info) = self.info(e) else {
            self.effects.insert("unknown");
            return;
        };
        if let Some(constructor) = &info.constructor {
            if let Some(s) = constructor.symbol()
                && self.ids.contains(&s.id)
            {
                self.edge(s.id, e.pos);
            }
            return;
        }
        if info.native_str(self.syms) == "to_string" || info.native_str(self.syms) == "clone" {
            self.effects.insert("read");
            return;
        }
        if let Some(s) = &info.symbol {
            if s.native == Native::Source {
                self.edge(s.id, e.pos);
                return;
            }
            if !s.native.is(self.syms, "core/panic") {
                self.effects.insert("unknown");
            }
            return;
        }
        if let Some(m) = &info.method {
            self.scan_method_call(m, e.pos);
            return;
        }
        self.effects.insert("unknown");
    }

    /// Adds the effects of a method call: an edge for source methods, or the
    /// known effects of the native receiver.
    fn scan_method_call(&mut self, method: &Method, pos: Pos) {
        if !self.syms.str(method.id).is_empty() {
            self.edge(method.id, pos);
            return;
        }
        let mut receiver = method.receiver.clone();
        if let Some(c) = &method.contract
            && !self.syms.str(c.id).is_empty()
        {
            receiver = c.clone();
        }
        let add =
            |s: &mut BTreeSet<&'static str>, list: &[&'static str]| s.extend(list.iter().copied());
        if receiver.is(Builtin::List) || receiver.is(Builtin::Map) || receiver.is(Builtin::Set) {
            add(&mut self.effects, &["read"]);
            if collection_mutation(self.syms, method) {
                add(&mut self.effects, &["write"]);
            }
            if method.ty.params.iter().any(|p| p.ty.kind == Kind::Function) {
                add(&mut self.effects, &["unknown"]);
            }
        } else if is_text_builder(self.syms, &receiver) {
            add(&mut self.effects, &["write"]);
        } else if matches!(receiver.kind, Kind::Contract | Kind::Variable) {
            add(&mut self.effects, &["unknown"]);
        }
    }
}

impl Visitor for Scan<'_> {
    fn stmt(&mut self, s: &Stmt) {
        if let StmtKind::Assign {
            target: AssignTarget::Member(_),
            ..
        } = &s.kind
        {
            self.effects.insert("write");
        }
    }

    fn expr(&mut self, e: &Expr) {
        if self
            .info(e)
            .is_some_and(|i| i.native_str(self.syms) == "index")
        {
            self.effects.insert("read");
        }
        // Converting a type to an interface hands out its methods: charge the converter.
        if let Some(info) = self.info(e)
            && let (Some(source), Some(target)) = (&info.interface_source, &info.ty)
            && let Some(ids) = self.conversions.get(&(target.id, source.id))
        {
            for id in ids.clone() {
                if self.ids.contains(&id) {
                    self.edge(id, e.pos);
                }
            }
        }
        if let Some(info) = self.info(e)
            && let (Some(source), Some(target)) = (&info.interface_source, &info.ty)
            && let (Some(def), Some(own)) = (&target.def, self.own_methods.get(&source.id))
        {
            let operations: Vec<Name> = def.operations.borrow().iter().map(|o| o.name).collect();
            for (name, id) in own {
                if operations.contains(name) && self.ids.contains(id) {
                    self.edge(*id, e.pos);
                }
            }
        }
        // A generic call instantiated at a concrete type hands out that type's interface methods.
        if let Some(info) = self.info(e) {
            for arg in info.type_args.iter().flatten() {
                if matches!(arg.kind, Kind::Type | Kind::Alternative)
                    && let Some(ids) = self.by_receiver.get(&arg.id)
                {
                    for id in ids.clone() {
                        if self.ids.contains(&id) {
                            self.edge(id, e.pos);
                        }
                    }
                }
            }
        }
        // A constant is a nullary function here: each use is a call to it.
        if self.module.facts().const_use.contains(&e.id) {
            self.scan_call(e);
            return;
        }
        match &e.kind {
            ExprKind::Member { left, .. } => {
                let receiver_record = self
                    .info(left)
                    .is_some_and(|r| r.ty.as_ref().is_some_and(|t| t.kind == Kind::Type));
                if receiver_record && self.info(e).is_some_and(|i| i.method.is_none()) {
                    self.effects.insert("read");
                }
                // A bound method value (`let f = value.method`) reaches the method where it is
                // named, as a function named as a value does. A call's callee is also visited
                // here; its edge was already recorded at the call.
                if let Some(method) = self.info(e).and_then(|i| i.method) {
                    self.scan_method_call(&method, e.pos);
                }
            }
            ExprKind::Map(entries) if entries.len() > 1 => {
                // Duplicate-key insertion may dispatch user-defined equality.
                self.effects.insert("unknown");
            }
            ExprKind::Call { .. } => self.scan_call(e),
            // A function named as a value, or called by name: authority is charged where it is referenced.
            ExprKind::Name(_) => {
                let reference = self
                    .info(e)
                    .and_then(|i| i.symbol)
                    .filter(|s| s.native == Native::Source && self.ids.contains(&s.id));
                if let Some(s) = reference {
                    self.edge(s.id, e.pos);
                }
            }
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
                    edge_pos: Vec::new(),
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
                    DeclKind::Fn(_) | DeclKind::Type(_) | DeclKind::Const(_)
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
        let mut conversions: HashMap<(Name, Name), Vec<Name>> = HashMap::new();
        let mut by_receiver: HashMap<Name, Vec<Name>> = HashMap::new();
        let mut own_methods: HashMap<Name, Vec<(Name, Name)>> = HashMap::new();
        for m in &self.p.methods {
            if let Some(contract) = &m.contract
                && !ms_syntax::Names::global().str(m.id).is_empty()
            {
                if m.is_inherent(ms_syntax::Names::global())
                    && let Some(decl) = &m.decl
                {
                    own_methods
                        .entry(m.receiver.id)
                        .or_default()
                        .push((decl.name(), m.id));
                }
                conversions
                    .entry((contract.id, m.receiver.id))
                    .or_default()
                    .push(m.id);
                by_receiver.entry(m.receiver.id).or_default().push(m.id);
            }
        }
        for node in nodes.values_mut() {
            let Some(module) = node.module.clone() else {
                continue;
            };
            let mut scan = Scan {
                syms: ms_syntax::Names::global(),
                module: &module,
                ids: &ids,
                effects: BTreeSet::new(),
                edges: HashSet::new(),
                edge_pos: Vec::new(),
                conversions: &conversions,
                by_receiver: &by_receiver,
                own_methods: &own_methods,
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
            node.edge_pos = scan.edge_pos;
        }
        self.declared_effects(&order, &nodes);
        propagate_effects(&order, &mut nodes);
        self.p.effects = nodes
            .into_iter()
            .map(|(id, node)| (id, node.effects.into_iter().collect()))
            .collect();
    }
}

impl Checker {
    /// Declared effects (`// ms: effect`) per callable and the project callables that reach an
    /// effect no `// ms: allow_effect` scope permits.
    fn declared_effects(&mut self, order: &[Name], nodes: &HashMap<Name, EffectNode>) {
        let mut lines: HashMap<Name, Lines> = HashMap::new();
        let mut reach: Vec<ReachNode> = Vec::with_capacity(order.len());
        for id in order {
            let node = &nodes[id];
            let Some(module) = &node.module else {
                continue;
            };
            let lines = lines
                .entry(module.file)
                .or_insert_with(|| Lines::new(&module.source));
            let func = match &node.target {
                Target::Decl(d) => FuncRef::of_decl(d.clone()),
                Target::Method(f) => f.clone(),
            };
            let at = lines.above(func.pos().line);
            let syms = ms_syntax::Names::global();
            let file = syms.str(module.file);
            let name = syms.str(func.name());
            let label = match &func.decl.decl().kind {
                DeclKind::Impl(i) if func.method().is_some() => {
                    format!("{}.{name}", i.receiver.name(syms))
                }
                _ => name.to_string(),
            };
            reach.push(ReachNode {
                id: *id,
                file: module.file,
                label,
                pos: func.pos(),
                project: !crate::stdlib::is_bundled_source(file),
                entry: name == "main" && func.method().is_none(),
                declared: at.declared,
                allow_fn: at.allow,
                allow_file: lines.header().allow,
                edges: node.edge_pos.clone(),
            });
        }
        self.p.effect_permits = reach
            .iter()
            .filter(|n| n.project)
            .filter_map(|n| {
                let lines = n.allow_fn.as_ref().or(n.allow_file.as_ref())?;
                Some((n.id, lines.clone()))
            })
            .collect();
        let resolved = resolve(&reach);
        self.p.declared_effects = resolved.declared;
        self.p.effect_violations = resolved.violations;
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
