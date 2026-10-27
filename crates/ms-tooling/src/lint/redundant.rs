//! A written `some(x)` where a plain `x` is wrapped to the same Optional
//! (`MSL113`). The fix replaces the call with its argument.

use super::{Finding, finding, module_file};
use ms_check::ModuleData;
use ms_syntax::DiagnosticFix;
use ms_syntax::ast::*;
use ms_syntax::visit::{Visitor, walk_callable, walk_decl};

pub(super) fn lint(module: &ModuleData, findings: &mut Vec<Finding>) {
    let file = module_file(module);
    let mut scan = Scan {
        module,
        file: &file,
        findings,
    };
    for decl in &module.decls {
        match &decl.decl().kind {
            DeclKind::Fn(f) => scan.func(f),
            DeclKind::Impl(i) => i.methods.iter().for_each(|m| scan.func(&m.func)),
            _ => walk_decl(&mut scan, decl.decl()),
        }
    }
}

struct Scan<'a> {
    module: &'a ModuleData,
    file: &'a std::sync::Arc<str>,
    findings: &'a mut Vec<Finding>,
}

impl Scan<'_> {
    /// A `ref` result lends part of a parameter: the explicit `some(...)` is what
    /// makes the Optional wrap that borrow, so those bodies are left alone.
    fn func(&mut self, f: &Func) {
        if !f.result_ref {
            walk_callable(self, &f.params, &f.body);
        }
    }
}

impl Visitor for Scan<'_> {
    fn expr(&mut self, e: &Expr) {
        let ExprKind::Call { args, .. } = &e.kind else {
            return;
        };
        let redundant = self
            .module
            .facts()
            .info(e.id)
            .is_some_and(|i| i.redundant_some);
        let [arg] = args.as_slice() else {
            return;
        };
        if !redundant {
            return;
        }
        let value = &arg.value;
        let Some(text) = self
            .module
            .source
            .get(value.start().offset as usize..value.end.offset as usize)
        else {
            return;
        };
        let mut f = finding(
            "MSL113",
            "some(...) is redundant here: a plain value is wrapped where an Optional is expected; pass the value itself",
            self.file,
            e.pos,
        );
        f.fix = Some(DiagnosticFix {
            pos: e.start(),
            end: e.end,
            replacement: text.to_string(),
        });
        self.findings.push(f);
    }
}
