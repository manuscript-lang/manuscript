//! `textDocument/documentSymbol`: the outline of a checked module.

use crate::analysis::{Analysis, Document};
use crate::json::{Json, obj};
use crate::text::{Range, SourcePositions};
use ms_check::api::syntax::DeclRef;
use ms_syntax::ast::*;

const FUNCTION: i64 = 12;
const CONSTANT: i64 = 14;
const CLASS: i64 = 5;
const ENUM: i64 = 10;
const INTERFACE: i64 = 11;
const METHOD: i64 = 6;
const FIELD: i64 = 8;
const ENUM_MEMBER: i64 = 22;

struct Outline<'a> {
    analysis: &'a Analysis,
    d: &'a Document,
    file: ms_check::api::types::Name,
    positions: SourcePositions<'a>,
}

impl Outline<'_> {
    /// The range of `name` on the declaration's line, else an empty range.
    fn selection(&self, offset: usize, name: &str) -> Range {
        if let Some(at) = crate::text::header(&self.d.text, offset, name) {
            return self.positions.range(at, at + name.len());
        }
        Range::at(self.positions.position(offset))
    }

    /// End of the block that precedes `next`, without trailing blank space.
    fn block_end(&self, next: usize) -> usize {
        let text = self.d.text.as_bytes();
        let mut next = next.min(text.len());
        if next < text.len() {
            next = text[..next]
                .iter()
                .rposition(|&b| b == b'\n')
                .map_or(0, |at| at + 1);
        }
        text[..next]
            .iter()
            .rposition(|b| !matches!(b, b' ' | b'\t' | b'\r' | b'\n'))
            .map_or(0, |at| at + 1)
    }

    fn declaration(&self, syms: ms_syntax::Names, d: &DeclRef, end: usize) -> Json {
        let decl = d.decl();
        let mut name = syms.str(d.name()).to_string();
        let mut kind = FUNCTION;
        let mut detail = String::new();
        if let Some(symbol) = self.symbol(d) {
            detail = symbol
                .value_type()
                .map(|t| t.display(syms).to_string())
                .unwrap_or_default();
            if symbol.is_constant() {
                kind = CONSTANT;
            }
        }
        let mut selection_name = name.clone();
        match &decl.kind {
            DeclKind::Type(_) => kind = CLASS,
            DeclKind::Alternative(_) => kind = ENUM,
            DeclKind::Alias(_) => kind = CLASS,
            DeclKind::Interface(_) => kind = INTERFACE,
            DeclKind::Impl(i) => {
                kind = CLASS;
                name = i.display_name(syms, decl.synthetic);
                selection_name = String::new();
            }
            DeclKind::Test(t) => {
                name = format!("{} {}", if t.bench { "bench" } else { "test" }, t.name);
                selection_name = String::new();
            }
            _ => {}
        }
        let mut children: Vec<Json> = Vec::new();
        for field in d.type_fields() {
            let r = self.selection(field.pos.offset as usize, syms.str(field.name));
            let start = field.pos.offset as usize;
            let rest = &self.d.text.as_bytes()[start.min(self.d.text.len())..];
            let line_end = rest.iter().position(|&b| b == b'\n').unwrap_or(rest.len());
            let line = &rest[..line_end];
            let line = line.strip_suffix(b"\r").unwrap_or(line);
            let line = String::from_utf8_lossy(line);
            let line = line.trim_end_matches(['\r']);
            children.push(obj([
                ("name", syms.str(field.name).into()),
                ("kind", FIELD.into()),
                (
                    "range",
                    Range {
                        start: r.start,
                        end: self.positions.position(start + line.len()),
                    }
                    .json(),
                ),
                ("selectionRange", r.json()),
            ]));
        }
        for case in d.cases() {
            let r = self.selection(case.pos.offset as usize, syms.str(case.name));
            children.push(obj([
                ("name", syms.str(case.name).into()),
                ("kind", ENUM_MEMBER.into()),
                ("range", r.json()),
                ("selectionRange", r.json()),
            ]));
        }
        let methods = d.methods();
        for (i, method) in methods.iter().enumerate() {
            let method_end = match methods.get(i + 1) {
                Some(next) => self.block_end(next.pos.offset as usize),
                None => end,
            };
            children.push(self.method(syms, method, method_end));
        }
        let mut value = obj([
            ("name", name.into()),
            ("detail", detail.into()),
            ("kind", kind.into()),
            (
                "range",
                self.positions.range(d.pos().offset as usize, end).json(),
            ),
            (
                "selectionRange",
                self.selection(d.pos().offset as usize, &selection_name)
                    .json(),
            ),
        ]);
        if !children.is_empty() {
            value.set("children", Json::Arr(children));
        }
        value
    }

    fn method(&self, syms: ms_syntax::Names, method: &Method, end: usize) -> Json {
        let name = syms.str(method.func.name);
        let offset = method.pos.offset as usize;
        obj([
            ("name", name.into()),
            ("detail", "".into()),
            ("kind", METHOD.into()),
            (
                "range",
                self.positions.range(offset, end.max(offset)).json(),
            ),
            ("selectionRange", self.selection(offset, name).json()),
        ])
    }

    /// The module symbol a declaration introduced, if it is this declaration.
    fn symbol(&self, d: &DeclRef) -> Option<ms_check::api::types::SymRef> {
        let names = self.analysis.program.as_ref()?.symbols.get(&self.file)?;
        let symbol = names.borrow().get(&d.name())?.clone();
        symbol
            .decl
            .as_ref()
            .is_some_and(|sd| sd.same(d))
            .then_some(symbol)
    }
}

/// The hierarchical outline of a document, or `[]` when it is not checked.
pub fn document_symbols(syms: ms_syntax::Names, analysis: &Analysis, d: &Document) -> Json {
    let Some(module) = analysis.module(syms, d) else {
        return Json::Arr(Vec::new());
    };
    let outline = Outline {
        analysis,
        d,
        file: module.file,
        positions: SourcePositions::new(&d.text),
    };
    let declarations = &module.decls;
    let mut out = Vec::new();
    for (i, decl) in declarations.iter().enumerate() {
        if decl.0.decl.synthetic && matches!(decl.decl().kind, DeclKind::Interface(_)) {
            continue;
        }
        // Select the boundary before scanning a potentially large EOF suffix.
        let next = declarations
            .get(i + 1)
            .map_or(d.text.len(), |next| next.pos().offset as usize);
        let end = outline.block_end(next).max(decl.pos().offset as usize);
        out.push(outline.declaration(syms, decl, end));
    }
    Json::Arr(out)
}
