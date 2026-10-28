//! Folding ranges and inlay hints.

use crate::analysis::{Analysis, Document};
use crate::json::{Json, obj};
use crate::text::{self, Range, SourcePositions};
use ms_check::types::BindingRef;
use ms_syntax::ast::*;
use ms_syntax::visit::{self, Visitor};

/// Indentation-based folding, so it remains available before parsing succeeds.
pub fn folding_ranges(d: &Document) -> Json {
    let lines: Vec<&str> = d.text.split('\n').collect();
    let indent = |line: &str| line.len() - line.trim_start_matches(' ').len();
    let mut result = Vec::new();
    for (start, line) in lines.iter().enumerate() {
        let header = text::editor_tokens(line)
            .into_iter()
            .rfind(|token| token.kind != text::EditorKind::Comment);
        if !header.is_some_and(|token| token.is(b':')) {
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
    module: ms_check::syntax::ModRef,
    positions: SourcePositions<'a>,
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
        let p = self
            .positions
            .position(pattern.pos.offset as usize + name.as_str().len());
        let (a, b) = (self.requested.start, self.requested.end);
        if a <= p && p <= b {
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
        module: module.clone(),
        positions: SourcePositions::new(&d.text),
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn folding_headers_allow_comments_and_hashes_in_strings() {
        let source = "fn main() Int: # 😀 note\n    if \"a#b\" == \"a#b\": # note\n        return 1\n    return 0\n";
        let expected = Json::Arr(vec![
            obj([
                ("startLine", 0usize.into()),
                ("endLine", 3usize.into()),
                ("kind", "region".into()),
            ]),
            obj([
                ("startLine", 1usize.into()),
                ("endLine", 2usize.into()),
                ("kind", "region".into()),
            ]),
        ]);
        for source in [source.to_string(), source.replace('\n', "\r\n")] {
            let d = Document::new("file:///folding.ms", source);
            assert_eq!(folding_ranges(&d), expected);
        }
    }

    #[test]
    fn folding_ignores_colons_in_comments_and_strings() {
        let d = Document::new(
            "file:///folding.ms",
            "# heading:\n    # indented comment\nlet text = \"fake: # comment\"\n    let other = 1\n",
        );
        assert_eq!(folding_ranges(&d), Json::Arr(Vec::new()));
    }
}
