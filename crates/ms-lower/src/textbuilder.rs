//! `build` for the owned `StringBuilder` and `BytesBuilder`.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_mir::types::Ty as MTy;

impl<'a> FnLower<'a> {
    /// `StringBuilder.build()` and `BytesBuilder.build()`: the consumed builder's buffer becomes the
    /// result, frozen into text without validation for a `StringBuilder`.
    pub(crate) fn text_builder_build(
        &mut self,
        e: &ms_syntax::ast::Expr,
        recv_expr: &ms_syntax::ast::Expr,
    ) -> Result<Val, Error> {
        let recv = self.expr(recv_expr)?;
        if self.dead {
            return Ok(recv);
        }
        self.at(e.pos);
        let result = self.emty(e)?;
        // The optimizer turns the copy of a builder that is not used again into a move.
        let buf = self.owned(recv);
        if result == MTy::STR {
            let slot = self.put_slot(buf);
            let text = self.call_runtime("msrt_strbuilder_freeze", &[slot], MTy::STR)?;
            return Ok(Val { v: text, own: true });
        }
        Ok(Val { v: buf, own: true })
    }
}
