//! Folding ranges and inlay hints.

use crate::analysis::{Analysis, Document};
use crate::json::{Json, obj};
use crate::text::{self, Range, SourcePositions};
use ms_check::api::types::BindingRef;
use ms_syntax::ast::*;
use ms_syntax::visit::{self, Visitor};

/// Lexical suites end at their last code token, excluding trailing comments.
/// Unfinished sources that cannot lex retain forgiving indentation folding.
pub fn folding_ranges(d: &Document) -> Json {
    let file = std::sync::Arc::from(d.path().as_str());
    if let Ok(lexed) = ms_syntax::lexer::lex(&file, &d.text) {
        use ms_syntax::token::Tok;
        let mut starts = Vec::new();
        let mut ranges = Vec::new();
        let mut header = 0;
        let mut last = 0;
        for token in lexed.tokens {
            match token.kind {
                Tok::Indent => starts.push(header),
                Tok::Dedent => {
                    if let Some(start) = starts.pop()
                        && last > start
                    {
                        ranges.push((start, last));
                    }
                }
                Tok::Comment | Tok::Newline | Tok::Eof => {}
                kind => {
                    last = token.end.line as usize - 1;
                    if kind == Tok::Colon {
                        header = token.pos.line as usize - 1;
                    }
                }
            }
        }
        ranges.sort_unstable();
        return Json::Arr(
            ranges
                .into_iter()
                .map(|(start, end)| {
                    obj([
                        ("startLine", start.into()),
                        ("endLine", end.into()),
                        ("kind", "region".into()),
                    ])
                })
                .collect(),
        );
    }
    indentation_folding(d)
}

fn indentation_folding(d: &Document) -> Json {
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
    syms: ms_syntax::Names,
    module: ms_check::api::syntax::ModRef,
    positions: SourcePositions<'a>,
    requested: Range,
    hints: Vec<(text::Position, Json)>,
}

impl Visitor for Hints<'_> {
    fn stmt(&mut self, s: &Stmt) {
        let syms = self.syms;
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
        if binding.ty.is_invalid() {
            return;
        }
        let p = self
            .positions
            .position(pattern.pos.offset as usize + syms.str(name).len());
        let (a, b) = (self.requested.start, self.requested.end);
        if a <= p && p <= b {
            self.hints.push((
                p,
                obj([
                    ("position", p.json()),
                    ("label", format!(": {}", binding.ty.display(syms)).into()),
                    ("kind", 1usize.into()),
                    ("paddingLeft", false.into()),
                    ("paddingRight", false.into()),
                ]),
            ));
        }
    }
}

/// Inferred-type hints for unannotated `let`/`var` names in `requested`.
pub fn inlay_hints(
    syms: ms_syntax::Names,
    analysis: &Analysis,
    d: &Document,
    requested: Range,
) -> Json {
    let Some(module) = analysis.module(syms, d) else {
        return Json::Arr(Vec::new());
    };
    let mut hints = Hints {
        syms,
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
    fn folding_ignores_multiline_payload_structure() {
        for source in [
            "/*\nheading:\n    fake body\n*/\n",
            "let text = \"\"\"\nheading:\n    fake body\n\"\"\"\n",
            "let text = r\"\"\"\nheading:\n    fake body 😀\n\"\"\"\n",
        ] {
            ms_syntax::parser::parse(&std::sync::Arc::from("folding.ms"), source).unwrap();
            let d = Document::new("file:///folding.ms", source);
            assert_eq!(folding_ranges(&d), Json::Arr(Vec::new()));
        }
    }

    #[test]
    fn folding_follows_suites_not_payload_indentation() {
        let cases: &[(&str, &[(usize, usize)])] = &[
            (
                "fn f() Int:\n    let x = 1\n// outside indentation is not a dedent\n    return x\n",
                &[(0, 3)],
            ),
            (
                "fn f() Int:\n    if true:\n        return 1\n    return 0\n",
                &[(0, 3), (1, 2)],
            ),
            (
                "fn f() String:\n    return \"\"\"\npayload:\n    not code\n\"\"\"\n",
                &[(0, 4)],
            ),
            (
                "fn f() Int:\n    return 1\n    // trailing comment\n",
                &[(0, 1)],
            ),
            ("interface Empty:\nfn f() Int:\n    return 1\n", &[(1, 2)]),
            ("fn f(\n    x: Int,\n) Int:\n    return x\n", &[(2, 3)]),
            (
                "fn f() Int:\n    let x = (\n        1 + 2\n    )\n    return x\n",
                &[(0, 4)],
            ),
        ];
        for (source, ranges) in cases {
            let expected = Json::Arr(
                ranges
                    .iter()
                    .map(|&(start, end)| {
                        obj([
                            ("startLine", start.into()),
                            ("endLine", end.into()),
                            ("kind", "region".into()),
                        ])
                    })
                    .collect(),
            );
            for source in [source.to_string(), source.replace('\n', "\r\n")] {
                ms_syntax::lexer::lex(&std::sync::Arc::from("folding.ms"), &source).unwrap();
                let d = Document::new("file:///folding.ms", source);
                assert_eq!(folding_ranges(&d), expected, "{}", d.text);
            }
        }
    }

    #[test]
    fn folding_keeps_unfinished_source_fallback() {
        let d = Document::new("file:///folding.ms", "fn f() Int:\n    return (\n");
        assert_eq!(
            folding_ranges(&d),
            Json::Arr(vec![obj([
                ("startLine", 0usize.into()),
                ("endLine", 1usize.into()),
                ("kind", "region".into()),
            ])])
        );
    }

    #[test]
    fn folding_headers_allow_comments_and_hashes_in_strings() {
        let source = "fn main() Int: // 😀 note\n    if \"a#b\" == \"a#b\": // note\n        return 1\n    return 0\n";
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
            "// heading:\n    // indented comment\nlet text = \"fake: # comment\"\n    let other = 1\n",
        );
        assert_eq!(folding_ranges(&d), Json::Arr(Vec::new()));
    }
}
