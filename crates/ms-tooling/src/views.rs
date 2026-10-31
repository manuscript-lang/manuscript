//! The diagram views: one question each, built from the fact model.

use crate::facts::{Fact, Facts};
use crate::tree::Node;
use std::collections::HashSet;

/// Names the diagram views, in help order.
pub const VIEWS: [&str; 7] = [
    "calls", "effects", "errors", "modules", "flow", "scope", "tasks",
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
        if view == "flow" || view == "scope" || view == "tasks" {
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
pub fn find_entity<'a>(facts: &'a Facts, name: &str) -> Result<&'a Fact, String> {
    let matches: Vec<&Fact> = facts
        .entities
        .values()
        .filter(|f| f.name == name || f.key == name || format!("{}::{}", f.file, f.name) == name)
        .collect();
    match matches.len() {
        1 => Ok(matches[0]),
        0 => Err(format!(
            "no entity named {name}; use a declaration name or file::name (ms review lists the public surface)"
        )),
        _ => {
            let keys: Vec<String> = matches
                .iter()
                .map(|f| format!("{}::{}", f.file, f.name))
                .collect();
            Err(format!(
                "{name} is ambiguous: {}; qualify it as file::name",
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
