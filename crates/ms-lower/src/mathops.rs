//! `math.min`, `math.max`, `math.min_of` and `math.max_of` over any `Comparable` scalar.
//!
//! Ordering follows the native compare of the type: `Float` puts NaN above every value and
//! equates `-0.0` with `0.0`. Ties keep the first operand.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::hir::CallView;
use ms_mir::ir::{Cc, Mode, Value};
use ms_mir::types::{Ty as MTy, TyKind};

impl FnLower<'_> {
    /// `-1`, `0` or `1` as `a` orders before, with or after `b`.
    fn order(&mut self, t: MTy, a: Value, b: Value) -> Result<Value, Error> {
        if t == MTy::INT {
            let (lt, gt) = (self.b.icmp(Cc::Lt, a, b), self.b.icmp(Cc::Gt, a, b));
            let (one, zero, minus) = (self.b.iconst(1), self.b.iconst(0), self.b.iconst(-1));
            let upper = self.b.select(gt, one, zero);
            return Ok(self.b.select(lt, minus, upper));
        }
        let sym = match self.b.m.types.kind(t) {
            TyKind::Float => "msrt_float_compare",
            TyKind::Str => "msrt_string_compare",
            TyKind::Obj(n, _) if n == "BigInt" => "msstd_bigint_compare",
            _ => {
                if let Some(sym) = self.ordering_symbol(t) {
                    return self.call_runtime(sym, &[a, b], MTy::INT);
                }
                let f = self.cx.user_compare(self.b.m, t)?;
                let f = f.ok_or_else(|| Error::new("ordering this type is not supported yet"))?;
                return Ok(self.b.call(f, &[a, b]));
            }
        };
        self.call_runtime(sym, &[a, b], MTy::INT)
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
        let (l, r) = (self.borrow(left), self.borrow(right));
        let c = self.order(t, l, r)?;
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

    /// `min_of(values)` or `max_of(values)`: the first of the extreme elements, or none.
    pub(crate) fn math_extreme_of(
        &mut self,
        e: &ms_syntax::ast::Expr,
        view: &CallView<'_>,
        greater: bool,
    ) -> Result<Val, Error> {
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let out = self.emty(e)?;
        let values = args
            .iter()
            .find(|a| a.name.as_str() == "values")
            .map(|a| a.val)
            .ok_or_else(|| Error::new("min_of and max_of take a list"))?;
        let list = self.borrow(values);
        let TyKind::List(elem) = self.b.m.types.kind(self.ty_of(list)).clone() else {
            return Err(Error::new("min_of and max_of take a list"));
        };
        let n = self.b.list_len(list);
        let zero = self.b.iconst(0);
        let empty = self.b.icmp(Cc::Eq, n, zero);
        let lvar = self.b.declare_var(self.ty_of(list), Mode::Borrow);
        self.b.def_var(lvar, list);
        self.two_ways(empty, out, &mut |s| Ok(Some(s.none_owned(out))), &mut |s| {
            let l = s.b.use_var(lvar);
            let first = s.b.list_get(l, zero);
            let first = s.owned(Val {
                v: first,
                own: false,
            });
            let best = s.fresh_var(elem);
            s.b.def_var(best, first);
            s.each_element(lvar, &mut |s, _, x| {
                let cur = s.b.use_var(best);
                let c = s.order(elem, x, cur)?;
                let z = s.b.iconst(0);
                let better = s.b.icmp(if greater { Cc::Gt } else { Cc::Lt }, c, z);
                let (take, skip) = (s.b.new_block(), s.b.new_block());
                s.b.br_if(better, take, &[], skip, &[]);
                s.b.seal_block(take);
                s.b.seal_block(skip);
                s.enter(take);
                let next = s.owned(Val { v: x, own: false });
                let old = s.b.use_var(best);
                s.drop_value(old);
                s.b.def_var(best, next);
                s.b.br(skip, &[]);
                s.enter(skip);
                Ok(None)
            })?;
            let v = s.b.use_var(best);
            Ok(Some(s.b.opt_some(v)))
        })
    }
}
