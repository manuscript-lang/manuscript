//! Unused imports (`MSL102`) and unreachable statements (`MSL103`). Unread bindings
//! are check errors.

use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::types::n;
use ms_check::{ModuleData, Program};
use ms_syntax::ast::*;
use ms_syntax::visit::Visitor;
use ms_syntax::{DiagnosticFix, Pos};
use std::collections::HashSet;

pub(super) fn lint(program: &Program, module: &ModuleData, findings: &mut Vec<Finding>) {
    let file = module_file(module);
    let mut scan = Scan {
        module,
        file: &file,
        findings,
    };
    walk_module(module, &mut scan);

    let facts = module.facts();
    let mut used = HashSet::new();
    for info in facts.exprs.iter().flatten() {
        if let Some(symbol) = &info.symbol {
            used.insert(symbol.key());
        }
    }
    // Collection literals require canonical imports even without written types.
    let symbols = program.symbols.get(&module.file);
    let symbol_of =
        |name: &str| symbols.and_then(|names| names.borrow().get(&n(name)).map(|s| s.key()));
    let mut literals = Literals::default();
    walk_module(module, &mut literals);
    if literals.list {
        used.extend(symbol_of("List"));
    }
    if literals.map {
        used.extend(symbol_of("Map"));
    }
    for ty in facts.type_refs.values() {
        if let Some(symbol) = ty.def.as_ref().and_then(|d| d.symbol()) {
            used.insert(symbol.key());
        }
    }
    let unused = |import: &Import| {
        let key = symbol_of(import.name.as_str());
        !key.is_some_and(|k| used.contains(&k))
    };
    for import in &module.imports {
        if unused(import) {
            let siblings = module.imports.iter().filter(|i| i.pos == import.pos);
            let whole = siblings.clone().all(unused);
            let mut found = finding(
                "MSL102",
                format!("Import {} is never used", import.name.as_str()),
                &file,
                import.name_pos,
            );
            found.fix = if whole {
                statement_removal(&module.source, import)
            } else {
                name_removal(&module.source, import)
            };
            findings.push(found);
        }
    }
}

/// The position of byte `offset` in `source`.
fn pos_at(source: &str, offset: usize) -> Pos {
    let before = &source[..offset];
    let line = before.matches('\n').count() + 1;
    let column = offset - before.rfind('\n').map_or(0, |i| i + 1) + 1;
    Pos {
        offset: offset as u32,
        line: line as u32,
        column: column as u32,
    }
}

fn fix_of(source: &str, start: usize, end: usize) -> Option<DiagnosticFix> {
    Some(DiagnosticFix {
        pos: pos_at(source, start),
        end: pos_at(source, end),
        replacement: String::new(),
    })
}

/// Deletes the whole `import ... from "path"` statement, with its line breaks.
fn statement_removal(source: &str, import: &Import) -> Option<DiagnosticFix> {
    let start = import.pos.offset as usize;
    let quote = start + source.get(start..)?.find('"')?;
    let close = quote + 1 + source.get(quote + 1..)?.find('"')?;
    let line_end = source[close..]
        .find('\n')
        .map_or(source.len(), |i| close + i + 1);
    let line_start = source[..start].rfind('\n').map_or(0, |i| i + 1);
    let alone = source[line_start..start].trim().is_empty();
    fix_of(source, if alone { line_start } else { start }, line_end)
}

/// Deletes one name and its separator from an import list that keeps other names.
fn name_removal(source: &str, import: &Import) -> Option<DiagnosticFix> {
    let start = import.name_pos.offset as usize;
    let end = start + import.name.as_str().len();
    let blank = |c: char| c == ' ' || c == '\t';
    let after = source[end..].trim_start_matches(blank);
    let after_at = source.len() - after.len();
    if after.starts_with(',') {
        let next = source[after_at + 1..].trim_start_matches(blank);
        let next_at = source.len() - next.len();
        let line_start = source[..start].rfind('\n').map_or(0, |i| i + 1);
        if next.starts_with('\n') && source[line_start..start].trim().is_empty() {
            return fix_of(source, line_start, next_at + 1);
        }
        return fix_of(source, start, next_at);
    }
    let before = source[..start].trim_end_matches(blank);
    if !before.ends_with(',') {
        return None;
    }
    fix_of(source, before.len() - 1, end)
}

#[derive(Default)]
struct Literals {
    list: bool,
    map: bool,
}

impl Visitor for Literals {
    fn expr(&mut self, e: &Expr) {
        match e.kind {
            ExprKind::List(_) => self.list = true,
            ExprKind::Map(_) => self.map = true,
            _ => {}
        }
    }
}

struct Scan<'a> {
    module: &'a ModuleData,
    file: &'a std::sync::Arc<str>,
    findings: &'a mut Vec<Finding>,
}

impl Visitor for Scan<'_> {
    fn block(&mut self, body: &[Stmt]) {
        let mut reachable = true;
        for s in body {
            if !reachable {
                self.findings.push(finding(
                    "MSL103",
                    "Statement is unreachable",
                    self.file,
                    s.pos,
                ));
            }
            let falls_through = self
                .module
                .facts()
                .stmts
                .get(&s.id)
                .and_then(|f| f.falls_through);
            if falls_through == Some(false) {
                reachable = false;
            }
        }
    }
}
