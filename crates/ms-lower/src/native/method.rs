//! Method calls on native receivers: strings, numbers, lists, maps and sets.

use super::*;

impl<'a> FnLower<'a> {
    pub fn native_method(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        m: &ct::MethodRef,
        recv_expr: &Expr,
        recv: Val,
    ) -> Result<Val, Error> {
        let native = m.native.text(self.syms);
        let at = self.b.current();
        // The receiver is evaluated first: an argument that reassigns its variable must not
        // change what the call reads.
        let snapshot = self.argument_reassigns(recv_expr, view);
        let func = m.decl.as_ref().and_then(|d| d.func());
        let later_try = view
            .arguments
            .iter()
            .any(|a| crate::mutation::has_try(a.expr))
            || func.is_some_and(|f| {
                m.ty.params.iter().zip(&f.params).any(|(p, d)| {
                    !view.arguments.iter().any(|a| a.slot.name == p.name)
                        && d.default.as_ref().is_some_and(crate::mutation::has_try)
                })
            });
        let recv = if snapshot {
            Val {
                v: self.owned(recv),
                own: true,
            }
        } else {
            recv
        };
        // Record only the owner held by this call, never an enclosing borrowed temporary.
        // Intact wrappers need their payload closer on an expected-error return too.
        let (recv, held) = if recv.own && (snapshot || later_try) {
            if let Some(key) = self.hold_resource_temp(recv.v)? {
                (Val { v: key, own: false }, Some(true))
            } else {
                (self.hold_temp(recv), Some(false))
            }
        } else {
            (recv, None)
        };
        let mut args = self.native_args(view)?;
        if self.dead {
            return Ok(recv);
        }
        let recv = if held.is_some() {
            recv
        } else {
            self.refresh(recv_expr, recv, at)?
        };
        self.fill_native_defaults(m.module, func, &m.ty.params, &mut args)?;
        if self.dead {
            return Ok(recv);
        }
        let recv = if let Some(resource) = held {
            let v = if resource {
                self.take_resource_temp(recv.v).0
            } else {
                recv.v
            };
            self.unhold_temp(recv.v);
            Val { v, own: true }
        } else {
            recv
        };
        self.at(e.pos);
        let str_recv = matches!(self.b.m.types.kind(self.ty_of(recv.v)), TyKind::Str);
        // `NormalizationForm` is the only alternative whose native `normalize` this lowers.
        let form_recv = matches!(self.b.m.types.kind(self.ty_of(recv.v)), TyKind::Alt(_));
        if str_recv && native == "chars" && self.chars_iter_for == Some(e as *const Expr) {
            // `for c in text.chars()`: the loop scans the string itself, so no list is built.
            self.chars_iter_for = None;
            return Ok(recv);
        }
        if str_recv && native == "scalar_values" && self.chars_iter_for == Some(e as *const Expr) {
            // `for c in text.scalar_values()`: the loop decodes the string itself.
            self.chars_iter_for = None;
            self.scalars_scan = true;
            return Ok(recv);
        }
        if self.map_walk_for == Some(e as *const Expr)
            && let Some(walk) = self.walk_kind(m, recv.v)
        {
            // `for e in m.entries()` over a map the loop cannot change: the loop walks the
            // map's slots, so no list is built and nothing is copied.
            self.map_walk_for = None;
            self.map_walk = Some(walk);
            return Ok(recv);
        }
        if self.keys_view_for == Some(e as *const Expr)
            && let Some(sym) = self.keys_view_symbol(m, recv_expr, recv.v)
        {
            // `for k in p.m.keys()` over a map in a parameter the body only reads: the list
            // borrows the map's strings instead of copying them.
            self.keys_view_for = None;
            let result = self.emty(e)?;
            return self.rt_method(sym, recv, &[], &[], result);
        }
        let lent = self.cx.fact(
            self.hir.data.file,
            e.id,
            ms_check::api::ownership::Fact::BorrowedRead,
        );
        if lent && !recv.own {
            // The checker lends the result (used in place while the receiver stays unchanged):
            // string keys and values, and the elements of a slice, are views of the receiver.
            let rty = self.ty_of(recv.v);
            let name = native.rsplit('/').next().unwrap_or(native);
            match (self.b.m.types.kind(rty), name) {
                (TyKind::Obj(Native::Map, _), "keys" | "values") => {
                    let sym = if name == "keys" {
                        "msrt_map_keys_view"
                    } else {
                        "msrt_map_values_view"
                    };
                    let result = self.emty(e)?;
                    return self.rt_method(sym, recv, &[], &[], result);
                }
                (TyKind::List(elem), "slice") if !self.b.m.needs_drop(*elem) => {
                    let result = self.emty(e)?;
                    // The list is a `cap == 0` view: dropping it frees and drops nothing.
                    return self.rt_method(
                        "msrt_list_slice_view",
                        recv,
                        &m.ty.params,
                        &args,
                        result,
                    );
                }
                _ => {}
            }
        }
        if str_recv
            && native == "split"
            && (lent
                || (self.split_view_for == Some(e as *const Expr) && self.stable_place(recv_expr)))
        {
            // A `split` the checker lends (its result is used in place while the receiver
            // stays unchanged), or `let parts = text.split(..)` read only in place over a
            // parameter the body only reads: the pieces are views of `text`.
            self.split_view_for = None;
            let result = self.emty(e)?;
            return self.rt_method("msrt_string_split_view", recv, &m.ty.params, &args, result);
        }
        if str_recv && native == "split" && self.split_iter_for == Some(e as *const Expr) {
            // `for piece in text.split(..)`: pieces are produced one at a time.
            self.split_iter_for = None;
            let iter = self.b.m.types.obj("SplitIter", Vec::new());
            return self.rt_method("msrt_string_split_iter", recv, &m.ty.params, &args, iter);
        }
        if let Some(&(_, sym, param, as_text)) = FORMAT_METHODS
            .iter()
            .find(|(n, ..)| *n == native && form_recv)
        {
            let result = self.emty(e)?;
            return self.format_method(result, m, recv, args, (sym, param, as_text));
        }
        if native == "hash" && !matches!(self.b.m.types.kind(self.ty_of(recv.v)), TyKind::Str) {
            return self.structural_hash(recv);
        }
        if let Some((_, sym)) = STRING_TO_STRING
            .iter()
            .find(|(n, _)| str_recv && *n == native)
        {
            let r = self.borrow(recv);
            let out = self.call_runtime(sym, &[r], MTy::STR)?;
            return Ok(Val { v: out, own: true });
        }
        if str_recv && (native == "length" || native == "scalar_length") {
            let r = self.borrow(recv);
            let n = self.b.str_len(r);
            return Ok(Val { v: n, own: false });
        }
        if let Some((_, sym, ret)) = PLAIN_STRING
            .iter()
            .find(|(n, _, _)| str_recv && *n == native)
        {
            let mut vals = vec![self.borrow(recv)];
            for a in args {
                vals.push(self.borrow(a.val));
            }
            let out = self.call_runtime(sym, &vals, *ret)?;
            return Ok(self.val(out, *ret == MTy::STR));
        }
        if native == "normalize" && form_recv {
            // The form is a payload-free alternative: its case index selects the algorithm.
            let result = self.emty(e)?;
            let syms = self.syms;
            let find = |n: &str| args.iter().find(|a| syms.str(a.name) == n).copied();
            let text = find("text").ok_or_else(|| Error::new("normalize without text"))?;
            let text = self.borrow(text.val);
            let form = self.borrow(recv);
            let kind = self.b.alt_tag(form);
            let (has, max) = self.optional_int(find("max_bytes"))?;
            let sym = "msrt_string_normalize_kind";
            let sig = crate::rtcall::rt_sig(sym)
                .ok_or_else(|| Error::new(format!("no runtime symbol {sym}")))?;
            return self.finish_rt_call(sym, &sig, true, vec![text, kind, has, max], result);
        }
        let pos = e.pos;
        let result = self.emty(e)?;
        self.native_method_tail(m, Some(recv_expr), pos, result, recv, args)
    }

    /// The part of a native method call that needs only the receiver, the arguments and the
    /// result type, so a bound method value reaches it without a call expression.
    pub(crate) fn native_method_tail(
        &mut self,
        m: &ct::MethodRef,
        recv_expr: Option<&Expr>,
        pos: ms_check::api::Pos,
        result: MTy,
        recv: Val,
        mut args: Vec<NArg>,
    ) -> Result<Val, Error> {
        let native = m.native.text(self.syms);
        let recv_ty = self.ty_of(recv.v);
        let numeric_recv = self.b.m.types.is_int(recv_ty) || self.b.m.types.is_float(recv_ty);
        // `Float.to_float32()` is a runtime call: it returns none when the value overflows.
        let float_to_float32 = native == "to_float32" && self.b.m.types.is_float(recv_ty);
        if (matches!(
            native,
            "to_int8"
                | "to_int16"
                | "to_int32"
                | "to_int64"
                | "to_uint8"
                | "to_uint16"
                | "to_uint32"
                | "to_uint64"
                | "to_float32"
                | "to_float64"
        ) || (numeric_recv && matches!(native, "to_int" | "to_float")))
            && !float_to_float32
        {
            return self.numeric_conversion(result, recv);
        }
        if recv_ty == MTy::UINT64
            && let Some(v) = self.uint64_method(native, result, recv, &args)?
        {
            return Ok(v);
        }
        // Other operations on a sized number run on its 64-bit kind; a clone keeps its width.
        let recv_nums = {
            let t = self.ty_of(recv.v);
            (self.b.m.types.is_int(t) || self.b.m.types.is_float(t))
                && native.rsplit('/').next() != Some("clone")
        };
        let recv = if recv_nums {
            for a in &mut args {
                a.val = self.widen_numeric(a.val);
            }
            self.widen_numeric(recv)
        } else {
            recv
        };
        if let Some(sym) = m.name().and_then(|n| {
            crate::rtcall::typed_method_symbol(self.syms, &m.receiver, self.syms.str(n))
        }) {
            return self.rt_method(&sym, recv, &m.ty.params, &args, result);
        }
        let name = native.rsplit('/').next().unwrap_or(native);
        let rty = self.ty_of(recv.v);
        match (self.b.m.types.kind(rty).clone(), name) {
            (TyKind::Obj(n, _), "length" | "is_empty") if n == Native::Map || n == Native::Set => {
                let r = self.borrow(recv);
                let len = self.call_runtime("msrt_map_length", &[r], MTy::INT)?;
                if name == "length" {
                    return Ok(Val { v: len, own: false });
                }
                let z = self.b.iconst(0);
                let v = self.b.icmp(ms_mir::ir::Cc::Eq, len, z);
                Ok(Val { v, own: false })
            }
            (TyKind::Obj(Native::Map, _), "get_or") => {
                self.map_get_or(recv, &m.ty.params, &args, result)
            }
            (TyKind::Obj(Native::Map, _), "entries") => self.map_entries(recv_expr, recv, result),
            (TyKind::List(_), "keys") => self.list_keys(recv_expr, recv, result),
            (TyKind::List(_), "entries") => self.list_entries(recv_expr, recv, result),
            (TyKind::List(_) | TyKind::Bytes, "length") => {
                let r = self.borrow(recv);
                let v = self.b.list_len(r);
                Ok(Val { v, own: false })
            }
            (TyKind::Bytes, "view") => {
                // A borrow of the receiver's storage; a temporary receiver is copied out before
                // it is dropped, as an element read of a temporary list is.
                let r = self.borrow(recv);
                let (start, end) = (self.borrow(args[0].val), self.borrow(args[1].val));
                let slot = self
                    .b
                    .emit(Op::Slot, &[], Imm::Ty(MTy::BYTES), Some(MTy::PTR))
                    .expect("slot");
                self.call_runtime("msrt_bytes_view", &[r, start, end, slot], MTy::UNIT)?;
                // Loading the header from the slot gives a value the MIR does not own.
                let v = self
                    .b
                    .emit(Op::Load, &[slot], Imm::Ty(MTy::BYTES), Some(MTy::BYTES))
                    .expect("load");
                if recv.own {
                    // The view of a temporary cannot outlive it: the result is the copy.
                    let o = self.clone_value(v);
                    return Ok(Val { v: o, own: true });
                }
                Ok(Val { v, own: false })
            }
            (TyKind::Str, "view") => {
                // Like `Bytes.view`: a borrow of the receiver's text, or a copy of a temporary's.
                let r = self.borrow(recv);
                let (start, end) = (self.borrow(args[0].val), self.borrow(args[1].val));
                let slot = self
                    .b
                    .emit(Op::Slot, &[], Imm::Ty(MTy::STR), Some(MTy::PTR))
                    .expect("slot");
                self.call_runtime("msrt_string_view", &[r, start, end, slot], MTy::UNIT)?;
                let v = self
                    .b
                    .emit(Op::Load, &[slot], Imm::Ty(MTy::STR), Some(MTy::STR))
                    .expect("load");
                if recv.own {
                    // The view of a temporary cannot outlive it: the result is the copy.
                    let o = self.clone_value(v);
                    return Ok(Val { v: o, own: true });
                }
                Ok(Val { v, own: false })
            }
            (TyKind::List(_) | TyKind::Bytes, "is_empty") => {
                let r = self.borrow(recv);
                let n = self.b.list_len(r);
                let z = self.b.iconst(0);
                let v = self.b.icmp(ms_mir::ir::Cc::Eq, n, z);
                Ok(Val { v, own: false })
            }
            (TyKind::List(elem), "reversed") => {
                let (lv, hidden) = self.list_source(recv_expr, recv)?;
                let r = self.list_reversed(lv, elem);
                self.release_source(lv, hidden);
                r
            }
            (TyKind::List(elem), "take" | "drop") => {
                let sym = if name == "take" {
                    "msrt_list_take"
                } else {
                    "msrt_list_drop_n"
                };
                let d = self.type_desc(elem);
                let r = self.borrow(recv);
                let n = self.borrow(args[0].val);
                let out = self.call_runtime(sym, &[r, d, n], rty)?;
                Ok(Val { v: out, own: true })
            }
            (TyKind::List(_), "zip") => {
                let TyKind::List(pair) = self.b.m.types.kind(result).clone() else {
                    return Err(Error::new("zip without a list result"));
                };
                let TyKind::Rec(rid) = self.b.m.types.kind(pair).clone() else {
                    return Err(Error::new("zip without a record element"));
                };
                let other = self.borrow(args[0].val);
                let other_len = self.b.list_len(other);
                // Zipping a list with itself must not iterate its variable, which loop headers
                // would consume while `other` is still read.
                let same = other == recv.v;
                let (lv, hidden) = self.list_source(if same { None } else { recv_expr }, recv)?;
                let acc = self.fresh_var(result);
                let first = self.b.list_new(pair, other_len);
                self.b.def_var(acc, first);
                self.each_element(lv, &mut |s, i, x| {
                    let inside = s.b.icmp(ms_mir::ir::Cc::Lt, i, other_len);
                    let (take, skip) = (s.b.new_block(), s.b.new_block());
                    s.b.br_if(inside, take, &[], skip, &[]);
                    s.b.seal_block(take);
                    s.b.seal_block(skip);
                    s.b.switch_to(take);
                    let y = s.b.list_get(other, i);
                    let xo = s.clone_value(x);
                    let yo = s.clone_value(y);
                    let rec = s.b.rec_new(rid, &[xo, yo]);
                    let cur = s.b.use_var(acc);
                    let next = s.b.list_push(cur, rec);
                    s.b.def_var(acc, next);
                    s.b.br(skip, &[]);
                    s.b.switch_to(skip);
                    Ok(None)
                })?;
                self.release_source(lv, hidden);
                let out = self.b.use_var(acc);
                Ok(Val { v: out, own: true })
            }
            (TyKind::List(elem), "chunks" | "windows") => {
                self.list_pieces(name == "chunks", elem, recv, &args, result)
            }
            (TyKind::List(_) | TyKind::Bytes, "get") => {
                let elem = self
                    .b
                    .m
                    .seq_elem(rty)
                    .ok_or_else(|| Error::new("get on a non-list"))?;
                // Arguments arrive in written order; the names say which is which.
                let mut index = None;
                let mut default = None;
                for a in args {
                    if self.syms.str(a.name) == "default" {
                        default = Some(a);
                    } else {
                        index = Some(a);
                    }
                }
                let index = index.ok_or_else(|| Error::new("get without index"))?;
                self.list_get_or(recv, elem, index, default)
            }
            (_, "abs" | "sign") if self.b.m.types.is_int(rty) => {
                let x = self.borrow(recv);
                let (zero, minus) = (self.b.iconst(0), self.b.iconst(-1));
                let neg = self.b.icmp(ms_mir::ir::Cc::Lt, x, zero);
                if name == "sign" {
                    let (one, pos) = (self.b.iconst(1), self.b.icmp(ms_mir::ir::Cc::Gt, x, zero));
                    let upper = self.b.select(pos, one, zero);
                    let v = self.b.select(neg, minus, upper);
                    return Ok(Val { v, own: false });
                }
                let negated = self.b.binop(ms_mir::ir::Op::ISubChk, zero, x);
                let v = self.b.select(neg, negated, x);
                // A narrower receiver keeps its type; the range check faults on its minimum.
                let v = if self.b.m.types.int_bits(result).is_some_and(|b| b < 64) {
                    let narrow = self.b.conv(v, result);
                    self.b.narrow_chk(narrow)
                } else {
                    v
                };
                Ok(Val { v, own: false })
            }
            (_, "abs" | "sign") if self.b.m.types.is_float(rty) => {
                let x = self.borrow(recv);
                let v = if name == "abs" {
                    self.b
                        .emit(
                            ms_mir::ir::Op::FAbs,
                            &[x],
                            ms_mir::ir::Imm::None,
                            Some(MTy::FLOAT),
                        )
                        .expect("fabs")
                } else {
                    self.call_runtime("msstd_math_sign", &[x], MTy::FLOAT)?
                };
                let v = if result == MTy::FLOAT32 {
                    self.b.conv(v, result)
                } else {
                    v
                };
                Ok(Val { v, own: false })
            }
            (TyKind::Int, "milliseconds" | "seconds" | "minutes") => self.duration_unit(name, recv),
            (TyKind::Int, "to_decimal") => {
                let n = self.borrow(recv);
                let v = self.call_runtime("msstd_decimal_from_int", &[n], result)?;
                Ok(Val { v, own: false })
            }
            (TyKind::Int, "to_float") => {
                let x = self.borrow(recv);
                let v = self
                    .b
                    .emit(
                        ms_mir::ir::Op::I2F,
                        &[x],
                        ms_mir::ir::Imm::None,
                        Some(MTy::FLOAT),
                    )
                    .expect("i2f");
                Ok(Val { v, own: false })
            }
            (TyKind::Float, "is_nan" | "is_finite") => {
                let x = self.borrow(recv);
                if name == "is_nan" {
                    let v = self.b.fcmp(ms_mir::ir::Cc::Ne, x, x);
                    return Ok(Val { v, own: false });
                }
                // `x - x` is zero for finite x and NaN for NaN and the infinities.
                let d = self.b.emit(
                    ms_mir::ir::Op::FSub,
                    &[x, x],
                    ms_mir::ir::Imm::None,
                    Some(MTy::FLOAT),
                );
                let zero = self.b.fconst(0.0);
                let v = self.b.fcmp(ms_mir::ir::Cc::Eq, d.expect("fsub"), zero);
                Ok(Val { v, own: false })
            }
            (_, "compare") if self.b.m.types.is_int(rty) || self.b.m.types.is_float(rty) => {
                let a = self.borrow(recv);
                let b = self.borrow(args[0].val);
                let (lt, gt) = if self.b.m.types.is_int(rty) {
                    (
                        self.b.icmp(ms_mir::ir::Cc::Lt, a, b),
                        self.b.icmp(ms_mir::ir::Cc::Gt, a, b),
                    )
                } else {
                    (
                        self.b.fcmp(ms_mir::ir::Cc::Lt, a, b),
                        self.b.fcmp(ms_mir::ir::Cc::Gt, a, b),
                    )
                };
                let (m1, one, zero) = (self.b.iconst(-1), self.b.iconst(1), self.b.iconst(0));
                // An unordered pair has a NaN: NaN equals NaN and sorts above every other value.
                let unordered = if self.b.m.types.is_float(rty) {
                    let a_nan = self.b.fcmp(ms_mir::ir::Cc::Ne, a, a);
                    let b_nan = self.b.fcmp(ms_mir::ir::Cc::Ne, b, b);
                    let a_only = self.b.select(b_nan, zero, one);
                    let b_only = self.b.select(b_nan, m1, zero);
                    self.b.select(a_nan, a_only, b_only)
                } else {
                    zero
                };
                let g = self.b.select(gt, one, unordered);
                let v = self.b.select(lt, m1, g);
                Ok(Val { v, own: false })
            }
            (TyKind::Opt(inner), _) if opt_method(name) => {
                let out = result;
                self.optional_method(out, pos, name, recv, inner, args)
            }
            (
                TyKind::Alt(a),
                "get" | "err" | "get_or_else" | "or_else" | "map_error" | "map" | "and_then"
                | "to_optional" | "error",
            ) => {
                let out = result;
                self.result_method(out, name, recv, a, args)
            }
            (TyKind::Alt(a), "is_ok" | "is_error") => self.result_state(name, recv, a),
            (TyKind::List(_), "repeated") => {
                let TyKind::List(elem) = self.b.m.types.kind(rty).clone() else {
                    unreachable!()
                };
                let d = self.type_desc(elem);
                let a = self.borrow(recv);
                let n = self.borrow(args[0].val);
                let out = self.call_runtime("msrt_list_repeat", &[a, d, n], rty)?;
                Ok(Val { v: out, own: true })
            }
            (TyKind::List(_), "concat") => {
                let TyKind::List(elem) = self.b.m.types.kind(rty).clone() else {
                    unreachable!()
                };
                let d = self.type_desc(elem);
                let a = self.borrow(recv);
                let b = self.borrow(args[0].val);
                let out = self.call_runtime("msrt_list_concat", &[a, b, d], rty)?;
                Ok(Val { v: out, own: true })
            }
            (TyKind::Int, "to_string") if !args.is_empty() => {
                let (v, r) = (self.borrow(recv), self.borrow(args[0].val));
                let out = self.call_runtime("msrt_int_to_string_radix", &[v, r], MTy::STR)?;
                Ok(Val { v: out, own: true })
            }
            (_, "to_string") if m.receiver.is(Builtin::Duration) => self.duration_text(recv),
            (_, "to_string") => self.format_value(recv),
            (_, "clone") => {
                let v = self.clone_value(recv.v);
                if recv.own {
                    self.drop_value(recv.v);
                }
                Ok(Val { v, own: true })
            }
            (TyKind::List(elem), "sorted") => self.list_sorted_call(recv_expr, recv, elem, args),
            (_, "equals") if args.len() == 1 => {
                let concrete = recv_expr.map_or_else(|| m.receiver.clone(), |r| self.hir.ty(r));
                self.equals_value(&concrete, recv, args[0].val)
            }
            _ if crate::iterate::handles(self.b.m, rty, name) => {
                let out = result;
                self.iterate_method(out, name, recv_expr, recv, args)
            }
            (TyKind::List(_), _) if is_higher_order(name) => {
                let out = result;
                self.list_higher(name, out, recv_expr, recv, args)
            }
            _ => {
                let Some(sym) = crate::rtcall::method_symbol(self.b.m, rty, native) else {
                    return Err(Error::new(format!(
                        "unsupported native method {native} ({name}) on {}",
                        ms_mir::print::ty_str(self.b.m, rty)
                    )));
                };
                self.rt_method(&sym, recv, &m.ty.params, &args, result)
            }
        }
    }

    /// A list method taking a function (`map`, `count`, `for_each`, ...).
    pub(super) fn list_higher(
        &mut self,
        name: &str,
        out: MTy,
        recv_expr: Option<&Expr>,
        recv: Val,
        args: Vec<NArg>,
    ) -> Result<Val, Error> {
        let TyKind::List(elem) = self.b.m.types.kind(self.ty_of(recv.v)).clone() else {
            return Err(Error::new("higher-order method on a non-list"));
        };
        let f = args
            .into_iter()
            .find(|a| self.is_fn(a.val.v))
            .ok_or_else(|| Error::new("missing function argument"))?;
        let (fvar, fhidden) = self.callback_var(f.val);
        let (lv, hidden) = self.list_source(recv_expr, recv)?;
        let r = self.list_higher_order(name, lv, elem, fvar, !f.reader, out);
        self.release_source(lv, hidden);
        self.release_source(fvar, fhidden);
        r
    }

    /// `result.is_ok()` or `result.is_error()`.
    pub(super) fn result_state(
        &mut self,
        name: &str,
        recv: Val,
        alt: ms_mir::types::AltId,
    ) -> Result<Val, Error> {
        let want = if name == "is_ok" { "ok" } else { "error" };
        let case = self.b.m.alts[alt.index()]
            .cases
            .iter()
            .position(|c| c.name == want)
            .ok_or_else(|| Error::new("Result without ok/error cases"))?;
        let tag = self.b.alt_tag(recv.v);
        let k = self.b.iconst(case as i64);
        let v = self.b.icmp(ms_mir::ir::Cc::Eq, tag, k);
        // Only read: an owned result holding a resource (`open().is_ok()`) closes it.
        self.close_finish(recv);
        Ok(Val { v, own: false })
    }
}
