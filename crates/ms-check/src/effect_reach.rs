//! Declared effects: what each callable may perform, and which project callables reach an
//! effect they are not permitted. Effects are named by `// ms: effect NAME` lines on a function
//! (the function performs `NAME`, and callers see its declared names instead of what its body
//! reaches) and permitted by `// ms: allow_effect PATTERN` lines. See
//! `proposals/function-effects.md`.
//!
//! The graph is dense: effect names intern to bit positions, each callable owns a fixed-width
//! slice of one flat `Vec<u64>`, and propagation is a worklist over caller lists.

use crate::effect_directives::matches;
use crate::fxmap::HashMap;
use crate::types::Name;
use ms_syntax::Pos;
use std::collections::VecDeque;

/// One callable and the callables it references: calls, function values, closure bodies.
pub struct ReachNode {
    pub id: Name,
    pub file: Name,
    /// Display name: `save`, or `Receiver.method`.
    pub label: String,
    pub pos: Pos,
    /// A project callable is checked; a standard-library one only contributes effects.
    pub project: bool,
    /// `main` is the boundary: it may perform everything.
    pub entry: bool,
    pub declared: Vec<String>,
    /// `allow_effect` lines directly above the callable, or `None`.
    pub allow_fn: Option<Vec<String>>,
    /// `allow_effect` lines in the file header, or `None`.
    pub allow_file: Option<Vec<String>>,
    /// Referenced callables with the position of the first reference.
    pub edges: Vec<(Name, Pos)>,
}

/// A project callable that reaches an effect no scope permits.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Violation {
    pub file: Name,
    /// The first reference in the callable that brings the effect in.
    pub pos: Pos,
    pub effect: String,
    /// Callables from the violating one down to the one that declares the effect.
    pub path: Vec<String>,
}

#[derive(Default)]
pub struct Reach {
    /// Effects callers see for each callable that has any, sorted by name.
    pub declared: HashMap<Name, Vec<String>>,
    pub violations: Vec<Violation>,
}

struct Bits {
    words: usize,
    data: Vec<u64>,
}

impl Bits {
    fn new(rows: usize, words: usize) -> Bits {
        Bits {
            words,
            data: vec![0; rows * words],
        }
    }

    fn row(&self, i: usize) -> &[u64] {
        &self.data[i * self.words..(i + 1) * self.words]
    }

    fn has(&self, i: usize, bit: usize) -> bool {
        self.data[i * self.words + bit / 64] & (1 << (bit % 64)) != 0
    }

    fn set(&mut self, i: usize, bit: usize) {
        self.data[i * self.words + bit / 64] |= 1 << (bit % 64);
    }

    fn any(&self, i: usize) -> bool {
        self.row(i).iter().any(|w| *w != 0)
    }

    fn bits(&self, i: usize) -> impl Iterator<Item = usize> + '_ {
        (0..self.words * 64).filter(move |b| self.has(i, *b))
    }
}

fn permitted(scope: &Option<Vec<String>>, effect: &str) -> bool {
    scope
        .as_ref()
        .is_none_or(|patterns| patterns.iter().any(|p| matches(p, effect)))
}

/// Resolves declared effects over `nodes` and reports unpermitted reach.
pub fn resolve(nodes: &[ReachNode]) -> Reach {
    let mut names: Vec<&str> = nodes
        .iter()
        .flat_map(|n| n.declared.iter().map(String::as_str))
        .collect();
    names.sort_unstable();
    names.dedup();
    if names.is_empty() {
        return Reach::default();
    }
    let slot: HashMap<&str, usize> = names.iter().enumerate().map(|(i, n)| (*n, i)).collect();
    let words = names.len().div_ceil(64);
    let index: HashMap<Name, usize> = nodes.iter().enumerate().map(|(i, n)| (n.id, i)).collect();

    let mut declared = Bits::new(nodes.len(), words);
    let mut inner = Bits::new(nodes.len(), words);
    let mut out = Bits::new(nodes.len(), words);
    let mut callers: Vec<Vec<usize>> = vec![Vec::new(); nodes.len()];
    let mut work: Vec<usize> = Vec::new();
    let mut queued = vec![false; nodes.len()];
    for (i, node) in nodes.iter().enumerate() {
        for effect in &node.declared {
            declared.set(i, slot[effect.as_str()]);
            out.set(i, slot[effect.as_str()]);
        }
        if declared.any(i) {
            work.push(i);
            queued[i] = true;
        }
        for (callee, _) in &node.edges {
            if let Some(&c) = index.get(callee) {
                callers[c].push(i);
            }
        }
    }
    while let Some(callee) = work.pop() {
        queued[callee] = false;
        for &caller in &callers[callee] {
            let keep_own = declared.any(caller);
            let mut grew = false;
            for w in 0..words {
                let incoming = out.data[callee * words + w];
                let fresh = incoming & !inner.data[caller * words + w];
                if fresh != 0 {
                    inner.data[caller * words + w] |= fresh;
                    if !keep_own {
                        out.data[caller * words + w] |= fresh;
                        grew = true;
                    }
                }
            }
            if grew && !queued[caller] {
                queued[caller] = true;
                work.push(caller);
            }
        }
    }

    let mut reach = Reach::default();
    for (i, node) in nodes.iter().enumerate() {
        if out.any(i) {
            reach
                .declared
                .insert(node.id, out.bits(i).map(|b| names[b].to_string()).collect());
        }
    }
    let mut pending: Vec<Vec<usize>> = Vec::new();
    for (i, node) in nodes.iter().enumerate() {
        if !node.project || node.entry {
            continue;
        }
        let none = node.allow_fn.is_none() && node.allow_file.is_none();
        for bit in inner.bits(i) {
            let effect = names[bit];
            if !none && permitted(&node.allow_fn, effect) && permitted(&node.allow_file, effect) {
                continue;
            }
            if pending.is_empty() {
                pending.resize_with(names.len(), Vec::new);
            }
            pending[bit].push(i);
        }
    }
    // Short, sparse queries should not pay for a whole-graph shortest-path table.
    // Once their combined searches cost a graph traversal, share the remaining work.
    if pending.is_empty() {
        return reach;
    }
    let budget = nodes
        .iter()
        .fold(nodes.len(), |n, node| n.saturating_add(node.edges.len()));
    let mut violations = Vec::new();
    for (bit, starts) in pending.into_iter().enumerate() {
        let mut searched = 0usize;
        let mut paths = None;
        for i in starts {
            if paths.is_none() && searched > budget {
                paths = Some(Paths::new(nodes, &index, &callers, &declared, &out, bit));
            }
            let path = if let Some(paths) = &paths {
                paths.path(nodes, &index, &declared, &out, i, bit)
            } else {
                path_to(nodes, &index, &declared, &out, i, bit, &mut searched)
            };
            let node = &nodes[i];
            let first = path.get(1).copied().unwrap_or(i);
            let pos = node
                .edges
                .iter()
                .find(|(callee, _)| index.get(callee) == Some(&first))
                .map_or(node.pos, |(_, pos)| *pos);
            violations.push((
                i,
                Violation {
                    file: node.file,
                    pos,
                    effect: names[bit].to_string(),
                    path: path.iter().map(|p| nodes[*p].label.clone()).collect(),
                },
            ));
        }
    }
    // Stable sorting restores node order, retaining sorted effect names within a node.
    violations.sort_by_key(|(i, _)| *i);
    reach.violations = violations.into_iter().map(|(_, v)| v).collect();
    reach
}

/// A shortest suffix per node for one effect, shared only while emitting that effect.
struct Paths {
    next: Vec<usize>,
}

impl Paths {
    fn new(
        nodes: &[ReachNode],
        index: &HashMap<Name, usize>,
        callers: &[Vec<usize>],
        declared: &Bits,
        out: &Bits,
        bit: usize,
    ) -> Self {
        let mut distance = vec![usize::MAX; nodes.len()];
        let mut queue = VecDeque::new();
        for (i, d) in distance.iter_mut().enumerate() {
            if declared.has(i, bit) {
                *d = 0;
                queue.push_back(i);
            }
        }
        while let Some(callee) = queue.pop_front() {
            for &caller in &callers[callee] {
                if distance[caller] == usize::MAX && out.has(caller, bit) {
                    distance[caller] = distance[callee] + 1;
                    queue.push_back(caller);
                }
            }
        }
        let mut next = vec![usize::MAX; nodes.len()];
        for (i, node) in nodes.iter().enumerate() {
            for (callee, _) in &node.edges {
                let Some(&c) = index.get(callee) else {
                    continue;
                };
                if c == i || distance[c] == usize::MAX {
                    continue;
                }
                let old = next[i];
                if old == usize::MAX
                    || distance[c] < distance[old]
                    || (distance[c] == distance[old] && nodes[c].label < nodes[old].label)
                {
                    next[i] = c;
                }
            }
        }
        Self { next }
    }

    fn path(
        &self,
        nodes: &[ReachNode],
        index: &HashMap<Name, usize>,
        declared: &Bits,
        out: &Bits,
        start: usize,
        bit: usize,
    ) -> Vec<usize> {
        let mut path = vec![start];
        let mut at = start;
        loop {
            let next = self.next[at];
            if next == usize::MAX || next == start {
                // A declaration cannot justify its own body's effect through a cycle.
                return path_to(nodes, index, declared, out, start, bit, &mut 0);
            }
            path.push(next);
            if declared.has(next, bit) {
                return path;
            }
            at = next;
        }
    }
}

/// The shortest chain of references from `start` to a callable that declares effect `bit`,
/// breaking ties by label.
fn path_to(
    nodes: &[ReachNode],
    index: &HashMap<Name, usize>,
    declared: &Bits,
    out: &Bits,
    start: usize,
    bit: usize,
    searched: &mut usize,
) -> Vec<usize> {
    let mut parent: HashMap<usize, usize> = HashMap::default();
    let mut queue = VecDeque::from([start]);
    while let Some(at) = queue.pop_front() {
        *searched = searched.saturating_add(1 + nodes[at].edges.len());
        let mut next: Vec<usize> = nodes[at]
            .edges
            .iter()
            .filter_map(|(callee, _)| index.get(callee).copied())
            .filter(|c| out.has(*c, bit) && *c != start && !parent.contains_key(c))
            .collect();
        next.sort_by(|a, b| nodes[*a].label.cmp(&nodes[*b].label));
        next.dedup();
        for callee in next {
            if parent.contains_key(&callee) {
                continue;
            }
            parent.insert(callee, at);
            if declared.has(callee, bit) {
                let mut path = vec![callee];
                let mut at = callee;
                while let Some(&p) = parent.get(&at) {
                    path.push(p);
                    at = p;
                }
                path.reverse();
                return path;
            }
            queue.push_back(callee);
        }
    }
    vec![start]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::n;

    fn node(name: &str, declared: &[&str], edges: &[&str]) -> ReachNode {
        ReachNode {
            id: n(name),
            file: n("a.ms"),
            label: name.to_string(),
            pos: Pos::default(),
            project: true,
            entry: false,
            declared: declared.iter().map(|s| s.to_string()).collect(),
            allow_fn: None,
            allow_file: None,
            edges: edges.iter().map(|e| (n(e), Pos::default())).collect(),
        }
    }

    fn violations(reach: &Reach) -> Vec<(String, String, Vec<String>)> {
        reach
            .violations
            .iter()
            .map(|v| (v.effect.clone(), v.path[0].clone(), v.path.clone()))
            .collect()
    }

    #[test]
    fn pure_by_default_and_path_is_reported() {
        let mut print = node("print", &["std.console.write"], &[]);
        print.project = false;
        let log = node("log", &[], &["print"]);
        let total = node("total", &[], &["log"]);
        let reach = resolve(&[print, log, total]);
        let got = violations(&reach);
        assert_eq!(got.len(), 2);
        assert_eq!(got[1].2, vec!["total", "log", "print"]);
    }

    #[test]
    fn allow_lines_permit_and_only_tighten() {
        let mut read = node("read_file", &["std.fs.read"], &[]);
        read.project = false;
        let mut load = node("load", &[], &["read_file"]);
        load.allow_fn = Some(vec!["std.fs.read".into()]);
        assert!(resolve(&[read, load]).violations.is_empty());

        let mut write = node("write_file", &["std.fs.write"], &[]);
        write.project = false;
        let mut save = node("save", &[], &["write_file"]);
        save.allow_file = Some(vec!["std.fs.*".into()]);
        save.allow_fn = Some(vec!["std.fs.read".into()]);
        assert_eq!(resolve(&[write, save]).violations.len(), 1);
    }

    #[test]
    fn declaration_hides_the_body_from_callers() {
        let mut connect = node("connect", &["std.net.connect"], &[]);
        connect.project = false;
        let mut exec = node("exec", &["db.write"], &["connect"]);
        exec.allow_fn = Some(vec!["std.net.connect".into()]);
        let mut save = node("save", &[], &["exec"]);
        save.allow_file = Some(vec!["db.*".into()]);
        let reach = resolve(&[connect, exec, save]);
        assert!(reach.violations.is_empty());
        assert_eq!(reach.declared[&n("save")], vec!["db.write".to_string()]);
    }

    #[test]
    fn entry_and_cycles() {
        let mut print = node("print", &["std.console.write"], &[]);
        print.project = false;
        let mut main = node("main", &[], &["a"]);
        main.entry = true;
        let a = node("a", &[], &["b"]);
        let b = node("b", &[], &["a", "print"]);
        let reach = resolve(&[print, main, a, b]);
        let labels: Vec<_> = reach
            .violations
            .iter()
            .map(|v| v.path[0].as_str())
            .collect();
        assert_eq!(labels, vec!["a", "b"]);
    }

    struct Graph {
        index: HashMap<Name, usize>,
        callers: Vec<Vec<usize>>,
        declared: Bits,
        out: Bits,
    }

    impl Graph {
        /// Independent fixed-point oracle for three test effects, including declaration barriers.
        fn new(nodes: &[ReachNode]) -> Self {
            let index: HashMap<_, _> = nodes.iter().enumerate().map(|(i, n)| (n.id, i)).collect();
            let mut callers = vec![Vec::new(); nodes.len()];
            let mut declared = Bits::new(nodes.len(), 1);
            let mut out = Bits::new(nodes.len(), 1);
            for (i, node) in nodes.iter().enumerate() {
                for e in &node.declared {
                    let bit = e.strip_prefix('e').unwrap().parse().unwrap();
                    declared.set(i, bit);
                    out.set(i, bit);
                }
                for (callee, _) in &node.edges {
                    if let Some(&c) = index.get(callee) {
                        callers[c].push(i);
                    }
                }
            }
            loop {
                let mut changed = false;
                for (i, node) in nodes.iter().enumerate() {
                    if !node.declared.is_empty() {
                        continue;
                    }
                    for (callee, _) in &node.edges {
                        let Some(&c) = index.get(callee) else {
                            continue;
                        };
                        for bit in 0..3 {
                            if out.has(c, bit) && !out.has(i, bit) {
                                out.set(i, bit);
                                changed = true;
                            }
                        }
                    }
                }
                if !changed {
                    break;
                }
            }
            Self {
                index,
                callers,
                declared,
                out,
            }
        }

        fn compare(&self, nodes: &[ReachNode]) {
            for bit in 0..3 {
                let paths = Paths::new(
                    nodes,
                    &self.index,
                    &self.callers,
                    &self.declared,
                    &self.out,
                    bit,
                );
                for start in 0..nodes.len() {
                    let old = path_to(
                        nodes,
                        &self.index,
                        &self.declared,
                        &self.out,
                        start,
                        bit,
                        &mut 0,
                    );
                    let new = paths.path(nodes, &self.index, &self.declared, &self.out, start, bit);
                    assert_eq!(new, old, "start={start}, bit={bit}");
                }
            }
        }
    }

    #[test]
    fn shared_paths_preserve_cycles_hidden_effects_and_equal_labels() {
        let mut nodes = vec![
            node("start", &["e0"], &["back", "second", "first", "start"]),
            node("back", &[], &["start"]),
            node("first", &[], &["sink1"]),
            node("second", &[], &["sink2"]),
            node("sink1", &["e0"], &[]),
            node("sink2", &["e0"], &[]),
            node("hidden", &["e1"], &["start", "sink1"]),
            node("caller", &[], &["hidden", "second", "missing"]),
        ];
        nodes[2].label = "same".into();
        nodes[3].label = "same".into();
        Graph::new(&nodes).compare(&nodes);
        // The shortest unrestricted suffix returns to the declaring start. The old
        // source-excluding BFS must instead retain the first equal-label branch.
        let graph = Graph::new(&nodes);
        let paths = Paths::new(
            &nodes,
            &graph.index,
            &graph.callers,
            &graph.declared,
            &graph.out,
            0,
        );
        assert_eq!(
            paths.path(&nodes, &graph.index, &graph.declared, &graph.out, 0, 0),
            vec![0, 3, 5]
        );
    }

    #[test]
    fn shared_paths_match_breadth_first_search_on_generated_graphs() {
        let mut seed = 0x3f891d2a_u64;
        let mut random = || {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
            (seed >> 32) as usize
        };
        for _ in 0..1500 {
            let count = 2 + random() % 24;
            let mut nodes: Vec<_> = (0..count)
                .map(|i| node(&format!("node{i}"), &[], &[]))
                .collect();
            for item in &mut nodes {
                item.label = format!("label{}", random() % 5);
                for bit in 0..3 {
                    if random() % 5 == 0 {
                        item.declared.push(format!("e{bit}"));
                    }
                }
                for _ in 0..random() % (count + 2) {
                    item.edges.push((
                        n(&format!("node{}", random() % (count + 1))),
                        Pos::default(),
                    ));
                }
            }
            Graph::new(&nodes).compare(&nodes);
        }
    }

    #[test]
    fn wide_shared_paths_keep_diagnostic_order_and_first_positions() {
        let mut nodes = vec![node("sink", &["e1", "e0"], &[]), node("hub", &[], &[])];
        for i in 0..64 {
            let name = format!("leaf{i:03}");
            nodes[1].edges.push((n(&name), Pos::default()));
            nodes.push(node(&name, &[], &["sink"]));
        }
        for i in 0..128 {
            let mut root = node(&format!("root{i:03}"), &[], &["hub"]);
            root.edges[0].1 = Pos {
                line: 100 + i,
                column: 7,
                ..Pos::default()
            };
            nodes.push(root);
        }
        let reach = resolve(&nodes);
        assert_eq!(reach.violations.len(), (1 + 64 + 128) * 2);
        for (i, node) in nodes.iter().enumerate().skip(1) {
            for bit in 0..2 {
                let v = &reach.violations[(i - 1) * 2 + bit];
                assert_eq!(v.effect, format!("e{bit}"));
                assert_eq!(v.path[0], node.label);
                assert_eq!(v.pos, node.edges[0].1);
                if i >= 66 {
                    assert_eq!(v.path, [node.label.as_str(), "hub", "leaf000", "sink"]);
                }
            }
        }
    }

    #[test]
    fn shared_resolution_preserves_permissions_and_multiword_effect_order() {
        let effects: Vec<_> = (0..130).map(|i| format!("e{i:03}")).collect();
        let mut sink = node("sink", &[], &[]);
        sink.declared = effects.iter().rev().cloned().collect();
        let mut hub = node("hub", &[], &[]);
        hub.allow_file = Some(vec!["*".into()]);
        let mut nodes = vec![sink, hub];
        let mut expected = Vec::new();
        for i in 0..16 {
            let name = format!("leaf{i:03}");
            nodes[1].edges.push((n(&name), Pos::default()));
            let leaf = node(&name, &[], &["sink"]);
            for effect in &effects {
                expected.push(Violation {
                    file: leaf.file,
                    pos: leaf.pos,
                    effect: effect.clone(),
                    path: vec![name.clone(), "sink".into()],
                });
            }
            nodes.push(leaf);
        }
        for i in 0..128 {
            let name = format!("root{i:03}");
            let mut root = node(&name, &[], &["hub"]);
            root.edges[0].1 = Pos::new(i * 10, i + 1, 3);
            match i % 6 {
                0 => root.entry = true,
                1 => root.project = false,
                2 => root.allow_file = Some(vec!["*".into()]),
                3 => root.allow_file = Some(vec!["e000".into()]),
                4 => {
                    root.allow_file = Some(vec!["e000".into()]);
                    root.allow_fn = Some(vec!["e001".into()]);
                }
                _ => {}
            }
            // Groups 0/1 are boundaries, 2 permits all, 3 permits only e000,
            // and the disjoint scopes in 4 permit no effect at all.
            if i % 6 >= 3 {
                for (bit, effect) in effects.iter().enumerate() {
                    if i % 6 == 3 && bit == 0 {
                        continue;
                    }
                    expected.push(Violation {
                        file: root.file,
                        pos: root.edges[0].1,
                        effect: effect.clone(),
                        path: vec![name.clone(), "hub".into(), "leaf000".into(), "sink".into()],
                    });
                }
            }
            nodes.push(root);
        }
        let reach = resolve(&nodes);
        assert_eq!(reach.violations, expected);
        for node in &nodes {
            assert_eq!(reach.declared[&node.id], effects);
        }
    }
}
