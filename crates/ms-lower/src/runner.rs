//! The test runner entry: runs the test whose index is the first program argument.

use crate::Error;
use crate::text::runtime_fn;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, Func, FuncId, FuncKind, Imm, Linkage, Mode, Module, Op, Param};
use ms_mir::types::{Ty as MTy, TyKind};

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
        let thunk = closure_thunk(m, bench);
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

/// A closure body that takes its environment first and forwards to `target`, which takes no
/// arguments.
fn closure_thunk(m: &mut Module, target: FuncId) -> FuncId {
    let proto = m.funcs[target.index()].clone();
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
    let r = thunk.call(target, &[]);
    thunk.ret(Some(r));
    let thunk = thunk.into_func();
    m.add_func(thunk)
}

/// A closure body: its environment, then `params` (all borrowed), returning `ret`; `body`
/// computes the result from the parameters after the environment.
fn closure_fn(
    m: &mut Module,
    name: &str,
    params: &[MTy],
    ret: MTy,
    body: impl FnOnce(&mut FuncBuilder<'_>, &[ms_mir::ir::Value]) -> ms_mir::ir::Value,
) -> FuncId {
    let mut all = vec![Param {
        ty: MTy::PTR,
        mode: Mode::Borrow,
    }];
    all.extend(params.iter().map(|&ty| Param {
        ty,
        mode: Mode::Borrow,
    }));
    let mut b = FuncBuilder::new(m, name, all, ret);
    b.func_mut().kind = FuncKind::Closure {
        captures: Vec::new(),
    };
    let values = b.params();
    let r = body(&mut b, &values[1..]);
    b.ret(Some(r));
    let f = b.into_func();
    m.add_func(f)
}

/// `ok(unit)` of the `Result` type `ret`.
fn ok_unit(b: &mut FuncBuilder<'_>, ret: MTy) -> ms_mir::ir::Value {
    let TyKind::Alt(a) = b.m.types.kind(ret).clone() else {
        panic!("a hook closure returns a Result");
    };
    let ok = b.m.alts[a.index()].ok_case().expect("ok case") as u32;
    let u = b.unit();
    b.alt_new(a, ok, &[u])
}

/// The parameter and result types of the closure type `ty`.
fn fn_parts(m: &Module, ty: MTy) -> Result<(Vec<MTy>, MTy), Error> {
    match m.types.kind(ty).clone() {
        TyKind::Fn(params, ret) => Ok((params, ret)),
        _ => Err(Error::new("the test runner expects a function value")),
    }
}

/// The element type of the list type `ty`.
fn list_elem(m: &Module, ty: MTy) -> Result<MTy, Error> {
    match m.types.kind(ty).clone() {
        TyKind::List(e) => Ok(e),
        _ => Err(Error::new("the test runner expects a list")),
    }
}

/// One test file for `build_file_runners`.
pub(crate) struct TestFile {
    /// Each test's function and index in the listing, in source order.
    pub tests: Vec<(FuncId, i64)>,
    /// `run_plain_file`, or the `run_fixture_file` instance for the file's fixture type.
    pub harness: FuncId,
    /// The fixture factory and its `before_all`, `before_each`, `after_each` and `after_all`
    /// hooks, for a file with `make_fixture`.
    pub fixture: Option<(FuncId, [Option<FuncId>; 4])>,
}

/// Builds `main`: one closure per file that calls the file's harness with its tests, handed
/// to `run_files` (`@std/internal/test_runner.ms` `run_test_files`), whose status `main` returns.
pub(crate) fn build_file_runners(
    m: &mut Module,
    files: &[TestFile],
    run_files: FuncId,
) -> Result<FuncId, Error> {
    let runner_ty = list_elem(m, m.funcs[run_files.index()].params[0].ty)?;
    let (runner_params, runner_ret) = fn_parts(m, runner_ty)?;
    let mut runners = Vec::new();
    for (position, file) in files.iter().enumerate() {
        let harness = m.funcs[file.harness.index()].clone();
        let types: Vec<MTy> = harness.params.iter().map(|p| p.ty).collect();
        let borrowed: Vec<bool> = harness
            .params
            .iter()
            .map(|p| p.mode == Mode::Borrow)
            .collect();
        // Parameters: file, [make, four hooks,] tests, indices, selected, results.
        let tests_at = if file.fixture.is_some() { 6 } else { 1 };
        let test_ty = list_elem(m, types[tests_at])?;
        let (test_params, test_ret) = fn_parts(m, test_ty)?;
        let mut test_closures = Vec::new();
        for &(t, _) in &file.tests {
            let thunk = closure_fn(m, "test", &test_params, test_ret, |b, ps| b.call(t, ps));
            test_closures.push(thunk);
        }
        let mut fixture_closures = Vec::new();
        if let Some((make, hooks)) = &file.fixture {
            let (make_params, make_ret) = fn_parts(m, types[1])?;
            let make = *make;
            fixture_closures.push((
                closure_fn(m, "make_fixture", &make_params, make_ret, |b, ps| {
                    b.call(make, ps)
                }),
                types[1],
            ));
            for (i, hook) in hooks.iter().enumerate() {
                let (hook_params, hook_ret) = fn_parts(m, types[2 + i])?;
                let hook = *hook;
                let thunk = closure_fn(m, "hook", &hook_params, hook_ret, |b, ps| match hook {
                    Some(h) if b.m.funcs[h.index()].ret == MTy::UNIT => {
                        b.call(h, ps);
                        ok_unit(b, hook_ret)
                    }
                    Some(h) => b.call(h, ps),
                    None => ok_unit(b, hook_ret),
                });
                fixture_closures.push((thunk, types[2 + i]));
            }
        }
        let indices: Vec<i64> = file.tests.iter().map(|&(_, i)| i).collect();
        let target = file.harness;
        let runner = closure_fn(m, "test file", &runner_params, runner_ret, |b, ps| {
            let mut args = vec![b.iconst(position as i64)];
            for &(c, ty) in &fixture_closures {
                let v = b
                    .emit(Op::ClosureNew, &[], Imm::Func(c), Some(ty))
                    .expect("closure");
                args.push(v);
            }
            let mut items = Vec::new();
            for &c in &test_closures {
                let v = b
                    .emit(Op::ClosureNew, &[], Imm::Func(c), Some(test_ty))
                    .expect("closure");
                items.push(v);
            }
            args.push(b.list_lit(test_ty, &items));
            args.push(b.list_const(MTy::INT, indices.clone()));
            args.extend_from_slice(ps);
            let r = b.call(target, &args);
            // Arguments the harness borrows are still ours; the caller's own stay theirs.
            let made = args.len() - ps.len();
            for (i, v) in args.iter().take(made).enumerate() {
                if borrowed[i] && i > 0 {
                    b.emit(Op::Drop, &[*v], Imm::None, None);
                }
            }
            r
        });
        runners.push(runner);
    }
    let borrowed = m.funcs[run_files.index()].params[0].mode == Mode::Borrow;
    let mut b = FuncBuilder::new(m, "main", Vec::new(), MTy::INT);
    let mut items = Vec::new();
    for c in runners {
        let v = b
            .emit(Op::ClosureNew, &[], Imm::Func(c), Some(runner_ty))
            .expect("closure");
        items.push(v);
    }
    let list = b.list_lit(runner_ty, &items);
    let status = b.call(run_files, &[list]);
    if borrowed {
        b.emit(Op::Drop, &[list], Imm::None, None);
    }
    b.ret(Some(status));
    let mut f = b.into_func();
    f.linkage = Linkage::Export;
    f.compact_blocks();
    Ok(m.add_func(f))
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
        let hit = crate::eq::string_eq(&mut b, selected, lit);
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
