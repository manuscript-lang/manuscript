//! Finite generic applications.

use crate::checker::Checker;
use crate::syntax::*;
use crate::types::*;
use ms_syntax::Pos;
use ms_syntax::ast::*;
use ms_syntax::visit::{self, Visitor};
use std::collections::{HashMap, HashSet};

struct Edge {
    target: Name,
    arguments: Vec<Ty>,
    file: Name,
    pos: Pos,
}

struct Node {
    variables: Vec<Ty>,
    module: Option<ModRef>,
    decl: Option<DeclRef>,
    method: Option<FuncRef>,
}

/// Nodes that can reach a directed cycle. Removing sinks also removes their incoming edges;
/// what remains is precisely the part of the graph that can reach an active ancestor.
fn recursive_paths(edges: &HashMap<Name, Vec<Edge>>) -> HashSet<Name> {
    let mut degree: HashMap<Name, usize> = HashMap::new();
    let mut predecessors: HashMap<Name, Vec<Name>> = HashMap::new();
    for (&id, outgoing) in edges {
        degree.insert(id, outgoing.len());
        for edge in outgoing {
            predecessors.entry(edge.target).or_default().push(id);
        }
    }
    // A declaration without a body can be a target without having an adjacency entry.
    for &target in predecessors.keys() {
        degree.entry(target).or_default();
    }
    let mut sinks: Vec<Name> = degree
        .iter()
        .filter_map(|(&id, &count)| (count == 0).then_some(id))
        .collect();
    while let Some(id) = sinks.pop() {
        for pred in predecessors.get(&id).into_iter().flatten() {
            let count = degree
                .get_mut(pred)
                .expect("predecessor has outgoing edges");
            *count -= 1;
            if *count == 0 {
                sinks.push(*pred);
            }
        }
    }
    degree
        .into_iter()
        .filter_map(|(id, count)| (count != 0).then_some(id))
        .collect()
}

struct EdgeScan<'a> {
    module: &'a ModRef,
    nodes: &'a HashMap<Name, Node>,
    methods: &'a HashMap<Name, MethodRef>,
    edges: Vec<Edge>,
}

impl Visitor for EdgeScan<'_> {
    fn expr(&mut self, e: &Expr) {
        let Some(info) = self.module.facts().info(e.id).cloned() else {
            return;
        };
        let file = self.module.file;
        if let Some(s) = &info.symbol
            && self.nodes.contains_key(&s.id)
            && !info.type_args.is_empty()
        {
            let arguments = info
                .type_args
                .iter()
                .map(|a| a.clone().unwrap_or_else(invalid))
                .collect();
            self.edges.push(Edge {
                target: s.id,
                arguments,
                file,
                pos: e.pos,
            });
        }
        if matches!(e.kind, ExprKind::Call { .. })
            && let Some(c) = &info.constructor
            && let Some(s) = c.symbol()
            && self.nodes.contains_key(&s.id)
            && !c.args.is_empty()
        {
            self.edges.push(Edge {
                target: s.id,
                arguments: c.args.clone(),
                file,
                pos: e.pos,
            });
        }
        if let Some(im) = &info.method
            && !im.id.as_str().is_empty()
            && self.nodes.contains_key(&im.id)
            && let Some(m) = self.methods.get(&im.id)
        {
            let mut s = Subst::new();
            if unify(
                &m.receiver,
                &im.receiver,
                &variable_set(&m.variables),
                &mut s,
            ) {
                let arguments = m
                    .variables
                    .iter()
                    .map(|v| s.get(&v.id).cloned().unwrap_or_else(invalid))
                    .collect();
                self.edges.push(Edge {
                    target: m.id,
                    arguments,
                    file,
                    pos: e.pos,
                });
            }
        }
    }
}

impl Checker {
    /// Rejects generic functions and types whose recursive applications change
    /// their type arguments, which would instantiate without end.
    pub(crate) fn finite_applications(&mut self) {
        let modules: HashMap<Name, ModRef> =
            self.p.modules.iter().map(|m| (m.file, m.clone())).collect();
        let mut order: Vec<Name> = Vec::new();
        let mut nodes: HashMap<Name, Node> = HashMap::new();
        for module in &self.p.modules {
            let Some(names) = self.p.symbols.get(&module.file) else {
                continue;
            };
            for d in &module.decls {
                if !matches!(d.decl().kind, DeclKind::Fn(_) | DeclKind::Record(_)) {
                    continue;
                }
                let Some(s) = names.borrow().get(&d.name()).cloned() else {
                    continue;
                };
                if !s.variables().is_empty() {
                    order.push(s.id);
                    nodes.insert(
                        s.id,
                        Node {
                            variables: s.variables(),
                            module: Some(module.clone()),
                            decl: Some(d.clone()),
                            method: None,
                        },
                    );
                }
            }
        }
        let mut methods: HashMap<Name, MethodRef> = HashMap::new();
        for m in &self.p.methods {
            methods.insert(m.id, m.clone());
            if !m.variables.is_empty()
                && let Some(decl) = &m.decl
            {
                order.push(m.id);
                nodes.insert(
                    m.id,
                    Node {
                        variables: m.variables.clone(),
                        module: modules.get(&m.module).cloned(),
                        decl: None,
                        method: Some(decl.clone()),
                    },
                );
            }
        }
        let mut edges: HashMap<Name, Vec<Edge>> = HashMap::new();
        for id in &order {
            let node = &nodes[id];
            let Some(module) = &node.module else {
                continue;
            };
            let mut scan = EdgeScan {
                module,
                nodes: &nodes,
                methods: &methods,
                edges: Vec::new(),
            };
            if let Some(d) = &node.decl {
                visit::walk_decl(&mut scan, d.decl());
                for m in &d.0.folded {
                    visit::walk_callable(&mut scan, &m.func.params, &m.func.body);
                }
            }
            if let Some(f) = &node.method
                && let Some(func) = f.func()
            {
                visit::walk_callable(&mut scan, &func.params, &func.body);
            }
            edges.insert(*id, scan.edges);
        }
        let variables: HashMap<Name, Vec<Ty>> = nodes
            .iter()
            .map(|(id, node)| (*id, node.variables.clone()))
            .collect();
        // An acyclic suffix cannot produce a recursive-application diagnostic. Prune it
        // before walking paths, which otherwise revisits shared suffixes exponentially.
        // Keep the original root/edge order and ancestor-dependent checks on recursive paths.
        let recursive = recursive_paths(&edges);
        for outgoing in edges.values_mut() {
            outgoing.retain(|edge| recursive.contains(&edge.target));
        }
        for root in &order {
            if !recursive.contains(root) {
                continue;
            }
            let mut active: HashMap<Name, Vec<Ty>> = HashMap::new();
            self.visit_application(
                *root,
                variables[root].clone(),
                &variables,
                &edges,
                &mut active,
            );
        }
    }

    fn visit_application(
        &mut self,
        id: Name,
        args: Vec<Ty>,
        variables: &HashMap<Name, Vec<Ty>>,
        edges: &HashMap<Name, Vec<Edge>>,
        active: &mut HashMap<Name, Vec<Ty>>,
    ) {
        if active.contains_key(&id) {
            return;
        }
        active.insert(id, args.clone());
        let mut s = Subst::new();
        for (i, v) in variables[&id].iter().enumerate() {
            if i < args.len() {
                s.insert(v.id, args[i].clone());
            }
        }
        for edge in edges.get(&id).map(Vec::as_slice).unwrap_or(&[]) {
            let next: Vec<Ty> = edge.arguments.iter().map(|a| sub(a, &s)).collect();
            if let Some(previous) = active.get(&edge.target) {
                let equal = previous.len() == next.len()
                    && previous.iter().zip(&next).all(|(a, b)| same(a, b));
                if !equal {
                    self.error_in(
                        edge.file,
                        edge.pos,
                        ms_syntax::Phase::Type,
                        "recursive generic applications must preserve their parameters; a type may refer to itself only with the same type arguments (e.g. List[Node[T]] inside Node[T])".to_string(),
                    );
                }
                continue;
            }
            self.visit_application(edge.target, next, variables, edges, active);
        }
        active.remove(&id);
    }

    /// Follows declaration dependencies, not expanded field layouts. For
    /// example, `Box[Box[Int]]` mentions Box twice but is not a recursive
    /// declaration. Function and interface signatures still participate in
    /// genuine recursive generic applications even though values store
    /// references.
    pub(crate) fn finite_type_applications(&mut self) {
        let mut nodes: HashMap<Name, (Vec<Ty>, DeclRef, Name)> = HashMap::new();
        let mut types: HashMap<Name, Ty> = HashMap::new();
        let mut roots: Vec<Name> = Vec::new();
        for module in &self.p.modules {
            let Some(names) = self.p.symbols.get(&module.file) else {
                continue;
            };
            for d in &module.decls {
                if !matches!(
                    d.decl().kind,
                    DeclKind::Record(_) | DeclKind::Alternative(_) | DeclKind::Interface(_)
                ) {
                    continue;
                }
                let Some(symbol) = names.borrow().get(&d.name()).cloned() else {
                    continue;
                };
                if !symbol.decl.as_ref().is_some_and(|sd| sd.same(d)) {
                    continue;
                }
                let t = symbol.ty();
                nodes.insert(t.id, (symbol.variables(), d.clone(), module.file));
                roots.push(t.id);
                types.insert(t.id, t);
            }
        }
        let mut edges: HashMap<Name, Vec<Edge>> = HashMap::new();
        let mut names: HashMap<(Name, Pos), String> = HashMap::new();
        for id in &roots {
            let (_, d, file) = &nodes[id];
            let def = types[id].def.clone().expect("def");
            let mut found: Vec<Edge> = Vec::new();
            let mut reference = |t: &Ty, pos: Pos| {
                fn walk(
                    t: &Ty,
                    pos: Pos,
                    file: Name,
                    nodes: &HashMap<Name, (Vec<Ty>, DeclRef, Name)>,
                    out: &mut Vec<Edge>,
                ) {
                    if nodes.contains_key(&t.id) {
                        out.push(Edge {
                            target: t.id,
                            arguments: t.args.clone(),
                            file,
                            pos,
                        });
                    }
                    for a in &t.args {
                        walk(a, pos, file, nodes, out);
                    }
                    for p in &t.params {
                        walk(&p.ty, pos, file, nodes, out);
                    }
                    if let Some(r) = &t.result {
                        walk(r, pos, file, nodes, out);
                    }
                }
                walk(t, pos, *file, &nodes, &mut found);
            };
            for (i, f) in def.fields.borrow().iter().enumerate() {
                let pos = d.record_fields()[i].pos;
                names.insert((*file, pos), format!("{}.{}", d.name(), f.name));
                reference(&f.ty, pos);
            }
            for (i, cs) in def.cases.borrow().iter().enumerate() {
                for (j, f) in cs.fields.iter().enumerate() {
                    let pos = d.cases()[i].fields[j].pos;
                    names.insert((*file, pos), format!("{}.{}.{}", d.name(), cs.name, f.name));
                    reference(&f.ty, pos);
                }
            }
            for (i, op) in def.operations.borrow().iter().enumerate() {
                let pos = d.methods()[i].pos;
                names.insert((*file, pos), format!("{}.{}", d.name(), op.name));
                reference(&op.ty, pos);
            }
            edges.insert(*id, found);
        }
        let variables: HashMap<Name, Vec<Ty>> = nodes
            .iter()
            .map(|(id, (vars, _, _))| (*id, vars.clone()))
            .collect();
        let mut reported: HashSet<(Name, Pos)> = HashSet::new();
        // A diagnostic needs an active ancestor, so only declarations on a path to a cycle can
        // produce one. Without this pruning every declaration is a root and a chain of N
        // generic types is walked N times with N different type variables (quadratic).
        let recursive = recursive_paths(&edges);
        for outgoing in edges.values_mut() {
            outgoing.retain(|edge| recursive.contains(&edge.target));
        }
        // A specialization's reachable subgraph is explored once across all roots,
        // so checking N declarations is linear in the graph rather than N walks.
        let mut visited: HashSet<String> = HashSet::new();
        for root in &roots {
            if !recursive.contains(root) {
                continue;
            }
            let mut active: HashMap<Name, Vec<Ty>> = HashMap::new();
            self.visit_type_application(
                *root,
                variables[root].clone(),
                &variables,
                &edges,
                &names,
                &mut reported,
                &mut visited,
                &mut active,
            );
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn visit_type_application(
        &mut self,
        id: Name,
        args: Vec<Ty>,
        variables: &HashMap<Name, Vec<Ty>>,
        edges: &HashMap<Name, Vec<Edge>>,
        names: &HashMap<(Name, Pos), String>,
        reported: &mut HashSet<(Name, Pos)>,
        visited: &mut HashSet<String>,
        active: &mut HashMap<Name, Vec<Ty>>,
    ) {
        // Shared dependencies need checking once for each specialization.
        // Check active cycles at the edge before consulting this cache.
        let mut probe = Type::new(id, id, Kind::Primitive);
        probe.args = args.clone();
        if !visited.insert(type_key(&std::rc::Rc::new(probe))) {
            return;
        }
        active.insert(id, args.clone());
        let mut s = Subst::new();
        for (i, v) in variables[&id].iter().enumerate() {
            if i < args.len() {
                s.insert(v.id, args[i].clone());
            }
        }
        for edge in edges.get(&id).map(Vec::as_slice).unwrap_or(&[]) {
            let next: Vec<Ty> = edge.arguments.iter().map(|a| sub(a, &s)).collect();
            if let Some(previous) = active.get(&edge.target) {
                let equal = previous.len() == next.len()
                    && previous.iter().zip(&next).all(|(a, b)| same(a, b));
                if !equal && reported.insert((edge.file, edge.pos)) {
                    let name = names
                        .get(&(edge.file, edge.pos))
                        .cloned()
                        .unwrap_or_default();
                    self.error_in(
                        edge.file,
                        edge.pos,
                        ms_syntax::Phase::Type,
                        format!("recursive generic applications must preserve their parameters in {name}; keep the same type arguments in the same positions along a recursive cycle"),
                    );
                }
                continue;
            }
            self.visit_type_application(
                edge.target,
                next,
                variables,
                edges,
                names,
                reported,
                visited,
                active,
            );
        }
        active.remove(&id);
    }
}
