//! Lookups in a literal map of constants, answered without building the map.
//!
//! `{"open": 3, "report": 1}.get(name).get(0)` used to build the map (an allocation and one
//! insert per entry) on every call, 85 ns for five entries. A small literal of constants is
//! instead searched by comparing the key with each constant in turn.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::api::ast::{Expr, ExprKind, MapEntry};
use ms_check::api::hir::CallView;
use ms_check::api::types::Builtin;
use ms_mir::builder::Var;
use ms_mir::ir::{Mode, Value};
use ms_mir::types::{Ty as MTy, TyKind};

/// Literals with more entries than this build the map: a long comparison chain costs more than
/// a hash probe.
const MAX_ENTRIES: usize = 12;

impl FnLower<'_> {
    /// The entries of `map` when it is a small `Map` literal whose keys and values are constants.
    pub(crate) fn const_literal<'e>(&self, map: &'e Expr, map_ty: MTy) -> Option<&'e [MapEntry]> {
        let ExprKind::Map(entries) = &map.kind else {
            return None;
        };
        if entries.is_empty() || entries.len() > MAX_ENTRIES || !self.ety(map).is(Builtin::Map) {
            return None;
        }
        self.const_map_table(map_ty, entries)?;
        Some(entries)
    }

    /// Searches `entries` for the borrowed key `key`: a flag for a hit and a variable holding the
    /// entry's value on a hit. The last of two equal keys wins, as when the map is built.
    fn const_probe(
        &mut self,
        entries: &[MapEntry],
        key: Value,
        key_ty: MTy,
        value_ty: MTy,
    ) -> Result<(Value, Var), Error> {
        // The values are constants, so the variable holds a borrow of one: a string literal is
        // static data, and whoever keeps the value copies it.
        let found = self.b.declare_var(MTy::BOOL, Mode::Borrow);
        let value = self.b.declare_var(value_ty, Mode::Borrow);
        let join = self.b.new_block();
        for en in entries.iter().rev() {
            let k = self.expr(&en.key)?;
            let hit = self.equal(key_ty, Val { v: key, own: false }, k)?;
            let (yes, no) = (self.b.new_block(), self.b.new_block());
            self.b.br_if(hit, yes, &[], no, &[]);
            self.b.seal_block(yes);
            self.b.seal_block(no);
            self.enter(yes);
            let v = self.expr(&en.value)?;
            self.b.def_var(value, v.v);
            let t = self.b.bconst(true);
            self.b.def_var(found, t);
            self.b.br(join, &[]);
            self.enter(no);
        }
        // A miss still defines the value variable, with a constant of the right type.
        let v = self.expr(&entries[0].value)?;
        self.b.def_var(value, v.v);
        let f = self.b.bconst(false);
        self.b.def_var(found, f);
        self.b.br(join, &[]);
        self.b.seal_block(join);
        self.enter(join);
        Ok((self.b.use_var(found), value))
    }

    /// The key and value types of a map literal's type.
    fn const_types(&self, map_ty: MTy) -> Option<(MTy, MTy)> {
        let TyKind::Obj(_, parts) = self.b.m.types.kind(map_ty) else {
            return None;
        };
        Some((*parts.first()?, *parts.get(1)?))
    }

    /// `{...}.get(key)` followed by `.get()`, `.get(default)`, `.is_some()` or `.is_none()`.
    pub(crate) fn const_get_chain(
        &mut self,
        view: &CallView<'_>,
        entries: &[MapEntry],
        map_ty: MTy,
        key: &Expr,
        name: &str,
    ) -> Result<Option<Val>, Error> {
        let Some((key_ty, value_ty)) = self.const_types(map_ty) else {
            return Ok(None);
        };
        let kv = self.expr(key)?;
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
            return Ok(Some(Val { v: kv, own: false }));
        }
        let (found, value) = self.const_probe(entries, kv, key_ty, value_ty)?;
        let missing = self.b.unop(ms_mir::ir::Op::Not, found);
        self.get_chain_tail(name, default, missing, value_ty, &mut |s| {
            s.b.use_var(value)
        })
    }

    /// `{...}.contains(key)` and `{...}.get(key)` on a literal receiver.
    pub(crate) fn const_map_method(
        &mut self,
        recv_expr: &Expr,
        view: &CallView<'_>,
        name: &str,
    ) -> Result<Option<Val>, Error> {
        if !matches!(name, "contains" | "get") || !self.ety(recv_expr).is(Builtin::Map) {
            return Ok(None);
        }
        let map_ty = self.emty(recv_expr)?;
        let Some(entries) = self.const_literal(recv_expr, map_ty) else {
            return Ok(None);
        };
        let [arg] = view.arguments.as_slice() else {
            return Ok(None);
        };
        let Some((key_ty, value_ty)) = self.const_types(map_ty) else {
            return Ok(None);
        };
        // A key the checker converts on the way in takes the ordinary call.
        if self.emty(arg.expr)? != key_ty {
            return Ok(None);
        }
        let kv = self.expr(arg.expr)?;
        if self.dead {
            return Ok(Some(kv));
        }
        let kv = self.borrow(kv);
        let (found, value) = self.const_probe(entries, kv, key_ty, value_ty)?;
        if name == "contains" {
            return Ok(Some(Val {
                v: found,
                own: false,
            }));
        }
        let opt_ty = self.b.m.types.opt(value_ty);
        let out = self.two_ways(
            found,
            opt_ty,
            &mut |s| {
                let v = s.b.use_var(value);
                let v = s.owned(Val { v, own: false });
                Ok(Some(s.b.opt_some(v)))
            },
            &mut |s| Ok(Some(s.b.opt_none(opt_ty))),
        )?;
        Ok(Some(out))
    }
}
