//! Calls to `extern fn` declarations: the native symbol is the function's own name and the
//! call follows the ABI conventions of `ms-rt/ABI.md`, section 1, as the signature spells them.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::rtcall::{RtParam, RtSig};
use ms_check::hir::CallView;
use ms_check::types as ct;
use ms_mir::ir::{Imm, Op};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::Expr;

impl FnLower<'_> {
    /// An `extern fn` applied to its arguments: scalars and borrowed strings in, a scalar,
    /// `Unit`, or an owned string (through a trailing `out`) back.
    pub(crate) fn extern_call(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        symbol: &str,
        params: &[ct::Param],
    ) -> Result<Val, Error> {
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let result = self.emty(e)?;
        let mut vals: Vec<_> = args.iter().map(|a| self.borrow(a.val)).collect();
        if let TyKind::Alt(a) = self.b.m.types.kind(result).clone() {
            // `Result[T, E]`: a `u8` status (0 is ok, `n` the `n`th case of `E`) and `T` through `out`.
            let ok = self.ok_case_index(a)?;
            let payload = self.b.m.alts[a.index()].cases[ok].fields[0].1;
            self.at(e.pos);
            let out = if payload == MTy::UNIT {
                None
            } else {
                let slot = self
                    .b
                    .emit(Op::Slot, &[], Imm::Ty(payload), Some(MTy::PTR))
                    .expect("slot");
                vals.push(slot);
                Some((slot, payload))
            };
            let code = self.status_code(symbol, &vals)?;
            // The `extern:` prefix numbers the error cases by declaration order.
            let mut r = self.status_result(&format!("extern:{symbol}"), code, out, None, result)?;
            r.v = self.stamped(r.v)?;
            return Ok(r);
        }
        let c_type = |t: MTy| match t {
            MTy::INT => "i64",
            MTy::FLOAT => "f64",
            MTy::BOOL => "u8",
            _ => "*const StrVal",
        };
        let mut sig = RtSig {
            params: params
                .iter()
                .zip(&vals)
                .map(|(p, v)| RtParam {
                    name: p.name.to_string(),
                    ty: c_type(self.ty_of(*v)).to_string(),
                })
                .collect(),
            ret: String::new(),
        };
        let has_out = result == MTy::STR;
        match result {
            MTy::INT => sig.ret = "i64".to_string(),
            MTy::FLOAT => sig.ret = "f64".to_string(),
            MTy::BOOL => sig.ret = "u8".to_string(),
            MTy::STR => sig.params.push(RtParam {
                name: "out".to_string(),
                ty: "*mut StrVal".to_string(),
            }),
            _ => {}
        }
        self.at(e.pos);
        self.finish_rt_call(symbol, &sig, has_out, vals, result)
    }
}
