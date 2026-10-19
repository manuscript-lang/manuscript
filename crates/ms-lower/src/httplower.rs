//! HTTP glue: method tokens, and the adapters that let the runtime call handler closures
//! (`ms-std-net/ABI.md`, "Handler thunks").

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Val};
use ms_check::hir::ModuleHir;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, Func, FuncId, FuncKind, Imm, Mode, Module, Op, Param, Value};
use ms_mir::types::{AltId, RecId, Ty as MTy, TyKind};
use std::rc::Rc;

/// Standard `HttpMethod` cases; `Custom` follows them.
const STANDARD_METHODS: i64 = 9;

/// A handler adapter waiting to be lowered.
pub struct HttpAdapterJob {
    /// A streaming handler (`fn(HttpExchange) Result[Unit, HttpError]`), else buffered.
    pub stream: bool,
    /// The handler's function type.
    pub handler: MTy,
    /// Module the use is written in.
    pub hir: Rc<ModuleHir>,
}

impl FnLower<'_> {
    /// Whether `t` is the `HttpMethod` alternative.
    pub(crate) fn is_http_method(&self, t: MTy) -> bool {
        matches!(self.b.m.types.kind(t), TyKind::Alt(a) if self.b.m.alts[a.index()].name.ends_with("HttpMethod"))
    }

    /// The method token of an `HttpMethod` value, as an owned string.
    pub(crate) fn method_text(&mut self, v: Value) -> Result<Value, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(self.ty_of(v)).clone() else {
            return Err(Error::new("not an HttpMethod"));
        };
        let custom = self.b.m.alts[a.index()].cases.len() as i64 - 1;
        let tag = self.b.alt_tag(v);
        let k = self.b.iconst(custom);
        let is_custom = self.b.icmp(Cc::Eq, tag, k);
        let r = self.two_ways(
            is_custom,
            MTy::STR,
            &mut |s| {
                let f = s.b.alt_get(a, custom as u32, 0, v);
                Ok(Some(
                    s.b.emit(Op::Copy, &[f], Imm::None, Some(MTy::STR))
                        .expect("copy"),
                ))
            },
            &mut |s| {
                Ok(Some(s.call_runtime(
                    "msrt_http_method_token",
                    &[tag],
                    MTy::STR,
                )?))
            },
        )?;
        Ok(r.v)
    }

    /// The `HttpMethod` named by an owned method token.
    pub(crate) fn method_from_text(&mut self, text: Value, ty: MTy) -> Result<Value, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(ty).clone() else {
            return Err(Error::new("not an HttpMethod"));
        };
        let raw = self.call_runtime("msrt_http_method_index", &[text], MTy::INT)?;
        let mask = self.b.iconst(0xff);
        let idx = self.b.binop(Op::And, raw, mask);
        let limit = self.b.iconst(STANDARD_METHODS);
        let standard = self.b.icmp(Cc::Lt, idx, limit);
        let custom = STANDARD_METHODS as u32;
        let r = self.two_ways(
            standard,
            ty,
            &mut |s| {
                s.b.emit(Op::Drop, &[text], Imm::None, None);
                s.standard_method(a, idx, 0).map(|v| Some(v.v))
            },
            &mut |s| Ok(Some(s.b.alt_new(a, custom, &[text]))),
        )?;
        Ok(r.v)
    }

    /// The standard method whose case index is `idx`.
    fn standard_method(&mut self, a: AltId, idx: Value, i: i64) -> Result<Val, Error> {
        if i + 1 == STANDARD_METHODS {
            let v = self.b.alt_new(a, i as u32, &[]);
            return Ok(Val { v, own: true });
        }
        let k = self.b.iconst(i);
        let hit = self.b.icmp(Cc::Eq, idx, k);
        let ty = self.b.m.types.alt(a);
        self.two_ways(
            hit,
            ty,
            &mut |s| Ok(Some(s.b.alt_new(a, i as u32, &[]))),
            &mut |s| Ok(Some(s.standard_method(a, idx, i + 1)?.v)),
        )
    }

    /// Methods of HTTP types that read the representation directly.
    pub(crate) fn http_inline_method(
        &mut self,
        native: &str,
        recv: Val,
    ) -> Result<Option<Val>, Error> {
        if native != "http/client_response_metadata" {
            return Ok(None);
        }
        let TyKind::Rec(rid) = self.b.m.types.kind(self.ty_of(recv.v)).clone() else {
            return Err(Error::new("ClientResponse is not a record"));
        };
        let r = self.borrow(recv);
        let head = self.b.rec_get(rid, 0, r);
        Ok(Some(Val {
            v: head,
            own: false,
        }))
    }

    /// A closure the runtime can call as a handler thunk: it captures `handler` and takes the
    /// runtime's pointers (`BufferedThunk` or `StreamThunk`).
    pub(crate) fn http_adapter(&mut self, handler: Val, stream: bool) -> Result<Val, Error> {
        let hty = self.ty_of(handler.v);
        let TyKind::Fn(ptys, _) = self.b.m.types.kind(hty).clone() else {
            return Err(Error::new("a handler must be a function"));
        };
        let key = format!("http-adapter:{stream}:{}", hty.0);
        let (id, fty) = match self.cx.helpers.get(&key) {
            Some(f) => {
                let ft = self.b.m.funcs[f.index()].clone();
                (*f, self.adapter_type(&ft, stream))
            }
            None => {
                let mut ps = vec![Param {
                    ty: MTy::PTR,
                    mode: Mode::Borrow,
                }];
                let ret = if stream { MTy::INT } else { MTy::UNIT };
                if stream {
                    let handle = match self.b.m.types.kind(ptys[0]).clone() {
                        TyKind::Iface(i) => self.cx.handle_ty(self.b.m, i),
                        _ => return Err(Error::new("a streaming handler takes an exchange")),
                    };
                    ps.push(Param {
                        ty: handle,
                        mode: Mode::Borrow,
                    });
                    ps.push(Param {
                        ty: MTy::PTR,
                        mode: Mode::Borrow,
                    });
                } else {
                    ps.extend([
                        Param {
                            ty: MTy::PTR,
                            mode: Mode::Borrow,
                        },
                        Param {
                            ty: MTy::PTR,
                            mode: Mode::Borrow,
                        },
                    ]);
                }
                let mut f = Func::new("http.adapter", ps, ret);
                f.kind = FuncKind::Closure {
                    captures: vec![hty],
                };
                let ft = f.clone();
                let id = self.b.m.add_func(f);
                self.cx.queue.push(Job {
                    func: id,
                    kind: JobKind::HttpAdapter(Rc::new(HttpAdapterJob {
                        stream,
                        handler: hty,
                        hir: self.hir.clone(),
                    })),
                });
                self.cx.helpers.insert(key, id);
                (id, self.adapter_type(&ft, stream))
            }
        };
        let captured = self.owned(handler);
        let v = self
            .b
            .emit(Op::ClosureNew, &[captured], Imm::Func(id), Some(fty))
            .expect("closure");
        Ok(Val { v, own: true })
    }

    /// The function type of the adapter closure (the closure object excluded).
    fn adapter_type(&mut self, f: &Func, _stream: bool) -> MTy {
        let params: Vec<MTy> = f.params.iter().skip(1).map(|p| p.ty).collect();
        self.b.m.types.func(params, f.ret)
    }
}

/// Lowers the body of a queued handler adapter.
pub(crate) fn build_http_adapter(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &HttpAdapterJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let file = m.add_file(job.hir.data.file.as_str());
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    b.func_mut().kind = proto.kind.clone();
    let mut fl = FnLower::new(cx, b, job.hir.clone(), ct::Subst::new(), file, proto.ret);
    let result = if job.stream {
        lower_stream_adapter(&mut fl, job)
    } else {
        lower_buffered_adapter(&mut fl, job)
    };
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

/// A value moved out of field `i` of the record image at `base`.
fn take_field(fl: &mut FnLower<'_>, base: Value, rid: RecId, i: u32, ty: MTy) -> Value {
    let p =
        fl.b.emit(Op::PtrField, &[base], Imm::Field(rid, i), Some(MTy::PTR))
            .expect("field");
    fl.b.emit(Op::Take, &[p], Imm::Ty(ty), Some(ty))
        .expect("take")
}

/// `RequestWire`: the method token, path, query, protocol, headers handle and body.
fn lower_buffered_adapter(fl: &mut FnLower<'_>, job: &HttpAdapterJob) -> Result<(), Error> {
    let params = fl.b.params();
    let TyKind::Fn(ptys, _) = fl.b.m.types.kind(job.handler).clone() else {
        return Err(Error::new("a handler must be a function"));
    };
    let (req_ty, resp_ptr) = (ptys[0], params[2]);
    let TyKind::Rec(request) = fl.b.m.types.kind(req_ty).clone() else {
        return Err(Error::new("a handler takes an HttpRequest"));
    };
    let fields = fl.b.m.records[request.index()].fields.clone();
    let headers_ty = fields[3].1;
    let image = fields_image(
        fl,
        &[
            MTy::STR,
            MTy::STR,
            MTy::STR,
            MTy::STR,
            headers_ty,
            MTy::BYTES,
        ],
    );
    let w = params[1];
    let method_text = take_field(fl, w, image, 0, MTy::STR);
    let path = take_field(fl, w, image, 1, MTy::STR);
    let query = take_field(fl, w, image, 2, MTy::STR);
    let protocol = take_field(fl, w, image, 3, MTy::STR);
    let headers = take_field(fl, w, image, 4, headers_ty);
    let body = take_field(fl, w, image, 5, MTy::BYTES);
    let method = fl.method_from_text(method_text, fields[0].1)?;
    let request_value =
        fl.b.rec_new(request, &[method, path, query, headers, body, protocol]);
    let handler =
        fl.b.emit(Op::ClosureCap, &[params[0]], Imm::Idx(0), Some(job.handler))
            .expect("capture");
    let response = fl.b.call_ind(handler, &[request_value]);
    fl.b.emit(Op::Drop, &[request_value], Imm::None, None);
    // An `HttpResponse` is laid out like the runtime's `ResponseWire`.
    fl.b.emit(Op::Put, &[resp_ptr, response], Imm::None, None);
    let u = fl.b.unit();
    fl.emit_return(Some(Val { v: u, own: false }));
    Ok(())
}

/// A record type with the given field types, to read a runtime struct image through.
fn fields_image(fl: &mut FnLower<'_>, tys: &[MTy]) -> RecId {
    let fields = tys
        .iter()
        .enumerate()
        .map(|(i, t)| (format!("f{i}"), *t))
        .collect();
    fl.b.m.add_record("WireImage", fields).0
}

fn lower_stream_adapter(fl: &mut FnLower<'_>, job: &HttpAdapterJob) -> Result<(), Error> {
    let params = fl.b.params();
    let TyKind::Fn(ptys, ret) = fl.b.m.types.kind(job.handler).clone() else {
        return Err(Error::new("a handler must be a function"));
    };
    // The runtime lends the exchange handle: the handler gets a reference of its own.
    let handle =
        fl.b.emit(Op::Copy, &[params[1]], Imm::None, Some(fl.ty_of(params[1])))
            .expect("copy");
    let exchange = fl.wrap_handle(handle, ptys[0])?;
    let handler =
        fl.b.emit(Op::ClosureCap, &[params[0]], Imm::Idx(0), Some(job.handler))
            .expect("capture");
    let result = fl.b.call_ind(handler, &[exchange.v]);
    fl.b.emit(Op::Drop, &[exchange.v], Imm::None, None);
    let code = status_of(fl, result, ret, params[2])?;
    fl.b.emit(Op::Drop, &[result], Imm::None, None);
    fl.emit_return(Some(Val {
        v: code,
        own: false,
    }));
    Ok(())
}

/// The runtime status of a handler's `Result[Unit, HttpError]`: 0, or `1 + the error case`,
/// with the text of `Failed(message)` stored through `err`.
fn status_of(
    fl: &mut FnLower<'_>,
    result: Value,
    result_ty: MTy,
    err: Value,
) -> Result<Value, Error> {
    let TyKind::Alt(ra) = fl.b.m.types.kind(result_ty).clone() else {
        return Err(Error::new("a streaming handler returns a Result"));
    };
    let cases = fl.b.m.alts[ra.index()].cases.clone();
    let ok = cases.iter().position(|c| c.name == "ok").unwrap_or(0) as i64;
    let bad = cases.iter().position(|c| c.name == "error").unwrap_or(1);
    let tag = fl.b.alt_tag(result);
    let k = fl.b.iconst(ok);
    let is_ok = fl.b.icmp(Cc::Eq, tag, k);
    let r = fl.two_ways(
        is_ok,
        MTy::INT,
        &mut |s| Ok(Some(s.b.iconst(0))),
        &mut |s| {
            let e = s.b.alt_get(ra, bad as u32, 0, result);
            let ety = s.ty_of(e);
            let TyKind::Alt(ea) = s.b.m.types.kind(ety).clone() else {
                return Err(Error::new("the error of a handler is an alternative"));
            };
            let etag = s.b.alt_tag(e);
            let one = s.b.iconst(1);
            let code = s.b.binop(Op::IAdd, etag, one);
            let failed = s.b.m.alts[ea.index()]
                .cases
                .iter()
                .position(|c| !c.fields.is_empty());
            if let Some(f) = failed {
                let kf = s.b.iconst(f as i64);
                let hit = s.b.icmp(Cc::Eq, etag, kf);
                s.two_ways(
                    hit,
                    MTy::UNIT,
                    &mut |s| {
                        let text = s.b.alt_get(ea, f as u32, 0, e);
                        let copy =
                            s.b.emit(Op::Copy, &[text], Imm::None, Some(MTy::STR))
                                .expect("copy");
                        s.b.emit(Op::Put, &[err, copy], Imm::None, None);
                        Ok(Some(s.b.unit()))
                    },
                    &mut |s| Ok(Some(s.b.unit())),
                )?;
            }
            Ok(Some(code))
        },
    )?;
    Ok(r.v)
}
