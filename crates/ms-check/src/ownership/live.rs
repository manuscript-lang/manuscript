//! Backward liveness of local bindings: which uses are the last on every path.
//!
//! The ownership walk asks this oracle whether a move is the final use of a
//! binding. A use is **last** when no later use of the same value can run:
//! reassigning a binding ends the old value's life, a loop keeps reads alive
//! until the final iteration, and a scope-closed resource and a closure's captured
//! variables stay live to the end of their scope.
//!
//! Liveness is kept per place: a binding and a path of fields (`b`, `b.items`). `uses` answers for
//! the whole binding (is any part of it used later), and `places` answers for the place a
//! field-path read names (is it, a prefix of it or an extension of it used later).

use crate::hir::*;
use crate::types::*;
use ms_syntax::ast::*;
use std::collections::HashMap;

/// Liveness of one use.
#[derive(Copy, Clone, Debug)]
pub struct UseLive {
    /// No later use of the value can run.
    pub last: bool,
    /// The earliest later use, for diagnostics.
    pub next: Option<NodeId>,
}

/// Per-use liveness of one callable, keyed by (node, binding identity).
#[derive(Default)]
pub struct Liveness {
    /// Name uses, and lambda creations for captures.
    pub uses: HashMap<(NodeId, usize), UseLive>,
    /// Field-path reads (`b.f.g`, by the outermost member expression and the root binding): no
    /// later use of the place, a prefix of it or an extension of it can run.
    pub places: HashMap<(NodeId, usize), UseLive>,
}

/// A live place: a binding identity and the fields below it.
type Key = (usize, Vec<Name>);

/// Places live after a point, each with its earliest later use.
type Live = HashMap<Key, NodeId>;

/// Whether one path is a prefix of the other.
fn related(a: &[Name], b: &[Name]) -> bool {
    a.iter().zip(b).all(|(x, y)| x == y)
}

/// Marks the last step of a key as a store: the place is overwritten there, not read.
fn store_step() -> Name {
    n("=")
}

/// The earliest later use of `uid` at a place related to `path`. A store counts for the whole
/// binding (`path` empty: assigning a field uses the binding) but not for a place: overwriting
/// `b.f` does not read the `b.f` an earlier move took.
fn next_use(live: &Live, uid: usize, path: &[Name]) -> Option<NodeId> {
    let store = store_step();
    live.iter()
        .filter(|((u, p), _)| {
            *u == uid && related(p, path) && (path.is_empty() || p.last() != Some(&store))
        })
        .map(|(_, n)| *n)
        .min()
}

/// The binding and fields a chain of member reads names, with the root name's node.
fn field_chain<'a>(m: &ModuleHir, e: &'a Expr) -> Option<(&'a Expr, BindingRef, Vec<Name>)> {
    let mut path = Vec::new();
    let mut at = e;
    while let ExprKind::Member { left, name } = &at.kind {
        path.push(*name);
        at = left;
    }
    path.reverse();
    match (&at.kind, m.resolution(at)) {
        (ExprKind::Name(_), Resolution::Local(b)) if !path.is_empty() => Some((at, b, path)),
        _ => None,
    }
}

fn join(into: &mut Live, from: &Live) {
    for (k, v) in from {
        into.entry(k.clone())
            .and_modify(|n| {
                if v.0 < n.0 {
                    *n = *v;
                }
            })
            .or_insert(*v);
    }
}

/// Computes liveness of a callable body.
pub fn liveness(m: &ModuleHir, c: &Callable) -> Liveness {
    let mut p = Pass {
        m,
        out: Liveness::default(),
        breaks: Vec::new(),
        continues: Vec::new(),
        exit: Live::new(),
    };
    match c.body() {
        Body::Block(body) => {
            p.block(body, Live::new());
        }
        Body::Expr(e) => p.expr(e, &mut Live::new()),
    }
    p.out
}

struct Pass<'a> {
    m: &'a ModuleHir,
    out: Liveness,
    breaks: Vec<Live>,
    continues: Vec<Live>,
    /// Live at `return`: resources of enclosing scopes, and the captured
    /// variables inside a lambda.
    exit: Live,
}

impl Pass<'_> {
    fn record(&mut self, node: NodeId, b: &BindingRef, live: &mut Live) {
        self.record_at(node, node, b, Vec::new(), live);
    }

    /// A use of the place `path` below `b`, named by the expression `node` (the root name for the
    /// binding's own table, `place_node` for the place table).
    fn record_at(
        &mut self,
        node: NodeId,
        place_node: NodeId,
        b: &BindingRef,
        path: Vec<Name>,
        live: &mut Live,
    ) {
        let next = next_use(live, b.uid, &[]);
        self.out.uses.insert(
            (node, b.uid),
            UseLive {
                last: next.is_none(),
                next,
            },
        );
        let near = next_use(live, b.uid, &path);
        self.out.places.insert(
            (place_node, b.uid),
            UseLive {
                last: near.is_none(),
                next: near,
            },
        );
        live.insert((b.uid, path), node);
    }

    /// The store to `uid` ends the life of the old value of the whole binding.
    fn kill(live: &mut Live, uid: usize) {
        live.retain(|(u, _), _| *u != uid);
    }

    fn block(&mut self, body: &[Stmt], mut live: Live) -> Live {
        for s in body.iter().rev() {
            live = self.stmt(s, live);
        }
        live
    }

    fn stmt(&mut self, s: &Stmt, mut live: Live) -> Live {
        match &s.kind {
            StmtKind::Bind { pattern, value, .. } => {
                self.define_pattern(pattern, &mut live);
                self.expr(value, &mut live);
            }
            StmtKind::Assign { target, value, .. } => {
                match target {
                    AssignTarget::Name(_) => {
                        if let Some(b) = self.m.assigned(value) {
                            // The store ends the old value's life.
                            Self::kill(&mut live, b.uid);
                        }
                    }
                    AssignTarget::Member(t) => {
                        if let Some((root, b, mut path)) = field_chain(self.m, t) {
                            // The store ends the life of what the place held, and of the parts
                            // below it; the binding itself is used.
                            live.retain(|(u, p), _| *u != b.uid || !p.starts_with(&path));
                            path.push(store_step());
                            self.record_at(root.id, t.id, &b, path, &mut live);
                        } else {
                            self.expr(t, &mut live);
                        }
                    }
                }
                self.expr(value, &mut live);
            }
            StmtKind::Call(e) => self.expr(e, &mut live),
            StmtKind::Return(e) => {
                live = self.exit.clone();
                if let Some(e) = e {
                    self.expr(e, &mut live);
                }
            }
            StmtKind::Break => live = self.breaks.last().cloned().unwrap_or_default(),
            StmtKind::Continue => live = self.continues.last().cloned().unwrap_or_default(),
            StmtKind::If {
                binding,
                cond,
                mutable: _,
                body,
                else_body,
            } => {
                let mut joined = self.block(body, live.clone());
                if let Some(p) = binding {
                    self.define_pattern(p, &mut joined);
                }
                join(&mut joined, &self.block(else_body, live));
                live = joined;
                self.expr(cond, &mut live);
            }
            StmtKind::While { cond, body } => {
                live = self.looping(Some(cond), None, None, body, live)
            }
            StmtKind::For { .. } if self.m.stmt(s).expansion.is_some() => {
                let expansion = self.m.stmt(s).expansion.unwrap_or_default();
                live = self.block(&expansion, live);
            }
            StmtKind::For { iter, body, .. } => {
                let variable = self.m.stmt(s).loop_binding;
                live = self.looping(None, Some(iter), variable.map(|b| b.uid), body, live);
            }
        }
        live
    }

    fn define_pattern(&mut self, p: &Pattern, live: &mut Live) {
        match &p.kind {
            PatternKind::Name(_) => {
                if let Some(b) = self.m.pattern_binding(p) {
                    Self::kill(live, b.uid);
                }
            }
            PatternKind::List(items) => items.iter().for_each(|i| self.define_pattern(i, live)),
            PatternKind::Record(fields) => fields
                .iter()
                .for_each(|f| self.define_pattern(&f.pattern, live)),
        }
    }

    /// A loop head fixpoint: the next iteration's reads keep bindings live.
    fn looping(
        &mut self,
        cond: Option<&Expr>,
        iter: Option<&Expr>,
        defined: Option<usize>,
        body: &[Stmt],
        after: Live,
    ) -> Live {
        let mut head = after.clone();
        loop {
            self.breaks.push(after.clone());
            self.continues.push(head.clone());
            let mut entry = self.block(body, head.clone());
            self.continues.pop();
            self.breaks.pop();
            // The loop variable is defined per iteration, inside the loop.
            if let Some(uid) = defined {
                Self::kill(&mut entry, uid);
            }
            join(&mut entry, &after);
            if let Some(c) = cond {
                self.expr(c, &mut entry);
            }
            let before = head.len();
            join(&mut head, &entry);
            if head.len() == before {
                break;
            }
        }
        let mut live = head;
        if let Some(i) = iter {
            self.expr(i, &mut live);
        }
        live
    }

    /// Walks an expression backwards: children in reverse evaluation order.
    fn expr(&mut self, e: &Expr, live: &mut Live) {
        match &e.kind {
            ExprKind::Number(_) | ExprKind::Bool(_) | ExprKind::Unit => {}
            ExprKind::Text(parts) => {
                for part in parts.iter().rev() {
                    if let TextPart::Interp(i) = part {
                        self.expr(i, live);
                    }
                }
            }
            ExprKind::Name(_) => {
                if let Resolution::Local(b) = self.m.resolution(e) {
                    self.record(e.id, &b, live);
                }
            }
            ExprKind::Member { left, .. } => {
                if let Some((root, b, path)) = field_chain(self.m, e) {
                    self.record_at(root.id, e.id, &b, path, live);
                } else {
                    self.expr(left, live);
                }
            }
            ExprKind::Apply { left, value, .. } => {
                if let Some(v) = value {
                    self.expr(v, live);
                }
                self.expr(left, live);
            }
            ExprKind::Index { left, index } => {
                self.expr(index, live);
                self.expr(left, live);
            }
            ExprKind::Probe(target) => self.expr(target, live),
            ExprKind::List(items) => items.iter().rev().for_each(|i| self.expr(i, live)),
            ExprKind::Map(entries) => {
                for entry in entries.iter().rev() {
                    self.expr(&entry.value, live);
                    self.expr(&entry.key, live);
                }
            }
            ExprKind::Unary { operand, .. } => self.expr(operand, live),
            ExprKind::Binary { op, left, right } => {
                if matches!(op, BinaryOp::And | BinaryOp::Or) {
                    // The right operand runs on some paths only.
                    let skipped = live.clone();
                    self.expr(right, live);
                    join(live, &skipped);
                } else {
                    self.expr(right, live);
                }
                self.expr(left, live);
            }
            ExprKind::Lambda(l) => self.lambda(e, l, live),
            ExprKind::Call { callee, args } => {
                for a in args.iter().rev() {
                    self.expr(&a.value, live);
                }
                self.expr(callee, live);
            }
            ExprKind::Match { scrutinee, arms } => {
                let after = live.clone();
                let mut joined = Live::new();
                for arm in arms.iter().rev() {
                    let mut arm_live = after.clone();
                    if let Some(v) = &arm.value {
                        self.expr(v, &mut arm_live);
                    }
                    arm_live = self.block(&arm.body, arm_live);
                    for b in self.m.arm(arm).bindings.iter().flatten() {
                        Self::kill(&mut arm_live, b.uid);
                    }
                    join(&mut joined, &arm_live);
                }
                *live = joined;
                self.expr(scrutinee, live);
            }
        }
    }

    fn lambda(&mut self, e: &Expr, l: &Lambda, live: &mut Live) {
        let captures = self.m.captures(e);
        // The closure may run again, so its captured variables never die in its body.
        let captured: Live = captures
            .iter()
            .map(|b| ((b.uid, Vec::new()), e.id))
            .collect();
        let saved = (
            std::mem::replace(&mut self.exit, captured.clone()),
            std::mem::take(&mut self.breaks),
            std::mem::take(&mut self.continues),
        );
        self.block(&l.body, captured);
        (self.exit, self.breaks, self.continues) = saved;
        for b in &captures {
            self.record(e.id, b, live);
        }
    }
}
