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

impl<'a> FnLower<'a> {
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
            (TyKind::Bytes, Some(values)) if self.ty_of(values.v) != MTy::BYTES => {
                let v = self.borrow(values);
                let out = self.call_runtime("msrt_bytes_from_values", &[v], ty)?;
                Ok(Val { v: out, own: true })
            }
            // A builder is an empty byte buffer.
            (TyKind::Bytes, None) => Ok(Val {
                v: self.call_runtime("msrt_list_new", &[], ty)?,
                own: true,
            }),
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
    pub(crate) fn map_insert(
        &mut self,
        old: Value,
        key: Value,
        value: Value,
    ) -> Result<Value, Error> {
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
    pub(crate) fn map_descs(&mut self, mt: MTy) -> Result<(Value, Option<Value>), Error> {
        let TyKind::Obj(_, a) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("not a map or set"));
        };
        let kd = self.type_desc(a[0]);
        let vd = a.get(1).map(|v| self.type_desc(*v));
        Ok((kd, vd))
    }

    /// A stack slot holding the owned `x`.
    pub(crate) fn put_slot(&mut self, x: Value) -> Value {
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

    pub(crate) fn take_slot(&mut self, slot: Value, t: MTy) -> Value {
        self.b
            .emit(Op::Take, &[slot], Imm::Ty(t), Some(t))
            .expect("take")
    }

    /// `(new collection, result)` of a mutator the runtime implements, applied to the owned `old`.
    /// With `copy_result` the result is a copy of the new value (the methods return their receiver).
    pub(crate) fn mutate_rt(
        &mut self,
        name: &str,
        old: Value,
        decl: &[ct::Param],
        args: &[NArg],
        copy_result: bool,
        result_ty: MTy,
    ) -> Result<(Value, Option<Val>), Error> {
        let mt = self.ty_of(old);
        if name == "freeze" {
            return self.freeze_builder(old, result_ty);
        }
        if name == "add_default_from" {
            return self.add_default_from(old, decl, args, copy_result);
        }
        let set = matches!(self.b.m.types.kind(mt), TyKind::Obj(n, _) if n == "Set");
        let text = decl.first().is_some_and(|p| p.ty.to_string() == "String");
        let sym = match (set, name) {
            (true, "add") => "msrt_set_add_copy".to_string(),
            (_, "append") if mt == MTy::BYTES && text => "msrt_strbuilder_append".to_string(),
            // `BytesBuilder.concat` mutates in place; `msrt_bytes_concat` is the pure `Bytes.concat`.
            (_, "concat") if mt == MTy::BYTES => "msrt_bytes_extend".to_string(),
            _ => crate::rtcall::method_symbol(self.b.m, mt, name)
                .ok_or_else(|| Error::new(format!("unsupported mutator {name}")))?,
        };
        // An argument that is the receiver itself is copied before the receiver moves out.
        let args: Vec<NArg> = args
            .iter()
            .map(|a| {
                if a.val.v != old {
                    return *a;
                }
                let v = self.owned(a.val);
                NArg {
                    val: Val { v, own: true },
                    ..*a
                }
            })
            .collect();
        let slot = self.put_slot(old);
        let recv = Val { v: old, own: false };
        self.rt_method_at(&sym, recv, Some(slot), decl, &args, MTy::UNIT)?;
        let new = self.take_slot(slot, mt);
        let result = copy_result.then(|| {
            let v = self.owned(Val { v: new, own: false });
            Val { v, own: true }
        });
        Ok((new, result))
    }

    /// `map.add_default_from(key, create)`: `create(key)` runs once, only when the key is absent.
    fn add_default_from(
        &mut self,
        old: Value,
        decl: &[ct::Param],
        args: &[NArg],
        copy_result: bool,
    ) -> Result<(Value, Option<Val>), Error> {
        let mt = self.ty_of(old);
        let key = args
            .iter()
            .find(|a| a.name.as_str() == "key")
            .copied()
            .ok_or_else(|| Error::new("add_default_from without a key"))?;
        let create = args
            .iter()
            .find(|a| a.name.as_str() == "create")
            .copied()
            .ok_or_else(|| Error::new("add_default_from without create"))?;
        let value_ty = decl
            .iter()
            .find(|p| p.name.as_str() == "create")
            .and_then(|p| p.ty.result.clone())
            .ok_or_else(|| Error::new("add_default_from create is not a function"))?;
        let key_decl = decl[..1].to_vec();
        let add_decl = vec![
            decl[0].clone(),
            ct::Param {
                name: ct::Name::from("value"),
                ty: value_ty,
            },
        ];
        let slot = self.put_slot(old);
        let recv = Val { v: old, own: false };
        let has = self.rt_method_at(
            "msrt_map_contains",
            recv,
            Some(slot),
            &key_decl,
            &[key],
            MTy::BOOL,
        )?;
        let present = self.borrow(has);
        let (absent, join) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(present, join, &[], absent, &[]);
        self.b.seal_block(absent);
        self.b.switch_to(absent);
        let k = self.borrow(key.val);
        let f = self.borrow(create.val);
        let made = self.b.call_ind(f, &[k]);
        let value = NArg {
            name: ct::Name::from("value"),
            val: Val { v: made, own: true },
            wrapped: false,
        };
        let recv = Val { v: old, own: false };
        self.rt_method_at(
            "msrt_map_add_default",
            recv,
            Some(slot),
            &add_decl,
            &[key, value],
            MTy::UNIT,
        )?;
        self.b.br(join, &[]);
        self.b.seal_block(join);
        self.enter(join);
        let new = self.take_slot(slot, mt);
        let result = copy_result.then(|| {
            let v = self.owned(Val { v: new, own: false });
            Val { v, own: true }
        });
        Ok((new, result))
    }

    /// `builder.freeze()`: the buffer becomes the result and the builder starts over empty.
    fn freeze_builder(
        &mut self,
        old: Value,
        result_ty: MTy,
    ) -> Result<(Value, Option<Val>), Error> {
        let bt = self.ty_of(old);
        let fresh = self.call_runtime("msrt_list_new", &[], bt)?;
        if result_ty == MTy::STR {
            let slot = self.put_slot(old);
            let text = self.call_runtime("msrt_strbuilder_freeze", &[slot], MTy::STR)?;
            return Ok((fresh, Some(Val { v: text, own: true })));
        }
        Ok((fresh, Some(Val { v: old, own: true })))
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
        let (mv, hidden) = self.list_source(Some(recv_expr), recv)?;
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

    /// `list.entries()`: `ListEntry` records pairing each index with its element.
    pub(crate) fn list_entries(
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
        let (lv, hidden) = self.list_source(Some(recv_expr), recv)?;
        let acc = self.fresh_var(result);
        let n = {
            let l = self.b.use_var(lv);
            self.b.list_len(l)
        };
        let first = self.b.list_new(entry, n);
        self.b.def_var(acc, first);
        self.each_element(lv, &mut |s, i, x| {
            let xo = s.owned(Val { v: x, own: false });
            let rec = s.b.rec_new(rid, &[i, xo]);
            let cur = s.b.use_var(acc);
            let next = s.b.list_push(cur, rec);
            s.b.def_var(acc, next);
            Ok(None)
        })?;
        self.release_source(lv, hidden);
        let out = self.b.use_var(acc);
        Ok(Val { v: out, own: true })
    }

    /// `map_from_entries(entries)`: later entries replace earlier values of equal keys.
    pub(crate) fn map_from_entries(&mut self, entries: Val, mt: MTy) -> Result<Val, Error> {
        let (lv, hidden) = self.list_source(None, entries)?;
        let acc = self.fresh_var(mt);
        let empty = self.map_new(mt)?;
        self.b.def_var(acc, empty);
        self.each_element(lv, &mut |s, _, x| {
            let rec_ty = s.ty_of(x);
            let TyKind::Rec(rid) = s.b.m.types.kind(rec_ty).clone() else {
                return Err(Error::new("map entry is not a record"));
            };
            let k = s.b.rec_get(rid, 0, x);
            let v = s.b.rec_get(rid, 1, x);
            let ko = s.owned(Val { v: k, own: false });
            let vo = s.owned(Val { v, own: false });
            let cur = s.b.use_var(acc);
            let next = s.map_insert(cur, ko, vo)?;
            s.b.def_var(acc, next);
            Ok(None)
        })?;
        self.release_source(lv, hidden);
        let out = self.b.use_var(acc);
        Ok(Val { v: out, own: true })
    }

    /// `set.entries()`: `[value, value]` lists in insertion order.
    pub(crate) fn set_entries(&mut self, recv: Val, result: MTy) -> Result<Val, Error> {
        let TyKind::List(pair) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("entries without a list type"));
        };
        let TyKind::List(inner) = self.b.m.types.kind(pair).clone() else {
            return Err(Error::new("entries pair is not a list"));
        };
        let acc = self.fresh_var(result);
        let empty = self.b.list_lit(pair, &[]);
        self.b.def_var(acc, empty);
        let m = self.borrow(recv);
        self.each_entry(m, &mut |s, key, _| {
            let ko = s.owned(Val { v: key, own: false });
            let kc = s.owned(Val { v: key, own: false });
            let p = s.b.list_lit(inner, &[ko, kc]);
            let cur = s.b.use_var(acc);
            let next = s.b.list_push(cur, p);
            s.b.def_var(acc, next);
            Ok(())
        })?;
        let out = self.b.use_var(acc);
        Ok(Val { v: out, own: true })
    }

    /// Runs `body(key, value)` for each live entry of the borrowed map or set `m` (`value` is
    /// `None` for a set). Both are borrowed views of the entry.
    pub(crate) fn each_entry(
        &mut self,
        m: Value,
        body: &mut EntryBody<'_, 'a>,
    ) -> Result<(), Error> {
        let mt = self.ty_of(m);
        let TyKind::Obj(_, a) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("not a map or set"));
        };
        let kt = a[0];
        let vt = a.get(1).copied();
        let count = self.call_runtime("msrt_map_slot_count", &[m], MTy::INT)?;
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
        let (kd, vd) = self.map_descs(mt)?;
        let vd = match vd {
            Some(v) => v,
            None => {
                let ot = self.b.m.types.opt(MTy::STR);
                self.b.opt_none(ot)
            }
        };
        let kp = self.ptr_slot();
        let vp = self.ptr_slot();
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
        let key = self
            .b
            .emit(Op::Load, &[kaddr], Imm::Ty(kt), Some(kt))
            .expect("load");
        let value = match vt {
            Some(vt) => {
                let vaddr = self
                    .b
                    .emit(Op::Load, &[vp], Imm::Ty(MTy::PTR), Some(MTy::PTR))
                    .expect("load");
                Some(
                    self.b
                        .emit(Op::Load, &[vaddr], Imm::Ty(vt), Some(vt))
                        .expect("load"),
                )
            }
            None => None,
        };
        body(self, key, value)?;
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
        Ok(())
    }

    fn ptr_slot(&mut self) -> Value {
        self.b
            .emit(Op::Slot, &[], Imm::Ty(MTy::PTR), Some(MTy::PTR))
            .expect("slot")
    }
}

/// Per-entry callback of `each_entry`: the key and, for maps, the value.
pub(crate) type EntryBody<'b, 'a> =
    dyn FnMut(&mut FnLower<'a>, Value, Option<Value>) -> Result<(), Error> + 'b;
