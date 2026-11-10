//! Functions that call themselves on every path (`MSL112`): no `return`, `try`
//! or fault leaves the function before the recursive call, so it never finishes.

use super::{Finding, finding, module_file};
use ms_check::api::types::n;
use ms_check::{ModuleData, Program};
use ms_syntax::ast::*;

pub(super) fn lint(
    syms: ms_syntax::Names,
    program: &Program,
    module: &ModuleData,
    findings: &mut Vec<Finding>,
) {
    let file = module_file(syms, module);
    let Some(symbols) = program.symbols.get(&module.file) else {
        return;
    };
    for decl in &module.decls {
        let decl = decl.decl();
        let DeclKind::Fn(func) = &decl.kind else {
            continue;
        };
        let Some(own) = symbols
            .borrow()
            .get(&n(syms.str(func.name)))
            .map(|s| s.key())
        else {
            continue;
        };
        let scan = Scan { module, own };
        if !func.external
            && !func.body.is_empty()
            && scan.block(syms, &func.body) == Outcome::Recursed
        {
            findings.push(finding(
                "MSL112",
                format!(
                    "{} calls itself on every path, so it never returns; add a base case that returns before the recursive call",
                    syms.str(func.name)
                ),
                &file,
                decl.pos,
            ));
        }
    }
}

/// How control leaves a block.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Outcome {
    /// Every path reaches the recursive call first.
    Recursed,
    /// Some path returns, propagates an error or faults without recursing.
    Escaped,
    /// Control reaches the end of the block.
    Continues,
}

struct Scan<'a> {
    module: &'a ModuleData,
    own: usize,
}

impl Scan<'_> {
    fn block(&self, syms: ms_syntax::Names, stmts: &[Stmt]) -> Outcome {
        for s in stmts {
            match self.stmt(syms, s) {
                Outcome::Continues => {}
                done => return done,
            }
        }
        Outcome::Continues
    }

    fn stmt(&self, syms: ms_syntax::Names, s: &Stmt) -> Outcome {
        match &s.kind {
            StmtKind::Return(None) => Outcome::Escaped,
            StmtKind::Return(Some(v)) => self.value(syms, v, true),
            StmtKind::Bind { value, .. } | StmtKind::Assign { value, .. } => {
                self.value(syms, value, false)
            }
            StmtKind::Call(e) => self.value(syms, e, false),
            StmtKind::Break | StmtKind::Continue => Outcome::Continues,
            StmtKind::If {
                cond,
                body,
                else_body,
                ..
            } => match self.value(syms, cond, false) {
                Outcome::Continues => {
                    self.branches(&[self.block(syms, body), self.block(syms, else_body)])
                }
                done => done,
            },
            // A loop may run zero times, so only an exit inside it counts.
            StmtKind::While { cond, body } => self.looped(syms, cond, body),
            StmtKind::For { iter, body, .. } => self.looped(syms, iter, body),
        }
    }

    fn looped(&self, syms: ms_syntax::Names, head: &Expr, body: &[Stmt]) -> Outcome {
        match self.value(syms, head, false) {
            Outcome::Continues if self.block(syms, body) == Outcome::Escaped => Outcome::Escaped,
            done => done,
        }
    }

    /// Branches taken one at a time: any exit is an exit, all recursing is recursing.
    fn branches(&self, outcomes: &[Outcome]) -> Outcome {
        if outcomes.contains(&Outcome::Escaped) {
            Outcome::Escaped
        } else if outcomes.iter().all(|o| *o == Outcome::Recursed) {
            Outcome::Recursed
        } else {
            Outcome::Continues
        }
    }

    /// The outcome of evaluating `e`; `returned` when its value is the function's result.
    fn value(&self, syms: ms_syntax::Names, e: &Expr, returned: bool) -> Outcome {
        if self.exits(e) {
            return Outcome::Escaped;
        }
        if let ExprKind::Match { scrutinee, arms } = &e.kind {
            if self.reaches_call(scrutinee) {
                return Outcome::Recursed;
            }
            let outcomes: Vec<Outcome> = arms.iter().map(|a| self.arm(syms, a, returned)).collect();
            return self.branches(&outcomes);
        }
        match (self.reaches_call(e), returned) {
            (true, _) => Outcome::Recursed,
            (false, true) => Outcome::Escaped,
            (false, false) => Outcome::Continues,
        }
    }

    fn arm(&self, syms: ms_syntax::Names, arm: &Arm, returned: bool) -> Outcome {
        match self.block(syms, &arm.body) {
            Outcome::Continues => match &arm.value {
                Some(v) => self.value(syms, v, returned),
                None if returned => Outcome::Escaped,
                None => Outcome::Continues,
            },
            done => done,
        }
    }

    /// Whether evaluating `e` can leave the function without returning normally: a `try`, or a
    /// call that never completes.
    fn exits(&self, e: &Expr) -> bool {
        let mut found = false;
        visit(e, &mut |x| {
            if matches!(
                x.kind,
                ExprKind::Unary {
                    op: UnaryOp::Try,
                    ..
                }
            ) {
                found = true;
            }
            let never = self
                .module
                .facts()
                .info(x.id)
                .and_then(|i| i.ty.as_ref())
                .is_some_and(|t| t.is_never());
            found |= never && matches!(x.kind, ExprKind::Call { .. });
        });
        found
    }

    /// Whether evaluating `e` unconditionally calls this function.
    fn reaches_call(&self, e: &Expr) -> bool {
        let mut found = false;
        visit(e, &mut |x| {
            if let ExprKind::Call { callee, .. } = &x.kind
                && self
                    .module
                    .facts()
                    .info(callee.id)
                    .and_then(|i| i.symbol.as_ref())
                    .is_some_and(|s| s.key() == self.own)
            {
                found = true;
            }
        });
        found
    }
}

/// Visits `e` and the subexpressions that are always evaluated: not the right side of
/// `and`/`or`, a lambda body, or a match arm.
fn visit(e: &Expr, f: &mut dyn FnMut(&Expr)) {
    f(e);
    match &e.kind {
        ExprKind::Member { left, .. } => visit(left, f),
        ExprKind::Apply { left, value, .. } => {
            visit(left, f);
            if let Some(v) = value {
                visit(v, f);
            }
        }
        ExprKind::Index { left, index } => {
            visit(left, f);
            visit(index, f);
        }
        ExprKind::List(items) => items.iter().for_each(|i| visit(i, f)),
        ExprKind::Map(entries) => entries.iter().for_each(|m| {
            visit(&m.key, f);
            visit(&m.value, f);
        }),
        ExprKind::Text(parts) => parts.iter().for_each(|p| {
            if let TextPart::Interp(x) = p {
                visit(x, f);
            }
        }),
        ExprKind::Unary { operand, .. } => visit(operand, f),
        ExprKind::Binary { op, left, right } => {
            visit(left, f);
            if !matches!(op, BinaryOp::And | BinaryOp::Or) {
                visit(right, f);
            }
        }
        ExprKind::Call { callee, args } => {
            visit(callee, f);
            args.iter().for_each(|a| visit(&a.value, f));
        }
        ExprKind::Match { scrutinee, .. } => visit(scrutinee, f),
        _ => {}
    }
}
