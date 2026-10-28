//! A resource closed at scope end whose type can report a failure only through a
//! separate method (`MSL114`): `close` cannot return an error, so a failed write
//! surfaces only if the binding is flushed first.

use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::editor::{MemberKind, members};
use ms_check::types::{Name, Ty, n};
use ms_check::{ModuleData, Program};
use ms_syntax::ast::*;
use ms_syntax::visit::Visitor;
use std::collections::{HashMap, HashSet};

/// Zero-argument methods that return a `Result` and make earlier writes durable.
const FINISHERS: [&str; 3] = ["flush", "sync", "commit"];

pub(super) fn lint(program: &Program, module: &ModuleData, findings: &mut Vec<Finding>) {
    let mut scan = Scan {
        module,
        moves: &program.close_moves,
        owned: Vec::new(),
        finished: HashSet::new(),
        kept: HashSet::new(),
    };
    walk_module(module, &mut scan);
    let file = module_file(module);
    for (uid, name, pos, ty) in scan.owned {
        // A binding every path moves is left alone: the new owner reports the close.
        let kept = !program.close_moves.contains_key(&uid) || scan.kept.contains(&uid);
        if scan.finished.contains(&uid) || !program.implicit_closes.contains(&uid) || !kept {
            continue;
        }
        let Some(method) = finisher(program, module, &ty) else {
            continue;
        };
        findings.push(finding(
            "MSL114",
            format!(
                "`{name}` is closed when its scope ends, and close cannot report a failure; call `try {name}.{method}()` before the scope ends to see one"
            ),
            &file,
            pos,
        ));
    }
}

/// The first finisher `ty` offers: no parameters, returning a `Result`.
fn finisher(program: &Program, module: &ModuleData, ty: &Ty) -> Option<Name> {
    members(program, ty, Some(module.file))
        .into_iter()
        .find(|m| {
            m.kind == MemberKind::Method
                && FINISHERS.iter().any(|f| m.name == n(f))
                && m.ty.params.is_empty()
                && m.ty.result_ty().is_std("Result")
        })
        .map(|m| m.name)
}

struct Scan<'a> {
    module: &'a ModuleData,
    /// The name expressions that move each conditionally moved closing binding.
    moves: &'a HashMap<usize, HashSet<NodeId>>,
    /// Conditionally moved bindings that some path closes at scope end.
    kept: HashSet<usize>,
    /// Bindings with an implicit-close cleanup: identity, name, position, type.
    owned: Vec<(usize, Name, ms_syntax::Pos, Ty)>,
    /// Bindings a finisher is called on.
    finished: HashSet<usize>,
}

impl Visitor for Scan<'_> {
    fn block(&mut self, body: &[Stmt]) {
        let facts = self.module.facts();
        for (i, s) in body.iter().enumerate() {
            let StmtKind::Bind { pattern, .. } = &s.kind else {
                continue;
            };
            let Some(b) = facts.patterns.get(&pattern.id) else {
                continue;
            };
            let Some(moves) = self.moves.get(&b.uid) else {
                continue;
            };
            let mut flow = Flow { moves, kept: false };
            if flow.run(&body[i + 1..], false, 0) == Held::Yes {
                flow.kept = true;
            }
            if flow.kept {
                self.kept.insert(b.uid);
            }
        }
    }

    fn stmt(&mut self, stmt: &Stmt) {
        let StmtKind::Bind { pattern, .. } = &stmt.kind else {
            return;
        };
        if !matches!(pattern.kind, PatternKind::Name(_)) {
            return;
        }
        let facts = self.module.facts();
        let Some(b) = facts.patterns.get(&pattern.id) else {
            return;
        };
        if facts
            .stmts
            .get(&stmt.id)
            .is_some_and(|f| f.cleanup.is_some())
        {
            self.owned.push((b.uid, b.name, pattern.pos, b.ty.clone()));
        }
    }

    fn expr(&mut self, e: &Expr) {
        let ExprKind::Call { callee, .. } = &e.kind else {
            return;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return;
        };
        if !FINISHERS.iter().any(|f| *name == n(f)) {
            return;
        }
        if let Some(b) = self
            .module
            .facts()
            .info(left.id)
            .and_then(|i| i.binding.clone())
        {
            self.finished.insert(b.uid);
        }
    }
}

/// Whether the binding still holds its resource at a point of the flow.
#[derive(Clone, Copy, PartialEq)]
enum Held {
    Yes,
    No,
    /// Control does not continue here (a `return`, or a `break` out of the analysed block).
    Gone,
}

/// Follows the statements after a binding to find whether some path reaches the end of its
/// scope with the resource still held, which is where the scope closes it.
struct Flow<'a> {
    moves: &'a HashSet<NodeId>,
    kept: bool,
}

impl Flow<'_> {
    /// Runs `body` starting with the resource held (`moved` false) or moved; `depth` counts the
    /// loops entered since the binding's block, whose `break` and `continue` stay inside it.
    fn run(&mut self, body: &[Stmt], moved: bool, depth: u32) -> Held {
        let mut state = if moved { Held::No } else { Held::Yes };
        for s in body {
            state = self.stmt(s, state, depth);
            if state == Held::Gone {
                return Held::Gone;
            }
        }
        state
    }

    fn stmt(&mut self, s: &Stmt, state: Held, depth: u32) -> Held {
        let own = |e: &Expr| self.has_move(e);
        let after = |moved: bool| {
            if moved { Held::No } else { state }
        };
        match &s.kind {
            StmtKind::Bind { value, .. } => after(own(value)),
            StmtKind::Assign { target, value, .. } => {
                let target_moves = matches!(target, AssignTarget::Member(t) if own(t));
                after(own(value) || target_moves)
            }
            StmtKind::Call(e) => after(own(e)),
            StmtKind::Return(e) => {
                let moved = e.as_ref().is_some_and(own);
                if state == Held::Yes && !moved {
                    self.kept = true;
                }
                Held::Gone
            }
            StmtKind::Break | StmtKind::Continue => {
                if depth == 0 && state == Held::Yes {
                    self.kept = true;
                }
                if depth == 0 { Held::Gone } else { state }
            }
            StmtKind::If {
                cond,
                body,
                else_body,
                ..
            } => {
                let state = if own(cond) { Held::No } else { state };
                let then = self.branch(body, state, depth);
                let other = self.branch(else_body, state, depth);
                match (then, other) {
                    (Held::Gone, x) | (x, Held::Gone) => x,
                    (Held::No, Held::No) => Held::No,
                    _ => Held::Yes,
                }
            }
            StmtKind::While { cond, body } => {
                let state = if own(cond) { Held::No } else { state };
                self.branch(body, state, depth + 1);
                state
            }
            StmtKind::For { iter, body, .. } => {
                let state = if own(iter) { Held::No } else { state };
                self.branch(body, state, depth + 1);
                state
            }
            StmtKind::With { value, body, .. } => {
                let state = if own(value) { Held::No } else { state };
                self.branch(body, state, depth)
            }
        }
    }

    fn branch(&mut self, body: &[Stmt], state: Held, depth: u32) -> Held {
        let mut at = state;
        for s in body {
            at = self.stmt(s, at, depth);
            if at == Held::Gone {
                break;
            }
        }
        at
    }

    fn has_move(&self, e: &Expr) -> bool {
        struct Find<'a> {
            moves: &'a HashSet<NodeId>,
            found: bool,
        }
        impl Visitor for Find<'_> {
            fn expr(&mut self, e: &Expr) {
                self.found |= self.moves.contains(&e.id);
            }
        }
        let mut find = Find {
            moves: self.moves,
            found: false,
        };
        ms_syntax::visit::walk_expr(&mut find, e);
        find.found
    }
}
