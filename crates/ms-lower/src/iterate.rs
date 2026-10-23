//! Higher-order methods over lists, maps and sets that take a callback per item:
//! `fold`, `fold_right`, `find_last` on lists and every callback method of `Map` and `Set`.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::native::NArg;
use ms_mir::builder::Var;
use ms_mir::ir::{Cc, Imm, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::Expr;

/// What a loop walks over.
#[derive(Clone, Copy)]
enum Items {
    List(Var),
    /// A map or set variable and its type.
    Slots(Var, MTy),
}

type ItemBody<'a> = dyn FnMut(&mut FnLower<'_>, &[Value]) -> Result<Option<Value>, Error> + 'a;

/// The language-level method name behind the native's name (`map_transform` is `Map.map`).
fn method(name: &str) -> &str {
    match name {
        "transform" => "map",
        "transform_keys" => "map_keys",
        other => other,
    }
}

/// Whether the method is handled here for a receiver of this shape.
pub(crate) fn handles(m: &ms_mir::ir::Module, recv: MTy, name: &str) -> bool {
    let name = method(name);
    match m.types.kind(recv) {
        TyKind::List(_) => matches!(name, "fold" | "fold_right" | "find_last"),
        TyKind::Obj(n, _) if n == "Map" => matches!(
            name,
            "filter"
                | "map"
                | "map_keys"
                | "fold"
                | "fold_right"
                | "find"
                | "find_last"
                | "some"
                | "every"
                | "for_each"
        ),
        TyKind::Obj(n, _) if n == "Set" => matches!(
            name,
            "filter"
                | "map"
                | "fold"
                | "fold_right"
                | "find"
                | "find_last"
                | "some"
                | "every"
                | "for_each"
        ),
        _ => false,
    }
}

impl FnLower<'_> {
    /// Visits each item (a map's key and value, otherwise the element) in order, or backwards.
    /// A returned condition leaves the loop when true.
    fn each_item(
        &mut self,
        items: Items,
        reverse: bool,
        body: &mut ItemBody<'_>,
    ) -> Result<(), Error> {
        let count = match items {
            Items::List(lv) => {
                let l = self.b.use_var(lv);
                self.b.list_len(l)
            }
            Items::Slots(mv, _) => {
                let m = self.b.use_var(mv);
                self.call_runtime("msrt_map_slot_count", &[m], MTy::INT)?
            }
        };
        let idx = self.b.declare_var(MTy::INT, ms_mir::ir::Mode::Borrow);
        let one = self.b.iconst(1);
        let start = if reverse {
            self.b.binop(Op::ISub, count, one)
        } else {
            self.b.iconst(0)
        };
        self.b.def_var(idx, start);
        let (header, step, next, exit) = (
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
            self.b.new_block(),
        );
        self.b.br(header, &[]);
        self.b.switch_to(header);
        let i = self.b.use_var(idx);
        let more = if reverse {
            let zero = self.b.iconst(0);
            self.b.icmp(Cc::Ge, i, zero)
        } else {
            self.b.icmp(Cc::Lt, i, count)
        };
        self.b.br_if(more, step, &[], exit, &[]);
        self.b.seal_block(step);
        self.b.switch_to(step);
        let i = self.b.use_var(idx);
        match items {
            Items::List(lv) => {
                let l = self.b.use_var(lv);
                let x = self.b.list_get(l, i);
                let stop = body(self, &[x])?;
                self.leave_item(stop, exit, next);
            }
            Items::Slots(mv, mt) => {
                let TyKind::Obj(name, a) = self.b.m.types.kind(mt).clone() else {
                    return Err(Error::new("not a map or set"));
                };
                let is_map = name == "Map";
                let m = self.b.use_var(mv);
                let kd = self.type_desc(a[0]);
                let vd = match a.get(1) {
                    Some(v) => self.type_desc(*v),
                    // A set is a map without a value descriptor: a null pointer.
                    None => self.b.iconst(0),
                };
                let slot = |s: &mut Self| {
                    s.b.emit(Op::Slot, &[], Imm::Ty(MTy::PTR), Some(MTy::PTR))
                        .expect("slot")
                };
                let (kp, vp) = (slot(self), slot(self));
                let live =
                    self.call_runtime("msrt_map_entry_ptrs", &[m, kd, vd, i, kp, vp], MTy::BOOL)?;
                let take = self.b.new_block();
                self.b.br_if(live, take, &[], next, &[]);
                self.b.seal_block(take);
                self.b.switch_to(take);
                let load = |s: &mut Self, p: Value, t: MTy| {
                    let addr =
                        s.b.emit(Op::Load, &[p], Imm::Ty(MTy::PTR), Some(MTy::PTR))
                            .expect("load");
                    s.b.emit(Op::Load, &[addr], Imm::Ty(t), Some(t))
                        .expect("load")
                };
                let mut xs = vec![load(self, kp, a[0])];
                if is_map {
                    xs.push(load(self, vp, a[1]));
                }
                let stop = body(self, &xs)?;
                self.leave_item(stop, exit, next);
            }
        }
        // `next` has the predecessors recorded above.
        self.b.seal_block(next);
        self.b.switch_to(next);
        let i = self.b.use_var(idx);
        let one = self.b.iconst(1);
        let moved = if reverse {
            self.b.binop(Op::ISub, i, one)
        } else {
            self.b.binop(Op::IAdd, i, one)
        };
        self.b.def_var(idx, moved);
        self.b.br(header, &[]);
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        Ok(())
    }

    fn leave_item(
        &mut self,
        stop: Option<Value>,
        exit: ms_mir::ir::Block,
        next: ms_mir::ir::Block,
    ) {
        match stop {
            Some(s) => self.b.br_if(s, exit, &[], next, &[]),
            None => self.b.br(next, &[]),
        }
    }

    /// `fold`, `fold_right`, `find`, `find_last`, `filter`, `map` and `map_keys` over the receiver.
    pub(crate) fn iterate_method(
        &mut self,
        out: MTy,
        name: &str,
        recv_expr: Option<&Expr>,
        recv: Val,
        args: Vec<NArg>,
    ) -> Result<Val, Error> {
        let name = method(name);
        let rty = self.ty_of(recv.v);
        let callback = |want: &str| args.iter().find(|a| a.name.as_str() == want).copied();
        let f = match name {
            "fold" | "fold_right" => callback("step"),
            _ => args.iter().find(|a| self.is_fn_value(a.val.v)).copied(),
        }
        .ok_or_else(|| Error::new("missing function argument"))?;
        let ft = self.ty_of(f.val.v);
        let fvar = self.fresh_var(ft);
        let fo = self.owned(f.val);
        self.b.def_var(fvar, fo);
        let (sv, hidden) = self.list_source(recv_expr, recv)?;
        let items = match self.b.m.types.kind(rty) {
            TyKind::List(_) => Items::List(sv),
            _ => Items::Slots(sv, rty),
        };
        let is_set = matches!(self.b.m.types.kind(rty), TyKind::Obj(n, _) if n == "Set");
        let result = match name {
            "fold" | "fold_right" => {
                let init = callback("initial").ok_or_else(|| Error::new("fold without initial"))?;
                let acc_ty = out;
                let acc = self.fresh_var(acc_ty);
                let init = self.owned(init.val);
                self.b.def_var(acc, init);
                self.each_item(items, name == "fold_right", &mut |s, xs| {
                    let f = s.b.use_var(fvar);
                    let cur = s.b.use_var(acc);
                    let mut call = vec![cur];
                    call.extend_from_slice(xs);
                    let r = s.b.call_ind(f, &call);
                    s.drop_value(cur);
                    s.b.def_var(acc, r);
                    Ok(None)
                })?;
                Val {
                    v: self.b.use_var(acc),
                    own: true,
                }
            }
            "some" | "every" => {
                let some = name == "some";
                let acc = self.b.declare_var(MTy::BOOL, ms_mir::ir::Mode::Borrow);
                let init = self.b.bconst(!some);
                self.b.def_var(acc, init);
                self.each_item(items, false, &mut |s, xs| {
                    let f = s.b.use_var(fvar);
                    let r = s.b.call_ind(f, xs);
                    let hit = if some { r } else { s.b.unop(Op::Not, r) };
                    let t = s.b.bconst(some);
                    let cur = s.b.use_var(acc);
                    let next = s.b.select(hit, t, cur);
                    s.b.def_var(acc, next);
                    Ok(Some(hit))
                })?;
                Val {
                    v: self.b.use_var(acc),
                    own: false,
                }
            }
            "for_each" => {
                self.each_item(items, false, &mut |s, xs| {
                    let f = s.b.use_var(fvar);
                    s.b.call_ind(f, xs);
                    Ok(None)
                })?;
                Val {
                    v: self.b.unit(),
                    own: false,
                }
            }
            "find" | "find_last" => {
                let acc = self.fresh_var(out);
                let none = self.none_owned(out);
                self.b.def_var(acc, none);
                let TyKind::Opt(inner) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("find without an optional result"));
                };
                self.each_item(items, name == "find_last", &mut |s, xs| {
                    let f = s.b.use_var(fvar);
                    let r = s.b.call_ind(f, xs);
                    let (keep, skip) = (s.b.new_block(), s.b.new_block());
                    s.b.br_if(r, keep, &[], skip, &[]);
                    s.b.seal_block(keep);
                    s.b.seal_block(skip);
                    s.b.switch_to(keep);
                    let owned: Vec<Value> = xs
                        .iter()
                        .map(|x| s.owned(Val { v: *x, own: false }))
                        .collect();
                    let item = match s.b.m.types.kind(inner).clone() {
                        TyKind::Rec(rid) if xs.len() == 2 => s.b.rec_new(rid, &owned),
                        _ => owned[0],
                    };
                    let found = s.b.opt_some(item);
                    let old = s.b.use_var(acc);
                    s.drop_value(old);
                    s.b.def_var(acc, found);
                    s.b.br(skip, &[]);
                    s.b.switch_to(skip);
                    Ok(Some(r))
                })?;
                Val {
                    v: self.b.use_var(acc),
                    own: true,
                }
            }
            "filter" | "map" | "map_keys" => {
                let by_list = is_set;
                let list_ty = if by_list {
                    let elem = match self.b.m.types.kind(out).clone() {
                        TyKind::Obj(_, a) => a[0],
                        _ => return Err(Error::new("set result expected")),
                    };
                    Some(self.b.m.types.list(elem))
                } else {
                    None
                };
                let acc_ty = list_ty.unwrap_or(out);
                let acc = self.fresh_var(acc_ty);
                let first = match list_ty {
                    Some(lt) => {
                        let TyKind::List(elem) = self.b.m.types.kind(lt).clone() else {
                            unreachable!()
                        };
                        self.b.list_lit(elem, &[])
                    }
                    None => self.map_new(out)?,
                };
                self.b.def_var(acc, first);
                self.each_item(items, false, &mut |s, xs| {
                    let f = s.b.use_var(fvar);
                    let r = s.b.call_ind(f, xs);
                    let add = |s: &mut FnLower<'_>, key: Value, value: Option<Value>| {
                        let cur = s.b.use_var(acc);
                        let next = match value {
                            Some(v) => s.map_insert(cur, key, v)?,
                            None => s.b.list_push(cur, key),
                        };
                        s.b.def_var(acc, next);
                        Ok::<(), Error>(())
                    };
                    let own = |s: &mut FnLower<'_>, x: Value| s.owned(Val { v: x, own: false });
                    if name == "filter" {
                        let (keep, skip) = (s.b.new_block(), s.b.new_block());
                        s.b.br_if(r, keep, &[], skip, &[]);
                        s.b.seal_block(keep);
                        s.b.seal_block(skip);
                        s.b.switch_to(keep);
                        let k = own(s, xs[0]);
                        let v = xs.get(1).map(|v| own(s, *v));
                        add(s, k, v)?;
                        s.b.br(skip, &[]);
                        s.b.switch_to(skip);
                    } else if by_list {
                        add(s, r, None)?;
                    } else if name == "map" {
                        let k = own(s, xs[0]);
                        add(s, k, Some(r))?;
                    } else {
                        let v = own(s, xs[1]);
                        add(s, r, Some(v))?;
                    }
                    Ok(None)
                })?;
                let built = self.b.use_var(acc);
                if by_list {
                    let list = Val {
                        v: built,
                        own: true,
                    };
                    self.set_from_list(list, out)?
                } else {
                    Val {
                        v: built,
                        own: true,
                    }
                }
            }
            other => return Err(Error::new(format!("unsupported collection method {other}"))),
        };
        self.release_source(sv, hidden);
        self.release_source(fvar, true);
        Ok(result)
    }
}
