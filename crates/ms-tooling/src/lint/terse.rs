//! Longer spellings of shorter forms that mean the same thing: `xs.length() == 0`
//! (`MSL118`) and `xs.get(i)` on a list (`MSL119`). Each finding carries the fix.

use super::bindings::pos_at;
use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::ModuleData;
use ms_check::api::types::Builtin;
use ms_syntax::ast::*;
use ms_syntax::diag::DiagnosticFix;
use ms_syntax::visit::Visitor;

pub(super) fn lint(syms: ms_syntax::Names, module: &ModuleData, findings: &mut Vec<Finding>) {
    let file = module_file(syms, module);
    let mut scan = Scan {
        syms,
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
    fn source(&self) -> &str {
        &self.module.source
    }

    fn collection(&self, e: &Expr) -> bool {
        self.module
            .facts()
            .info(e.id)
            .and_then(|i| i.ty.as_ref())
            .is_some_and(|t| {
                t.is_string() || t.is(Builtin::List) || t.is(Builtin::Map) || t.is(Builtin::Set)
            })
    }

    fn list(&self, e: &Expr) -> bool {
        self.module
            .facts()
            .info(e.id)
            .and_then(|i| i.ty.as_ref())
            .is_some_and(|t| t.is(Builtin::List))
    }

    /// `recv.length()` as its receiver.
    fn length_of<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let ExprKind::Call { callee, args } = &e.kind else {
            return None;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return None;
        };
        (self.syms.str(name) == "length" && args.is_empty() && self.collection(left))
            .then_some(&**left)
    }

    fn text(&self, from: &Expr, to: &Expr) -> Option<&str> {
        let (a, b) = (from.start().offset as usize, to.end.offset as usize);
        self.source().get(a..b)
    }

    fn report(
        &mut self,
        code: &'static str,
        message: String,
        at: &Expr,
        from: usize,
        to: usize,
        replacement: String,
    ) {
        let mut found = finding(code, message, self.file, at.pos);
        found.fix = Some(DiagnosticFix {
            pos: pos_at(self.source(), from),
            end: pos_at(self.source(), to),
            replacement,
        });
        self.findings.push(found);
    }

    /// `x.length() == 0` and, in a condition, `x.length() != 0` / `> 0`.
    fn emptiness(&mut self, e: &Expr, condition: bool) {
        match &e.kind {
            ExprKind::Binary {
                op: BinaryOp::And | BinaryOp::Or,
                left,
                right,
            } => {
                self.emptiness(left, condition);
                self.emptiness(right, condition);
            }
            ExprKind::Binary { op, left, right } => {
                let zero = matches!(&right.kind, ExprKind::Number(n) if self.syms.str(n) == "0");
                let Some(receiver) = self.length_of(left).filter(|_| zero) else {
                    return;
                };
                let Some(recv) = self.text(receiver, receiver) else {
                    return;
                };
                let replacement = match op {
                    // `== 0` is reported where the expression is visited.
                    BinaryOp::Eq if !condition => format!("{recv}.is_empty()"),
                    BinaryOp::Ne | BinaryOp::Gt if condition => format!("not {recv}.is_empty()"),
                    _ => return,
                };
                self.report(
                    "MSL118",
                    "Use is_empty() instead of comparing length() with 0".to_string(),
                    e,
                    e.start().offset as usize,
                    right.end.offset as usize,
                    replacement,
                );
            }
            _ => {}
        }
    }
}

impl Visitor for Scan<'_> {
    fn stmt(&mut self, s: &Stmt) {
        match &s.kind {
            StmtKind::If {
                binding: None,
                cond,
                ..
            }
            | StmtKind::While { cond, .. } => self.emptiness(cond, true),
            StmtKind::Return(Some(e)) => self.emptiness(e, true),
            _ => {}
        }
    }

    fn expr(&mut self, e: &Expr) {
        if let ExprKind::Binary {
            op: BinaryOp::Eq, ..
        } = &e.kind
        {
            self.emptiness(e, false);
        }
        // `xs.get(i)` on a list held in a name or field is `xs[i]`.
        let ExprKind::Call { callee, args } = &e.kind else {
            return;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return;
        };
        let ([arg], true) = (args.as_slice(), self.syms.str(name) == "get") else {
            return;
        };
        if arg.name.is_some()
            || !matches!(left.kind, ExprKind::Name(_) | ExprKind::Member { .. })
            || !self.list(left)
        {
            return;
        }
        let dot = (name_pos(callee) as usize).checked_sub(1);
        let source = self.source();
        let (Some(dot), Some(index)) = (dot, self.text(&arg.value, &arg.value)) else {
            return;
        };
        if source.as_bytes().get(dot) != Some(&b'.') {
            return;
        }
        let index = index.to_string();
        self.report(
            "MSL119",
            "Index the list with xs[i] instead of xs.get(i)".to_string(),
            e,
            dot,
            e.end.offset as usize,
            format!("[{index}]"),
        );
    }
}

fn name_pos(callee: &Expr) -> u32 {
    callee.pos.offset
}
