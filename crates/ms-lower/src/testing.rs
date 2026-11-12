//! The extern of `@std/test/test.ms` that needs the compiler: the debug text of a value. The
//! expectations themselves are Manuscript source.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::api::ast::Expr;
use ms_check::api::hir::CallView;
use ms_mir::ir::Value;
use ms_mir::types::{AltId, Ty as MTy, TyKind};

impl FnLower<'_> {
    /// The `ok` and `error` case indexes of a Result alternative.
    fn result_cases(&self, rty: MTy) -> Result<(AltId, u32, u32), Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(rty).clone() else {
            return Err(Error::new("not a Result"));
        };
        let find = |n: &str| {
            self.b.m.alts[a.index()]
                .cases
                .iter()
                .position(|c| c.name == n)
                .map(|i| i as u32)
        };
        match (find("ok"), find("error")) {
            (Some(ok), Some(err)) => Ok((a, ok, err)),
            _ => Err(Error::new("not a Result")),
        }
    }

    /// `ok(payload)` of the Result type (payload owned).
    pub(crate) fn testing_ok(&mut self, rty: MTy, payload: Value) -> Result<Value, Error> {
        let (a, ok, _) = self.result_cases(rty)?;
        Ok(self.b.alt_new(a, ok, &[payload]))
    }

    /// A borrowed string literal.
    pub(crate) fn lit(&mut self, text: &str) -> Val {
        let v = self.b.str_lit(text);
        Val { v, own: false }
    }

    /// The hand-lowered externs of `@std/internal/test.ms`: `repr`.
    pub fn testing_native(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        name: &str,
    ) -> Result<Val, Error> {
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        self.at(e.pos);
        let operand = self.borrow(args[0].val);
        match name {
            "repr" => Ok(self.repr_text(operand)),
            other => Err(Error::new(format!("unsupported testing function {other}"))),
        }
    }
}
