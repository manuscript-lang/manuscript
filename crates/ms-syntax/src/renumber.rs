//! Fresh node ids for a cloned method, so per-node checker facts of two copies never collide.

use crate::ast::*;

/// Gives every node of `method` a new id drawn from `next`.
pub fn renumber_method(method: &mut Method, next: &mut u32) {
    let mut r = Renumber { next };
    r.id(&mut method.id);
    r.func(&mut method.func);
}

struct Renumber<'a> {
    next: &'a mut u32,
}

impl Renumber<'_> {
    fn id(&mut self, id: &mut NodeId) {
        *id = NodeId(*self.next);
        *self.next += 1;
    }

    fn func(&mut self, f: &mut Func) {
        for p in &mut f.type_params {
            self.type_param(p);
        }
        for p in &mut f.params {
            self.param(p);
        }
        self.ty(&mut f.result);
        self.block(&mut f.body);
    }

    fn type_param(&mut self, p: &mut TypeParam) {
        self.id(&mut p.id);
        for b in &mut p.bounds {
            self.ty(b);
        }
        if let Some(d) = &mut p.default {
            self.ty(d);
        }
    }

    fn param(&mut self, p: &mut Param) {
        self.id(&mut p.id);
        if let Some(t) = &mut p.ty {
            self.ty(t);
        }
        if let Some(d) = &mut p.default {
            self.expr(d);
        }
    }

    fn ty(&mut self, t: &mut TypeRef) {
        self.id(&mut t.id);
        match &mut t.kind {
            TypeKind::Named { args, .. } => args.iter_mut().for_each(|a| self.ty(a)),
            TypeKind::Fn { params, result } => {
                params.iter_mut().for_each(|p| self.param(p));
                self.ty(result);
            }
        }
    }

    fn block(&mut self, body: &mut [Stmt]) {
        body.iter_mut().for_each(|s| self.stmt(s));
    }

    fn pattern(&mut self, p: &mut Pattern) {
        self.id(&mut p.id);
        match &mut p.kind {
            PatternKind::Name(_) => {}
            PatternKind::List(items) => items.iter_mut().for_each(|i| self.pattern(i)),
            PatternKind::Type(fields) => {
                fields.iter_mut().for_each(|f| self.pattern(&mut f.pattern))
            }
        }
    }

    fn stmt(&mut self, s: &mut Stmt) {
        self.id(&mut s.id);
        match &mut s.kind {
            StmtKind::Bind {
                pattern, ty, value, ..
            } => {
                self.pattern(pattern);
                if let Some(t) = ty {
                    self.ty(t);
                }
                self.expr(value);
            }
            StmtKind::Assign { target, value, .. } => {
                if let AssignTarget::Member(e) = target {
                    self.expr(e);
                }
                self.expr(value);
            }
            StmtKind::Call(e) => self.expr(e),
            StmtKind::Return(e) => {
                if let Some(e) = e {
                    self.expr(e);
                }
            }
            StmtKind::Break | StmtKind::Continue => {}
            StmtKind::If {
                binding,
                cond,
                body,
                else_body,
                ..
            } => {
                if let Some(b) = binding {
                    self.pattern(b);
                }
                self.expr(cond);
                self.block(body);
                self.block(else_body);
            }
            StmtKind::While { cond, body } => {
                self.expr(cond);
                self.block(body);
            }
            StmtKind::For { iter, body, .. } => {
                self.expr(iter);
                self.block(body);
            }
        }
    }

    fn expr(&mut self, e: &mut Expr) {
        self.id(&mut e.id);
        match &mut e.kind {
            ExprKind::Number(_) | ExprKind::Bool(_) | ExprKind::Unit | ExprKind::Name(_) => {}
            ExprKind::Text(parts) => {
                for p in parts {
                    if let TextPart::Interp(x) = p {
                        self.expr(x);
                    }
                }
            }
            ExprKind::Member { left, .. } | ExprKind::Probe(left) => self.expr(left),
            ExprKind::Apply { left, types, value } => {
                self.expr(left);
                types.iter_mut().for_each(|t| self.ty(t));
                if let Some(v) = value {
                    self.expr(v);
                }
            }
            ExprKind::Index { left, index } => {
                self.expr(left);
                self.expr(index);
            }
            ExprKind::List(items) => items.iter_mut().for_each(|i| self.expr(i)),
            ExprKind::Map(entries) => {
                for en in entries {
                    self.expr(&mut en.key);
                    self.expr(&mut en.value);
                }
            }
            ExprKind::Unary { operand, .. } => self.expr(operand),
            ExprKind::Binary { left, right, .. } => {
                self.expr(left);
                self.expr(right);
            }
            ExprKind::Lambda(l) => {
                l.params.iter_mut().for_each(|p| self.param(p));
                if let Some(r) = &mut l.result {
                    self.ty(r);
                }
                self.block(&mut l.body);
            }
            ExprKind::Call { callee, args } => {
                self.expr(callee);
                args.iter_mut().for_each(|a| self.expr(&mut a.value));
            }
            ExprKind::Match { scrutinee, arms } => {
                self.expr(scrutinee);
                for a in arms {
                    self.id(&mut a.id);
                    self.expr(&mut a.path);
                    self.block(&mut a.body);
                    if let Some(v) = &mut a.value {
                        self.expr(v);
                    }
                }
            }
        }
    }
}
