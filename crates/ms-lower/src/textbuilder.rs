//! `build` for the owned `StringBuilder` and `BytesBuilder`.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::text::Piece;
use ms_check::api::ast::{BinaryOp, Expr, ExprKind};
use ms_mir::types::Ty as MTy;

/// Most pieces appended one by one; a longer text is joined first so the call count stays small.
const MAX_APPENDS: usize = 8;

impl<'a> FnLower<'a> {
    /// `StringBuilder.build()` and `BytesBuilder.build()`: the consumed builder's buffer becomes the
    /// result, frozen into text without validation for a `StringBuilder`.
    pub(crate) fn text_builder_build(
        &mut self,
        e: &ms_check::api::ast::Expr,
        recv_expr: &ms_check::api::ast::Expr,
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

    /// Whether `arg` is a text the builder can take piece by piece: an interpolation or a `+` chain
    /// over strings.
    pub(crate) fn is_text_expr(&mut self, arg: &Expr) -> bool {
        match &arg.kind {
            ExprKind::Text(_) => true,
            ExprKind::Binary {
                op: BinaryOp::Add, ..
            } => self.emty(arg).is_ok_and(|t| t == MTy::STR),
            _ => false,
        }
    }

    /// `builder.append(text)` for an interpolation or a `+` chain: every piece is evaluated first,
    /// left to right, and then appended in turn, so the joined string is never built. The runtime
    /// append checks that the builder is not sealed before it writes a byte.
    pub(crate) fn text_builder_append(
        &mut self,
        e: &Expr,
        recv_expr: &Expr,
        arg: &Expr,
    ) -> Result<Val, Error> {
        self.prepare_place(recv_expr)?;
        if self.dead {
            self.finish_place(recv_expr);
            return Ok(self.dummy(MTy::VOID));
        }
        let mut pieces = match &arg.kind {
            ExprKind::Text(parts) => self.text_pieces(parts)?,
            _ => self.sum_pieces(arg)?,
        };
        if self.dead {
            self.finish_place(recv_expr);
            return Ok(self.dummy(MTy::VOID));
        }
        self.at(e.pos);
        if pieces.len() > MAX_APPENDS {
            let joined = self.join_pieces(pieces)?;
            pieces = vec![Piece::Str(self.hold_temp(joined))];
        }
        let out = self.place_update_prepared(recv_expr, &mut |s, old| {
            let mt = s.ty_of(old);
            let mut cur = old;
            for p in &pieces {
                let slot = s.put_slot(cur);
                match p {
                    Piece::Str(v) => {
                        let text = s.borrow(*v);
                        s.call_runtime("msrt_strbuilder_append", &[slot, text], MTy::VOID)?;
                    }
                    Piece::Int(x) => {
                        s.call_runtime("msrt_strbuilder_append_int", &[slot, *x], MTy::VOID)?;
                    }
                }
                cur = s.take_slot(slot, mt);
            }
            Ok(cur)
        });
        self.finish_place(recv_expr);
        out?;
        let u = self.b.unit();
        Ok(Val { v: u, own: false })
    }
}
