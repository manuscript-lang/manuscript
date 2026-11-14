//! `math.min` and `math.max` over any `Comparable` scalar, and `List.min` and `List.max`.
//!
//! Ordering follows the native compare of the type: `Float` puts NaN above every value and
//! equates `-0.0` with `0.0`. Ties keep the first operand.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::api::types as ct;
use ms_check::api::types::Builtin;
use ms_mir::ir::{Cc, Imm, Op, Value};
use ms_mir::types::Native;
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
            TyKind::Obj(Native::BigInt, _) => "msstd_bigint_compare",
            _ => {
                if let Some(c) = self.native_compare(t, a, b)? {
                    return Ok(c);
                }
                return self.user_order(concrete, a, b);
            }
        };
        self.call_runtime(sym, &[a, b], MTy::INT)
    }

    /// `a.compare(b)` through the `Comparable` implementation of `concrete`.
    fn user_order(&mut self, concrete: &ct::Ty, a: Value, b: Value) -> Result<Value, Error> {
        let key = self.cx.tys.shape(concrete);
        let tys = &mut self.cx.tys;
        let compare_name = self.cx.session.sole_operation("@std/core.ms", "Comparable");
        let compare = |m: &ct::MethodRef| m.name().is_some() && m.name() == compare_name;
        let im = self
            .cx
            .methods
            .iter()
            .find(|m| {
                m.contract
                    .as_ref()
                    .is_some_and(|c| c.is(Builtin::Comparable))
                    && compare(m)
                    && tys.shape(&m.receiver) == key
            })
            // A type's own `compare` orders it without an `impl Comparable`.
            .or_else(|| {
                self.cx.methods.iter().find(|m| {
                    m.is_inherent(self.syms) && compare(m) && tys.shape(&m.receiver) == key
                })
            })
            .cloned()
            .ok_or_else(|| Error::new("ordering this type is not supported yet"))?;
        let decl = im
            .decl
            .as_ref()
            .ok_or_else(|| Error::new("compare without declaration"))?;
        let c = self.callable_of_decl(im.module, Some(decl.id()))?;
        let fid = self.cx.function_for(self.b.m, &c, &ct::Subst::default())?;
        let other = b;
        let recv = if self.cx.var_positions(&c).contains(&0) {
            // A changing receiver is borrowed as a slot holding a copy that is dropped afterwards.
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
}
