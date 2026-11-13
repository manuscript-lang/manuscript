//! Faults that constant operands make certain: integer overflow, division by
//! zero, an index outside a list literal and locking a `Shared` twice.

use crate::checker::Checker;
use crate::fxmap::HashMap;
use crate::types::*;
use ms_syntax::ast::*;
use std::cell::RefCell;

/// Memoized facts about arithmetic trees over literals, keyed by file and node. Each fact of a
/// node reads only the facts of its operands, so every node is visited once however deep the tree.
#[derive(Default)]
pub(crate) struct LiteralFacts {
    folded: RefCell<HashMap<Folding, Option<i128>>>,
    fractional: RefCell<HashMap<(Name, NodeId), Option<bool>>>,
}

/// A node folded within an inclusive value range.
type Folding = (Name, NodeId, i128, i128);

impl Checker {
    /// The value of an integer expression built from literals and `+ - * / %`, or none when an
    /// operand is not constant, a division is by zero, or an intermediate leaves `range`.
    pub(crate) fn fold(&self, e: &Expr, range: (i128, i128)) -> Option<i128> {
        let key = (self.current_file(), e.id, range.0, range.1);
        if let Some(&known) = self.literal_facts.folded.borrow().get(&key) {
            return known;
        }
        let fits = |v: i128| (range.0..=range.1).contains(&v).then_some(v);
        let value = match &e.kind {
            ExprKind::Number(t) => ms_syntax::number::canonical(self.syms.str(t))
                .parse::<i128>()
                .ok(),
            ExprKind::Unary { op, operand } => self.fold(operand, range).and_then(|v| match op {
                UnaryOp::Neg => fits(-v),
                UnaryOp::Plus => Some(v),
                _ => None,
            }),
            ExprKind::Binary { op, left, right } => {
                let a = self.fold(left, range);
                let b = self.fold(right, range);
                a.zip(b).and_then(|(a, b)| fits(apply(*op, a, b)?))
            }
            _ => None,
        };
        self.literal_facts.folded.borrow_mut().insert(key, value);
        value
    }

    /// Whether `e` is a plain literal or arithmetic over plain literals only, and if so whether its
    /// literals are fractional. Mixed integer and fractional literals have no common kind.
    pub(crate) fn literal_tree_fractional(&self, e: &Expr) -> Option<bool> {
        let key = (self.current_file(), e.id);
        if let Some(&known) = self.literal_facts.fractional.borrow().get(&key) {
            return known;
        }
        let kind = match &e.kind {
            ExprKind::Number(t) => {
                let text = ms_syntax::number::canonical(self.syms.str(t));
                (!ms_syntax::number::is_decimal(&text))
                    .then(|| ms_syntax::number::is_fractional(&text))
            }
            ExprKind::Unary {
                op: UnaryOp::Neg | UnaryOp::Plus,
                operand,
            } => self.literal_tree_fractional(operand),
            ExprKind::Binary {
                op: BinaryOp::Add | BinaryOp::Sub | BinaryOp::Mul | BinaryOp::Div | BinaryOp::Rem,
                left,
                right,
            } => {
                let l = self.literal_tree_fractional(left);
                let r = self.literal_tree_fractional(right);
                l.zip(r).and_then(|(l, r)| (l == r).then_some(l))
            }
            _ => None,
        };
        self.literal_facts.fractional.borrow_mut().insert(key, kind);
        kind
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
        if matches!(op, BinaryOp::Div | BinaryOp::Rem) && self.fold(right, range) == Some(0) {
            self.type_error(
                e.pos,
                "division by zero always faults; guard the divisor or use a nonzero constant",
            );
            return;
        }
        let (Some(a), Some(b)) = (self.fold(left, range), self.fold(right, range)) else {
            return;
        };
        if apply(op, a, b).is_some_and(|v| !(range.0..=range.1).contains(&v)) {
            self.type_error(
                e.pos,
                format!(
                    "{a} {} {b} overflows {ty_t} and always faults; use a smaller value or a wider type such as BigInt",
                    op.as_str()
                , ty_t = ty.display(self.syms)),
            );
        }
    }

    /// Reports a constant index outside a list literal.
    pub(crate) fn constant_index(&mut self, e: &Expr, left: &Expr, index: &Expr) {
        let ExprKind::List(items) = &left.kind else {
            return;
        };
        let Some(i) = self.fold(index, int_range(&int()).unwrap_or_default()) else {
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
