//! The nested-match ban over `.ms` files and fenced Markdown snippets. A
//! fixture under `tests/` may opt out with a reason on the preceding line.

use crate::skipped;
use ms_syntax::ast::{Expr, ExprKind, Module};
use ms_syntax::parser::parse;
use ms_syntax::visit::{Visitor, walk_decl};
use std::sync::Arc;

const ALLOWANCE: &str = "# manuscript:allow-nested-match ";

pub fn check(files: &[String]) -> Vec<String> {
    let mut issues = Vec::new();
    for path in files.iter().filter(|p| !skipped(p)) {
        let is_ms = path.ends_with(".ms");
        if !is_ms && !path.ends_with(".md") {
            continue;
        }
        let Ok(source) = std::fs::read_to_string(path) else {
            continue;
        };
        if is_ms {
            report(&mut issues, path, &source, 1, path.starts_with("tests/"));
        } else {
            for (line, code) in fences(&source) {
                report(&mut issues, path, &code, line, false);
            }
        }
    }
    issues
}

/// Bodies of ```manuscript, ```ms and ```text fences with their first line.
fn fences(source: &str) -> Vec<(usize, String)> {
    let mut found = Vec::new();
    let mut open: Option<(usize, Vec<&str>)> = None;
    for (index, line) in source.lines().enumerate() {
        match &mut open {
            None => {
                if matches!(line, "```manuscript" | "```ms" | "```text") {
                    open = Some((index + 2, Vec::new()));
                }
            }
            Some((start, body)) => {
                if line == "```" {
                    found.push((*start, body.join("\n") + "\n"));
                    open = None;
                } else {
                    body.push(line);
                }
            }
        }
    }
    found
}

fn report(issues: &mut Vec<String>, path: &str, code: &str, first_line: usize, fixture: bool) {
    let file: Arc<str> = Arc::from(path);
    let mut wrapped = false;
    let mut module = parse(&file, code).ok();
    // Reference fragments may consist solely of executable statements.
    if module.as_ref().is_none_or(|m| m.decls.is_empty()) {
        wrapped = true;
        let indent = code
            .lines()
            .filter(|l| !l.trim().is_empty())
            .map(|l| l.len() - l.trim_start().len())
            .min()
            .unwrap_or(0);
        let body: Vec<String> = code
            .lines()
            .map(|l| format!("    {}", l.get(indent..).unwrap_or(l)))
            .collect();
        module = parse(
            &file,
            &format!("fn fragment() Unit:\n{}\n", body.join("\n")),
        )
        .ok();
    }
    let Some(module) = module else { return };
    let lines: Vec<&str> = code.lines().collect();
    for line in nested_match_lines(&module) {
        // Line within `code`, undoing the wrapper's header line.
        let within = line - usize::from(wrapped);
        let allowed = fixture
            && within >= 2
            && lines.get(within - 2).is_some_and(|l| {
                l.trim()
                    .strip_prefix(ALLOWANCE)
                    .is_some_and(|reason| !reason.trim().is_empty())
            });
        if !allowed {
            issues.push(format!(
                "{path}:{}: nested match; flatten the outer match with an early exit, compatible try, or a small helper",
                first_line + within - 1
            ));
        }
    }
}

/// Lines of matches that sit inside another match's arms.
fn nested_match_lines(module: &Module) -> Vec<usize> {
    struct Scan {
        depth: usize,
        lines: Vec<usize>,
    }
    impl Visitor for Scan {
        fn expr(&mut self, e: &Expr) {
            if matches!(e.kind, ExprKind::Match { .. }) {
                if self.depth > 0 {
                    self.lines.push(e.pos.line as usize);
                }
                self.depth += 1;
            }
        }
        fn leave_expr(&mut self, e: &Expr) {
            if matches!(e.kind, ExprKind::Match { .. }) {
                self.depth -= 1;
            }
        }
    }
    let mut scan = Scan {
        depth: 0,
        lines: Vec::new(),
    };
    for decl in &module.decls {
        walk_decl(&mut scan, decl);
    }
    scan.lines
}
