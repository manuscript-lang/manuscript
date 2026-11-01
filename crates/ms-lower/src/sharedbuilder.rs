//! `Shared[T]` boxes, and `build` for the owned `StringBuilder` and `BytesBuilder`.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_mir::ir::{Cc, Imm, Module, Op, Value};
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
                // `0` free, `n > 0` for `n` read holds, `-1` while a call or update changes it.
                ("state".to_string(), MTy::INT),
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
    /// The payload of the handle `e` evaluated to, read in place. The read waits while another
    /// task's call changes the box, and faults inside this task's own change of it, unless the
    /// call in progress holds the box.
    pub(crate) fn shared_read(&mut self, e: &ms_syntax::ast::Expr, h: Val) -> Result<Val, Error> {
        self.at(e.pos);
        let handle = self.borrow(h);
        let rec = self.builder_rec(self.ty_of(handle))?;
        let value_ty = self.b.m.records[rec.index()].fields[0].1;
        let addr = self
            .b
            .emit(Op::SharedAddr, &[handle], Imm::None, Some(MTy::PTR))
            .expect("addr");
        let key = self.shared_key(e);
        if !self.held.contains(&key) && !self.read_held.contains(&key) {
            let state = self
                .b
                .emit(Op::PtrField, &[addr], Imm::Field(rec, 1), Some(MTy::PTR))
                .expect("field");
            self.wait_turn(addr, state, true)?;
        }
        let value = self
            .b
            .emit(Op::PtrField, &[addr], Imm::Field(rec, 0), Some(MTy::PTR))
            .expect("field");
        let v = self
            .b
            .emit(Op::Load, &[value], Imm::Ty(value_ty), Some(value_ty))
            .expect("load");
        Ok(Val { v, own: false })
    }

    /// Whether `e` is a `Shared` handle that stands for its payload.
    pub(crate) fn through_shared(&self, e: &ms_syntax::ast::Expr) -> bool {
        self.hir.info(e).through_shared.is_some()
    }

    /// Replaces the payload of the handle `handle_expr` by `f(payload)` in its box. The box is
    /// marked in use while `f` runs, so another task's access waits for the change to finish and
    /// this task's own access faults; a task waiting for the box is woken after.
    pub(crate) fn shared_update(
        &mut self,
        handle_expr: &ms_syntax::ast::Expr,
        f: &mut dyn FnMut(&mut Self, Value) -> Result<Value, Error>,
    ) -> Result<(), Error> {
        let held = self.held.contains(&self.shared_key(handle_expr));
        let handle = self.shared_handle(handle_expr)?;
        if self.dead {
            return Ok(());
        }
        self.shared_update_handle(handle, held, f)
    }

    /// The raw handle of `handle_expr`, a `Shared` that otherwise stands for its payload.
    fn shared_handle(&mut self, handle_expr: &ms_syntax::ast::Expr) -> Result<Value, Error> {
        let saved = self.handle_of;
        self.handle_of = Some(handle_expr as *const ms_syntax::ast::Expr);
        let h = self.expr_value(handle_expr);
        self.handle_of = saved;
        let h = h?;
        Ok(self.borrow(h))
    }

    /// `shared_update` of an evaluated handle. A box `held` by the call in progress changes
    /// without a check: the hold already keeps every other access out.
    pub(crate) fn shared_update_handle(
        &mut self,
        handle: Value,
        held: bool,
        f: &mut dyn FnMut(&mut Self, Value) -> Result<Value, Error>,
    ) -> Result<(), Error> {
        let rec = self.builder_rec(self.ty_of(handle))?;
        let value_ty = self.b.m.records[rec.index()].fields[0].1;
        let addr = self
            .b
            .emit(Op::SharedAddr, &[handle], Imm::None, Some(MTy::PTR))
            .expect("addr");
        let value = self
            .b
            .emit(Op::PtrField, &[addr], Imm::Field(rec, 0), Some(MTy::PTR))
            .expect("field");
        let state = self
            .b
            .emit(Op::PtrField, &[addr], Imm::Field(rec, 1), Some(MTy::PTR))
            .expect("field");
        if held {
            let old = self.take_slot(value, value_ty);
            let updated = f(self, old)?;
            self.b.emit(Op::Put, &[value, updated], Imm::None, None);
            return Ok(());
        }
        self.wait_turn(addr, state, false)?;
        let changing = self.b.iconst(-1);
        self.b.emit(Op::Store, &[state, changing], Imm::None, None);
        let old = self.take_slot(value, value_ty);
        let updated = f(self, old)?;
        self.b.emit(Op::Put, &[value, updated], Imm::None, None);
        let free = self.b.iconst(0);
        self.b.emit(Op::Store, &[state, free], Imm::None, None);
        let id = self.call_runtime("msrt_addr_id", &[addr], MTy::INT)?;
        self.call_runtime("msrt_waitq_wake_all", &[id], MTy::UNIT)?;
        Ok(())
    }

    /// The address of the payload in the box of the handle `handle_expr`.
    pub(crate) fn shared_payload_ptr(
        &mut self,
        handle_expr: &ms_syntax::ast::Expr,
    ) -> Result<Value, Error> {
        let handle = self.shared_handle(handle_expr)?;
        let rec = self.builder_rec(self.ty_of(handle))?;
        let addr = self
            .b
            .emit(Op::SharedAddr, &[handle], Imm::None, Some(MTy::PTR))
            .expect("addr");
        Ok(self
            .b
            .emit(Op::PtrField, &[addr], Imm::Field(rec, 0), Some(MTy::PTR))
            .expect("field"))
    }

    /// Waits while the box at `addr` is busy for the access: a read waits while a call or update
    /// changes the box, a change waits until no call holds it. Waiting on this task's own hold (a
    /// callback, or a second handle) faults.
    fn wait_turn(&mut self, addr: Value, state: Value, read: bool) -> Result<(), Error> {
        let (check, busy, free) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(check, &[]);
        self.b.switch_to(check);
        let word = self
            .b
            .emit(Op::Load, &[state], Imm::Ty(MTy::INT), Some(MTy::INT))
            .expect("load");
        let zero = self.b.iconst(0);
        let flag = self.b.icmp(if read { Cc::Lt } else { Cc::Ne }, word, zero);
        self.b.br_if(flag, busy, &[], free, &[]);
        self.b.seal_block(busy);
        self.b.seal_block(free);
        self.b.switch_to(busy);
        let id = self.call_runtime("msrt_addr_id", &[addr], MTy::INT)?;
        self.call_runtime("msrt_shared_wait", &[id], MTy::UNIT)?;
        self.b.br(check, &[]);
        self.b.seal_block(check);
        self.b.switch_to(free);
        Ok(())
    }

    /// The `Shared` handle a place such as `stats.items[0].name` reads through, if any.
    pub(crate) fn shared_root<'e>(
        &self,
        e: &'e ms_syntax::ast::Expr,
    ) -> Option<&'e ms_syntax::ast::Expr> {
        use ms_syntax::ast::ExprKind;
        let mut cur = e;
        loop {
            if self.through_shared(cur) {
                return Some(cur);
            }
            cur = match &cur.kind {
                ExprKind::Member { left, .. }
                | ExprKind::Index { left, .. }
                | ExprKind::Apply { left, .. } => left,
                ExprKind::Probe(t) => t,
                _ => return None,
            };
        }
    }

    /// The same key for every mention of one local handle, and the node otherwise.
    fn shared_key(&self, e: &ms_syntax::ast::Expr) -> String {
        match self.hir.resolution(e) {
            ms_check::hir::Resolution::Local(b) => format!("local {}", b.uid),
            _ => format!("node {:?}", e.id),
        }
    }

    /// Holds, for the call about to run, the box of every handle the call's `var` arguments read
    /// through: another task's access waits until `shared_release`, and a cancelled or faulted
    /// call releases it on the cleanup path.
    pub(crate) fn shared_hold(
        &mut self,
        places: &[Option<ms_syntax::ast::Expr>],
    ) -> Result<Vec<(String, Value)>, Error> {
        self.shared_hold_modes(places, &[])
    }

    /// Holds the boxes the borrowed `places` read through for reading, before the call's
    /// arguments are evaluated: reads share a box, and a change waits until they end, so a
    /// payload a parked call borrows stays in place.
    pub(crate) fn shared_read_hold(
        &mut self,
        places: &[&ms_syntax::ast::Expr],
    ) -> Result<Vec<(String, Value)>, Error> {
        let places: Vec<Option<ms_syntax::ast::Expr>> =
            places.iter().map(|p| Some((*p).clone())).collect();
        self.shared_hold_modes(&places, &vec![true; places.len()])
    }

    /// Holds the boxes `places` read through, each for reading when `reads` says so at its
    /// position and otherwise for a change.
    pub(crate) fn shared_hold_modes(
        &mut self,
        places: &[Option<ms_syntax::ast::Expr>],
        reads: &[bool],
    ) -> Result<Vec<(String, Value)>, Error> {
        let mut holds = Vec::new();
        for (i, place) in places.iter().enumerate() {
            let Some(place) = place else {
                continue;
            };
            let read = reads.get(i).copied().unwrap_or(false);
            let Some(root) = self.shared_root(place) else {
                continue;
            };
            let key = self.shared_key(root);
            let held = self.held.contains(&key) || (read && self.read_held.contains(&key));
            if held || !self.is_place(root) {
                continue;
            }
            let handle = self.shared_handle(root)?;
            if self.dead {
                break;
            }
            let rec = self.builder_rec(self.ty_of(handle))?;
            let addr = self
                .b
                .emit(Op::SharedAddr, &[handle], Imm::None, Some(MTy::PTR))
                .expect("addr");
            let state = self
                .b
                .emit(Op::PtrField, &[addr], Imm::Field(rec, 1), Some(MTy::PTR))
                .expect("field");
            self.wait_turn(addr, state, read)?;
            let id = self.call_runtime("msrt_addr_id", &[addr], MTy::INT)?;
            let mode = self.b.iconst(i64::from(read));
            self.call_runtime("msrt_shared_hold", &[id, state, mode], MTy::UNIT)?;
            if read {
                self.read_held.push(key.clone());
            } else {
                self.held.push(key.clone());
            }
            holds.push((key, id));
        }
        Ok(holds)
    }

    /// Ends the holds `shared_hold` took, last first, and wakes a task waiting for each box.
    pub(crate) fn shared_release(&mut self, holds: Vec<(String, Value)>) -> Result<(), Error> {
        for (key, id) in holds.into_iter().rev() {
            // Each key is held once at a time, either for reading or for a change.
            self.held.retain(|k| *k != key);
            self.read_held.retain(|k| *k != key);
            if !self.dead {
                self.call_runtime("msrt_shared_release", &[id], MTy::UNIT)?;
            }
        }
        Ok(())
    }

    /// `Shared(value)`: the value moves into a new box with one holder, and the last holder's drop
    /// closes it.
    pub(crate) fn construct_shared(
        &mut self,
        view: &ms_check::hir::CallView<'_>,
        t: &ms_check::types::Ty,
        handle: MTy,
    ) -> Result<Val, Error> {
        let [a] = view.arguments.as_slice() else {
            return Err(Error::new("Shared takes one value"));
        };
        let x = self.expr(a.expr)?;
        if self.dead {
            return Ok(x);
        }
        if let Some(held) = t.args.first() {
            self.register_shared_close(held, handle)?;
        }
        let mut payload = self.owned(x);
        if a.wrap_optional.is_some() {
            payload = self.b.opt_some(payload);
        }
        let v = self.shared_new(payload, handle);
        Ok(Val { v, own: true })
    }

    /// A new box holding `payload`, not in use.
    pub(crate) fn shared_new(&mut self, payload: Value, handle: MTy) -> Value {
        let rec = self.builder_rec(handle).expect("shared handle");
        let free = self.b.iconst(0);
        let state = self.b.rec_new(rec, &[payload, free]);
        self.b
            .emit(Op::SharedNew, &[state], Imm::None, Some(handle))
            .expect("shared result")
    }
}
