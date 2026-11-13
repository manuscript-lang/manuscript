//! The test runner entry: runs the test whose index is the first program argument.

use crate::Error;
use crate::text::runtime_fn;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, Func, FuncId, FuncKind, Imm, Linkage, Mode, Module, Op, Param};
use ms_mir::types::{Ty as MTy, TyKind};

/// Marks a skip: the fault message of `skip(reason)`, which the report turns into a skipped test.
pub const SKIP_MARKER: &str = "\u{1}SKIP\u{1}";

/// One entry per bench that calls `driver(closure over the bench, operations per iteration)`. The
/// driver takes the body as a `fn() Result[Unit, Error]` and returns that `Result`, so the
/// entries run as tests do.
pub(crate) fn bench_entries(
    m: &mut Module,
    benches: &[FuncId],
    per: &[i64],
    driver: FuncId,
) -> Vec<FuncId> {
    let mut entries = Vec::new();
    for (&bench, &per) in benches.iter().zip(per) {
        let proto = m.funcs[bench.index()].clone();
        // A closure body takes its environment first and forwards to the bench.
        let mut thunk = FuncBuilder::new(
            m,
            &proto.name,
            vec![Param {
                ty: MTy::PTR,
                mode: Mode::Borrow,
            }],
            proto.ret,
        );
        thunk.func_mut().kind = FuncKind::Closure {
            captures: Vec::new(),
        };
        let r = thunk.call(bench, &[]);
        thunk.ret(Some(r));
        let thunk = thunk.into_func();
        let thunk = m.add_func(thunk);
        let fty = m.types.func(Vec::new(), proto.ret);
        let borrowed = m.funcs[driver.index()]
            .params
            .first()
            .is_some_and(|p| p.mode == Mode::Borrow);
        let mut b = FuncBuilder::new(m, &proto.name, Vec::new(), proto.ret);
        let closure = b
            .emit(Op::ClosureNew, &[], Imm::Func(thunk), Some(fty))
            .expect("closure");
        let operations = b.iconst(per);
        let r = b.call(driver, &[closure, operations]);
        if borrowed {
            b.emit(Op::Drop, &[closure], Imm::None, None);
        }
        b.ret(Some(r));
        let f = b.into_func();
        entries.push(m.add_func(f));
    }
    entries
}

/// Builds `main`: argument `i` selects test `i`, which must return `Result[Unit, Error]`.
/// A failed test reports its message and site through `msrt_test_failure` and exits with 1.
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
        let consume = runtime_fn(b.m, "msrt_args_consume", &[], MTy::UNIT);
        b.call_rt(consume, &[]);
        let r = b.call(*t, &[]);
        let TyKind::Alt(a) = b.m.types.kind(b.ty(r)).clone() else {
            return Err(Error::new("a test must return a Result"));
        };
        let err = b.m.alts[a.index()]
            .error_case()
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
        let TyKind::Type(er) = b.m.types.kind(b.ty(payload)).clone() else {
            return Err(Error::new("a test error must be an Error"));
        };
        let field = b.type_get(er, 0, payload);
        let message = b
            .emit(Op::Clone, &[field], Imm::None, Some(MTy::STR))
            .expect("copy");
        let details = b.type_get(er, 2, payload);
        let details_ty = b.ty(details);
        let report = runtime_fn(b.m, "msrt_test_failure", &[MTy::STR, details_ty], MTy::UNIT);
        b.call_rt(report, &[message, details]);
        for v in [message, r] {
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

/// Wraps a `main` that returns `Unit`, `Result[Unit, Error]` or `Result[Int?, Error]` in the `Int`
/// entry the runtime expects: success exits 0 (or the `Int?` payload), and an error prints `error: <message>` to standard error and exits 1.
pub(crate) fn build_main_wrapper(m: &mut Module, user: FuncId) -> Result<Func, Error> {
    let ret = m.funcs[user.index()].ret;
    let mut b = FuncBuilder::new(m, "main", Vec::new(), MTy::INT);
    let r = b.call(user, &[]);
    let TyKind::Alt(a) = b.m.types.kind(ret).clone() else {
        let z = b.iconst(0);
        b.ret(Some(z));
        return Ok(finish_entry(b));
    };
    let err = b.m.alts[a.index()]
        .error_case()
        .ok_or_else(|| Error::new("main must return Unit, Unit!, or Int"))?;
    let tag = b.alt_tag(r);
    let k = b.iconst(err as i64);
    let failed = b.icmp(Cc::Eq, tag, k);
    let (bad, good) = (b.new_block(), b.new_block());
    b.br_if(failed, bad, &[], good, &[]);
    b.seal_block(bad);
    b.seal_block(good);
    b.switch_to(bad);
    let payload = b.alt_get(a, err as u32, 0, r);
    let TyKind::Type(er) = b.m.types.kind(b.ty(payload)).clone() else {
        return Err(Error::new("main's error must be an Error"));
    };
    let message = b.type_get(er, 0, payload);
    let write = runtime_fn(b.m, "msrt_io_write_stderr", &[MTy::STR], MTy::UNIT);
    for text in ["error: ", "\n"] {
        let lit = b.str_lit(text);
        b.call_rt(write, &[lit]);
        if text == "error: " {
            b.call_rt(write, &[message]);
        }
    }
    b.emit(Op::Drop, &[r], Imm::None, None);
    let one = b.iconst(1);
    b.ret(Some(one));
    b.switch_to(good);
    let ok = b.m.alts[a.index()].ok_case().expect("result") as u32;
    let payload = b.alt_get(a, ok, 0, r);
    let status = if matches!(b.m.types.kind(b.ty(payload)), TyKind::Opt(_)) {
        // `Int?!`: some(n) exits n and none exits 0.
        let present = b.opt_is_some(payload);
        let n = b.opt_get(payload);
        let zero = b.iconst(0);
        b.select(present, n, zero)
    } else {
        b.iconst(0)
    };
    b.emit(Op::Drop, &[r], Imm::None, None);
    b.ret(Some(status));
    Ok(finish_entry(b))
}

fn finish_entry(b: FuncBuilder<'_>) -> Func {
    let mut f = b.into_func();
    f.linkage = Linkage::Export;
    f.compact_blocks();
    f
}
