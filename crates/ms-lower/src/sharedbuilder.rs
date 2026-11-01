//! `Shared[T]` boxes, and `build` for the owned `StringBuilder` and `BytesBuilder`.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_mir::ir::{Imm, Mode, Module, Op, Param, Value};
use ms_mir::types::{RecId, Ty as MTy, TyKind};

/// The handle type of a builder over the payload type `items`.
pub(crate) fn handle_ty(m: &mut Module, name: &str, items: MTy) -> MTy {
    let rec_name = format!("{name}#{}", items.0);
    let rec = match m.records.iter().position(|r| r.name == rec_name) {
        Some(i) => m.types.rec(RecId(i as u32)),
        None => {
            let fields = vec![
                // The payload comes first: a field's address is read with the field's own layout,
                // which matches its place in the record only when it starts the record.
                ("items".to_string(), items),
                ("sealed".to_string(), MTy::BOOL),
            ];
            m.add_record(&rec_name, fields).1
        }
    };
    m.types.obj("Shared", vec![rec])
}

impl<'a> FnLower<'a> {
    pub(crate) fn builder_rec(&self, handle: MTy) -> Result<RecId, Error> {
        if let TyKind::Obj(n, a) = self.b.m.types.kind(handle)
            && n == "Shared"
            && let Some(&r) = a.first()
            && let TyKind::Rec(id) = self.b.m.types.kind(r)
        {
            return Ok(*id);
        }
        Err(Error::new("not a builder handle"))
    }

    /// Faults with `message` when the flag at `flag` equals `when`.
    fn fault_if_flag(&mut self, flag: Value, when: bool, message: &str) {
        let flag = self
            .b
            .emit(Op::Load, &[flag], Imm::Ty(MTy::BOOL), Some(MTy::BOOL))
            .expect("load");
        let (bad, good) = (self.b.new_block(), self.b.new_block());
        if when {
            self.b.br_if(flag, bad, &[], good, &[]);
        } else {
            self.b.br_if(flag, good, &[], bad, &[]);
        }
        self.b.seal_block(bad);
        self.b.seal_block(good);
        self.b.switch_to(bad);
        let msg = self.b.str_lit(message);
        let ext = self.b.m.add_extern(ms_mir::ir::ExternDef {
            name: "msrt_fault_string".to_string(),
            params: vec![Param {
                ty: MTy::STR,
                mode: Mode::Borrow,
            }],
            ret: MTy::UNIT,
            noreturn: true,
            pure_: false,
            fresh: false,
        });
        self.b.call_rt(ext, &[msg]);
        self.b.unreachable();
        self.b.switch_to(good);
    }

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

impl<'a> FnLower<'a> {
    /// `Shared[T].get`: a box holds `{value, taken}`. A `get` while the value is out faults, which is
    /// the runtime check of the single mutable borrow.
    pub(crate) fn shared_method(
        &mut self,
        e: &ms_syntax::ast::Expr,
        recv_expr: &ms_syntax::ast::Expr,
        name: &str,
    ) -> Result<Val, Error> {
        let recv = self.expr(recv_expr)?;
        if self.dead {
            return Ok(recv);
        }
        let handle = self.borrow(recv);
        self.shared_op(e, handle, name, &[])
    }

    /// The private primitives of `@std/concurrency/shared.ms` that `lock` and `SharedGuard` are built
    /// on: `take` moves the value out and marks the box in use; `put` moves it back. A second
    /// `take` while the value is out faults.
    pub(crate) fn shared_primitive(
        &mut self,
        e: &ms_syntax::ast::Expr,
        view: &ms_check::hir::CallView<'_>,
        name: &str,
    ) -> Result<Val, Error> {
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let first = args
            .first()
            .ok_or_else(|| Error::new("a Shared primitive without a box"))?;
        let handle = self.borrow(first.val);
        self.shared_op(e, handle, name, &args[1..])
    }

    fn shared_op(
        &mut self,
        e: &ms_syntax::ast::Expr,
        handle: Value,
        name: &str,
        args: &[crate::native::NArg],
    ) -> Result<Val, Error> {
        self.at(e.pos);
        let rec = self.builder_rec(self.ty_of(handle))?;
        let value_ty = self.b.m.records[rec.index()].fields[0].1;
        let addr = self
            .b
            .emit(Op::SharedAddr, &[handle], Imm::None, Some(MTy::PTR))
            .expect("addr");
        let field = |s: &mut Self, i: u32| {
            s.b.emit(Op::PtrField, &[addr], Imm::Field(rec, i), Some(MTy::PTR))
                .expect("field")
        };
        let value = field(self, 0);
        let taken = field(self, 1);
        match name {
            "get" => {
                self.fault_if_flag(taken, true, "shared value is in use");
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
                self.fault_if_flag(taken, true, "shared value is in use");
                let yes = self.b.bconst(true);
                self.b.emit(Op::Store, &[taken, yes], Imm::None, None);
                let v = self.take_slot(value, value_ty);
                Ok(Val { v, own: true })
            }
            "put" => {
                self.fault_if_flag(taken, false, "shared value was not taken");
                let arg = args
                    .first()
                    .ok_or_else(|| Error::new("put without a value"))?;
                // `put` moves the argument bitwise: its one caller, `SharedGuard.close`, clears `held`
                // first, and the glue of a closed guard neither copies nor drops its `value`.
                let moved = if arg.val.own || !self.needs_drop(value_ty) {
                    arg.val.v
                } else {
                    self.b.move_out(arg.val.v)
                };
                self.b.emit(Op::Put, &[value, moved], Imm::None, None);
                let no = self.b.bconst(false);
                self.b.emit(Op::Store, &[taken, no], Imm::None, None);
                Ok(Val {
                    v: self.b.unit(),
                    own: false,
                })
            }
            _ => Err(Error::new("unknown Shared operation")),
        }
    }

    /// `share(value)`: a new box holding the value, not taken.
    pub(crate) fn shared_new(&mut self, payload: Value, handle: MTy) -> Value {
        let rec = self.builder_rec(handle).expect("shared handle");
        let free = self.b.bconst(false);
        let state = self.b.rec_new(rec, &[payload, free]);
        self.b
            .emit(Op::SharedNew, &[state], Imm::None, Some(handle))
            .expect("shared result")
    }
}
