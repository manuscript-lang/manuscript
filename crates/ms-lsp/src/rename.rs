//! `textDocument/prepareRename` and `textDocument/rename`.
//!
//! Every rename is validated by re-checking the affected workspace with the
//! edits applied; nothing is proposed that would not check.

use crate::analysis::{Analysis, Document, Documents, workspace_analysis};
use crate::index::Occurrence;
use crate::json::{Json, obj};
use crate::nav::occurrence_at;
use crate::text::{self, Position, Range};
use crate::uri;
use crate::workspace::{CancelCheck, ScanError, workspace_documents};
use ms_syntax::token::Tok;
use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;

const CANCELED: &str = "context canceled";

fn canceled(check: Option<CancelCheck>) -> Result<(), String> {
    match check {
        Some(f) if f() => Err(CANCELED.to_string()),
        _ => Ok(()),
    }
}

struct Replacement {
    start: usize,
    end: usize,
}

/// The rename edit for the identity at `p`, the prepare answer when `name` is
/// empty, or the reason the rename is refused.
pub fn rename(
    analysis: &Analysis,
    index: &[Occurrence],
    d: &Document,
    p: Position,
    name: &str,
    cancel: Option<CancelCheck>,
    open: Option<&Documents>,
) -> Result<Json, String> {
    canceled(cancel)?;
    let Some(selected) = occurrence_at(analysis, d, p, index) else {
        return Err("select a name that refers to a source declaration".to_string());
    };
    if selected.key.contains(":@std/") {
        return Err("standard-library declarations are read-only".to_string());
    }
    let mut docs: Documents = match open {
        Some(open) => open.clone(),
        None => Documents::new(),
    };
    docs.insert(d.uri.clone(), d.clone());
    let targets: Vec<Document> = if selected.key.starts_with("binding:") {
        vec![d.clone()]
    } else {
        workspace_documents(d, &docs, false, cancel).map_err(|e| match e {
            ScanError::Canceled => CANCELED.to_string(),
            ScanError::Io(e) => e.to_string(),
        })?
    };
    let mut by_uri: BTreeMap<String, Vec<Replacement>> = BTreeMap::new();
    let mut content: HashMap<String, Document> = HashMap::new();
    let mut has_declaration = false;
    for target in &targets {
        canceled(cancel)?;
        let other;
        let (checked, entries): (&Analysis, &[Occurrence]) = if target.uri == d.uri {
            (analysis, index)
        } else {
            other = workspace_analysis(target, &docs);
            canceled(cancel)?;
            (&other, other.index())
        };
        canceled(cancel)?;
        let Some(program) = &checked.program else {
            continue;
        };
        for entry in entries {
            if entry.key != selected.key {
                continue;
            }
            has_declaration |= entry.declaration;
            let path = checked.module_path(entry.file.as_str());
            let file_uri = open_uri(&docs, &path);
            if !content.contains_key(&file_uri) {
                let mut file = Document::new(file_uri.clone(), String::new());
                if let Some(m) = program.modules.iter().find(|m| m.file == entry.file) {
                    file = Document::new(file_uri.clone(), m.source.to_string());
                }
                if let Some(actual) = docs.get(&file_uri) {
                    file = actual.clone();
                }
                content.insert(file_uri.clone(), file);
            }
            let edits = by_uri.entry(file_uri).or_default();
            if !edits.iter().any(|e| e.start == entry.offset) {
                edits.push(Replacement {
                    start: entry.offset,
                    end: entry.end,
                });
            }
        }
    }
    if !has_declaration {
        return Err("declaration is external or has no editable source".to_string());
    }
    if name.is_empty() {
        let range = Range {
            start: text::position(&d.text, selected.offset),
            end: text::position(&d.text, selected.end),
        };
        return Ok(obj([
            ("range", range.json()),
            ("placeholder", selected.name.clone().into()),
        ]));
    }
    if !is_identifier(name) {
        return Err("new name must be a Manuscript identifier".to_string());
    }
    if name == selected.name {
        return Ok(obj([("documentChanges", Json::Arr(Vec::new()))]));
    }
    let (modified, changes) = rename_changes(&docs, &content, by_uri, name, cancel)?;
    validate_rename(&targets, &docs, &modified, cancel)?;
    Ok(obj([("documentChanges", Json::Arr(changes))]))
}

/// The URI an editor opened `path` under, so one file keeps one snapshot and
/// version however its URI is spelled (symlink, percent-encoding); the
/// canonical URI when it is not open.
fn open_uri(docs: &Documents, path: &str) -> String {
    let canonical = uri::file_uri(path);
    if docs.contains_key(&canonical) {
        return canonical;
    }
    let resolve = |p: &str| ms_driver::project::pathops::eval_symlinks(p).unwrap_or(p.to_string());
    let wanted = resolve(path);
    let mut matches: Vec<&String> = docs
        .values()
        .filter(|open| !uri::is_standard_library(&open.uri) && resolve(&open.path()) == wanted)
        .map(|open| &open.uri)
        .collect();
    matches.sort();
    matches.first().map_or(canonical, |u| (*u).clone())
}

fn is_identifier(name: &str) -> bool {
    let file: Arc<str> = "rename".into();
    let Ok(lexed) = ms_syntax::lexer::lex(&file, name) else {
        return false;
    };
    lexed
        .tokens
        .first()
        .is_some_and(|t| t.kind == Tok::Name && &lexed.source[t.lo as usize..t.hi as usize] == name)
}

/// One versioned edit per source file, stopping at each file boundary. Partial
/// edits and modified overlays never escape a canceled phase.
fn rename_changes(
    docs: &Documents,
    content: &HashMap<String, Document>,
    by_uri: BTreeMap<String, Vec<Replacement>>,
    name: &str,
    cancel: Option<CancelCheck>,
) -> Result<(Documents, Vec<Json>), String> {
    let mut modified = docs.clone();
    let mut changes = Vec::new();
    for (file_uri, mut edits) in by_uri {
        canceled(cancel)?;
        let file = &content[&file_uri];
        let filename: Arc<str> = uri::filename(&file_uri).into();
        let lexed = ms_syntax::lexer::lex(&filename, &file.text).map_err(|e| e.message.clone())?;
        for token in &lexed.tokens {
            if token.kind == Tok::Name
                && &lexed.source[token.lo as usize..token.hi as usize] == name
            {
                return Err(format!(
                    "{name} already occurs in {}; rename could capture another binding",
                    uri::filename(&file_uri)
                ));
            }
        }
        edits.sort_by_key(|e| std::cmp::Reverse(e.start));
        let positions = text::SourcePositions::new(&file.text);
        let mut lsp_edits = Vec::new();
        let mut updated = file.clone();
        for edit in &edits {
            if edit.end > updated.text.len() {
                return Err("source revision changed".to_string());
            }
            lsp_edits.push(obj([
                ("range", positions.range(edit.start, edit.end).json()),
                ("newText", name.into()),
            ]));
            updated.text.replace_range(edit.start..edit.end, name);
        }
        modified.insert(file_uri.clone(), updated);
        let version = match docs.get(&file_uri) {
            Some(opened) => opened.version.into(),
            None => Json::Null,
        };
        changes.push(obj([
            (
                "textDocument",
                obj([("uri", file_uri.clone().into()), ("version", version)]),
            ),
            ("edits", Json::Arr(lsp_edits)),
        ]));
    }
    Ok((modified, changes))
}

/// Validates the complete affected workspace before proposing any edit.
/// Signature labels, imports, constructors and type annotations participate in
/// the same index, so a rename cannot quietly break another module's contract.
fn validate_rename(
    targets: &[Document],
    docs: &Documents,
    modified: &Documents,
    cancel: Option<CancelCheck>,
) -> Result<(), String> {
    for target in targets {
        canceled(cancel)?;
        let before = workspace_analysis(target, docs);
        canceled(cancel)?;
        if !before.success() {
            return Err(format!(
                "rename requires a clean workspace: {}",
                uri::filename(&target.uri)
            ));
        }
        let updated = modified.get(&target.uri).unwrap_or(target);
        let after = workspace_analysis(updated, modified);
        canceled(cancel)?;
        if !after.success() {
            let message = after
                .diagnostics
                .first()
                .map_or("unknown checking failure".to_string(), |d| {
                    d.message.clone()
                });
            return Err(format!(
                "rename would break {}: {message}",
                uri::filename(&target.uri)
            ));
        }
    }
    Ok(())
}
