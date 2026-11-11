//! Match shapes with a simpler spelling: nested matches (`MSL107`) and
//! two-arm matches on `Optional` (`MSL108`) or `Result` (`MSL109`).

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
        depth: 0,
        findings,
    };
    walk_module(module, &mut scan);
}

/// The final written segment of an arm path: `some` for `Optional.some`.
pub(super) fn path_text(syms: ms_syntax::Names, path: &Expr) -> String {
    match &path.kind {
        ExprKind::Name(name) | ExprKind::Member { name, .. } => syms.str(name).to_string(),
        _ => String::new(),
    }
}

struct Scan<'a> {
    syms: ms_syntax::Names,
    module: &'a ModuleData,
    file: &'a std::sync::Arc<str>,
    depth: usize,
    findings: &'a mut Vec<Finding>,
}

impl Scan<'_> {
    fn two_arm(&mut self, syms: ms_syntax::Names, e: &Expr, scrutinee: &Expr, arms: &[Arm]) {
        if arms.len() != 2 {
            return;
        }
        let checked = self.module.facts().info(e.id).is_some();
        let ty = self
            .module
            .facts()
            .info(scrutinee.id)
            .and_then(|i| i.ty.clone());
        let Some(ty) = ty.filter(|_| checked) else {
            return;
        };
        let (code, message, first, second) = if ty.is(Builtin::Optional) {
            (
                "MSL108",
                "Matching an Optional with only a payload arm and none; use 'if value := ...:' with 'else:', or an Optional method such as get(default) or map",
                "some",
                "none",
            )
        } else if ty.is(Builtin::Result) {
            (
                "MSL109",
                "Matching a Result with only ok and error; use a trailing '?', 'if value := ...:' with 'else:', or a Result method such as get(default), is_error, or err",
                "ok",
                "error",
            )
        } else {
            return;
        };
        let texts: Vec<String> = arms
            .iter()
            .map(|a| {
                if a.bare && ty.is(Builtin::Optional) {
                    "some".to_string()
                } else {
                    path_text(syms, &a.path)
                }
            })
            .collect();
        if texts.iter().any(|t| t == first) && texts.iter().any(|t| t == second) {
            self.findings.push(finding(code, message, self.file, e.pos));
        }
    }
}

impl Visitor for Scan<'_> {
    fn expr(&mut self, e: &Expr) {
        let syms = self.syms;
        let ExprKind::Match { scrutinee, arms } = &e.kind else {
            return;
        };
        if !e.is_written_match() {
            return;
        }
        if self.depth > 0 {
            self.findings.push(finding(
                "MSL107",
                "Nested match obscures control flow; bind the outer payload with an early exit, use a compatible trailing '?', or call a small helper",
                self.file,
                e.pos,
            ));
        }
        self.depth += 1;
        self.two_arm(syms, e, scrutinee, arms);
    }

    fn leave_expr(&mut self, e: &Expr) {
        if e.is_written_match() {
            self.depth -= 1;
        }
    }
}
