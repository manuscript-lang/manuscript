//! HTTP handlers and methods across the runtime boundary (`ms-std-net/ABI.md`, "http").
//!
//! `serve` and `serve_stream` take the handler as one closure object whose code word the
//! server calls: `code(closure, request, response)` for a buffered handler and
//! `code(closure, exchange, err) -> status` for a streaming one. The wrapper closure built
//! here captures the user's handler and converts between the wire records and the language
//! values. `HttpMethod` crosses as its token text.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, FuncKind, Imm, Mode, Op, Param};
use ms_mir::types::{AltId, Ty as MTy, TyKind};

/// The cases of `HttpMethod` that carry no text, in declaration order.
const METHOD_TOKENS: [&str; 9] = [
    "GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "CONNECT", "OPTIONS", "TRACE",
];

fn pointer(mode: Mode) -> Param {
    Param { ty: MTy::PTR, mode }
}

impl FnLower<'_> {
    /// The function the cleanup stack calls to release `ty` when a fault abandons the frame
    /// that owns it.
    fn drop_thunk(&mut self, ty: MTy) -> ms_mir::ir::FuncId {
        let key = format!("drop:{}", ty.index());
        if let Some(f) = self.cx.helpers.get(&key) {
            return *f;
        }
        let ps = vec![Param {
            ty,
            mode: Mode::Own,
        }];
        let mut b = FuncBuilder::new(self.b.m, "drop", ps, MTy::UNIT);
        b.func_mut().linkage = ms_mir::ir::Linkage::Internal;
        b.func_mut().kind = FuncKind::Normal;
        let v = b.params()[0];
        b.emit(Op::Drop, &[v], Imm::None, None);
        let u = b.unit();
        b.ret(Some(u));
        let f = b.into_func();
        let id = self.b.m.add_func(f);
        self.cx.helpers.insert(key, id);
        id
    }

    /// The token text of an `HttpMethod` value.
    pub(crate) fn method_text(&mut self, method: Val) -> Result<Val, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(self.ty_of(method.v)).clone() else {
            return Err(Error::new("an HTTP method is not an alternative"));
        };
        let v = self.borrow(method);
        let tag = self.b.alt_tag(v);
        let r = self.method_token(a, v, tag, 0)?;
        Ok(r)
    }

    fn method_token(
        &mut self,
        a: AltId,
        method: ms_mir::ir::Value,
        tag: ms_mir::ir::Value,
        from: usize,
    ) -> Result<Val, Error> {
        if from >= METHOD_TOKENS.len() {
            let custom = (METHOD_TOKENS.len()) as u32;
            let text = self.b.alt_get(a, custom, 0, method);
            return Ok(Val {
                v: text,
                own: false,
            });
        }
        let k = self.b.iconst(from as i64);
        let hit = self.b.icmp(Cc::Eq, tag, k);
        self.two_ways(
            hit,
            MTy::STR,
            &mut |s| {
                let t = s.b.str_lit(METHOD_TOKENS[from]);
                Ok(Some(s.owned(Val { v: t, own: false })))
            },
            &mut |s| {
                let r = s.method_token(a, method, tag, from + 1)?;
                Ok(Some(s.owned(r)))
            },
        )
    }

    /// The `HttpMethod` named by the token `text` (an owned alternative).
    pub(crate) fn method_from_text(
        &mut self,
        a: AltId,
        text: ms_mir::ir::Value,
        from: usize,
    ) -> Result<ms_mir::ir::Value, Error> {
        let ty = self.b.m.types.alt(a);
        if from >= METHOD_TOKENS.len() {
            let own = self.owned(Val {
                v: text,
                own: false,
            });
            return Ok(self.b.alt_new(a, METHOD_TOKENS.len() as u32, &[own]));
        }
        let token = self.b.str_lit(METHOD_TOKENS[from]);
        let hit = self.call_runtime("msrt_string_eq", &[text, token], MTy::BOOL)?;
        let r = self.two_ways(
            hit,
            ty,
            &mut |s| Ok(Some(s.b.alt_new(a, from as u32, &[]))),
            &mut |s| s.method_from_text(a, text, from + 1).map(Some),
        )?;
        Ok(r.v)
    }

    /// The handler closure the server calls, wrapping the user's `handler`; an owned
    /// temporary released at the end of the statement.
    pub(crate) fn handler_env(
        &mut self,
        streaming: bool,
        handler: Val,
    ) -> Result<ms_mir::ir::Value, Error> {
        let user_ty = self.ty_of(handler.v);
        let TyKind::Fn(params, result) = self.b.m.types.kind(user_ty).clone() else {
            return Err(Error::new("a server handler is not a function"));
        };
        let key = format!("serve-thunk:{streaming}:{}", user_ty.0);
        let thunk = match self.cx.helpers.get(&key) {
            Some(t) => *t,
            None => {
                let f = if streaming {
                    self.stream_thunk(user_ty, params[0], result)?
                } else {
                    self.buffered_thunk(user_ty, params[0])?
                };
                let id = self.b.m.add_func(f);
                self.cx.helpers.insert(key, id);
                id
            }
        };
        let fty = if streaming {
            let ht = crate::natiface::handle_ty(self.b.m);
            self.b.m.types.func(vec![ht, MTy::PTR], MTy::INT)
        } else {
            self.b.m.types.func(vec![MTy::PTR, MTy::PTR], MTy::UNIT)
        };
        let user = self.owned(handler);
        let closure = self
            .b
            .emit(Op::ClosureNew, &[user], Imm::Func(thunk), Some(fty))
            .expect("closure");
        self.temps.push(closure);
        Ok(closure)
    }

    /// `code(closure, request, response)`: reads a `RequestWire`, calls the handler and
    /// moves its `HttpResponse` into the `ResponseWire`.
    fn buffered_thunk(&mut self, user_ty: MTy, request: MTy) -> Result<ms_mir::ir::Func, Error> {
        let TyKind::Rec(rid) = self.b.m.types.kind(request).clone() else {
            return Err(Error::new("a request is not a record"));
        };
        let fields = self.b.m.records[rid.index()].fields.clone();
        // `RequestWire`: method, path, query, protocol, headers, body.
        let by_name = |n: &str| {
            fields
                .iter()
                .position(|f| f.0 == n)
                .ok_or_else(|| Error::new(format!("a request without {n}")))
        };
        let wire: Vec<(String, MTy)> = [
            ("method", MTy::STR),
            ("path", MTy::STR),
            ("query", MTy::STR),
            ("protocol", MTy::STR),
            ("headers", fields[by_name("headers")?].1),
            ("body", MTy::BYTES),
        ]
        .iter()
        .map(|(n, t)| (n.to_string(), *t))
        .collect();
        let (wire_id, wire_ty) = self.b.m.add_record("RequestWire", wire);
        let TyKind::Alt(method_alt) = self.b.m.types.kind(fields[by_name("method")?].1).clone()
        else {
            return Err(Error::new("a request method is not an alternative"));
        };
        let order: Vec<usize> = fields
            .iter()
            .map(|f| match f.0.as_str() {
                "method" => 0,
                "path" => 1,
                "query" => 2,
                "protocol" => 3,
                "headers" => 4,
                _ => 5,
            })
            .collect();
        let hir = self.hir.clone();
        let b = FuncBuilder::new(
            self.b.m,
            "serve.buffered",
            vec![
                pointer(Mode::Borrow),
                pointer(Mode::Borrow),
                pointer(Mode::Borrow),
            ],
            MTy::UNIT,
        );
        let mut fl = FnLower::new(self.cx, b, hir, Default::default(), 0, MTy::UNIT);
        fl.b.func_mut().kind = FuncKind::Closure {
            captures: vec![user_ty],
        };
        let p = fl.b.params();
        let handler =
            fl.b.emit(Op::ClosureCap, &[p[0]], Imm::Idx(0), Some(user_ty))
                .expect("capture");
        let loaded =
            fl.b.emit(Op::Take, &[p[1]], Imm::Ty(wire_ty), Some(wire_ty))
                .expect("take");
        let mut values = Vec::new();
        for (k, source) in order.iter().enumerate() {
            let field = fl.b.rec_get(wire_id, *source as u32, loaded);
            let v = if k == 0 {
                fl.method_from_text(method_alt, field, 0)?
            } else {
                fl.owned(Val {
                    v: field,
                    own: false,
                })
            };
            values.push(v);
        }
        let req = fl.b.rec_new(rid, &values);
        fl.drop_value(loaded);
        // A fault in the handler abandons this frame; the cleanup stack releases the request.
        let rec_ty = fl.ty_of(req);
        let thunk = fl.drop_thunk(rec_ty);
        let handle =
            fl.b.emit(Op::CleanupPush, &[req], Imm::Func(thunk), Some(MTy::INT))
                .expect("handle");
        let response = fl.b.call_ind(handler, &[req]);
        let _ = fl.call_runtime("msrt_cleanup_discard", &[handle], MTy::UNIT);
        fl.drop_value(req);
        fl.b.emit(Op::Put, &[p[2], response], Imm::None, None);
        let unit = fl.b.unit();
        fl.emit_return(Some(Val {
            v: unit,
            own: false,
        }));
        Ok(fl.b.into_func())
    }

    /// `code(closure, exchange, err) -> status`: wraps the exchange handle in its
    /// interface, calls the handler and reports its `HttpError` as a status.
    fn stream_thunk(
        &mut self,
        user_ty: MTy,
        exchange: MTy,
        result: MTy,
    ) -> Result<ms_mir::ir::Func, Error> {
        let TyKind::Iface(iface) = self.b.m.types.kind(exchange).clone() else {
            return Err(Error::new("an exchange is not an interface"));
        };
        let TyKind::Alt(ra) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("a stream handler does not return a Result"));
        };
        let ok = self.ok_case_index(ra)?;
        let err_case = 1 - ok;
        let hir = self.hir.clone();
        let vt = self
            .cx
            .handle_vtable_of(self.b.m, &hir, "msrt_http_exchange", iface)?;
        let ht = crate::natiface::handle_ty(self.b.m);
        let b = FuncBuilder::new(
            self.b.m,
            "serve.stream",
            vec![
                pointer(Mode::Borrow),
                Param {
                    ty: ht,
                    mode: Mode::Borrow,
                },
                pointer(Mode::Borrow),
            ],
            MTy::INT,
        );
        let mut fl = FnLower::new(self.cx, b, hir, Default::default(), 0, MTy::INT);
        fl.b.func_mut().kind = FuncKind::Closure {
            captures: vec![user_ty],
        };
        let p = fl.b.params();
        let handler =
            fl.b.emit(Op::ClosureCap, &[p[0]], Imm::Idx(0), Some(user_ty))
                .expect("capture");
        // The server keeps its reference; the interface value takes its own.
        let handle = fl.owned(Val {
            v: p[1],
            own: false,
        });
        let ex =
            fl.b.emit(Op::IfaceNew, &[handle], Imm::Vtable(vt), Some(exchange))
                .expect("iface");
        let r = fl.b.call_ind(handler, &[ex]);
        fl.drop_value(ex);
        let tag = fl.b.alt_tag(r);
        let ok_tag = fl.b.iconst(ok as i64);
        let is_ok = fl.b.icmp(Cc::Eq, tag, ok_tag);
        let status = fl.two_ways(
            is_ok,
            MTy::INT,
            &mut |s| Ok(Some(s.b.iconst(0))),
            &mut |s| {
                let e = s.b.alt_get(ra, err_case as u32, 0, r);
                s.error_status(e, p[2]).map(Some)
            },
        )?;
        fl.drop_value(r);
        fl.emit_return(Some(status));
        Ok(fl.b.into_func())
    }

    /// The status of an error alternative `e` (`1 + the case index`); a case that carries text
    /// (`Failed(message)`) also stores its text through `err`.
    pub(crate) fn error_status(
        &mut self,
        e: ms_mir::ir::Value,
        err: ms_mir::ir::Value,
    ) -> Result<ms_mir::ir::Value, Error> {
        let ea = self.alt_of(e)?;
        let etag = self.b.alt_tag(e);
        let texts: Vec<usize> = (0..self.b.m.alts[ea.index()].cases.len())
            .filter(|i| self.b.m.alts[ea.index()].cases[*i].fields.len() == 1)
            .collect();
        for case in texts {
            let k = self.b.iconst(case as i64);
            let hit = self.b.icmp(Cc::Eq, etag, k);
            self.two_ways(
                hit,
                MTy::INT,
                &mut |s| {
                    let text = s.b.alt_get(ea, case as u32, 0, e);
                    let text = s.owned(Val {
                        v: text,
                        own: false,
                    });
                    s.b.emit(Op::Put, &[err, text], Imm::None, None);
                    Ok(Some(s.b.iconst(0)))
                },
                &mut |s| Ok(Some(s.b.iconst(0))),
            )?;
        }
        let one = self.b.iconst(1);
        Ok(self.b.binop(Op::IAdd, etag, one))
    }
}
