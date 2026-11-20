//! Conservative potential effects of callables.

use crate::checker::Checker;
use crate::effect_directives::{Directives, Lines};
use crate::effect_reach::{ReachNode, resolve};
use crate::fxmap::{HashMap, HashSet};
use crate::std_ops::{collection_mutation, is_text_builder};
use crate::syntax::*;
use crate::types::Method;
use crate::types::*;
use ms_syntax::Pos;
use ms_syntax::ast::*;
use ms_syntax::visit::{self, Visitor};
use std::collections::BTreeSet;

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
    /// Own or declared `equals`, `hash` and `compare` method ids per concrete type id: what an
    /// operator or a collection operation runs.
    comparison_ops: &'a HashMap<Name, Vec<(Builtin, Name)>>,
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

    /// A concrete type reaches the methods `ids` lists for it: charge them here.
    fn charge_type(&mut self, ty: &Ty, pos: Pos, ids: &HashMap<Name, Vec<Name>>) {
        if matches!(ty.kind, Kind::Type | Kind::Alternative)
            && let Some(ids) = ids.get(&ty.id)
        {
            for id in ids.clone() {
                if self.ids.contains(&id) {
                    self.edge(id, pos);
                }
            }
        }
    }

    /// The properties a method needs of each type argument of its receiver, by position: the
    /// bounds its declaration writes on the receiver (`fn List[T: Equal].contains`), and for a
    /// `Set` or `Map` the key's equality and hash once an argument can be a key.
    fn receiver_requirements(&self, method: &Method) -> Vec<(usize, Vec<Builtin>)> {
        let mut found: Vec<(usize, Vec<Builtin>)> = Vec::new();
        let Some(decl) = &method.decl else {
            return found;
        };
        if let DeclKind::Impl(imp) = &decl.decl.decl().kind
            && let TypeKind::Named { args, .. } = &imp.receiver.kind
        {
            for bound_param in &imp.bounds {
                let Some(arg) = args
                    .iter()
                    .position(|a| a.name(self.syms) == self.syms.str(bound_param.name))
                else {
                    continue;
                };
                for bound in &bound_param.bounds {
                    let property = match bound.name(self.syms) {
                        "Equal" => &[Builtin::Equal][..],
                        "Hashable" => &[Builtin::Equal, Builtin::Hashable],
                        "Comparable" => &[Builtin::Comparable],
                        _ => continue,
                    };
                    found.push((arg, property.to_vec()));
                }
            }
        }
        let keyed = method.receiver.is(Builtin::Set) || method.receiver.is(Builtin::Map);
        let takes_value = method.ty.params.iter().any(|p| p.ty.kind != Kind::Function);
        if keyed && takes_value {
            found.push((0, vec![Builtin::Equal, Builtin::Hashable]));
        }
        found
    }

    /// Charges the `equals`, `hash` or `compare` methods of `ty` and its type arguments that
    /// serve one of `properties`.
    fn charge_operations(&mut self, ty: &Ty, pos: Pos, properties: &[Builtin]) {
        let mut ids: HashMap<Name, Vec<Name>> = HashMap::default();
        self.collect_operations(ty, properties, &mut ids);
        let mut types = Vec::new();
        collect_types(ty, &mut types);
        for t in types {
            self.charge_type(&t, pos, &ids);
        }
    }

    fn collect_operations(
        &self,
        ty: &Ty,
        properties: &[Builtin],
        out: &mut HashMap<Name, Vec<Name>>,
    ) {
        if let Some(found) = self.comparison_ops.get(&ty.id) {
            let ids: Vec<Name> = found
                .iter()
                .filter(|(b, _)| properties.contains(b))
                .map(|(_, id)| *id)
                .collect();
            out.entry(ty.id).or_default().extend(ids);
        }
        for arg in &ty.args {
            self.collect_operations(arg, properties, out);
        }
    }

    fn scan_call(&mut self, e: &Expr) {
        let module = self.module;
        let facts = module.facts();
        let Some(info) = facts.info(e.id) else {
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
        // `contains`, `Set.add` and the like run the argument types' own operations.
        for (arg, properties) in self.receiver_requirements(method) {
            if let Some(ty) = method.receiver.args.get(arg) {
                self.charge_operations(ty, pos, &properties);
            }
        }
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
        // Facts are read in place: cloning an `Info` per lookup was a measurable share of the pass.
        let module = self.module;
        let facts = module.facts();
        let info = facts.info(e.id);
        if info.is_some_and(|i| i.native_str(self.syms) == "index") {
            self.effects.insert("read");
        }
        // Converting a type to an interface hands out its methods: charge the converter.
        if let Some(info) = info
            && let (Some(source), Some(target)) = (&info.interface_source, &info.ty)
            && let Some(ids) = self.conversions.get(&(target.id, source.id))
        {
            for id in ids.clone() {
                if self.ids.contains(&id) {
                    self.edge(id, e.pos);
                }
            }
        }
        if let Some(info) = info
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
        if let Some(info) = info {
            for arg in info.type_args.iter().flatten() {
                self.charge_type(arg, e.pos, self.by_receiver);
            }
        }
        // A constant is a nullary function here: each use is a call to it.
        if facts.const_use.contains(&e.id) {
            self.scan_call(e);
            return;
        }
        match &e.kind {
            ExprKind::Member { left, .. } => {
                let receiver_record = facts
                    .info(left.id)
                    .is_some_and(|r| r.ty.as_ref().is_some_and(|t| t.kind == Kind::Type));
                if receiver_record && info.is_some_and(|i| i.method.is_none()) {
                    self.effects.insert("read");
                }
                // A bound method value (`let f = value.method`) reaches the method where it is
                // named, as a function named as a value does. A call's callee is also visited
                // here; its edge was already recorded at the call.
                if let Some(method) = info.and_then(|i| i.method.as_ref()) {
                    self.scan_method_call(method, e.pos);
                }
            }
            ExprKind::Map(entries) if entries.len() > 1 => {
                // Duplicate-key insertion may dispatch user-defined equality.
                self.effects.insert("unknown");
            }
            ExprKind::Call { .. } => self.scan_call(e),
            // `==` runs the operand type's own `equals`; ordering operators take no user type.
            ExprKind::Binary {
                op: BinaryOp::Eq | BinaryOp::Ne,
                left,
                ..
            } => {
                if let Some(ty) = facts.info(left.id).and_then(|i| i.ty.as_ref()) {
                    self.charge_operations(ty, e.pos, &[Builtin::Equal]);
                }
            }
            // A function named as a value, or called by name: authority is charged where it is referenced.
            ExprKind::Name(_) => {
                let reference = info
                    .and_then(|i| i.symbol.as_ref())
                    .filter(|s| s.native == Native::Source && self.ids.contains(&s.id));
                if let Some(s) = reference {
                    self.edge(s.id, e.pos);
                }
            }
            _ => {}
        }
    }
}

/// `ty` and every type argument nested in it.
fn collect_types(ty: &Ty, out: &mut Vec<Ty>) {
    out.push(ty.clone());
    for arg in &ty.args {
        collect_types(arg, out);
    }
}

/// The effect scan of a program: every callable is a node, but a node is scanned only when a root
/// or a scanned node reaches it. The standard library does not depend on the program, so a
/// library callable scanned later has the effects it would have had first; most programs reach a
/// few library callables and never scan the rest.
#[derive(Default)]
pub struct EffectScan {
    state: Option<State>,
    /// Conservative potential effects by callable id, for the scanned callables.
    effects: HashMap<Name, Vec<&'static str>>,
    /// Declared effects (`// ms: effect`) callers see, by callable id, for the scanned callables.
    declared: HashMap<Name, Vec<String>>,
    /// Fetched packages: what each may reach.
    packages: Vec<crate::types::PackageScope>,
    /// The directives above each callable and in its file header, by callable id. The source never
    /// changes, and every query republishes, so each callable's comment block is read once.
    directives: std::cell::RefCell<HashMap<Name, (Directives, Directives)>>,
}

struct State {
    order: Vec<Name>,
    nodes: HashMap<Name, EffectNode>,
    scanned: HashSet<Name>,
    ids: HashSet<Name>,
    conversions: HashMap<(Name, Name), Vec<Name>>,
    by_receiver: HashMap<Name, Vec<Name>>,
    comparison_ops: HashMap<Name, Vec<(Builtin, Name)>>,
    own_methods: HashMap<Name, Vec<(Name, Name)>>,
}

impl EffectScan {
    /// Registers every callable of `modules` and `methods` as an unscanned node.
    fn new(
        modules: &[ModRef],
        symbols: &HashMap<Name, crate::checker::Names>,
        methods: &[MethodRef],
    ) -> EffectScan {
        let by_file: HashMap<Name, ModRef> = modules.iter().map(|m| (m.file, m.clone())).collect();
        let mut order: Vec<Name> = Vec::new();
        let mut nodes: HashMap<Name, EffectNode> = HashMap::default();
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
                    edges: HashSet::default(),
                    edge_pos: Vec::new(),
                },
            );
        };
        for module in modules {
            let Some(names) = symbols.get(&module.file) else {
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
        for method in methods {
            if let Some(decl) = &method.decl {
                add(
                    method.id,
                    by_file.get(&method.module).cloned(),
                    Target::Method(decl.clone()),
                );
            }
        }
        let ids: HashSet<Name> = nodes.keys().copied().collect();
        let mut conversions: HashMap<(Name, Name), Vec<Name>> = HashMap::default();
        let mut by_receiver: HashMap<Name, Vec<Name>> = HashMap::default();
        let mut comparison_ops: HashMap<Name, Vec<(Builtin, Name)>> = HashMap::default();
        let mut own_methods: HashMap<Name, Vec<(Name, Name)>> = HashMap::default();
        for m in methods {
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
                let syms = ms_syntax::Names::global();
                for b in [Builtin::Equal, Builtin::Hashable, Builtin::Comparable] {
                    if contract.is(b) || m.overrides(syms, b) {
                        comparison_ops
                            .entry(m.receiver.id)
                            .or_default()
                            .push((b, m.id));
                    }
                }
            }
        }
        EffectScan {
            state: Some(State {
                order,
                nodes,
                scanned: HashSet::default(),
                ids,
                conversions,
                by_receiver,
                comparison_ops,
                own_methods,
            }),
            ..EffectScan::default()
        }
    }

    /// Scans `roots` and everything they reach that is not scanned yet, then folds the callees'
    /// effects into their callers. Returns whether any node was scanned.
    fn scan(&mut self, roots: Vec<Name>) -> bool {
        let Some(st) = self.state.as_mut() else {
            return false;
        };
        let mut todo: Vec<Name> = roots
            .into_iter()
            .filter(|id| st.nodes.contains_key(id) && st.scanned.insert(*id))
            .collect();
        if todo.is_empty() {
            return false;
        }
        while let Some(id) = todo.pop() {
            let node = st.nodes.get_mut(&id).expect("node");
            if let Some(module) = node.module.clone() {
                let mut scan = Scan {
                    syms: ms_syntax::Names::global(),
                    module: &module,
                    ids: &st.ids,
                    effects: BTreeSet::new(),
                    edges: HashSet::default(),
                    edge_pos: Vec::new(),
                    conversions: &st.conversions,
                    by_receiver: &st.by_receiver,
                    comparison_ops: &st.comparison_ops,
                    own_methods: &st.own_methods,
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
            for e in node.edges.clone() {
                if st.nodes.contains_key(&e) && st.scanned.insert(e) {
                    todo.push(e);
                }
            }
        }
        true
    }

    /// Declared effects per scanned callable and the project callables that reach an effect no
    /// `// ms: allow_effect` scope permits.
    fn declared_effects(&self) -> (crate::effect_reach::Reach, HashMap<Name, Vec<String>>) {
        let st = self.state.as_ref().expect("scan state");
        let mut lines: HashMap<Name, Lines> = HashMap::default();
        let mut cache = self.directives.borrow_mut();
        let mut reach: Vec<ReachNode> = Vec::with_capacity(st.scanned.len());
        for id in st.order.iter().filter(|id| st.scanned.contains(id)) {
            let node = &st.nodes[id];
            let Some(module) = &node.module else {
                continue;
            };
            let func = match &node.target {
                Target::Decl(d) => FuncRef::of_decl(d.clone()),
                Target::Method(f) => f.clone(),
            };
            let (at, header) = cache.entry(*id).or_insert_with(|| {
                let lines = lines
                    .entry(module.file)
                    .or_insert_with(|| Lines::new(&module.source));
                (lines.above(func.pos().line), lines.header())
            });
            let syms = ms_syntax::Names::global();
            let file = syms.str(module.file);
            let name = syms.str(func.name());
            let label = match &func.decl.decl().kind {
                DeclKind::Impl(i) if func.method().is_some() => {
                    format!("{}.{name}", i.receiver.name(syms))
                }
                _ => name.to_string(),
            };
            let cap = package_holding(&self.packages, file).map(|p| p.effects.clone());
            let header = header.allow.clone();
            reach.push(ReachNode {
                id: *id,
                file: module.file,
                label,
                pos: func.pos(),
                project: !crate::stdlib::is_bundled_source(file),
                entry: name == "main" && func.method().is_none() && cap.is_none(),
                declared: at.declared.clone(),
                allow_fn: at.allow.clone(),
                allow_file: header.or_else(|| cap.clone()),
                cap,
                edges: node.edge_pos.clone(),
            });
        }
        let permits = reach
            .iter()
            .filter(|n| n.project)
            .filter_map(|n| {
                let lines = n.allow_fn.as_ref().or(n.allow_file.as_ref())?;
                Some((n.id, lines.clone()))
            })
            .collect();
        (resolve(&reach), permits)
    }

    /// Folds the effects of the scanned nodes into their callers and publishes the results.
    fn publish(&mut self) -> (crate::effect_reach::Reach, HashMap<Name, Vec<String>>) {
        let (resolved, permits) = self.declared_effects();
        let st = self.state.as_mut().expect("scan state");
        let scanned: Vec<Name> = st
            .order
            .iter()
            .filter(|id| st.scanned.contains(id))
            .copied()
            .collect();
        propagate_effects(&scanned, &mut st.nodes);
        self.effects = scanned
            .iter()
            .map(|id| (*id, st.nodes[id].effects.iter().copied().collect()))
            .collect();
        self.declared = resolved.declared.clone();
        (resolved, permits)
    }

    /// Scans what `id` reaches (once) and publishes.
    fn reach(&mut self, id: Name) {
        let new = self
            .state
            .as_ref()
            .is_some_and(|s| !s.scanned.contains(&id));
        if new && self.scan(vec![id]) {
            self.publish();
        }
    }
}

impl Checker {
    /// Computes the potential effects of the project's callables and of every callable they reach.
    /// An indirect or unclassified operation contributes unknown rather than claiming purity. The
    /// rest of the standard library is scanned if a query asks (`Program::effects_of`).
    pub(crate) fn effect_summaries(&mut self) {
        let mut scan = EffectScan::new(&self.p.modules, &self.p.symbols, &self.p.methods);
        let project: Vec<Name> = {
            let st = scan.state.as_ref().expect("scan state");
            st.order
                .iter()
                .filter(|id| {
                    st.nodes[id].module.as_ref().is_some_and(|m| {
                        !crate::stdlib::is_bundled_source(ms_syntax::Names::global().str(m.file))
                    })
                })
                .copied()
                .collect()
        };
        scan.packages = self.packages.clone();
        scan.scan(project);
        let (resolved, permits) = scan.publish();
        self.p.effect_permits = permits;
        // A package that reaches an effect it did not declare is an error, not a lint finding.
        let (package, project): (Vec<_>, Vec<_>) = resolved
            .violations
            .into_iter()
            .partition(|v| self.package_of(self.syms.str(v.file)).is_some());
        self.p.effect_violations = project;
        for v in package {
            let file = self.syms.str(v.file);
            let name = self
                .package_of(file)
                .map(|p| p.prefix.trim_end_matches('/').to_string())
                .unwrap_or_default();
            let message = format!(
                "package {name} reaches {} through {}, which its ms.toml does not declare; add it to effects under [project], or stop calling it",
                v.effect,
                v.path.join(" -> ")
            );
            self.error_in(v.file, v.pos, ms_syntax::Phase::Type, message);
        }
        *self.p.effect_scan.borrow_mut() = scan;
    }
}

impl crate::checker::Program {
    /// Potential effects of callable `id` (project or library), scanning what it reaches on first use.
    pub fn effects_of(&self, id: Name) -> Vec<&'static str> {
        let mut scan = self.effect_scan.borrow_mut();
        scan.reach(id);
        scan.effects.get(&id).cloned().unwrap_or_default()
    }

    /// Declared effects (`// ms: effect`) callers see for callable `id`, scanning what it reaches on first use.
    pub fn declared_effects_of(&self, id: Name) -> Vec<String> {
        let mut scan = self.effect_scan.borrow_mut();
        scan.reach(id);
        scan.declared.get(&id).cloned().unwrap_or_default()
    }

    /// The callables callable `id` references, first reference of each, in source order (for the
    /// C checker's comparison tool; deleted with the Rust checker).
    pub fn effect_edges_of(&self, id: Name) -> Vec<(Name, Pos)> {
        let mut scan = self.effect_scan.borrow_mut();
        scan.reach(id);
        let Some(node) = scan.state.as_ref().and_then(|s| s.nodes.get(&id)) else {
            return Vec::new();
        };
        node.edge_pos.clone()
    }

    /// Scans every callable, for a listing of the whole library.
    pub fn scan_all_effects(&self) {
        let mut scan = self.effect_scan.borrow_mut();
        let all: Vec<Name> = scan
            .state
            .as_ref()
            .map(|s| s.order.clone())
            .unwrap_or_default();
        if scan.scan(all) {
            scan.publish();
        }
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
    let mut callers: HashMap<Name, Vec<Name>> = HashMap::default();
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
