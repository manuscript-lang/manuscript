//! In-place list mutation, counted loops and higher-order list operations.

use super::*;

impl<'a> FnLower<'a> {
    /// An incoming resource remains in its cleanup slot until the leaf mutator succeeds.
    pub(super) fn guarded_list_mutation(
        &mut self,
        name: &str,
        old: Value,
        args: &[NArg],
    ) -> Result<Option<(Value, Option<Val>)>, Error> {
        let lt = self.ty_of(old);
        let TyKind::List(elem) = self.b.m.types.kind(lt).clone() else {
            return Ok(None);
        };
        let index = match name {
            "append" | "prepend" => 0,
            "insert" | "set" | "replace" => 1,
            _ => return Ok(None),
        };
        let Some(arg) = args.get(index) else {
            return Ok(None);
        };
        let Some(incoming) = self.resource_temp_slot(arg.val.v) else {
            return Ok(None);
        };
        let list = self.put_slot(old);
        let result = self.guarded_list_slot(name, list, elem, (incoming, Some(arg.val.v)), args)?;
        let new = self.take_slot(list, lt);
        Ok(Some((new, result)))
    }

    /// Runtime validation precedes consumption of `incoming`; success hands it to `list`.
    pub(super) fn guarded_list_slot(
        &mut self,
        name: &str,
        list: Value,
        elem: MTy,
        incoming: (Value, Option<Value>),
        args: &[NArg],
    ) -> Result<Option<Val>, Error> {
        let (incoming, key) = incoming;
        let d = self.type_desc(elem);
        let mut outgoing = None;
        match name {
            "append" => {
                self.call_runtime("msrt_list_push", &[list, d, incoming], MTy::UNIT)?;
            }
            "prepend" | "insert" => {
                let i = if name == "prepend" {
                    self.b.iconst(0)
                } else {
                    self.borrow(args[0].val)
                };
                self.call_runtime("msrt_list_insert", &[list, d, i, incoming], MTy::UNIT)?;
            }
            "set" | "replace" => {
                let i = self.borrow(args[0].val);
                if name == "set" {
                    let list_ty = self.b.m.types.list(elem);
                    let header = self
                        .b
                        .emit(
                            ms_mir::ir::Op::Load,
                            &[list],
                            ms_mir::ir::Imm::Ty(list_ty),
                            Some(list_ty),
                        )
                        .expect("list header");
                    let n = self.b.list_len(header);
                    let zero = self.b.iconst(0);
                    let neg = self.b.icmp(ms_mir::ir::Cc::Lt, i, zero);
                    let shifted = self.b.binop(ms_mir::ir::Op::IAdd, i, n);
                    let resolved = self.b.select(neg, shifted, i);
                    self.check_index(2, i, resolved, n, false);
                }
                let out = self
                    .b
                    .emit(
                        ms_mir::ir::Op::Slot,
                        &[],
                        ms_mir::ir::Imm::Ty(elem),
                        Some(MTy::PTR),
                    )
                    .expect("outgoing list element");
                // Unlike set's descriptor drop, replace cannot invoke a capture closer before
                // the incoming slot is consumed. The detached old storage is dropped below.
                self.call_runtime("msrt_list_replace", &[list, d, i, incoming, out], MTy::UNIT)?;
                outgoing = Some(out);
            }
            _ => unreachable!("guarded list mutator"),
        }
        if let Some(key) = key {
            self.retire_consumed_resource_temp(key);
        }
        let result = outgoing.map(|out| Val {
            v: self.take_slot(out, elem),
            own: true,
        });
        if name == "set" {
            if let Some(old) = result {
                self.drop_value(old.v);
            }
            return Ok(None);
        }
        Ok(result)
    }

    /// `(new list, result)` of a list mutator applied to the owned `old` list.
    pub(super) fn mutate_list(
        &mut self,
        name: &str,
        old: Value,
        args: &[NArg],
    ) -> Result<(Value, Option<Val>), Error> {
        use ms_mir::ir::{Cc, Op};
        let lt = self.ty_of(old);
        let TyKind::List(elem) = self.b.m.types.kind(lt).clone() else {
            return Err(Error::new("list mutator on a non-list"));
        };
        let d = self.type_desc(elem);
        match name {
            "append" => {
                let v = self.element_value(&args[0]);
                Ok((self.b.list_push(old, v), None))
            }
            "set" => {
                let i = self.borrow(args[0].val);
                let n = self.b.list_len(old);
                let zero = self.b.iconst(0);
                let neg = self.b.icmp(Cc::Lt, i, zero);
                let shifted = self.b.binop(Op::IAdd, i, n);
                let r = self.b.select(neg, shifted, i);
                self.check_index(2, i, r, n, false);
                let v = self.element_value(&args[1]);
                if !self.b.m.needs_drop(elem) {
                    return Ok((self.b.list_set(old, i, v), None));
                }
                // Dropping the old element can run a capture close that faults: move it out and
                // the new one in first, so the list stays an owned value the unwinder releases.
                let (old_element, moved) = self.list_elem_at(old, r)?;
                let new = if moved {
                    self.b.list_fill(old, r, v)
                } else {
                    self.b.list_set(old, r, v)
                };
                self.drop_value(old_element);
                Ok((new, None))
            }
            "swap" => {
                let n = self.b.list_len(old);
                let zero = self.b.iconst(0);
                let mut at = [old; 2];
                let mut got = [old; 2];
                for (k, a) in args.iter().enumerate().take(2) {
                    let i = self.borrow(a.val);
                    let neg = self.b.icmp(Cc::Lt, i, zero);
                    let shifted = self.b.binop(Op::IAdd, i, n);
                    let r = self.b.select(neg, shifted, i);
                    self.check_index(3, i, r, n, false);
                    at[k] = r;
                    got[k] = self.b.list_get(old, r);
                }
                let first = self.b.list_set(old, at[0], got[1]);
                Ok((self.b.list_set(first, at[1], got[0]), None))
            }
            "replace" => {
                // The element moves out in line and the new value moves in; nothing is copied or dropped.
                let idx = self.borrow(args[0].val);
                // Checked before the incoming element is stored, so a fault leaves it registered.
                let n = self.b.list_len(old);
                let zero = self.b.iconst(0);
                let neg = self.b.icmp(Cc::Lt, idx, zero);
                let shifted = self.b.binop(Op::IAdd, idx, n);
                let r = self.b.select(neg, shifted, idx);
                self.check_index(4, idx, r, n, false);
                let v = self.element_value(&args[1]);
                let (old_element, moved) = self.list_elem_at(old, r)?;
                let new = if moved {
                    self.b.list_fill(old, r, v)
                } else {
                    self.b.list_set(old, r, v)
                };
                Ok((
                    new,
                    Some(Val {
                        v: old_element,
                        own: true,
                    }),
                ))
            }
            "prepend" | "insert" | "remove" => {
                let n = self.b.list_len(old);
                let (idx, item) = match name {
                    "prepend" => (self.b.iconst(0), Some(&args[0])),
                    "insert" => (self.borrow(args[0].val), Some(&args[1])),
                    _ => (self.borrow(args[0].val), None),
                };
                let zero = self.b.iconst(0);
                let neg = self.b.icmp(Cc::Lt, idx, zero);
                let shifted = self.b.binop(Op::IAdd, idx, n);
                let i = self.b.select(neg, shifted, idx);
                if name != "prepend" {
                    self.check_index(
                        if item.is_some() { 0 } else { 1 },
                        idx,
                        i,
                        n,
                        item.is_some(),
                    );
                }
                // Shifts the tail in place; the runtime consumes the incoming slot or drops the removed one.
                let incoming = item.map(|x| {
                    let xo = self.element_value(x);
                    self.put_slot(xo)
                });
                let list = self.put_slot(old);
                match incoming {
                    Some(incoming) => {
                        self.call_runtime("msrt_list_insert", &[list, d, idx, incoming], MTy::UNIT)?
                    }
                    None => self.call_runtime("msrt_list_remove", &[list, d, idx], MTy::UNIT)?,
                };
                Ok((self.take_slot(list, lt), None))
            }
            "pop" => {
                let optty = self.b.m.types.opt(elem);
                let n = self.b.list_len(old);
                let zero = self.b.iconst(0);
                let empty = self.b.icmp(Cc::Eq, n, zero);
                let res = self.fresh_var(optty);
                let acc = self.fresh_var(lt);
                self.b.def_var(acc, old);
                let none = self.none_owned(optty);
                self.b.def_var(res, none);
                let (take, join) = (self.b.new_block(), self.b.new_block());
                self.b.br_if(empty, join, &[], take, &[]);
                self.b.seal_block(take);
                self.b.switch_to(take);
                let cur = self.b.use_var(acc);
                let one = self.b.iconst(1);
                let last = self.b.binop(Op::ISub, n, one);
                // The element moves out of the list; the list is shortened past it.
                let xo = self.b.list_take(cur, last);
                let some = self.b.opt_some(xo);
                let placeholder = self.b.use_var(res);
                self.drop_value(placeholder);
                self.b.def_var(res, some);
                let rest = self.b.list_drop_last_taken(cur);
                self.b.def_var(acc, rest);
                self.b.br(join, &[]);
                self.b.seal_block(join);
                self.b.switch_to(join);
                let r = self.b.use_var(res);
                let l = self.b.use_var(acc);
                Ok((l, Some(Val { v: r, own: true })))
            }
            "sort" => {
                let f = args
                    .iter()
                    .find(|a| self.is_fn(a.val.v))
                    .ok_or_else(|| Error::new("sort without comparator"))?;
                let ft = self.ty_of(f.val.v);
                let fvar = self.fresh_var(ft);
                let fo = self.owned(f.val);
                self.b.def_var(fvar, fo);
                let var = self.fresh_var(lt);
                self.b.def_var(var, old);
                let r = self.list_sorted(var, fvar, elem)?;
                let o = self.b.use_var(var);
                self.drop_value(o);
                self.release_source(fvar, true);
                Ok((r.v, None))
            }
            "reverse" => {
                let var = self.fresh_var(lt);
                self.b.def_var(var, old);
                let r = self.list_reversed(var, elem)?;
                let o = self.b.use_var(var);
                self.drop_value(o);
                Ok((r.v, None))
            }
            _ => Err(Error::new(format!("unsupported list mutator {name}"))),
        }
    }

    pub(crate) fn is_fn_value(&self, v: Value) -> bool {
        self.is_fn(v)
    }

    pub(super) fn is_fn(&self, v: Value) -> bool {
        matches!(self.b.m.types.kind(self.ty_of(v)), TyKind::Fn(..))
    }

    /// A fresh SSA variable owning or borrowing per the type.
    pub(crate) fn fresh_var(&mut self, t: MTy) -> ms_mir::builder::Var {
        let owned = self.needs_drop(t);
        self.b
            .declare_var(t, if owned { Mode::Move } else { Mode::Borrow })
    }

    /// Runs `body(i)` for `i` in `from..n`; `from` and `n` are `Int` values.
    pub(crate) fn counted_loop(
        &mut self,
        from: Value,
        n: Value,
        body: &mut dyn FnMut(&mut Self, Value) -> Result<(), Error>,
    ) -> Result<(), Error> {
        let idx = self.b.declare_var(MTy::INT, Mode::Borrow);
        self.b.def_var(idx, from);
        let (head, step, exit) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(head, &[]);
        self.b.switch_to(head);
        let i = self.b.use_var(idx);
        let more = self.b.icmp(ms_mir::ir::Cc::Lt, i, n);
        self.b.br_if(more, step, &[], exit, &[]);
        self.b.seal_block(step);
        self.b.switch_to(step);
        let i = self.b.use_var(idx);
        body(self, i)?;
        let one = self.b.iconst(1);
        let i = self.b.use_var(idx);
        let next = self.b.binop(ms_mir::ir::Op::IAdd, i, one);
        self.b.def_var(idx, next);
        self.b.br(head, &[]);
        self.b.seal_block(head);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        Ok(())
    }

    /// Visits each element with `body(index, element)`; a returned condition leaves the loop when true.
    pub(crate) fn each_element(
        &mut self,
        lv: ms_mir::builder::Var,
        body: &mut ElementBody<'_, Self>,
    ) -> Result<(), Error> {
        self.each_element_at(lv, false, body)
    }

    /// `each_element`, handing the body each element's address when `by_address` (a callback
    /// that takes it as `var` changes it in place).
    pub(super) fn each_element_at(
        &mut self,
        lv: ms_mir::builder::Var,
        by_address: bool,
        body: &mut ElementBody<'_, Self>,
    ) -> Result<(), Error> {
        let l = self.b.use_var(lv);
        let n = self.b.list_len(l);
        let idx = self.b.declare_var(MTy::INT, Mode::Borrow);
        let zero = self.b.iconst(0);
        self.b.def_var(idx, zero);
        let (header, step, exit) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(header, &[]);
        self.b.switch_to(header);
        let i = self.b.use_var(idx);
        let c = self.b.icmp(ms_mir::ir::Cc::Lt, i, n);
        self.b.br_if(c, step, &[], exit, &[]);
        self.b.seal_block(step);
        self.b.switch_to(step);
        let i = self.b.use_var(idx);
        let l = self.b.use_var(lv);
        let x = if by_address {
            self.b
                .emit(
                    ms_mir::ir::Op::ListAddrU,
                    &[l, i],
                    ms_mir::ir::Imm::None,
                    Some(MTy::PTR),
                )
                .expect("element address")
        } else {
            self.b.list_get(l, i)
        };
        let stop = body(self, i, x)?;
        let one = self.b.iconst(1);
        let i = self.b.use_var(idx);
        let next = self.b.binop(ms_mir::ir::Op::IAdd, i, one);
        self.b.def_var(idx, next);
        match stop {
            Some(s) => {
                self.b.br_if(s, exit, &[], header, &[]);
            }
            None => self.b.br(header, &[]),
        }
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        Ok(())
    }

    pub(super) fn list_higher_order(
        &mut self,
        name: &str,
        lv: ms_mir::builder::Var,
        elem: MTy,
        fvar: ms_mir::builder::Var,
        by_address: bool,
        out: MTy,
    ) -> Result<Val, Error> {
        let l = self.b.use_var(lv);
        match name {
            "map" | "filter" => {
                let n = self.b.list_len(l);
                let res_elem = match self.b.m.types.kind(out).clone() {
                    TyKind::List(t) => t,
                    _ => return Err(Error::new("map without list result")),
                };
                let zero = self.b.iconst(0);
                let first = self
                    .b
                    .list_new(res_elem, if name == "map" { n } else { zero });
                let acc = self.fresh_var(out);
                self.b.def_var(acc, first);
                let is_map = name == "map";
                self.each_element(lv, &mut |s, _, x| {
                    let r = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    if is_map {
                        let cur = s.b.use_var(acc);
                        let next = s.b.list_push(cur, r);
                        s.b.def_var(acc, next);
                        return Ok(None);
                    }
                    let (keep, skip) = (s.b.new_block(), s.b.new_block());
                    s.b.br_if(r, keep, &[], skip, &[]);
                    s.b.seal_block(keep);
                    s.b.seal_block(skip);
                    s.b.switch_to(keep);
                    let xo = s.owned_boundary(Val { v: x, own: false });
                    let cur = s.b.use_var(acc);
                    let next = s.b.list_push(cur, xo);
                    s.b.def_var(acc, next);
                    s.b.br(skip, &[]);
                    s.b.switch_to(skip);
                    Ok(None)
                })?;
                let r = self.b.use_var(acc);
                Ok(Val { v: r, own: true })
            }
            "partition" => {
                let TyKind::Type(rid) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("partition without a type result"));
                };
                let lt = self.b.m.type_defs[rid.index()].fields[0].1;
                let zero = self.b.iconst(0);
                let (yes, no) = (self.fresh_var(lt), self.fresh_var(lt));
                for v in [yes, no] {
                    let first = self.b.list_new(elem, zero);
                    self.b.def_var(v, first);
                }
                self.each_element(lv, &mut |s, _, x| {
                    let r = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    let (hit, miss, join) = (s.b.new_block(), s.b.new_block(), s.b.new_block());
                    s.b.br_if(r, hit, &[], miss, &[]);
                    s.b.seal_block(hit);
                    s.b.seal_block(miss);
                    for (blk, acc) in [(hit, yes), (miss, no)] {
                        s.b.switch_to(blk);
                        let xo = s.owned_boundary(Val { v: x, own: false });
                        let cur = s.b.use_var(acc);
                        let next = s.b.list_push(cur, xo);
                        s.b.def_var(acc, next);
                        s.b.br(join, &[]);
                    }
                    s.b.seal_block(join);
                    s.b.switch_to(join);
                    Ok(None)
                })?;
                let (a, b) = (self.b.use_var(yes), self.b.use_var(no));
                let tval = self.b.type_new(rid, &[a, b]);
                Ok(Val { v: tval, own: true })
            }
            "flat_map" => {
                let TyKind::List(res_elem) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("flat_map without list result"));
                };
                let zero = self.b.iconst(0);
                let first = self.b.list_new(res_elem, zero);
                let acc = self.fresh_var(out);
                self.b.def_var(acc, first);
                self.each_element(lv, &mut |s, _, x| {
                    let r = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    let rt = s.ty_of(r);
                    let rv = s.fresh_var(rt);
                    s.b.def_var(rv, r);
                    s.each_element(rv, &mut |s, _, y| {
                        let yo = s.clone_value(y);
                        let cur = s.b.use_var(acc);
                        let next = s.b.list_push(cur, yo);
                        s.b.def_var(acc, next);
                        Ok(None)
                    })?;
                    let done = s.b.use_var(rv);
                    s.drop_value(done);
                    Ok(None)
                })?;
                Ok(Val {
                    v: self.b.use_var(acc),
                    own: true,
                })
            }
            "group_by" => {
                let TyKind::Obj(_, parts) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("group_by without a map result"));
                };
                let group_ty = parts[1];
                let first = self.map_new(out)?;
                let acc = self.fresh_var(out);
                self.b.def_var(acc, first);
                self.each_element(lv, &mut |s, _, x| {
                    let k = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    let (kd, vd) = s.map_descs(out)?;
                    let vd = vd.ok_or_else(|| Error::new("group_by without a value type"))?;
                    // The lookup only reads the key, so it borrows the key itself.
                    let kslot = s.borrow_slot(k);
                    let m = s.b.use_var(acc);
                    let sym = s
                        .word_map_symbol("msrt_map_get_ptr", out)
                        .unwrap_or("msrt_map_get_ptr");
                    let found = s.call_runtime(sym, &[m, kd, vd, kslot], MTy::PTR)?;
                    let missing =
                        s.b.emit(
                            ms_mir::ir::Op::PtrIsNull,
                            &[found],
                            ms_mir::ir::Imm::None,
                            Some(MTy::BOOL),
                        )
                        .expect("is_null");
                    let TyKind::List(group_elem) = s.b.m.types.kind(group_ty).clone() else {
                        return Err(Error::new("group_by without list groups"));
                    };
                    // A present group is taken out of its entry, grown and put back where it
                    // lies, so a bucket is never copied; an absent one starts as `[x]`.
                    let cur = s.b.use_var(acc);
                    let next = s
                        .two_ways(
                            missing,
                            out,
                            &mut |s| {
                                let empty = s.b.list_lit(group_elem, &[]);
                                let xo = s.owned_boundary(Val { v: x, own: false });
                                let grown = s.b.list_push(empty, xo);
                                let next = s.map_insert(cur, k, grown)?;
                                Ok(Some(next))
                            },
                            &mut |s| {
                                let taken =
                                    s.b.emit(
                                        ms_mir::ir::Op::Take,
                                        &[found],
                                        ms_mir::ir::Imm::Ty(group_ty),
                                        Some(group_ty),
                                    )
                                    .expect("take");
                                let xo = s.owned_boundary(Val { v: x, own: false });
                                let grown = s.b.list_push(taken, xo);
                                s.b.emit(
                                    ms_mir::ir::Op::Put,
                                    &[found, grown],
                                    ms_mir::ir::Imm::None,
                                    None,
                                );
                                s.drop_value(k);
                                Ok(Some(cur))
                            },
                        )?
                        .v;
                    s.b.def_var(acc, next);
                    Ok(None)
                })?;
                Ok(Val {
                    v: self.b.use_var(acc),
                    own: true,
                })
            }
            "count" => {
                let acc = self.b.declare_var(MTy::INT, Mode::Borrow);
                let z = self.b.iconst(0);
                self.b.def_var(acc, z);
                self.each_element(lv, &mut |s, _, x| {
                    let r = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    let cur = s.b.use_var(acc);
                    let one = s.b.iconst(1);
                    let zero = s.b.iconst(0);
                    let inc = s.b.select(r, one, zero);
                    let next = s.b.binop(ms_mir::ir::Op::IAdd, cur, inc);
                    s.b.def_var(acc, next);
                    Ok(None)
                })?;
                Ok(Val {
                    v: self.b.use_var(acc),
                    own: false,
                })
            }
            "any" | "all" => {
                let some = name == "any";
                let acc = self.b.declare_var(MTy::BOOL, Mode::Borrow);
                let init = self.b.bconst(!some);
                self.b.def_var(acc, init);
                self.each_element(lv, &mut |s, _, x| {
                    let r = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    let hit = if some {
                        r
                    } else {
                        s.b.unop(ms_mir::ir::Op::Not, r)
                    };
                    let t = s.b.bconst(some);
                    let cur = s.b.use_var(acc);
                    let next = s.b.select(hit, t, cur);
                    s.b.def_var(acc, next);
                    Ok(Some(hit))
                })?;
                Ok(Val {
                    v: self.b.use_var(acc),
                    own: false,
                })
            }
            "for_each" => {
                // The callback takes each element as `var`: it gets the element's address (the
                // list is not copied), and a callback that changes it does so in place.
                self.each_element_at(lv, by_address, &mut |s, _, p| {
                    let f = s.b.use_var(fvar);
                    s.b.call_ind(f, &[p]);
                    Ok(None)
                })?;
                let u = self.b.unit();
                Ok(Val { v: u, own: false })
            }
            "find" | "find_index" | "find_last_index" => {
                let by_index = name != "find";
                // The last match wins: keep scanning past hits.
                let last = name == "find_last_index";
                let acc = self.fresh_var(out);
                let none = self.none_owned(out);
                self.b.def_var(acc, none);
                self.each_element(lv, &mut |s, i, x| {
                    let r = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    let (hit, miss) = (s.b.new_block(), s.b.new_block());
                    s.b.br_if(r, hit, &[], miss, &[]);
                    s.b.seal_block(hit);
                    s.b.seal_block(miss);
                    s.b.switch_to(hit);
                    let payload = if by_index {
                        i
                    } else {
                        s.owned_boundary(Val { v: x, own: false })
                    };
                    let some = s.b.opt_some(payload);
                    let old = s.b.use_var(acc);
                    s.drop_value(old);
                    s.b.def_var(acc, some);
                    s.b.br(miss, &[]);
                    s.b.switch_to(miss);
                    // The last hit wins, so `find_last_index` visits every element.
                    Ok((!last).then_some(r))
                })?;
                Ok(Val {
                    v: self.b.use_var(acc),
                    own: true,
                })
            }
            _ => Err(Error::new(format!(
                "unsupported list method {name} ({elem:?})"
            ))),
        }
    }
}
