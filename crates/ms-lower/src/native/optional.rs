//! Optional and Result methods and runtime fault sites.

use super::*;

impl<'a> FnLower<'a> {
    /// A fault with no operands (the runtime formats the message).
    pub(super) fn runtime_fault(&mut self, sym: &str) {
        let ext = self.b.m.add_extern(ms_mir::ir::ExternDef {
            name: sym.to_string(),
            params: Vec::new(),
            ret: MTy::UNIT,
            noreturn: true,
            pure_: false,
            fresh: false,
            role: ms_mir::ir::ExternRole::None,
            leaf: crate::rtcall::rt_flags(sym).leaf,
            reads: crate::rtcall::rt_flags(sym).reads,
        });
        self.b.call_rt(ext, &[]);
        self.b.unreachable();
    }

    /// Faults for `get()` on an error result. When the error is a type whose first field is a
    /// `String` message (the standard `Error`), the fault names it; any other error type gets the
    /// generic text.
    pub(super) fn fault_result_get(&mut self, alt: ms_mir::types::AltId, r: Value, err: u32) {
        let payload = self.b.m.alts[alt.index()].cases[err as usize].fields[0].1;
        let message_field = match self.b.m.types.kind(payload) {
            TyKind::Type(rid) => {
                let first = self.b.m.type_defs[rid.index()].fields.first();
                first
                    .filter(|f| f.0 == "message" && f.1 == MTy::STR)
                    .map(|_| *rid)
            }
            _ => None,
        };
        let Some(rid) = message_field else {
            self.runtime_fault("msrt_fault_result_get");
            return;
        };
        let e = self.b.alt_get(alt, err, 0, r);
        let message = self.b.type_get(rid, 0, e);
        let head = self.b.str_lit("called Result.get() on error: ");
        let tail = self
            .b
            .str_lit("; check is_ok first, or pass a default: get(default: ...)");
        let joined = self
            .call_runtime("msrt_string_concat", &[head, message], MTy::STR)
            .and_then(|text| self.call_runtime("msrt_string_concat", &[text, tail], MTy::STR));
        let Ok(text) = joined else {
            self.runtime_fault("msrt_fault_result_get");
            return;
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
        self.b.call_rt(fault, &[text]);
        self.b.unreachable();
    }

    pub(super) fn optional_method(
        &mut self,
        out: MTy,
        at: ms_check::api::Pos,
        name: &str,
        recv: Val,
        inner: MTy,
        args: Vec<NArg>,
    ) -> Result<Val, Error> {
        let r = recv.v;
        let some = self.b.opt_is_some(r);
        match name {
            "is_some" | "is_none" => {
                let v = if name == "is_some" {
                    some
                } else {
                    self.b.unop(ms_mir::ir::Op::Not, some)
                };
                // Only read: an owned optional of a resource (`open().is_some()`) closes it.
                self.close_finish(recv);
                Ok(Val { v, own: false })
            }
            "get" if args.is_empty() && self.holds(inner) && !recv.own => {
                // The payload of a borrowed optional is a borrow of it: a reader uses it in
                // place and a `let` holds it as a lexical borrow. (An owned optional hands its
                // payload over below.)
                let (good, bad) = (self.b.new_block(), self.b.new_block());
                self.b.br_if(some, good, &[], bad, &[]);
                self.b.seal_block(good);
                self.b.seal_block(bad);
                self.b.switch_to(bad);
                self.b.fault(ms_mir::ir::FaultKind::NoneUnwrap);
                self.b.switch_to(good);
                let p = self.b.opt_get(r);
                self.boundary_reads.insert(p);
                self.borrow(recv);
                Ok(Val { v: p, own: false })
            }
            "get" => {
                let default = args.first().copied();
                self.two_ways(
                    some,
                    inner,
                    &mut |s| {
                        // An owned optional hands its payload over; a borrowed one is copied.
                        let o = if recv.own {
                            s.b.opt_unbox(r)
                        } else {
                            let p = s.b.opt_get(r);
                            s.owned_boundary(Val { v: p, own: false })
                        };
                        if let Some(d) = default {
                            // The default goes unused: an owned resource there closes now.
                            if d.wrapped {
                                s.close_finish(d.val);
                            } else {
                                s.finish(d.val);
                            }
                        }
                        Ok(Some(o))
                    },
                    &mut |s| match default {
                        Some(d) => {
                            let v = if d.wrapped {
                                s.owned_boundary(d.val)
                            } else {
                                let p = s.b.opt_unwrap(d.val.v);
                                s.finish(d.val);
                                p
                            };
                            s.finish(recv);
                            Ok(Some(v))
                        }
                        None => {
                            s.b.fault(ms_mir::ir::FaultKind::NoneUnwrap);
                            Ok(None)
                        }
                    },
                )
            }
            "get_or_else" => {
                let f = args
                    .first()
                    .copied()
                    .ok_or_else(|| Error::new("missing function"))?;
                self.two_ways(
                    some,
                    inner,
                    &mut |s| {
                        let p = s.b.opt_get(r);
                        let o = s.owned_boundary(Val { v: p, own: false });
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(o))
                    },
                    &mut |s| {
                        let v = s.b.call_ind(f.val.v, &[]);
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                )
            }
            "map" | "and_then" | "or_else" => {
                let f = args
                    .first()
                    .copied()
                    .ok_or_else(|| Error::new("missing function"))?;
                let by_map = name == "map";
                let keep = name == "or_else";
                self.two_ways(
                    some,
                    out,
                    &mut |s| {
                        if keep {
                            // Pass an owned wrapper through; copying a borrowed wrapper is
                            // the declared Optional boundary, not an implicit ordinary copy.
                            let o = s.owned_boundary(recv);
                            s.finish(f.val);
                            return Ok(Some(o));
                        }
                        let p = s.b.opt_get(r);
                        let fv = f.val.v;
                        let y = s.b.call_ind(fv, &[p]);
                        let v = if by_map { s.b.opt_some(y) } else { y };
                        // The callback only borrowed the payload: an owned temporary closes it.
                        s.close_finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                    &mut |s| {
                        let v = if keep {
                            s.b.call_ind(f.val.v, &[])
                        } else {
                            s.none_owned(out)
                        };
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                )
            }
            "ok_or" | "ok_or_else" => self.optional_ok_or(out, at, name, recv, args),
            _ => Err(Error::new(format!("unsupported Optional method {name}"))),
        }
    }

    /// `opt.ok_or(cause)` and `opt.ok_or_else(create)`.
    pub(super) fn optional_ok_or(
        &mut self,
        out: MTy,
        at: ms_check::api::Pos,
        name: &str,
        recv: Val,
        args: Vec<NArg>,
    ) -> Result<Val, Error> {
        let r = recv.v;
        let some = self.b.opt_is_some(r);
        let TyKind::Alt(res) = self.b.m.types.kind(out).clone() else {
            return Err(Error::new("ok_or without a Result type"));
        };
        let index = |m: &ms_mir::ir::Module, n: &str| {
            m.alts[res.index()].cases.iter().position(|c| c.name == n)
        };
        let (ok, err) = (
            index(self.b.m, "ok").ok_or_else(|| Error::new("not a Result"))?,
            index(self.b.m, "error").ok_or_else(|| Error::new("not a Result"))?,
        );
        let cause = args.first().copied();
        self.two_ways(
            some,
            out,
            &mut |s| {
                // Closing an unused cause can fault. Keep an owned resource receiver
                // intact and registered until that cleanup succeeds, before taking its payload.
                let held = if recv.own && cause.is_some_and(|c| c.val.own) {
                    s.hold_resource_temp(r)?
                } else {
                    None
                };
                if let Some(c) = cause {
                    // A borrowed cause remains with its caller.
                    s.close_finish(c.val);
                }
                let receiver = if let Some(key) = held {
                    let owned = s.take_resource_temp(key).0;
                    s.unhold_temp(key);
                    owned
                } else {
                    r
                };
                // No user evaluation follows retirement of the intact receiver guard.
                let o = if recv.own {
                    s.b.opt_unbox(receiver)
                } else {
                    let p = s.b.opt_get(receiver);
                    s.clone_value(p)
                };
                Ok(Some(s.b.alt_new(res, ok as u32, &[o])))
            },
            &mut |s| {
                let failure = if name == "ok_or_else" {
                    let f = cause.ok_or_else(|| Error::new("ok_or_else without a function"))?;
                    let v = s.b.call_ind(f.val.v, &[]);
                    s.finish(f.val);
                    v
                } else if let Some(c) = cause {
                    if c.wrapped {
                        s.owned(c.val)
                    } else {
                        let p = s.b.opt_unwrap(c.val.v);
                        s.finish(c.val);
                        p
                    }
                } else {
                    let et = s.b.m.alts[res.index()].cases[err].fields[0].1;
                    let cause = s.missing_value_at(et, at)?;
                    s.owned(cause)
                };
                s.finish(recv);
                Ok(Some(s.b.alt_new(res, err as u32, &[failure])))
            },
        )
    }

    /// Constructs the default `Error` (kind NotFound) naming the invoking source line.
    pub(crate) fn missing_value_at(
        &mut self,
        ty: MTy,
        at: ms_check::api::Pos,
    ) -> Result<Val, Error> {
        let TyKind::Type(er) = self.b.m.types.kind(ty).clone() else {
            return Err(Error::new("ok_or without a cause needs Error"));
        };
        let file = &self.b.m.files[self.file as usize];
        let base = file.rsplit('/').next().unwrap_or(file);
        let text = self
            .b
            .str_lit(&format!("missing value at {base}:{}", at.line));
        let text = self.owned(Val {
            v: text,
            own: false,
        });
        let v = self.error_type(er, "ENOENT", text, None)?;
        Ok(Val { v, own: true })
    }

    pub(super) fn result_method(
        &mut self,
        out: MTy,
        name: &str,
        recv: Val,
        alt: ms_mir::types::AltId,
        args: Vec<NArg>,
    ) -> Result<Val, Error> {
        // A borrowing result is read through its own alternative, so its borrowed cases are
        // never taken.
        let alt = match self.b.m.types.kind(self.ty_of(recv.v)) {
            TyKind::Alt(a) => *a,
            _ => alt,
        };
        let case = |m: &ms_mir::ir::Module, n: &str| {
            m.alts[alt.index()].cases.iter().position(|c| c.name == n)
        };
        let ok = case(self.b.m, "ok").ok_or_else(|| Error::new("not a Result"))? as u32;
        let err = case(self.b.m, "error").ok_or_else(|| Error::new("not a Result"))? as u32;
        let r = recv.v;
        let tag = self.b.alt_tag(r);
        let k = self.b.iconst(ok as i64);
        let is_ok = self.b.icmp(ms_mir::ir::Cc::Eq, tag, k);
        let payload = self.b.m.alts[alt.index()].cases[ok as usize].fields[0].1;
        if name == "get" && args.is_empty() && !recv.own && self.needs_drop(payload) {
            // The payload of a borrowed result is a borrow of it: a reader uses it in place, a
            // `let` holds it as a lexical borrow, and only a consumer copies it.
            let (good, bad) = (self.b.new_block(), self.b.new_block());
            self.b.br_if(is_ok, good, &[], bad, &[]);
            self.b.seal_block(good);
            self.b.seal_block(bad);
            self.b.switch_to(bad);
            self.fault_result_get(alt, r, err);
            self.b.switch_to(good);
            let p = self.b.alt_get(alt, ok, 0, r);
            self.boundary_reads.insert(p);
            return Ok(Val { v: p, own: false });
        }
        let f = args.first().copied();
        match name {
            "get" => {
                let default = f;
                self.two_ways(
                    is_ok,
                    out,
                    &mut |s| {
                        // An owned result hands its payload over; a borrowed one is copied.
                        let o = if recv.own && !s.b.m.alts[alt.index()].borrows(ok as usize) {
                            let p = s.b.alt_take(alt, ok, 0, r);
                            s.b.alt_release(alt, ok, 1, r);
                            p
                        } else {
                            // A `Clonable` payload is copied by `get(default)`; the bound is the declaration.
                            let p = s.b.alt_get(alt, ok, 0, r);
                            s.clone_value(p)
                        };
                        if let Some(d) = default {
                            // The default goes unused: an owned resource there closes now.
                            if d.wrapped {
                                s.close_finish(d.val);
                            } else {
                                s.finish(d.val);
                            }
                        }
                        Ok(Some(o))
                    },
                    &mut |s| match default {
                        Some(d) => {
                            let v = if d.wrapped {
                                s.owned_boundary(d.val)
                            } else {
                                let p = s.b.opt_unwrap(d.val.v);
                                s.finish(d.val);
                                p
                            };
                            s.finish(recv);
                            Ok(Some(v))
                        }
                        None => {
                            s.fault_result_get(alt, r, err);
                            Ok(None)
                        }
                    },
                )
            }
            "err"
                if (!recv.own || self.b.m.alts[alt.index()].borrows(err as usize))
                    && self.needs_drop(out) =>
            {
                // A borrowed result borrows its error, and so does a borrowing temporary whose
                // error case lives in its source; a consumer that keeps it must clone it.
                let (bad, good) = (self.b.new_block(), self.b.new_block());
                self.b.br_if(is_ok, bad, &[], good, &[]);
                self.b.seal_block(good);
                self.b.seal_block(bad);
                self.b.switch_to(bad);
                self.runtime_fault("msrt_fault_result_err");
                self.b.switch_to(good);
                let p = self.b.alt_get(alt, err, 0, r);
                self.boundary_reads.insert(p);
                if recv.own {
                    // The temporary's borrowed case owns nothing: dropping it leaves the error.
                    self.finish(recv);
                }
                Ok(Val { v: p, own: false })
            }
            "err" => self.two_ways(
                is_ok,
                out,
                &mut |s| {
                    s.runtime_fault("msrt_fault_result_err");
                    Ok(None)
                },
                &mut |s| {
                    let o = s.take_alt_field(alt, err, 0, recv);
                    Ok(Some(o))
                },
            ),
            "or_else" => {
                let f = f.ok_or_else(|| Error::new("missing function"))?;
                self.two_ways(
                    is_ok,
                    out,
                    &mut |s| {
                        // An owned result passes through whole; a borrowed `Clonable` one is cloned.
                        let o = if recv.own { r } else { s.clone_value(r) };
                        s.finish(f.val);
                        Ok(Some(o))
                    },
                    &mut |s| {
                        let p = s.b.alt_get(alt, err, 0, r);
                        let v = s.b.call_ind(f.val.v, &[p]);
                        s.close_finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                )
            }
            "map_error" => {
                let f = f.ok_or_else(|| Error::new("missing function"))?;
                let TyKind::Alt(oa) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("map_error without Result result"));
                };
                let (out_ok, out_err) = {
                    let cs = &self.b.m.alts[oa.index()];
                    (
                        cs.ok_case().unwrap_or(0) as u32,
                        cs.error_case().unwrap_or(1) as u32,
                    )
                };
                self.two_ways(
                    is_ok,
                    out,
                    &mut |s| {
                        let po = s.take_alt_field_through(alt, ok, 0, recv);
                        let v = s.b.alt_new(oa, out_ok, &[po]);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                    &mut |s| {
                        let p = s.b.alt_get(alt, err, 0, r);
                        let y = s.b.call_ind(f.val.v, &[p]);
                        let v = s.b.alt_new(oa, out_err, &[y]);
                        s.close_finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                )
            }
            "get_or_else" => {
                let f = f.ok_or_else(|| Error::new("missing function"))?;
                self.two_ways(
                    is_ok,
                    out,
                    &mut |s| {
                        let p = s.b.alt_get(alt, ok, 0, r);
                        let o = s.owned_boundary(Val { v: p, own: false });
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(o))
                    },
                    &mut |s| {
                        let p = s.b.alt_get(alt, err, 0, r);
                        let v = s.b.call_ind(f.val.v, &[p]);
                        s.close_finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                )
            }
            "map" | "and_then" => {
                let f = f.ok_or_else(|| Error::new("missing function"))?;
                let TyKind::Alt(oa) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("Result method without Result result"));
                };
                let o_ok = case(self.b.m, "ok").unwrap_or(0) as u32;
                let o_err = case(self.b.m, "error").unwrap_or(1) as u32;
                let _ = (o_ok, o_err);
                let (out_ok, out_err) = {
                    let cs = &self.b.m.alts[oa.index()];
                    (
                        cs.ok_case().unwrap_or(0) as u32,
                        cs.error_case().unwrap_or(1) as u32,
                    )
                };
                let is_map = name == "map";
                self.two_ways(
                    is_ok,
                    out,
                    &mut |s| {
                        let p = s.b.alt_get(alt, ok, 0, r);
                        let y = s.b.call_ind(f.val.v, &[p]);
                        let v = if is_map {
                            s.b.alt_new(oa, out_ok, &[y])
                        } else {
                            y
                        };
                        s.close_finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                    &mut |s| {
                        let po = s.take_alt_field_through(alt, err, 0, recv);
                        let v = s.b.alt_new(oa, out_err, &[po]);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                )
            }
            "to_optional" => {
                let TyKind::Opt(_) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("to_optional without Optional result"));
                };
                self.two_ways(
                    is_ok,
                    out,
                    &mut |s| {
                        let po = s.take_alt_field_through(alt, ok, 0, recv);
                        let v = s.b.opt_some(po);
                        Ok(Some(v))
                    },
                    &mut |s| {
                        let v = s.none_owned(out);
                        s.close_finish(recv);
                        Ok(Some(v))
                    },
                )
            }
            "error" => {
                let TyKind::Opt(_) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("error without Optional result"));
                };
                self.two_ways(
                    is_ok,
                    out,
                    &mut |s| {
                        let v = s.none_owned(out);
                        s.close_finish(recv);
                        Ok(Some(v))
                    },
                    &mut |s| {
                        let po = s.take_alt_field_through(alt, err, 0, recv);
                        let v = s.b.opt_some(po);
                        Ok(Some(v))
                    },
                )
            }
            _ => Err(Error::new(format!("unsupported Result method {name}"))),
        }
    }

    /// A variable or a field chain from one.
    pub fn is_place(&self, e: &Expr) -> bool {
        let cur = crate::mutation::place_base(self.syms, &self.hir, e);
        matches!(&cur.kind, ExprKind::Name(_))
            && matches!(self.hir.resolution(cur), Resolution::Local(_))
    }

    pub(crate) fn mutate_any(
        &mut self,
        name: &str,
        old: Value,
        decl: &[ct::Param],
        args: &[NArg],
        copy_result: bool,
        result_ty: MTy,
    ) -> Result<(Value, Option<Val>), Error> {
        if let Some((new, result)) = self.guarded_list_mutation(name, old, args)? {
            debug_assert!(
                !copy_result,
                "list insertion methods never return the receiver"
            );
            return Ok((new, result));
        }
        // Swapping elements that need no drop (scalars, optional scalars, plain types) is two
        // loads and two stores; the rest move through the runtime without a copy.
        let plain_swap = name == "swap"
            && matches!(self.b.m.types.kind(self.ty_of(old)), TyKind::List(e) if !self.needs_drop(*e));
        let runtime_only = !plain_swap
            && !matches!(
                name,
                "append"
                    | "set"
                    | "replace"
                    | "prepend"
                    | "insert"
                    | "remove"
                    | "pop"
                    | "reverse"
                    | "sort"
            );
        let is_list = matches!(self.b.m.types.kind(self.ty_of(old)), TyKind::List(_));
        // The runtime shifts the tail in place; rebuilding the list from slices copies every element.
        let in_place = matches!(name, "insert" | "remove" | "reverse");
        if !is_list || runtime_only || in_place {
            return self.mutate_rt(name, old, decl, args, copy_result, result_ty);
        }
        let (new, r) = self.mutate_list(name, old, args)?;
        if r.is_none() && copy_result {
            let v = self.clone_value(new);
            return Ok((new, Some(Val { v, own: true })));
        }
        Ok((new, r))
    }

    /// An owned element for a collection, wrapped when the checker converted it to an optional.
    pub(crate) fn element_value(&mut self, a: &NArg) -> Value {
        // Fallback ownership extraction. Protected direct-list stores bypass this helper and
        // retain the registered incoming slot until the native mutation succeeds.
        let v = if self.resource_temps.contains_key(&a.val.v) {
            let key = a.val.v;
            let (v, _) = self.take_resource_temp(key);
            self.unhold_temp(key);
            v
        } else {
            self.owned(a.val)
        };
        if a.wrapped { self.b.opt_some(v) } else { v }
    }
}
