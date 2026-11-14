//! One-scalar strings kept as their code point.
//!
//! `text.get(i) == "+"`, `c >= "0"` and `for c in text.chars(): if c == " "` read a character
//! only to compare it with a one-character literal. Such a comparison is an integer compare on
//! the code point (UTF-8 byte order is code point order), so no `String` is built or compared.
//! A name bound to a `get` result or a `chars()` element stays a code point while every use of
//! it is such a comparison; any other use keeps the ordinary `String`.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::api::ast::*;
use ms_check::api::hir::Resolution;
use ms_check::fxmap::HashSet;
use ms_mir::ir::{Cc, Imm, Op, Value};
use ms_mir::types::Ty as MTy;

/// The condition code of an ordering or equality operator.
fn cond(op: BinaryOp) -> Option<Cc> {
    Some(match op {
        BinaryOp::Eq => Cc::Eq,
        BinaryOp::Ne => Cc::Ne,
        BinaryOp::Lt => Cc::Lt,
        BinaryOp::Gt => Cc::Gt,
        BinaryOp::Le => Cc::Le,
        BinaryOp::Ge => Cc::Ge,
        _ => return None,
    })
}

/// The condition code with its operands swapped.
fn swapped(cc: Cc) -> Cc {
    match cc {
        Cc::Lt => Cc::Gt,
        Cc::Gt => Cc::Lt,
        Cc::Le => Cc::Ge,
        Cc::Ge => Cc::Le,
        other => other,
    }
}

/// The code point of a literal of exactly one scalar.
fn literal_scalar(e: &Expr) -> Option<i64> {
    let ExprKind::Text(parts) = &e.kind else {
        return None;
    };
    let [TextPart::Lit(s)] = parts.as_slice() else {
        return None;
    };
    let mut chars = s.chars();
    let c = chars.next()?;
    chars.next().is_none().then_some(i64::from(u32::from(c)))
}

/// A comparison of an operand with a one-character literal: the operand and the condition read
/// with the operand on the left.
fn compare_parts(e: &Expr) -> Option<(&Expr, Cc, i64)> {
    let ExprKind::Binary { op, left, right } = &e.kind else {
        return None;
    };
    let cc = cond(*op)?;
    if let Some(c) = literal_scalar(right) {
        return Some((left, cc, c));
    }
    literal_scalar(left).map(|c| (&**right, swapped(cc), c))
}

/// The receiver of `x.parse_int()`.
fn parse_int_receiver(syms: ms_check::api::Names, e: &Expr) -> Option<&Expr> {
    let ExprKind::Call { callee, args } = &e.kind else {
        return None;
    };
    let ExprKind::Member { left, name } = &callee.kind else {
        return None;
    };
    (args.is_empty() && syms.str(name) == "parse_int").then_some(&**left)
}

/// Locals of a body that some use needs as a `String`: a use other than a comparison with a
/// one-character literal, or one inside a closure.
pub(crate) fn string_uses(fl: &FnLower<'_>, body: &[Stmt]) -> HashSet<usize> {
    struct Scan<'a, 'b> {
        fl: &'a FnLower<'b>,
        compared: HashSet<*const Expr>,
        needed: HashSet<usize>,
    }
    impl ms_check::api::visit::Visitor for Scan<'_, '_> {
        fn expr(&mut self, e: &Expr) {
            if let Some((operand, _, _)) = compare_parts(e) {
                self.compared.insert(operand);
            }
            if let Some(recv) = parse_int_receiver(self.fl.syms, e) {
                self.compared.insert(recv);
            }
            match &e.kind {
                ExprKind::Name(_) if !self.compared.contains(&std::ptr::from_ref(e)) => {
                    if let Resolution::Local(b) = self.fl.hir.resolution(e) {
                        self.needed.insert(b.uid);
                    }
                }
                ExprKind::Lambda(_) => {
                    let captured = self.fl.hir.captures(e);
                    self.needed.extend(captured.iter().map(|b| b.uid));
                }
                _ => {}
            }
        }
    }
    let mut scan = Scan {
        fl,
        compared: HashSet::default(),
        needed: HashSet::default(),
    };
    ms_check::api::visit::walk_block(&mut scan, body);
    scan.needed
}

impl FnLower<'_> {
    /// The receiver and index of `text.get(index)` on a `String`, without a default.
    fn string_get_parts<'e>(&mut self, e: &'e Expr) -> Option<(&'e Expr, &'e Expr)> {
        let ExprKind::Call { callee, args } = &e.kind else {
            return None;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return None;
        };
        let [index] = args.as_slice() else {
            return None;
        };
        let labelled = index.name.is_some_and(|n| self.syms.str(n) != "index");
        if self.syms.str(name) != "get" || labelled {
            return None;
        }
        (self.emty(left).ok()? == MTy::STR).then_some((&**left, &index.value))
    }

    /// The code point of `text.get(index)`; a fault out of range, as `get` does.
    pub(crate) fn get_scalar(&mut self, e: &Expr) -> Result<Option<Val>, Error> {
        let Some((recv, index)) = self.string_get_parts(e) else {
            return Ok(None);
        };
        let text = self.expr(recv)?;
        let text = Val {
            v: self.borrow(text),
            own: false,
        };
        let at = self.expr(index)?;
        if self.dead {
            return Ok(Some(at));
        }
        self.at(e.pos);
        // All-ASCII text reads its byte inline; anything else asks the runtime.
        let byte = self
            .b
            .emit(Op::StrAsciiAt, &[text.v, at.v], Imm::None, Some(MTy::INT))
            .expect("ascii_at");
        let zero = self.b.iconst(0);
        let hit = self.b.icmp(Cc::Ge, byte, zero);
        let code = self.two_ways(hit, MTy::INT, &mut |_| Ok(Some(byte)), &mut |s| {
            let (has, zero) = (s.b.bconst(false), s.b.iconst(0));
            let v = s.call_runtime(
                "msrt_string_scalar_at",
                &[text.v, at.v, has, zero],
                MTy::INT,
            )?;
            Ok(Some(v))
        })?;
        Ok(Some(Val {
            v: code.v,
            own: false,
        }))
    }

    /// The scalar count of the borrowed string `text`: its byte length when it is known to be
    /// ASCII (read inline by the backends), else the runtime's count.
    pub(crate) fn scalar_len(&mut self, text: Value) -> Result<Value, Error> {
        let known = self.b.str_ascii_len(text);
        let zero = self.b.iconst(0);
        let hit = self.b.icmp(Cc::Ge, known, zero);
        let n = self.two_ways(hit, MTy::INT, &mut |_| Ok(Some(known)), &mut |s| {
            Ok(Some(s.b.str_len(text)))
        })?;
        Ok(n.v)
    }

    /// Whether the local `uid` may stay a code point: every use compares it.
    pub(crate) fn scalar_eligible(&self, b: &ms_check::api::types::BindingRef) -> bool {
        !b.mutable
            && !self.slotted.contains(&b.uid)
            && !self.cx.exclusive(b.uid)
            && !self.string_needed.contains(&b.uid)
    }

    /// `operand <op> "c"` on code points, for an operand that is a `get` call or a local kept
    /// as a code point.
    pub(crate) fn scalar_compare(&mut self, e: &Expr) -> Result<Option<Val>, Error> {
        let Some((operand, cc, c)) = compare_parts(e) else {
            return Ok(None);
        };
        let Some(code) = self.scalar_operand(operand)? else {
            return Ok(None);
        };
        if self.dead {
            return Ok(Some(code));
        }
        let lit: Value = self.b.iconst(c);
        let out = self.b.icmp(cc, code.v, lit);
        Ok(Some(self.val(out, true)))
    }

    /// The code point of a `get` call or of a local kept as one.
    fn scalar_operand(&mut self, operand: &Expr) -> Result<Option<Val>, Error> {
        if let ExprKind::Name(_) = &operand.kind {
            let Resolution::Local(b) = self.hir.resolution(operand) else {
                return Ok(None);
            };
            return Ok(self
                .scalar_locals
                .get(&b.uid)
                .map(|v| Val { v: *v, own: false }));
        }
        self.get_scalar(operand)
    }

    /// `c.parse_int()` of a one-scalar string: its digit value, or none.
    pub(crate) fn scalar_parse_int(&mut self, e: &Expr) -> Result<Option<Val>, Error> {
        let Some(operand) = parse_int_receiver(self.syms, e) else {
            return Ok(None);
        };
        let Some(code) = self.scalar_operand(operand)? else {
            return Ok(None);
        };
        if self.dead {
            return Ok(Some(code));
        }
        let (zero, nine) = (self.b.iconst(48), self.b.iconst(57));
        let (lo, hi) = (
            self.b.icmp(Cc::Ge, code.v, zero),
            self.b.icmp(Cc::Le, code.v, nine),
        );
        let digit = self.b.binop(Op::And, lo, hi);
        let opt = self.emty(e)?;
        let out = self.two_ways(
            digit,
            opt,
            &mut |s| {
                let base = s.b.iconst(48);
                let d = s.b.binop(Op::ISub, code.v, base);
                Ok(Some(s.b.opt_some(d)))
            },
            &mut |s| Ok(Some(s.b.opt_none(opt))),
        )?;
        Ok(Some(out))
    }
}
