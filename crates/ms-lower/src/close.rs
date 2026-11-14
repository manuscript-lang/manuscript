//! Closing resources: a binding's `close` runs on every way out of its scope, and the parts a
//! holder owns close with it.

use crate::Error;
use crate::cx::HelperKey;
use crate::func::{FnLower, RawSlot};
use crate::text::runtime_fn;
use ms_check::api::ast::*;
use ms_check::api::ownership::BindingFact;
use ms_check::api::types as ct;
use ms_check::api::types::Builtin;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, FuncId, FuncKind, Imm, Linkage, Mode, Op, Param, Value};
use ms_mir::types::{AltId, IfaceId, Native, Std, Ty as MTy, TyKind, TypeId};

/// How a binding is closed.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub(crate) enum CloseKind {
    /// An interface value: the vtable entry.
    Iface(IfaceId, u32),
    /// A source instance, which may hand `self` back through a slot.
    Func { fid: FuncId, writes_back: bool },
}

/// A complete owned resource held as a pending operand, including intact wrapper payloads.
#[derive(Clone)]
pub(crate) struct ResourceTemp {
    slot: Value,
    /// The close function the pass runs on the slot (`scope.own` kind).
    owner_kind: u32,
    kind: CloseKind,
}

impl CloseKind {
    /// Whether a value held in a variable can be closed as it is.
    pub(crate) fn in_value(&self) -> bool {
        !self.writes_back()
    }

    /// Whether the close changes the value it closes, so it needs the value's own storage.
    fn writes_back(&self) -> bool {
        matches!(
            self,
            CloseKind::Func {
                writes_back: true,
                ..
            }
        )
    }
}

/// A field to close: its index, MIR type and close.
type Part = (u32, MTy, CloseKind);

/// What a type, alternative or collection holds that needs closing.
enum Shape {
    /// Type fields: index, type, close; last declared first.
    Type(TypeId, Vec<Part>),
    /// The fields to close in each case that has any.
    Alt(AltId, Vec<(u32, Vec<Part>)>),
    /// The payload of an `Optional`.
    Opt(MTy, CloseKind),
    /// The elements of a list, last first.
    List(MTy, CloseKind),
    /// The values of a map, newest entry first: map, key and value types, the key and value
    /// glue scopes, and the value's close.
    Map(MTy, MTy, MTy, u32, u32, CloseKind),
}

/// Closes the parts `shape` names in the value stored at `ptr`, each in place.
fn emit_parts(b: &mut FuncBuilder<'_>, ptr: Value, shape: Shape) {
    match shape {
        Shape::Type(r, parts) => {
            for (i, ft, k) in parts {
                let fp = b
                    .emit(Op::PtrField, &[ptr], Imm::Field(r, i), Some(MTy::PTR))
                    .expect("field address");
                close_at(b, &k, fp, ft);
            }
        }
        Shape::Alt(a, cases) => {
            // A case's fields share the value's storage with every other case, so they have no
            // address of their own: the value is taken apart, its parts closed, and rebuilt.
            let alt_ty = b.m.types.alt(a);
            let cur = b
                .emit(Op::Load, &[ptr], Imm::Ty(alt_ty), Some(alt_ty))
                .expect("load");
            let tag = b.alt_tag(cur);
            let exit = b.new_block();
            let blocks: Vec<_> = cases.iter().map(|_| b.new_block()).collect();
            let arms: Vec<(i64, _)> = cases
                .iter()
                .zip(&blocks)
                .map(|((c, _), blk)| (*c as i64, *blk))
                .collect();
            b.switch(tag, &arms, exit);
            for ((c, parts), blk) in cases.into_iter().zip(blocks) {
                b.seal_block(blk);
                b.switch_to(blk);
                let v = b
                    .emit(Op::Take, &[ptr], Imm::Ty(alt_ty), Some(alt_ty))
                    .expect("take");
                let n = b.m.alts[a.index()].cases[c as usize].fields.len();
                let mut fields: Vec<Value> =
                    (0..n as u32).map(|j| b.alt_take(a, c, j, v)).collect();
                let mask = if n >= 32 { u32::MAX } else { (1u32 << n) - 1 };
                b.alt_release(a, c, mask, v);
                for (j, ft, k) in parts {
                    fields[j as usize] = close_owned(b, &k, fields[j as usize], ft);
                }
                let rebuilt = b.alt_new(a, c, &fields);
                b.emit(Op::Put, &[ptr, rebuilt], Imm::None, None);
                b.br(exit, &[]);
            }
            b.seal_block(exit);
            b.switch_to(exit);
        }
        Shape::Opt(inner, k) => {
            let opt_ty = b.m.types.opt(inner);
            let cur = b
                .emit(Op::Load, &[ptr], Imm::Ty(opt_ty), Some(opt_ty))
                .expect("load");
            let some = b.opt_is_some(cur);
            let (yes, exit) = (b.new_block(), b.new_block());
            b.br_if(some, yes, &[], exit, &[]);
            b.seal_block(yes);
            b.switch_to(yes);
            let v = b
                .emit(Op::Take, &[ptr], Imm::Ty(opt_ty), Some(opt_ty))
                .expect("take");
            let x = b.opt_unbox(v);
            let x = close_owned(b, &k, x, inner);
            let rebuilt = b.opt_some(x);
            b.emit(Op::Put, &[ptr, rebuilt], Imm::None, None);
            b.br(exit, &[]);
            b.seal_block(exit);
            b.switch_to(exit);
        }
        Shape::List(elem, k) => {
            let list_ty = b.m.types.list(elem);
            let l = b
                .emit(Op::Load, &[ptr], Imm::Ty(list_ty), Some(list_ty))
                .expect("load");
            let n = b.list_len(l);
            let idx = b.declare_var(MTy::INT, Mode::Borrow);
            b.def_var(idx, n);
            let (header, body, exit) = (b.new_block(), b.new_block(), b.new_block());
            b.br(header, &[]);
            b.switch_to(header);
            let i = b.use_var(idx);
            let zero = b.iconst(0);
            let more = b.icmp(Cc::Gt, i, zero);
            b.br_if(more, body, &[], exit, &[]);
            b.seal_block(body);
            b.switch_to(body);
            let i = b.use_var(idx);
            let one = b.iconst(1);
            let j = b.binop(Op::ISub, i, one);
            b.def_var(idx, j);
            let ep = b
                .emit(Op::ListAddrU, &[l, j], Imm::None, Some(MTy::PTR))
                .expect("element address");
            close_at(b, &k, ep, elem);
            b.br(header, &[]);
            b.seal_block(header);
            b.seal_block(exit);
            b.switch_to(exit);
        }
        Shape::Map(mt, kt, vt, ks, vs, k) => {
            let m = b
                .emit(Op::Load, &[ptr], Imm::Ty(mt), Some(mt))
                .expect("load");
            let count_fn = runtime_fn(b.m, "msrt_map_slot_count", &[mt], MTy::INT);
            let n = b.call_rt(count_fn, &[m]);
            let desc = |b: &mut FuncBuilder<'_>, t: MTy, scope: u32| {
                b.emit(Op::TypeDesc, &[], Imm::Ty(t.scoped(scope)), Some(MTy::PTR))
                    .expect("typedesc")
            };
            let (kd, vd) = (desc(b, kt, ks), desc(b, vt, vs));
            let slot = |b: &mut FuncBuilder<'_>| {
                b.emit(Op::Slot, &[], Imm::Ty(MTy::PTR), Some(MTy::PTR))
                    .expect("slot")
            };
            let (kp, vp) = (slot(b), slot(b));
            let idx = b.declare_var(MTy::INT, Mode::Borrow);
            b.def_var(idx, n);
            let (header, probe, body, exit) =
                (b.new_block(), b.new_block(), b.new_block(), b.new_block());
            b.br(header, &[]);
            b.switch_to(header);
            let i = b.use_var(idx);
            let zero = b.iconst(0);
            let more = b.icmp(Cc::Gt, i, zero);
            b.br_if(more, probe, &[], exit, &[]);
            b.seal_block(probe);
            b.switch_to(probe);
            let i = b.use_var(idx);
            let one = b.iconst(1);
            let j = b.binop(Op::ISub, i, one);
            b.def_var(idx, j);
            let entry_fn = runtime_fn(
                b.m,
                "msrt_map_entry_ptrs",
                &[mt, MTy::PTR, MTy::PTR, MTy::INT, MTy::PTR, MTy::PTR],
                MTy::BOOL,
            );
            let live = b.call_rt(entry_fn, &[m, kd, vd, j, kp, vp]);
            b.br_if(live, body, &[], header, &[]);
            b.seal_block(body);
            b.switch_to(body);
            let vaddr = b
                .emit(Op::Load, &[vp], Imm::Ty(MTy::PTR), Some(MTy::PTR))
                .expect("load");
            close_at(b, &k, vaddr, vt);
            b.br(header, &[]);
            b.seal_block(header);
            b.seal_block(exit);
            b.switch_to(exit);
        }
    }
}

/// A resource field of a binding with moved parts that has an owner of its own.
struct SplitItem {
    path: Vec<u32>,
    ptr: Value,
    thunk: FuncId,
    /// The field's path by name when some path moves it out.
    moved: Option<Vec<ct::Name>>,
}

/// Drops the parts of the type of type `ty` stored at `p` (reached by `prefix`) that are not
/// among the fields at `owned`.
fn drop_rest(b: &mut FuncBuilder, p: Value, ty: MTy, prefix: &mut Vec<u32>, owned: &[Vec<u32>]) {
    let TyKind::Type(r) = b.m.types.kind(ty).clone() else {
        return;
    };
    let fields: Vec<MTy> = b.m.type_defs[r.index()]
        .fields
        .iter()
        .map(|f| f.1)
        .collect();
    for (i, fty) in fields.into_iter().enumerate() {
        prefix.push(i as u32);
        if !owned.iter().any(|o| o == prefix) && b.m.needs_drop(fty) {
            let fp = b
                .emit(Op::PtrField, &[p], Imm::Field(r, i as u32), Some(MTy::PTR))
                .expect("field address");
            if owned.iter().any(|o| o.starts_with(prefix)) {
                drop_rest(b, fp, fty, prefix, owned);
            } else {
                let o = b
                    .emit(Op::Take, &[fp], Imm::Ty(fty), Some(fty))
                    .expect("field");
                b.emit(Op::Drop, &[o], Imm::None, None);
            }
        }
        prefix.pop();
    }
}

/// Closes the value of type `ty` stored at `ptr`, in place. A close that fails here has nowhere to
/// return its error (a part of a holder, a temporary, a replaced value), so it faults; only the
/// scope-end close of a binding propagates it, through [`close_at_result`].
fn close_at(b: &mut FuncBuilder<'_>, kind: &CloseKind, ptr: Value, ty: MTy) {
    let r = close_at_result(b, kind, ptr, ty);
    close_error_fault(b, r, None);
}

/// Closes the value at `ptr` and types a failed close in `failed` instead of faulting.
fn close_at_deferred(
    b: &mut FuncBuilder<'_>,
    kind: &CloseKind,
    ptr: Value,
    ty: MTy,
    failed: ms_mir::builder::Var,
) {
    let r = close_at_result(b, kind, ptr, ty);
    let rty = b.ty(r);
    if let TyKind::Alt(a) = b.m.types.kind(rty).clone()
        && let Some(err) = b.m.alts[a.index()].error_case()
    {
        let tag = b.alt_tag(r);
        let k = b.iconst(err as i64);
        let is_err = b.icmp(Cc::Eq, tag, k);
        let prev = b.use_var(failed);
        let any = b.binop(Op::Or, prev, is_err);
        b.def_var(failed, any);
    }
    if b.m.needs_drop(rty) {
        b.emit(Op::Drop, &[r], Imm::None, None);
    }
}

/// Closes the value at `ptr` and drops the result: for the cleanup stack a fault runs, where the
/// failure is already being reported.
fn close_at_silent(b: &mut FuncBuilder<'_>, kind: &CloseKind, ptr: Value, ty: MTy) {
    let r = close_at_result(b, kind, ptr, ty);
    if b.m.needs_drop(b.ty(r)) {
        b.emit(Op::Drop, &[r], Imm::None, None);
    }
}

/// Closes the owned `v` of type `ty` and hands it back: what the close leaves behind is still
/// the caller's to drop. A failed close faults.
fn close_owned(b: &mut FuncBuilder<'_>, kind: &CloseKind, v: Value, ty: MTy) -> Value {
    let (v, r) = close_owned_result(b, kind, v, ty);
    close_error_fault(b, r, None);
    v
}

/// Closes the owned `v`: the value after the close, and the close's result.
fn close_owned_result(
    b: &mut FuncBuilder<'_>,
    kind: &CloseKind,
    v: Value,
    ty: MTy,
) -> (Value, Value) {
    match kind {
        CloseKind::Iface(iface, k) => (v, b.call_method(*iface, *k, v, &[])),
        CloseKind::Func {
            fid,
            writes_back: false,
        } => (v, b.call(*fid, &[v])),
        CloseKind::Func {
            writes_back: true, ..
        } => {
            // The close changes the value in memory: it works on the value's own storage.
            let droppable = b.m.needs_drop(ty);
            let slot = b
                .emit(Op::Slot, &[], Imm::Ty(ty), Some(MTy::PTR))
                .expect("slot");
            b.emit(
                if droppable { Op::Put } else { Op::Store },
                &[slot, v],
                Imm::None,
                None,
            );
            let r = close_at_result(b, kind, slot, ty);
            let take = if droppable { Op::Take } else { Op::Load };
            let after = b.emit(take, &[slot], Imm::Ty(ty), Some(ty)).expect("take");
            (after, r)
        }
    }
}

/// Faults when `r`, the `Result` of a close, is an error; otherwise releases it.
fn close_error_fault(b: &mut FuncBuilder<'_>, r: Value, slot: Option<(Value, MTy)>) {
    let rty = b.ty(r);
    let TyKind::Alt(a) = b.m.types.kind(rty).clone() else {
        return;
    };
    let Some(err) = b.m.alts[a.index()].error_case() else {
        return;
    };
    let tag = b.alt_tag(r);
    let k = b.iconst(err as i64);
    let is_err = b.icmp(Cc::Eq, tag, k);
    let (bad, good) = (b.new_block(), b.new_block());
    b.br_if(is_err, bad, &[], good, &[]);
    b.seal_block(bad);
    b.seal_block(good);
    b.switch_to(bad);
    // The fault never returns to the caller that drops what the close leaves behind.
    if b.m.needs_drop(rty) {
        b.emit(Op::Drop, &[r], Imm::None, None);
    }
    if let Some((ptr, ty)) = slot
        && b.m.needs_drop(ty)
    {
        let left = b
            .emit(Op::Take, &[ptr], Imm::Ty(ty), Some(ty))
            .expect("value");
        b.emit(Op::Drop, &[left], Imm::None, None);
    }
    let msg = b.str_lit("a resource could not be closed: its close returned an error");
    let ext = crate::text::runtime_fn(b.m, "msrt_fault_string", &[MTy::STR], MTy::UNIT);
    b.call_rt(ext, &[msg]);
    b.unreachable();
    b.switch_to(good);
    if b.m.needs_drop(rty) {
        b.emit(Op::Drop, &[r], Imm::None, None);
    }
}

/// Calls the close operation on the value of type `ty` stored at `ptr`, in place; the result is
/// `Unit`, or the `Result` of a close that can fail, which the caller owns. A close that changes
/// `self` takes the address; the others take the value as a borrow.
fn close_at_result(b: &mut FuncBuilder<'_>, kind: &CloseKind, ptr: Value, ty: MTy) -> Value {
    match kind {
        CloseKind::Func {
            fid,
            writes_back: true,
        } => b.call(*fid, &[ptr]),
        _ => {
            let v = b
                .emit(Op::Load, &[ptr], Imm::Ty(ty), Some(ty))
                .expect("load");
            match kind {
                CloseKind::Iface(iface, k) => b.call_method(*iface, *k, v, &[]),
                CloseKind::Func { fid, .. } => b.call(*fid, &[v]),
            }
        }
    }
}

impl FnLower<'_> {
    /// Holds an intact owned resource until a later operand finishes. Its ordered temporary
    /// entry handles source-level exits; the registered slot handles faults and cancellation.
    pub(crate) fn hold_resource_temp(&mut self, v: Value) -> Result<Option<Value>, Error> {
        let ty = self.ty_of(v);
        let Some(kind) = self.part_closer_mir(ty)? else {
            return Ok(None);
        };
        Ok(Some(self.hold_resource_temp_with(v, kind)))
    }

    /// Registers an intact owned value with its already-resolved closer.
    pub(crate) fn hold_resource_temp_with(&mut self, v: Value, kind: CloseKind) -> Value {
        let ty = self.ty_of(v);
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(ty), Some(MTy::PTR))
            .expect("resource temporary slot");
        self.move_into(slot, v);
        let thunk = self.close_thunk_as(&kind, ty, true, true);
        let owner_kind = thunk.index() as u32 + 2;
        let scope = self.own_raw_value(slot, owner_kind);
        let key = self
            .b
            .emit(Op::Load, &[slot], Imm::Ty(ty), Some(ty))
            .expect("resource temporary view");
        self.resource_temps.insert(
            key,
            ResourceTemp {
                slot,
                owner_kind,
                kind,
            },
        );
        self.pass_temps.insert(key, scope);
        self.temps.push(key);
        key
    }

    /// What the pass owns for the pending temporary `t`, and with which close: a resource's slot,
    /// or the value itself.
    pub(crate) fn temp_owner(&self, t: Value) -> (Value, u32) {
        self.resource_temps
            .get(&t)
            .map_or((t, 0), |r| (r.slot, r.owner_kind))
    }

    /// The authoritative slot for an intact pending resource.
    pub(crate) fn resource_temp_slot(&self, key: Value) -> Option<Value> {
        self.resource_temps.get(&key).map(|owner| owner.slot)
    }

    /// A leaf operation has consumed the slot on success. Nothing remains to take or drop.
    pub(crate) fn retire_consumed_resource_temp(&mut self, key: Value) {
        self.unhold_temp(key);
    }

    /// Permanently retires only this resource's cleanup and takes its sole owned value.
    /// Newer lexical owners remain registered. Keep the metadata: emitting an early-return
    /// branch must not change the continuing path, but each runtime path consumes the handle once.
    pub(crate) fn take_resource_temp(&mut self, key: Value) -> (Value, CloseKind) {
        let owner = self.resource_temps[&key].clone();
        let v = self.move_out(owner.slot, self.ty_of(key));
        if !self.dead {
            self.b.emit(Op::ScopeDisown, &[owner.slot], Imm::None, None);
        }
        (v, owner.kind)
    }

    /// Drops an owned temporary at the end of its statement, closing it first when it is a
    /// resource (`open().id()`).
    pub(crate) fn drop_temp(&mut self, v: Value) {
        if self.resource_temps.contains_key(&v) {
            let (v, kind) = self.take_resource_temp(v);
            let v = self.close_discarded_kind(&kind, v);
            self.drop_value(v);
            return;
        }
        let v = self.close_temp(v);
        self.drop_value(v);
    }

    /// Closes an owned temporary that is a resource; the value after the close.
    fn close_temp(&mut self, v: Value) -> Value {
        let mt = self.b.ty(v);
        let Some(kind) = self.temp_closer(mt) else {
            return v;
        };
        close_owned(&mut self.b, &kind, v, mt)
    }

    /// Whether the temporary `v` closes before it drops.
    pub(crate) fn is_resource_temp(&mut self, v: Value) -> bool {
        let mt = self.b.ty(v);
        self.temp_closer(mt).is_some()
    }

    fn temp_closer(&mut self, mt: MTy) -> Option<CloseKind> {
        let ty = self.cx.source_tys.get(mt.0 as usize).cloned()?;
        // A resource, or a type or list holding one (only read in place: the checker rejects
        // moving a resource part out of a computed value). A wrapper (`Result`, `Optional`) may
        // have had its payload moved out already, so it closes only when it is itself one.
        if self.cx.classes.class(self.syms, &ty) != ms_check::api::ownership::Class::Resource
            || (self.closeable_method(&ty).is_none()
                && (ty.is(Builtin::Optional) || ty.is(Builtin::Result)))
        {
            return None;
        }
        self.part_closer(&ty).ok().flatten()
    }

    /// The close operation of a value of the MIR type `ty` holding a resource, if it is one.
    pub(crate) fn part_closer_mir(&mut self, ty: MTy) -> Result<Option<CloseKind>, Error> {
        // An interface value with `close` carries its closer in the vtable, whatever the checker type.
        if let TyKind::Iface(iface) = self.b.m.types.kind(ty).clone() {
            return Ok(self.iface_closer(iface));
        }
        let Some(ct) = self.cx.source_tys.get(ty.0 as usize).cloned() else {
            return self.generated_closer(ty);
        };
        self.part_closer(&ct)
    }

    /// The closer of a MIR type with no checker type recorded: `source_tys` is filled when a checker
    /// type is lowered, so an optional lowering builds first (an argument converted to `T?` before the
    /// callee's parameter type is lowered) has no entry yet. An optional closes what it holds.
    fn generated_closer(&mut self, ty: MTy) -> Result<Option<CloseKind>, Error> {
        let TyKind::Opt(inner) = self.b.m.types.kind(ty).clone() else {
            // A type, alternative, list or object type is registered when its checker type is
            // lowered; one that is not would be taken for plain data and never closed. A
            // borrowing variant of an alternative owns only the cases it does not borrow.
            debug_assert!(
                match self.b.m.types.kind(ty) {
                    TyKind::Type(_) | TyKind::List(_) | TyKind::Obj(..) => false,
                    TyKind::Alt(a) => self.b.m.alts[a.index()].borrowed != 0,
                    _ => true,
                },
                "MIR type {ty:?} has no checker type, so its resources cannot be closed"
            );
            return Ok(None);
        };
        let Some(kind) = self.part_closer_mir(inner)? else {
            return Ok(None);
        };
        Ok(Some(self.optional_resource_closer(ty, inner, kind)))
    }

    /// The extra ABI optional around an owned function-value argument closes that
    /// argument in place. The resolved payload closer keeps module-local evidence.
    pub(crate) fn optional_resource_closer(
        &mut self,
        ty: MTy,
        inner: MTy,
        kind: CloseKind,
    ) -> CloseKind {
        debug_assert_eq!(self.b.m.types.kind(ty), &TyKind::Opt(inner));
        let key = HelperKey::CloseOptional(ty, kind.clone());
        if let Some(fid) = self.cx.helpers.get(&key) {
            return CloseKind::Func {
                fid: *fid,
                writes_back: true,
            };
        }
        let params = vec![Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        }];
        let mut b = FuncBuilder::new(self.b.m, "close_optional", params, MTy::UNIT);
        b.func_mut().linkage = Linkage::Internal;
        let ptr = b.params()[0];
        emit_parts(&mut b, ptr, Shape::Opt(inner, kind));
        let unit = b.unit();
        b.ret(Some(unit));
        let func = b.into_func();
        let fid = self.b.m.add_func(func);
        self.cx.helpers.insert(key, fid);
        CloseKind::Func {
            fid,
            writes_back: true,
        }
    }

    /// Closes the value the local `l` holds, in place; the close's result.
    pub(crate) fn close_local_result(&mut self, l: &crate::func::Local, kind: &CloseKind) -> Value {
        if let Some(p) = l.slot {
            return close_at_result(&mut self.b, kind, p, l.ty);
        }
        let v = self.local_take(l);
        let (v, r) = close_owned_result(&mut self.b, kind, v, l.ty);
        self.local_put(l, v);
        r
    }

    /// `x.close()` on a value closed through its parts: the receiver `recv` is a local, closed
    /// in place, or a temporary, closed and released.
    pub(crate) fn close_receiver(
        &mut self,
        kind: &CloseKind,
        recv_expr: &Expr,
        recv: crate::func::Val,
    ) -> Result<(), Error> {
        if recv.own {
            let ty = self.b.ty(recv.v);
            let v = close_owned(&mut self.b, kind, recv.v, ty);
            self.drop_value(v);
            return Ok(());
        }
        let ms_check::api::hir::Resolution::Local(b) = self.hir.resolution(recv_expr) else {
            return Err(Error::new(
                "a part-wise close of a borrowed value that is not a local",
            ));
        };
        if let Some(a) = self.aliases.get(&b.uid).cloned() {
            // A borrow of a part (`if var value = map[key]?`): the part is closed where it lies,
            // taken out of its holder and put back closed.
            let kind = kind.clone();
            return self.alias_update(&a, &[], &mut |s, v| {
                let ty = s.b.ty(v);
                let (v, r) = close_owned_result(&mut s.b, &kind, v, ty);
                close_error_fault(&mut s.b, r, None);
                Ok(v)
            });
        }
        let l = self.local(&b)?;
        let r = self.close_local_result(&l, kind);
        close_error_fault(&mut self.b, r, None);
        Ok(())
    }

    /// Releases `x`, closing it first when it is an owned temporary of a resource type that
    /// nothing takes.
    pub(crate) fn close_finish(&mut self, x: crate::func::Val) {
        if !x.own || self.dead {
            return;
        }
        let mt = self.b.ty(x.v);
        let kind = self
            .cx
            .source_tys
            .get(mt.0 as usize)
            .cloned()
            .and_then(|ty| self.part_closer(&ty).ok().flatten());
        let v = match kind {
            Some(kind) => self.close_discarded_kind(&kind, x.v),
            None => x.v,
        };
        self.drop_value(v);
    }

    /// Drops a discarded statement result, closing it first when it holds a resource nothing
    /// took: unlike a pending temporary it may be a wrapper (`xs.pop()` is an `Optional`).
    pub(crate) fn drop_unused(&mut self, v: Value, ty: &ct::Ty) {
        let mt = self.b.ty(v);
        let v = match self.part_closer(ty) {
            Ok(Some(kind)) => close_owned(&mut self.b, &kind, v, mt),
            _ => v,
        };
        self.drop_value(v);
    }

    /// Binds `binding` to `x` and registers its close operation: a fault runs it through the
    /// runtime's cleanup stack, and leaving the binding's scope closes the current value.
    pub(crate) fn bind_closing(
        &mut self,
        binding: &ct::BindingRef,
        x: crate::func::Val,
        cleanup: Option<&ct::MethodRef>,
    ) -> Result<(), Error> {
        let Some(kind) = self.closer_opt(cleanup, &binding.ty)? else {
            self.bind_local(binding, x);
            return Ok(());
        };
        self.bind_closing_kind(binding, x, kind)
    }

    /// [`Self::bind_closing`] with the close operation already chosen.
    /// The `Result` type a close function returns, when its close can fail.
    fn close_result_ty(&self, kind: &CloseKind) -> Option<MTy> {
        let CloseKind::Func { fid, .. } = kind else {
            return None;
        };
        let r = self.b.m.funcs[fid.index()].ret;
        matches!(self.b.m.types.kind(r), TyKind::Alt(a) if self.b.m.alts[a.index()].std == Std::Result)
            .then_some(r)
    }

    /// Whether the elaborate pass can return a failed close of this function: the function
    /// leaves by a plain return, with no frame work that only `emit_return` does and no cleanup
    /// that lowering still has to run on the way out.
    fn fallible_close_ok(&mut self, kind: &CloseKind, uid: usize) -> bool {
        // The error exit returns at once, so no cleanup that lowering still runs may be pending:
        // every enclosing scope holds nothing else to drop or close.
        // A local the pass owns at its exits needs no close: the error exit releases the owned
        // values still live, as it does for any return.
        let nothing_else = self
            .scopes
            .iter()
            .all(|s| s.iter().all(|u| *u == uid || self.raw_vars.contains_key(u)));
        // The temporaries the pass owns are in its scopes' chains already.
        let temps_empty = self.temps.iter().all(|t| self.pass_temps.contains_key(t));
        nothing_else
            && temps_empty
            && self.close_result_ty(kind).is_some()
            // A `var` parameter that left its slot is put back by `emit_return` only.
            && self
                .var_slots
                .iter()
                .all(|v| self.locals.get(&v.uid).is_some_and(|l| l.slot == Some(v.ptr)))
            && self.default_frames.is_empty()
            && self.fixture.is_none()
    }

    /// Gives the slot close `thunk` the function that returns its `Result`, and this function
    /// the exit that turns a failed close into its return value.
    fn fallible_slot_close(&mut self, kind: &CloseKind, ty: MTy, thunk: FuncId) {
        let Some(rty) = self.close_result_ty(kind) else {
            return;
        };
        if self.b.m.funcs[thunk.index()].slot_result.is_none() {
            let key = HelperKey::CloseResult(thunk);
            let rc = match self.cx.helpers.get(&key) {
                Some(f) => *f,
                None => {
                    let ps = vec![Param {
                        ty: MTy::PTR,
                        mode: Mode::Borrow,
                    }];
                    let mut b = FuncBuilder::new(self.b.m, "close", ps, rty);
                    b.func_mut().linkage = Linkage::Internal;
                    b.func_mut().kind = FuncKind::Normal;
                    let p = b.params()[0];
                    let r = close_at_result(&mut b, kind, p, ty);
                    b.ret(Some(r));
                    let f = b.into_func();
                    let id = self.b.m.add_func(f);
                    self.cx.helpers.insert(key, id);
                    id
                }
            };
            self.b.m.funcs[thunk.index()].slot_result = Some(rc);
        }
        let exit = (self.close_exit(rty, false), self.close_exit(rty, true));
        self.b.func_mut().close_exit = Some(exit);
    }

    /// The function that returns a failed close `e` of type `rty` as this function's result;
    /// with `pending`, it also takes the value the function was already returning, which stays
    /// when it is an error (the first error wins).
    fn close_exit(&mut self, rty: MTy, pending: bool) -> FuncId {
        let ret = self.ret_ty;
        // A function that returns a borrow hands its pending result on without owning it.
        let borrowed = self.b.func_mut().ret_borrowed;
        let key = HelperKey::CloseExit(rty, ret, pending, borrowed);
        if let Some(f) = self.cx.helpers.get(&key) {
            return *f;
        }
        let mut ps = vec![Param {
            ty: rty,
            mode: Mode::Move,
        }];
        if pending {
            ps.push(Param {
                ty: ret,
                mode: if borrowed { Mode::Borrow } else { Mode::Move },
            });
        }
        let mut b = FuncBuilder::new(self.b.m, "close_exit", ps, ret);
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().kind = FuncKind::Normal;
        b.func_mut().ret_borrowed = borrowed && pending;
        let e = b.params()[0];
        if pending {
            let held = b.params()[1];
            let is_result = matches!(b.m.types.kind(ret), TyKind::Alt(a)
                if b.m.alts[a.index()].std == Std::Result);
            if is_result {
                let tag = b.alt_tag(held);
                let error = b.iconst(Std::ERROR as i64);
                let is_error = b.icmp(Cc::Eq, tag, error);
                let (keep, replace) = (b.new_block(), b.new_block());
                b.br_if(is_error, keep, &[], replace, &[]);
                b.seal_block(keep);
                b.seal_block(replace);
                b.switch_to(keep);
                if b.m.needs_drop(rty) {
                    b.emit(Op::Drop, &[e], Imm::None, None);
                }
                b.ret(Some(held));
                b.switch_to(replace);
            }
            if b.m.needs_drop(ret) && !borrowed {
                b.emit(Op::Drop, &[held], Imm::None, None);
            }
        }
        let TyKind::Alt(a) = b.m.types.kind(rty).clone() else {
            unreachable!("a fallible close returns a Result")
        };
        let err = Std::ERROR;
        // A function that returns a borrow cannot return the close's own error.
        let returned = match b.m.types.kind(ret).clone() {
            TyKind::Alt(ra)
                if !(borrowed && pending)
                    && b.m.alts[ra.index()].std == Std::Result
                    && b.m.alts[ra.index()].cases[err].fields[0].1
                        == b.m.alts[a.index()].cases[err].fields[0].1 =>
            {
                Some(ra)
            }
            _ => None,
        };
        match returned {
            Some(ra) => {
                let po = b.alt_take(a, err as u32, 0, e);
                b.alt_release(a, err as u32, 1, e);
                let out = b.alt_new(ra, err as u32, &[po]);
                b.ret(Some(out));
            }
            None => {
                close_error_fault(&mut b, e, None);
                b.unreachable();
            }
        }
        let f = b.into_func();
        let id = self.b.m.add_func(f);
        self.cx.helpers.insert(key, id);
        id
    }

    /// Whether the success of a fallible close carries no value, so the pass can stand in for a
    /// close that did not run (the value moved out) with a plain success.
    fn close_succeeds_with_unit(&self, kind: &CloseKind) -> bool {
        let Some(r) = self.close_result_ty(kind) else {
            return true;
        };
        let TyKind::Alt(a) = self.b.m.types.kind(r).clone() else {
            return false;
        };
        self.b.m.alts[a.index()].cases[Std::OK].fields[0].1 == MTy::UNIT
    }

    /// Whether the elaborate pass can close the owned binding that lives in memory: nothing
    /// closes it by hand, a move of it is one the pass tracks, and no closer of its scope was
    /// declared before it (the pass closes at the scope end, after the scope's other closers).
    fn raw_closable(&mut self, binding: &ct::BindingRef, kind: &CloseKind) -> bool {
        let uid = binding.uid;
        let unit_close = match kind {
            CloseKind::Func { fid, .. } => self.b.m.funcs[fid.index()].ret == MTy::UNIT,
            CloseKind::Iface(..) => true,
        };
        if !unit_close && !self.fallible_close_ok(kind, uid) {
            return false;
        }
        let own = &self.cx.ownership;
        let moves = own.moves.contains_key(&uid)
            || own.close_moves.contains_key(&uid)
            || own
                .binding_facts
                .has(uid, ms_check::api::ownership::BindingFact::ConditionalMove);
        let by_hand = own.binding_facts.has(uid, BindingFact::ExplicitClose)
            || own.binding_facts.has(uid, BindingFact::CloseHandled);
        !self.dead
            && (!moves || self.close_succeeds_with_unit(kind))
            && (!by_hand || self.close_succeeds_with_unit(kind))
    }

    /// Tells the pass the program closed (`closed`) or refilled the value in the raw slot.
    fn mark_raw_closed(&mut self, raw: &RawSlot, closed: bool) {
        let imm = Imm::Int(i64::from(closed));
        self.b.emit(Op::ScopeMark, &[raw.slot], imm, None);
    }

    /// The assignment to the raw slot `raw` of binding `uid` is next: the pass closes the value
    /// the slot still holds (a moved one registers a fresh cleanup entry), and the new value has
    /// not been closed by the program unless every lifetime handles its result.
    pub(crate) fn refill_raw(&mut self, uid: usize, raw: &RawSlot) {
        self.b.emit(Op::ScopeMark, &[raw.slot], Imm::Int(2), None);
        if (self.cx.ownership.binding_facts).has(uid, BindingFact::CloseHandled) {
            self.mark_raw_closed(raw, true);
        }
    }

    pub(crate) fn bind_closing_kind(
        &mut self,
        binding: &ct::BindingRef,
        x: crate::func::Val,
        kind: CloseKind,
    ) -> Result<(), Error> {
        // A `var` binding that changes lives in memory, so a fault or cancellation closes its
        // value at that moment and not the one it started with. So does a binding some path
        // moves out of (its cleanup entry holds the slot, so the paths that keep the value
        // register nothing twice), one whose close changes the value (the close works on the
        // value's own storage), and one a resource field moves out of (each field registers
        // its own address).
        let places = self
            .cx
            .ownership
            .resource_moves
            .get(&binding.uid)
            .filter(|p| !p.is_empty())
            .cloned();
        if binding.mutable
            || kind.writes_back()
            || places.is_some()
            || self.cx.ownership.close_moves.contains_key(&binding.uid)
        {
            self.slotted.insert(binding.uid);
        }
        self.redefined.insert(binding.uid);
        let raw = std::mem::replace(&mut self.raw_owners, false);
        // The pass closes a binding that lives in memory, whatever its close does to the value.
        let raw_ok = raw && places.is_none() && self.raw_closable(binding, &kind);
        if raw_ok {
            self.slotted.insert(binding.uid);
        }
        self.bind_local(binding, x);
        self.raw_owners = raw;
        let ty = self.locals[&binding.uid].ty;
        let slot = self.locals[&binding.uid].slot;
        if let Some(places) = places {
            return if raw {
                self.bind_split(binding, places)
            } else {
                Err(Error::new(
                    "a binding with moved fields the pass cannot own",
                ))
            };
        }
        if let Some(ptr) = slot
            && raw_ok
        {
            // The elaborate pass closes it where its scope ends, shielded, and drops what is left.
            let thunk = self.close_thunk(&kind, ty, true);
            if self.close_result_ty(&kind).is_some() {
                self.fallible_slot_close(&kind, ty, thunk);
            }
            if let Some(scope) = self.scopes.last_mut() {
                scope.retain(|u| *u != binding.uid);
            }
            self.own_raw_kind(binding.uid, ptr, thunk.index() as u32 + 2);
            let facts = &self.cx.ownership.binding_facts;
            let handled = facts.has(binding.uid, BindingFact::CloseHandled);
            let raw = RawSlot { slot: ptr, kind };
            if handled {
                // Every lifetime handles its result: the scope end's close drops it.
                self.mark_raw_closed(&raw, true);
            }
            self.raw_slots.insert(binding.uid, raw);
            return Ok(());
        }
        Err(Error::new(
            "a closing binding the elaborate pass cannot own (internal: report this program)",
        ))
    }

    /// A binding some path moves a resource field out of lives in memory. Each resource field is
    /// an owner of the pass that closes it, and a type owner declared before them drops
    /// everything else, so the pass closes the fields last declared first and the rest after.
    /// A move of a field disowns its owner.
    fn bind_split(
        &mut self,
        binding: &ct::BindingRef,
        places: ms_check::fxmap::HashMap<ms_check::api::ast::NodeId, Vec<ct::Name>>,
    ) -> Result<(), Error> {
        let uid = binding.uid;
        let root = self.locals[&uid]
            .slot
            .ok_or_else(|| Error::new("a split binding lives in memory"))?;
        let ty = ct::sub(&binding.ty, &self.subst);
        let mut tails: Vec<Vec<ct::Name>> = places.into_values().collect();
        tails.sort_by_key(|t| {
            t.iter()
                .map(|n| self.syms.str(n).to_string())
                .collect::<Vec<_>>()
        });
        tails.dedup();
        let mut items = Vec::new();
        self.split_fields(&ty, root, &[], &[], &tails, &mut items)?;
        let paths: Vec<Vec<u32>> = items.iter().map(|i| i.path.clone()).collect();
        let rest = self.split_rest_thunk(self.locals[&uid].ty, &paths);
        if let Some(scope) = self.scopes.last_mut() {
            scope.retain(|u| *u != uid);
        }
        let mut owners = vec![root];
        self.own_raw_kind(uid, root, rest.index() as u32 + 2);
        for item in items {
            self.own_raw_value(item.ptr, item.thunk.index() as u32 + 2);
            owners.push(item.ptr);
            if let Some(names) = item.moved {
                self.split_places.insert((uid, names), item.ptr);
            }
        }
        self.split_owners.insert(uid, owners);
        Ok(())
    }

    /// The owners for the resource fields of the type of checked type `ty` stored at `ptr`,
    /// reached by `prefix` from the binding; `tails` are the moved places below it, by name.
    fn split_fields(
        &mut self,
        ty: &ct::Ty,
        ptr: Value,
        prefix: &[u32],
        names: &[ct::Name],
        tails: &[Vec<ct::Name>],
        items: &mut Vec<SplitItem>,
    ) -> Result<(), Error> {
        let mt = self.mty(ty)?;
        let TyKind::Type(r) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("a moved field of a non-type"));
        };
        for (i, f) in ct::fields(ty).iter().enumerate() {
            if self.cx.classes.class(self.syms, &f.ty) != ms_check::api::ownership::Class::Resource
            {
                continue;
            }
            let fty = self.b.m.type_defs[r.index()].fields[i].1;
            let fp = self
                .b
                .emit(
                    Op::PtrField,
                    &[ptr],
                    Imm::Field(r, i as u32),
                    Some(MTy::PTR),
                )
                .expect("field address");
            let mut path = prefix.to_vec();
            path.push(i as u32);
            let mut here = names.to_vec();
            here.push(f.name);
            let below: Vec<Vec<_>> = tails
                .iter()
                .filter(|t| t.starts_with(&here))
                .cloned()
                .collect();
            let moved = below.iter().any(|t| t.len() == here.len());
            if !below.is_empty() && !moved {
                self.split_fields(&f.ty, fp, &path, &here, tails, items)?;
                continue;
            }
            let Some(kind) = self.part_closer(&f.ty)? else {
                return Err(Error::new("a moved resource without a close operation"));
            };
            items.push(SplitItem {
                path,
                ptr: fp,
                thunk: self.field_thunk(&kind, fty),
                moved: moved.then_some(here),
            });
        }
        Ok(())
    }

    /// A close of the value of type `ty` held in memory that ignores a failed close, and that no
    /// scope's fallible close turns into a returning one.
    fn field_thunk(&mut self, kind: &CloseKind, ty: MTy) -> FuncId {
        let key = HelperKey::CloseField(ty, kind.clone());
        if let Some(f) = self.cx.helpers.get(&key) {
            return *f;
        }
        let ps = vec![Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        }];
        let mut b = FuncBuilder::new(self.b.m, "close", ps, MTy::UNIT);
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().kind = FuncKind::Normal;
        b.func_mut().slot_close = b.m.needs_drop(ty).then_some(ty);
        let v = b.params()[0];
        close_at_silent(&mut b, kind, v, ty);
        let u = b.unit();
        b.ret(Some(u));
        let f = b.into_func();
        let id = self.b.m.add_func(f);
        self.cx.helpers.insert(key, id);
        id
    }

    /// The function that drops what the type of type `ty` held in memory holds besides the
    /// resource fields at `owned`, which owners of their own close and drop.
    fn split_rest_thunk(&mut self, ty: MTy, owned: &[Vec<u32>]) -> FuncId {
        let key = HelperKey::SplitRest(ty, owned.to_vec());
        if let Some(f) = self.cx.helpers.get(&key) {
            return *f;
        }
        let ps = vec![Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        }];
        let mut b = FuncBuilder::new(self.b.m, "close", ps, MTy::UNIT);
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().kind = FuncKind::Normal;
        let p = b.params()[0];
        drop_rest(&mut b, p, ty, &mut Vec::new(), owned);
        let u = b.unit();
        b.ret(Some(u));
        let f = b.into_func();
        let id = self.b.m.add_func(f);
        self.cx.helpers.insert(key, id);
        id
    }

    /// A move of the resource field `names` out of the binding `uid`: the new owner closes it,
    /// so the binding's owner for it goes away.
    pub(crate) fn moved_field(
        &mut self,
        uid: usize,
        names: &[ct::Name],
        field: Value,
    ) -> Result<Value, Error> {
        let ptr = *self
            .split_places
            .get(&(uid, names.to_vec()))
            .ok_or_else(|| Error::new("a moved field the binding does not track"))?;
        self.b.emit(Op::ScopeDisown, &[ptr], Imm::None, None);
        Ok(self.b.move_out(field))
    }

    /// How a binding of `ty` is closed: its own close operation (`cleanup`, or the type's
    /// `Closeable` implementation when the statement names none, as a pattern binding's does
    /// not), if it has one, and then the resources it holds; `None` when this module sees no
    /// close operation for the type (its `Closeable` implementation is local to another file).
    pub(crate) fn closer_opt(
        &mut self,
        cleanup: Option<&ct::MethodRef>,
        ty: &ct::Ty,
    ) -> Result<Option<CloseKind>, Error> {
        let ty = ct::sub(ty, &self.subst);
        let mt = self.mty(&ty)?;
        if let TyKind::Iface(iface) = self.b.m.types.kind(mt).clone() {
            return self
                .iface_closer(iface)
                .map(Some)
                .ok_or_else(|| Error::new("interface without close"));
        }
        let own = match cleanup.cloned().or_else(|| self.closeable_method(&ty)) {
            Some(c) => Some(self.own_closer(&c, &ty)?),
            None => None,
        };
        self.close_with_parts(&ty, own)
    }

    /// The `close` entry of an interface value's vtable, if the interface declares one.
    fn iface_closer(&self, iface: IfaceId) -> Option<CloseKind> {
        let k = self.b.m.ifaces[iface.index()].close?;
        Some(CloseKind::Iface(iface, k))
    }

    /// The close operation `cleanup` names for the concrete receiver `ty`.
    fn own_closer(&mut self, cleanup: &ct::MethodRef, ty: &ct::Ty) -> Result<CloseKind, Error> {
        let im = if cleanup.native == ct::Native::Contract {
            self.contract_impl(cleanup, ty).ok_or_else(|| {
                Error::new(format!(
                    "{ty_t} has no close operation",
                    ty_t = ty.display(self.syms)
                ))
            })?
        } else {
            cleanup.clone()
        };
        if im.native != ct::Native::Source {
            return Err(Error::new(format!(
                "unsupported native close {}",
                im.native.text(self.syms)
            )));
        }
        let decl = im
            .decl
            .as_ref()
            .ok_or_else(|| Error::new("close without declaration"))?;
        let c = self.callable_of_decl(im.module, Some(decl.id()))?;
        // The checked reference fixes an implementation's variables; its declaration keeps them.
        let declared = self
            .cx
            .methods
            .iter()
            .find(|d| d.module == im.module && d.decl.as_ref().map(|x| x.id()) == Some(decl.id()))
            .unwrap_or(&im);
        let mut subst = ct::Subst::default();
        if !ct::unify(
            &declared.receiver,
            ty,
            &ct::variable_set(&declared.variables),
            &mut subst,
        ) {
            return Err(Error::new("cannot bind close receiver type"));
        }
        let fid = self.instance(&c, &subst)?;
        let writes_back = self.cx.var_positions(&c).contains(&0);
        Ok(CloseKind::Func { fid, writes_back })
    }

    /// The `close` method of a concrete type that meets `Closeable`, if it has one.
    fn closeable_method(&self, ty: &ct::Ty) -> Option<ct::MethodRef> {
        self.cx
            .methods
            .iter()
            .find(|m| {
                m.name().is_some_and(|n| self.syms.str(n) == "close")
                    && m.closes(self.syms)
                    && ct::unify(
                        &m.receiver,
                        ty,
                        &ct::variable_set(&m.variables),
                        &mut ct::Subst::default(),
                    )
            })
            .cloned()
    }

    /// The close of a resource held inside another: its own `close`, then what it holds in turn.
    /// `None` for a value that is not a resource.
    pub(crate) fn part_closer(&mut self, ty: &ct::Ty) -> Result<Option<CloseKind>, Error> {
        if self.cx.classes.class(self.syms, ty) != ms_check::api::ownership::Class::Resource {
            return Ok(None);
        }
        let mt = self.mty(ty)?;
        if let TyKind::Iface(iface) = self.b.m.types.kind(mt).clone() {
            return Ok(self.iface_closer(iface));
        }
        let own = match self.closeable_method(ty) {
            Some(m) => Some(self.own_closer(&m, ty)?),
            None => None,
        };
        match self.close_with_parts(ty, own)? {
            Some(k) => Ok(Some(k)),
            None => Err(Error::new(format!(
                "{ty_t} holds a resource with no close operation",
                ty_t = ty.display(self.syms)
            ))),
        }
    }

    /// `own`, followed by the close of every resource `ty` holds, last declared first: the
    /// close of a type, alternative, `Optional`, `List` or `Map` is generated from its parts.
    fn close_with_parts(
        &mut self,
        ty: &ct::Ty,
        own: Option<CloseKind>,
    ) -> Result<Option<CloseKind>, Error> {
        let mt = self.mty(ty)?;
        let shape = match self.b.m.types.kind(mt).clone() {
            TyKind::Type(r) => {
                let held = ct::fields(ty);
                let mut parts = Vec::new();
                for (i, f) in held.iter().enumerate().rev() {
                    let ft = self.b.m.type_defs[r.index()].fields[i].1;
                    if let Some(k) = self.part_closer(&f.ty)? {
                        parts.push((i as u32, ft, k));
                    }
                }
                (!parts.is_empty()).then_some(Shape::Type(r, parts))
            }
            TyKind::Alt(a) => {
                let s = ct::substitution(ty);
                let mut cases = Vec::new();
                if let Some(def) = &ty.def {
                    let defs: Vec<_> = def.cases.borrow().iter().cloned().collect();
                    for (c, case) in defs.iter().enumerate() {
                        let mut parts = Vec::new();
                        for (j, f) in case.fields.iter().enumerate().rev() {
                            let ft = self.b.m.alts[a.index()].cases[c].fields[j].1;
                            if let Some(k) = self.part_closer(&ct::sub(&f.ty, &s))? {
                                parts.push((j as u32, ft, k));
                            }
                        }
                        if !parts.is_empty() {
                            cases.push((c as u32, parts));
                        }
                    }
                }
                (!cases.is_empty()).then_some(Shape::Alt(a, cases))
            }
            TyKind::Opt(inner) => match ty.args.first() {
                Some(arg) => self.part_closer(arg)?.map(|k| Shape::Opt(inner, k)),
                None => None,
            },
            TyKind::List(elem) => match ty.args.first() {
                Some(arg) => self.part_closer(arg)?.map(|k| Shape::List(elem, k)),
                None => None,
            },
            TyKind::Obj(Native::Map, a) => {
                let holds = ty.args.get(1).map(|v| self.part_closer(v)).transpose()?;
                match holds.flatten() {
                    Some(k) => {
                        let (kt, vt) = (a[0], a[1]);
                        let ks = self.glue_scope(kt);
                        self.cx.ensure_glue(self.b.m, kt, ks);
                        let vs = self.glue_scope(vt);
                        self.cx.ensure_glue(self.b.m, vt, vs);
                        Some(Shape::Map(mt, kt, vt, ks, vs, k))
                    }
                    None => None,
                }
            }
            _ => None,
        };
        let Some(shape) = shape else {
            return Ok(own);
        };
        // The helper closes the holder in place, through its address: a part whose close
        // changes it is written back where it lives, with no copy of the holder.
        let key = HelperKey::CloseParts(self.cx.tys.intern(ty), own.is_some());
        if let Some(f) = self.cx.helpers.get(&key) {
            return Ok(Some(CloseKind::Func {
                fid: *f,
                writes_back: true,
            }));
        }
        let ps = vec![Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        }];
        let mut b = FuncBuilder::new(self.b.m, "close_parts", ps, MTy::UNIT);
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().kind = FuncKind::Normal;
        let p = b.params()[0];
        if let Some(o) = &own {
            close_at(&mut b, o, p, mt);
        }
        emit_parts(&mut b, p, shape);
        let u = b.unit();
        b.ret(Some(u));
        let f = b.into_func();
        let fid = self.b.m.add_func(f);
        self.cx.helpers.insert(key, fid);
        Ok(Some(CloseKind::Func {
            fid,
            writes_back: true,
        }))
    }

    /// The function the cleanup stack calls with the registered value.
    /// The type a loop over an owned list of type `list` keeps in memory: the list and the
    /// index of the first element the loop has not taken.
    pub(crate) fn list_cursor(&mut self, list: MTy) -> (TypeId, MTy) {
        if let Some(c) = self.cx.list_cursors.get(&list) {
            return *c;
        }
        let c = self.b.m.add_type(
            "ListCursor",
            vec![("list".into(), list), ("next".into(), MTy::INT)],
        );
        self.cx.list_cursors.insert(list, c);
        c
    }

    /// The list a cursor holds, as a borrow.
    pub(crate) fn cursor_list(&mut self, slot: Value, tval: TypeId, list: MTy) -> Value {
        let at = self
            .b
            .emit(Op::PtrField, &[slot], Imm::Field(tval, 0), Some(MTy::PTR))
            .expect("field");
        self.b
            .emit(Op::Load, &[at], Imm::Ty(list), Some(list))
            .expect("list")
    }

    /// The close of a loop's cursor (`list_cursor`): closes the elements the loop never reached
    /// with `closer`, shielded and errors dropped, then releases them with the list.
    pub(crate) fn list_tail_thunk(&mut self, list: MTy, closer: Option<&CloseKind>) -> FuncId {
        let key = HelperKey::ListTail(list, closer.cloned());
        if let Some(f) = self.cx.helpers.get(&key) {
            return *f;
        }
        let (tval, _) = self.list_cursor(list);
        let elem = self.b.m.list_elem(list).expect("a list");
        let ps = vec![Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        }];
        let mut b = FuncBuilder::new(self.b.m, "close", ps, MTy::UNIT);
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().kind = FuncKind::Normal;
        let p = b.params()[0];
        let lp = b
            .emit(Op::PtrField, &[p], Imm::Field(tval, 0), Some(MTy::PTR))
            .expect("field");
        let np = b
            .emit(Op::PtrField, &[p], Imm::Field(tval, 1), Some(MTy::PTR))
            .expect("field");
        let next = b
            .emit(Op::Load, &[np], Imm::Ty(MTy::INT), Some(MTy::INT))
            .expect("next");
        if let Some(kind) = closer {
            let cur = b.declare_var(MTy::INT, Mode::Borrow);
            b.def_var(cur, next);
            let (header, body, done) = (b.new_block(), b.new_block(), b.new_block());
            b.br(header, &[]);
            b.switch_to(header);
            let j = b.use_var(cur);
            let l = b
                .emit(Op::Load, &[lp], Imm::Ty(list), Some(list))
                .expect("list");
            let len = b.list_len(l);
            let more = b.icmp(Cc::Lt, j, len);
            b.br_if(more, body, &[], done, &[]);
            b.seal_block(body);
            b.switch_to(body);
            let j = b.use_var(cur);
            let l = b
                .emit(Op::Load, &[lp], Imm::Ty(list), Some(list))
                .expect("list");
            let ep = b
                .emit(Op::ListAddrU, &[l, j], Imm::None, Some(MTy::PTR))
                .expect("element address");
            close_at_silent(&mut b, kind, ep, elem);
            let one = b.iconst(1);
            let bumped = b
                .emit(Op::IAdd, &[j, one], Imm::None, Some(MTy::INT))
                .expect("add");
            b.def_var(cur, bumped);
            b.br(header, &[]);
            b.seal_block(header);
            b.seal_block(done);
            b.switch_to(done);
        }
        let l = b
            .emit(Op::Take, &[lp], Imm::Ty(list), Some(list))
            .expect("list");
        b.list_release(l, next);
        let u = b.unit();
        b.ret(Some(u));
        let f = b.into_func();
        let id = self.b.m.add_func(f);
        self.cx.helpers.insert(key, id);
        id
    }

    pub(crate) fn close_thunk(&mut self, kind: &CloseKind, ty: MTy, in_slot: bool) -> FuncId {
        self.close_thunk_as(kind, ty, in_slot, false)
    }

    /// `close_thunk`; `private` makes a function of its own, one no scope's fallible close turns
    /// into a returning one: a pending temporary whose close fails faults, as `drop_temp` does.
    pub(crate) fn close_thunk_as(
        &mut self,
        kind: &CloseKind,
        ty: MTy,
        in_slot: bool,
        private: bool,
    ) -> FuncId {
        let key = if private {
            HelperKey::CloseSilent(ty, kind.clone())
        } else {
            match kind {
                CloseKind::Iface(i, k) => HelperKey::CloseIface {
                    iface: i.0,
                    k: *k,
                    in_slot,
                },
                CloseKind::Func { fid, writes_back } => HelperKey::CloseFunc {
                    fid: *fid,
                    writes_back: *writes_back,
                    in_slot,
                },
            }
        };
        if let Some(f) = self.cx.helpers.get(&key) {
            return *f;
        }
        // A value that lives in memory registers its address and is closed there; a value that
        // does not is registered as it is, which only a close that leaves it unchanged can take.
        assert!(
            in_slot || !kind.writes_back(),
            "a close that changes the value closes it in memory"
        );
        let ps = vec![Param {
            ty: if in_slot { MTy::PTR } else { ty },
            mode: Mode::Borrow,
        }];
        let mut b = FuncBuilder::new(self.b.m, "close", ps, MTy::UNIT);
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().kind = FuncKind::Normal;
        let v = b.params()[0];
        if in_slot {
            b.func_mut().slot_close = b.m.needs_drop(ty).then_some(ty);
            if private {
                let r = close_at_result(&mut b, kind, v, ty);
                close_error_fault(&mut b, r, Some((v, ty)));
            } else {
                close_at_silent(&mut b, kind, v, ty);
            }
        } else {
            let (_, r) = close_owned_result(&mut b, kind, v, ty);
            if b.m.needs_drop(b.ty(r)) {
                b.emit(Op::Drop, &[r], Imm::None, None);
            }
        }
        let u = b.unit();
        b.ret(Some(u));
        let f = b.into_func();
        let id = self.b.m.add_func(f);
        self.cx.helpers.insert(key, id);
        id
    }

    /// The function that closes a value of the closing binding `uid` held by a closure built at
    /// `e`, when `e` moves the binding into its environment.
    pub(crate) fn capture_closer(&mut self, uid: usize, e: &Expr, ty: MTy) -> Option<FuncId> {
        if let Some(raw) = self.raw_slots.get(&uid).cloned() {
            let moves = self.cx.ownership.close_moves.get(&uid)?;
            if self.dead || !moves.contains(&e.id) {
                return None;
            }
            return Some(self.close_thunk(&raw.kind, ty, true));
        }
        None
    }

    /// A move of the closing binding `uid` at the name expression `e`: the new owner closes the
    /// value, so neither the cleanup entry nor the scope end does.
    pub(crate) fn moved_closer(&mut self, uid: usize, e: &Expr) {
        if let Some(RawSlot { slot, .. }) = self.raw_slots.get(&uid).cloned() {
            let moved = self
                .cx
                .ownership
                .close_moves
                .get(&uid)
                .is_some_and(|n| n.contains(&e.id));
            if moved && !self.dead {
                self.disown_raw(uid, slot);
            }
            return;
        }
        if let Some(owners) = self.split_owners.get(&uid).cloned() {
            let moved = self
                .cx
                .ownership
                .close_moves
                .get(&uid)
                .is_some_and(|n| n.contains(&e.id));
            if moved && !self.dead {
                for owner in owners {
                    self.b.emit(Op::ScopeDisown, &[owner], Imm::None, None);
                }
            }
        }
    }

    /// Types that the program called `close()` on the closing binding `recv` named.
    pub(crate) fn note_explicit_close(&mut self, recv: &Expr) {
        let ms_check::api::hir::Resolution::Local(b) = self.hir.resolution(recv) else {
            return;
        };
        if self.dead {
            return;
        }
        if let Some(raw) = self.raw_slots.get(&b.uid).cloned() {
            self.mark_raw_closed(&raw, true);
        }
    }

    /// Closes the owned `v`, a value of the place `place` that the program is about to overwrite
    /// or discard, when it holds a resource: shielded like any other close. What the close
    /// leaves is returned for the caller to drop; a value with nothing to close adds no code.
    pub(crate) fn close_discarded(&mut self, place: &Expr, v: Value) -> Result<Value, Error> {
        let ty = ct::sub(&self.hir.ty(place), &self.subst);
        self.close_discarded_ty(&ty, v)
    }

    /// [`Self::close_discarded`] for a value of checked type `ty`.
    pub(crate) fn close_discarded_ty(&mut self, ty: &ct::Ty, v: Value) -> Result<Value, Error> {
        let Some(kind) = self.part_closer(ty)? else {
            return Ok(v);
        };
        Ok(self.close_discarded_kind(&kind, v))
    }

    /// Closes the owned `v` with `kind`, shielded like any other close; the value after it.
    pub(crate) fn close_discarded_kind(&mut self, kind: &CloseKind, v: Value) -> Value {
        let mt = self.ty_of(v);
        let _ = self.call_runtime("msrt_shield_enter", &[], MTy::UNIT);
        let v = close_owned(&mut self.b, kind, v, mt);
        let _ = self.call_runtime("msrt_shield_exit", &[], MTy::UNIT);
        v
    }

    /// Starts deferring close failures: a mutator that discards entries closes them in place,
    /// and the entry is gone once the mutation ran, so the fault comes after it.
    pub(crate) fn defer_close_failures(&mut self) {
        let failed = self.b.declare_var(MTy::BOOL, Mode::Borrow);
        let no = self.b.bconst(false);
        self.b.def_var(failed, no);
        self.deferred_close = Some(failed);
    }

    /// Faults when a close deferred by `defer_close_failures` failed.
    pub(crate) fn fault_deferred_close(&mut self) {
        let Some(failed) = self.deferred_close.take() else {
            return;
        };
        if self.dead {
            return;
        }
        let bad = self.b.use_var(failed);
        let (fail, good) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(bad, fail, &[], good, &[]);
        self.b.seal_block(fail);
        self.b.seal_block(good);
        self.b.switch_to(fail);
        let msg = self
            .b
            .str_lit("a resource could not be closed: its close returned an error");
        let ext = crate::text::runtime_fn(self.b.m, "msrt_fault_string", &[MTy::STR], MTy::UNIT);
        self.b.call_rt(ext, &[msg]);
        self.b.unreachable();
        self.b.switch_to(good);
    }

    /// Closes the value of checked type `ty` stored at `ptr`, in place, when it holds a
    /// resource: shielded like any other close.
    pub(crate) fn close_discarded_at(&mut self, ty: &ct::Ty, ptr: Value) -> Result<(), Error> {
        let Some(kind) = self.part_closer(ty)? else {
            return Ok(());
        };
        let mt = self.mty(ty)?;
        self.close_at_shielded(&kind, ptr, mt);
        Ok(())
    }

    /// Closes the value of type `ty` at `ptr` with `kind`, shielded like any other close.
    pub(crate) fn close_at_shielded(&mut self, kind: &CloseKind, ptr: Value, ty: MTy) {
        let _ = self.call_runtime("msrt_shield_enter", &[], MTy::UNIT);
        if let Some(failed) = self.deferred_close {
            close_at_deferred(&mut self.b, kind, ptr, ty, failed);
        } else {
            close_at(&mut self.b, kind, ptr, ty);
        }
        let _ = self.call_runtime("msrt_shield_exit", &[], MTy::UNIT);
    }
}
