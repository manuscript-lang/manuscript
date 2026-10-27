//! Navigation over the occurrence index: hover, definition, type definition,
//! references and highlights.

use crate::analysis::{Analysis, Document};
use crate::index::{DeclFiles, OccInfo, Occurrence, callables, expr_text};
use crate::json::{Json, obj};
use crate::text::{self, Position, Range};
use ms_check::syntax::ModRef;
use ms_check::types::{Name, SymRef};
use ms_syntax::Pos;
use ms_syntax::ast::*;
use ms_syntax::visit::{self, Visitor};
use std::rc::Rc;

/// The occurrence covering a position, if the document is checked.
pub fn occurrence_at<'a>(
    analysis: &Analysis,
    d: &Document,
    p: Position,
    index: &'a [Occurrence],
) -> Option<&'a Occurrence> {
    let offset = text::offset(&d.text, p).ok()?;
    let file = analysis.module_file(d);
    index
        .iter()
        .find(|e| e.file.as_str() == file && offset >= e.offset && offset < e.end)
}

/// A name, member, literal or operator found by position.
pub struct Hit {
    /// Start byte.
    pub offset: usize,
    /// The written text.
    pub text: String,
    /// Checked facts.
    pub info: Rc<OccInfo>,
}

struct Finder<'a> {
    module: &'a ModRef,
    source: &'a str,
    p: Position,
    best: Option<Hit>,
}

impl Finder<'_> {
    fn consider(&mut self, e: &Expr) {
        let Some(text) = expr_text(e) else { return };
        let Some(info) = self.module.facts().info(e.id).cloned() else {
            return;
        };
        let offset = e.pos.offset as usize;
        let start = text::position(self.source, offset);
        let end = text::position(self.source, offset + text.len());
        let inside = self.p.line == start.line
            && self.p.character >= start.character
            && self.p.character < end.character;
        if inside && self.best.as_ref().is_none_or(|b| text.len() < b.text.len()) {
            self.best = Some(Hit {
                offset,
                text: text.to_string(),
                info: Rc::new(OccInfo::of(&info)),
            });
        }
    }

    fn path(&mut self, path: &Expr) {
        self.consider(path);
        match &path.kind {
            ExprKind::Member { left, .. } | ExprKind::Apply { left, .. } => self.path(left),
            _ => {}
        }
    }
}

impl Visitor for Finder<'_> {
    fn expr(&mut self, e: &Expr) {
        self.consider(e);
        if let ExprKind::Match { arms, .. } = &e.kind {
            for arm in arms {
                self.path(&arm.path);
            }
        }
    }
}

/// The index entry at a position, else the smallest checked expression there.
pub fn at(analysis: &Analysis, d: &Document, p: Position, index: &[Occurrence]) -> Option<Hit> {
    if let Some(entry) = occurrence_at(analysis, d, p, index) {
        return Some(Hit {
            offset: entry.offset,
            text: entry.name.clone(),
            info: entry.info.clone()?,
        });
    }
    let module = analysis.module(d)?;
    let mut finder = Finder {
        module: &module,
        source: &d.text,
        p,
        best: None,
    };
    for decl in &module.decls {
        visit::walk_decl(&mut finder, decl.decl());
    }
    finder.best
}

/// Which navigation request to answer.
#[derive(Copy, Clone, PartialEq, Eq)]
pub enum Navigate {
    /// `textDocument/hover`.
    Hover,
    /// `textDocument/definition`.
    Definition,
}

/// The location of an occurrence.
pub fn occurrence_location(analysis: &Analysis, entry: &Occurrence) -> Option<Json> {
    let module = analysis
        .source_modules()
        .into_iter()
        .find(|m| m.file == entry.file)?;
    Some(location(
        &analysis.source_uri(entry.file.as_str()),
        Range {
            start: text::position(&module.source, entry.offset),
            end: text::position(&module.source, entry.end),
        },
    ))
}

/// `{uri, range}`.
pub fn location(uri: &str, range: Range) -> Json {
    obj([("uri", uri.into()), ("range", range.json())])
}

/// Hover or definition at a position.
pub fn navigation(
    analysis: &Analysis,
    d: &Document,
    p: Position,
    method: Navigate,
    index: &[Occurrence],
) -> Json {
    let Some(hit) = at(analysis, d, p, index) else {
        return Json::Null;
    };
    let info = hit.info.clone();
    if method == Navigate::Hover {
        let Some(mut shown) = info.ty.clone() else {
            return Json::Null;
        };
        if let Some(symbol) = &info.symbol
            && symbol.is_constant()
            && symbol.ty_opt().is_some_and(|t| Rc::ptr_eq(&t, &shown))
            && let Some(value) = symbol.value_type()
        {
            shown = value;
        }
        let mut value = format!("```manuscript\n{}: {}\n```", hit.text, shown);
        let docs = hover_documentation(analysis, &info);
        if !docs.is_empty() {
            value.push_str("\n\n");
            value.push_str(&docs);
        }
        return obj([
            (
                "contents",
                obj([("kind", "markdown".into()), ("value", value.into())]),
            ),
            (
                "range",
                Range {
                    start: text::position(&d.text, hit.offset),
                    end: text::position(&d.text, hit.offset + hit.text.len()),
                }
                .json(),
            ),
        ]);
    }
    if let Some(selected) = occurrence_at(analysis, d, p, index) {
        for entry in index {
            if entry.key != selected.key || !entry.declaration {
                continue;
            }
            // Operation keys group a contract and all implementations for
            // rename. Definition lookup follows the checked concrete method.
            if let Some(method) = info.method.as_ref().filter(|m| !m.id.as_str().is_empty()) {
                let same = entry
                    .info
                    .as_ref()
                    .and_then(|i| i.method.as_ref())
                    .is_some_and(|m| m.id == method.id);
                if !same {
                    continue;
                }
            }
            return match occurrence_location(analysis, entry) {
                Some(l) => Json::Arr(vec![l]),
                None => Json::Arr(vec![Json::Null]),
            };
        }
    }
    let Some((file, pos)) = declaration(analysis, &info) else {
        return Json::Null;
    };
    declaration_location(analysis, file, pos)
}

/// `[{uri, range}]` at a declaration position, or `null` for an unknown module.
fn declaration_location(analysis: &Analysis, file: Name, pos: Pos) -> Json {
    for m in analysis.source_modules() {
        if m.file == file {
            let at = text::position(&m.source, pos.offset as usize);
            return Json::Arr(vec![location(
                &analysis.source_uri(file.as_str()),
                Range::at(at),
            )]);
        }
    }
    Json::Null
}

/// Where a symbol, method or implicit binding is declared.
pub fn declaration(analysis: &Analysis, info: &OccInfo) -> Option<(Name, Pos)> {
    let modules = analysis.source_modules();
    let files = DeclFiles::new(&modules);
    if let Some(symbol) = &info.symbol
        && let Some(decl) = &symbol.decl
    {
        return Some((symbol.module, decl.pos()));
    }
    if let Some(method) = &info.method
        && let Some(decl) = &method.decl
    {
        return Some((files.file(decl, method.module), decl.pos()));
    }
    let binding = info.binding.as_ref()?;
    let program = analysis.program.as_ref()?;
    for m in &modules {
        for d in &m.decls {
            for func in callables(d) {
                let facts = m.facts();
                let Some(decl_facts) = facts.decls.get(&func.id()) else {
                    continue;
                };
                if decl_facts
                    .fixture
                    .as_ref()
                    .is_some_and(|b| Rc::ptr_eq(b, binding))
                {
                    if let Some(fixture) = program.test_fixtures.get(&m.file)
                        && let Some(decl) = &fixture.factory.decl
                    {
                        return Some((fixture.factory.module, decl.pos()));
                    }
                    return Some((m.file, func.pos()));
                }
            }
        }
    }
    for m in &modules {
        for d in &m.decls {
            for func in callables(d) {
                let facts = m.facts();
                if facts
                    .decls
                    .get(&func.id())
                    .and_then(|f| f.self_binding.as_ref())
                    .is_some_and(|b| Rc::ptr_eq(b, binding))
                {
                    return Some((m.file, func.pos()));
                }
            }
        }
    }
    None
}

/// The `#` comment block directly above a declaration. The source remains the
/// single documentation authority for project modules and the immutable
/// standard-library documents alike.
pub fn declaration_documentation(analysis: &Analysis, file: Name, pos: Pos) -> String {
    let Some(module) = analysis
        .source_modules()
        .into_iter()
        .find(|m| m.file == file)
    else {
        return String::new();
    };
    let source = module.source.as_bytes();
    let offset = pos.offset as usize;
    if pos.line <= 1 || offset > source.len() {
        return String::new();
    }
    // Offsets are in the original source, including CRLF and recovered
    // declarations. Only inspect the immediately preceding line spans.
    let mut notes: Vec<String> = Vec::new();
    let mut end = source[..offset].iter().rposition(|&b| b == b'\n');
    while let Some(line_end) = end {
        let start = source[..line_end]
            .iter()
            .rposition(|&b| b == b'\n')
            .map_or(0, |at| at + 1);
        let line = String::from_utf8_lossy(&source[start..line_end]);
        let line = line.trim();
        let Some(note) = line.strip_prefix('#') else {
            break;
        };
        notes.push(note.trim().to_string());
        end = start.checked_sub(1);
    }
    notes.reverse();
    notes.join("\n").trim().to_string()
}

fn documentation_of(analysis: &Analysis, info: &OccInfo) -> String {
    let files = DeclFiles::new(&analysis.source_modules());
    let target = if let Some(method) = &info.method
        && let Some(decl) = &method.decl
    {
        Some((files.file(decl, method.module), decl.pos()))
    } else {
        info.symbol
            .as_ref()
            .and_then(|s| s.decl.as_ref().map(|d| (s.module, d.pos())))
    };
    match target {
        Some((file, pos)) => declaration_documentation(analysis, file, pos),
        None => String::new(),
    }
}

/// Documentation shown on hover: the declaration's own, else its receiver's.
pub fn hover_documentation(analysis: &Analysis, info: &OccInfo) -> String {
    let docs = documentation_of(analysis, info);
    if !docs.is_empty() {
        return docs;
    }
    let Some(method) = &info.method else {
        return String::new();
    };
    for receiver in [Some(&method.receiver), method.contract.as_ref()]
        .into_iter()
        .flatten()
    {
        if let Some(symbol) = receiver.symbol()
            && let Some(decl) = &symbol.decl
        {
            let docs = declaration_documentation(analysis, symbol.module, decl.pos());
            if !docs.is_empty() {
                return docs;
            }
        }
    }
    String::new()
}

/// Documentation of a declaration as an LSP markup value, or `null`.
pub fn description(analysis: &Analysis, file: Name, pos: Pos) -> Json {
    let notes = declaration_documentation(analysis, file, pos);
    if notes.is_empty() {
        Json::Null
    } else {
        obj([("kind", "markdown".into()), ("value", notes.into())])
    }
}

/// The location of a symbol's declaration, as a one-element list.
pub fn symbol_location(analysis: &Analysis, symbol: &SymRef) -> Json {
    match &symbol.decl {
        Some(decl) => declaration_location(analysis, symbol.module, decl.pos()),
        None => Json::Null,
    }
}

/// Where the type of the expression at a position is declared.
pub fn type_definition(
    analysis: &Analysis,
    d: &Document,
    p: Position,
    index: &[Occurrence],
) -> Json {
    let Some(hit) = at(analysis, d, p, index) else {
        return Json::Null;
    };
    match hit.info.ty.as_ref().and_then(|t| t.symbol()) {
        Some(symbol) => {
            // Point at the declared name, as definition does, not at the declaration keyword.
            let key = crate::index::symbol_key(Some(&symbol));
            let name = index.iter().find(|e| e.declaration && e.key == key);
            match name.and_then(|e| occurrence_location(analysis, e)) {
                Some(found) => Json::Arr(vec![found]),
                None => symbol_location(analysis, &symbol),
            }
        }
        None => Json::Null,
    }
}

/// Every occurrence of the identity at a position within this analysis.
pub fn references_with_index(
    analysis: &Analysis,
    index: &[Occurrence],
    d: &Document,
    p: Position,
    include: bool,
) -> Vec<Json> {
    let Some(selected) = occurrence_at(analysis, d, p, index) else {
        return Vec::new();
    };
    index
        .iter()
        .filter(|e| e.key == selected.key && (include || !e.declaration))
        .filter_map(|e| occurrence_location(analysis, e))
        .collect()
}

/// Go prints a location map as `map[range:{{a b} {c d}} uri:u]`; results
/// are ordered by that text, which this reproduces.
pub fn go_location_order(location: &Json) -> String {
    let number = |j: Option<&Json>| j.and_then(|j| j.as_i64()).unwrap_or(0);
    let range = location.get("range");
    let side = |name: &str| {
        let s = range.and_then(|r| r.get(name));
        format!(
            "{{{} {}}}",
            number(s.and_then(|s| s.get("line"))),
            number(s.and_then(|s| s.get("character")))
        )
    };
    format!(
        "map[range:{{{} {}}} uri:{}]",
        side("start"),
        side("end"),
        location.get("uri").and_then(|u| u.as_str()).unwrap_or("")
    )
}
