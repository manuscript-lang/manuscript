//! Declared effects: what each callable may perform, and which project callables reach an
//! effect they are not permitted. Effects are named by `// ms: effect NAME` lines on a function
//! (the function performs `NAME`, and callers see its declared names instead of what its body
//! reaches) and permitted by `// ms: allow_effect PATTERN` lines. See
//! `proposals/function-effects.md`.
//!
//! The graph is dense: effect names intern to bit positions, each callable owns a fixed-width
//! slice of one flat `Vec<u64>`, and propagation is a worklist over caller lists.

use crate::effect_directives::matches;
use crate::types::Name;
use ms_syntax::Pos;
use std::collections::{HashMap, VecDeque};

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
            let path = path_to(nodes, &index, &declared, &out, i, bit);
            let first = path.get(1).copied().unwrap_or(i);
            let pos = node
                .edges
                .iter()
                .find(|(callee, _)| index.get(callee) == Some(&first))
                .map_or(node.pos, |(_, pos)| *pos);
            reach.violations.push(Violation {
                file: node.file,
                pos,
                effect: effect.to_string(),
                path: path.iter().map(|p| nodes[*p].label.clone()).collect(),
            });
        }
    }
    reach
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
) -> Vec<usize> {
    let mut parent: HashMap<usize, usize> = HashMap::new();
    let mut queue = VecDeque::from([start]);
    while let Some(at) = queue.pop_front() {
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
}
