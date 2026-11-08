//! An integer literal interpolated into text (`MSL117`): `"\\d{4}"` reads as a regex quantifier but
//! interpolates the number 4.

use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::ModuleData;
use ms_syntax::ast::*;
use ms_syntax::visit::Visitor;

pub(super) fn lint(syms: ms_syntax::Names, module: &ModuleData, findings: &mut Vec<Finding>) {
    let file = module_file(syms, module);
    let mut scan = Scan {
        syms,
        file: &file,
        findings,
    };
    walk_module(module, &mut scan);
}

struct Scan<'a> {
    syms: ms_syntax::Names,
    file: &'a std::sync::Arc<str>,
    findings: &'a mut Vec<Finding>,
}

impl Visitor for Scan<'_> {
    fn expr(&mut self, e: &Expr) {
        let ExprKind::Text(parts) = &e.kind else {
            return;
        };
        for part in parts {
            let TextPart::Interp(inner) = part else {
                continue;
            };
            let ExprKind::Number(spelling) = &inner.kind else {
                continue;
            };
            let digits = self.syms.str(*spelling);
            if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
                continue;
            }
            self.findings.push(finding(
                "MSL117",
                format!(
                    "`{{{digits}}}` interpolates the number {digits}, not a literal brace; write `\\{{{digits}\\}}` for braces (a regex quantifier), or use `r\"\"\"` raw text"
                ),
                self.file,
                inner.pos,
            ));
        }
    }
}
