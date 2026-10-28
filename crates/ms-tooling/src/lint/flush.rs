//! A resource closed at scope end whose type can report a failure only through a
//! separate method (`MSL114`): `close` cannot return an error, so a failed write
//! surfaces only if the binding is flushed first.

use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::editor::{MemberKind, members};
use ms_check::types::{Name, Ty, n};
use ms_check::{ModuleData, Program};
use ms_syntax::ast::*;
use ms_syntax::visit::Visitor;
use std::collections::HashSet;

/// Zero-argument methods that return a `Result` and make earlier writes durable.
const FINISHERS: [&str; 3] = ["flush", "sync", "commit"];

pub(super) fn lint(program: &Program, module: &ModuleData, findings: &mut Vec<Finding>) {
    let mut scan = Scan {
        module,
        owned: Vec::new(),
        finished: HashSet::new(),
    };
    walk_module(module, &mut scan);
    let file = module_file(module);
    for (uid, name, pos, ty) in scan.owned {
        if scan.finished.contains(&uid) || !program.implicit_closes.contains(&uid) {
            continue;
        }
        let Some(method) = finisher(program, module, &ty) else {
            continue;
        };
        findings.push(finding(
            "MSL114",
            format!(
                "`{name}` is closed when its scope ends, and close cannot report a failure; call `try {name}.{method}()` before the scope ends to see one"
            ),
            &file,
            pos,
        ));
    }
}

/// The first finisher `ty` offers: no parameters, returning a `Result`.
fn finisher(program: &Program, module: &ModuleData, ty: &Ty) -> Option<Name> {
    members(program, ty, Some(module.file))
        .into_iter()
        .find(|m| {
            m.kind == MemberKind::Method
                && FINISHERS.iter().any(|f| m.name == n(f))
                && m.ty.params.is_empty()
                && m.ty.result_ty().is_std("Result")
        })
        .map(|m| m.name)
}

struct Scan<'a> {
    module: &'a ModuleData,
    /// Bindings with an implicit-close cleanup: identity, name, position, type.
    owned: Vec<(usize, Name, ms_syntax::Pos, Ty)>,
    /// Bindings a finisher is called on.
    finished: HashSet<usize>,
}

impl Visitor for Scan<'_> {
    fn stmt(&mut self, stmt: &Stmt) {
        let StmtKind::Bind { pattern, .. } = &stmt.kind else {
            return;
        };
        if !matches!(pattern.kind, PatternKind::Name(_)) {
            return;
        }
        let facts = self.module.facts();
        let Some(b) = facts.patterns.get(&pattern.id) else {
            return;
        };
        if facts
            .stmts
            .get(&stmt.id)
            .is_some_and(|f| f.cleanup.is_some())
        {
            self.owned.push((b.uid, b.name, pattern.pos, b.ty.clone()));
        }
    }

    fn expr(&mut self, e: &Expr) {
        let ExprKind::Call { callee, .. } = &e.kind else {
            return;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return;
        };
        if !FINISHERS.iter().any(|f| *name == n(f)) {
            return;
        }
        if let Some(b) = self
            .module
            .facts()
            .info(left.id)
            .and_then(|i| i.binding.clone())
        {
            self.finished.insert(b.uid);
        }
    }
}
