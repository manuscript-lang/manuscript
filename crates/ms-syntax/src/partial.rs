//! Editor recovery parsing.
//!
//! [`parse_partial`] retains independently valid declarations for editor
//! analysis. [`crate::parser::parse`] remains the strict build API. Recovered
//! trees keep original positions and source text, and always carry the
//! diagnostics from omitted declarations.

use crate::ast::*;
use crate::diag::Diagnostic;
use crate::lexer::lex;
use crate::parser::{parse, parse_chunk};
use crate::pos::Span;
use std::collections::HashMap;
use std::sync::Arc;

/// Parses `source`, recovering what it can. Returns the module of every
/// declaration that parsed (or parsed after blanking invalid statements) and
/// the diagnostics of everything that did not.
pub fn parse_partial(file: &Arc<str>, source: &str) -> (Module, Vec<Diagnostic>) {
    if let Ok(module) = parse(file, source) {
        return (module, Vec::new());
    }
    let mut module = Module {
        file: file.clone(),
        source: Arc::from(source),
        ..Module::default()
    };
    let mut diagnostics: Vec<Diagnostic> = Vec::new();
    let mut starts: Vec<usize> = Vec::new();
    // A probe records the parse of one candidate root: its end, and its error.
    let mut probes: HashMap<usize, (usize, Option<Box<Diagnostic>>)> = HashMap::new();
    let (mut attempted_start, mut continuation_end) = (usize::MAX, 0usize);
    let mut offset = 0usize;
    let lines: Vec<&str> = source.split_inclusive('\n').collect();
    for (index, line) in lines.iter().enumerate() {
        if offset < continuation_end {
            offset += line.len();
            continue;
        }
        let trimmed = line.trim();
        let first = line.as_bytes().first().copied();
        if first.is_some_and(|b| b != b' ' && b != b'\t')
            && !trimmed.is_empty()
            && !trimmed.starts_with('#')
        {
            let declaration = [
                "import ",
                "export ",
                "def ",
                "extern ",
                "let ",
                "let(",
                "type ",
                "interface ",
                "impl ",
                "test ",
            ]
            .iter()
            .any(|k| trimmed.starts_with(k))
                || is_from_import(trimmed);
            // A fresh declaration synchronizes even after an unmatched opener.
            // Other column-zero lines can still belong to a continued header,
            // import, or expression. Let the lexer handle strings and comments
            // rather than counting delimiter characters in source text.
            if !declaration && let Some(&last) = starts.last() {
                let unterminated = matches!(lex(file, &source[last..offset]), Err(d) if d.message.starts_with("unterminated delimiter"));
                if unterminated {
                    let mut start = last;
                    if attempted_start != start {
                        attempted_start = start;
                        // Probe each possible root once, up to the next possible root.
                        // A successful single-root parse proves the intervening lines
                        // are continuations. Failed probes keep the original splitter.
                        if partial_root_start(&source[start..]) {
                            let mut end = offset;
                            for next in &lines[index..] {
                                if partial_root_start(next) {
                                    break;
                                }
                                end += next.len();
                            }
                            if starts.len() == 1 {
                                start = 0; // The first chunk owns its leading trivia.
                            }
                            // An open prefix cannot parse without a later closer. This
                            // rejects common unfinished headers before another lex/parse;
                            // strings and comments may only cause harmless false positives.
                            if source[offset..end].contains([')', ']', '}']) {
                                let parsed = parse(file, &source[start..end]);
                                let single = parsed.as_ref().is_ok_and(single_partial_root);
                                if parsed.is_err() || single {
                                    probes.insert(start, (end, parsed.err()));
                                }
                                if single {
                                    continuation_end = end;
                                }
                            }
                        }
                    }
                    offset += line.len();
                    continue;
                }
            }
            starts.push(offset);
        }
        offset += line.len();
    }
    if starts.is_empty() {
        if let Err(d) = parse(file, source) {
            diagnostics.push(*d);
        }
        return (module, diagnostics);
    }
    starts[0] = 0;
    starts.push(source.len());
    let (mut line_offset, mut previous) = (0u32, 0usize);
    for index in 0..starts.len() - 1 {
        let (start, end) = (starts[index], starts[index + 1]);
        line_offset += source[previous..start].matches('\n').count() as u32;
        previous = start;
        let chunk = &source[start..end];
        let err = match probes.remove(&start) {
            // Failed probes also avoid repeating the same strict parse.
            Some((probe_end, err)) if probe_end == end => err,
            _ => parse(file, chunk).err(),
        };
        let mut text: &str = chunk;
        let recovered_text;
        if let Some(err) = err {
            let rebased = |mut issue: Diagnostic| {
                issue.message = shift_opened(&issue.message, line_offset);
                issue.pos.offset += start as u32;
                issue.pos.line += line_offset;
                if let Some(e) = issue.end.as_mut() {
                    e.offset += start as u32;
                    e.line += line_offset;
                }
                if let Some(f) = issue.fix.as_mut() {
                    f.pos.offset += start as u32;
                    f.pos.line += line_offset;
                    f.end.offset += start as u32;
                    f.end.line += line_offset;
                }
                issue
            };
            match recover_statements(file, chunk, *err.clone()) {
                None => {
                    if let Some(name) = declared_name(chunk) {
                        module.omitted.push(name);
                    }
                    diagnostics.push(rebased(*err));
                    continue;
                }
                Some((blanked, mut issues)) => {
                    issues.sort_by_key(|i| i.pos.offset);
                    diagnostics.extend(issues.into_iter().map(rebased));
                    module.recovered.push(Span {
                        start: start as u32,
                        end: end as u32,
                    });
                    recovered_text = blanked;
                    text = &recovered_text;
                }
            }
        }
        // The chunk is known to parse; parse again at its true position and
        // node-id range so the merged tree needs no rewriting.
        if let Ok(parsed) = parse_chunk(file, text, start as u32, line_offset, module.node_count) {
            module.node_count = parsed.node_count;
            module.imports.extend(parsed.imports);
            module.decls.extend(parsed.decls);
        }
    }
    (module, diagnostics)
}

/// Only a bound for optimistic parsing, never a recovery boundary. Includes
/// constants and token boundaries such as `import{` and `let(`; malformed input
/// still synchronizes using the original rules.
/// `from` begins an import only before a module path; elsewhere it is an ordinary name.
fn is_from_import(line: &str) -> bool {
    line.strip_prefix("from")
        .is_some_and(|rest| rest.trim_start().starts_with('"'))
}

fn partial_root_start(source: &str) -> bool {
    if source.starts_with("from") {
        return is_from_import(source);
    }
    for keyword in [
        "import",
        "export",
        "def",
        "extern",
        "type",
        "interface",
        "impl",
        "test",
        "let",
    ] {
        if !source.starts_with(keyword) {
            continue;
        }
        return match source.as_bytes().get(keyword.len()) {
            None => true,
            Some(b) => !(b.is_ascii_alphanumeric() || *b == b'_'),
        };
    }
    false
}

/// Grouped imports and constants produce several AST nodes for one written
/// root. Reusing larger chunks would change recovery boundaries.
fn single_partial_root(module: &Module) -> bool {
    let mut root: Option<u32> = None;
    for imp in &module.imports {
        if root.is_some_and(|r| r != imp.pos.offset) {
            return false;
        }
        root = Some(imp.pos.offset);
    }
    for decl in &module.decls {
        let pos = match &decl.kind {
            DeclKind::Const(c) => c.group.unwrap_or(decl.pos),
            _ => decl.pos,
        };
        if root.is_some_and(|r| r != pos.offset) {
            return false;
        }
        root = Some(pos.offset);
    }
    root.is_some()
}

/// Retries a failed declaration chunk with each offending statement (and the
/// block it opens) blanked to spaces, so every remaining statement keeps its
/// original position. Returns `None` when no bounded number of blankings
/// parses, in which case the whole declaration is omitted.
fn recover_statements(
    file: &Arc<str>,
    chunk: &str,
    first: Diagnostic,
) -> Option<(String, Vec<Diagnostic>)> {
    let mut issues = Vec::new();
    let mut lines: Vec<String> = chunk.split_inclusive('\n').map(str::to_string).collect();
    let mut issue = first;
    for attempt in 0..8 {
        // An unterminated delimiter is reported at the end of the chunk; the
        // statement to drop is the one that opened it. Only the first failure
        // is redirected: a delimiter left open by an earlier blanking is a
        // cascade, and the declaration is omitted rather than reported twice.
        let mut line = issue.pos.line as usize;
        let opened = opened_line(&issue.message);
        if opened > 0 && attempt == 0 {
            line = opened;
        }
        // The header line (line 1) failing means the signature is unusable.
        if line < 2 || line > lines.len() {
            return None;
        }
        issues.push(issue.clone());
        let at = line - 1;
        let indent = leading_space(&lines[at]);
        if lines[at].trim().is_empty() || indent == 0 {
            return None;
        }
        for (index, text) in lines.iter_mut().enumerate().skip(at) {
            if index > at && !text.trim().is_empty() && leading_space(text) <= indent {
                break;
            }
            *text = blank(text);
        }
        let text = lines.concat();
        match parse(file, &text) {
            Ok(_) => return Some((text, issues)),
            Err(e) => issue = *e,
        }
    }
    None
}

/// Splits an `unterminated delimiter ... opened at line N:` message into the
/// byte range of `N` (`unterminated delimiter ... opened at line N:`).
fn opened_range(message: &str) -> Option<(usize, usize)> {
    const PREFIX: &str = "unterminated delimiter ";
    const MARK: &str = " opened at line ";
    if !message.starts_with(PREFIX) {
        return None;
    }
    let mut search_end = message.len();
    while let Some(at) = message[..search_end].rfind(MARK) {
        if at >= PREFIX.len() - 1 {
            let digits = at + MARK.len();
            let n = message[digits..]
                .bytes()
                .take_while(u8::is_ascii_digit)
                .count();
            if n > 0 && message[digits + n..].starts_with(':') {
                return Some((digits, digits + n));
            }
        }
        search_end = at;
    }
    None
}

fn opened_line(message: &str) -> usize {
    opened_range(message)
        .and_then(|(a, b)| message[a..b].parse().ok())
        .unwrap_or(0)
}

/// Rewrites the chunk-relative opener line in an unterminated-delimiter
/// message to the file-relative line.
fn shift_opened(message: &str, lines: u32) -> String {
    match opened_range(message) {
        Some((a, b)) if lines != 0 => {
            let line = opened_line(message) + lines as usize;
            format!("{}{}{}", &message[..a], line, &message[b..])
        }
        _ => message.to_string(),
    }
}

fn leading_space(line: &str) -> usize {
    line.len() - line.trim_start_matches([' ', '\t']).len()
}

/// Replaces every byte but line breaks with a space, keeping offsets.
fn blank(line: &str) -> String {
    line.chars()
        .flat_map(|c| {
            if c == '\r' || c == '\n' {
                vec![c]
            } else {
                vec![' '; c.len_utf8()]
            }
        })
        .collect()
}

/// The name a declaration chunk introduces, for chunks that failed to parse.
fn declared_name(chunk: &str) -> Option<String> {
    for line in chunk.split('\n') {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let rest = trimmed.strip_prefix("export ").unwrap_or(trimmed);
        let fields: Vec<&str> = rest.split_whitespace().collect();
        if fields.len() < 2 || !matches!(fields[0], "def" | "type" | "interface") {
            return None;
        }
        return fields[1]
            .split(['(', '[', ':'])
            .find(|s| !s.is_empty())
            .map(str::to_string);
    }
    None
}
