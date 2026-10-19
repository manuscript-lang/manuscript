//! Discarded `Result` values (`MSL104`).

use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::ModuleData;
use ms_syntax::ast::*;
use ms_syntax::visit::Visitor;

pub(super) fn lint(module: &ModuleData, findings: &mut Vec<Finding>) {
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
    // An expression statement, including a standalone match. Only the
    // discarded outer value is inspected: arguments and match arm values may
    // be consumed, and a standalone `try` has already unwrapped to Unit.
    fn stmt(&mut self, s: &Stmt) {
        let StmtKind::Call(value) = &s.kind else {
            return;
        };
        let facts = self.module.facts();
        let discarded = facts
            .info(value.id)
            .and_then(|i| i.ty.as_ref())
            .is_some_and(|t| t.is_std("Result"));
        if discarded {
            self.findings.push(finding(
                "MSL104",
                "Result is discarded; handle it with try or if let, return it, or bind it to _ignored to discard intentionally",
                self.file,
                s.pos,
            ));
        }
    }
}
