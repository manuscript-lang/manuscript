//! Exclusive (`var`) borrows: `var x = place` and `if var x = accessor(place)`.
//!
//! The ownership checker guarantees that while `x` lives nothing else reads, changes or moves
//! the origin, so `x` is lowered as a name for the origin's place instead of a value: a read of
//! `x` reads the place, a change to `x` updates the place. Nothing is taken out of the origin,
//! so early exits, `try` and faults need no put-back.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::hir::Resolution;
use ms_check::types::{BindingRef, Name};
use ms_mir::builder::Var;
use ms_mir::ir::{Imm, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::*;

/// One step from a local to the part a borrow names.
#[derive(Clone)]
pub(crate) enum AStep {
    /// A record field.
    Field(Name),
    /// A list element, at an index saved when the borrow was made.
    Index(Value),
    /// A map entry, at a key saved (and kept alive) when the borrow was made.
    Key(Var),
}

/// The place a borrow binding names.
#[derive(Clone)]
pub(crate) struct Alias {
    pub root: BindingRef,
    pub steps: Vec<AStep>,
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
                let Some(fields) = self.cx.getters.get(&(self.hir.data.file, e.id)).cloned() else {
                    return Err(Error::new(
                        "a mutable borrow needs a field or element of a variable",
                    ));
                };
                let arg = match (&callee.kind, self.hir.resolution(e)) {
                    (ExprKind::Member { left, .. }, Resolution::Method(_)) => &**left,
                    _ => &args[0].value,
                };
                let mut a = self.alias_chain(arg)?;
                a.steps.extend(fields.into_iter().map(AStep::Field));
                Ok(a)
            }
            _ => {
                let Some((left, index)) = crate::mutation::index_parts(&self.hir, e) else {
                    return Err(Error::new(
                        "a mutable borrow needs a field or element of a variable",
                    ));
                };
                let mut a = self.alias_chain(left)?;
                let i = self.expr(index)?;
                let at = self.borrow(i);
                a.steps.push(AStep::Index(at));
                Ok(a)
            }
        }
    }

    /// The place `if var name = recv.get(key)` (or `first`, `last`) names.
    pub(crate) fn alias_accessor(&mut self, cond: &Expr) -> Result<(Alias, Val), Error> {
        let ExprKind::Call { callee, args } = &cond.kind else {
            return Err(Error::new(
                "`if var` borrows the payload of a call such as `m.get(key)`, `xs.first()` or `xs.last()`",
            ));
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return Err(Error::new("`if var` needs a method call on a place"));
        };
        let mut a = self.alias_chain(left)?;
        let whole = self.alias_read(&a)?;
        let ty = self.ty_of(whole.v);
        let mut values = Vec::new();
        match (self.b.m.types.kind(ty).clone(), name.as_str()) {
            (TyKind::List(_), "first") => {
                let zero = self.b.iconst(0);
                a.steps.push(AStep::Index(zero));
            }
            (TyKind::List(_), "last") => {
                let len = self.b.list_len(whole.v);
                let one = self.b.iconst(1);
                let at = self.b.binop(Op::ISub, len, one);
                a.steps.push(AStep::Index(at));
            }
            (TyKind::List(_), "get") if args.len() == 1 => {
                let i = self.expr(&args[0].value)?;
                let at = self.borrow(i);
                a.steps.push(AStep::Index(at));
                values.push(Val { v: at, own: false });
            }
            (TyKind::Obj(..), "get") if args.len() == 1 => {
                let k = self.expr(&args[0].value)?;
                let key = self.bind_hidden(k);
                a.steps.push(AStep::Key(key));
                let v = self.b.use_var(key);
                values.push(Val { v, own: false });
            }
            _ => {
                return Err(Error::new(
                    "`if var` supports `get` on a map or list and `first` or `last` on a list",
                ));
            }
        }
        let Resolution::Method(method) = self.hir.resolution(cond) else {
            return Err(Error::new("`if var` needs a method call on a place"));
        };
        let args = method
            .ty
            .params
            .iter()
            .zip(values)
            .map(|(p, val)| crate::native::NArg {
                name: p.name,
                val,
                wrapped: false,
            })
            .collect::<Vec<_>>();
        let result = self.emty(cond)?;
        // Test the same receiver and key the borrow will name. Re-lowering `cond`
        // would run calls in its receiver path or key a second time.
        let value = self.bound_native_call(&method, whole, &args, result)?;
        Ok((a, value))
    }

    /// The current value of a borrowed place, as a borrow.
    pub(crate) fn alias_read(&mut self, a: &Alias) -> Result<Val, Error> {
        let mut cur = self.read_local(&a.root)?.v;
        for s in &a.steps {
            cur = match s {
                AStep::Field(name) => {
                    let (rid, idx) = self.field_index(cur, *name)?;
                    self.b.rec_get(rid, idx, cur)
                }
                AStep::Index(at) => self.b.list_get(cur, *at),
                AStep::Key(var) => {
                    let ptr = self.map_entry_ptr(cur, *var)?;
                    let vty = self.map_value_type(cur)?;
                    self.b
                        .emit(Op::Load, &[ptr], Imm::Ty(vty), Some(vty))
                        .expect("load")
                }
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
                let cur = self.b.rec_get(rid, idx, obj);
                let (cur_own, moved) = self.take_projection(cur);
                let inner = self.update_steps(cur_own, rest, f)?;
                Ok(if moved {
                    self.b.rec_fill(rid, idx, obj, inner)
                } else {
                    self.b.rec_set(rid, idx, obj, inner)
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
            AStep::Key(var) => {
                let ptr = self.map_entry_ptr(obj, *var)?;
                let vty = self.map_value_type(obj)?;
                let held = self
                    .b
                    .emit(Op::Load, &[ptr], Imm::Ty(vty), Some(vty))
                    .expect("load");
                let cur = self.owned(Val {
                    v: held,
                    own: false,
                });
                let inner = self.update_steps(cur, rest, f)?;
                let key = self.b.use_var(*var);
                let key = self.owned(Val { v: key, own: false });
                self.map_insert(obj, key, inner)
            }
        }
    }

    fn field_index(&self, obj: Value, name: Name) -> Result<(ms_mir::types::RecId, u32), Error> {
        let TyKind::Rec(rid) = self.b.m.types.kind(self.ty_of(obj)).clone() else {
            return Err(Error::new("field access on a non-record"));
        };
        let idx = self.b.m.records[rid.index()]
            .fields
            .iter()
            .position(|f| f.0 == name.as_str())
            .ok_or_else(|| Error::new(format!("no field {name}")))?;
        Ok((rid, idx as u32))
    }

    /// The type of a map's values.
    fn map_value_type(&self, map: Value) -> Result<MTy, Error> {
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
        // The lookup only reads the key, so it lends the key itself.
        let kslot = self.lend_slot(k);
        self.call_runtime("msrt_map_get_ptr", &[map, kd, vd, kslot], MTy::PTR)
    }
}
