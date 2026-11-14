//! Exclusive (`var`) borrows: `var x = place` and `if var x = place[key]?`.
//!
//! The ownership checker guarantees that while `x` lives nothing else reads, changes or moves
//! the origin, so `x` is lowered as a name for the origin's place instead of a value: a read of
//! `x` reads the place, a change to `x` updates the place. Nothing is taken out of the origin,
//! so early exits, `try` and faults need no put-back.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::api::ast::*;
use ms_check::api::hir::Resolution;
use ms_check::api::types::{BindingRef, Name};
use ms_mir::builder::Var;
use ms_mir::ir::{Cc, Imm, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};

/// One step from a local to the part a borrow names.
#[derive(Clone)]
pub(crate) enum AStep {
    /// A type field.
    Field(Name),
    /// A list element, at an index saved when the borrow was made.
    Index(Value),
    /// A map entry, at a key saved (and kept alive) when the borrow was made, with the entry's
    /// address when the borrow found it in this function: the exclusive borrow keeps the map
    /// from gaining or losing entries, so the address holds until the borrow ends.
    Key(Var, Option<Value>),
    /// The payload of an `Optional` the match has shown present (`c?.f()`).
    Some,
}

/// The place a borrow binding names.
#[derive(Clone)]
pub(crate) struct Alias {
    pub root: BindingRef,
    pub steps: Vec<AStep>,
}

/// How `if` tests the value it binds from.
pub(crate) enum Found {
    /// An `Optional` result.
    Opt(Val),
    /// A `Bool` computed without reading the value.
    Present(Value),
}

type Update<'u, 'a> = &'u mut dyn FnMut(&mut FnLower<'a>, Value) -> Result<Value, Error>;

impl<'a> FnLower<'a> {
    /// The place named by a variable or a chain of fields and elements from one.
    pub(crate) fn alias_chain(&mut self, e: &Expr) -> Result<Alias, Error> {
        match &e.kind {
            ExprKind::Name(_) => {
                let Resolution::Local(b) = self.hir.resolution(e) else {
                    return Err(Error::new(
                        "a mutable borrow needs a variable to borrow from",
                    ));
                };
                Ok(match self.aliases.get(&b.uid) {
                    Some(a) => a.clone(),
                    None => Alias {
                        root: b,
                        steps: Vec::new(),
                    },
                })
            }
            ExprKind::Member { left, name } => {
                let mut a = self.alias_chain(left)?;
                a.steps.push(AStep::Field(*name));
                Ok(a)
            }
            ExprKind::Call { callee, args } => {
                // `map.get(key).get()`: the entry, as `if var x = map.get(key)` names it; an
                // absent key faults.
                if let ExprKind::Member { left, name } = &callee.kind
                    && self.syms.str(name) == "get"
                    && args.is_empty()
                    && matches!(&left.kind, ExprKind::Call { .. })
                    && !self
                        .cx
                        .ownership
                        .getter_borrows
                        .contains_key(&(self.hir.data.file, e.id))
                {
                    let (alias, found) = self.alias_accessor(left, None)?;
                    let (ok, bad) = (self.b.new_block(), self.b.new_block());
                    self.b.br_if(found, ok, &[], bad, &[]);
                    self.b.seal_block(ok);
                    self.b.seal_block(bad);
                    self.b.switch_to(bad);
                    self.b.fault(ms_mir::ir::FaultKind::NoneUnwrap);
                    self.b.switch_to(ok);
                    return Ok(alias);
                }
                let Some(fields) = self
                    .cx
                    .ownership
                    .getter_borrows
                    .get(&(self.hir.data.file, e.id))
                    .cloned()
                else {
                    return Err(Error::new(
                        "a mutable borrow needs a field or element of a variable",
                    ));
                };
                let arg = match (&callee.kind, self.hir.resolution(e)) {
                    (ExprKind::Member { left, .. }, Resolution::Method(_)) => &**left,
                    _ => &args[0].value,
                };
                // The callee runs for its effects; the borrow then names the part it returned,
                // which the checker found to be this field chain of the argument.
                let result = self.expr(e)?;
                if result.own {
                    self.drop_value(result.v);
                }
                let mut a = self.alias_chain(arg)?;
                a.steps.extend(fields.into_iter().map(AStep::Field));
                Ok(a)
            }
            _ => {
                let Some((left, index)) = crate::mutation::index_parts(self.syms, &self.hir, e)
                else {
                    return Err(Error::new(
                        "a mutable borrow needs a field or element of a variable",
                    ));
                };
                let mut a = self.alias_chain(left)?;
                let whole = self.alias_read(&a)?;
                let i = self.expr(index)?;
                if matches!(self.b.m.types.kind(self.ty_of(whole.v)), TyKind::Obj(..)) {
                    // A map entry: found once, and a missing key faults like a read.
                    let at = self.borrow(i);
                    let copy = self.clone_value(at);
                    let key = self.bind_hidden(Val { v: copy, own: true });
                    let ptr = self.map_entry_ptr(whole.v, key)?;
                    let missing = self
                        .b
                        .emit(Op::PtrIsNull, &[ptr], Imm::None, Some(MTy::BOOL))
                        .expect("is_null");
                    let (bad, good) = (self.b.new_block(), self.b.new_block());
                    self.b.br_if(missing, bad, &[], good, &[]);
                    self.b.seal_block(bad);
                    self.b.seal_block(good);
                    self.b.switch_to(bad);
                    self.fault_key_not_found(at)?;
                    self.b.switch_to(good);
                    a.steps.push(AStep::Key(key, Some(ptr)));
                    return Ok(a);
                }
                let at = self.borrow(i);
                a.steps.push(AStep::Index(at));
                Ok(a)
            }
        }
    }

    /// The place `if var name = recv[key]?` (or `if var name = map.get(key)`) names, and the
    /// test for whether it exists.
    pub(crate) fn alias_accessor(
        &mut self,
        cond: &Expr,
        body: Option<&[Stmt]>,
    ) -> Result<(Alias, Value), Error> {
        let (left, index) = match &cond.kind {
            ExprKind::Probe(target) => {
                crate::mutation::index_parts(self.syms, &self.hir, target)
                    .ok_or_else(|| Error::new("`?` needs an index of a map or list"))?
            }
            ExprKind::Call { callee, args }
                if matches!(&callee.kind, ExprKind::Member { name, .. } if self.syms.str(name) == "get")
                    && args.len() == 1 =>
            {
                let ExprKind::Member { left, .. } = &callee.kind else {
                    unreachable!("matched above")
                };
                (&**left, &args[0].value)
            }
            _ => {
                return Err(Error::new(
                    "`if var` borrows an entry written as `place[key]?` or `map.get(key)`",
                ));
            }
        };
        let mut a = self.alias_chain(left)?;
        let whole = self.alias_read(&a)?;
        let ty = self.ty_of(whole.v);
        match self.b.m.types.kind(ty).clone() {
            TyKind::List(_) => {
                let i = self.expr(index)?;
                let at = self.borrow(i);
                let zero = self.b.iconst(0);
                let len = self.b.list_len(whole.v);
                let above = self.b.icmp(Cc::Ge, at, zero);
                let below = self.b.icmp(Cc::Lt, at, len);
                let found = self.b.binop(Op::And, above, below);
                a.steps.push(AStep::Index(at));
                Ok((a, found))
            }
            TyKind::Obj(..) => {
                // One lookup finds the entry: the test is its address, and the borrow reads
                // and writes through it.
                let k = self.expr(index)?;
                // A key named by an unchanging variable is borrowed for the alias's lifetime.
                let unchanging = !k.own
                    && matches!(&index.kind, ExprKind::Name(_))
                    && matches!(
                        self.hir.resolution(index),
                        Resolution::Local(b) if !b.mutable
                            || body.is_some_and(|body| !crate::mutation::mutated_locals(
                                self.syms,
                                &self.hir,
                                ms_check::api::hir::Body::Block(body),
                                &self.cx.callables,
                                &self.cx.mutated,
                            )
                            .contains(&b.uid))
                    );
                let key = if unchanging {
                    let var = self
                        .b
                        .declare_var(self.ty_of(k.v), ms_mir::ir::Mode::Borrow);
                    self.b.def_var(var, k.v);
                    var
                } else if k.own {
                    self.bind_hidden(k)
                } else {
                    // The body changes the key's variable: the borrow keeps the key it found the
                    // entry by, a declared copy.
                    let copy = self.clone_value(k.v);
                    self.bind_hidden(Val { v: copy, own: true })
                };
                let ptr = self.map_entry_ptr(whole.v, key)?;
                let missing = self
                    .b
                    .emit(Op::PtrIsNull, &[ptr], Imm::None, Some(MTy::BOOL))
                    .expect("is_null");
                let found = self.b.unop(Op::Not, missing);
                a.steps.push(AStep::Key(key, Some(ptr)));
                Ok((a, found))
            }
            _ => Err(Error::new("`?` needs an index of a map or list")),
        }
    }

    /// The address of the payload `place` names, when `place` is a borrow of a boxed optional's
    /// payload (`c?.f()` on `left: Node?`): the box is the payload's storage, so a callee that
    /// changes it writes there, and nothing is unboxed, copied back or reboxed.
    pub(crate) fn alias_payload_addr(&mut self, place: &Expr) -> Option<Value> {
        if !matches!(place.kind, ExprKind::Name(_)) {
            return None;
        }
        let Resolution::Local(b) = self.hir.resolution(place) else {
            return None;
        };
        let mut a = self.aliases.get(&b.uid)?.clone();
        if !matches!(a.steps.pop(), Some(AStep::Some)) {
            return None;
        }
        let held = self.alias_read(&a).ok()?.v;
        let inner = self.b.m.opt_inner(self.ty_of(held))?;
        if !ms_mir::ir::Boxing::default().opt(self.b.m, inner) {
            return None;
        }
        Some(self.b.opt_addr(held))
    }

    /// The current value of a borrowed place, as a borrow.
    pub(crate) fn alias_read(&mut self, a: &Alias) -> Result<Val, Error> {
        let mut cur = self.read_local(&a.root)?.v;
        for s in &a.steps {
            cur = match s {
                AStep::Field(name) => {
                    let (rid, idx) = self.field_index(cur, *name)?;
                    self.b.type_get(rid, idx, cur)
                }
                AStep::Index(at) => self.b.list_get(cur, *at),
                AStep::Key(var, at) => {
                    let ptr = match at {
                        Some(p) => *p,
                        None => self.map_entry_ptr(cur, *var)?,
                    };
                    let vty = self.map_value_type(cur)?;
                    self.b
                        .emit(Op::Load, &[ptr], Imm::Ty(vty), Some(vty))
                        .expect("load")
                }
                AStep::Some => self.b.opt_get(cur),
            };
        }
        Ok(Val { v: cur, own: false })
    }

    /// Replaces the part named by `a` and then `fields` by `f(current)`.
    pub(crate) fn alias_update(
        &mut self,
        a: &Alias,
        fields: &[Name],
        f: Update<'_, 'a>,
    ) -> Result<(), Error> {
        let mut steps = a.steps.clone();
        steps.extend(fields.iter().map(|n| AStep::Field(*n)));
        let l = self.local(&a.root)?;
        let root = self.local_take(&l);
        let updated = self.update_steps(root, &steps, f)?;
        self.local_put(&l, updated);
        Ok(())
    }

    /// Returns `obj` (owned) with the part at `steps` replaced by `f(part)`.
    fn update_steps(
        &mut self,
        obj: Value,
        steps: &[AStep],
        f: Update<'_, 'a>,
    ) -> Result<Value, Error> {
        let Some((first, rest)) = steps.split_first() else {
            return f(self, obj);
        };
        match first {
            AStep::Field(name) => {
                let (rid, idx) = self.field_index(obj, *name)?;
                let cur = self.b.type_get(rid, idx, obj);
                let (cur_own, moved) = self.take_projection(cur);
                let inner = self.update_steps(cur_own, rest, f)?;
                Ok(if moved {
                    self.b.type_fill(rid, idx, obj, inner)
                } else {
                    self.b.type_set(rid, idx, obj, inner)
                })
            }
            AStep::Index(at) => {
                let (elem, moved) = self.list_elem_at(obj, *at)?;
                let inner = self.update_steps(elem, rest, f)?;
                Ok(if moved {
                    self.b.list_fill(obj, *at, inner)
                } else {
                    self.b.list_set(obj, *at, inner)
                })
            }
            AStep::Some => {
                // The match showed the optional present: its payload moves out, changes, and
                // moves back in; nothing is copied.
                let payload = self.b.opt_unbox(obj);
                let inner = self.update_steps(payload, rest, f)?;
                Ok(self.b.opt_some(inner))
            }
            AStep::Key(var, at) => {
                // The entry is changed where it lies: its value is taken out of the slot,
                // updated and put back, so the map is not searched or rebuilt again.
                let ptr = match at {
                    Some(p) => *p,
                    None => self.map_entry_ptr(obj, *var)?,
                };
                let vty = self.map_value_type(obj)?;
                let drops = self.needs_drop(vty);
                let (take, put) = if drops {
                    (Op::Take, Op::Put)
                } else {
                    (Op::Load, Op::Store)
                };
                let cur = self
                    .b
                    .emit(take, &[ptr], Imm::Ty(vty), Some(vty))
                    .expect("take");
                let inner = self.update_steps(cur, rest, f)?;
                self.b.emit(put, &[ptr, inner], Imm::None, None);
                Ok(obj)
            }
        }
    }

    fn field_index(&self, obj: Value, name: Name) -> Result<(ms_mir::types::TypeId, u32), Error> {
        let TyKind::Type(rid) = self.b.m.types.kind(self.ty_of(obj)).clone() else {
            return Err(Error::new("field access on a non-type"));
        };
        let idx = self.b.m.type_defs[rid.index()]
            .fields
            .iter()
            .position(|f| f.0 == self.syms.str(name))
            .ok_or_else(|| {
                Error::new(format!("no field {name_t}", name_t = self.syms.str(name)))
            })?;
        Ok((rid, idx as u32))
    }

    /// The type of a map's values.
    pub(crate) fn map_value_type(&self, map: Value) -> Result<MTy, Error> {
        match self.b.m.types.kind(self.ty_of(map)).clone() {
            TyKind::Obj(_, a) if a.len() == 2 => Ok(a[1]),
            _ => Err(Error::new("a keyed borrow needs a map")),
        }
    }

    /// A pointer to the entry for the key held in `key`, which must be present.
    fn map_entry_ptr(&mut self, map: Value, key: Var) -> Result<Value, Error> {
        let mt = self.ty_of(map);
        let (kd, vd) = self.map_descs(mt)?;
        let vd = vd.ok_or_else(|| Error::new("a keyed borrow needs a map"))?;
        let k = self.b.use_var(key);
        // The lookup only reads the key, so it borrows the key itself.
        let kslot = self.borrow_slot(k);
        let sym = self
            .word_map_symbol("msrt_map_get_ptr", mt)
            .unwrap_or("msrt_map_get_ptr");
        self.call_runtime(sym, &[map, kd, vd, kslot], MTy::PTR)
    }
}
