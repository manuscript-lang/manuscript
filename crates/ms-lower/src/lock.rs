//! `Lock[T]` from `@std/lock.ms`: a runtime cell holding `{value, taken}`.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_mir::ir::{Imm, Op, Value};
use ms_mir::types::Ty as MTy;

impl<'a> FnLower<'a> {
    /// A native method of a `Lock[T]`: a cell holding `{value, taken}`. `take` moves the
    /// value out and marks the box in use; `put` moves it back. A second `take`, or a `get`, while
    /// the value is out faults, which is the runtime check of the single mutable borrow.
    pub(crate) fn lock_method(
        &mut self,
        e: &ms_syntax::ast::Expr,
        view: &ms_check::hir::CallView<'_>,
        recv_expr: &ms_syntax::ast::Expr,
        name: &str,
    ) -> Result<Val, Error> {
        let recv = self.expr(recv_expr)?;
        if self.dead {
            return Ok(recv);
        }
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let handle = self.borrow(recv);
        self.at(e.pos);
        let result = self.emty(e)?;
        let rec = self.cell_rec(self.ty_of(handle))?;
        let value_ty = self.b.m.records[rec.index()].fields[0].1;
        let addr = self
            .b
            .emit(Op::CellAddr, &[handle], Imm::None, Some(MTy::PTR))
            .expect("addr");
        let field = |s: &mut Self, i: u32| {
            s.b.emit(Op::PtrField, &[addr], Imm::Field(rec, i), Some(MTy::PTR))
                .expect("field")
        };
        let value = field(self, 0);
        let taken = field(self, 1);
        match name {
            "peek" => {
                self.fault_if_flag(taken, true, "the lock is held");
                let v = self
                    .b
                    .emit(Op::Load, &[value], Imm::Ty(value_ty), Some(value_ty))
                    .expect("load");
                Ok(Val { v, own: false })
            }
            "id" => {
                // The box address: what a wait queue is keyed by.
                let id = self.call_runtime("msrt_addr_id", &[addr], MTy::INT)?;
                Ok(Val { v: id, own: false })
            }
            "locked" => {
                let v = self
                    .b
                    .emit(Op::Load, &[taken], Imm::Ty(MTy::BOOL), Some(MTy::BOOL))
                    .expect("load");
                Ok(Val { v, own: false })
            }
            "take" => {
                self.fault_if_flag(taken, true, "the lock is held");
                let yes = self.b.bconst(true);
                self.b.emit(Op::Store, &[taken, yes], Imm::None, None);
                let v = self.take_slot(value, value_ty);
                Ok(Val { v, own: true })
            }
            "put" => {
                self.fault_if_flag(taken, false, "the lock was not held");
                let arg = args
                    .first()
                    .ok_or_else(|| Error::new("put without a value"))?;
                // `put` moves the argument bitwise: its one caller, `Locked.close`, clears `held`
                // first, and the glue of a closed guard neither copies nor drops its `value`.
                let moved = if arg.val.own || !self.needs_drop(value_ty) {
                    arg.val.v
                } else {
                    self.b.move_out(arg.val.v)
                };
                self.b.emit(Op::Put, &[value, moved], Imm::None, None);
                let no = self.b.bconst(false);
                self.b.emit(Op::Store, &[taken, no], Imm::None, None);
                let _ = result;
                Ok(Val {
                    v: self.b.unit(),
                    own: false,
                })
            }
            _ => Err(Error::new("unknown Lock method")),
        }
    }

    /// `new_lock(value)`: a new cell holding the value, not taken.
    pub(crate) fn lock_new(&mut self, payload: Value, handle: MTy) -> Value {
        let rec = self.cell_rec(handle).expect("lock handle");
        let free = self.b.bconst(false);
        let state = self.b.rec_new(rec, &[payload, free]);
        self.b
            .emit(Op::CellNew, &[state], Imm::None, Some(handle))
            .expect("lock result")
    }
}
