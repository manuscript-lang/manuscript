//! `textDocument/codeAction`: quick fixes, import organization and the
//! format-all action.

use crate::analysis::{Analysis, Document};
use crate::json::{Json, obj};
use crate::lint::Lint;
use crate::text::{self, Position, Range};
use crate::uri;
use ms_check::syntax::ModRef;
use ms_syntax::token::Tok;
use std::sync::Arc;

fn action_for(
    d: &Document,
    title: &str,
    kind: &str,
    edits: Vec<Json>,
    diagnostics: Vec<Json>,
) -> Json {
    let mut action = obj([
        ("title", title.into()),
        ("kind", kind.into()),
        (
            "edit",
            obj([(
                "documentChanges",
                Json::Arr(vec![obj([
                    (
                        "textDocument",
                        obj([("uri", d.uri.clone().into()), ("version", d.version.into())]),
                    ),
                    ("edits", Json::Arr(edits)),
                ])]),
            )]),
        ),
    ]);
    if !diagnostics.is_empty() {
        action.set("diagnostics", Json::Arr(diagnostics));
        action.set("isPreferred", true.into());
    }
    action
}

fn edit(range: Range, text: &str) -> Json {
    obj([("range", range.json()), ("newText", text.into())])
}

/// The range of whole line `line` including its newline.
fn line_range(source: &str, line: usize) -> Range {
    let mut start = 0;
    for _ in 0..line {
        match source[start..].find('\n') {
            Some(offset) => start += offset + 1,
            None => break,
        }
    }
    let end = match source[start..].find('\n') {
        Some(end) => end + 1,
        None => source.len() - start,
    };
    Range {
        start: text::position(source, start),
        end: text::position(source, start + end),
    }
}

/// The "Format Manuscript document" action, absent when already formatted.
pub fn format_actions(d: &Document) -> Vec<Json> {
    let file: Arc<str> = uri::filename(&d.uri).into();
    let Ok(formatted) = ms_syntax::format(&file, &d.text) else {
        return Vec::new();
    };
    if formatted == d.text {
        return Vec::new();
    }
    let range = Range {
        start: Position::default(),
        end: text::position(&d.text, d.text.len()),
    };
    vec![obj([
        ("title", "Format Manuscript document".into()),
        ("kind", "source.fixAll.manuscript".into()),
        (
            "edit",
            obj([(
                "documentChanges",
                Json::Arr(vec![obj([
                    (
                        "textDocument",
                        obj([("uri", d.uri.clone().into()), ("version", d.version.into())]),
                    ),
                    ("edits", Json::Arr(vec![edit(range, &formatted)])),
                ])]),
            )]),
        ),
    ])]
}

/// Code actions for `requested`, restricted to the kinds in `only` when given.
pub fn editor_actions(
    d: &Document,
    checked: &Analysis,
    lint: &dyn Lint,
    requested: Range,
    only: &[String],
) -> Vec<Json> {
    let mut result = format_actions(d);
    let eligible =
        |r: Range| r.start.line <= requested.end.line && r.end.line >= requested.start.line;
    let module = checked.module(d);
    for issue in &checked.diagnostics {
        let Some(m) = &module else { break };
        let (Some(end), Some(fix)) = (issue.end, &issue.fix) else {
            continue;
        };
        if issue.file.as_ref() != m.file.as_str() || issue.code() != "MS2003" {
            continue;
        }
        let r = Range {
            start: text::position(&d.text, issue.pos.offset as usize),
            end: text::position(&d.text, end.offset as usize),
        };
        if eligible(r) {
            let fix_range = Range {
                start: text::position(&d.text, fix.pos.offset as usize),
                end: text::position(&d.text, fix.end.offset as usize),
            };
            let diagnostic = obj([
                ("range", r.json()),
                ("message", issue.message.clone().into()),
                ("code", issue.code().into()),
                ("source", "manuscript".into()),
            ]);
            result.push(action_for(
                d,
                "Remove redundant prelude import",
                "quickfix",
                vec![edit(fix_range, &fix.replacement)],
                vec![diagnostic],
            ));
        }
    }
    for issue in lint.source(&uri::filename(&d.uri), &d.text) {
        let p = text::position(&d.text, issue.offset);
        let r = Range::at(p);
        if !eligible(r) {
            continue;
        }
        let (mut title, mut end, mut new_text) = ("Insert final newline", p, "\n");
        if issue.code == "MSL001" {
            title = "Remove trailing whitespace";
            let tail = &d.text[issue.offset..];
            let mut n = tail.find('\n').unwrap_or(tail.len());
            if n > 0 && tail.as_bytes()[n - 1] == b'\r' {
                n -= 1;
            }
            end = text::position(&d.text, issue.offset + n);
            new_text = "";
        }
        let diagnostic = obj([
            ("range", r.json()),
            ("message", issue.message.clone().into()),
            ("code", issue.code.clone().into()),
            ("source", "manuscript-lint".into()),
        ]);
        result.push(action_for(
            d,
            title,
            "quickfix",
            vec![edit(Range { start: p, end }, new_text)],
            vec![diagnostic],
        ));
    }
    if let (Some(program), Some(m)) = (&checked.program, &module) {
        for issue in lint.program(program) {
            if issue.file != m.file.as_str() || issue.code != "MSL102" {
                continue;
            }
            let (edits, r) = unused_import_edits(d, m, issue.offset);
            if eligible(r) && !edits.is_empty() {
                let diagnostic = obj([
                    ("range", Range::at(r.start).json()),
                    ("message", issue.message.clone().into()),
                    ("code", issue.code.clone().into()),
                    ("source", "manuscript-lint".into()),
                ]);
                result.push(action_for(
                    d,
                    "Remove unused import",
                    "quickfix",
                    edits,
                    vec![diagnostic],
                ));
            }
        }
    }
    // Sort contiguous import runs. Comments and blank separators retain their
    // original attachment and remain outside the replaced source ranges.
    let lines: Vec<&str> = d.text.split_inclusive('\n').collect();
    let mut edits = Vec::new();
    let mut at = 0;
    let is_import = |line: &str| line.trim().starts_with("import ");
    while at < lines.len() {
        if !is_import(lines[at]) {
            at += 1;
            continue;
        }
        let start = at;
        let mut block: Vec<&str> = Vec::new();
        while at < lines.len() && is_import(lines[at]) {
            block.push(lines[at]);
            at += 1;
        }
        let before = block.concat();
        block.sort();
        let after = block.concat();
        if before != after {
            let range = Range {
                start: line_range(&d.text, start).start,
                end: line_range(&d.text, at - 1).end,
            };
            edits.push(edit(range, &after));
        }
    }
    if !edits.is_empty() {
        result.push(action_for(
            d,
            "Organize imports",
            "source.organizeImports",
            edits,
            Vec::new(),
        ));
    }
    if only.is_empty() {
        return result;
    }
    result
        .into_iter()
        .filter(|action| {
            let kind = action.get("kind").and_then(|k| k.as_str()).unwrap_or("");
            only.iter()
                .any(|wanted| kind == wanted || kind.starts_with(&format!("{wanted}.")))
        })
        .collect()
}

/// A grouped import expands into bindings sharing one declaration position.
/// Remove the selected name and its following comma without touching comments or
/// other bindings. A remaining trailing comma is valid Manuscript syntax.
fn unused_import_edits(d: &Document, module: &ModRef, offset: usize) -> (Vec<Json>, Range) {
    let none = (Vec::new(), Range::default());
    let file: Arc<str> = module.file.as_str().into();
    let Ok(lexed) = ms_syntax::lexer::lex(&file, &module.source) else {
        return none;
    };
    let tokens: Vec<_> = lexed
        .tokens
        .iter()
        .filter(|t| t.kind != Tok::Comment)
        .collect();
    let Some(selected) = module
        .imports
        .iter()
        .find(|i| i.name_pos.offset as usize == offset)
    else {
        return none;
    };
    let count = module
        .imports
        .iter()
        .filter(|i| i.pos.offset == selected.pos.offset)
        .count();
    if count == 1 {
        let mut end_line = selected.name_pos.line;
        for token in &tokens {
            if token.pos.offset >= selected.pos.offset && token.kind == Tok::String {
                end_line = token.pos.line;
                break;
            }
        }
        let r = Range {
            start: line_range(&d.text, selected.pos.line as usize - 1).start,
            end: line_range(&d.text, end_line as usize - 1).end,
        };
        return (vec![edit(r, "")], r);
    }
    let r = Range {
        start: text::position(&d.text, offset),
        end: text::position(&d.text, offset + selected.name.as_str().len()),
    };
    let mut edits = vec![edit(r, "")];
    for (at, token) in tokens.iter().enumerate() {
        if token.pos.offset as usize == offset
            && tokens.get(at + 1).is_some_and(|t| t.kind == Tok::Comma)
        {
            let comma = tokens[at + 1].pos.offset as usize;
            edits.push(edit(
                Range {
                    start: text::position(&d.text, comma),
                    end: text::position(&d.text, comma + 1),
                },
                "",
            ));
            break;
        }
    }
    (edits, r)
}
