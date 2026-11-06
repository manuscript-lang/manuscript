//! Calls that fault when a value is absent: `Optional.get()` without a
//! default (`MSL110`).

use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::ModuleData;
use ms_check::api::types::Builtin;
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

impl Visitor for Scan<'_> {
    fn expr(&mut self, e: &Expr) {
        let syms = self.syms;
        let ExprKind::Call { callee, args } = &e.kind else {
            return;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return;
        };
        if syms.str(name) != "get" || !args.is_empty() {
            return;
        }
        let absent_faults = self
            .module
            .facts()
            .info(left.id)
            .and_then(|i| i.ty.as_ref())
            .is_some_and(|t| t.is(Builtin::Optional));
        if absent_faults {
            self.findings.push(finding(
                "MSL110",
                "Optional.get() without a default faults when the value is absent; use 'if let value = ...:', pass a default to get(default), or get_or_else",
                self.file,
                e.pos,
            ));
        }
    }
}
