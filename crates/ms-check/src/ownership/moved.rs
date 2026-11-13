//! Which bindings some path keeps without completing a tracked action.
//!
//! A binding that every path moves out of before leaving its scope has nothing left to drop: its
//! local is consumed where the move is. A binding some path keeps is still dropped at the scope
//! end on those paths, so lowering holds it in a form that can be empty (an optional).
//!
//! The walk runs backwards over the body with a set of bindings that every path from the current
//! point moves before any exit of the scope. An exit (the end of the body, `return`, and `break`
//! or `continue` for the loop they leave) empties the set for the bindings whose scope ends; a
//! join keeps the bindings every incoming path moves. Scope-close inference reuses the walk
//! with completed explicit-close and replacement actions, without changing lowering move facts.

use crate::hir::*;
use ms_syntax::ast::*;
use std::collections::{HashMap, HashSet};

/// Every path from here completes an action for these bindings before leaving their scope.
type Must = HashSet<usize>;

fn meet(into: &mut Option<Must>, from: Must) {
    match into {
        Some(m) => m.retain(|u| from.contains(u)),
        None => *into = Some(from),
    }
}

/// The bindings with an action (by expression and binding) that some path leaves undone.
/// Moves consume a binding; completed closes and replacements handle its old close outcome.
/// Actions occur after the expression's operands have finished evaluating.
pub fn conditional(
    m: &ModuleHir,
    c: &Callable,
    actions: &HashSet<(NodeId, usize)>,
) -> HashSet<usize> {
    let mut p = Pass {
        m,
        actions: actions
            .iter()
            .fold(HashMap::new(), |mut actions, &(node, uid)| {
                actions.entry(node).or_insert_with(Vec::new).push(uid);
                actions
            }),
        tracked: actions.iter().map(|(_, u)| *u).collect(),
        out: HashSet::new(),
        breaks: Vec::new(),
        continues: Vec::new(),
    };
    let must = match c.body() {
        Body::Block(body) => p.block(body, Must::new()),
        Body::Expr(e) => {
            let mut must = Must::new();
            p.expr(e, &mut must);
            must
        }
    };
    for b in c.self_binding.iter().chain(c.parameters.iter()) {
        p.define(b.uid, &must);
    }
    p.out
}

struct Pass<'a> {
    m: &'a ModuleHir,
    actions: HashMap<NodeId, Vec<usize>>,
    /// Bindings with at least one tracked action.
    tracked: HashSet<usize>,
    out: HashSet<usize>,
    breaks: Vec<Must>,
    continues: Vec<Must>,
}

impl Pass<'_> {
    /// The declaration of `uid`: some path leaves its lifetime without a tracked action.
    fn define(&mut self, uid: usize, must: &Must) {
        if self.tracked.contains(&uid) && !must.contains(&uid) {
            self.out.insert(uid);
        }
    }

    fn define_pattern(&mut self, p: &Pattern, must: &mut Must) {
        match &p.kind {
            PatternKind::Name(_) => {
                if let Some(b) = self.m.pattern_binding(p) {
                    self.define(b.uid, must);
                    must.remove(&b.uid);
                }
            }
            PatternKind::List(items) => items.iter().for_each(|i| self.define_pattern(i, must)),
            PatternKind::Type(fields) => fields
                .iter()
                .for_each(|f| self.define_pattern(&f.pattern, must)),
        }
    }

    fn block(&mut self, body: &[Stmt], mut must: Must) -> Must {
        for s in body.iter().rev() {
            must = self.stmt(s, must);
        }
        must
    }

    fn stmt(&mut self, s: &Stmt, mut must: Must) -> Must {
        match &s.kind {
            StmtKind::Bind { pattern, value, .. } => {
                self.define_pattern(pattern, &mut must);
                self.expr(value, &mut must);
            }
            StmtKind::Assign { target, value, .. } => {
                match target {
                    // The store defines a new value, kept to the scope end unless every path
                    // after it moves it; the old value's life ends here.
                    AssignTarget::Name(_) => {
                        if let Some(b) = self.m.assigned(value) {
                            self.define(b.uid, &must);
                            must.remove(&b.uid);
                        }
                    }
                    AssignTarget::Member(t) => self.expr(t, &mut must),
                }
                self.expr(value, &mut must);
            }
            StmtKind::Call(e) => self.expr(e, &mut must),
            StmtKind::Return(e) => {
                must = Must::new();
                if let Some(e) = e {
                    self.expr(e, &mut must);
                }
            }
            StmtKind::Break => must = self.breaks.last().cloned().unwrap_or_default(),
            StmtKind::Continue => must = self.continues.last().cloned().unwrap_or_default(),
            StmtKind::If {
                binding,
                cond,
                mutable: _,
                body,
                else_body,
            } => {
                let mut then = self.block(body, must.clone());
                if let Some(p) = binding {
                    self.define_pattern(p, &mut then);
                }
                let otherwise = self.block(else_body, must);
                let mut joined = Some(then);
                meet(&mut joined, otherwise);
                must = joined.unwrap_or_default();
                self.expr(cond, &mut must);
            }
            StmtKind::While { cond, body } => {
                must = self.looping(Some(cond), None, None, body, must);
            }
            StmtKind::For { .. } if self.m.stmt(s).expansion.is_some() => {
                let expansion = self.m.stmt(s).expansion.unwrap_or_default();
                must = self.block(&expansion, must);
            }
            StmtKind::For { iter, body, .. } => {
                let variable = self.m.stmt(s).loop_binding;
                must = self.looping(None, Some(iter), variable.map(|b| b.uid), body, must);
            }
        }
        must
    }

    /// A loop: the body may run any number of times, so a move inside it is certain only when
    /// the paths that skip or leave the loop are certain too.
    fn looping(
        &mut self,
        cond: Option<&Expr>,
        iter: Option<&Expr>,
        defined: Option<usize>,
        body: &[Stmt],
        after: Must,
    ) -> Must {
        let mut head = after.clone();
        loop {
            self.breaks.push(after.clone());
            self.continues.push(head.clone());
            let mut entry = self.block(body, head.clone());
            self.continues.pop();
            self.breaks.pop();
            if let Some(uid) = defined {
                self.define(uid, &entry);
                entry.remove(&uid);
            }
            // The loop may not run at all, or stop before this iteration.
            entry.retain(|u| after.contains(u));
            if let Some(c) = cond {
                self.expr(c, &mut entry);
            }
            let before = head.len();
            head.retain(|u| entry.contains(u));
            if head.len() == before {
                break;
            }
        }
        let mut must = head;
        if let Some(i) = iter {
            self.expr(i, &mut must);
        }
        must
    }

    /// Walks an expression backwards: children in reverse evaluation order.
    fn expr(&mut self, e: &Expr, must: &mut Must) {
        // Reverse evaluation order: a completed action follows every operand. A `try` in
        // an operand can still exit before this action, clearing it below.
        if let Some(bindings) = self.actions.get(&e.id) {
            must.extend(bindings);
        }
        match &e.kind {
            ExprKind::Number(_) | ExprKind::Bool(_) | ExprKind::Unit => {}
            ExprKind::Text(parts) => {
                for part in parts.iter().rev() {
                    if let TextPart::Interp(i) = part {
                        self.expr(i, must);
                    }
                }
            }
            ExprKind::Name(_) => {}
            ExprKind::Member { left, .. } => self.expr(left, must),
            ExprKind::Apply { left, value, .. } => {
                if let Some(v) = value {
                    self.expr(v, must);
                }
                self.expr(left, must);
            }
            ExprKind::Index { left, index } => {
                self.expr(index, must);
                self.expr(left, must);
            }
            ExprKind::Probe(target) => self.expr(target, must),
            ExprKind::List(items) => items.iter().rev().for_each(|i| self.expr(i, must)),
            ExprKind::Map(entries) => {
                for entry in entries.iter().rev() {
                    self.expr(&entry.value, must);
                    self.expr(&entry.key, must);
                }
            }
            ExprKind::Unary { op, operand } => {
                if *op == UnaryOp::Try {
                    // An error leaves the function here, before any later move.
                    must.clear();
                }
                self.expr(operand, must);
            }
            ExprKind::Binary { op, left, right } => {
                if matches!(op, BinaryOp::And | BinaryOp::Or) {
                    // The right operand runs on some paths only.
                    let skipped = must.clone();
                    self.expr(right, must);
                    must.retain(|u| skipped.contains(u));
                } else {
                    self.expr(right, must);
                }
                self.expr(left, must);
            }
            ExprKind::Lambda(l) => self.lambda(e, l),
            ExprKind::Call { callee, args } => {
                for a in args.iter().rev() {
                    self.expr(&a.value, must);
                }
                self.expr(callee, must);
            }
            ExprKind::Match { scrutinee, arms } => {
                let after = must.clone();
                let mut joined: Option<Must> = None;
                for arm in arms.iter().rev() {
                    let mut arm_must = after.clone();
                    if let Some(v) = &arm.value {
                        self.expr(v, &mut arm_must);
                    }
                    arm_must = self.block(&arm.body, arm_must);
                    for b in self.m.arm(arm).bindings.iter().flatten() {
                        self.define(b.uid, &arm_must);
                        arm_must.remove(&b.uid);
                    }
                    meet(&mut joined, arm_must);
                }
                *must = joined.unwrap_or_default();
                self.expr(scrutinee, must);
            }
        }
    }

    /// A lambda moves the captures it owns when it is built; its body is a scope of its own.
    fn lambda(&mut self, e: &Expr, l: &Lambda) {
        let saved = (
            std::mem::take(&mut self.breaks),
            std::mem::take(&mut self.continues),
        );
        let inner = self.block(&l.body, Must::new());
        for b in self.m.lambda_parameters(e) {
            self.define(b.uid, &inner);
        }
        (self.breaks, self.continues) = saved;
    }
}
