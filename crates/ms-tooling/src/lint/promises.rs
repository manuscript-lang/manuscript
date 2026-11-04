//! A promise dropped the moment it is made (`MSL115`). Dropping a promise cancels it, so
//! `promise(fn: work())` as a statement, or `let _ = read(path)`, starts work that is ended
//! before it can do anything. Keep the promise and `wait` for it.

use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::ModuleData;
use ms_syntax::DiagnosticFix;
use ms_syntax::ast::*;
use ms_syntax::visit::Visitor;

pub(super) fn lint(syms: ms_syntax::Names, module: &ModuleData, findings: &mut Vec<Finding>) {
    let file = module_file(syms, module);
    let mut scan = Scan {
        syms: ms_syntax::Names::global(),
        module,
        file: &file,
        findings,
    };
    walk_module(module, &mut scan);
}

struct Scan<'a> {
    syms: ms_syntax::Names,
    module: &'a ModuleData,
    file: &'a std::sync::Arc<str>,
    findings: &'a mut Vec<Finding>,
}

impl Scan<'_> {
    /// Whether `e` has type `Promise[..]` of `@std/concurrency/promise.ms`.
    fn is_promise(&self, syms: ms_syntax::Names, e: &Expr) -> bool {
        self.module
            .facts()
            .info(e.id)
            .and_then(|i| i.ty.as_ref())
            .is_some_and(|t| t.is_source_type(syms, "@std/concurrency/promise.ms", "Promise"))
    }

    fn report(&mut self, e: &Expr, statement: bool) {
        let mut found = finding(
            "MSL115",
            "This promise is dropped as soon as it is made, which cancels it; bind it and call wait() on it, or pass it to wait_all",
            self.file,
            e.pos,
        );
        // A call that used to wait for its result and ignored it: wait for it, still ignoring the result. As a
        // statement the result must be dropped on purpose, since `wait()` gives a `Result`.
        if matches!(e.kind, ExprKind::Call { .. }) {
            let text = self
                .module
                .source
                .get(e.pos.offset as usize..e.end.offset as usize);
            found.fix = match (statement, text) {
                (true, Some(text)) => Some(DiagnosticFix {
                    pos: e.pos,
                    end: e.end,
                    replacement: format!("let _ = {text}.wait()"),
                }),
                _ => Some(DiagnosticFix {
                    pos: e.end,
                    end: e.end,
                    replacement: ".wait()".to_string(),
                }),
            };
        }
        self.findings.push(found);
    }
}

impl Visitor for Scan<'_> {
    fn stmt(&mut self, stmt: &Stmt) {
        let syms = self.syms;
        match &stmt.kind {
            StmtKind::Call(e) if self.is_promise(syms, e) => self.report(e, true),
            StmtKind::Bind { pattern, value, .. }
                if matches!(&pattern.kind, PatternKind::Name(n) if syms.str(n) == "_")
                    && self.is_promise(syms, value) =>
            {
                self.report(value, false);
            }
            _ => {}
        }
    }
}
