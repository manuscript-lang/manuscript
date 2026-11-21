//! Prints what the effect graph and the effect directives give for a text graph or for source
//! files, so the C checker in `src/compiler/` can be compared with it byte for byte
//! (`src/compiler/tests/check-diff.sh`). Temporary tooling for the C rewrite: delete it with the
//! Rust checker.
//!
//!   c_oracle_effects graph < GRAPH     resolve the graph described in `src/compiler/tests/effect-graph.md`
//!   c_oracle_effects directives FILE.. header and per-line directives of each source file

use ms_check::effect_oracle::{Directives, Lines, ReachNode, resolve};
use ms_syntax::{Names, Pos};
use std::fmt::Write;
use std::io::Read;

fn list(items: &[String]) -> String {
    format!("[{}]", items.join(","))
}

fn scope(allow: &Option<Vec<String>>) -> String {
    allow.as_ref().map_or("none".to_string(), |a| list(a))
}

fn directives(out: &mut String, label: &str, d: &Directives) {
    let _ = writeln!(
        out,
        "{label} declared={} allow={}",
        list(&d.declared),
        scope(&d.allow)
    );
}

fn source_files(files: &[String]) -> String {
    let mut out = String::new();
    for path in files {
        let source = std::fs::read_to_string(path).expect("source file");
        let lines = Lines::new(&source);
        let _ = writeln!(out, "file {path}");
        directives(&mut out, "header", &lines.header());
        for line in 1..=source.split('\n').count() as u32 {
            let found = lines.above(line);
            if !found.declared.is_empty() || found.allow.is_some() {
                directives(&mut out, &format!("above {line}"), &found);
            }
        }
    }
    out
}

fn pos(line: &str) -> Pos {
    let v: Vec<u32> = line
        .split_whitespace()
        .map(|t| t.parse().expect("number"))
        .collect();
    Pos {
        line: v[0],
        column: v[1],
        offset: v[2],
    }
}

/// The graph text: one `node ID LABEL FILE LINE COL OFFSET project|library entry|plain` line,
/// then optional `declared`, `allow_fn`, `allow_file`, `cap` lines (a bare keyword is a written,
/// empty scope), `edge CALLEE LINE COL OFFSET` lines, and `end`.
fn parse_graph(text: &str) -> Vec<ReachNode> {
    let names = Names::global();
    let mut nodes: Vec<ReachNode> = Vec::new();
    for line in text.lines() {
        let t: Vec<&str> = line.split_whitespace().collect();
        let rest: Vec<String> = t.iter().skip(1).map(|s| s.to_string()).collect();
        match t.first().copied() {
            Some("node") => nodes.push(ReachNode {
                id: names.intern(t[1]),
                label: t[2].to_string(),
                file: names.intern(t[3]),
                pos: pos(&t[4..7].join(" ")),
                project: t[7] == "project",
                entry: t[8] == "entry",
                declared: Vec::new(),
                allow_fn: None,
                allow_file: None,
                cap: None,
                edges: Vec::new(),
            }),
            Some("declared") => nodes.last_mut().unwrap().declared = rest,
            Some("allow_fn") => nodes.last_mut().unwrap().allow_fn = Some(rest),
            Some("allow_file") => nodes.last_mut().unwrap().allow_file = Some(rest),
            Some("cap") => nodes.last_mut().unwrap().cap = Some(rest),
            Some("edge") => nodes
                .last_mut()
                .unwrap()
                .edges
                .push((names.intern(t[1]), pos(&t[2..5].join(" ")))),
            _ => {}
        }
    }
    nodes
}

fn graph(text: &str) -> String {
    let nodes = parse_graph(text);
    let names = Names::global();
    let reach = resolve(&nodes);
    let mut out = String::new();
    for node in &nodes {
        if let Some(effects) = reach.declared.get(&node.id) {
            let _ = writeln!(
                out,
                "declared {}: {}",
                names.str(node.id),
                effects.join(" ")
            );
        }
    }
    for v in &reach.violations {
        let _ = writeln!(
            out,
            "violation {} {}:{}:{} {}: {}",
            names.str(v.file),
            v.pos.line,
            v.pos.column,
            v.pos.offset,
            v.effect,
            v.path.join(" > ")
        );
    }
    out
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("graph") => {
            let mut text = String::new();
            std::io::stdin().read_to_string(&mut text).expect("stdin");
            print!("{}", graph(&text));
        }
        Some("directives") => print!("{}", source_files(&args[1..])),
        _ => {
            eprintln!("usage: c_oracle_effects graph | directives FILE..");
            std::process::exit(2);
        }
    }
}
