//! Calls to `extern fn` declarations: the native symbol is the function's own name and the
//! call follows the ABI conventions of `ms-rt/ABI.md`, section 1, as the signature spells them:
//! scalars and strings direct, other values by pointer, optional parameters flattened to a
//! presence flag and a value, payload-free enums as their case index, and results through a
//! trailing `out` (with a `u8` status for `Result` and a presence flag for `Optional`).

use crate::Error;
use crate::func::{FnLower, Val};
use crate::rtcall::Input;
use ms_check::hir::CallView;
use ms_check::types as ct;
use ms_mir::ir::{Imm, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::Expr;

/// The runtime parameter type a flattened optional payload is passed as.
fn payload_kind(kind: &TyKind, t: MTy) -> &'static str {
    match kind {
        TyKind::Int | TyKind::Int8 | TyKind::Int16 | TyKind::Int32 => "i64",
        TyKind::Float | TyKind::Float32 => "f64",
        _ if t == MTy::STR => "*const StrVal",
        TyKind::Alt(_) => "i64",
        _ => "u8",
    }
}

impl FnLower<'_> {
    /// An `extern fn` applied to its arguments.
    pub(crate) fn extern_call(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        symbol: &str,
        sym: &ct::SymRef,
    ) -> Result<Val, Error> {
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let result = self.emty(e)?;
        let mut vals: Vec<Value> = Vec::new();
        for a in &args {
            self.extern_argument(a.val, a.wrapped, &mut vals)?;
        }
        self.at(e.pos);
        if let TyKind::Alt(a) = self.b.m.types.kind(result).clone() {
            // `Result[T, E]`: a `u8` status (0 is ok, `n` the `n`th case of `E`) and `T` through `out`.
            let ok = self.ok_case_index(a)?;
            let payload = self.b.m.alts[a.index()].cases[ok].fields[0].1;
            let out = (payload != MTy::UNIT).then(|| self.out_slot(payload, &mut vals));
            let code = self.status_code(symbol, &vals)?;
            // Bundled modules keep the runtime's own status table; user externs number the cases.
            let key = if sym.module.as_str().starts_with("@std/") {
                symbol.to_string()
            } else {
                format!("extern:{symbol}")
            };
            let mut r = self.status_result(&key, code, out, None, result)?;
            r.v = self.stamped(r.v)?;
            return Ok(r);
        }
        if let TyKind::Opt(inner) = self.b.m.types.kind(result).clone() {
            // `Optional[T]`: a presence flag, with `T` through `out` when present.
            let (slot, _) = self.out_slot(inner, &mut vals);
            let present = self.call_runtime(symbol, &vals, MTy::BOOL)?;
            return self.two_ways(
                present,
                result,
                &mut |s| {
                    let v =
                        s.b.emit(Op::Take, &[slot], Imm::Ty(inner), Some(inner))
                            .expect("take");
                    Ok(Some(s.b.opt_some(v)))
                },
                &mut |s| Ok(Some(s.none_owned(result))),
            );
        }
        if result == MTy::UNIT {
            self.call_runtime(symbol, &vals, MTy::UNIT)?;
            return Ok(Val {
                v: self.b.unit(),
                own: false,
            });
        }
        if matches!(result, MTy::INT | MTy::FLOAT | MTy::BOOL) {
            let v = self.call_runtime(symbol, &vals, result)?;
            return Ok(Val { v, own: false });
        }
        if matches!(self.b.m.types.kind(result), TyKind::Obj(..)) {
            // A runtime handle (such as a big integer) is returned directly, owned by the caller.
            let v = self.call_runtime(symbol, &vals, result)?;
            return Ok(Val { v, own: true });
        }
        // An owned value (a string, a record) comes back through a trailing `out`.
        let (slot, _) = self.out_slot(result, &mut vals);
        self.call_runtime(symbol, &vals, MTy::UNIT)?;
        let v = self
            .b
            .emit(Op::Take, &[slot], Imm::Ty(result), Some(result))
            .expect("take");
        Ok(Val { v, own: true })
    }

    /// An uninitialised slot for a trailing `out` parameter, appended to `vals`.
    fn out_slot(&mut self, t: MTy, vals: &mut Vec<Value>) -> (Value, MTy) {
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
            .expect("slot");
        vals.push(slot);
        (slot, t)
    }

    /// Appends the native form of one argument.
    fn extern_argument(
        &mut self,
        arg: Val,
        wrapped: bool,
        vals: &mut Vec<Value>,
    ) -> Result<(), Error> {
        let v = self.borrow(arg);
        let t = self.ty_of(v);
        match self.b.m.types.kind(t).clone() {
            _ if matches!(t, MTy::INT | MTy::FLOAT | MTy::BOOL | MTy::STR) => vals.push(v),
            // A runtime handle is its own pointer.
            TyKind::Obj(..) => vals.push(v),
            TyKind::Opt(inner) => {
                let kind = self.b.m.types.kind(inner).clone();
                let payload = payload_kind(&kind, inner);
                let input = Input {
                    val: Some(arg),
                    wrapped,
                };
                let (has, value) = self.flatten_optional(input, payload)?;
                vals.push(has);
                vals.push(value);
            }
            TyKind::Alt(a)
                if self.b.m.alts[a.index()]
                    .cases
                    .iter()
                    .all(|c| c.fields.is_empty()) =>
            {
                // A payload-free enum crosses as its case index.
                vals.push(self.b.alt_tag(v));
            }
            _ => {
                // Any other value is lent by pointer.
                let slot = self
                    .b
                    .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
                    .expect("slot");
                self.b.emit(Op::Store, &[slot, v], Imm::None, None);
                vals.push(slot);
            }
        }
        Ok(())
    }
}
