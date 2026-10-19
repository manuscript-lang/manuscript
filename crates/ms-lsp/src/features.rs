//! Folding ranges and inlay hints.

use crate::analysis::{Analysis, Document};
use crate::json::{Json, obj};
use crate::text::{self, Range};
use ms_check::types::BindingRef;
use ms_syntax::ast::*;
use ms_syntax::visit::{self, Visitor};

/// Indentation-based folding, so it remains available before parsing succeeds.
pub fn folding_ranges(d: &Document) -> Json {
    let lines: Vec<&str> = d.text.split('\n').collect();
    let indent = |line: &str| line.len() - line.trim_start_matches(' ').len();
    let mut result = Vec::new();
    for (start, line) in lines.iter().enumerate() {
        let trimmed = line.trim();
        let code = trimmed.split('#').next().unwrap_or("");
        if !code.ends_with(':') {
            continue;
        }
        let level = indent(line);
        let mut end = start;
        for (next, content) in lines.iter().enumerate().skip(start + 1) {
            if content.trim().is_empty() {
                continue;
            }
            if indent(content) <= level {
                break;
            }
            end = next;
        }
        if end > start {
            result.push(obj([
                ("startLine", start.into()),
                ("endLine", end.into()),
                ("kind", "region".into()),
            ]));
        }
    }
    Json::Arr(result)
}

struct Hints<'a> {
    analysis: &'a Analysis,
    module: ms_check::syntax::ModRef,
    source: &'a str,
    requested: Range,
    hints: Vec<(text::Position, Json)>,
}

impl Visitor for Hints<'_> {
    fn stmt(&mut self, s: &Stmt) {
        let StmtKind::Bind {
            pattern, ty: None, ..
        } = &s.kind
        else {
            return;
        };
        let PatternKind::Name(name) = &pattern.kind else {
            return;
        };
        let binding: Option<BindingRef> = self.module.facts().patterns.get(&pattern.id).cloned();
        let Some(binding) = binding else { return };
        if binding.ty.id.as_str() == "<invalid>" {
            return;
        }
        let p = text::position(
            self.source,
            pattern.pos.offset as usize + name.as_str().len(),
        );
        let (a, b) = (self.requested.start, self.requested.end);
        let after_start = p.line > a.line || (p.line == a.line && p.character >= a.character);
        let before_end = p.line < b.line || (p.line == b.line && p.character <= b.character);
        if after_start && before_end {
            let _ = self.analysis;
            self.hints.push((
                p,
                obj([
                    ("position", p.json()),
                    ("label", format!(": {}", binding.ty).into()),
                    ("kind", 1usize.into()),
                    ("paddingLeft", false.into()),
                    ("paddingRight", false.into()),
                ]),
            ));
        }
    }
}

/// Inferred-type hints for unannotated `let`/`var` names in `requested`.
pub fn inlay_hints(analysis: &Analysis, d: &Document, requested: Range) -> Json {
    let Some(module) = analysis.module(d) else {
        return Json::Arr(Vec::new());
    };
    let mut hints = Hints {
        analysis,
        module: module.clone(),
        source: &d.text,
        requested,
        hints: Vec::new(),
    };
    for decl in &module.decls {
        visit::walk_decl(&mut hints, decl.decl());
    }
    let mut hints = hints.hints;
    hints.sort_by_key(|(p, _)| (p.line, p.character));
    Json::Arr(hints.into_iter().map(|(_, hint)| hint).collect())
}
