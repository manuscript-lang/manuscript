//! `CompressionFormat.compress_stream` and `decompress_stream`: a `ReadStream` that pulls chunks
//! from another `ReadStream` through the runtime's encoder or decoder object.
//!
//! The stream's data is a record holding the codec (none when its level was rejected) and the
//! input. Its `read` is generated here: the runtime reports when it needs input, and the loop
//! reads the next chunk from the input stream and feeds it. Closing the stream closes the input.

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Val};
use crate::native::NArg;
use ms_check::hir::ModuleHir;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{
    Cc, FuncId, FuncKind, Imm, Linkage, Mode, Module, Op, Param, VtableDef, VtableId,
};
use ms_mir::types::{IfaceId, RecId, Ty as MTy, TyKind};
use std::rc::Rc;

/// The decoder poll statuses and the input chunk size of `compressedStream` in the Go runtime.
const NEED_INPUT: i64 = 64;
const DONE: i64 = 65;
const INPUT_CHUNK: i64 = 32768;
const OUTPUT_CHUNK: i64 = 65536;

/// A generated operation of a codec stream.
pub(crate) struct CodecJob {
    hir: Rc<ModuleHir>,
    op: String,
    decode: bool,
    rec: RecId,
    data_ty: MTy,
}

impl Cx {
    /// The `ReadStream` table over the codec record `rec`.
    fn codec_vtable(
        &mut self,
        m: &mut Module,
        hir: &Rc<ModuleHir>,
        iface: IfaceId,
        rec: RecId,
        decode: bool,
    ) -> VtableId {
        let key = format!("codec:{decode}:{}", iface.0);
        if let Some(v) = self.vtables.get(&key) {
            return *v;
        }
        let data_ty = m.types.rec(rec);
        let sigs = m.ifaces[iface.index()].methods.clone();
        let mut methods = Vec::new();
        for s in &sigs {
            let mut ps = vec![Param {
                ty: MTy::PTR,
                mode: Mode::Borrow,
            }];
            ps.extend(s.params.iter().map(|t| Param {
                ty: *t,
                mode: Mode::Borrow,
            }));
            let mut f = ms_mir::ir::Func::new(&format!("codec.{}", s.name), ps, s.ret);
            f.kind = FuncKind::Method;
            f.linkage = Linkage::Internal;
            let id = m.add_func(f);
            self.queue.push(Job {
                func: id,
                kind: JobKind::Codec(Rc::new(CodecJob {
                    hir: hir.clone(),
                    op: s.name.clone(),
                    decode,
                    rec,
                    data_ty,
                })),
            });
            methods.push(id);
        }
        m.vtables.push(VtableDef {
            name: key.clone(),
            iface,
            methods,
            data_ty,
        });
        let id = VtableId(m.vtables.len() as u32 - 1);
        self.vtables.insert(key, id);
        id
    }
}

/// Builds the body of a codec stream operation reserved by [`Cx::codec_vtable`].
pub(crate) fn build_codec_method(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &CodecJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    let mut fl = FnLower::new(cx, b, job.hir.clone(), Default::default(), 0, proto.ret);
    fl.b.func_mut().kind = FuncKind::Method;
    fl.b.func_mut().linkage = Linkage::Internal;
    let result = match job.op.as_str() {
        "read" => fl.codec_read(job, proto.ret),
        "close" => fl.codec_close(job),
        other => Err(Error::new(format!("a codec stream has no {other}"))),
    };
    let mut out = fl.b.into_func();
    result?;
    out.compact_blocks();
    m.funcs[func.index()] = out;
    Ok(())
}

impl FnLower<'_> {
    /// The record the codec stream keeps: the codec and the input stream.
    fn codec_record(&mut self, input: MTy) -> (RecId, MTy) {
        let key = format!("native:CodecStream:{}", input.0);
        if let Some(t) = self.cx.tycache.get(&key).copied()
            && let TyKind::Rec(r) = self.b.m.types.kind(t)
        {
            return (*r, t);
        }
        let ht = crate::natiface::handle_ty(self.b.m);
        let codec = self.b.m.types.opt(ht);
        let fields = vec![("codec".to_string(), codec), ("input".to_string(), input)];
        let (id, ty) = self.b.m.add_record("CodecStream", fields);
        self.cx.tycache.insert(key, ty);
        (id, ty)
    }

    /// `format.compress_stream(input, level)` / `format.decompress_stream(input, max_bytes)`.
    pub(crate) fn codec_stream(
        &mut self,
        format: Val,
        args: &[NArg],
        decode: bool,
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::Iface(iface) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("a codec stream returns a stream interface"));
        };
        let find = |name: &str| args.iter().find(|a| a.name.as_str() == name).copied();
        let input = find("input").ok_or_else(|| Error::new("a codec stream without an input"))?;
        let input = self.owned(input.val);
        let (rec, rec_ty) = self.codec_record(result);
        let ht = crate::natiface::handle_ty(self.b.m);
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(ht), Some(MTy::PTR))
            .expect("slot");
        let name = self.borrow(format);
        let codec_opt = self.b.m.types.opt(ht);
        let ok = if decode {
            let (has, max) = self.optional_int(find("max_bytes"))?;
            self.call_runtime(
                "msrt_compress_decoder_new",
                &[name, has, max, slot],
                MTy::BOOL,
            )?
        } else {
            let level =
                find("level").ok_or_else(|| Error::new("compress_stream without a level"))?;
            let level = self.borrow(level.val);
            self.call_runtime("msrt_compress_encoder_new", &[name, level, slot], MTy::BOOL)?
        };
        // The runtime answers zero for a codec it built; a rejected level leaves none behind.
        let zero = self.b.iconst(0);
        let code = self
            .b
            .emit(Op::B2I, &[ok], Imm::None, Some(MTy::INT))
            .expect("b2i");
        let good = self.b.icmp(Cc::Eq, code, zero);
        let codec = self.two_ways(
            good,
            codec_opt,
            &mut |s| {
                let h =
                    s.b.emit(Op::Take, &[slot], Imm::Ty(ht), Some(ht))
                        .expect("take");
                Ok(Some(s.b.opt_some(h)))
            },
            &mut |s| Ok(Some(s.none_owned(codec_opt))),
        )?;
        let data = self.b.rec_new(rec, &[codec.v, input]);
        let _ = rec_ty;
        let hir = self.hir.clone();
        let vt = self.cx.codec_vtable(self.b.m, &hir, iface, rec, decode);
        let v = self
            .b
            .emit(Op::IfaceNew, &[data], Imm::Vtable(vt), Some(result))
            .expect("iface");
        Ok(Val { v, own: true })
    }

    /// `close()`: closes the input stream.
    fn codec_close(&mut self, job: &CodecJob) -> Result<(), Error> {
        let args = self.b.params();
        let rec = self
            .b
            .emit(
                Op::Load,
                &[args[0]],
                Imm::Ty(job.data_ty),
                Some(job.data_ty),
            )
            .expect("load");
        let input = self.b.rec_get(job.rec, 1, rec);
        let (iface, close) = self.stream_method(input, "close")?;
        let r = self.b.call_method(iface, close, input, &[]);
        self.b.ret(Some(r));
        Ok(())
    }

    fn stream_method(&mut self, v: ms_mir::ir::Value, name: &str) -> Result<(IfaceId, u32), Error> {
        let TyKind::Iface(i) = self.b.m.types.kind(self.ty_of(v)).clone() else {
            return Err(Error::new("a codec input must be a stream interface"));
        };
        let k = self.b.m.ifaces[i.index()]
            .methods
            .iter()
            .position(|m| m.name == name)
            .ok_or_else(|| Error::new(format!("no stream method {name}")))?;
        Ok((i, k as u32))
    }

    /// `read(max_bytes)`: the next chunk of compressed or decompressed bytes.
    fn codec_read(&mut self, job: &CodecJob, ret: MTy) -> Result<(), Error> {
        let args = self.b.params();
        let TyKind::Alt(result) = self.b.m.types.kind(ret).clone() else {
            return Err(Error::new("a stream read returns a Result"));
        };
        let ok = self.ok_case_index(result)?;
        let some_ty = self.b.m.alts[result.index()].cases[ok].fields[0].1;
        let TyKind::Opt(_) = self.b.m.types.kind(some_ty) else {
            return Err(Error::new("a stream read yields an optional chunk"));
        };
        let rec = self
            .b
            .emit(
                Op::Load,
                &[args[0]],
                Imm::Ty(job.data_ty),
                Some(job.data_ty),
            )
            .expect("load");
        let codec = self.b.rec_get(job.rec, 0, rec);
        let input = self.b.rec_get(job.rec, 1, rec);
        let (iface, read) = self.stream_method(input, "read")?;
        let max = args[1];

        // A supplied size must be positive; a codec that was rejected fails every read.
        let has = self.b.opt_is_some(max);
        let size = self.b.opt_get(max);
        let zero = self.b.iconst(0);
        let nonpositive = self.b.icmp(Cc::Le, size, zero);
        let no = self.b.bconst(false);
        let bad_size = self.b.select(has, nonpositive, no);
        let default = self.b.iconst(OUTPUT_CHUNK);
        let n = self.b.select(has, size, default);
        let built = self.b.opt_is_some(codec);
        let rejected = self.b.icmp(Cc::Eq, built, no);
        let invalid = self.b.binop(Op::Or, bad_size, rejected);
        let (fail, start) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(invalid, fail, &[], start, &[]);
        self.b.seal_block(fail);
        self.b.seal_block(start);
        self.enter(fail);
        let one = self.b.iconst(1);
        let e = self.status_failure(ret, one, "msrt_compress_stream")?;
        self.b.ret(Some(e));
        self.enter(start);
        let h = self.b.opt_get(codec);
        let header = self.b.new_block();
        self.b.br(header, &[]);
        self.enter(header);
        self.b.poll();

        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(MTy::BYTES), Some(MTy::PTR))
            .expect("slot");
        let pull = self.b.new_block();
        if job.decode {
            let st = self.call_runtime("msrt_compress_decoder_poll", &[h, n, slot], MTy::BOOL)?;
            let code = self
                .b
                .emit(Op::B2I, &[st], Imm::None, Some(MTy::INT))
                .expect("b2i");
            let k = self.b.iconst(0);
            let produced = self.b.icmp(Cc::Eq, code, k);
            let (yes, rest) = (self.b.new_block(), self.b.new_block());
            self.b.br_if(produced, yes, &[], rest, &[]);
            self.b.seal_block(yes);
            self.b.seal_block(rest);
            self.enter(yes);
            self.chunk_result(slot, result, ok, some_ty);
            self.enter(rest);
            let need = self.b.iconst(NEED_INPUT);
            let wants = self.b.icmp(Cc::Eq, code, need);
            let (more, rest) = (pull, self.b.new_block());
            self.b.br_if(wants, more, &[], rest, &[]);
            self.b.seal_block(rest);
            self.enter(rest);
            let end = self.b.iconst(DONE);
            let finished = self.b.icmp(Cc::Eq, code, end);
            let (eof, failed) = (self.b.new_block(), self.b.new_block());
            self.b.br_if(finished, eof, &[], failed, &[]);
            self.b.seal_block(eof);
            self.b.seal_block(failed);
            self.enter(eof);
            let none = self.none_owned(some_ty);
            let v = self.b.alt_new(result, ok as u32, &[none]);
            self.b.ret(Some(v));
            self.enter(failed);
            let e = self.status_failure(ret, code, "msrt_compress_decoder_poll")?;
            self.b.ret(Some(e));
        } else {
            let has_out = self.call_runtime("msrt_compress_encoder_has_output", &[h], MTy::BOOL)?;
            let (take, rest) = (self.b.new_block(), self.b.new_block());
            self.b.br_if(has_out, take, &[], rest, &[]);
            self.b.seal_block(take);
            self.b.seal_block(rest);
            self.enter(take);
            self.call_runtime("msrt_compress_encoder_take", &[h, n, slot], MTy::UNIT)?;
            self.chunk_result(slot, result, ok, some_ty);
            self.enter(rest);
            let fin = self.call_runtime("msrt_compress_encoder_is_finished", &[h], MTy::BOOL)?;
            let (eof, more) = (self.b.new_block(), pull);
            self.b.br_if(fin, eof, &[], more, &[]);
            self.b.seal_block(eof);
            self.enter(eof);
            let none = self.none_owned(some_ty);
            let v = self.b.alt_new(result, ok as u32, &[none]);
            self.b.ret(Some(v));
        }

        // pull: read one chunk of input; an error ends the read, the end finishes the codec.
        self.b.seal_block(pull);
        self.enter(pull);
        let want = self.b.iconst(INPUT_CHUNK);
        let some = self.b.opt_some(want);
        let r = self.b.call_method(iface, read, input, &[some]);
        let tag = self.b.alt_tag(r);
        let err = self.error_case_index(result)?;
        let k = self.b.iconst(err as i64);
        let is_err = self.b.icmp(Cc::Eq, tag, k);
        let (bad, good) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(is_err, bad, &[], good, &[]);
        self.b.seal_block(bad);
        self.b.seal_block(good);
        self.enter(bad);
        // The input's own error is this stream's error.
        self.b.ret(Some(r));
        self.enter(good);
        let chunk = self.b.alt_get(result, ok as u32, 0, r);
        let present = self.b.opt_is_some(chunk);
        let (feed, end) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(present, feed, &[], end, &[]);
        self.b.seal_block(feed);
        self.b.seal_block(end);
        self.enter(feed);
        let data = self.b.opt_get(chunk);
        let side = if job.decode { "decoder" } else { "encoder" };
        self.call_runtime(&format!("msrt_compress_{side}_feed"), &[h, data], MTy::UNIT)?;
        self.drop_value(r);
        self.b.br(header, &[]);
        self.enter(end);
        let finish = if job.decode { "finish_input" } else { "finish" };
        self.call_runtime(&format!("msrt_compress_{side}_{finish}"), &[h], MTy::UNIT)?;
        self.drop_value(r);
        self.b.br(header, &[]);
        self.b.seal_block(header);
        Ok(())
    }

    /// Returns `ok(some(chunk))` for the bytes the runtime wrote to `slot`.
    fn chunk_result(
        &mut self,
        slot: ms_mir::ir::Value,
        result: ms_mir::types::AltId,
        ok: usize,
        _opt: MTy,
    ) {
        let bytes = self
            .b
            .emit(Op::Take, &[slot], Imm::Ty(MTy::BYTES), Some(MTy::BYTES))
            .expect("take");
        let some = self.b.opt_some(bytes);
        let v = self.b.alt_new(result, ok as u32, &[some]);
        self.b.ret(Some(v));
    }

    fn error_case_index(&self, a: ms_mir::types::AltId) -> Result<usize, Error> {
        self.b.m.alts[a.index()]
            .cases
            .iter()
            .position(|c| c.name == "error")
            .ok_or_else(|| Error::new("not a Result"))
    }
}
