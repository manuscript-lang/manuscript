//! Container reads that lower to a borrow of the entry instead of a copy of it.
//!
//! The ownership checker holds `let x = m.get(k)` and `if let x = xs.first()` as lexical borrows
//! of the container (`crates/ms-check/OWNERSHIP.md`, "Borrowed results"), so the entry can be
//! read in place: a pointer or an index, a presence test and a load. An `Optional` built this way
//! is `opt.view`, a borrow that is never dropped.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_mir::ir::{Cc, Imm, Mode, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::{Expr, ExprKind};

/// A read whose result can be lent.
#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum Shape {
    /// `m.get(key)` on a `Map`.
    MapGet,
    /// `xs.first()` on a `List`.
    First,
    /// `xs.last()` on a `List`.
    Last,
}

/// Where a found entry lives.
pub(crate) enum Entry {
    /// A map value, behind its entry pointer.
    Map { ptr: Value, ty: MTy },
    /// A list element at an index that is in range.
    List { list: Value, index: Value, ty: MTy },
}

impl Entry {
    fn ty(&self) -> MTy {
        match self {
            Entry::Map { ty, .. } | Entry::List { ty, .. } => *ty,
        }
    }
}

impl<'a> FnLower<'a> {
    /// Whether `e` is a container read whose result can be lent: `m.get(k)` on a `Map` with a key
    /// of the map's key type, or `xs.first()` / `xs.last()` on a `List`, in a function the
    /// ownership checker vetted, with a payload `opt.view` can hold (not a boxed optional).
    /// Emits nothing.
    pub(crate) fn lent_shape(&mut self, e: &Expr) -> Result<Option<Shape>, Error> {
        if !self.ownership_checked() {
            return Ok(None);
        }
        let ExprKind::Call { callee, args } = &e.kind else {
            return Ok(None);
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return Ok(None);
        };
        let recv = self.ety(left);
        let shape = match (name.as_str(), args.as_slice()) {
            ("get", [key]) if key.name.is_none() && recv.is_std("Map") => {
                // A key the checker converts on the way in (an `Optional` key given a plain
                // value) takes the ordinary call, which applies the conversion.
                let map_ty = self.emty(left)?;
                let TyKind::Obj(_, parts) = self.b.m.types.kind(map_ty).clone() else {
                    return Ok(None);
                };
                let key_ty = self.emty(&key.value)?;
                if parts.first() != Some(&key_ty) {
                    return Ok(None);
                }
                Shape::MapGet
            }
            ("first", []) if recv.is_std("List") => Shape::First,
            ("last", []) if recv.is_std("List") => Shape::Last,
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

    /// Evaluates the container and key of a lent read: the presence test and the entry. `None`
    /// when evaluation ended the block.
    pub(crate) fn lent_read(
        &mut self,
        shape: Shape,
        e: &Expr,
    ) -> Result<Option<(Value, Entry)>, Error> {
        let ExprKind::Call { callee, args } = &e.kind else {
            return Err(Error::new("a lent read is a call"));
        };
        let ExprKind::Member { left, .. } = &callee.kind else {
            return Err(Error::new("a lent read is a method call"));
        };
        let recv = self.expr(left)?;
        if self.dead {
            return Ok(None);
        }
        let recv = self.borrow(recv);
        if shape == Shape::MapGet {
            let key = self.expr(&args[0].value)?;
            if self.dead {
                return Ok(None);
            }
            let key = self.borrow(key);
            let mt = self.ty_of(recv);
            let ty = self.map_value_type(recv)?;
            let (kd, vd) = self.map_descs(mt)?;
            let vd = vd.ok_or_else(|| Error::new("a set has no values"))?;
            // The lookup only reads the key, so it lends the key itself.
            let ks = self.lend_slot(key);
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
            return Ok(Some((present, Entry::Map { ptr, ty })));
        }
        let len = self.b.list_len(recv);
        let zero = self.b.iconst(0);
        let present = self.b.icmp(Cc::Gt, len, zero);
        let index = if shape == Shape::First {
            zero
        } else {
            let one = self.b.iconst(1);
            self.b.binop(Op::ISub, len, one)
        };
        let ty = self
            .b
            .m
            .list_elem(self.ty_of(recv))
            .ok_or_else(|| Error::new("first or last on a non-list"))?;
        Ok(Some((
            present,
            Entry::List {
                list: recv,
                index,
                ty,
            },
        )))
    }

    /// The entry's value, a borrow. Emitted where `present` holds.
    pub(crate) fn lent_payload(&mut self, entry: &Entry) -> Value {
        match entry {
            Entry::Map { ptr, ty } => self
                .b
                .emit(Op::Load, &[*ptr], Imm::Ty(*ty), Some(*ty))
                .expect("load"),
            Entry::List { list, index, ty } => self
                .b
                .emit(Op::ListGetU, &[*list, *index], Imm::None, Some(*ty))
                .expect("list.get.u"),
        }
    }

    /// The read as a lent `Optional`: `opt.view` of the entry where present, else `opt.none`.
    pub(crate) fn lent_optional(&mut self, present: Value, entry: &Entry) -> Result<Val, Error> {
        let ty = entry.ty();
        let opt_ty = self.b.m.types.opt(ty);
        let lend = self.needs_drop(ty);
        self.two_ways_mode(
            present,
            opt_ty,
            Mode::Borrow,
            &mut |s| {
                let p = s.lent_payload(entry);
                Ok(Some(if lend {
                    s.b.opt_view(p)
                } else {
                    s.b.opt_some(p)
                }))
            },
            &mut |s| Ok(Some(s.b.opt_none(opt_ty))),
        )
    }
}
