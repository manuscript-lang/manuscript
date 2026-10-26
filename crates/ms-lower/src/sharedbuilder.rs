//! The collection and text builders (`ListBuilder`, `MapBuilder`, `SetBuilder`, `StringBuilder`,
//! `BytesBuilder`): shared handles that accumulate a value.
//!
//! A builder is a `Shared` cell holding `{items, sealed}`. Copies of the handle see every
//! append or add, and `build` seals the cell so later changes fault with "builder is sealed".

use crate::Error;
use crate::func::{FnLower, Val};
use crate::native::NArg;
use ms_check::types as ct;
use ms_mir::ir::{Imm, Mode, Module, Op, Param, Value};
use ms_mir::types::{RecId, Ty as MTy, TyKind};

/// The std builder type `t` is, if any.
pub(crate) fn builder_kind(t: &ct::Ty) -> Option<&'static str> {
    [
        "ListBuilder",
        "MapBuilder",
        "SetBuilder",
        "StringBuilder",
        "BytesBuilder",
    ]
    .into_iter()
    .find(|n| t.is_std(n))
}

/// The handle type of a builder over the collection type `items`.
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
    fn builder_rec(&self, handle: MTy) -> Result<RecId, Error> {
        if let TyKind::Obj(n, a) = self.b.m.types.kind(handle)
            && n == "Shared"
            && let Some(&r) = a.first()
            && let TyKind::Rec(id) = self.b.m.types.kind(r)
        {
            return Ok(*id);
        }
        Err(Error::new("not a builder handle"))
    }

    /// `ListBuilder[T]()`, `MapBuilder[K, V]()` and `SetBuilder[T]()`.
    pub(crate) fn construct_builder(&mut self, handle: MTy) -> Result<Val, Error> {
        let rec = self.builder_rec(handle)?;
        let items_ty = self.b.m.records[rec.index()].fields[0].1;
        let items = match self.b.m.types.kind(items_ty).clone() {
            TyKind::List(elem) => self.b.list_lit(elem, &[]),
            // A text or byte builder accumulates an empty byte buffer.
            TyKind::Bytes => self.call_runtime("msrt_list_new", &[], items_ty)?,
            _ => self.map_new(items_ty)?,
        };
        let sealed = self.b.bconst(false);
        let state = self.b.rec_new(rec, &[items, sealed]);
        let v = self
            .b
            .emit(Op::SharedNew, &[state], Imm::None, Some(handle))
            .expect("shared result");
        Ok(Val { v, own: true })
    }

    /// Faults with "builder is sealed" when the flag at `sealed` is set.
    fn fault_if_sealed(&mut self, sealed: Value) {
        self.fault_if_flag(sealed, true, "builder is sealed");
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

    /// A builder method (`append`, `add`, `build`) on the handle `handle`.
    pub(crate) fn builder_call(
        &mut self,
        name: &str,
        handle: Value,
        decl: &[ct::Param],
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let rec = self.builder_rec(self.ty_of(handle))?;
        let items_ty = self.b.m.records[rec.index()].fields[0].1;
        let addr = self
            .b
            .emit(Op::SharedAddr, &[handle], Imm::None, Some(MTy::PTR))
            .expect("addr");
        let field = |s: &mut Self, i: u32| {
            s.b.emit(Op::PtrField, &[addr], Imm::Field(rec, i), Some(MTy::PTR))
                .expect("field")
        };
        let items = field(self, 0);
        let sealed = field(self, 1);
        if name == "build" {
            // Seal, then hand out a copy: the builder keeps its items for a second build.
            let yes = self.b.bconst(true);
            self.b.emit(Op::Store, &[sealed, yes], Imm::None, None);
            let cur = self
                .b
                .emit(Op::Load, &[items], Imm::Ty(items_ty), Some(items_ty))
                .expect("load");
            let copy = self.owned(Val { v: cur, own: false });
            if result == MTy::STR {
                // The runtime consumes the buffer it freezes into text.
                let slot = self.put_slot(copy);
                let text = self.call_runtime("msrt_strbuilder_freeze", &[slot], MTy::STR)?;
                return Ok(Val { v: text, own: true });
            }
            return Ok(Val { v: copy, own: true });
        }
        self.fault_if_sealed(sealed);
        let old = self.take_slot(items, items_ty);
        let (new, _) = self.mutate_any(name, old, decl, args, false, MTy::UNIT)?;
        self.b.emit(Op::Put, &[items, new], Imm::None, None);
        let u = self.b.unit();
        Ok(Val { v: u, own: false })
    }

    /// `builder.append(x)` and friends as a call expression.
    pub(crate) fn builder_method(
        &mut self,
        e: &ms_syntax::ast::Expr,
        view: &ms_check::hir::CallView<'_>,
        m: &ct::MethodRef,
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
        self.builder_call(name, handle, &m.ty.params, &args, result)
    }
}

impl<'a> FnLower<'a> {
    /// A method of a user-facing `Shared[T]`: a box holding `{value, taken}`. `take` moves the
    /// value out and marks the box in use; `put` moves it back. A second `take`, or a `get`, while
    /// the value is out faults, which is the runtime check of the single mutable borrow.
    pub(crate) fn shared_method(
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
                let _ = result;
                Ok(Val {
                    v: self.b.unit(),
                    own: false,
                })
            }
            _ => Err(Error::new("unknown Shared method")),
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
