//! The test runner entry: runs the test whose index is the first program argument.

use crate::Error;
use crate::text::runtime_fn;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, FuncId, Imm, Linkage, Module, Op};
use ms_mir::types::{Ty as MTy, TyKind};

/// Marks a failure message on stderr, ahead of the message.
pub const FAILURE_MARKER: &str = "\u{1}FAIL\u{1}";

/// Builds `main`: argument `i` selects test `i`, which must return `Result[Unit, Error]`.
/// A failed test writes `FAILURE_MARKER` and its message to stderr and exits with 1.
pub(crate) fn build_runner(m: &mut Module, tests: &[FuncId]) -> Result<FuncId, Error> {
    let mut b = FuncBuilder::new(m, "main", Vec::new(), MTy::INT);
    let args_ty = b.m.types.list(MTy::STR);
    let args_fn = runtime_fn(b.m, "msrt_args", &[], args_ty);
    let done = b.new_block();
    let mut next = b.current();
    for (i, t) in tests.iter().enumerate() {
        b.switch_to(next);
        let args = b.call_rt(args_fn, &[]);
        let zero = b.iconst(0);
        let selected = b.list_get(args, zero);
        let lit = b.str_lit(&i.to_string());
        let eq_fn = runtime_fn(b.m, "msrt_string_eq", &[MTy::STR, MTy::STR], MTy::BOOL);
        let hit = b.call_rt(eq_fn, &[selected, lit]);
        b.emit(Op::Drop, &[args], Imm::None, None);
        let (run, miss) = (b.new_block(), b.new_block());
        b.br_if(hit, run, &[], miss, &[]);
        b.seal_block(run);
        b.seal_block(miss);
        b.switch_to(run);
        let r = b.call(*t, &[]);
        let TyKind::Alt(a) = b.m.types.kind(b.ty(r)).clone() else {
            return Err(Error::new("a test must return a Result"));
        };
        let err = b.m.alts[a.index()]
            .cases
            .iter()
            .position(|c| c.name == "error")
            .ok_or_else(|| Error::new("a test must return a Result"))?;
        let tag = b.alt_tag(r);
        let k = b.iconst(err as i64);
        let failed = b.icmp(Cc::Eq, tag, k);
        let (bad, good) = (b.new_block(), b.new_block());
        b.br_if(failed, bad, &[], good, &[]);
        b.seal_block(bad);
        b.seal_block(good);
        b.switch_to(bad);
        let payload = b.alt_get(a, err as u32, 0, r);
        let TyKind::Iface(iface) = b.m.types.kind(b.ty(payload)).clone() else {
            return Err(Error::new("a test error must be an Error"));
        };
        let message = b.call_method(iface, 0, payload, &[]);
        let marker = b.str_lit(FAILURE_MARKER);
        let cat = runtime_fn(b.m, "msrt_string_concat", &[MTy::STR, MTy::STR], MTy::STR);
        let line = b.call_rt(cat, &[marker, message]);
        let write = runtime_fn(b.m, "msrt_io_write_stderr", &[MTy::STR], MTy::UNIT);
        b.call_rt(write, &[line]);
        for v in [line, message, r] {
            b.emit(Op::Drop, &[v], Imm::None, None);
        }
        let one = b.iconst(1);
        b.ret(Some(one));
        b.switch_to(good);
        b.emit(Op::Drop, &[r], Imm::None, None);
        b.br(done, &[]);
        next = miss;
    }
    b.switch_to(next);
    b.br(done, &[]);
    b.seal_block(done);
    b.switch_to(done);
    let z = b.iconst(0);
    b.ret(Some(z));
    let mut f = b.into_func();
    f.linkage = Linkage::Export;
    f.compact_blocks();
    Ok(m.add_func(f))
}
