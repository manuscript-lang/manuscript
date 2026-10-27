//! Unused imports (`MSL102`) and unreachable statements (`MSL103`). Unread bindings
//! are check errors.

use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::types::n;
use ms_check::{ModuleData, Program};
use ms_syntax::ast::*;
use ms_syntax::visit::Visitor;
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
    for import in &module.imports {
        let key = symbol_of(import.name.as_str());
        if !key.is_some_and(|k| used.contains(&k)) {
            findings.push(finding(
                "MSL102",
                format!("Import {} is never used", import.name.as_str()),
                &file,
                import.name_pos,
            ));
        }
    }
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
