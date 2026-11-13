//! `Map` and `Set`: construction, literals, in-place mutators and the entry list.
//!
//! The runtime changes a map through a pointer, so a mutator moves the owned map into a
//! stack slot, calls the runtime on the slot's address and takes the map back.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::native::NArg;
use crate::rtcall::Input;
use ms_check::api::ast::{Expr, ExprKind, MapEntry, TextPart};
use ms_check::api::hir::{CallView, Resolution};
use ms_check::api::types as ct;
use ms_check::api::types::Builtin;
use ms_mir::builder::Var;
use ms_mir::ir::{Cc, Imm, Mode, Op, Value};
use ms_mir::types::Native;
use ms_mir::types::{Ty as MTy, TyKind};

/// Entries above which a map literal is built in chunks.
const LONG_MAP_LITERAL: usize = 256;
/// Entries per chunk of a long map literal.
const LONG_MAP_CHUNK: usize = 64;
/// Entries from which a literal of constants is a static table.
const CONST_MAP_TABLE: usize = 16;

/// Whether `t` is a `Map` or `Set`.
pub(crate) fn is_map_or_set(m: &ms_mir::ir::Module, t: MTy) -> bool {
    matches!(m.types.kind(t), TyKind::Obj(n, _) if n.is_map_or_set())
}

/// `x` of `x.clone()`.
fn clone_receiver<'e>(
    syms: ms_check::api::Names,
    hir: &ms_check::api::hir::ModuleHir,
    e: &'e Expr,
) -> Option<&'e Expr> {
    if hir.info(e).native_str(syms) != "clone" {
        return None;
    }
    let ExprKind::Call { callee, args } = &e.kind else {
        return None;
    };
    let ExprKind::Member { left, name } = &callee.kind else {
        return None;
    };
    (syms.str(name) == "clone" && args.is_empty()).then_some(&**left)
}

impl<'a> FnLower<'a> {
    /// `m.add(key: k.clone(), value: v)` and `m.add_default(..)` on a `String`-keyed map held in a
    /// local, with `k` a part of a variable that cannot change: the runtime copies the key only when
    /// the entry is absent, so updating an existing entry allocates nothing.
    pub(crate) fn borrowed_key_add(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        m: &ct::MethodRef,
        recv_expr: &Expr,
        name: &str,
    ) -> Result<Option<Val>, Error> {
        if !matches!(name, "add" | "add_default")
            || self.discard != Some(e as *const Expr as usize)
            || view.arguments.len() != 2
        {
            return Ok(None);
        }
        let declared: Vec<_> = m.ty.params.iter().map(|p| p.name).collect();
        if declared.len() != 2
            || view.arguments[0].slot.name != declared[0]
            || view.arguments[1].slot.name != declared[1]
        {
            return Ok(None);
        }
        let (key_e, value_e) = (view.arguments[0].expr, view.arguments[1].expr);
        let Some(inner) = clone_receiver(self.syms, &self.hir, key_e) else {
            return Ok(None);
        };
        if !self.is_place(recv_expr) || !self.is_place(inner) {
            return Ok(None);
        }
        let base = crate::mutation::place_base(self.syms, &self.hir, inner);
        let Resolution::Local(binding) = self.hir.resolution(base) else {
            return Ok(None);
        };
        // The key is borrowed until the add, so the value must not consume its owner.
        if binding.mutable || crate::mutation::uses_of(&self.hir, value_e, binding.uid) != 0 {
            return Ok(None);
        }
        let mt = self.emty(recv_expr)?;
        let TyKind::Obj(n, a) = self.b.m.types.kind(mt).clone() else {
            return Ok(None);
        };
        if n != Native::Map || a.first() != Some(&MTy::STR) {
            return Ok(None);
        }
        let k = self.expr(inner)?;
        if self.dead {
            return Ok(Some(k));
        }
        let k = self.borrow(k);
        let v = self.expr(value_e)?;
        if self.dead {
            return Ok(Some(v));
        }
        let v = self.owned(v);
        let (kd, vd) = self.map_descs(mt)?;
        let vd = vd.ok_or_else(|| Error::new("a set has no values"))?;
        let sym = if name == "add" {
            "msrt_map_add_lent"
        } else {
            "msrt_map_add_default_lent"
        };
        self.place_update(recv_expr, &mut |s, old| {
            let slot = s.put_slot(old);
            let ks = s.borrow_slot(k);
            let vs = s.put_slot(v);
            s.call_runtime(sym, &[slot, kd, vd, ks, vs], MTy::UNIT)?;
            Ok(s.take_slot(slot, mt))
        })?;
        let u = self.b.unit();
        Ok(Some(Val { v: u, own: false }))
    }

    /// `m.update(key: k.clone(), initial, change)` on a `String`-keyed map held in a local, with
    /// `k` a part of a variable that cannot change: `update` only borrows its key (the runtime
    /// copies it when the entry is new), so the argument is read in place as `(index, k)`.
    pub(crate) fn borrowed_update_key<'e>(
        &mut self,
        view: &CallView<'e>,
        m: &ct::MethodRef,
        recv_expr: &Expr,
        name: &str,
    ) -> Result<Option<(usize, &'e Expr)>, Error> {
        if name != "update" || view.arguments.len() != 3 || m.ty.params.len() != 3 {
            return Ok(None);
        }
        // The key is the first declared parameter, found by its declared slot, so renaming it in
        // the standard declaration or writing the arguments in another order changes nothing.
        let key_slot = m.ty.params[0].name;
        let Some(at) = view.arguments.iter().position(|a| a.slot.name == key_slot) else {
            return Ok(None);
        };
        let key = &view.arguments[at];
        if key.wrap_optional.is_some() {
            return Ok(None);
        }
        let Some(inner) = clone_receiver(self.syms, &self.hir, key.expr) else {
            return Ok(None);
        };
        if !self.is_place(recv_expr) || !self.is_place(inner) {
            return Ok(None);
        }
        let base = crate::mutation::place_base(self.syms, &self.hir, inner);
        let Resolution::Local(binding) = self.hir.resolution(base) else {
            return Ok(None);
        };
        // The key is borrowed until the update, so no other argument may consume its owner.
        let others_use =
            view.arguments.iter().enumerate().any(|(i, a)| {
                i != at && crate::mutation::uses_of(&self.hir, a.expr, binding.uid) != 0
            });
        if binding.mutable || others_use {
            return Ok(None);
        }
        let mt = self.emty(recv_expr)?;
        let TyKind::Obj(n, a) = self.b.m.types.kind(mt).clone() else {
            return Ok(None);
        };
        if n != Native::Map || a.first() != Some(&MTy::STR) {
            return Ok(None);
        }
        Ok(Some((at, inner)))
    }

    /// `m.get(key).get()`, `.get(default)`, `.is_some()` and `.is_none()` read the entry in place:
    /// `get` borrows its result, so the value is copied only when something keeps it (and `get`
    /// with a default copies on a hit). `None` leaves any other shape to the ordinary path.
    pub(crate) fn map_get_chain(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        recv_expr: &Expr,
        name: &str,
    ) -> Result<Option<Val>, Error> {
        if !matches!(name, "get" | "is_some" | "is_none")
            || !self.ety(recv_expr).is(Builtin::Optional)
        {
            return Ok(None);
        }
        let ExprKind::Call { callee, args } = &recv_expr.kind else {
            return Ok(None);
        };
        let ExprKind::Member { left: map, name: n } = &callee.kind else {
            return Ok(None);
        };
        let [key] = args.as_slice() else {
            return Ok(None);
        };
        if self.syms.str(n) != "get" || key.name.is_some() || !self.ety(map).is(Builtin::Map) {
            return Ok(None);
        }
        // A key the checker converts on the way in (an `Optional` key given a plain value) takes
        // the ordinary call, which applies the conversion.
        let map_ty = self.emty(map)?;
        let TyKind::Obj(_, parts) = self.b.m.types.kind(map_ty).clone() else {
            return Ok(None);
        };
        let key_ty = self.emty(&key.value)?;
        if parts.first() != Some(&key_ty) {
            return Ok(None);
        }
        // A default that changes the map would run between the borrow and the lookup, so that
        // call takes the ordinary path, which looks up first (#2842).
        if let Some(uid) = crate::mutation::place_root(self.syms, &self.hir, map)
            && view.arguments.iter().any(|a| {
                crate::mutation::mutated_locals(
                    self.syms,
                    &self.hir,
                    ms_check::api::hir::Body::Expr(a.expr),
                    &self.cx.callables,
                    &self.cx.mutated,
                )
                .contains(&uid)
            })
        {
            return Ok(None);
        }
        if let Some(entries) = self.const_literal(map, map_ty) {
            return self.const_get_chain(view, entries, map_ty, &key.value, name);
        }
        let mv = self.expr(map)?;
        if self.dead {
            return Ok(Some(mv));
        }
        let mv = self.borrow(mv);
        let kv = self.expr(&key.value)?;
        if self.dead {
            return Ok(Some(kv));
        }
        let kv = self.borrow(kv);
        let default = if view.arguments.is_empty() {
            None
        } else {
            self.native_args(view)?.first().copied()
        };
        if self.dead {
            return Ok(Some(Val { v: mv, own: false }));
        }
        let mt = self.ty_of(mv);
        let value_ty = self.map_value_type(mv)?;
        let (kd, vd) = self.map_descs(mt)?;
        let vd = vd.ok_or_else(|| Error::new("a set has no values"))?;
        let ks = self.borrow_slot(kv);
        self.at(e.pos);
        let probe = self
            .word_map_symbol("msrt_map_get_ptr", mt)
            .unwrap_or("msrt_map_get_ptr");
        let p = self.call_runtime(probe, &[mv, kd, vd, ks], MTy::PTR)?;
        let missing = self
            .b
            .emit(Op::PtrIsNull, &[p], Imm::None, Some(MTy::BOOL))
            .expect("is_null");
        self.get_chain_tail(name, default, missing, value_ty, &mut |s| {
            s.b.emit(Op::Load, &[p], Imm::Ty(value_ty), Some(value_ty))
                .expect("load")
        })
    }

    /// The result of `m.get(key)` followed by `.get()`, `.get(default)`, `.is_some()` or
    /// `.is_none()`, once the probe says whether the key is `missing` and `load` reads the entry.
    pub(crate) fn get_chain_tail(
        &mut self,
        name: &str,
        default: Option<NArg>,
        missing: Value,
        value_ty: MTy,
        load: &mut dyn FnMut(&mut Self) -> Value,
    ) -> Result<Option<Val>, Error> {
        match name {
            "is_some" | "is_none" => {
                let v = if name == "is_none" {
                    missing
                } else {
                    self.b.unop(Op::Not, missing)
                };
                Ok(Some(Val { v, own: false }))
            }
            _ => match default {
                None => {
                    let (bad, good) = (self.b.new_block(), self.b.new_block());
                    self.b.br_if(missing, bad, &[], good, &[]);
                    self.b.seal_block(bad);
                    self.b.seal_block(good);
                    self.b.switch_to(bad);
                    self.b.fault(ms_mir::ir::FaultKind::NoneUnwrap);
                    self.b.switch_to(good);
                    let v = load(self);
                    // A `let` of this value is a lexical borrow of the map: the ownership
                    // checker rejects changing the map while it lives.
                    self.stable_reads.insert(v);
                    // `Optional.get()` borrows its payload; a `let` that keeps it copies it.
                    self.boundary_reads.insert(v);
                    Ok(Some(Val { v, own: false }))
                }
                Some(d) => {
                    let out = self.two_ways(
                        missing,
                        value_ty,
                        &mut |s| {
                            let v = if d.wrapped {
                                s.owned_boundary(d.val)
                            } else {
                                let x = s.b.opt_unwrap(d.val.v);
                                s.finish(d.val);
                                x
                            };
                            Ok(Some(v))
                        },
                        &mut |s| {
                            let hit = load(s);
                            let hit = s.owned_boundary(Val { v: hit, own: false });
                            s.finish(d.val);
                            Ok(Some(hit))
                        },
                    )?;
                    Ok(Some(out))
                }
            },
        }
    }

    /// `m[key]`: one probe, borrowing the entry; an absent key faults with the key's text.
    pub(crate) fn map_index(&mut self, e: &Expr, map: &Expr, key: &Expr) -> Result<Val, Error> {
        let stable = self.stable_place(map);
        let mv = self.expr(map)?;
        if self.dead {
            return Ok(mv);
        }
        let mv = self.borrow(mv);
        let kv = self.expr(key)?;
        if self.dead {
            return Ok(kv);
        }
        let kv = self.borrow(kv);
        let mt = self.ty_of(mv);
        let value_ty = self.map_value_type(mv)?;
        let (kd, vd) = self.map_descs(mt)?;
        let vd = vd.ok_or_else(|| Error::new("a set has no values"))?;
        let ks = self.borrow_slot(kv);
        self.at(e.pos);
        let probe = self
            .word_map_symbol("msrt_map_get_ptr", mt)
            .unwrap_or("msrt_map_get_ptr");
        let p = self.call_runtime(probe, &[mv, kd, vd, ks], MTy::PTR)?;
        let missing = self
            .b
            .emit(Op::PtrIsNull, &[p], Imm::None, Some(MTy::BOOL))
            .expect("is_null");
        let (bad, good) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(missing, bad, &[], good, &[]);
        self.b.seal_block(bad);
        self.b.seal_block(good);
        self.b.switch_to(bad);
        self.fault_key_not_found(kv)?;
        self.b.switch_to(good);
        let v = self
            .b
            .emit(Op::Load, &[p], Imm::Ty(value_ty), Some(value_ty))
            .expect("load");
        if stable {
            self.stable_reads.insert(v);
        }
        Ok(Val { v, own: false })
    }

    /// A fresh empty map or set of type `ty`.
    pub(crate) fn map_new(&mut self, ty: MTy) -> Result<Value, Error> {
        let v = self.call_runtime("msrt_map_new", &[], ty)?;
        self.stamped(v)
    }

    /// A map or set that keeps the `Equal` and `Hashable` of the module that makes it, when its
    /// key type has local extensions; any other value is returned unchanged.
    pub(crate) fn stamped(&mut self, v: Value) -> Result<Value, Error> {
        let t = self.ty_of(v);
        let TyKind::Obj(n, args) = self.b.m.types.kind(t).clone() else {
            return Ok(v);
        };
        if (n != Native::Map && n != Native::Set) || !self.cx.holds_extension(self.b.m, args[0]) {
            return Ok(v);
        }
        let kd = self.type_desc(args[0]);
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
            .expect("slot");
        self.b.emit(Op::Put, &[slot, v], Imm::None, None);
        self.call_runtime("msrt_map_stamp", &[slot, kd], MTy::UNIT)?;
        Ok(self
            .b
            .emit(Op::Take, &[slot], Imm::Ty(t), Some(t))
            .expect("take"))
    }

    /// `Set(values)`: the set of a list's elements.
    pub(crate) fn set_from_list(&mut self, list: Val, ty: MTy) -> Result<Val, Error> {
        let TyKind::Obj(_, a) = self.b.m.types.kind(ty).clone() else {
            return Err(Error::new("not a set"));
        };
        let d = self.type_desc(a[0]);
        let l = self.borrow(list);
        let out = self.call_runtime("msrt_list_to_set", &[l, d], ty)?;
        let out = self.stamped(out)?;
        Ok(Val { v: out, own: true })
    }

    /// `List[T]()`, `Map[K, V]()`, `Set[T]()` and `Set(values)`.
    pub(crate) fn construct_collection(
        &mut self,
        view: &ms_check::api::hir::CallView<'_>,
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
        let wrapped = view
            .arguments
            .first()
            .is_some_and(|a| a.wrap_optional.is_some());
        match (self.b.m.types.kind(ty).clone(), arg) {
            (TyKind::List(elem), None) => {
                let v = self.b.list_lit(elem, &[]);
                Ok(Val { v, own: true })
            }
            // `List[T](reserve: n)`: an empty list with room for `n` items.
            (TyKind::List(elem), Some(n)) => {
                let input = Input {
                    val: Some(n),
                    wrapped,
                };
                let (has, n) = self.flatten_optional(input, "i64")?;
                let zero = self.b.iconst(0);
                let neg = self.b.icmp(Cc::Lt, n, zero);
                let floor = self.b.select(neg, zero, n);
                let cap = self.b.select(has, floor, zero);
                let v = self.b.list_new(elem, cap);
                Ok(Val { v, own: true })
            }
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
        let early = entries
            .iter()
            .any(|en| crate::mutation::has_try(&en.key) || crate::mutation::has_try(&en.value));
        let table = if early || entries.len() < CONST_MAP_TABLE {
            None
        } else {
            self.const_map_table(ty, entries)
        };
        if let Some(table) = table {
            return self.table_map_literal(ty, table);
        }
        if !early && entries.len() > LONG_MAP_LITERAL {
            return self.long_map_literal(ty, entries);
        }
        let mut acc = self.map_new(ty)?;
        if !early && entries.len() > 1 {
            return self.map_literal_in_place(ty, acc, entries);
        }
        for en in entries {
            // A `try` in a later key or value may return early: the map and key built so far
            // stay registered as temporaries until then.
            if early {
                self.pend_temp(acc);
            }
            let k = self.expr(&en.key)?;
            let k = if self.dead { k.v } else { self.owned(k) };
            if early && !self.dead {
                self.pend_temp(k);
            }
            let v = self.expr(&en.value)?;
            if early {
                self.unhold_temp(acc);
                if !self.dead {
                    self.unhold_temp(k);
                }
            }
            if self.dead {
                return Ok(self.dummy(ty));
            }
            let v = self.owned(v);
            acc = self.map_insert(acc, k, v)?;
        }
        Ok(Val { v: acc, own: true })
    }

    /// One item of a constant table: the tag-0 word of an `Int`, `Float` or `Bool` constant, or
    /// the tag-1 length and bytes of a `String` constant (see `msrt_map_add_table`).
    fn table_item(&self, t: MTy, e: &Expr, out: &mut Vec<u8>) -> Option<()> {
        if t == MTy::STR {
            let ExprKind::Text(parts) = &e.kind else {
                return None;
            };
            let mut text = String::new();
            for p in parts {
                let TextPart::Lit(s) = p else {
                    return None;
                };
                text.push_str(s);
            }
            out.push(1);
            out.extend_from_slice(&u32::try_from(text.len()).ok()?.to_le_bytes());
            out.extend_from_slice(text.as_bytes());
            return Some(());
        }
        if ![MTy::INT, MTy::FLOAT, MTy::BOOL].contains(&t) {
            return None;
        }
        out.push(0);
        out.extend_from_slice(&self.const_scalar(e)?.to_le_bytes());
        Some(())
    }

    /// The packed table of a literal whose keys (`Int` or `String`) and values (`Int`, `Float`,
    /// `Bool` or `String`) are all constants.
    pub(crate) fn const_map_table(&self, ty: MTy, entries: &[MapEntry]) -> Option<Vec<u8>> {
        let TyKind::Obj(_, a) = self.b.m.types.kind(ty) else {
            return None;
        };
        let (kt, vt) = (*a.first()?, *a.get(1)?);
        if kt != MTy::INT && kt != MTy::STR {
            return None;
        }
        let mut table = Vec::new();
        for en in entries {
            self.table_item(kt, &en.key, &mut table)?;
            self.table_item(vt, &en.value, &mut table)?;
        }
        Some(table)
    }

    /// A map of constants built by the runtime from static data: no code per entry, so a
    /// 20000-entry literal is one call rather than a function as long as the literal.
    fn table_map_literal(&mut self, ty: MTy, table: Vec<u8>) -> Result<Val, Error> {
        let (kd, vd) = self.map_descs(ty)?;
        let vd = vd.ok_or_else(|| Error::new("a set literal is not supported"))?;
        let empty = self.map_new(ty)?;
        let slot = self.put_slot(empty);
        let data = self.b.bytes_lit(table);
        let data = self.borrow_slot(data);
        self.call_runtime("msrt_map_add_table", &[slot, kd, vd, data], MTy::UNIT)?;
        Ok(Val {
            v: self.take_slot(slot, ty),
            own: true,
        })
    }

    /// A long literal is built in chunks, each a small map made by its own helper function when
    /// the chunk's code can move there (`FuncBuilder::outline`), and merged in order so a later
    /// entry still replaces an earlier one. One function holding every `msrt_map_add` call keeps
    /// the map's address and descriptors live across all of them, and register allocation is
    /// quadratic in that (5000 entries took 13 s of `llc`).
    fn long_map_literal(&mut self, ty: MTy, entries: &[MapEntry]) -> Result<Val, Error> {
        let (kd, vd) = self.map_descs(ty)?;
        let vd = vd.ok_or_else(|| Error::new("a set literal is not supported"))?;
        let mut acc: Option<Value> = None;
        for chunk in entries.chunks(LONG_MAP_CHUNK) {
            let mark = self.b.mark();
            let temps = self.temps.len();
            let empty = self.map_new(ty)?;
            let mut part = self.map_literal_in_place(ty, empty, chunk)?.v;
            if self.dead {
                return Ok(self.dummy(ty));
            }
            if self.temps.len() == temps {
                let name = format!("map.literal.{}", self.b.m.funcs.len());
                part = self.b.outline(mark, part, &name).unwrap_or(part);
            }
            acc = Some(match acc {
                None => part,
                Some(head) => {
                    let into = self.put_slot(head);
                    let from = self.borrow_slot(part);
                    self.call_runtime("msrt_map_merge", &[into, from, kd, vd], MTy::UNIT)?;
                    self.drop_value(part);
                    self.take_slot(into, ty)
                }
            });
        }
        let v = acc.expect("a long literal has entries");
        Ok(Val { v, own: true })
    }

    /// The entries of a literal with no early return, added to the map `acc` held in one slot.
    /// Each `msrt_map_add` takes its key and value out of two slots that the next entry fills
    /// again, so an entry costs two stores and a call; moving the map and the slots in and out
    /// per entry made a 20000-entry literal half a million IR lines.
    fn map_literal_in_place(
        &mut self,
        ty: MTy,
        acc: Value,
        entries: &[MapEntry],
    ) -> Result<Val, Error> {
        let (kd, vd) = self.map_descs(ty)?;
        let vd = vd.ok_or_else(|| Error::new("a set literal is not supported"))?;
        let slot = self.put_slot(acc);
        let mut held: Option<(Value, Value)> = None;
        for en in entries {
            let k = self.expr(&en.key)?;
            let k = if self.dead { k.v } else { self.owned(k) };
            let v = self.expr(&en.value)?;
            if self.dead {
                return Ok(self.dummy(ty));
            }
            let v = self.owned(v);
            let (ks, vs) = match held {
                Some(slots) => slots,
                None => {
                    let slots = (self.new_slot(self.ty_of(k)), self.new_slot(self.ty_of(v)));
                    held = Some(slots);
                    slots
                }
            };
            self.fill_slot(ks, k);
            self.fill_slot(vs, v);
            self.call_runtime("msrt_map_add", &[slot, kd, vd, ks, vs], MTy::UNIT)?;
        }
        Ok(Val {
            v: self.take_slot(slot, ty),
            own: true,
        })
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

    /// A stack slot for a value of type `t`.
    fn new_slot(&mut self, t: MTy) -> Value {
        self.b
            .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
            .expect("slot")
    }

    /// Stores the owned `x` in `slot`.
    fn fill_slot(&mut self, slot: Value, x: Value) {
        let op = if self.needs_drop(self.ty_of(x)) {
            Op::Put
        } else {
            Op::Store
        };
        self.b.emit(op, &[slot, x], Imm::None, None);
    }

    /// A stack slot holding the owned `x`.
    pub(crate) fn put_slot(&mut self, x: Value) -> Value {
        let slot = self.new_slot(self.ty_of(x));
        self.fill_slot(slot, x);
        slot
    }

    /// A stack slot giving a borrow of `x` to a runtime call that only reads it: nothing is
    /// copied and nothing is taken back or dropped afterwards.
    /// Faults with the missing key named; ends the current block.
    pub(crate) fn fault_key_not_found(&mut self, kv: Value) -> Result<(), Error> {
        let head = "map key not found";
        let msg = if self.ty_of(kv) == MTy::INT {
            let head = self.b.str_lit(&format!("{head}: "));
            let text = self.call_runtime("msrt_int_to_string", &[kv], MTy::STR)?;
            self.call_runtime("msrt_string_concat", &[head, text], MTy::STR)?
        } else if self.ty_of(kv) == MTy::STR {
            let open = self.b.str_lit(&format!("{head}: \""));
            let close = self.b.str_lit("\"");
            let text = self.call_runtime("msrt_string_concat", &[open, kv], MTy::STR)?;
            self.call_runtime("msrt_string_concat", &[text, close], MTy::STR)?
        } else {
            self.b.str_lit(head)
        };
        let fault = self.b.m.add_extern(ms_mir::ir::ExternDef {
            name: "msrt_fault_string".to_string(),
            params: vec![ms_mir::ir::Param {
                ty: MTy::STR,
                mode: ms_mir::ir::Mode::Borrow,
            }],
            ret: MTy::UNIT,
            noreturn: true,
            pure_: false,
            fresh: false,
            role: ms_mir::ir::ExternRole::None,
            leaf: crate::rtcall::rt_flags("msrt_fault_string").leaf,
            reads: crate::rtcall::rt_flags("msrt_fault_string").reads,
        });
        self.b.call_rt(fault, &[msg]);
        self.b.unreachable();
        Ok(())
    }

    pub(crate) fn borrow_slot(&mut self, x: Value) -> Value {
        let t = self.ty_of(x);
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
            .expect("slot");
        self.b.emit(Op::Store, &[slot, x], Imm::None, None);
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
        if name == "drain" {
            return self.drain_builder(old, result_ty);
        }
        if name == "add_default_from" {
            return self.add_default_from(old, decl, args, copy_result);
        }
        if name == "update" && matches!(self.b.m.types.kind(mt), TyKind::Obj(Native::Map, _)) {
            return self.map_update(old, args);
        }
        let set = matches!(self.b.m.types.kind(mt), TyKind::Obj(Native::Set, _));
        let text = decl.first().is_some_and(|p| p.ty.is_string());
        let sym = match (set, name) {
            (true, "add") => "msrt_set_add_copy".to_string(),
            (_, "insert") if matches!(self.b.m.types.kind(mt), TyKind::List(_)) => {
                "msrt_list_insert_copy".to_string()
            }
            (_, "append") if mt == MTy::BYTES && text => "msrt_strbuilder_append".to_string(),
            // `BytesBuilder.append_bytes` mutates in place; `msrt_bytes_concat` is the pure `Bytes.concat`.
            (_, "append_bytes") if mt == MTy::BYTES => "msrt_bytes_extend".to_string(),
            _ => crate::rtcall::method_symbol(self.b.m, mt, name)
                .ok_or_else(|| Error::new(format!("unsupported mutator {name}")))?,
        };
        // An owned element moves into the list: copying it would leave the caller a second
        // value to drop, and a resource would close twice.
        if let ("msrt_list_insert_copy", TyKind::List(elem)) =
            (sym.as_str(), self.b.m.types.kind(mt).clone())
            && let Some(value) = args.iter().find(|a| self.syms.str(a.name) == "value")
            && let Some(index) = args.iter().find(|a| self.syms.str(a.name) == "index")
            && (value.val.own || self.resource_temps.contains_key(&value.val.v))
            && !value.wrapped
            && value.val.v != old
        {
            let d = self.type_desc(elem);
            let i = self.borrow(index.val);
            // A staged resource stays registered for fault cleanup until the bounds check passes.
            let element = if self.resource_temps.contains_key(&value.val.v) {
                let n = self.b.list_len(old);
                let zero = self.b.iconst(0);
                let neg = self.b.icmp(ms_mir::ir::Cc::Lt, i, zero);
                let shifted = self.b.binop(ms_mir::ir::Op::IAdd, i, n);
                let r = self.b.select(neg, shifted, i);
                self.check_index(0, i, r, n, true);
                self.element_value(value)
            } else {
                value.val.v
            };
            let element = self.put_slot(element);
            let slot = self.put_slot(old);
            self.call_runtime("msrt_list_insert", &[slot, d, i, element], MTy::UNIT)?;
            let new = self.take_slot(slot, mt);
            let result = copy_result.then(|| {
                let v = self.clone_value(new);
                Val { v, own: true }
            });
            return Ok((new, result));
        }
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
            let v = self.clone_value(new);
            Val { v, own: true }
        });
        Ok((new, result))
    }

    /// `map.update(key, initial, change)`: one lookup finds or creates the entry (holding `initial`
    /// when it is new), `change` reads the stored value through its slot, and its result replaces
    /// the old value in place. The checker rejects a `change` that overlaps the receiver, so the
    /// slot stays valid across the call. A fault in `change` leaves the entry as it was.
    fn map_update(&mut self, old: Value, args: &[NArg]) -> Result<(Value, Option<Val>), Error> {
        let mt = self.ty_of(old);
        let arg = |s: &Self, n: &str| {
            args.iter()
                .find(|a| s.syms.str(a.name) == n)
                .copied()
                .ok_or_else(|| Error::new(format!("update without {n}")))
        };
        let (key, initial, change) = (
            arg(self, "key")?,
            arg(self, "initial")?,
            arg(self, "change")?,
        );
        let (_, vt) = match self.b.m.types.kind(mt).clone() {
            TyKind::Obj(_, a) if a.len() == 2 => (a[0], a[1]),
            _ => return Err(Error::new("update on a map without values")),
        };
        // A key the checker converts on the way in (`Int` to `Optional[Int]`) is wrapped first.
        let k = if key.wrapped {
            let v = self.element_value(&key);
            self.hold_temp(Val { v, own: true }).v
        } else {
            self.borrow(key.val)
        };
        let f = self.borrow(change.val);
        let init = self.owned(initial.val);
        let (kd, vd) = self.map_descs(mt)?;
        let vd = vd.ok_or_else(|| Error::new("a set has no values"))?;
        let slot = self.put_slot(old);
        let ks = self.borrow_slot(k);
        let ds = self.put_slot(init);
        let upsert =
            |s: &mut Self| s.call_runtime("msrt_map_slot_lent", &[slot, kd, vd, ks, ds], MTy::PTR);
        // A scalar-valued Int or String map probes through the inlined word lookup; only an absent
        // key reaches the runtime, which appends the entry.
        let p = match self.word_map_symbol("msrt_map_get_ptr", mt) {
            Some(probe) => {
                let hit = self.call_runtime(probe, &[slot, kd, vd, ks], MTy::PTR)?;
                let missing = self
                    .b
                    .emit(Op::PtrIsNull, &[hit], Imm::None, Some(MTy::BOOL))
                    .expect("is_null");
                self.two_ways_mode(
                    missing,
                    MTy::PTR,
                    Mode::Borrow,
                    &mut |s| upsert(s).map(Some),
                    &mut |_| Ok(Some(hit)),
                )?
                .v
            }
            None => upsert(self)?,
        };
        // A value that owns storage moves out of its slot and is released after `change` read it.
        let (take, put) = if self.needs_drop(vt) {
            (Op::Take, Op::Put)
        } else {
            (Op::Load, Op::Store)
        };
        let cur = self
            .b
            .emit(take, &[p], Imm::Ty(vt), Some(vt))
            .expect("take");
        let next = self.b.call_ind(f, &[cur]);
        self.drop_value(cur);
        self.b.emit(put, &[p, next], Imm::None, None);
        let new = self.take_slot(slot, mt);
        Ok((new, None))
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
            .find(|a| self.syms.str(a.name) == "key")
            .copied()
            .ok_or_else(|| Error::new("add_default_from without a key"))?;
        let create = args
            .iter()
            .find(|a| self.syms.str(a.name) == "create")
            .copied()
            .ok_or_else(|| Error::new("add_default_from without create"))?;
        let value_ty = decl
            .iter()
            .find(|p| self.syms.str(p.name) == "create")
            .and_then(|p| p.ty.result.clone())
            .ok_or_else(|| Error::new("add_default_from create is not a function"))?;
        let key_decl = decl[..1].to_vec();
        let add_decl = vec![
            decl[0].clone(),
            ct::Param {
                name: self.syms.intern("value"),
                ty: value_ty,
                mutable: false,
                positional: false,
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
            name: self.syms.intern("value"),
            val: Val { v: made, own: true },
            wrapped: false,
            reader: false,
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
            let v = self.clone_value(new);
            Val { v, own: true }
        });
        Ok((new, result))
    }

    /// `builder.drain()`: the accumulated value, leaving the builder empty. The runtime moving_params
    /// the buffer it freezes into text.
    fn drain_builder(&mut self, old: Value, result_ty: MTy) -> Result<(Value, Option<Val>), Error> {
        let empty = self.call_runtime("msrt_list_new", &[], MTy::BYTES)?;
        if result_ty == MTy::STR {
            let slot = self.put_slot(old);
            let text = self.call_runtime("msrt_strbuilder_freeze", &[slot], MTy::STR)?;
            return Ok((empty, Some(Val { v: text, own: true })));
        }
        Ok((empty, Some(Val { v: old, own: true })))
    }

    /// `map.get_or(key, fallback)`: the entry is read through its pointer, so a hit copies the
    /// value once and a miss copies nothing.
    pub(crate) fn map_get_or(
        &mut self,
        recv: Val,
        decl: &[ct::Param],
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let fallback = args
            .iter()
            .find(|a| self.syms.str(a.name) == "fallback")
            .ok_or_else(|| Error::new("get_or without a fallback"))?
            .val;
        // A key the checker converts on the way in takes the ordinary call, which converts it.
        let key = args
            .iter()
            .find(|a| self.syms.str(a.name) == "key" && !a.wrapped)
            .map(|a| a.val);
        let Some(key) = key else {
            return self.map_get_or_copied(recv, decl, args, result, fallback);
        };
        let mt = self.ty_of(recv.v);
        let mv = self.borrow(recv);
        let kv = self.borrow(key);
        let (kd, vd) = self.map_descs(mt)?;
        let vd = vd.ok_or_else(|| Error::new("a set has no values"))?;
        let ks = self.borrow_slot(kv);
        let sym = self
            .word_map_symbol("msrt_map_get_ptr", mt)
            .unwrap_or("msrt_map_get_ptr");
        let ptr = self.call_runtime(sym, &[mv, kd, vd, ks], MTy::PTR)?;
        let missing = self
            .b
            .emit(Op::PtrIsNull, &[ptr], Imm::None, Some(MTy::BOOL))
            .expect("is_null");
        self.two_ways(
            missing,
            result,
            &mut |s| Ok(Some(s.owned_boundary(fallback))),
            &mut |s| {
                let hit =
                    s.b.emit(Op::Load, &[ptr], Imm::Ty(result), Some(result))
                        .expect("load");
                let hit = s.clone_value(hit);
                // The eager fallback is unused on this path.
                s.finish(fallback);
                Ok(Some(hit))
            },
        )
    }

    /// `get_or` through `msrt_map_get`, which copies the entry into an `Optional`.
    fn map_get_or_copied(
        &mut self,
        recv: Val,
        decl: &[ct::Param],
        args: &[NArg],
        result: MTy,
        fallback: Val,
    ) -> Result<Val, Error> {
        let opt_ty = self.b.m.types.opt(result);
        let found = self.rt_method("msrt_map_get", recv, decl, args, opt_ty)?;
        let present = self.b.opt_is_some(found.v);
        let out = self.two_ways(
            present,
            result,
            &mut |s| {
                let x = s.b.opt_get(found.v);
                let hit = s.owned(Val { v: x, own: false });
                // The eager fallback is unused on this path.
                s.finish(fallback);
                Ok(Some(hit))
            },
            &mut |s| Ok(Some(s.owned(fallback))),
        )?;
        if found.own {
            self.drop_value(found.v);
        }
        Ok(out)
    }

    /// `map.entries()`: a list of fresh `MapEntry` types.
    pub(crate) fn map_entries(
        &mut self,
        recv_expr: Option<&ms_check::api::ast::Expr>,
        recv: Val,
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::List(entry) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("entries without a list type"));
        };
        let TyKind::Type(rid) = self.b.m.types.kind(entry).clone() else {
            return Err(Error::new("entries without a type"));
        };
        let (mv, hidden) = self.list_source(recv_expr, recv)?;
        let acc: Var = self.fresh_var(result);
        let empty = self.b.list_lit(entry, &[]);
        self.b.def_var(acc, empty);
        let m = self.b.use_var(mv);
        self.each_entry(m, &mut |s, key, value| {
            let value = value.ok_or_else(|| Error::new("entries of a set"))?;
            let ko = s.clone_value(key);
            let vo = s.clone_value(value);
            let tval = s.b.type_new(rid, &[ko, vo]);
            let cur = s.b.use_var(acc);
            let next = s.b.list_push(cur, tval);
            s.b.def_var(acc, next);
            Ok(())
        })?;
        self.release_source(mv, hidden);
        let out = self.b.use_var(acc);
        Ok(Val { v: out, own: true })
    }

    /// `list.entries()`: `ListEntry` types pairing each index with its element.
    pub(crate) fn list_entries(
        &mut self,
        recv_expr: Option<&ms_check::api::ast::Expr>,
        recv: Val,
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::List(entry) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("entries without a list type"));
        };
        let TyKind::Type(rid) = self.b.m.types.kind(entry).clone() else {
            return Err(Error::new("entries without a type"));
        };
        let (lv, hidden) = self.list_source(recv_expr, recv)?;
        let acc = self.fresh_var(result);
        let n = {
            let l = self.b.use_var(lv);
            self.b.list_len(l)
        };
        let first = self.b.list_new(entry, n);
        self.b.def_var(acc, first);
        self.each_element(lv, &mut |s, i, x| {
            let xo = s.owned_boundary(Val { v: x, own: false });
            let tval = s.b.type_new(rid, &[i, xo]);
            let cur = s.b.use_var(acc);
            let next = s.b.list_push(cur, tval);
            s.b.def_var(acc, next);
            Ok(None)
        })?;
        self.release_source(lv, hidden);
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
            // A set is a map without a value descriptor: a null pointer.
            None => self.b.iconst(0),
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
