//! Container reads that lower to a borrow of the entry instead of a copy of it.
//!
//! The ownership checker holds `let x = m.get(k)` and `if let x = m.get(k)` as lexical borrows
//! of the container (`crates/ms-check/OWNERSHIP.md`, "Borrowed results"), so the entry can be
//! read in place: a pointer or an index, a presence test and a load. An `Optional` built this way
//! is `opt.view`, a borrow that is never dropped.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::api::ast::{Expr, ExprKind};
use ms_check::api::ownership::{NativeBorrow, native_borrow};
use ms_mir::ir::{Imm, Mode, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};

/// A read whose result can be borrowed.
#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum Shape {
    /// `m.get(key)` on a `Map`.
    MapGet,
}

/// Where a found entry lives.
pub(crate) enum Entry {
    /// A map value, behind its entry pointer.
    Map { ptr: Value, ty: MTy },
}

impl Entry {
    fn ty(&self) -> MTy {
        match self {
            Entry::Map { ty, .. } => *ty,
        }
    }
}

impl<'a> FnLower<'a> {
    /// Whether `e` is a container read whose result can be borrowed: `m.get(k)` on a `Map` with a key
    /// of the map's key type, in a function the
    /// ownership checker vetted, with a payload `opt.view` can hold (not a boxed optional).
    /// Emits nothing.
    pub(crate) fn borrowed_shape(&mut self, e: &Expr) -> Result<Option<Shape>, Error> {
        let ExprKind::Call { callee, args } = &e.kind else {
            return Ok(None);
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return Ok(None);
        };
        let recv = self.ety(left);
        let shape = match native_borrow(&recv, self.syms.str(name), args.len()) {
            Some(NativeBorrow::MapGet) => {
                // A key the checker converts on the way in (an `Optional` key given a plain
                // value) takes the ordinary call, which applies the conversion.
                let map_ty = self.emty(left)?;
                let TyKind::Obj(_, parts) = self.b.m.types.kind(map_ty).clone() else {
                    return Ok(None);
                };
                let key_ty = self.emty(&args[0].value)?;
                if parts.first() != Some(&key_ty) {
                    return Ok(None);
                }
                Shape::MapGet
            }
            _ => return Ok(None),
        };
        let result = self.emty(e)?;
        let Some(inner) = self.b.m.opt_inner(result) else {
            return Ok(None);
        };
        if self.b.m.opt_is_boxed(inner) {
            return Ok(None);
        }
        Ok(Some(shape))
    }

    /// Evaluates the container and key of a borrowed read: the presence test and the entry. `None`
    /// when evaluation ended the block.
    pub(crate) fn borrowed_read(
        &mut self,
        shape: Shape,
        e: &Expr,
    ) -> Result<Option<(Value, Entry)>, Error> {
        let ExprKind::Call { callee, args } = &e.kind else {
            return Err(Error::new("a borrowed read is a call"));
        };
        let ExprKind::Member { left, .. } = &callee.kind else {
            return Err(Error::new("a borrowed read is a method call"));
        };
        let recv = self.expr(left)?;
        if self.dead {
            return Ok(None);
        }
        let recv = self.borrow(recv);
        let Shape::MapGet = shape;
        let key = self.expr(&args[0].value)?;
        if self.dead {
            return Ok(None);
        }
        let key = self.borrow(key);
        let mt = self.ty_of(recv);
        let ty = self.map_value_type(recv)?;
        let (kd, vd) = self.map_descs(mt)?;
        let vd = vd.ok_or_else(|| Error::new("a set has no values"))?;
        // The lookup only reads the key, so it borrows the key itself.
        let ks = self.borrow_slot(key);
        let sym = self
            .word_map_symbol("msrt_map_get_ptr", mt)
            .unwrap_or("msrt_map_get_ptr");
        self.at(e.pos);
        let ptr = self.call_runtime(sym, &[recv, kd, vd, ks], MTy::PTR)?;
        let missing = self
            .b
            .emit(Op::PtrIsNull, &[ptr], Imm::None, Some(MTy::BOOL))
            .expect("is_null");
        let present = self.b.unop(Op::Not, missing);
        Ok(Some((present, Entry::Map { ptr, ty })))
    }

    /// The entry's value, a borrow. Emitted where `present` holds.
    pub(crate) fn borrowed_payload(&mut self, entry: &Entry) -> Value {
        match entry {
            Entry::Map { ptr, ty } => self
                .b
                .emit(Op::Load, &[*ptr], Imm::Ty(*ty), Some(*ty))
                .expect("load"),
        }
    }

    /// The read as a borrowed `Optional`: `opt.view` of the entry where present, else `opt.none`.
    pub(crate) fn borrowed_optional(
        &mut self,
        present: Value,
        entry: &Entry,
    ) -> Result<Val, Error> {
        let ty = entry.ty();
        let opt_ty = self.b.m.types.opt(ty);
        let borrowed = self.needs_drop(ty);
        self.two_ways_mode(
            present,
            opt_ty,
            Mode::Borrow,
            &mut |s| {
                let p = s.borrowed_payload(entry);
                Ok(Some(if borrowed {
                    s.b.opt_view(p)
                } else {
                    s.b.opt_some(p)
                }))
            },
            &mut |s| Ok(Some(s.b.opt_none(opt_ty))),
        )
    }
}
