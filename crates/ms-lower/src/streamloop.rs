//! `io.read_all`, `io.copy` and `io.read_line` over any `ReadStream`.
//!
//! The loop calls the stream's own `read`; the accumulator in `ms-std-io` owns the policy
//! (chunk sizes, validation, limits). A failing `read` or `write_bytes` returns its `IoError`
//! unchanged.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::hir::CallView;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Block, Cc, FuncKind, Imm, Mode, Op, Param, Value};
use ms_mir::types::{AltId, IfaceId, Ty as MTy, TyKind};

/// Which operation the accumulator runs.
#[derive(Clone, Copy)]
pub(crate) enum Loop {
    ReadAll,
    Copy,
    ReadLine,
}

impl Loop {
    fn kind(self) -> i64 {
        match self {
            Loop::ReadAll => 0,
            Loop::Copy => 1,
            Loop::ReadLine => 2,
        }
    }

    fn finish(self) -> &'static str {
        match self {
            Loop::ReadAll => "msstd_io_acc_finish_bytes",
            Loop::Copy => "msstd_io_acc_finish_count",
            Loop::ReadLine => "msstd_io_acc_finish_line",
        }
    }
}

impl FnLower<'_> {
    /// `io.read_all(input, max_bytes)` and `io.copy(input, output, max_bytes)`.
    pub(crate) fn stream_native(
        &mut self,
        e: &ms_syntax::ast::Expr,
        view: &CallView<'_>,
        kind: Loop,
    ) -> Result<Val, Error> {
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let result = self.emty(e)?;
        let find = |name: &str| args.iter().find(|a| a.name.as_str() == name).copied();
        let input =
            find("input").ok_or_else(|| Error::new("a stream operation without an input"))?;
        let input = self.borrow(input.val);
        let sink = match kind {
            Loop::Copy => {
                let out = find("output").ok_or_else(|| Error::new("copy without an output"))?;
                Some(self.borrow(out.val))
            }
            _ => None,
        };
        let (has, max) = self.optional_int(find("max_bytes"))?;
        self.at(e.pos);
        self.stream_loop(kind, input, sink, has, max, result)
    }

    /// Runs `kind` over `stream` (and `sink` for a copy); the owned `Result` it yields.
    pub(crate) fn stream_loop(
        &mut self,
        kind: Loop,
        stream: Value,
        sink: Option<Value>,
        has: Value,
        max: Value,
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::Alt(dst) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("a stream operation returns a Result"));
        };
        let (dok, derr) = (case(self, dst, "ok")?, case(self, dst, "error")?);
        let _ = dok;
        let (iface, read) = method(self, stream, "read")?;
        let write = match sink {
            Some(s) => Some(method(self, s, "write_bytes")?),
            None => None,
        };
        // The operands are borrowed in variables of their own: the loop re-reads them each round,
        // and a stream is called in place, so its state outlives the call.
        let hold = |s: &mut Self, v: Value| {
            let t = s.ty_of(v);
            let var = s.b.declare_var(t, Mode::Borrow);
            s.b.def_var(var, v);
            var
        };
        let stream_var = hold(self, stream);
        let sink_var = sink.map(|v| hold(self, v));
        let k = self.b.iconst(kind.kind());
        let acc = self.call_runtime("msstd_io_acc_new", &[k, has, max], MTy::PTR)?;
        let res = self.b.declare_var(result, Mode::Own);
        let [header, body, got, chunk, stop, exit, join] =
            std::array::from_fn(|_| self.b.new_block());
        self.b.br(header, &[]);

        // header: ask the accumulator for the next request size.
        self.enter(header);
        self.b.poll();
        let want = self.call_runtime("msstd_io_acc_want", &[acc], MTy::INT)?;
        let zero = self.b.iconst(0);
        let more = self.b.icmp(Cc::Ne, want, zero);
        self.b.br_if(more, body, &[], exit, &[]);
        self.b.seal_block(body);

        // body: read a chunk; a failing read is the result.
        self.enter(body);
        let some = self.b.opt_some(want);
        let stream = self.b.use_var(stream_var);
        let r = self.b.call_method(iface, read, stream, &[some]);
        let src = self.alt_of(r)?;
        let (sok, serr) = (case(self, src, "ok")?, case(self, src, "error")?);
        let (fail, ok_blk) = (self.b.new_block(), got);
        let tag = self.b.alt_tag(r);
        let kerr = self.b.iconst(serr as i64);
        let is_err = self.b.icmp(Cc::Eq, tag, kerr);
        self.b.br_if(is_err, fail, &[], ok_blk, &[]);
        self.b.seal_block(fail);
        self.b.seal_block(ok_blk);
        self.enter(fail);
        self.fail_with(r, src, serr, dst, derr, res, join)?;

        // got: end of stream finishes; a chunk goes to the accumulator.
        self.enter(got);
        let opt = self.b.alt_get(src, sok as u32, 0, r);
        let present = self.b.opt_is_some(opt);
        self.b.br_if(present, chunk, &[], stop, &[]);
        self.b.seal_block(chunk);
        self.b.seal_block(stop);
        self.enter(stop);
        self.drop_value(r);
        self.b.br(exit, &[]);

        self.enter(chunk);
        let data = self.b.opt_get(opt);
        let accepted = self.call_runtime("msstd_io_acc_push", &[acc, data], MTy::BOOL)?;
        let (next, ended) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(accepted, next, &[], ended, &[]);
        self.b.seal_block(next);
        self.b.seal_block(ended);
        self.enter(ended);
        self.drop_value(r);
        self.b.br(exit, &[]);

        self.enter(next);
        if let (Some(sink_var), Some((wiface, widx))) = (sink_var, write) {
            let sink = self.b.use_var(sink_var);
            let w = self.b.call_method(wiface, widx, sink, &[data]);
            let wsrc = self.alt_of(w)?;
            let werr = case(self, wsrc, "error")?;
            let (wfail, wok) = (self.b.new_block(), self.b.new_block());
            let wtag = self.b.alt_tag(w);
            let kw = self.b.iconst(werr as i64);
            let bad = self.b.icmp(Cc::Eq, wtag, kw);
            self.b.br_if(bad, wfail, &[], wok, &[]);
            self.b.seal_block(wfail);
            self.b.seal_block(wok);
            self.enter(wfail);
            self.drop_value(r);
            self.fail_with(w, wsrc, werr, dst, derr, res, join)?;
            self.enter(wok);
            self.drop_value(w);
        }
        self.drop_value(r);
        self.b.br(header, &[]);
        self.b.seal_block(header);

        // exit: the accumulator's outcome.
        self.b.seal_block(exit);
        self.enter(exit);
        let sym = kind.finish();
        let sig = crate::rtcall::rt_sig(sym)
            .ok_or_else(|| Error::new(format!("no runtime symbol {sym}")))?;
        let out = self.finish_rt_call(sym, &sig, true, vec![acc], result)?;
        let out = self.owned(out);
        self.b.def_var(res, out);
        self.b.br(join, &[]);

        self.b.seal_block(join);
        self.enter(join);
        let v = self.b.use_var(res);
        Ok(Val { v, own: true })
    }

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
    /// err) -> status` calls the captured `ReadStream`'s `read` and reports its `IoError` as a
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
                    s.error_status(e, p[5]).map(Some)
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
