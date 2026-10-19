//! Ownership fact corpus: small programs with the facts MIR relies on.
//! Each line is `name line:col kind [last]`, in source order.

use ms_check::hir::Body;
use ms_check::ownership::UseKind;
use ms_check::{CheckOptions, ImportMap};
use ms_syntax::ast::*;
use ms_syntax::visit::{self, Visitor};
use std::collections::HashMap;
use std::sync::Arc;

struct Positions(HashMap<NodeId, (u32, u32)>);

impl Visitor for Positions {
    fn expr(&mut self, e: &Expr) {
        self.0.insert(e.id, (e.pos.line, e.pos.column));
    }
    fn stmt(&mut self, s: &Stmt) {
        self.0.insert(s.id, (s.pos.line, s.pos.column));
    }
}

/// Renders the uses of every callable named `function`.
fn facts(source: &str, function: &str) -> Vec<String> {
    // Tests are written with two-space indents for width; the language wants four.
    let source: String = source
        .lines()
        .map(|l| {
            let indent = l.len() - l.trim_start().len();
            format!("{}{}\n", " ".repeat(indent * 2), l.trim_start())
        })
        .collect();
    let function = function.to_string();
    std::thread::Builder::new()
        .stack_size(64 << 20)
        .spawn(move || {
            let file: Arc<str> = Arc::from("t.ms");
            let module = ms_syntax::parser::parse(&file, &source).expect("parses");
            let program = ms_check::check(
                vec![ms_check::load_module(&module)],
                ImportMap::default(),
                CheckOptions::default(),
            );
            assert!(
                program.diagnostics.is_empty(),
                "{:?}",
                program
                    .diagnostics
                    .iter()
                    .map(|d| &d.message)
                    .collect::<Vec<_>>()
            );
            let hir = program.hir();
            let ownership = hir.ownership();
            let callable = hir
                .callables()
                .into_iter()
                .find(|c| c.name.as_str() == function && c.module.file.as_str() == "t.ms")
                .expect("callable");
            let mut positions = Positions(HashMap::new());
            if let Body::Block(b) = callable.body() {
                visit::walk_block(&mut positions, b);
            }
            let o = ownership.of(&callable).expect("facts");
            let mut lines: Vec<((u32, u32), String)> = o
                .uses
                .values()
                .map(|u| {
                    let pos = positions.0.get(&u.node).copied().unwrap_or((0, 0));
                    let name = o.bindings[&u.binding].binding.name;
                    let kind = match u.kind {
                        UseKind::Borrow => "borrow",
                        UseKind::Retain => "retain",
                        UseKind::Capture => "capture",
                        UseKind::Write => "write",
                    };
                    let last = if u.last { " last" } else { "" };
                    (pos, format!("{name} {}:{} {kind}{last}", pos.0, pos.1))
                })
                .collect();
            lines.sort();
            lines.into_iter().map(|(_, l)| l).collect()
        })
        .unwrap()
        .join()
        .unwrap()
}

#[test]
fn straight_line_last_use() {
    let src = "fn f(a: Int) Int:\n  let b = a + 1\n  let c = a + b\n  return c\n";
    assert_eq!(
        facts(src, "f"),
        [
            "a 2:13 borrow",
            "a 3:13 borrow last",
            "b 3:17 borrow last",
            "c 4:12 retain last",
        ]
    );
}

#[test]
fn loop_keeps_reads_alive() {
    let src = "fn f(n: Int) Int:\n  var s = 0\n  var i = 0\n  while i < n:\n    s = s + i\n    i = i + 1\n  return s\n";
    assert_eq!(
        facts(src, "f"),
        [
            "i 4:11 borrow",
            "n 4:15 borrow",
            "s 5:9 write",
            "s 5:13 borrow last",
            "i 5:17 borrow",
            "i 6:9 write",
            "i 6:13 borrow last",
            "s 7:12 retain last",
        ]
    );
}

#[test]
fn branches_join() {
    let src = "fn f(a: List[Int], c: Bool) Int:\n  if c:\n    return a.length()\n  return a.length() + 1\n";
    let got = facts(src, "f");
    assert!(
        got.iter()
            .filter(|l| l.starts_with("a ") && l.ends_with("last"))
            .count()
            == 2,
        "{got:?}"
    );
}

#[test]
fn constructor_and_return_retain() {
    let src = "type Box:\n  v: List[Int]\n\nfn f(xs: List[Int]) Box:\n  return Box(v: xs)\n";
    assert_eq!(facts(src, "f"), ["xs 5:19 retain last"]);
}

#[test]
fn borrow_through_source_callee() {
    let src = "fn total(xs: List[Int]) Int:\n  return xs.length()\n\nfn f(xs: List[Int]) Int:\n  let n = total(xs)\n  return n + total(xs)\n";
    let got = facts(src, "f");
    assert_eq!(got[0], "xs 5:19 borrow", "{got:?}");
    assert_eq!(got[2], "xs 6:22 borrow last", "{got:?}");
}

#[test]
fn escaping_parameter_retains() {
    let src = "fn keep(xs: List[Int]) List[Int]:\n  return xs\n\nfn f(xs: List[Int]) List[Int]:\n  return keep(xs)\n";
    assert_eq!(facts(src, "f"), ["xs 5:17 retain last"]);
}

#[test]
fn closure_capture_is_a_use_at_creation() {
    let src = "fn f(a: Int) Int:\n  let g = fn(x: Int) Int: x + a\n  return g(a)\n";
    let got = facts(src, "f");
    assert!(
        got.iter()
            .any(|l| l.starts_with("a 2:") && l.contains("capture")),
        "{got:?}"
    );
    // Inside the closure a captured variable never dies.
    assert!(
        got.iter()
            .any(|l| l.starts_with("a 2:") && l.contains("borrow") && !l.ends_with("last")),
        "{got:?}"
    );
    assert!(got.iter().any(|l| l == "a 3:14 retain last"), "{got:?}");
}

#[test]
fn short_circuit_right_operand_is_conditional() {
    let src = "fn f(a: Bool, b: Bool) Bool:\n  let x = a and b\n  return x or b\n";
    let got = facts(src, "f");
    // `b` is read again after the first `and`, so its first read is not last.
    assert!(
        got.iter()
            .any(|l| l.starts_with("b 2:") && !l.ends_with("last")),
        "{got:?}"
    );
    assert!(
        got.iter()
            .any(|l| l.starts_with("b 3:") && l.ends_with("last")),
        "{got:?}"
    );
}

#[test]
fn match_arms_join() {
    let src = "type Shape:\n  case Dot\n  case Circle(r: Int)\n\nfn f(s: Shape, k: Int) Int:\n  return match s:\n    Dot: k\n    Circle(r): r + k\n";
    let got = facts(src, "f");
    assert_eq!(
        got.iter()
            .filter(|l| l.starts_with("k ") && l.ends_with("last"))
            .count(),
        2,
        "{got:?}"
    );
}

/// Every source in the diagnostic corpus that checks cleanly goes through the
/// whole pipeline without panicking.
#[test]
fn ownership_is_total() {
    let handle = std::thread::Builder::new()
        .stack_size(256 << 20)
        .spawn(|| {
            let golden = include_str!("golden.txt");
            let mut analyzed = 0;
            for record in golden.split('\u{1e}') {
                let (source, expected) = record.split_once('\u{1f}').expect("record");
                if !expected.trim().is_empty() {
                    continue;
                }
                let file: Arc<str> = Arc::from("t.ms");
                let Ok(module) = ms_syntax::parser::parse(&file, source) else {
                    continue;
                };
                let program = ms_check::check(
                    vec![ms_check::load_module(&module)],
                    ImportMap::default(),
                    CheckOptions::default(),
                );
                let hir = program.hir();
                let ownership = hir.ownership();
                for c in hir.callables() {
                    assert!(ownership.of(&c).is_some());
                }
                analyzed += 1;
            }
            assert!(analyzed > 100, "analyzed {analyzed}");
        })
        .unwrap();
    handle.join().unwrap();
}

fn binding_summary(source: &str, function: &str, binding: &str) -> (bool, bool, bool, bool) {
    let (source, function, binding) = (
        source.to_string(),
        function.to_string(),
        binding.to_string(),
    );
    std::thread::Builder::new()
        .stack_size(64 << 20)
        .spawn(move || {
            let source: String = source
                .lines()
                .map(|l| {
                    let indent = l.len() - l.trim_start().len();
                    format!("{}{}\n", " ".repeat(indent * 2), l.trim_start())
                })
                .collect();
            let file: Arc<str> = Arc::from("t.ms");
            let module = ms_syntax::parser::parse(&file, &source).expect("parses");
            let program = ms_check::check(
                vec![ms_check::load_module(&module)],
                ImportMap::default(),
                CheckOptions::default(),
            );
            assert!(program.diagnostics.is_empty());
            let hir = program.hir();
            let ownership = hir.ownership();
            let c = hir
                .callables()
                .into_iter()
                .find(|c| c.name.as_str() == function && c.module.file.as_str() == "t.ms")
                .unwrap();
            let f = ownership
                .of(&c)
                .unwrap()
                .bindings
                .values()
                .find(|b| b.binding.name.as_str() == binding)
                .unwrap()
                .clone();
            (f.fresh, f.retained, f.captured, f.local_only())
        })
        .unwrap()
        .join()
        .unwrap()
}

#[test]
fn fresh_unescaped_allocation_is_local_only() {
    let src = "fn f() Int:\n  let xs = [1, 2, 3]\n  return xs.length()\n";
    assert_eq!(binding_summary(src, "f", "xs"), (true, false, false, true));
}

#[test]
fn returned_allocation_escapes() {
    let src = "fn f() List[Int]:\n  let xs = [1, 2, 3]\n  return xs\n";
    assert_eq!(binding_summary(src, "f", "xs"), (true, true, false, false));
}
