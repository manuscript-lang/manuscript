//! Constant list literals that a loop iterates are built once, before the outermost loop.
//!
//! `for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:` inside a loop allocated five lists and freed
//! them on every pass (about 50 ns), the direction tables of grid searches. The literal has no
//! free variables, so it is the same value on every pass: the outermost enclosing loop builds
//! it into a hidden local that the loop's scope drops, and the inner `for` borrows it.

use crate::Error;
use crate::func::FnLower;
use ms_check::api::NodeId;
use ms_check::api::ast::{Expr, ExprKind, Stmt, StmtKind};
use ms_check::api::visit::{self, Visitor};

/// Literals with more items than this are left to be built where they are written.
const MAX_ITEMS: usize = 32;

impl FnLower<'_> {
    /// A non-empty list literal of constant scalars, or of such lists.
    fn constant_literal(&self, e: &Expr, nested: bool) -> bool {
        let ExprKind::List(items) = &e.kind else {
            return false;
        };
        !items.is_empty()
            && items.len() <= MAX_ITEMS
            && items.iter().all(|it| {
                self.const_scalar(it).is_some() || (!nested && self.constant_literal(it, true))
            })
    }

    /// Builds the constant literals that `for` statements in `body` (outside closures) iterate,
    /// when no loop encloses this one, into hidden locals of the current scope.
    pub(crate) fn hoist_literals(&mut self, body: &[Stmt]) -> Result<(), Error> {
        if !self.loops.is_empty() {
            return Ok(());
        }
        struct Find<'a, 'b> {
            fl: &'a FnLower<'b>,
            lambdas: usize,
            found: Vec<Expr>,
        }
        impl Visitor for Find<'_, '_> {
            fn stmt(&mut self, s: &Stmt) {
                if let StmtKind::For { iter, .. } = &s.kind
                    && self.lambdas == 0
                    && self.fl.constant_literal(iter, false)
                {
                    self.found.push(iter.clone());
                }
            }
            fn expr(&mut self, e: &Expr) {
                if matches!(e.kind, ExprKind::Lambda(_)) {
                    self.lambdas += 1;
                }
            }
            fn leave_expr(&mut self, e: &Expr) {
                if matches!(e.kind, ExprKind::Lambda(_)) {
                    self.lambdas -= 1;
                }
            }
        }
        let mut find = Find {
            fl: self,
            lambdas: 0,
            found: Vec::new(),
        };
        visit::walk_block(&mut find, body);
        let found = find.found;
        for lit in found {
            let id: NodeId = lit.id;
            if self.hoisted.contains_key(&id) {
                continue;
            }
            let v = self.expr(&lit)?;
            if self.dead {
                return Ok(());
            }
            let var = self.bind_hidden(v);
            self.hoisted.insert(id, var);
        }
        Ok(())
    }
}
