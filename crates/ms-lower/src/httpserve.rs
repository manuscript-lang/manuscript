//! HTTP handlers and methods across the runtime boundary (`ms-std-net/ABI.md`, "http").
//!
//! `serve` takes the handler as one closure object whose code word the server calls:
//! `code(closure, exchange, err) -> status`. The wrapper closure built
//! here captures the user's handler and converts between the wire types and the language
//! values. `HttpMethod` crosses as its token text.

use crate::Error;
use crate::cx::HelperKey;
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

/// The kinds an HTTP handler failure keeps; any other kind is `EIO`, which carries its text.
pub(crate) const HTTP_KINDS: [&str; 6] = [
    "EINVAL",
    "EBADMSG",
    "EOVERFLOW",
    "EACCES",
    "EBADF",
    "ETIMEDOUT",
];

impl FnLower<'_> {
    /// The `HttpMethod` named by the token `text` (an owned alternative).
    pub(crate) fn method_from_text(
        &mut self,
        a: AltId,
        text: ms_mir::ir::Value,
        from: usize,
    ) -> Result<ms_mir::ir::Value, Error> {
        let ty = self.b.m.types.alt(a);
        if from >= METHOD_TOKENS.len() {
            let own = self.owned_boundary(Val {
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

    /// The handler closure the server calls, wrapping the user's `handler`, which the checker
    /// hands over owned (`msstd_http_serving_new` keeps its callback); the serving owns the
    /// closure from here and drops it when it ends.
    pub(crate) fn handler_env(
        &mut self,
        handler: Val,
        exchange: MTy,
    ) -> Result<ms_mir::ir::Value, Error> {
        let user_ty = self.ty_of(handler.v);
        let TyKind::Fn(_, result) = self.b.m.types.kind(user_ty).clone() else {
            return Err(Error::new("a server handler is not a function"));
        };
        let key = HelperKey::ServeThunk(user_ty);
        let thunk = match self.cx.helpers.get(&key) {
            Some(t) => *t,
            None => {
                let f = self.stream_thunk(user_ty, exchange, result)?;
                let id = self.b.m.add_func(f);
                self.cx.helpers.insert(key, id);
                id
            }
        };
        let ht = crate::natiface::handle_ty(self.b.m);
        let fty = self.b.m.types.func(vec![ht, MTy::PTR], MTy::INT);
        let user = self.owned(handler);
        let closure = self
            .b
            .emit(Op::ClosureNew, &[user], Imm::Func(thunk), Some(fty))
            .expect("closure");
        Ok(closure)
    }

    /// `code(closure, exchange, err) -> status`: wraps the exchange handle in its
    /// interface, calls the handler with the address of a slot holding that view (its
    /// `var HttpExchange` parameter) and reports its `Error` as a status.
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
            .handle_vtable_of(self.b.m, &hir, "msstd_http_exchange", iface)?;
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
        // The server keeps the exchange alive for the call: the handler sees a view of it in a
        // slot it may replace (middleware wraps the exchange in place); whatever the slot holds
        // afterwards is dropped here, and a view frees nothing.
        let ex = fl.b.iface_borrow(vt, p[1], exchange);
        let slot =
            fl.b.emit(Op::Slot, &[], Imm::Ty(exchange), Some(MTy::PTR))
                .expect("slot");
        fl.move_into(slot, ex);
        let r = fl.b.call_ind(handler, &[slot]);
        let back = fl.move_out(slot, exchange);
        fl.drop_value(back);
        let tag = fl.b.alt_tag(r);
        let ok_tag = fl.b.iconst(ok as i64);
        let is_ok = fl.b.icmp(Cc::Eq, tag, ok_tag);
        let status = fl.two_ways(
            is_ok,
            MTy::INT,
            &mut |s| Ok(Some(s.b.iconst(0))),
            &mut |s| {
                let e = s.b.alt_get(ra, err_case as u32, 0, r);
                s.error_status(e, p[2], &HTTP_KINDS).map(Some)
            },
        )?;
        fl.drop_value(r);
        fl.emit_return(Some(status));
        Ok(fl.b.into_func())
    }

    /// The shared `ms-rt-abi` status of an `Error` value `e` whose kind is one of `kinds`. Any
    /// other kind becomes `STATUS_FAILED`, which also stores the message through `err`.
    pub(crate) fn error_status(
        &mut self,
        e: ms_mir::ir::Value,
        err: ms_mir::ir::Value,
        kinds: &[&str],
    ) -> Result<ms_mir::ir::Value, Error> {
        let kind = self.b.type_get(er_of(self, e)?, 1, e);
        let present = self.b.opt_is_some(kind);
        let r = self.two_ways(
            present,
            MTy::INT,
            &mut |s| {
                let code = s.b.opt_get(kind);
                s.kind_status(e, code, err, kinds, 0).map(Some)
            },
            &mut |s| s.failed_status(e, err).map(Some),
        )?;
        Ok(r.v)
    }

    /// `STATUS_FAILED`, storing the message of the `Error` `e` through `err`.
    fn failed_status(
        &mut self,
        e: ms_mir::ir::Value,
        err: ms_mir::ir::Value,
    ) -> Result<ms_mir::ir::Value, Error> {
        let er = er_of(self, e)?;
        let text = self.b.type_get(er, 0, e);
        let text = self.owned_boundary(Val {
            v: text,
            own: false,
        });
        self.b.emit(Op::Put, &[err, text], Imm::None, None);
        Ok(self.b.iconst(i64::from(ms_rt_abi::STATUS_FAILED)))
    }

    fn kind_status(
        &mut self,
        e: ms_mir::ir::Value,
        kind: ms_mir::ir::Value,
        err: ms_mir::ir::Value,
        kinds: &[&str],
        at: usize,
    ) -> Result<ms_mir::ir::Value, Error> {
        let Some(code) = kinds.get(at).copied() else {
            return self.failed_status(e, err);
        };
        let lit = self.b.str_lit(code);
        let hit = self.call_runtime("msrt_string_eq", &[kind, lit], MTy::BOOL)?;
        let r = self.two_ways(
            hit,
            MTy::INT,
            &mut |s| Ok(Some(s.b.iconst(kind_status_number(code)))),
            &mut |s| s.kind_status(e, kind, err, kinds, at + 1).map(Some),
        )?;
        Ok(r.v)
    }
}

fn er_of(s: &FnLower<'_>, e: ms_mir::ir::Value) -> Result<ms_mir::types::TypeId, Error> {
    match s.b.m.types.kind(s.ty_of(e)) {
        TyKind::Type(er) => Ok(*er),
        _ => Err(Error::new("a stream method must fail with an Error")),
    }
}

/// The shared status number of an error code: the first row of the status table.
fn kind_status_number(kind: &str) -> i64 {
    crate::rtcall::status_table("")
        .iter()
        .find(|(_, k, _)| *k == kind)
        .map_or(i64::from(ms_rt_abi::STATUS_FAILED), |(n, _, _)| *n)
}
