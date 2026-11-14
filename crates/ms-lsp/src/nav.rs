//! Navigation over the occurrence index: hover, definition, type definition,
//! references and highlights.

use crate::analysis::{Analysis, Document};
use crate::index::{DeclFiles, OccInfo, Occurrence, callables, expr_text, hidden_structure};
use crate::json::{Json, obj};
use crate::text::{self, Position, Range};
use ms_check::api::syntax::ModRef;
use ms_check::api::types::{Name, SymRef};
use ms_check::fxmap::HashMap;
use ms_syntax::Pos;
use ms_syntax::ast::*;
use ms_syntax::visit::{self, Visitor};
use std::cell::OnceCell;
use std::rc::Rc;

/// The occurrence covering a position, if the document is checked.
pub fn occurrence_at<'a>(
    syms: ms_syntax::Names,
    analysis: &Analysis,
    d: &Document,
    p: Position,
    index: &'a [Occurrence],
) -> Option<&'a Occurrence> {
    let offset = text::offset(&d.text, p).ok()?;
    let file = analysis.module_file(syms, d);
    index
        .iter()
        .find(|e| syms.str(e.file) == file && offset >= e.offset && offset < e.end)
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
    syms: ms_syntax::Names,
    module: &'a ModRef,
    source: &'a str,
    cursor: Result<usize, Position>,
    best: Option<Hit>,
    hidden: HashMap<NodeId, bool>,
    /// Line index and cursor position for the mismatched-snapshot fallback, built on first use
    /// so each expression costs a lookup instead of a scan of the source prefix.
    lines: OnceCell<(text::SourcePositions<'a>, Position)>,
}

impl Finder<'_> {
    fn consider(&mut self, syms: ms_syntax::Names, e: &Expr) {
        let Some(text) = expr_text(syms, e) else {
            return;
        };
        let Some(info) = self.module.facts().info(e.id).cloned() else {
            return;
        };
        if hidden_structure(self.module, e, &info, &mut self.hidden) {
            return;
        }
        let offset = e.pos.offset as usize;
        let end = offset + text.len();
        let inside = if let Ok(cursor) = self.cursor
            && self.source.get(offset..end) == Some(text)
            && !text.contains('\n')
        {
            cursor >= offset && cursor < end
        } else {
            // Invalid positions and mismatched/recovered snapshots retain the
            // original clamped UTF-16 comparison.
            let (lines, p) = self.lines.get_or_init(|| {
                let lines = text::SourcePositions::new(self.source);
                let p = self.cursor.map_or_else(|p| p, |at| lines.position(at));
                (lines, p)
            });
            let (start, end) = (lines.position(offset), lines.position(end));
            p.line == start.line && p.character >= start.character && p.character < end.character
        };
        if inside && self.best.as_ref().is_none_or(|b| text.len() < b.text.len()) {
            self.best = Some(Hit {
                offset,
                text: text.to_string(),
                info: Rc::new(OccInfo::of(&info)),
            });
        }
    }

    fn path(&mut self, syms: ms_syntax::Names, path: &Expr) {
        self.consider(syms, path);
        match &path.kind {
            ExprKind::Member { left, .. } | ExprKind::Apply { left, .. } => self.path(syms, left),
            _ => {}
        }
    }
}

impl Visitor for Finder<'_> {
    fn expr(&mut self, e: &Expr) {
        let syms = self.syms;
        self.consider(syms, e);
        if let ExprKind::Match { arms, .. } = &e.kind {
            for arm in arms {
                self.path(syms, &arm.path);
            }
        }
    }
}

/// The index entry at a position, else the smallest checked expression there.
pub fn at(
    syms: ms_syntax::Names,
    analysis: &Analysis,
    d: &Document,
    p: Position,
    index: &[Occurrence],
) -> Option<Hit> {
    if let Some(entry) = occurrence_at(syms, analysis, d, p, index) {
        return Some(Hit {
            offset: entry.offset,
            text: entry.name.clone(),
            info: entry.info.clone()?,
        });
    }
    let module = analysis.module(syms, d)?;
    let mut finder = Finder {
        syms,
        module: &module,
        source: &d.text,
        cursor: text::offset(&d.text, p).map_err(|_| p),
        best: None,
        hidden: HashMap::default(),
        lines: OnceCell::new(),
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
pub fn occurrence_location(
    syms: ms_syntax::Names,
    analysis: &Analysis,
    entry: &Occurrence,
) -> Option<Json> {
    let module = analysis
        .source_modules(syms)
        .into_iter()
        .find(|m| m.file == entry.file)?;
    Some(location(
        &analysis.source_uri(syms.str(entry.file)),
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

/// The effects line hover shows for a project or standard function: the declared effects it
/// reaches, what it is permitted to reach, or that it is pure in the ambient sense.
fn effects_line(
    syms: ms_syntax::Names,
    analysis: &Analysis,
    info: &OccInfo,
    shown: &str,
) -> Option<String> {
    if !shown.starts_with("fn(") {
        return None;
    }
    let program = analysis.program.as_ref()?;
    let id = match (&info.method, &info.symbol) {
        (Some(m), _) if !syms.str(m.id).is_empty() => m.id,
        (_, Some(s)) if s.native == ms_check::api::types::Native::Source => s.id,
        _ => return None,
    };
    let reach = program
        .declared_effects
        .get(&id)
        .cloned()
        .unwrap_or_default();
    let permits = program.effect_permits.get(&id).cloned().unwrap_or_default();
    let mut parts = vec![if reach.is_empty() {
        "effects: pure (ambient authority only)".to_string()
    } else {
        format!("effects: {}", reach.join(", "))
    }];
    if !permits.is_empty() {
        parts.push(format!("permits: {}", permits.join(", ")));
    }
    Some(parts.join("  \n"))
}

/// The type hover shows for an occurrence, or `None` when its type did not resolve.
pub fn hover_type(syms: ms_syntax::Names, info: &OccInfo) -> Option<String> {
    let mut shown = info.ty.clone()?;
    if let Some(symbol) = &info.symbol
        && symbol.is_constant()
        && symbol.ty_opt().is_some_and(|t| Rc::ptr_eq(&t, &shown))
        && let Some(value) = symbol.value_type()
    {
        shown = value;
    }
    (!ms_check::api::types::invalid_ty(&shown)).then(|| shown.display(syms).to_string())
}

/// The checked type of every identifier in the project's own modules, for the html map.
pub fn type_hints(syms: ms_syntax::Names, analysis: &Analysis) -> Vec<ms_tooling::html::TypeHint> {
    let modules: HashMap<Name, ModRef> = analysis
        .source_modules(syms)
        .into_iter()
        .filter(|m| !syms.str(m.file).starts_with("@std/"))
        .map(|m| (m.file, m))
        .collect();
    let mut hints = Vec::new();
    for entry in analysis.occurrence_index(syms) {
        let (Some(module), Some(info)) = (modules.get(&entry.file), &entry.info) else {
            continue;
        };
        let Some(ty) = hover_type(syms, info) else {
            continue;
        };
        let at = text::position(&module.source, entry.offset);
        hints.push(ms_tooling::html::TypeHint {
            file: syms.str(entry.file).to_string(),
            line: at.line,
            col: at.character,
            len: text::utf16_length(
                &module.source.as_bytes()[entry.offset..entry.end.min(module.source.len())],
            ),
            ty,
        });
    }
    hints
}

/// Hover or definition at a position.
pub fn navigation(
    syms: ms_syntax::Names,
    analysis: &Analysis,
    d: &Document,
    p: Position,
    method: Navigate,
    index: &[Occurrence],
) -> Json {
    let Some(hit) = at(syms, analysis, d, p, index) else {
        return Json::Null;
    };
    let info = hit.info.clone();
    if method == Navigate::Hover {
        let Some(shown) = hover_type(syms, &info) else {
            return Json::Null;
        };
        let mut value = format!("```manuscript\n{}: {}\n```", hit.text, shown);
        if let Some(line) = effects_line(syms, analysis, &info, &shown) {
            value.push_str("\n\n");
            value.push_str(&line);
        }
        let docs = hover_documentation(syms, analysis, &info);
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
    if let Some(selected) = occurrence_at(syms, analysis, d, p, index) {
        for entry in index {
            if entry.key != selected.key || !entry.declaration {
                continue;
            }
            // Operation keys group a contract and all implementations for
            // rename. Definition lookup follows the checked concrete method.
            if let Some(method) = info.method.as_ref().filter(|m| !syms.str(m.id).is_empty()) {
                let same = entry
                    .info
                    .as_ref()
                    .and_then(|i| i.method.as_ref())
                    .is_some_and(|m| m.id == method.id);
                if !same {
                    continue;
                }
            }
            return match occurrence_location(syms, analysis, entry) {
                Some(l) => Json::Arr(vec![l]),
                None => Json::Arr(vec![Json::Null]),
            };
        }
    }
    let Some((file, pos)) = declaration(syms, analysis, &info) else {
        return Json::Null;
    };
    declaration_location(syms, analysis, file, pos)
}

/// `[{uri, range}]` at a declaration position, or `null` for an unknown module.
fn declaration_location(syms: ms_syntax::Names, analysis: &Analysis, file: Name, pos: Pos) -> Json {
    for m in analysis.source_modules(syms) {
        if m.file == file {
            let at = text::position(&m.source, pos.offset as usize);
            return Json::Arr(vec![location(
                &analysis.source_uri(syms.str(file)),
                Range::at(at),
            )]);
        }
    }
    Json::Null
}

/// Where a symbol, method or implicit binding is declared.
pub fn declaration(
    syms: ms_syntax::Names,
    analysis: &Analysis,
    info: &OccInfo,
) -> Option<(Name, Pos)> {
    let modules = analysis.source_modules(syms);
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

/// The comment block directly above a declaration, or its trailing `//` comment. The source remains the
/// single documentation authority for project modules and the immutable
/// standard-library documents alike.
pub fn declaration_documentation(
    syms: ms_syntax::Names,
    analysis: &Analysis,
    file: Name,
    pos: Pos,
) -> String {
    declaration_documentation_in(&analysis.source_modules(syms), file, pos)
}

/// [`declaration_documentation`] over modules the caller already listed, for a caller that asks
/// about many declarations.
pub fn declaration_documentation_in(modules: &[ModRef], file: Name, pos: Pos) -> String {
    let Some(module) = modules.iter().find(|m| m.file == file) else {
        return String::new();
    };
    let source = module.source.as_ref();
    let offset = pos.offset as usize;
    if pos.line <= 1 || offset > source.len() || !source.is_char_boundary(offset) {
        return String::new();
    }
    // Offsets are in the original source, including CRLF and recovered
    // declarations. Only the immediately preceding line spans are inspected.
    let line_start = source[..offset].rfind('\n').map_or(0, |at| at + 1);
    let above = ms_syntax::doc::comments_above(source, line_start, None);
    let docs = if above.is_empty() {
        ms_syntax::doc::trailing_comment(source, offset)
    } else {
        above
    };
    docs.trim().to_string()
}

fn documentation_of(syms: ms_syntax::Names, analysis: &Analysis, info: &OccInfo) -> String {
    let target = if let Some(method) = &info.method
        && let Some(decl) = &method.decl
    {
        let files = DeclFiles::new(&analysis.source_modules(syms));
        Some((files.file(decl, method.module), decl.pos()))
    } else {
        info.symbol
            .as_ref()
            .and_then(|s| s.decl.as_ref().map(|d| (s.module, d.pos())))
    };
    match target {
        Some((file, pos)) => declaration_documentation(syms, analysis, file, pos),
        None => String::new(),
    }
}

/// Documentation shown on hover: the declaration's own, else its receiver's.
pub fn hover_documentation(syms: ms_syntax::Names, analysis: &Analysis, info: &OccInfo) -> String {
    let docs = documentation_of(syms, analysis, info);
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
            let docs = declaration_documentation(syms, analysis, symbol.module, decl.pos());
            if !docs.is_empty() {
                return docs;
            }
        }
    }
    String::new()
}

/// Documentation of a declaration as an LSP markup value, or `null`.
pub fn description(syms: ms_syntax::Names, analysis: &Analysis, file: Name, pos: Pos) -> Json {
    description_in(&analysis.source_modules(syms), file, pos)
}

/// [`description`] over modules the caller already listed.
pub fn description_in(modules: &[ModRef], file: Name, pos: Pos) -> Json {
    let notes = declaration_documentation_in(modules, file, pos);
    if notes.is_empty() {
        Json::Null
    } else {
        obj([("kind", "markdown".into()), ("value", notes.into())])
    }
}

/// The location of a symbol's declaration, as a one-element list.
pub fn symbol_location(syms: ms_syntax::Names, analysis: &Analysis, symbol: &SymRef) -> Json {
    match &symbol.decl {
        Some(decl) => declaration_location(syms, analysis, symbol.module, decl.pos()),
        None => Json::Null,
    }
}

/// Where the type of the expression at a position is declared.
pub fn type_definition(
    syms: ms_syntax::Names,
    analysis: &Analysis,
    d: &Document,
    p: Position,
    index: &[Occurrence],
) -> Json {
    let Some(hit) = at(syms, analysis, d, p, index) else {
        return Json::Null;
    };
    match hit.info.ty.as_ref().and_then(|t| t.symbol()) {
        Some(symbol) => {
            // Point at the declared name, as definition does, not at the declaration keyword.
            let key = crate::index::symbol_key(syms, &analysis.module_path(""), Some(&symbol));
            let name = index.iter().find(|e| e.declaration && e.key == key);
            match name.and_then(|e| occurrence_location(syms, analysis, e)) {
                Some(found) => Json::Arr(vec![found]),
                None => symbol_location(syms, analysis, &symbol),
            }
        }
        None => Json::Null,
    }
}

/// Every occurrence of the identity at a position within this analysis.
pub fn references_with_index(
    syms: ms_syntax::Names,
    analysis: &Analysis,
    index: &[Occurrence],
    d: &Document,
    p: Position,
    include: bool,
) -> Vec<Json> {
    let Some(selected) = occurrence_at(syms, analysis, d, p, index) else {
        return Vec::new();
    };
    let entries: Vec<_> = index
        .iter()
        .filter(|e| e.key == selected.key && (include || !e.declaration))
        .collect();
    if entries.is_empty() {
        return Vec::new();
    }
    let modules = analysis.source_modules(syms);
    let mut locations = Vec::with_capacity(entries.len());
    for entries in entries.chunk_by(|a, b| a.file == b.file) {
        let file = entries[0].file;
        let Some(module) = modules.iter().find(|m| m.file == file) else {
            continue;
        };
        // Index only the prefix needed by these locations. A reference near the
        // start of a large file should not scan the unrelated remainder.
        let end = entries
            .iter()
            .map(|e| e.offset.max(e.end))
            .max()
            .unwrap_or(0);
        let source = module.source.get(..end).unwrap_or(&module.source);
        let positions = text::SourcePositions::new(source);
        let source_uri = analysis.source_uri(syms.str(file));
        locations.extend(
            entries
                .iter()
                .map(|entry| location(&source_uri, positions.range(entry.offset, entry.end))),
        );
    }
    locations
}

/// Orders locations by range (start line and character, then end), then URI.
pub type LocationKey = (i64, i64, i64, i64, String);

/// The sort and de-duplication key of a location.
pub fn location_sort_key(location: &Json) -> LocationKey {
    let number = |j: Option<&Json>| j.and_then(|j| j.as_i64()).unwrap_or(0);
    let range = location.get("range");
    let side = |name: &str| {
        let s = range.and_then(|r| r.get(name));
        (
            number(s.and_then(|s| s.get("line"))),
            number(s.and_then(|s| s.get("character"))),
        )
    };
    let (start, end) = (side("start"), side("end"));
    let uri = location.get("uri").and_then(|u| u.as_str()).unwrap_or("");
    (start.0, start.1, end.0, end.1, uri.to_string())
}
