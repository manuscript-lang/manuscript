//! Shared native calls, list sources and sorting, and collection mutators with their cleanup.

use super::*;

impl<'a> FnLower<'a> {
    /// A collection mutator applied in place to the variable at `slot`, for a method value
    /// that shares its receiver.
    pub(crate) fn shared_native_call(
        &mut self,
        m: &ct::MethodRef,
        slot: Value,
        rty: MTy,
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let name = m
            .name()
            .map(|n| self.syms.str(n).to_string())
            .unwrap_or_default();
        let old = self.move_out(slot, rty);
        let (new, r) = self.mutate_any(&name, old, &m.ty.params, args, true, result)?;
        self.move_into(slot, new);
        if result == MTy::UNIT {
            if let Some(r) = r.filter(|r| r.own) {
                self.drop_value(r.v);
            }
            return Ok(Val {
                v: self.b.unit(),
                own: false,
            });
        }
        r.ok_or_else(|| Error::new("a collection mutator without a result"))
    }

    /// A native method applied to evaluated arguments, for method values.
    pub(crate) fn bound_native_call(
        &mut self,
        m: &ct::MethodRef,
        recv: Val,
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let rty = self.ty_of(recv.v);
        let name = m
            .name()
            .map(|n| self.syms.str(n).to_string())
            .unwrap_or_default();
        if let Some(&(_, sym, param, as_text)) = FORMAT_METHODS
            .iter()
            .find(|(n, ..)| *n == m.native.text(self.syms))
        {
            return self.format_method(result, m, recv, args.to_vec(), (sym, param, as_text));
        }
        if ms_check::api::ownership::collection_mutation(self.syms, m) {
            // The bound receiver is a copy: the mutated collection is the result.
            let b = self.borrow(recv);
            let old = self.owned_boundary(Val { v: b, own: false });
            let (new, r) = self.mutate_any(&name, old, &m.ty.params, args, true, result)?;
            if result == MTy::UNIT {
                self.drop_value(new);
                if let Some(r) = r.filter(|r| r.own) {
                    self.drop_value(r.v);
                }
                return Ok(Val {
                    v: self.b.unit(),
                    own: false,
                });
            }
            return Ok(match r {
                Some(r) => {
                    self.drop_value(new);
                    r
                }
                None => Val { v: new, own: true },
            });
        }
        if name == "clone" {
            let v = self.clone_value(recv.v);
            return Ok(Val { v, own: true });
        }
        if let (TyKind::Alt(a), "is_ok" | "is_error") =
            (self.b.m.types.kind(rty).clone(), name.as_str())
        {
            return self.result_state(&name, recv, a);
        }
        if let (
            TyKind::Alt(a),
            "get" | "err" | "get_or_else" | "or_else" | "map_error" | "map" | "and_then"
            | "to_optional" | "error",
        ) = (self.b.m.types.kind(rty).clone(), name.as_str())
        {
            return self.result_method(result, &name, recv, a, args.to_vec());
        }
        if let (TyKind::Opt(inner), true) = (self.b.m.types.kind(rty).clone(), opt_method(&name)) {
            let at = ms_check::api::Pos::default();
            return self.optional_method(result, at, &name, recv, inner, args.to_vec());
        }
        if let (TyKind::Obj(n, _), "get_or") = (self.b.m.types.kind(rty).clone(), name.as_str())
            && n == Native::Map
        {
            return self.map_get_or(recv, &m.ty.params, args, result);
        }
        if let (Some(elem), "get") = (self.b.m.seq_elem(rty), name.as_str()) {
            let find = |want: bool| {
                args.iter()
                    .find(|a| (self.syms.str(a.name) == "default") == want)
            };
            let index = find(false)
                .copied()
                .ok_or_else(|| Error::new("get without index"))?;
            return self.list_get_or(recv, elem, index, find(true).copied());
        }
        if crate::iterate::handles(self.b.m, rty, &name) {
            return self.iterate_method(result, &name, None, recv, args.to_vec());
        }
        if matches!(self.b.m.types.kind(rty), TyKind::List(_)) && is_higher_order(&name) {
            return self.list_higher(&name, result, None, recv, args.to_vec());
        }
        if let (TyKind::List(elem), "take" | "drop") =
            (self.b.m.types.kind(rty).clone(), name.as_str())
        {
            let sym = if name == "take" {
                "msrt_list_take"
            } else {
                "msrt_list_drop_n"
            };
            let d = self.type_desc(elem);
            let r = self.borrow(recv);
            let n = self.borrow(args[0].val);
            let out = self.call_runtime(sym, &[r, d, n], rty)?;
            return Ok(Val { v: out, own: true });
        }
        if m.native.is(self.syms, "hash") && !matches!(self.b.m.types.kind(rty), TyKind::Str) {
            return self.structural_hash(recv);
        }
        self.native_method_tail(
            m,
            None,
            ms_check::api::Pos::default(),
            result,
            recv,
            args.to_vec(),
        )
    }

    /// `equals` of data with built-in equality: the equality `==` selects, against another
    /// value of the same type.
    pub(super) fn equals_value(
        &mut self,
        _concrete: &ct::Ty,
        recv: Val,
        other: Val,
    ) -> Result<Val, Error> {
        let t = self.ty_of(recv.v);
        // `equal` borrows both operands, so owned temporaries are released with the statement.
        let v = self.equal(t, recv, other)?;
        Ok(Val { v, own: false })
    }

    /// A variable that always holds the receiver list, for use across loop headers.
    /// The flag says the variable is a hidden copy to drop afterwards.
    pub(crate) fn list_source(
        &mut self,
        recv_expr: Option<&Expr>,
        recv: Val,
    ) -> Result<(ms_mir::builder::Var, bool), Error> {
        // A local the expression moved out of (`recv.own`) is the caller's to drop: it is held
        // as a hidden copy below, not read in place.
        if !recv.own
            && let Some(Resolution::Local(b)) = recv_expr.map(|r| self.hir.resolution(r))
            && !self.aliases.contains_key(&b.uid)
            && self.local(&b)?.slot.is_none()
            && !self.local(&b)?.opt
        {
            return Ok((self.local(&b)?.var, false));
        }
        let t = self.ty_of(recv.v);
        if !recv.own {
            // A borrowed receiver stays borrowed across the loop: the owner cannot change while
            // the borrow lives, so no hidden copy is needed.
            let var = self.b.declare_var(t, Mode::Borrow);
            self.b.def_var(var, recv.v);
            return Ok((var, false));
        }
        let var = self.fresh_var(t);
        self.b.def_var(var, recv.v);
        Ok((var, true))
    }

    /// A variable holding the callback `f` for the loop a higher-order method runs: an owned
    /// callback (a lambda written in the call) is held and dropped afterwards (`true`); a
    /// borrowed one (a function value a local holds) is read in place, never copied.
    pub(crate) fn callback_var(&mut self, f: Val) -> (ms_mir::builder::Var, bool) {
        let ft = self.ty_of(f.v);
        let hidden = f.own && self.needs_drop(ft);
        let var = self
            .b
            .declare_var(ft, if hidden { Mode::Move } else { Mode::Borrow });
        self.b.def_var(var, f.v);
        (var, hidden)
    }

    pub(crate) fn release_source(&mut self, var: ms_mir::builder::Var, hidden: bool) {
        if hidden {
            let v = self.b.use_var(var);
            self.drop_value(v);
        }
    }

    /// `sorted(compare)`: a stable sort of a copy ordered by the comparator's sign.
    pub(super) fn list_sorted_call(
        &mut self,
        recv_expr: Option<&Expr>,
        recv: Val,
        elem: MTy,
        args: Vec<NArg>,
    ) -> Result<Val, Error> {
        let f = args
            .into_iter()
            .next()
            .ok_or_else(|| Error::new("sorted without comparator"))?;
        if !self.is_fn(f.val.v) {
            return Err(Error::new(
                "sorted takes a comparator function; omit compare to sort in natural order",
            ));
        }
        let (fvar, fhidden) = self.callback_var(f.val);
        let (lv, hidden) = self.list_source(recv_expr, recv)?;
        let r = self.list_sorted(lv, fvar, elem);
        self.release_source(lv, hidden);
        self.release_source(fvar, fhidden);
        r
    }

    /// The indexes of a list: `0..length`.
    pub(super) fn list_keys(
        &mut self,
        recv_expr: Option<&Expr>,
        recv: Val,
        result: MTy,
    ) -> Result<Val, Error> {
        let (lv, hidden) = self.list_source(recv_expr, recv)?;
        let n = {
            let l = self.b.use_var(lv);
            self.b.list_len(l)
        };
        let acc = self.fresh_var(result);
        let first = self.b.list_new(MTy::INT, n);
        self.b.def_var(acc, first);
        self.each_element(lv, &mut |s, i, _| {
            let cur = s.b.use_var(acc);
            let next = s.b.list_push(cur, i);
            s.b.def_var(acc, next);
            Ok(None)
        })?;
        self.release_source(lv, hidden);
        let out = self.b.use_var(acc);
        Ok(Val { v: out, own: true })
    }

    /// `chunks(size)` (steps by `size`, keeps a short tail) or `windows(size)` (steps by one).
    pub(super) fn list_pieces(
        &mut self,
        chunks: bool,
        elem: MTy,
        recv: Val,
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::List(inner) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("pieces without a list result"));
        };
        let d = self.type_desc(elem);
        let od = self.type_desc(inner);
        let r = self.borrow(recv);
        let size = self.borrow(args[0].val);
        let step = if chunks { size } else { self.b.iconst(1) };
        let short = self.b.bconst(chunks);
        let out = self.call_runtime("msrt_list_pieces", &[r, d, od, size, step, short], result)?;
        Ok(Val { v: out, own: true })
    }

    /// A stable merge sort of a copy (the runtime's), ordered by the comparator's sign.
    pub(super) fn list_sorted(
        &mut self,
        lv: ms_mir::builder::Var,
        fvar: ms_mir::builder::Var,
        elem: MTy,
    ) -> Result<Val, Error> {
        let l = self.b.use_var(lv);
        let f = self.b.use_var(fvar);
        let thunk = self.sort_thunk(elem, self.ty_of(f));
        let cmp = self
            .b
            .emit(
                ms_mir::ir::Op::FuncAddr,
                &[],
                ms_mir::ir::Imm::Func(thunk),
                Some(MTy::PTR),
            )
            .expect("func.addr");
        let d = self.type_desc(elem);
        let t = self.ty_of(l);
        let out = self.call_runtime("msrt_list_sorted", &[l, d, cmp, f], t)?;
        Ok(Val { v: out, own: true })
    }

    /// `fn(comparator, ptr, ptr) -> int` for the runtime sort: loads the two element slots and
    /// calls the source comparator on them.
    pub(super) fn sort_thunk(&mut self, elem: MTy, closure: MTy) -> ms_mir::ir::FuncId {
        let p = |ty| Param {
            ty,
            mode: Mode::Borrow,
        };
        let mut tb = ms_mir::builder::FuncBuilder::new(
            self.b.m,
            "sort.cmp",
            vec![p(closure), p(MTy::PTR), p(MTy::PTR)],
            MTy::INT,
        );
        tb.func_mut().linkage = ms_mir::ir::Linkage::Internal;
        tb.func_mut().sort = ms_mir::ir::SortThunk::Generic;
        let args = tb.params();
        let mut load = |a| {
            tb.emit(
                ms_mir::ir::Op::Load,
                &[a],
                ms_mir::ir::Imm::Ty(elem),
                Some(elem),
            )
            .expect("load")
        };
        let (x, y) = (load(args[1]), load(args[2]));
        let r = tb.call_ind(args[0], &[x, y]);
        tb.ret(Some(r));
        let thunk = tb.into_func();
        self.b.m.add_func(thunk)
    }

    /// A collection method that changes its receiver place: the place receives the new value.
    pub fn mutator_call(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        m: &ct::MethodRef,
        recv_expr: &Expr,
        name: &str,
    ) -> Result<Val, Error> {
        let out = self.mutator_call_inner(e, view, m, recv_expr, name);
        self.fault_deferred_close();
        out
    }

    fn mutator_call_inner(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        m: &ct::MethodRef,
        recv_expr: &Expr,
        name: &str,
    ) -> Result<Val, Error> {
        // A map or set mutator returns its receiver; copy it only when something reads it.
        let discarded = self.discard == Some(e as *const Expr as usize);
        let result_ty = self.ety(e);
        let result_mty = self.emty(e)?;
        let hands_back = !discarded
            && (result_ty.is(Builtin::List)
                || result_ty.is(Builtin::Map)
                || result_ty.is(Builtin::Set));
        // A mutator that discards an entry closes a resource in it first; the fast paths below
        // overwrite entries without a look at the old one.
        let discards = self.discards_resource(recv_expr, name)?;
        let protect_list = self.ety(recv_expr).is(Builtin::List)
            && matches!(name, "append" | "prepend" | "insert" | "set" | "replace");
        let mut receiver_resource = None;
        // A receiver that is not a place is evaluated before the arguments, as written. An owned
        // receiver stays registered as a temporary while a later argument can leave through `try`.
        let mut receiver: Option<(Val, bool)> = None;
        if !self.is_place(recv_expr) {
            let x = self.expr(recv_expr)?;
            if self.dead {
                return Ok(x);
            }
            let x = if protect_list && x.own {
                if let Some(key) = self.hold_resource_temp(x.v)? {
                    receiver_resource = Some(key);
                    Val { v: key, own: false }
                } else {
                    x
                }
            } else {
                x
            };
            let held = view
                .arguments
                .iter()
                .any(|a| crate::mutation::has_try(a.expr));
            if held {
                self.hold_temp(x);
            }
            receiver = Some((x, held));
        } else {
            self.prepare_place(recv_expr)?;
            if self.dead {
                self.finish_place(recv_expr);
                return Ok(self.dummy(MTy::UNIT));
            }
        }
        if !discards && let Some(done) = self.borrowed_key_add(e, view, m, recv_expr, name)? {
            self.finish_place(recv_expr);
            return Ok(done);
        }
        let borrowed = self.borrowed_update_key(view, m, recv_expr, name)?;
        let mut args = self.native_args_borrowing(view, protect_list, borrowed)?;
        if self.dead {
            self.finish_place(recv_expr);
            return Ok(self.dummy(MTy::UNIT));
        }
        if let Some(key) = receiver_resource {
            return self.mutate_computed_resource_list(name, key, &args, recv_expr);
        }
        if matches!(name, "insert" | "replace" | "remove") && self.is_place(recv_expr) {
            self.precheck_list_index(recv_expr, name, &args[0])?;
            if self.dead {
                return Ok(self.dummy(MTy::UNIT));
            }
        }
        if discards {
            // The incoming owned arguments stay registered while the old entry closes: a close
            // that faults unwinds them with the statement instead of leaking them.
            // A resource is registered for fault and cancellation cleanup; other owned values
            // wait as ordinary temporaries.
            let mut held = Vec::new();
            for (i, arg) in args.iter_mut().enumerate() {
                if !arg.val.own {
                    continue;
                }
                if let Some(key) = self.hold_resource_temp(arg.val.v)? {
                    arg.val = Val { v: key, own: false };
                    held.push((i, true));
                } else {
                    arg.val = self.hold_temp(arg.val);
                    held.push((i, false));
                }
            }
            self.defer_close_failures();
            self.close_discarded_entry(recv_expr, name, &args)?;
            if self.dead {
                self.finish_place(recv_expr);
                return Ok(self.dummy(MTy::UNIT));
            }
            for (i, resource) in held.into_iter().rev() {
                let key = args[i].val.v;
                let v = if resource {
                    self.take_resource_temp(key).0
                } else {
                    key
                };
                self.unhold_temp(key);
                args[i].val = Val { v, own: true };
            }
        }
        if name == "set"
            && !hands_back
            && let Some(done) = self.slot_list_set(recv_expr, &args)?
        {
            self.finish_place(recv_expr);
            return Ok(done);
        }
        if let Some((x, held)) = receiver {
            if held {
                self.unhold_temp(x.v);
            }
            let old = self.owned(x);
            let (new, r) = self.mutate_any(name, old, &m.ty.params, &args, false, result_mty)?;
            return Ok(match r {
                Some(r) => {
                    self.drop_value(new);
                    r
                }
                // The updated temporary is the result only when the method returns its receiver;
                // a Unit method releases it, as the place branch below does.
                None if result_ty.is(Builtin::List)
                    || result_ty.is(Builtin::Map)
                    || result_ty.is(Builtin::Set) =>
                {
                    Val { v: new, own: true }
                }
                None => {
                    self.drop_value(new);
                    let u = self.b.unit();
                    Val { v: u, own: false }
                }
            });
        }
        let mut result: Option<Val> = None;
        self.place_update(recv_expr, &mut |s, old| {
            let (new, r) = s.mutate_any(name, old, &m.ty.params, &args, hands_back, result_mty)?;
            result = r;
            Ok(new)
        })?;
        match result {
            Some(r) => Ok(r),
            None => {
                let u = self.b.unit();
                Ok(Val { v: u, own: false })
            }
        }
    }

    /// Faults on an index the mutator would reject while the list still sits in its variable: the
    /// mutation takes the list out first, and a fault after that leaves the variable's cleanup
    /// with nothing to close (the entries stay unclosed on targets whose slot is not left intact).
    fn precheck_list_index(
        &mut self,
        recv_expr: &Expr,
        name: &str,
        index: &NArg,
    ) -> Result<(), Error> {
        use ms_mir::ir::{Cc, Op};
        if !self.ety(recv_expr).is(Builtin::List) {
            return Ok(());
        }
        let x = self.expr(recv_expr)?;
        if self.dead {
            return Ok(());
        }
        let list = self.borrow(x);
        let i = self.borrow(index.val);
        let n = self.b.list_len(list);
        let zero = self.b.iconst(0);
        let neg = self.b.icmp(Cc::Lt, i, zero);
        let shifted = self.b.binop(Op::IAdd, i, n);
        let r = self.b.select(neg, shifted, i);
        let (op, allow_end) = match name {
            "insert" => (0, true),
            "remove" => (1, false),
            _ => (4, false),
        };
        self.check_index(op, i, r, n, allow_end);
        self.finish(x);
        Ok(())
    }

    /// A temporary resource receiver stays in its authoritative cleanup slot throughout mutation.
    fn mutate_computed_resource_list(
        &mut self,
        name: &str,
        key: Value,
        args: &[NArg],
        recv_expr: &Expr,
    ) -> Result<Val, Error> {
        let ty = self.ety(recv_expr);
        let lt = self.ty_of(key);
        let TyKind::List(elem) = self.b.m.types.kind(lt).clone() else {
            unreachable!("resource list")
        };
        if name == "set" {
            self.close_list_entry_value(&ty.args[0], Val { v: key, own: false }, &args[0])?;
        }
        let index = if matches!(name, "append" | "prepend") {
            0
        } else {
            1
        };
        let arg = &args[index];
        let guard = self
            .resource_temp_slot(arg.val.v)
            .map(|slot| (slot, Some(arg.val.v)));
        let (incoming, incoming_key) = match guard {
            Some(pair) => pair,
            None => {
                let v = self.element_value(arg);
                (self.put_slot(v), None)
            }
        };
        let slot = self
            .resource_temp_slot(key)
            .expect("computed receiver slot");
        let result = self.guarded_list_slot(name, slot, elem, (incoming, incoming_key), args)?;
        let mut result_guard = None;
        if let Some(r) = result
            && r.own
        {
            result_guard = self.hold_resource_temp(r.v)?;
        }
        self.unhold_temp(key);
        self.drop_temp(key);
        if let Some(key) = result_guard {
            let v = self.take_resource_temp(key).0;
            self.unhold_temp(key);
            return Ok(Val { v, own: true });
        }
        Ok(result.unwrap_or(Val {
            v: self.b.unit(),
            own: false,
        }))
    }

    /// Whether `name` on the place `recv_expr` discards a resource entry of a list or map:
    /// `set` and `remove` on a list of resources, `add`, `remove` and `clear` on a map of them.
    pub(super) fn discards_resource(
        &mut self,
        recv_expr: &Expr,
        name: &str,
    ) -> Result<bool, Error> {
        if !ms_check::api::ownership::discards_entries(name) || !self.is_place(recv_expr) {
            return Ok(false);
        }
        let ty = self.ety(recv_expr);
        let held = if ty.is(Builtin::List) && matches!(name, "set" | "remove" | "splice") {
            ty.args.first()
        } else if ty.is(Builtin::Map) && matches!(name, "add" | "remove" | "clear") {
            ty.args.get(1)
        } else {
            None
        };
        match held {
            Some(t) => Ok(self.part_closer(t)?.is_some()),
            None => Ok(false),
        }
    }

    /// Closes the entry `name` is about to discard from the place `recv_expr`.
    pub(super) fn close_discarded_entry(
        &mut self,
        recv_expr: &Expr,
        name: &str,
        args: &[NArg],
    ) -> Result<(), Error> {
        let ty = self.ety(recv_expr);
        if name == "splice" {
            return self.close_list_range(recv_expr, &args[0], &args[1]);
        }
        if ty.is(Builtin::List) {
            return self.close_list_entry(recv_expr, &args[0]);
        }
        if name == "clear" {
            // Every value goes: the map closes what it holds, last inserted first.
            let x = self.expr(recv_expr)?;
            if self.dead {
                return Ok(());
            }
            if x.own {
                let map = self.close_discarded_ty(&ty, x.v)?;
                self.drop_value(map);
                return Ok(());
            }
            let Some(kind) = self.part_closer(&ty)? else {
                return Ok(());
            };
            self.place_update_prepared(recv_expr, &mut |s, old| {
                Ok(s.close_discarded_kind(&kind, old))
            })?;
            return Ok(());
        }
        self.close_map_entry(recv_expr, &args[0])
    }

    /// `m.add(k, v)` over an existing key and `m.remove(k)` discard the value of `k`.
    pub(super) fn close_map_entry(&mut self, recv_expr: &Expr, key: &NArg) -> Result<(), Error> {
        use ms_mir::ir::{Imm, Op};
        let ty = self.ety(recv_expr);
        let Some(value) = ty.args.get(1).cloned() else {
            return Ok(());
        };
        let x = self.expr(recv_expr)?;
        if self.dead {
            return Ok(());
        }
        let mv = self.borrow(x);
        let kv = self.borrow(key.val);
        let mt = self.ty_of(mv);
        let value_ty = self.map_value_type(mv)?;
        let (kd, vd) = self.map_descs(mt)?;
        let vd = vd.ok_or_else(|| Error::new("a set has no values"))?;
        let ks = self.borrow_slot(kv);
        let p = self.call_runtime("msrt_map_get_ptr", &[mv, kd, vd, ks], MTy::PTR)?;
        let missing = self
            .b
            .emit(Op::PtrIsNull, &[p], Imm::None, Some(MTy::BOOL))
            .expect("is_null");
        let (absent, present) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(missing, absent, &[], present, &[]);
        self.b.seal_block(present);
        self.b.switch_to(present);
        let _ = value_ty;
        self.close_discarded_at(&value, p)?;
        self.b.br(absent, &[]);
        self.b.seal_block(absent);
        self.b.switch_to(absent);
        self.finish(x);
        Ok(())
    }

    /// `xs.splice(start, count, ..)` deletes `count` elements from `start`: the resources in
    /// them close, last first. Bounds the mutator rejects close nothing and fault there.
    pub(super) fn close_list_range(
        &mut self,
        recv_expr: &Expr,
        start: &NArg,
        count: &NArg,
    ) -> Result<(), Error> {
        use ms_mir::ir::{Cc, Mode, Op};
        let list_ty = self.ety(recv_expr);
        let Some(elem) = list_ty.args.first().cloned() else {
            return Ok(());
        };
        let x = self.expr(recv_expr)?;
        if self.dead {
            return Ok(());
        }
        let list = self.borrow(x);
        let from = self.borrow(start.val);
        let n = self.borrow(count.val);
        let len = self.b.list_len(list);
        let zero = self.b.iconst(0);
        let end = self.b.binop(Op::IAdd, from, n);
        let c1 = self.b.icmp(Cc::Ge, from, zero);
        let c2 = self.b.icmp(Cc::Ge, n, zero);
        let c3 = self.b.icmp(Cc::Le, end, len);
        let c12 = self.b.binop(Op::And, c1, c2);
        let valid = self.b.binop(Op::And, c12, c3);
        let (enter, exit) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(valid, enter, &[], exit, &[]);
        self.b.seal_block(enter);
        self.b.switch_to(enter);
        let idx = self.b.declare_var(MTy::INT, Mode::Borrow);
        self.b.def_var(idx, end);
        let (header, body, done) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(header, &[]);
        self.b.switch_to(header);
        let i = self.b.use_var(idx);
        let more = self.b.icmp(Cc::Gt, i, from);
        self.b.br_if(more, body, &[], done, &[]);
        self.b.seal_block(body);
        self.b.switch_to(body);
        let i = self.b.use_var(idx);
        let one = self.b.iconst(1);
        let j = self.b.binop(Op::ISub, i, one);
        self.b.def_var(idx, j);
        let ep = self
            .b
            .emit(
                Op::ListAddrU,
                &[list, j],
                ms_mir::ir::Imm::None,
                Some(MTy::PTR),
            )
            .expect("element address");
        self.close_discarded_at(&elem, ep)?;
        self.b.br(header, &[]);
        self.b.seal_block(header);
        self.b.seal_block(done);
        self.b.switch_to(done);
        self.b.br(exit, &[]);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        self.finish(x);
        Ok(())
    }

    /// `xs.set(i, v)` and `xs.remove(i)` discard the element at `i`: a resource in it closes
    /// first. An index out of range closes nothing and faults in the mutator.
    pub(super) fn close_list_entry(&mut self, recv_expr: &Expr, index: &NArg) -> Result<(), Error> {
        let list_ty = self.ety(recv_expr);
        let Some(elem) = list_ty.args.first().filter(|_| list_ty.is(Builtin::List)) else {
            return Ok(());
        };
        if self.part_closer(elem)?.is_none() {
            return Ok(());
        }
        let x = self.expr(recv_expr)?;
        if self.dead {
            return Ok(());
        }
        self.close_list_entry_value(elem, x, index)
    }

    fn close_list_entry_value(&mut self, elem: &ct::Ty, x: Val, index: &NArg) -> Result<(), Error> {
        use ms_mir::ir::{Cc, Op};
        let list = self.borrow(x);
        let i = self.borrow(index.val);
        let n = self.b.list_len(list);
        let zero = self.b.iconst(0);
        let neg = self.b.icmp(Cc::Lt, i, zero);
        let shifted = self.b.binop(Op::IAdd, i, n);
        let r = self.b.select(neg, shifted, i);
        let lo = self.b.icmp(Cc::Ge, r, zero);
        let hi = self.b.icmp(Cc::Lt, r, n);
        let inside = self.b.binop(Op::And, lo, hi);
        let (yes, exit) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(inside, yes, &[], exit, &[]);
        self.b.seal_block(yes);
        self.b.switch_to(yes);
        let ep = self
            .b
            .emit(
                Op::ListAddrU,
                &[list, r],
                ms_mir::ir::Imm::None,
                Some(MTy::PTR),
            )
            .expect("element address");
        self.close_discarded_at(elem, ep)?;
        self.b.br(exit, &[]);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        self.finish(x);
        Ok(())
    }

    /// `xs.set(i, v)` where the list stays in place: a list variable that lives in memory (a
    /// closure shares it) or an element of one (`dp[i][j] = v`). The element is written where it
    /// lies: taking the list out of its place and putting the unchanged header back would store
    /// ptr, len and cap again after every write.
    pub(super) fn slot_list_set(
        &mut self,
        recv_expr: &Expr,
        args: &[NArg],
    ) -> Result<Option<Val>, Error> {
        use ms_mir::ir::{Cc, Imm, Op};
        if args
            .get(1)
            .is_some_and(|a| self.resource_temp_slot(a.val.v).is_some())
        {
            return Ok(None);
        }
        let elem_place = crate::mutation::index_parts(self.syms, &self.hir, recv_expr).is_some();
        let list = if elem_place {
            // The row is a borrowed read of the owner's element; only its elements change.
            let row = self.read_place(recv_expr)?;
            if self.dead {
                return Ok(None);
            }
            let list = self.borrow(row);
            if self.b.m.list_elem(self.ty_of(list)).is_none() {
                return Ok(None);
            }
            list
        } else {
            let ExprKind::Name(_) = &recv_expr.kind else {
                return Ok(None);
            };
            let Resolution::Local(binding) = self.hir.resolution(recv_expr) else {
                return Ok(None);
            };
            if self.aliases.contains_key(&binding.uid) {
                return Ok(None);
            }
            let l = self.local(&binding)?;
            if l.slot.is_none() || !matches!(self.b.m.types.kind(l.ty), TyKind::List(_)) {
                return Ok(None);
            }
            self.read_local(&binding)?.v
        };
        let Some(elem) = self.b.m.list_elem(self.ty_of(list)) else {
            return Ok(None);
        };
        let i = self.borrow(args[0].val);
        let n = self.b.list_len(list);
        let zero = self.b.iconst(0);
        let neg = self.b.icmp(Cc::Lt, i, zero);
        let shifted = self.b.binop(Op::IAdd, i, n);
        let r = self.b.select(neg, shifted, i);
        self.check_index(2, i, r, n, false);
        let v = self.element_value(&args[1]);
        let at = self
            .b
            .emit(Op::ListAddrU, &[list, r], Imm::None, Some(MTy::PTR))
            .expect("list.addr.u");
        if self.needs_drop(elem) {
            let old = self
                .b
                .emit(Op::Take, &[at], Imm::Ty(elem), Some(elem))
                .expect("take");
            self.drop_value(old);
            self.b.emit(Op::Put, &[at, v], Imm::None, None);
        } else {
            self.b.emit(Op::Store, &[at, v], Imm::None, None);
        }
        let u = self.b.unit();
        Ok(Some(Val { v: u, own: false }))
    }

    /// Runs two branches that each produce an owned value of `ty` (or diverge with `None`).
    pub(crate) fn two_ways(
        &mut self,
        cond: Value,
        ty: MTy,
        yes: &mut BranchBody<'_, Self>,
        no: &mut BranchBody<'_, Self>,
    ) -> Result<Val, Error> {
        let mode = if self.needs_drop(ty) {
            Mode::Move
        } else {
            Mode::Borrow
        };
        let out = self.two_ways_mode(cond, ty, mode, yes, no)?;
        // A scalar resource has no drop glue, so its storage mode is a borrow, but the join
        // still owns it: its parent must close.
        if mode == Mode::Borrow && !self.dead && self.part_closer_mir(ty)?.is_some() {
            return Ok(Val {
                v: out.v,
                own: true,
            });
        }
        Ok(out)
    }

    /// `two_ways` with the result's ownership chosen by the caller: `Borrow` joins two values
    /// that are borrows, so the result is one too.
    pub(crate) fn two_ways_mode(
        &mut self,
        cond: Value,
        ty: MTy,
        mode: Mode,
        yes: &mut BranchBody<'_, Self>,
        no: &mut BranchBody<'_, Self>,
    ) -> Result<Val, Error> {
        let owned = mode == Mode::Move;
        let out = self.b.declare_var(ty, mode);
        let (a, b, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br_if(cond, a, &[], b, &[]);
        self.b.seal_block(a);
        self.b.seal_block(b);
        let mut live = false;
        self.enter(a);
        if let Some(v) = yes(self)? {
            self.b.def_var(out, v);
            self.b.br(join, &[]);
            live = true;
        }
        self.enter(b);
        if let Some(v) = no(self)? {
            self.b.def_var(out, v);
            self.b.br(join, &[]);
            live = true;
        }
        self.b.seal_block(join);
        self.enter(join);
        if !live {
            self.dead = true;
            return Ok(self.dummy(ty));
        }
        let v = self.b.use_var(out);
        Ok(Val { v, own: owned })
    }

    /// Drops an owned operand once its branch is done with it.
    pub(crate) fn finish(&mut self, x: Val) {
        if x.own && self.needs_drop(self.ty_of(x.v)) {
            self.drop_value(x.v);
        }
    }

    /// Faults unless `lo <= i && i < hi_exclusive` (`i` already resolved from the end).
    pub(crate) fn check_index(
        &mut self,
        op: i64,
        original: Value,
        i: Value,
        len: Value,
        allow_end: bool,
    ) {
        use ms_mir::ir::{Cc, Op};
        let zero = self.b.iconst(0);
        let lo = self.b.icmp(Cc::Ge, i, zero);
        let hi = self.b.icmp(if allow_end { Cc::Le } else { Cc::Lt }, i, len);
        let ok = self.b.binop(Op::And, lo, hi);
        let (good, bad) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(ok, good, &[], bad, &[]);
        self.b.seal_block(good);
        self.b.seal_block(bad);
        self.b.switch_to(bad);
        let opv = self.b.iconst(op);
        let ext = self.b.m.add_extern(ms_mir::ir::ExternDef {
            name: "msrt_list_index_fault".to_string(),
            params: vec![
                Param {
                    ty: MTy::INT,
                    mode: Mode::Borrow
                };
                3
            ],
            ret: MTy::UNIT,
            noreturn: true,
            pure_: false,
            fresh: false,
            role: ms_mir::ir::ExternRole::None,
            leaf: crate::rtcall::rt_flags("msrt_list_index_fault").leaf,
            reads: crate::rtcall::rt_flags("msrt_list_index_fault").reads,
        });
        self.b.call_rt(ext, &[opv, original, len]);
        self.b.unreachable();
        self.b.switch_to(good);
    }

    /// `n.seconds()`, `n.milliseconds()`, `n.minutes()`: the runtime's checked nanosecond count.
    pub(crate) fn duration_unit(&mut self, unit: &str, n: Val) -> Result<Val, Error> {
        let v = self.borrow(n);
        let nanos = self.call_runtime(&format!("msstd_time_int_{unit}"), &[v], MTy::INT)?;
        let out = self.duration_of(nanos)?;
        Ok(Val { v: out, own: false })
    }
}
