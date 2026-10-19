//! `Map` and `Set`: construction, literals, in-place mutators and the entry list.
//!
//! The runtime changes a map through a pointer, so a mutator moves the owned map into a
//! stack slot, calls the runtime on the slot's address and takes the map back.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::native::NArg;
use ms_check::types as ct;
use ms_mir::builder::Var;
use ms_mir::ir::{Cc, Imm, Mode, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::MapEntry;

/// Whether `t` is a `Map` or `Set`.
pub(crate) fn is_map_or_set(m: &ms_mir::ir::Module, t: MTy) -> bool {
    matches!(m.types.kind(t), TyKind::Obj(n, _) if n == "Map" || n == "Set")
}

impl FnLower<'_> {
    /// A fresh empty map or set of type `ty`.
    pub(crate) fn map_new(&mut self, ty: MTy) -> Result<Value, Error> {
        self.call_runtime("msrt_map_new", &[], ty)
    }

    /// `Set(values)`: the set of a list's elements.
    pub(crate) fn set_from_list(&mut self, list: Val, ty: MTy) -> Result<Val, Error> {
        let TyKind::Obj(_, a) = self.b.m.types.kind(ty).clone() else {
            return Err(Error::new("not a set"));
        };
        let d = self.type_desc(a[0]);
        let l = self.borrow(list);
        let out = self.call_runtime("msrt_list_to_set", &[l, d], ty)?;
        Ok(Val { v: out, own: true })
    }

    /// `List[T]()`, `Map[K, V]()`, `Set[T]()` and `Set(values)`.
    pub(crate) fn construct_collection(
        &mut self,
        view: &ms_check::hir::CallView<'_>,
        ty: MTy,
    ) -> Result<Val, Error> {
        let arg = match view.arguments.as_slice() {
            [] => None,
            [a] => Some(self.expr(a.expr)?),
            _ => return Err(Error::new("unsupported collection constructor")),
        };
        if self.dead {
            return Ok(self.dummy(ty));
        }
        match (self.b.m.types.kind(ty).clone(), arg) {
            (TyKind::List(elem), None) => {
                let v = self.b.list_lit(elem, &[]);
                Ok(Val { v, own: true })
            }
            (TyKind::List(_), Some(x)) => Ok(x),
            (_, None) => Ok(Val {
                v: self.map_new(ty)?,
                own: true,
            }),
            (_, Some(list)) => self.set_from_list(list, ty),
        }
    }

    /// `{key: value, ...}`.
    pub(crate) fn map_literal(&mut self, ty: MTy, entries: &[MapEntry]) -> Result<Val, Error> {
        let mut acc = self.map_new(ty)?;
        for en in entries {
            let k = self.expr(&en.key)?;
            if self.dead {
                self.drop_value(acc);
                return Ok(self.dummy(ty));
            }
            let k = self.owned(k);
            let v = self.expr(&en.value)?;
            if self.dead {
                self.drop_value(k);
                self.drop_value(acc);
                return Ok(self.dummy(ty));
            }
            let v = self.owned(v);
            acc = self.map_insert(acc, k, v)?;
        }
        Ok(Val { v: acc, own: true })
    }

    /// The owned map `old` with `key` bound to `value`; both are consumed.
    fn map_insert(&mut self, old: Value, key: Value, value: Value) -> Result<Value, Error> {
        let mt = self.ty_of(old);
        let slot = self.put_slot(old);
        let (kd, vd) = self.map_descs(mt)?;
        let ks = self.put_slot(key);
        let vs = self.put_slot(value);
        let vd = vd.ok_or_else(|| Error::new("a set literal is not supported"))?;
        self.call_runtime("msrt_map_add", &[slot, kd, vd, ks, vs], MTy::UNIT)?;
        Ok(self.take_slot(slot, mt))
    }

    /// Key and value descriptors of a map type (no value descriptor for a set).
    fn map_descs(&mut self, mt: MTy) -> Result<(Value, Option<Value>), Error> {
        let TyKind::Obj(_, a) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("not a map or set"));
        };
        let kd = self.type_desc(a[0]);
        let vd = a.get(1).map(|v| self.type_desc(*v));
        Ok((kd, vd))
    }

    /// A stack slot holding the owned `x`.
    fn put_slot(&mut self, x: Value) -> Value {
        let t = self.ty_of(x);
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
            .expect("slot");
        let op = if self.needs_drop(t) {
            Op::Put
        } else {
            Op::Store
        };
        self.b.emit(op, &[slot, x], Imm::None, None);
        slot
    }

    fn take_slot(&mut self, slot: Value, t: MTy) -> Value {
        self.b
            .emit(Op::Take, &[slot], Imm::Ty(t), Some(t))
            .expect("take")
    }

    /// `(new map, result)` of a map or set mutator applied to the owned `old`. With
    /// `copy_result` the result is a copy of the new map (the methods return their receiver).
    pub(crate) fn mutate_map(
        &mut self,
        name: &str,
        old: Value,
        decl: &[ct::Param],
        args: &[NArg],
        copy_result: bool,
    ) -> Result<(Value, Option<Val>), Error> {
        let mt = self.ty_of(old);
        let set = matches!(self.b.m.types.kind(mt), TyKind::Obj(n, _) if n == "Set");
        let sym = match (set, name) {
            (true, "add") => "msrt_set_add_copy".to_string(),
            _ => crate::rtcall::method_symbol(self.b.m, mt, name)
                .ok_or_else(|| Error::new(format!("unsupported map mutator {name}")))?,
        };
        let slot = self.put_slot(old);
        let recv = Val { v: old, own: false };
        self.rt_method_at(&sym, recv, Some(slot), decl, args, MTy::UNIT)?;
        let new = self.take_slot(slot, mt);
        let result = copy_result.then(|| {
            let v = self.owned(Val { v: new, own: false });
            Val { v, own: true }
        });
        Ok((new, result))
    }

    /// `map.get_or(key, fallback)`.
    pub(crate) fn map_get_or(
        &mut self,
        recv: Val,
        decl: &[ct::Param],
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let opt_ty = self.b.m.types.opt(result);
        let found = self.rt_method("msrt_map_get", recv, decl, args, opt_ty)?;
        let fallback = args
            .iter()
            .find(|a| a.name.as_str() == "fallback")
            .ok_or_else(|| Error::new("get_or without a fallback"))?
            .val;
        let present = self.b.opt_is_some(found.v);
        let out = self.two_ways(
            present,
            result,
            &mut |s| {
                let x = s.b.opt_get(found.v);
                Ok(Some(s.owned(Val { v: x, own: false })))
            },
            &mut |s| Ok(Some(s.owned(fallback))),
        )?;
        if found.own {
            self.drop_value(found.v);
        }
        Ok(out)
    }

    /// `map.entries()`: a list of fresh `MapEntry` records.
    pub(crate) fn map_entries(
        &mut self,
        recv_expr: &ms_syntax::ast::Expr,
        recv: Val,
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::List(entry) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("entries without a list type"));
        };
        let TyKind::Rec(rid) = self.b.m.types.kind(entry).clone() else {
            return Err(Error::new("entries without a record type"));
        };
        let mt = self.ty_of(recv.v);
        let TyKind::Obj(_, a) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("not a map"));
        };
        let (kt, vt) = (a[0], a[1]);
        let (mv, hidden) = self.list_source(recv_expr, recv)?;
        let acc: Var = self.fresh_var(result);
        let empty = self.b.list_lit(entry, &[]);
        self.b.def_var(acc, empty);
        let m0 = self.b.use_var(mv);
        let count = self.call_runtime("msrt_map_slot_count", &[m0], MTy::INT)?;
        let idx = self.b.declare_var(MTy::INT, Mode::Borrow);
        let zero = self.b.iconst(0);
        self.b.def_var(idx, zero);
        let (header, step, exit) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(header, &[]);
        self.b.switch_to(header);
        let i = self.b.use_var(idx);
        let more = self.b.icmp(Cc::Lt, i, count);
        self.b.br_if(more, step, &[], exit, &[]);
        self.b.seal_block(step);
        self.b.switch_to(step);
        let i = self.b.use_var(idx);
        let m = self.b.use_var(mv);
        let (kd, vd) = self.map_descs(mt)?;
        let kp = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(MTy::PTR), Some(MTy::PTR))
            .expect("slot");
        let vp = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(MTy::PTR), Some(MTy::PTR))
            .expect("slot");
        let vd = vd.ok_or_else(|| Error::new("entries of a set"))?;
        let live = self.call_runtime("msrt_map_entry_ptrs", &[m, kd, vd, i, kp, vp], MTy::BOOL)?;
        let (take, skip) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(live, take, &[], skip, &[]);
        self.b.seal_block(take);
        self.b.seal_block(skip);
        self.b.switch_to(take);
        let kaddr = self
            .b
            .emit(Op::Load, &[kp], Imm::Ty(MTy::PTR), Some(MTy::PTR))
            .expect("load");
        let vaddr = self
            .b
            .emit(Op::Load, &[vp], Imm::Ty(MTy::PTR), Some(MTy::PTR))
            .expect("load");
        let key = self
            .b
            .emit(Op::Load, &[kaddr], Imm::Ty(kt), Some(kt))
            .expect("load");
        let val = self
            .b
            .emit(Op::Load, &[vaddr], Imm::Ty(vt), Some(vt))
            .expect("load");
        let ko = self.owned(Val { v: key, own: false });
        let vo = self.owned(Val { v: val, own: false });
        let rec = self.b.rec_new(rid, &[ko, vo]);
        let cur = self.b.use_var(acc);
        let next = self.b.list_push(cur, rec);
        self.b.def_var(acc, next);
        self.b.br(skip, &[]);
        self.b.switch_to(skip);
        let one = self.b.iconst(1);
        let i = self.b.use_var(idx);
        let n = self.b.binop(Op::IAdd, i, one);
        self.b.def_var(idx, n);
        self.b.br(header, &[]);
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        self.release_source(mv, hidden);
        let out = self.b.use_var(acc);
        Ok(Val { v: out, own: true })
    }
}
