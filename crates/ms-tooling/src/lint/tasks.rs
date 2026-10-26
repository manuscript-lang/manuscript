//! A `while True` loop that never waits (`MSL111`). Tasks share one thread and are
//! cancelled at their next wait, so such a loop starves its siblings and ignores
//! timeouts and `TaskGroup` close.

use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::ModuleData;
use ms_check::types::Kind;
use ms_syntax::ast::*;
use ms_syntax::visit::{Visitor, walk_block};

pub(super) fn lint(module: &ModuleData, findings: &mut Vec<Finding>) {
    if !module.imports.iter().any(|i| i.path.ends_with("tasks.ms")) {
        return;
    }
    let file = module_file(module);
    let mut scan = Scan {
        module,
        file: &file,
        findings,
    };
    walk_module(module, &mut scan);
}

struct Scan<'a> {
    module: &'a ModuleData,
    file: &'a std::sync::Arc<str>,
    findings: &'a mut Vec<Finding>,
}

impl Visitor for Scan<'_> {
    fn stmt(&mut self, stmt: &Stmt) {
        let StmtKind::While { cond, body } = &stmt.kind else {
            return;
        };
        if !matches!(cond.kind, ExprKind::Bool(true)) {
            return;
        }
        let mut body_scan = Body {
            module: self.module,
            may_wait_or_exit: false,
        };
        walk_block(&mut body_scan, body);
        if !body_scan.may_wait_or_exit {
            self.findings.push(finding(
                "MSL111",
                "This loop never waits or exits, so other tasks cannot run and a timeout cannot stop it; wait inside the loop (sleep or a channel call), or return once cancelled() is True",
                self.file,
                cond.pos,
            ));
        }
    }
}

/// Whether a loop body can wait, call something unknown, or leave the loop.
struct Body<'a> {
    module: &'a ModuleData,
    may_wait_or_exit: bool,
}

impl Body<'_> {
    /// A call that runs to completion without waiting: a constructor, or a method of a
    /// primitive or a core collection.
    fn local_call(&self, call: &Expr, callee: &Expr) -> bool {
        let facts = self.module.facts();
        if facts.info(call.id).is_some_and(|i| i.constructor.is_some()) {
            return true;
        }
        let ExprKind::Member { left, .. } = &callee.kind else {
            return false;
        };
        let Some(ty) = facts.info(left.id).and_then(|i| i.ty.clone()) else {
            return false;
        };
        ty.kind == Kind::Primitive
            || [
                "List", "Map", "Set", "String", "Optional", "Result", "Bytes",
            ]
            .iter()
            .any(|name| ty.is_std(name))
    }
}

impl Visitor for Body<'_> {
    fn stmt(&mut self, stmt: &Stmt) {
        if matches!(stmt.kind, StmtKind::Break | StmtKind::Return(_)) {
            self.may_wait_or_exit = true;
        }
    }

    fn expr(&mut self, e: &Expr) {
        match &e.kind {
            ExprKind::Call { callee, .. } if !self.local_call(e, callee) => {
                self.may_wait_or_exit = true;
            }
            ExprKind::Lambda(_) | ExprKind::Match { .. } => self.may_wait_or_exit = true,
            _ => {}
        }
    }
}
