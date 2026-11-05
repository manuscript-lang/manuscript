//! Editor recovery parsing.
//!
//! [`parse_partial`] retains independently valid declarations for editor
//! analysis. [`crate::parser::parse`] remains the strict build API. Recovered
//! trees keep original positions and source text, and always carry the
//! diagnostics from omitted declarations.

use crate::ast::*;
use crate::diag::Diagnostic;
use crate::lexer::{lex, recovery_continuations, unterminated_prefixes};
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
    let roots: Vec<bool> = lines.iter().map(|line| is_declaration_line(line)).collect();
    let continuations = recovery_continuations(file, source, &roots);
    let mut boundaries: Option<(Vec<usize>, Vec<usize>)> = None;
    let mut last_start_index = 0usize;
    // A lexer pass records the continuation answer for the current root's
    // later column-zero lines. It stops when that root would split, and the
    // next declaration bounds the pass even when a delimiter stays open.
    let mut prefix_index: Option<(usize, Vec<bool>)> = None;
    for (index, line) in lines.iter().enumerate() {
        if offset < continuation_end || continuations[index] {
            offset += line.len();
            continue;
        }
        if is_candidate_line(line) {
            let declaration = is_declaration_line(line);
            // A fresh declaration synchronizes even after an unmatched opener.
            // Other column-zero lines can still belong to a continued header,
            // import, or expression. Let the lexer handle strings and comments
            // rather than counting delimiter characters in source text.
            if !declaration && let Some(&last) = starts.last() {
                let unterminated = if let Some((cached_start, prefixes)) = &prefix_index
                    && *cached_start == last
                {
                    prefixes
                        .get(index - last_start_index)
                        .copied()
                        .unwrap_or(false)
                } else {
                    matches!(lex(file, &source[last..offset]), Err(d) if d.message.starts_with("unterminated delimiter") || d.message.starts_with("unterminated multi-line text"))
                };
                if unterminated {
                    let mut start = last;
                    if attempted_start != start {
                        attempted_start = start;
                        // Probe each possible root once, up to the next possible root.
                        // A successful single-root parse proves the intervening lines
                        // are continuations. Failed probes keep the original splitter.
                        if partial_root_start(&source[start..]) {
                            let mut end = offset;
                            for (next_index, next) in lines.iter().enumerate().skip(index) {
                                if !continuations[next_index] && partial_root_start(next) {
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
                    if continuation_end <= offset
                        && prefix_index
                            .as_ref()
                            .is_none_or(|(cached_start, _)| *cached_start != last)
                    {
                        let (line_offsets, next_declaration) = boundaries
                            .get_or_insert_with(|| line_boundaries(&lines, &continuations));
                        let end_index = next_declaration[index + 1];
                        let stop_at: Vec<bool> = lines[last_start_index..end_index]
                            .iter()
                            .enumerate()
                            .map(|(i, line)| {
                                i > 0
                                    && !continuations[last_start_index + i]
                                    && is_candidate_line(line)
                                    && !is_declaration_line(line)
                            })
                            .collect();
                        let prefixes = unterminated_prefixes(
                            file,
                            &source[last..line_offsets[end_index]],
                            &stop_at,
                        );
                        prefix_index = Some((last, prefixes));
                    }
                    offset += line.len();
                    continue;
                }
            }
            starts.push(offset);
            last_start_index = index;
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
                shift_opened(&mut issue, line_offset);
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

fn line_boundaries(lines: &[&str], continuations: &[bool]) -> (Vec<usize>, Vec<usize>) {
    let mut offsets = Vec::with_capacity(lines.len() + 1);
    offsets.push(0);
    for line in lines {
        offsets.push(offsets.last().unwrap() + line.len());
    }
    let mut next_declaration = vec![lines.len(); lines.len() + 1];
    for index in (0..lines.len()).rev() {
        next_declaration[index] = if !continuations[index] && is_declaration_line(lines[index]) {
            index
        } else {
            next_declaration[index + 1]
        };
    }
    (offsets, next_declaration)
}

fn is_candidate_line(line: &str) -> bool {
    let first = line.as_bytes().first().copied();
    let trimmed = line.trim();
    first.is_some_and(|b| b != b' ' && b != b'\t')
        && !trimmed.is_empty()
        && !trimmed.starts_with("//")
}

/// Whether a column-zero line starts an independent recovery declaration.
pub fn is_declaration_line(line: &str) -> bool {
    is_candidate_line(line) && partial_root_start(line.trim())
}

/// Recognizes declaration starts by token boundary, including contextual words
/// only when their following token selects a declaration. The same roots bound
/// optimistic parsing and synchronize recovery after an unmatched opener.
fn partial_root_start(source: &str) -> bool {
    for keyword in [
        "import",
        "export",
        "extern",
        "type",
        "enum",
        "interface",
        "impl",
        "test",
        "let",
    ] {
        if after_keyword(source, keyword).is_some() {
            return true;
        }
    }
    after_keyword(source, "fn").is_some_and(|rest| {
        let rest = rest.trim_start();
        let name_start = rest
            .as_bytes()
            .first()
            .is_some_and(|b| b.is_ascii_alphabetic() || *b == b'_');
        let name_end = rest
            .bytes()
            .take_while(|b| b.is_ascii_alphanumeric() || *b == b'_')
            .count();
        // A named function needs a parameter or type-parameter list after
        // its name. Inferred callbacks can continue their header on later lines.
        name_start && rest[name_end..].trim_start().starts_with(['(', '['])
    }) || after_keyword(source, "bench").is_some_and(|rest| rest.trim_start().starts_with('"'))
        || after_keyword(source, "opaque").is_some_and(|rest| {
            ["type", "enum"]
                .iter()
                .any(|keyword| after_keyword(rest.trim_start(), keyword).is_some())
        })
}

fn after_keyword<'a>(source: &'a str, keyword: &str) -> Option<&'a str> {
    source.strip_prefix(keyword).filter(|rest| {
        rest.as_bytes()
            .first()
            .is_none_or(|b| !(b.is_ascii_alphanumeric() || *b == b'_'))
    })
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
        let opened = issue.opener_line as usize;
        if opened > 0 && attempt == 0 {
            line = opened;
        }
        // A misindented line of multi-line text drops the whole statement.
        if issue.message.starts_with("text line is indented less") && attempt == 0 {
            while line > 1 && line <= lines.len() && !lines[line - 1].trim_end().ends_with("\"\"\"")
            {
                line -= 1;
            }
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
        // A one-line statement cut off mid-expression (`return g.`, `let v = a +`)
        // keeps its operands for navigation once the dangling tail is trimmed.
        let single = lines
            .get(at + 1..)
            .and_then(|rest| rest.iter().find(|l| !l.trim().is_empty()))
            .is_none_or(|next| leading_space(next) <= indent);
        if single && let Some(trimmed) = trim_dangling(file, &lines, at) {
            return Some((trimmed, issues));
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

/// Removes the dangling tail of line `at` (a trailing `.`, `?.`, operator or
/// separator) until the declaration parses, keeping the line's columns by
/// padding with spaces. `None` when trimming does not make it parse.
fn trim_dangling(file: &Arc<str>, lines: &[String], at: usize) -> Option<String> {
    let line = &lines[at];
    let newline = &line[line.trim_end_matches(['\n', '\r']).len()..];
    let mut code = line.trim_end_matches(['\n', '\r']).trim_end().to_string();
    if code.contains("//") || code.contains('"') {
        return None;
    }
    for _ in 0..3 {
        let kept = code.trim_end_matches(|c: char| {
            matches!(
                c,
                '.' | '?' | '+' | '-' | '*' | '/' | '%' | '<' | '>' | '=' | '!' | ',' | '|'
            ) || c == ' '
        });
        let kept = ["and", "or", "not"]
            .iter()
            .find_map(|w| kept.strip_suffix(w).filter(|r| r.ends_with(' ')))
            .unwrap_or(kept);
        if kept.len() == code.len() || kept.trim().is_empty() {
            return None;
        }
        code = kept.trim_end().to_string();
        let mut attempt = lines.to_vec();
        attempt[at] = format!(
            "{}{}{newline}",
            code,
            " ".repeat(line.trim_end_matches(['\n', '\r']).len() - code.len())
        );
        let text = attempt.concat();
        if parse(file, &text).is_ok() {
            return Some(text);
        }
    }
    None
}

/// Rewrites the chunk-relative opener position in an unterminated-delimiter
/// diagnostic to the file-relative one.
fn shift_opened(issue: &mut Diagnostic, lines: u32) {
    if issue.opener_line == 0 {
        return;
    }
    let old = format!("opened at line {}:", issue.opener_line);
    issue.opener_line += lines;
    let new = format!("opened at line {}:", issue.opener_line);
    issue.message = issue.message.replacen(&old, &new, 1);
}

fn leading_space(line: &str) -> usize {
    line.len() - line.trim_start_matches([' ', '\t']).len()
}

/// Replaces every byte but line breaks with a space, keeping offsets.
fn blank(line: &str) -> String {
    let bytes = line
        .bytes()
        .map(|byte| match byte {
            b'\r' | b'\n' => byte,
            _ => b' ',
        })
        .collect();
    String::from_utf8(bytes).expect("blanked source is ASCII")
}

/// The name a declaration chunk introduces, for chunks that failed to parse.
fn declared_name(chunk: &str) -> Option<String> {
    for line in chunk.split('\n') {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with("//") {
            continue;
        }
        let rest = trimmed.strip_prefix("export ").unwrap_or(trimmed);
        let rest = rest.strip_prefix("opaque ").unwrap_or(rest);
        let fields: Vec<&str> = rest.split_whitespace().collect();
        if fields.len() < 2 || !matches!(fields[0], "fn" | "type" | "enum" | "interface") {
            return None;
        }
        return fields[1]
            .split(['(', '[', ':'])
            .find(|s| !s.is_empty())
            .map(str::to_string);
    }
    None
}

#[cfg(test)]
mod continuation_tests {
    use super::*;

    #[test]
    fn blanking_preserves_byte_width_and_physical_line_breaks() {
        assert_eq!(blank(""), "");
        assert_eq!(blank("aé中🦀\t\0\r\nlast\r"), "            \r\n    \r");
        assert_eq!(blank("\n\r\n"), "\n\r\n");
    }

    #[test]
    fn indexed_prefixes_match_lexing_each_candidate_prefix() {
        let file: Arc<str> = Arc::from("recovery.ms");
        let bodies = [
            "1,\n2,\n3,\n",
            "(1),\n[2],\n{3},\n",
            "\"a ] # b\",\n# ignored )\n2,\n",
            "(\nfrom: Int,\n)\nnext(\n",
            "    1,\n2,\n    [3],\n",
            "1,\n]\n[\n2,\n",
            "1,\n@\n2,\n",
            "\"{value}\",\n2,\n",
        ];
        for ending in ["\n", "\r\n"] {
            for body in bodies {
                let source = ("let data = [\n".to_string() + body).replace('\n', ending);
                let lines: Vec<&str> = source.split_inclusive('\n').collect();
                let stop_at: Vec<bool> = lines
                    .iter()
                    .enumerate()
                    .map(|(index, line)| index > 0 && is_candidate_line(line))
                    .collect();
                let indexed = unterminated_prefixes(&file, &source, &stop_at);
                let mut offset = 0;
                for (index, line) in lines.iter().enumerate() {
                    if stop_at[index] {
                        let expected = matches!(lex(&file, &source[..offset]), Err(d) if d.message.starts_with("unterminated delimiter"));
                        assert_eq!(indexed[index], expected, "{source:?} at {offset}");
                        if !expected {
                            break;
                        }
                    }
                    offset += line.len();
                }
            }
        }
    }
}
