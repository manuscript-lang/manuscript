//! `textDocument/codeAction`: quick fixes, import organization and the
//! format-all action.

use crate::analysis::{Analysis, Document, Documents};
use crate::json::{Json, obj};
use crate::lint::Lint;
use crate::text::{self, Position, Range};
use crate::uri;
use crate::workspace;
use ms_check::api::syntax::ModRef;
use ms_driver::project::pathops;
use ms_syntax::token::Tok;
use std::collections::BTreeMap;
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

/// `(name, "./relative/path.ms")` for each top-level `export` declaration in
/// the other `.ms` files of `d`'s project, found without running the checker.
fn project_exports(
    syms: ms_syntax::Names,
    d: &Document,
    docs: &Documents,
) -> Vec<(String, String, bool)> {
    let Ok(files) = workspace::workspace_documents(d, docs, true, None) else {
        return Vec::new();
    };
    let here = d.path();
    let dir = pathops::dir(&here);
    let mut found = Vec::new();
    for file in files {
        let path = file.path();
        if path == here {
            continue;
        }
        let Some(import) = ms_driver::imports::import_path(&dir, &path) else {
            continue;
        };
        for export in ms_driver::imports::exported_declarations(syms, &file.text) {
            found.push((export.name, import.clone(), export.is_type));
        }
    }
    found.sort();
    found.dedup();
    found
}

/// Import boundaries anchored to the recovered module, scanned only up to the
/// next known declaration. Unrelated unfinished code cannot erase valid imports.
fn import_end_lines(source: &str, module: Option<&ModRef>) -> BTreeMap<usize, usize> {
    let Some(module) = module else {
        return BTreeMap::new();
    };
    let mut boundaries: Vec<usize> = module
        .imports
        .iter()
        .map(|i| i.pos.offset as usize)
        .collect();
    boundaries.extend(module.decls.iter().map(|d| d.pos().offset as usize));
    boundaries.push(source.len());
    boundaries.sort_unstable();
    boundaries.dedup();
    let positions = text::SourcePositions::new(source);
    let mut ends = BTreeMap::new();
    for import in &module.imports {
        let start = import.pos.offset as usize;
        let line = import.pos.line as usize - 1;
        if ends.contains_key(&line) {
            continue;
        }
        let next = boundaries.partition_point(|at| *at <= start);
        let Some(&end) = boundaries.get(next) else {
            continue;
        };
        let Some(part) = source.get(start..end) else {
            continue;
        };
        if let Some(path) = text::editor_tokens(part)
            .iter()
            .find(|t| t.kind == text::EditorKind::Str)
        {
            ends.insert(line, positions.position(start + path.end).line);
        }
    }
    ends
}

/// Keep a blank-terminated initial comment block at the top of the file.
/// Moving effect permissions below an import would change their scope.
pub(crate) fn file_header_end(source: &str) -> Position {
    text::position(
        source,
        ms_driver::imports::import_position(source).offset as usize,
    )
}

/// Where `statement` goes: after the leading run of imports, else after a file header.
fn import_insertion(source: &str, statement: &str, module: Option<&ModRef>) -> (Position, String) {
    let newline = if source.contains("\r\n") {
        "\r\n"
    } else {
        "\n"
    };
    let lines: Vec<&str> = source.split_inclusive('\n').collect();
    let ends = import_end_lines(source, module);
    let mut at = 0;
    let mut last = None;
    while at < lines.len() {
        let line = lines[at].trim();
        if let Some(&end) = ends.get(&at) {
            at = end + 1;
            last = Some(end);
        } else if line.is_empty() || line.starts_with("//") || line.starts_with("/*") {
            at += 1;
        } else {
            break;
        }
    }
    match last {
        Some(line) => {
            let end = line_range(source, line).end;
            let missing = !lines[line].ends_with('\n');
            let prefix = if missing { newline } else { "" };
            (end, format!("{prefix}{statement}{newline}"))
        }
        None => (file_header_end(source), format!("{statement}{newline}")),
    }
}

/// Code actions for `requested`, restricted to the kinds in `only` when given.
pub fn editor_actions(
    syms: ms_syntax::Names,
    d: &Document,
    checked: &Analysis,
    lint: &dyn Lint,
    docs: &Documents,
    requested: Range,
    only: &[String],
) -> Vec<Json> {
    let mut result = format_actions(d);
    let eligible =
        |r: Range| r.start.line <= requested.end.line && r.end.line >= requested.start.line;
    let module = checked.module(syms, d);
    for issue in &checked.diagnostics {
        let Some(m) = &module else { break };
        let (Some(end), Some(fix)) = (issue.end, &issue.fix) else {
            continue;
        };
        if issue.file.as_ref() != syms.str(m.file) || issue.code() != "MS2003" {
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
    // The checker's machine-applicable fixes (misspellings, `let` to `var`,
    // conversions), the same edits `ms check --fix` applies. Import fixes and
    // redundant-prelude removal have their own actions.
    for issue in &checked.diagnostics {
        let Some(m) = &module else { break };
        let Some(fix) = &issue.fix else { continue };
        if issue.file.as_ref() != syms.str(m.file)
            || issue.code() == "MS2003"
            || fix.replacement.starts_with("import ")
        {
            continue;
        }
        let fix_range = Range {
            start: text::position(&d.text, fix.pos.offset as usize),
            end: text::position(&d.text, fix.end.offset as usize),
        };
        let start = text::position(&d.text, issue.pos.offset as usize);
        let r = Range {
            start,
            end: issue.end.map_or(fix_range.end, |e| {
                text::position(&d.text, e.offset as usize)
            }),
        };
        if !eligible(r) {
            continue;
        }
        let title = if fix.replacement.is_empty() {
            "Remove the flagged text".to_string()
        } else if fix.pos.offset == fix.end.offset {
            format!("Insert `{}`", fix.replacement)
        } else {
            format!("Replace with `{}`", fix.replacement)
        };
        let diagnostic = obj([
            ("range", r.json()),
            ("message", issue.message.clone().into()),
            ("code", issue.code().into()),
            ("source", "manuscript".into()),
        ]);
        result.push(action_for(
            d,
            &title,
            "quickfix",
            vec![edit(fix_range, &fix.replacement)],
            vec![diagnostic],
        ));
    }
    let mut project: Option<Vec<(String, String, bool)>> = None;
    for issue in &checked.diagnostics {
        let Some(m) = &module else { break };
        if issue.file.as_ref() != syms.str(m.file) {
            continue;
        }
        let Some(name) = ms_driver::imports::unresolved_name(&issue.message) else {
            continue;
        };
        // The diagnostic covers the unresolved name.
        let start = issue.pos.offset as usize;
        let r = Range {
            start: text::position(&d.text, start),
            end: text::position(&d.text, start + name.len()),
        };
        if !eligible(r) {
            continue;
        }
        let exports = project.get_or_insert_with(|| project_exports(syms, d, docs));
        let types_only = issue.message.starts_with("unknown type ");
        let mut statements: Vec<String> = exports
            .iter()
            .filter(|(exported, _, is_type)| exported == name && (!types_only || *is_type))
            .map(|(_, path, _)| ms_driver::imports::import_statement(name, path))
            .collect();
        // A project declaration is preferred over a standard-library one.
        let standard = if types_only {
            ms_check::api::hints::type_import_hint(&checked.session, name)
        } else {
            ms_check::api::hints::import_hint(&checked.session, name)
        };
        if let Some((_, statement)) = standard.split_once("; add: ") {
            statements.push(statement.to_string());
        }
        for (i, statement) in statements.iter().enumerate() {
            let (at, text) = import_insertion(&d.text, statement, module.as_ref());
            let diagnostic = obj([
                ("range", r.json()),
                ("message", issue.message.clone().into()),
                ("code", issue.code().into()),
                ("source", "manuscript".into()),
            ]);
            let mut action = action_for(
                d,
                &format!("Add `{statement}`"),
                "quickfix",
                vec![edit(Range::at(at), &text)],
                vec![diagnostic],
            );
            if i > 0 {
                action.set("isPreferred", false.into());
            }
            result.push(action);
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
            if issue.file != syms.str(m.file) || issue.code != "MSL102" {
                continue;
            }
            let (edits, r) = unused_import_edits(syms, d, m, issue.offset);
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
    let ends = import_end_lines(&d.text, module.as_ref());
    let mut edits = Vec::new();
    let mut at = 0;
    while at < lines.len() {
        if !ends.contains_key(&at) {
            at += 1;
            continue;
        }
        let start = at;
        let mut block: Vec<String> = Vec::new();
        while let Some(&end) = ends.get(&at) {
            block.push(lines[at..=end].concat());
            at = end + 1;
        }
        let before = block.concat();
        // EOF's missing newline belongs to the block, not to the declaration
        // that happened to come last before sorting.
        let missing_final_newline = !before.ends_with('\n');
        let newline = if before.contains("\r\n") {
            "\r\n"
        } else {
            "\n"
        };
        if missing_final_newline {
            block
                .last_mut()
                .expect("nonempty import run")
                .push_str(newline);
        }
        // Group by module path, the part of the statement after `from`.
        block.sort_by_key(|statement| {
            let path = statement.rsplit_once(" from ").map_or("", |(_, path)| path);
            (path.trim().to_string(), statement.clone())
        });
        let mut after = block.concat();
        if missing_final_newline {
            let trailing = if after.ends_with("\r\n") { 2 } else { 1 };
            after.truncate(after.len() - trailing);
        }
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
/// other bindings; the last name of an unparenthesized list also loses the comma before it.
fn unused_import_edits(
    syms: ms_syntax::Names,
    d: &Document,
    module: &ModRef,
    offset: usize,
) -> (Vec<Json>, Range) {
    let none = (Vec::new(), Range::default());
    let file: Arc<str> = syms.str(module.file).into();
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
        end: text::position(&d.text, offset + syms.str(selected.name).len()),
    };
    let mut edits = vec![edit(r, "")];
    let Some(at) = tokens.iter().position(|t| t.pos.offset as usize == offset) else {
        return (edits, r);
    };
    if let Some(next) = tokens.get(at + 1).filter(|t| t.kind == Tok::Comma) {
        let comma = next.pos.offset as usize;
        let spaces = d.text[comma + 1..]
            .bytes()
            .take_while(|b| matches!(b, b' ' | b'\t'))
            .count();
        edits.push(edit(
            Range {
                start: text::position(&d.text, comma),
                end: text::position(&d.text, comma + 1 + spaces),
            },
            "",
        ));
    } else if let Some(previous) = at
        .checked_sub(1)
        .map(|before| tokens[before])
        .filter(|t| t.kind == Tok::Comma)
    {
        // The last name of a list: drop the separator before it, since a
        // trailing comma is only valid inside parentheses.
        let comma = previous.pos.offset as usize;
        let gap = &d.text[comma + 1..offset];
        let spaces = if gap.chars().all(|c| c == ' ' || c == '\t') {
            gap.len()
        } else {
            0
        };
        let removal = Range {
            start: text::position(&d.text, offset - spaces),
            end: r.end,
        };
        edits = vec![
            edit(
                Range {
                    start: text::position(&d.text, comma),
                    end: text::position(&d.text, comma + 1),
                },
                "",
            ),
            edit(removal, ""),
        ];
    }
    (edits, r)
}
