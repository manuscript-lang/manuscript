//! `math.min` and `math.max` over any `Comparable` scalar, and `List.min` and `List.max`.
//!
//! Ordering follows the native compare of the type: `Float` puts NaN above every value and
//! equates `-0.0` with `0.0`. Ties keep the first operand.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::hir::CallView;
use ms_check::types as ct;
use ms_mir::ir::{Cc, Imm, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};

impl FnLower<'_> {
    /// `-1`, `0` or `1` as `a` orders before, with or after `b`.
    pub(crate) fn order(
        &mut self,
        t: MTy,
        concrete: &ct::Ty,
        a: Value,
        b: Value,
    ) -> Result<Value, Error> {
        if self.b.m.types.is_int(t) {
            let (lt, gt) = (self.b.icmp(Cc::Lt, a, b), self.b.icmp(Cc::Gt, a, b));
            let (one, zero, minus) = (self.b.iconst(1), self.b.iconst(0), self.b.iconst(-1));
            let upper = self.b.select(gt, one, zero);
            return Ok(self.b.select(lt, minus, upper));
        }
        let sym = match self.b.m.types.kind(t) {
            TyKind::Float | TyKind::Float32 => "msrt_float_compare",
            TyKind::Str => "msrt_string_compare",
            TyKind::Obj(n, _) if n == "BigInt" => "msstd_bigint_compare",
            _ => {
                if let Some(sym) = self.ordering_symbol(t) {
                    return self.call_runtime(sym, &[a, b], MTy::INT);
                }
                return self.user_order(concrete, a, b);
            }
        };
        self.call_runtime(sym, &[a, b], MTy::INT)
    }

    /// `a.compare(b)` through the `Comparable` implementation of `concrete`.
    fn user_order(&mut self, concrete: &ct::Ty, a: Value, b: Value) -> Result<Value, Error> {
        let key = ct::type_key(concrete);
        let im = self
            .cx
            .methods
            .iter()
            .find(|m| {
                m.contract.as_ref().is_some_and(|c| c.is_std("Comparable"))
                    && m.name().is_some_and(|n| n.as_str() == "compare")
                    && ct::type_key(&m.receiver) == key
            })
            .cloned()
            .ok_or_else(|| Error::new("ordering this type is not supported yet"))?;
        let decl = im
            .decl
            .as_ref()
            .ok_or_else(|| Error::new("compare without declaration"))?;
        let c = self.callable_of_decl(im.module, Some(decl.id()))?;
        let fid = self.cx.function_for(self.b.m, &c, &ct::Subst::new())?;
        let other = b;
        let recv = if self.cx.var_positions(&c).contains(&0) {
            // A changing receiver is lent as a slot holding a copy that is dropped afterwards.
            let t = self.ty_of(a);
            let copy = self.owned(Val { v: a, own: false });
            let slot = self
                .b
                .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
                .expect("slot");
            self.move_into(slot, copy);
            Some((slot, t))
        } else {
            None
        };
        let first = recv.map_or(a, |(slot, _)| slot);
        let r = self.b.call(fid, &[first, other]);
        if let Some((slot, t)) = recv {
            let back = self.move_out(slot, t);
            self.drop_value(back);
        }
        Ok(r)
    }

    /// `min(left, right)` or `max(left, right)`.
    pub(crate) fn math_extreme(
        &mut self,
        view: &CallView<'_>,
        greater: bool,
    ) -> Result<Val, Error> {
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let find = |n: &str| args.iter().find(|a| a.name.as_str() == n).map(|a| a.val);
        let (Some(left), Some(right)) = (find("left"), find("right")) else {
            return Err(Error::new("min and max take two operands"));
        };
        let t = self.ty_of(left.v);
        let concrete = view
            .arguments
            .iter()
            .find(|a| a.slot.name.as_str() == "left")
            .map(|a| self.ety(a.expr))
            .ok_or_else(|| Error::new("min and max take two operands"))?;
        let (l, r) = (self.borrow(left), self.borrow(right));
        let c = self.order(t, &concrete, l, r)?;
        let zero = self.b.iconst(0);
        // The left operand wins ties.
        let keep_left = self.b.icmp(if greater { Cc::Ge } else { Cc::Le }, c, zero);
        if !self.needs_drop(t) {
            let v = self.b.select(keep_left, l, r);
            return Ok(Val { v, own: false });
        }
        self.two_ways(
            keep_left,
            t,
            &mut |s| Ok(Some(s.owned(Val { v: l, own: false }))),
            &mut |s| Ok(Some(s.owned(Val { v: r, own: false }))),
        )
    }
}
