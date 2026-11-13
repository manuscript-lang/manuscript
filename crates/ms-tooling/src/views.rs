//! The diagram views: one question each, built from the fact model.

use crate::facts::{Fact, Facts};
use crate::tree::Node;
use std::collections::{HashMap, HashSet};
use std::fmt::Write;

/// Names the diagram views, in help order.
pub const VIEWS: [&str; 10] = [
    "overview",
    "calls",
    "effects",
    "errors",
    "modules",
    "flow",
    "scope",
    "tasks",
    "types",
    "ownership",
];

/// Bounds one view so a large project stays readable and the output size predictable.
pub const NODE_CAP: usize = 200;

pub fn effect_list(effects: &[String]) -> String {
    if effects.is_empty() {
        "none".to_string()
    } else {
        effects.join("+")
    }
}

pub fn or_none(text: &str) -> &str {
    if text.is_empty() { "none" } else { text }
}

/// Builds one question's tree from the fact model. With `entity` empty the
/// roots are chosen by the view; otherwise the entity is the single root.
pub fn build_view(facts: &Facts, view: &str, entity: &str, depth: i64) -> Result<Node, String> {
    let depth = if depth <= 0 {
        if matches!(view, "flow" | "scope" | "tasks" | "ownership") {
            1
        } else {
            3
        }
    } else {
        depth
    };
    if view == "modules" {
        return modules_view(facts, entity);
    }
    if view == "overview" {
        return Ok(overview_tree(&overview(facts)));
    }
    if view == "types" {
        return types_view(facts, entity, depth);
    }
    if view == "ownership" {
        return ownership_view(facts, entity, depth);
    }
    if view == "flow" || view == "scope" || view == "tasks" {
        return flow_view(facts, view, entity, depth);
    }
    let roots = view_roots(facts, view, entity)?;
    let mut builder = ViewBuilder {
        facts,
        view,
        depth,
        count: 0,
        skipped: 0,
    };
    let mut root = Node::new(format!("{} VIEW", view.to_uppercase()));
    for fact in &roots {
        if builder.count >= NODE_CAP {
            builder.skipped += 1;
            continue;
        }
        root.children
            .push(builder.expand(fact, 0, &mut HashSet::new()));
    }
    if roots.is_empty() {
        root.children.push(Node::new("none"));
    }
    if builder.skipped > 0 {
        root.omitted = builder.skipped;
        root.children.push(Node::new(format!(
            "+{} more (output capped at {NODE_CAP} nodes)",
            builder.skipped
        )));
    }
    Ok(root)
}

struct ViewBuilder<'a> {
    facts: &'a Facts,
    view: &'a str,
    depth: i64,
    count: usize,
    skipped: usize,
}

impl ViewBuilder<'_> {
    fn label(&self, f: &Fact) -> String {
        match self.view {
            "effects" => format!("{}  effects: {}", f.name, effect_list(&f.effects)),
            "errors" => format!(
                "{}  error: {}, try sites: {}",
                f.name,
                or_none(&f.error),
                f.tries
            ),
            _ => format!("{}  [{}] {}:{}", f.name, f.kind, f.file, f.line),
        }
    }

    fn expand(&mut self, f: &Fact, level: i64, path: &mut HashSet<String>) -> Node {
        let mut node = Node {
            label: self.label(f),
            reference: f.key.clone(),
            kind: f.kind.clone(),
            file: f.file.clone(),
            line: f.line,
            ..Node::default()
        };
        self.count += 1;
        if level >= self.depth {
            return node;
        }
        path.insert(f.key.clone());
        for key in &f.calls {
            let Some(callee) = self.facts.entities.get(key) else {
                continue;
            };
            if !relevant(self.view, callee) {
                continue;
            }
            if path.contains(key) {
                if self.count >= NODE_CAP {
                    self.skipped += 1;
                    continue;
                }
                self.count += 1;
                node.children.push(Node {
                    label: format!("{}  (cycle)", callee.name),
                    kind: "cycle".into(),
                    reference: callee.key.clone(),
                    file: callee.file.clone(),
                    line: callee.line,
                    ..Node::default()
                });
                continue;
            }
            if self.count >= NODE_CAP {
                self.skipped += 1;
                continue;
            }
            let child = self.expand(callee, level + 1, path);
            node.children.push(child);
        }
        if self.view == "effects" || self.view == "calls" {
            for target in &f.external {
                if self.view == "effects" && f.effects.is_empty() {
                    break;
                }
                if self.count >= NODE_CAP {
                    self.skipped += 1;
                    continue;
                }
                self.count += 1;
                node.children.push(Node {
                    label: target.clone(),
                    kind: "external".into(),
                    reference: target.clone(),
                    ..Node::default()
                });
            }
        }
        path.remove(&f.key);
        node
    }
}

/// Drops callees that cannot answer the view's question.
fn relevant(view: &str, f: &Fact) -> bool {
    match view {
        "effects" => !f.effects.is_empty(),
        "errors" => !f.error.is_empty() || f.tries > 0,
        _ => true,
    }
}

fn view_roots<'a>(facts: &'a Facts, view: &str, entity: &str) -> Result<Vec<&'a Fact>, String> {
    if !entity.is_empty() {
        return Ok(vec![find_entity(facts, entity)?]);
    }
    let mut called: HashSet<&str> = HashSet::new();
    for f in facts.entities.values().filter(|f| relevant(view, f)) {
        for key in &f.calls {
            if facts
                .entities
                .get(key)
                .is_some_and(|callee| relevant(view, callee))
            {
                called.insert(key);
            }
        }
    }
    // `entities` is keyed by `Fact::key`, so iteration is already in key order.
    let mut roots: Vec<&Fact> = facts
        .entities
        .values()
        .filter(|f| {
            (f.kind == "fn" || f.kind == "method" || f.kind == "test")
                && relevant(view, f)
                && !called.contains(f.key.as_str())
        })
        .collect();
    // Every callable must be reachable from a root, including disconnected
    // recursive groups, which have no node with zero incoming edges.
    let mut reached = HashSet::new();
    for root in &roots {
        mark_reachable(facts, view, &root.key, &mut reached);
    }
    for fact in facts
        .entities
        .values()
        .filter(|f| (f.kind == "fn" || f.kind == "method" || f.kind == "test") && relevant(view, f))
    {
        if !reached.contains(fact.key.as_str()) {
            roots.push(fact);
            mark_reachable(facts, view, &fact.key, &mut reached);
        }
    }
    Ok(roots)
}

fn mark_reachable<'a>(facts: &'a Facts, view: &str, key: &'a str, seen: &mut HashSet<&'a str>) {
    let mut pending = vec![key];
    while let Some(key) = pending.pop() {
        if !seen.insert(key) {
            continue;
        }
        if let Some(fact) = facts.entities.get(key) {
            pending.extend(fact.calls.iter().filter_map(|key| {
                facts
                    .entities
                    .get(key)
                    .filter(|f| relevant(view, f))
                    .map(|_| key.as_str())
            }));
        }
    }
}

/// Resolves a name, `file::name`, or full key to exactly one entity.
/// An exact key takes precedence over display names and qualified names.
pub fn find_entity<'a>(facts: &'a Facts, name: &str) -> Result<&'a Fact, String> {
    if let Some(fact) = facts.entities.get(name) {
        return Ok(fact);
    }
    let matches: Vec<&Fact> = facts
        .entities
        .values()
        .filter(|f| f.name == name || format!("{}::{}", f.file, f.name) == name)
        .collect();
    match matches.len() {
        1 => Ok(matches[0]),
        0 => Err(format!(
            "no entity named {name}; use a declaration name, file::name, or full entity ID file#kind#name (ms review lists the public surface)"
        )),
        _ => {
            let mut keys: Vec<String> = matches
                .iter()
                .map(|f| format!("{}::{}", f.file, f.name))
                .collect();
            // A type and its impl share file::name. Test display names can
            // also equal another entity's qualified name or full key. Count
            // all name matches before offering qualified-name remedies.
            let mut counts: HashMap<&str, usize> =
                keys.iter().map(|key| (key.as_str(), 0)).collect();
            for f in facts.entities.values() {
                if let Some(count) = counts.get_mut(f.name.as_str()) {
                    *count += 1;
                }
                let qualified = format!("{}::{}", f.file, f.name);
                if qualified != f.name
                    && let Some(count) = counts.get_mut(qualified.as_str())
                {
                    *count += 1;
                }
            }
            let usable = keys.iter().zip(&matches).all(|(key, f)| {
                facts
                    .entities
                    .get(key)
                    .map_or(counts[key.as_str()] == 1, |exact| exact.key == f.key)
            });
            if !usable {
                keys = matches.iter().map(|f| f.key.clone()).collect();
            }
            Err(format!(
                "{name} is ambiguous; use one of: {}",
                keys.join(", ")
            ))
        }
    }
}

fn modules_view(facts: &Facts, entity: &str) -> Result<Node, String> {
    let files: Vec<&String> = facts
        .imports
        .keys()
        .filter(|file| entity.is_empty() || *file == entity)
        .collect();
    if !entity.is_empty() && files.is_empty() {
        return Err(format!(
            "no module named {entity}; use a project-relative path such as src/main.ms"
        ));
    }
    let mut root = Node::new("MODULES VIEW");
    let mut count = 0;
    let mut skipped = 0;
    for file in &files {
        if count >= NODE_CAP {
            skipped += 1;
            continue;
        }
        count += 1;
        let mut module = Node {
            label: (*file).clone(),
            kind: "module".into(),
            file: (*file).clone(),
            ..Node::default()
        };
        for path in &facts.imports[*file] {
            if count >= NODE_CAP {
                skipped += 1;
                continue;
            }
            count += 1;
            module.children.push(Node::new(path.clone()));
        }
        root.children.push(module);
    }
    if files.is_empty() {
        root.children.push(Node::new("none"));
    }
    if skipped > 0 {
        root.omitted = skipped;
        root.children.push(Node::new(format!(
            "+{skipped} more (output capped at {NODE_CAP} nodes)"
        )));
    }
    Ok(root)
}

/// Prints one callable's steps, expanding project calls to `depth` levels.
fn flow_view(facts: &Facts, view: &str, entity: &str, depth: i64) -> Result<Node, String> {
    if entity.is_empty() {
        return Err(format!(
            "{view} needs --entity; name a function or method (ms review lists the public surface)"
        ));
    }
    let f = find_entity(facts, entity)?;
    let empty = Vec::new();
    let steps = facts.flows.get(&f.key).unwrap_or(&empty);
    let mut expander = FlowExpander {
        facts,
        depth,
        count: 0,
        skipped: 0,
    };
    let mut root = Node::new(format!("{} VIEW", view.to_uppercase()));
    let mut path = HashSet::from([f.key.clone()]);
    let mut body = expander.expand(steps, 1, &mut path);
    if view == "scope" {
        body = prune_scopes(&body, false);
    }
    if view == "tasks" {
        body = prune_tasks(&body);
    }
    let mut header = Node {
        label: format!("{}  [{}] {}:{}", f.name, f.kind, f.file, f.line),
        reference: f.key.clone(),
        kind: f.kind.clone(),
        file: f.file.clone(),
        line: f.line,
        children: body,
        ..Node::default()
    };
    if header.children.is_empty() {
        header.children = vec![Node::new("none")];
    }
    root.children.push(header);
    if expander.skipped > 0 {
        root.omitted = expander.skipped;
        root.children.push(Node::new(format!(
            "+{} more (output capped at {NODE_CAP} nodes)",
            expander.skipped
        )));
    }
    Ok(root)
}

struct FlowExpander<'a> {
    facts: &'a Facts,
    depth: i64,
    count: usize,
    skipped: usize,
}

impl FlowExpander<'_> {
    fn expand(&mut self, nodes: &[Node], level: i64, path: &mut HashSet<String>) -> Vec<Node> {
        let mut out = Vec::new();
        for n in nodes {
            if self.count >= NODE_CAP {
                self.skipped += 1;
                continue;
            }
            self.count += 1;
            let mut copied = Node {
                label: n.label.clone(),
                kind: n.kind.clone(),
                reference: n.reference.clone(),
                file: n.file.clone(),
                line: n.line,
                children: Vec::new(),
                ..Node::default()
            };
            copied.children = self.expand(&n.children, level, path);
            if !n.reference.is_empty() && level < self.depth {
                if path.contains(&n.reference) {
                    copied.children.push(Node::new("(cycle)"));
                } else {
                    path.insert(n.reference.clone());
                    let callee = self
                        .facts
                        .flows
                        .get(&n.reference)
                        .map(Vec::as_slice)
                        .unwrap_or(&[]);
                    let expanded = self.expand(callee, level + 1, path);
                    copied.children.extend(expanded);
                    path.remove(&n.reference);
                }
            }
            out.push(copied);
        }
        out
    }
}

/// Keeps cleanup scopes and, inside them, the exits that run the cleanup:
/// return, break, continue, and try sites.
fn prune_scopes(nodes: &[Node], in_scope: bool) -> Vec<Node> {
    let mut out = Vec::new();
    for n in nodes {
        let kids = prune_scopes(&n.children, in_scope || n.kind == "scope");
        let exit = in_scope && (n.kind == "exit" || n.kind == "try");
        if n.kind == "scope" || exit || !kids.is_empty() {
            out.push(Node {
                label: n.label.clone(),
                kind: n.kind.clone(),
                file: n.file.clone(),
                line: n.line,
                children: kids,
                ..Node::default()
            });
        }
    }
    out
}

/// Keeps task groups (resource scopes holding a spawn) and the work each spawn starts.
fn prune_tasks(nodes: &[Node]) -> Vec<Node> {
    let mut out = Vec::new();
    for n in nodes {
        if n.kind == "spawn" {
            out.push(n.clone());
            continue;
        }
        let kids = prune_tasks(&n.children);
        if !kids.is_empty() {
            out.push(Node {
                label: n.label.clone(),
                kind: n.kind.clone(),
                file: n.file.clone(),
                line: n.line,
                children: kids,
                ..Node::default()
            });
        }
    }
    out
}

fn head_label(f: &Fact) -> String {
    format!("{}  [{}] {}:{}", f.name, f.kind, f.file, f.line)
}

fn head_node(f: &Fact) -> Node {
    Node {
        label: head_label(f),
        reference: f.key.clone(),
        kind: f.kind.clone(),
        file: f.file.clone(),
        line: f.line,
        ..Node::default()
    }
}

fn capped(root: &mut Node, skipped: usize) {
    if skipped > 0 {
        root.omitted = skipped;
        root.children.push(Node::new(format!(
            "+{skipped} more (output capped at {NODE_CAP} nodes)"
        )));
    }
}

/// How a callable's parameters and result move ownership, per the memory model:
/// plain parameters follow their checked passing mode, `var` is exclusive, and
/// result labels preserve borrowed values and owned views/cases.
fn ownership_view(facts: &Facts, entity: &str, depth: i64) -> Result<Node, String> {
    let roots: Vec<&Fact> = if entity.is_empty() {
        facts
            .entities
            .values()
            .filter(|f| {
                matches!(f.kind.as_str(), "fn" | "method")
                    && (f.scopes > 0 || f.slots.iter().any(|s| s.var))
            })
            .collect()
    } else {
        vec![find_entity(facts, entity)?]
    };
    let mut root = Node::new("OWNERSHIP VIEW");
    let (mut count, mut skipped) = (0, 0);
    for f in &roots {
        if count >= NODE_CAP {
            skipped += 1;
            continue;
        }
        let node = ownership_node(facts, f, 0, depth, &mut HashSet::new(), &mut count);
        root.children.push(node);
    }
    if roots.is_empty() {
        root.children.push(Node::new("none"));
    }
    capped(&mut root, skipped);
    Ok(root)
}

fn ownership_node(
    facts: &Facts,
    f: &Fact,
    level: i64,
    depth: i64,
    path: &mut HashSet<String>,
    count: &mut usize,
) -> Node {
    let mut node = head_node(f);
    *count += 1;
    if f.kind == "interface" {
        // An operation fixes only how it takes `self`; its other modes are the implementer's.
        for op in &f.slots {
            let mode = if op.var {
                "var (exclusive borrow)"
            } else {
                "borrow"
            };
            node.children
                .push(Node::new(format!("{}{}  self {mode}", op.name, op.ty)));
        }
        return node;
    }
    for s in &f.slots {
        let mode = if s.var {
            "var (exclusive borrow)"
        } else {
            s.passing_mode()
        };
        let text = if mode.is_empty() {
            format!("{}: {}", s.name, s.ty)
        } else {
            format!("{}: {}  {mode}", s.name, s.ty)
        };
        node.children.push(Node::new(text));
    }
    if let Some(r) = &f.result {
        node.children.push(Node::new(format!(
            "returns {}  {}",
            r.ty,
            f.result_ownership.label()
        )));
    }
    // After the parameters and result: pages index those positionally.
    match f.receiver {
        "" => {}
        "var" => node
            .children
            .push(Node::new("self  var (exclusive borrow)")),
        mode => node.children.push(Node::new(format!("self  {mode}"))),
    }
    if f.scopes > 0 {
        node.children
            .push(Node::new(format!("closes {} resource scope(s)", f.scopes)));
    }
    if level >= depth {
        return node;
    }
    path.insert(f.key.clone());
    for key in &f.calls {
        let Some(callee) = facts.entities.get(key) else {
            continue;
        };
        if path.contains(key) || *count >= NODE_CAP {
            continue;
        }
        let child = ownership_node(facts, callee, level + 1, depth, path, count);
        node.children.push(child);
    }
    path.remove(&f.key);
    node
}

/// The composition tree of data: each type's fields and cases expand to the
/// project types they hold; a callable expands its parameters and result the same way.
fn types_view(facts: &Facts, entity: &str, depth: i64) -> Result<Node, String> {
    let roots: Vec<&Fact> = if entity.is_empty() {
        let held: HashSet<&str> = facts
            .entities
            .values()
            .filter(|f| matches!(f.kind.as_str(), "type" | "alternative"))
            .flat_map(|f| {
                f.slots
                    .iter()
                    .flat_map(|s| s.refs.iter().map(String::as_str))
            })
            .collect();
        let all: Vec<&Fact> = facts
            .entities
            .values()
            .filter(|f| matches!(f.kind.as_str(), "type" | "alternative" | "interface"))
            .collect();
        let tops: Vec<&Fact> = all
            .iter()
            .copied()
            .filter(|f| !held.contains(f.key.as_str()))
            .collect();
        if tops.is_empty() { all } else { tops }
    } else {
        vec![find_entity(facts, entity)?]
    };
    let mut root = Node::new("TYPES VIEW");
    let (mut count, mut skipped) = (0, 0);
    for f in &roots {
        if count >= NODE_CAP {
            skipped += 1;
            continue;
        }
        let node = type_node(facts, f, 0, depth, &mut HashSet::new(), &mut count);
        root.children.push(node);
    }
    if roots.is_empty() {
        root.children.push(Node::new("none"));
    }
    capped(&mut root, skipped);
    Ok(root)
}

fn type_node(
    facts: &Facts,
    f: &Fact,
    level: i64,
    depth: i64,
    path: &mut HashSet<String>,
    count: &mut usize,
) -> Node {
    let mut node = head_node(f);
    *count += 1;
    if level >= depth {
        return node;
    }
    path.insert(f.key.clone());
    let slots = f.slots.iter().chain(f.result.iter());
    for s in slots {
        if *count >= NODE_CAP {
            break;
        }
        let label = match (s.name.is_empty(), f.kind.as_str()) {
            (true, _) => format!("returns {}", s.ty),
            (false, "alternative") if s.ty.starts_with('(') || s.ty.is_empty() => {
                format!("case {}{}", s.name, s.ty)
            }
            _ => format!("{}: {}", s.name, s.ty),
        };
        *count += 1;
        let mut child = Node::new(label);
        for key in &s.refs {
            let Some(target) = facts.entities.get(key) else {
                continue;
            };
            if path.contains(key) {
                child.children.push(Node {
                    label: format!("{}  (cycle)", target.name),
                    kind: "cycle".into(),
                    reference: key.clone(),
                    ..Node::default()
                });
            } else if *count < NODE_CAP {
                let sub = type_node(facts, target, level + 1, depth, path, count);
                child.children.push(sub);
            }
        }
        node.children.push(child);
    }
    path.remove(&f.key);
    node
}

/// Mermaid output with its own diagram type: a class diagram for `types`, a
/// color-coded flow for `ownership`. Other views, and a callable as `--entity`
/// of `types`, use the generic tree rendering (None).
pub fn mermaid_view(facts: &Facts, view: &str, entity: &str, depth: i64) -> Option<String> {
    match view {
        "overview" => Some(overview_mermaid(&overview(facts))),
        "types" => class_diagram(facts, entity, if depth <= 0 { 3 } else { depth }),
        "ownership" => Some(ownership_flow(
            facts,
            entity,
            if depth <= 0 { 1 } else { depth },
        )),
        _ => None,
    }
}

fn is_data_type(f: &Fact) -> bool {
    matches!(f.kind.as_str(), "type" | "alternative" | "interface")
}

/// Mermaid class members cannot contain `[` or `]`; generics use `~`.
fn mermaid_text(text: &str) -> String {
    text.replace(['[', ']'], "~")
}

fn class_id(f: &Fact) -> String {
    f.name
        .replace(|c: char| !c.is_alphanumeric() && c != '_', "_")
}

fn class_set<'a>(facts: &'a Facts, entity: &str, depth: i64) -> Option<Vec<&'a Fact>> {
    Some(if entity.is_empty() {
        facts
            .entities
            .values()
            .filter(|f| is_data_type(f))
            .collect()
    } else {
        let start = find_entity(facts, entity).ok()?;
        if !is_data_type(start) {
            return None;
        }
        let mut seen = vec![start];
        let mut frontier = vec![start];
        for _ in 0..depth {
            let mut next = Vec::new();
            for f in &frontier {
                for key in f.slots.iter().flat_map(|s| s.refs.iter()) {
                    if let Some(t) = facts.entities.get(key)
                        && !seen.iter().any(|s| s.key == t.key)
                    {
                        seen.push(t);
                        next.push(t);
                    }
                }
            }
            frontier = next;
        }
        seen
    })
}

fn class_diagram(facts: &Facts, entity: &str, depth: i64) -> Option<String> {
    let chosen = class_set(facts, entity, depth)?;
    let chosen = &chosen[..chosen.len().min(NODE_CAP)];
    // Names are labels, not declaration identities. Reserve every existing name before
    // allocating IDs so a generated ID cannot collide with a later declaration's name.
    let mut reserved: HashSet<String> = chosen.iter().map(|f| class_id(f)).collect();
    let mut assigned = HashSet::new();
    let mut ids = HashMap::new();
    let mut next_id = 0;
    for f in chosen {
        let name = class_id(f);
        let id = if assigned.insert(name.clone()) {
            name
        } else {
            loop {
                let id = format!("__ms_type_{next_id}");
                next_id += 1;
                if reserved.insert(id.clone()) {
                    break id;
                }
            }
        };
        ids.insert(f.key.as_str(), id);
    }
    let mut out = String::from("classDiagram\n");
    for f in chosen {
        let id = &ids[f.key.as_str()];
        let name = class_id(f);
        if *id == name {
            let _ = writeln!(out, "    class {id} {{");
        } else {
            let _ = writeln!(out, "    class {id}[\"{name}\"] {{");
        }
        if f.kind != "type" {
            let _ = writeln!(out, "        <<{}>>", f.kind);
        }
        for s in &f.slots {
            if f.kind == "type" {
                let _ = writeln!(out, "        +{} {}", mermaid_text(&s.ty), s.name);
            } else {
                let _ = writeln!(out, "        {}{}", s.name, mermaid_text(&s.ty));
            }
        }
        out.push_str("    }\n");
    }
    for f in chosen {
        for s in &f.slots {
            for key in &s.refs {
                if let Some(target) = ids.get(key.as_str()) {
                    let _ = writeln!(out, "    {} *-- {target} : {}", ids[f.key.as_str()], s.name);
                }
            }
        }
    }
    Some(out)
}

/// Render checked parameter/result modes without inferring ownership from type spellings.
fn ownership_flow(facts: &Facts, entity: &str, depth: i64) -> String {
    let roots = ownership_roots(facts, entity);
    let mut out = String::from("flowchart LR\n");
    let mut styles: Vec<&str> = Vec::new();
    let mut declared: Vec<String> = Vec::new();
    let mut frontier: Vec<&Fact> = roots.iter().copied().take(NODE_CAP).collect();
    let mut done: Vec<&str> = Vec::new();
    for level in 0..=depth {
        let mut next: Vec<&Fact> = Vec::new();
        for f in frontier {
            if done.contains(&f.key.as_str()) {
                continue;
            }
            done.push(&f.key);
            let fid = format!("f{}", done.len());
            let closes = if f.scopes > 0 {
                format!("<br/>closes {}", f.scopes)
            } else {
                String::new()
            };
            let _ = writeln!(
                out,
                "    {fid}[\"{}(){closes}\"]:::fn",
                f.name.replace('"', "'")
            );
            if !f.receiver.is_empty() {
                let tid = flow_type_node(&mut out, &mut declared, "self");
                let _ = writeln!(out, "    {tid} -->|\"self {}\"| {fid}", f.receiver);
                styles.push(match f.receiver {
                    "var" => "stroke:#d33,stroke-width:3px",
                    "move" => "stroke:#2a2,stroke-width:3px",
                    _ => "stroke:#37b",
                });
            }
            for s in &f.slots {
                let mode = s.passing_mode();
                let style = match mode {
                    "var" => "stroke:#d33,stroke-width:3px",
                    "copy" => "stroke:#999,stroke-dasharray:4",
                    "move" => "stroke:#2a2,stroke-width:3px",
                    _ => "stroke:#37b",
                };
                let tid = flow_type_node(&mut out, &mut declared, &s.ty);
                let _ = writeln!(
                    out,
                    "    {tid} -->|\"{}\"| {fid}",
                    format!("{} {mode}", s.name).trim_end()
                );
                styles.push(style);
            }
            if let Some(r) = &f.result {
                let tid = flow_type_node(&mut out, &mut declared, &r.ty);
                let mode = f.result_ownership.label();
                let _ = writeln!(out, "    {fid} -->|\"{mode}\"| {tid}");
                styles.push(
                    if matches!(f.result_ownership, crate::facts::ResultOwnership::Borrow) {
                        "stroke:#37b"
                    } else {
                        "stroke:#2a2,stroke-width:3px"
                    },
                );
            }
            if level < depth {
                next.extend(f.calls.iter().filter_map(|k| facts.entities.get(k)));
            }
        }
        frontier = next;
    }
    out.push_str("    classDef fn fill:#fff3cd,stroke:#b8860b\n");
    for (i, style) in styles.iter().enumerate() {
        let _ = writeln!(out, "    linkStyle {i} {style}");
    }
    out
}

fn flow_type_node(out: &mut String, declared: &mut Vec<String>, ty: &str) -> String {
    let id = format!("t_{}", ty.replace(|c: char| !c.is_alphanumeric(), "_"));
    if !declared.contains(&id) {
        let _ = writeln!(out, "    {id}([\"{}\"])", ty.replace('"', "'"));
        declared.push(id.clone());
    }
    id
}

fn ownership_roots<'a>(facts: &'a Facts, entity: &str) -> Vec<&'a Fact> {
    match find_entity(facts, entity) {
        Ok(f) if !entity.is_empty() => vec![f],
        _ => facts
            .entities
            .values()
            .filter(|f| {
                matches!(f.kind.as_str(), "fn" | "method")
                    && (f.scopes > 0 || f.slots.iter().any(|s| s.var))
            })
            .collect(),
    }
}

fn pad(text: &str, width: usize) -> String {
    format!("{text:<width$}")
}

/// Plain-text counterpart of the Mermaid diagrams: class boxes joined by
/// composition lines, and per-function IN/OUT lines naming each borrow mode.
pub fn ascii_view(facts: &Facts, view: &str, entity: &str, depth: i64) -> Option<String> {
    match view {
        "overview" => Some(overview_ascii(&overview(facts))),
        "types" => {
            let chosen = class_set(facts, entity, if depth <= 0 { 3 } else { depth })?;
            Some(ascii_classes(facts, &chosen))
        }
        "ownership" => Some(ascii_ownership(
            facts,
            entity,
            if depth <= 0 { 1 } else { depth },
        )),
        _ => None,
    }
}

fn ascii_classes(facts: &Facts, chosen: &[&Fact]) -> String {
    let mut out = String::new();
    for f in chosen.iter().take(NODE_CAP) {
        let tag = if f.kind == "type" {
            String::new()
        } else {
            format!("<<{}>> ", f.kind)
        };
        let title = format!("{tag}{}", f.name);
        let members: Vec<String> = f
            .slots
            .iter()
            .map(|s| {
                if f.kind == "type" {
                    format!("{}: {}", s.name, s.ty)
                } else {
                    format!("{}{}", s.name, s.ty)
                }
            })
            .collect();
        let width = members
            .iter()
            .map(String::len)
            .chain([title.len()])
            .max()
            .unwrap_or(0);
        let rule = format!("+-{}-+\n", "-".repeat(width));
        out.push_str(&rule);
        let _ = writeln!(out, "| {} |", pad(&title, width));
        if !members.is_empty() {
            out.push_str(&rule);
            for m in &members {
                let _ = writeln!(out, "| {} |", pad(m, width));
            }
        }
        out.push_str(&rule);
        for s in &f.slots {
            for key in &s.refs {
                if let Some(t) = facts.entities.get(key)
                    && chosen.iter().take(NODE_CAP).any(|c| c.key == t.key)
                {
                    let _ = writeln!(out, "  <>-- {} --> {}", s.name, t.name);
                }
            }
        }
        out.push('\n');
    }
    if chosen.is_empty() {
        out.push_str("none\n");
    }
    out
}

/// One signature line per function: `var` marks an argument the callee may
/// change; parameter and result modes are available in the JSON/Mermaid view.
/// Callees nest beneath their caller.
fn ascii_ownership(facts: &Facts, entity: &str, depth: i64) -> String {
    let mut out = String::new();
    let mut lines = 0;
    for f in ownership_roots(facts, entity) {
        if lines >= NODE_CAP {
            let _ = writeln!(out, "+more (output capped at {NODE_CAP} lines)");
            break;
        }
        signature_lines(facts, f, 0, depth, &mut Vec::new(), &mut lines, &mut out);
    }
    if lines == 0 {
        out.push_str("none\n");
    }
    out
}

fn signature_lines<'a>(
    facts: &'a Facts,
    f: &'a Fact,
    level: i64,
    depth: i64,
    path: &mut Vec<&'a str>,
    lines: &mut usize,
    out: &mut String,
) {
    let receiver = match f.receiver {
        "" => None,
        "borrow" => Some("self".to_string()),
        mode => Some(format!("{mode} self")),
    };
    let params: Vec<String> = receiver
        .into_iter()
        .chain(f.slots.iter().map(|s| {
            let var = if s.var { "var " } else { "" };
            format!("{var}{}: {}", s.name, s.ty)
        }))
        .collect();
    let result = f.result.as_ref().map_or("", |r| r.ty.as_str());
    let closes = if f.scopes > 0 {
        format!("  [closes {}]", f.scopes)
    } else {
        String::new()
    };
    let indent = "  ".repeat(level as usize);
    let _ = writeln!(
        out,
        "{indent}{}({}) {result}{closes}",
        f.name,
        params.join(", ")
    );
    *lines += 1;
    if level >= depth {
        return;
    }
    path.push(&f.key);
    for key in &f.calls {
        let Some(callee) = facts.entities.get(key) else {
            continue;
        };
        if path.contains(&key.as_str()) || *lines >= NODE_CAP {
            continue;
        }
        signature_lines(facts, callee, level + 1, depth, path, lines, out);
    }
    path.pop();
}

/// One module of the system overview.
struct Module {
    file: String,
    fns: usize,
    types: usize,
    tests: usize,
    entry: bool,
    effects: Vec<String>,
    /// Other modules this one calls, with the number of distinct call edges.
    calls: Vec<(String, usize)>,
}

/// The system level: each project module, what it holds, the effects it
/// reaches, and which modules it calls. Module order is by file name.
fn overview(facts: &Facts) -> Vec<Module> {
    let mut modules: std::collections::BTreeMap<&str, Module> = std::collections::BTreeMap::new();
    for file in facts.imports.keys() {
        modules.insert(
            file,
            Module {
                file: file.clone(),
                fns: 0,
                types: 0,
                tests: 0,
                entry: false,
                effects: Vec::new(),
                calls: Vec::new(),
            },
        );
    }
    for f in facts.entities.values() {
        let Some(m) = modules.get_mut(f.file.as_str()) else {
            continue;
        };
        match f.kind.as_str() {
            "fn" | "method" => {
                m.fns += 1;
                m.entry |= f.name == "main";
            }
            "type" | "alternative" | "interface" => m.types += 1,
            "test" | "bench" => m.tests += 1,
            _ => {}
        }
        for e in &f.effects {
            if !m.effects.contains(e) {
                m.effects.push(e.clone());
            }
        }
        for key in &f.calls {
            let Some(target) = facts.entities.get(key) else {
                continue;
            };
            if target.file == f.file {
                continue;
            }
            match m.calls.iter_mut().find(|(file, _)| *file == target.file) {
                Some((_, n)) => *n += 1,
                None => m.calls.push((target.file.clone(), 1)),
            }
        }
    }
    let mut out: Vec<Module> = modules.into_values().collect();
    for m in &mut out {
        m.effects.sort();
        m.calls.sort();
    }
    out
}

fn module_summary(m: &Module) -> String {
    let mut parts = vec![format!("{} fn", m.fns)];
    if m.tests > 0 {
        parts.push(format!(
            "{} test{}",
            m.tests,
            if m.tests == 1 { "" } else { "s" }
        ));
    }
    if m.types > 0 {
        parts.push(format!(
            "{} type{}",
            m.types,
            if m.types == 1 { "" } else { "s" }
        ));
    }
    parts.join(", ")
}

fn overview_ascii(modules: &[Module]) -> String {
    let mut out = String::new();
    for m in modules.iter().take(NODE_CAP) {
        let entry = if m.entry { "  [entry]" } else { "" };
        let _ = writeln!(
            out,
            "{}{entry}  {}  effects: {}",
            m.file,
            module_summary(m),
            effect_list(&m.effects)
        );
        for (file, n) in &m.calls {
            let _ = writeln!(out, "  -> {file}  ({n} calls)");
        }
    }
    if modules.is_empty() {
        out.push_str("none\n");
    }
    out
}

fn overview_mermaid(modules: &[Module]) -> String {
    let mut out = String::from("flowchart LR\n");
    let id = |file: &str| format!("m_{}", file.replace(|c: char| !c.is_alphanumeric(), "_"));
    for m in modules.iter().take(NODE_CAP) {
        let class = if m.entry {
            "entry"
        } else if m.effects.is_empty() {
            "pure"
        } else {
            "effect"
        };
        let _ = writeln!(
            out,
            "    {}[\"{}<br/>{}<br/>{}\"]:::{class}",
            id(&m.file),
            m.file,
            module_summary(m),
            effect_list(&m.effects)
        );
    }
    for m in modules.iter().take(NODE_CAP) {
        for (file, n) in &m.calls {
            let _ = writeln!(out, "    {} -->|{n} calls| {}", id(&m.file), id(file));
        }
    }
    out.push_str("    classDef entry fill:#d6e9ff,stroke:#37b,stroke-width:3px\n");
    out.push_str("    classDef pure fill:#dff5e1,stroke:#2a2\n");
    out.push_str("    classDef effect fill:#fff3cd,stroke:#b8860b\n");
    out
}

fn overview_tree(modules: &[Module]) -> Node {
    let mut root = Node::new("OVERVIEW VIEW");
    for m in modules.iter().take(NODE_CAP) {
        let entry = if m.entry { "  [entry]" } else { "" };
        let mut node = Node {
            label: format!(
                "{}{entry}  {}  effects: {}",
                m.file,
                module_summary(m),
                effect_list(&m.effects)
            ),
            kind: "module".into(),
            file: m.file.clone(),
            ..Node::default()
        };
        for (file, n) in &m.calls {
            node.children
                .push(Node::new(format!("-> {file}  ({n} calls)")));
        }
        root.children.push(node);
    }
    if modules.is_empty() {
        root.children.push(Node::new("none"));
    }
    root
}
