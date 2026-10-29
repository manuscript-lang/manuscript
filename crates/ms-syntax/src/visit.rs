//! Source-order walker over executable syntax.
//!
//! Implement [`Visitor`] and override the hooks you need; [`walk_decl`] does the
//! recursion through parameter defaults, interpolation, closures, branches and
//! match arms. Types and patterns are not executable and are not visited.
//!
//! Visit order : for a statement, `stmt` then the assignment
//! target, the value, the body, the else body. For an expression, `expr`, then
//! left/right, arguments, list/map elements, text interpolations, lambda
//! parameter defaults and body, arms (body then value), and finally
//! `leave_expr`.

use crate::ast::*;

/// Hooks called by the walker. All have empty defaults.
pub trait Visitor {
    /// Called once for every non-empty statement list, before its statements.
    fn block(&mut self, _body: &[Stmt]) {}
    /// Called for every statement before its children.
    fn stmt(&mut self, _stmt: &Stmt) {}
    /// Called for every expression before its children.
    fn expr(&mut self, _expr: &Expr) {}
    /// Called after all executable children of an expression, arm bodies included.
    fn leave_expr(&mut self, _expr: &Expr) {}
}

/// Walks a declaration and its methods.
pub fn walk_decl<V: Visitor>(v: &mut V, d: &Decl) {
    match &d.kind {
        DeclKind::Fn(f) => walk_callable(v, &f.params, &f.body),
        DeclKind::Const(c) => walk_expr(v, &c.value),
        DeclKind::Record(r) => walk_params(v, &r.fields),
        DeclKind::Alternative(_) => {}
        DeclKind::Interface(i) => i
            .methods
            .iter()
            .for_each(|m| walk_callable(v, &m.func.params, &m.func.body)),
        DeclKind::Impl(i) => i
            .methods
            .iter()
            .for_each(|m| walk_callable(v, &m.func.params, &m.func.body)),
        DeclKind::Test(t) => walk_block(v, &t.body),
    }
}

/// Visits parameter defaults and a body.
pub fn walk_callable<V: Visitor>(v: &mut V, params: &[Param], body: &[Stmt]) {
    walk_params(v, params);
    walk_block(v, body);
}

fn walk_params<V: Visitor>(v: &mut V, params: &[Param]) {
    for p in params {
        if let Some(d) = &p.default {
            walk_expr(v, d);
        }
    }
}

/// Visits a statement list.
pub fn walk_block<V: Visitor>(v: &mut V, body: &[Stmt]) {
    if body.is_empty() {
        return;
    }
    v.block(body);
    for s in body {
        walk_stmt(v, s);
    }
}

/// Visits one statement.
pub fn walk_stmt<V: Visitor>(v: &mut V, s: &Stmt) {
    v.stmt(s);
    match &s.kind {
        StmtKind::Bind { value, .. } => walk_expr(v, value),
        StmtKind::Assign { target, value, .. } => {
            if let AssignTarget::Member(t) = target {
                walk_expr(v, t);
            }
            walk_expr(v, value);
        }
        StmtKind::Call(e) => walk_expr(v, e),
        StmtKind::Return(e) => {
            if let Some(e) = e {
                walk_expr(v, e);
            }
        }
        StmtKind::Break | StmtKind::Continue => {}
        StmtKind::If {
            cond,
            body,
            else_body,
            ..
        } => {
            walk_expr(v, cond);
            walk_block(v, body);
            walk_block(v, else_body);
        }
        StmtKind::While { cond, body } => {
            walk_expr(v, cond);
            walk_block(v, body);
        }
        StmtKind::For { iter, body, .. } => {
            walk_expr(v, iter);
            walk_block(v, body);
        }
    }
}

/// Visits one expression.
pub fn walk_expr<V: Visitor>(v: &mut V, e: &Expr) {
    v.expr(e);
    match &e.kind {
        ExprKind::Number(_) | ExprKind::Bool(_) | ExprKind::Unit | ExprKind::Name(_) => {}
        ExprKind::Text(parts) => {
            for part in parts {
                if let TextPart::Interp(x) = part {
                    walk_expr(v, x);
                }
            }
        }
        ExprKind::Member { left, .. } => walk_expr(v, left),
        ExprKind::Apply { left, value, .. } => {
            walk_expr(v, left);
            if let Some(x) = value {
                walk_expr(v, x);
            }
        }
        ExprKind::Index { left, index } => {
            walk_expr(v, left);
            walk_expr(v, index);
        }
        ExprKind::List(items) => items.iter().for_each(|x| walk_expr(v, x)),
        ExprKind::Map(entries) => entries.iter().for_each(|en| {
            walk_expr(v, &en.key);
            walk_expr(v, &en.value);
        }),
        ExprKind::Unary { operand, .. } => walk_expr(v, operand),
        ExprKind::Binary { left, right, .. } => {
            walk_expr(v, left);
            walk_expr(v, right);
        }
        ExprKind::Lambda(l) => walk_callable(v, &l.params, &l.body),
        ExprKind::Call { callee, args } => {
            walk_expr(v, callee);
            args.iter().for_each(|a| walk_expr(v, &a.value));
        }
        ExprKind::Match { scrutinee, arms } => {
            walk_expr(v, scrutinee);
            for arm in arms {
                walk_block(v, &arm.body);
                if let Some(x) = &arm.value {
                    walk_expr(v, x);
                }
            }
        }
    }
    v.leave_expr(e);
}
