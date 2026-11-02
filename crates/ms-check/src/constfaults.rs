//! Faults that constant operands make certain: integer overflow, division by
//! zero, an index outside a list literal and locking a `Shared` twice.

use crate::checker::Checker;
use crate::types::*;
use ms_syntax::ast::*;

/// The value of an integer expression built from literals and `+ - * / %`, or none when an
/// operand is not constant, a division is by zero, or an intermediate leaves `range`.
fn fold(e: &Expr, range: (i128, i128)) -> Option<i128> {
    let fits = |v: i128| (range.0..=range.1).contains(&v).then_some(v);
    match &e.kind {
        ExprKind::Number(t) if !t.as_str().contains(['.', 'e', 'E']) && !t.ends_with('d') => {
            ms_syntax::number::canonical(t.as_str())
                .parse::<i128>()
                .ok()
        }
        ExprKind::Unary { op, operand } => {
            let v = fold(operand, range)?;
            match op {
                UnaryOp::Neg => fits(-v),
                UnaryOp::Plus => Some(v),
                _ => None,
            }
        }
        ExprKind::Binary { op, left, right } => {
            let (a, b) = (fold(left, range)?, fold(right, range)?);
            fits(apply(*op, a, b)?)
        }
        _ => None,
    }
}

fn apply(op: BinaryOp, a: i128, b: i128) -> Option<i128> {
    match op {
        BinaryOp::Add => a.checked_add(b),
        BinaryOp::Sub => a.checked_sub(b),
        BinaryOp::Mul => a.checked_mul(b),
        BinaryOp::Div => a.checked_div(b),
        BinaryOp::Rem => a.checked_rem(b),
        _ => None,
    }
}

impl Checker {
    /// Reports `left op right` over integers of `ty` when constant operands make it fault.
    pub(crate) fn constant_arithmetic(
        &mut self,
        e: &Expr,
        op: BinaryOp,
        left: &Expr,
        right: &Expr,
        ty: &Ty,
    ) {
        let Some(range) = int_range(ty) else {
            return;
        };
        if matches!(op, BinaryOp::Div | BinaryOp::Rem) && fold(right, range) == Some(0) {
            self.type_error(
                e.pos,
                "division by zero always faults; guard the divisor or use a nonzero constant",
            );
            return;
        }
        let (Some(a), Some(b)) = (fold(left, range), fold(right, range)) else {
            return;
        };
        if apply(op, a, b).is_some_and(|v| !(range.0..=range.1).contains(&v)) {
            self.type_error(
                e.pos,
                format!(
                    "{a} {} {b} overflows {ty} and always faults; use a smaller value or a wider type such as BigInt",
                    op.as_str()
                ),
            );
        }
    }

    /// Reports a constant index outside a list literal.
    pub(crate) fn constant_index(&mut self, e: &Expr, left: &Expr, index: &Expr) {
        let ExprKind::List(items) = &left.kind else {
            return;
        };
        let Some(i) = fold(index, int_range(&int()).unwrap_or_default()) else {
            return;
        };
        let len = items.len() as i128;
        if i >= len || i < -len {
            self.type_error(
                e.pos,
                format!(
                    "index {i} is outside this list literal of {len} element(s) and always faults"
                ),
            );
        }
    }
}

/// The written place `a` or `a.b.c`, or none for any other expression.
fn place_text(e: &Expr) -> Option<String> {
    match &e.kind {
        ExprKind::Name(name) => Some(name.as_str().to_string()),
        ExprKind::Member { left, name } => Some(format!("{}.{}", place_text(left)?, name.as_str())),
        _ => None,
    }
}

impl Checker {
    /// Tracks `let guard = lock(box)` until its scope ends or `guard.close()` runs, and rejects
    /// locking the same written place again meanwhile, which waits on itself forever. Returns
    /// whether a lock was pushed; `block` pops it when the scope ends.
    pub(crate) fn begin_lock(&mut self, s: &Stmt, guard: Name, value: &Expr, ty: &Ty) -> bool {
        let ExprKind::Call { args, .. } = &value.kind else {
            return false;
        };
        if !ty.is_source_type("@std/concurrency/sync.ms", "SharedGuard") {
            return false;
        }
        let Some(place) = args.first().and_then(|a| place_text(&a.value)) else {
            return false;
        };
        let function = self.function;
        if self
            .held_locks
            .iter()
            .any(|(f, p, _)| *f == function && *p == place)
        {
            self.type_error(
                s.pos,
                format!(
                    "{place} is already locked by an earlier guard that is still open, so locking it again waits on itself forever; use that guard's value, or call its close() first"
                ),
            );
            return false;
        }
        self.held_locks.push((function, place, guard));
        true
    }
}
