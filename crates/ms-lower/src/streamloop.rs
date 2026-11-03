//! Helpers shared by the stream-related native lowerings: error forwarding and stream upload.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::httpserve::IO_KINDS;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Block, Cc, FuncKind, Imm, Mode, Op, Param, Value};
use ms_mir::types::{AltId, IfaceId, Ty as MTy, TyKind};

impl FnLower<'_> {
    /// Returns `failed` (a `Result` whose error case is `err`) as the error of this operation.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn fail_with(
        &mut self,
        failed: Value,
        src: AltId,
        err: usize,
        dst: AltId,
        derr: usize,
        res: ms_mir::builder::Var,
        join: Block,
    ) -> Result<(), Error> {
        let payload = self.b.alt_get(src, err as u32, 0, failed);
        let copy = self.owned(Val {
            v: payload,
            own: false,
        });
        let out = self.b.alt_new(dst, derr as u32, &[copy]);
        self.drop_value(failed);
        self.b.def_var(res, out);
        self.b.br(join, &[]);
        Ok(())
    }

    pub(crate) fn alt_of(&mut self, v: Value) -> Result<AltId, Error> {
        match self.b.m.types.kind(self.ty_of(v)).clone() {
            TyKind::Alt(a) => Ok(a),
            _ => Err(Error::new("a stream method must return a Result")),
        }
    }
}

pub(crate) fn case(s: &FnLower<'_>, a: AltId, name: &str) -> Result<usize, Error> {
    s.b.m.alts[a.index()]
        .cases
        .iter()
        .position(|c| c.name == name)
        .ok_or_else(|| Error::new(format!("not a Result: no {name} case")))
}

/// The interface of `v` and the index of its method `name`.
pub(crate) fn method(s: &FnLower<'_>, v: Value, name: &str) -> Result<(IfaceId, u32), Error> {
    let TyKind::Iface(i) = s.b.m.types.kind(s.ty_of(v)).clone() else {
        return Err(Error::new("a stream operand must be an interface"));
    };
    let k = s.b.m.ifaces[i.index()]
        .methods
        .iter()
        .position(|m| m.name == name)
        .ok_or_else(|| Error::new(format!("no stream method {name}")))?;
    Ok((i, k as u32))
}

impl FnLower<'_> {
    /// The closure a request upload reads through: `code(closure, has_max, max, out, present,
    /// err) -> status` calls the captured `ReadStream`'s `read` and reports its `Error` as a
    /// status (`Failed` text through `err`). An owned temporary released at the end of the
    /// statement.
    pub(crate) fn upload_env(&mut self, stream: Val) -> Result<Value, Error> {
        let stream_ty = self.ty_of(stream.v);
        let key = format!("upload-thunk:{}", stream_ty.0);
        let thunk = match self.cx.helpers.get(&key) {
            Some(t) => *t,
            None => {
                let f = self.upload_thunk(stream_ty)?;
                let id = self.b.m.add_func(f);
                self.cx.helpers.insert(key, id);
                id
            }
        };
        let fty = self.b.m.types.func(
            vec![MTy::BOOL, MTy::INT, MTy::PTR, MTy::PTR, MTy::PTR],
            MTy::INT,
        );
        let held = self.owned(stream);
        let closure = self
            .b
            .emit(Op::ClosureNew, &[held], Imm::Func(thunk), Some(fty))
            .expect("closure");
        self.temps.push(closure);
        Ok(closure)
    }

    fn upload_thunk(&mut self, stream_ty: MTy) -> Result<ms_mir::ir::Func, Error> {
        let hir = self.hir.clone();
        let pointer = |mode| Param { ty: MTy::PTR, mode };
        let b = FuncBuilder::new(
            self.b.m,
            "upload.read",
            vec![
                pointer(Mode::Borrow),
                Param {
                    ty: MTy::BOOL,
                    mode: Mode::Borrow,
                },
                Param {
                    ty: MTy::INT,
                    mode: Mode::Borrow,
                },
                pointer(Mode::Borrow),
                pointer(Mode::Borrow),
                pointer(Mode::Borrow),
            ],
            MTy::INT,
        );
        let mut fl = FnLower::new(self.cx, b, hir, Default::default(), 0, MTy::INT);
        fl.b.func_mut().kind = FuncKind::Closure {
            captures: vec![stream_ty],
        };
        let p = fl.b.params();
        let stream =
            fl.b.emit(Op::ClosureCap, &[p[0]], Imm::Idx(0), Some(stream_ty))
                .expect("capture");
        let (iface, read) = method(&fl, stream, "read")?;
        let limit = fl.b.m.types.opt(MTy::INT);
        let max = fl
            .two_ways(
                p[1],
                limit,
                &mut |s| Ok(Some(s.b.opt_some(p[2]))),
                &mut |s| Ok(Some(s.b.opt_none(limit))),
            )?
            .v;
        let r = fl.b.call_method(iface, read, stream, &[max]);
        let src = fl.alt_of(r)?;
        let (sok, serr) = (case(&fl, src, "ok")?, case(&fl, src, "error")?);
        let tag = fl.b.alt_tag(r);
        let kerr = fl.b.iconst(serr as i64);
        let is_err = fl.b.icmp(Cc::Eq, tag, kerr);
        let status = fl
            .two_ways(
                is_err,
                MTy::INT,
                &mut |s| {
                    let e = s.b.alt_get(src, serr as u32, 0, r);
                    s.error_status(e, p[5], &IO_KINDS).map(Some)
                },
                &mut |s| {
                    let chunk = s.b.alt_get(src, sok as u32, 0, r);
                    let present = s.b.opt_is_some(chunk);
                    s.b.emit(Op::Store, &[p[4], present], Imm::None, None);
                    s.two_ways(
                        present,
                        MTy::INT,
                        &mut |s| {
                            let data = s.b.opt_get(chunk);
                            let data = s.owned(Val {
                                v: data,
                                own: false,
                            });
                            s.b.emit(Op::Put, &[p[3], data], Imm::None, None);
                            Ok(Some(s.b.iconst(0)))
                        },
                        &mut |s| Ok(Some(s.b.iconst(0))),
                    )
                    .map(|v| Some(v.v))
                },
            )?
            .v;
        fl.drop_value(r);
        fl.emit_return(Some(Val {
            v: status,
            own: false,
        }));
        Ok(fl.b.into_func())
    }
}
