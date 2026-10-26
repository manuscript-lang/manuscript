use ms_mir::interp::Interp;
use ms_mir::ir::{Imm, Module, Op};
use ms_mir::opt::{self, Level};
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;
use std::path::Path;

fn module(src: &str) -> Module {
    let m = parse_module(src).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    m
}

/// Exit code or `kind: message` of the fault, plus stdout. Fault stacks are omitted
/// because inlining changes them.
fn outcome(m: &Module) -> (Result<i64, String>, String) {
    let mut it = Interp::new(m);
    let r = it
        .run_entry()
        .map_err(|f| format!("{:?}: {}", f.kind, f.message));
    (r, it.stdout().to_string())
}

fn inlined(src: &str) -> Module {
    let mut m = module(src);
    opt::inline::run(&mut m);
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    m
}

fn fixture_sources() -> Vec<(String, String)> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests");
    let mut out = Vec::new();
    for dir in ["fixtures", "fixtures-opt"] {
        let mut files: Vec<_> = std::fs::read_dir(root.join(dir))
            .unwrap()
            .map(|e| e.unwrap().path())
            .filter(|p| p.extension().is_some_and(|e| e == "mir"))
            .collect();
        files.sort();
        for p in files {
            out.push((
                p.display().to_string(),
                std::fs::read_to_string(&p).unwrap(),
            ));
        }
    }
    out
}

fn calls_to(m: &Module, name: &str) -> usize {
    let Some(id) = m.func_by_name(name) else {
        return 0;
    };
    m.funcs
        .iter()
        .flat_map(|f| f.blocks.iter())
        .flat_map(|b| b.insts.iter())
        .filter(|i| i.op == Op::Call && i.imm == Imm::Func(id))
        .count()
}

fn count_op(m: &Module, fname: &str, op: Op) -> usize {
    let id = m
        .func_by_name(fname)
        .unwrap_or_else(|| panic!("no function {fname}"));
    m.funcs[id.index()]
        .blocks
        .iter()
        .flat_map(|b| b.insts.iter())
        .filter(|i| i.op == op)
        .count()
}

fn has_func(m: &Module, name: &str) -> bool {
    m.func_by_name(name).is_some()
}

#[test]
fn all_fixtures_behave_the_same_after_inlining() {
    for (path, src) in fixture_sources() {
        let before = module(&src);
        let after = inlined(&src);
        assert_eq!(outcome(&before), outcome(&after), "{path}");
    }
}

#[test]
fn all_fixtures_behave_the_same_after_the_pipeline() {
    for (path, src) in fixture_sources() {
        let before = module(&src);
        let mut after = module(&src);
        opt::optimize(&mut after, Level::Speed, true);
        assert_eq!(outcome(&before), outcome(&after), "{path}");
    }
}

#[test]
fn inlining_is_idempotent() {
    for (path, src) in fixture_sources() {
        let mut m = inlined(&src);
        let text = print_module(&m);
        assert!(
            !opt::inline::run(&mut m),
            "{path}: second run changed the module"
        );
        assert_eq!(text, print_module(&m), "{path}");
    }
}

#[test]
fn simple_calls_are_inlined_and_callees_removed() {
    let m = inlined(include_str!("fixtures-opt/simple.mir"));
    assert_eq!(calls_to(&m, "add1"), 0);
    assert_eq!(calls_to(&m, "show"), 0);
    assert!(!has_func(&m, "add1"));
    assert!(!has_func(&m, "show"));
    assert_eq!(m.funcs.len(), 1);
    assert_eq!(outcome(&m), (Ok(43), "42\n".to_string()));
}

#[test]
fn multi_return_callee_joins_at_one_continuation() {
    let m = inlined(include_str!("fixtures-opt/multi_return.mir"));
    assert_eq!(calls_to(&m, "abs"), 0);
    assert!(!has_func(&m, "abs"));
    assert_eq!(outcome(&m).0, Ok(12));
}

#[test]
fn owned_and_borrowed_params_keep_ownership_linear() {
    let m = inlined(include_str!("fixtures-opt/ownership.mir"));
    assert_eq!(calls_to(&m, "push2"), 0);
    assert_eq!(calls_to(&m, "total"), 0);
    assert_eq!(outcome(&m).0, Ok(2 + 4));
    let mut it = Interp::new(&m);
    it.run_entry().unwrap();
    let before = module(include_str!("fixtures-opt/ownership.mir"));
    let mut it0 = Interp::new(&before);
    it0.run_entry().unwrap();
    assert_eq!(it.drops(), it0.drops());
}

#[test]
fn recursive_functions_are_not_inlined() {
    let m = inlined(include_str!("fixtures-opt/recursion.mir"));
    assert_eq!(calls_to(&m, "fib"), 3, "{}", print_module(&m));
    assert!(has_func(&m, "fib"));
    assert_eq!(count_op(&m, "fib", Op::DepthEnter), 1);
    assert_eq!(count_op(&m, "fib", Op::DepthLeave), 2);
    assert_eq!(outcome(&m).0, Ok(610));
}

#[test]
fn mutually_recursive_functions_are_not_inlined() {
    let m = inlined(include_str!("fixtures-opt/mutual.mir"));
    assert_eq!(calls_to(&m, "even"), 2);
    assert_eq!(calls_to(&m, "odd"), 1);
    assert_eq!(count_op(&m, "even", Op::DepthEnter), 1);
    assert_eq!(count_op(&m, "odd", Op::DepthEnter), 1);
    assert_eq!(outcome(&m).0, Ok(1));
}

#[test]
fn depth_accounting_is_stripped_outside_cycles() {
    let src = r#"module "d"
entry @main
fn @leaf(%x: int) -> int {
b0:
  depth.enter
  %one: int = iconst 1
  %r: int = iadd %x, %one
  depth.leave
  ret %r
}
fn @main() -> int {
b0:
  depth.enter
  %a: int = iconst 1
  %r: int = call @leaf (%a)
  depth.leave
  ret %r
}
"#;
    let m = inlined(src);
    for f in &m.funcs {
        for b in &f.blocks {
            assert!(
                b.insts
                    .iter()
                    .all(|i| !matches!(i.op, Op::DepthEnter | Op::DepthLeave))
            );
        }
    }
}

#[test]
fn functions_with_indirect_calls_keep_depth_accounting() {
    let src = r#"module "i"
entry @main
fn @cb(%env: ptr, %x: int) -> int closure() {
b0:
  depth.enter
  %f: fn(int) -> int = closure.new @cb
  %r: int = call.ind (%f, %x)
  drop %f
  depth.leave
  ret %r
}
fn @main() -> int {
b0:
  %f: fn(int) -> int = closure.new @cb
  %x: int = iconst 0
  %r: int = call.ind (%f, %x)
  drop %f
  ret %r
}
"#;
    let m = inlined(src);
    assert_eq!(count_op(&m, "cb", Op::DepthEnter), 1);
    assert_eq!(count_op(&m, "cb", Op::DepthLeave), 1);
}

fn hint_program(always_size: usize) -> String {
    let body = |name: &str, hint: &str, n: usize| {
        let mut s =
            format!("fn @{name}(%x: int) -> int {hint} {{\nb0:\n  %v0: int = iadd %x, %x\n");
        for i in 1..n {
            s.push_str(&format!("  %v{i}: int = iadd %v{}, %x\n", i - 1));
        }
        s.push_str(&format!("  ret %v{}\n}}\n", n - 1));
        s
    };
    let mut s = String::from("module \"hints\"\nentry @main\n");
    s.push_str(&body("small_auto", "", 3));
    s.push_str(&body("big_auto", "", 130));
    s.push_str(&body("small_never", "inline(never)", 3));
    s.push_str(&body("big_always", "inline(always)", always_size));
    s.push_str(
        "fn @main() -> int {\nb0:\n  %a: int = iconst 1\n  %p: int = call @small_auto (%a)\n  %q: int = call @big_auto (%a)\n  %r: int = call @small_never (%a)\n  %s: int = call @big_always (%a)\n  %t1: int = iadd %p, %q\n  %t2: int = iadd %t1, %r\n  %t3: int = iadd %t2, %s\n  ret %t3\n}\n",
    );
    s
}

#[test]
fn hints_decide_inlining() {
    let src = hint_program(200);
    let before = module(&src);
    let m = inlined(&src);
    assert_eq!(calls_to(&m, "small_auto"), 0);
    assert_eq!(calls_to(&m, "big_auto"), 1);
    assert_eq!(calls_to(&m, "small_never"), 1);
    assert_eq!(calls_to(&m, "big_always"), 0);
    assert!(!has_func(&m, "small_auto"));
    assert!(!has_func(&m, "big_always"));
    assert!(has_func(&m, "big_auto"));
    assert!(has_func(&m, "small_never"));
    assert_eq!(outcome(&before), outcome(&m));
}

#[test]
fn growth_budget_limits_auto_inlining() {
    let mut s = String::from("module \"g\"\nentry @main\n");
    s.push_str("fn @f(%x: int) -> int {\nb0:\n  %v0: int = iadd %x, %x\n");
    for i in 1..50 {
        s.push_str(&format!("  %v{i}: int = iadd %v{}, %x\n", i - 1));
    }
    s.push_str("  ret %v49\n}\n");
    s.push_str("fn @main() -> int {\nb0:\n  %a: int = iconst 1\n");
    let mut prev = "a".to_string();
    for i in 0..40 {
        s.push_str(&format!("  %c{i}: int = call @f (%{prev})\n"));
        prev = format!("c{i}");
    }
    s.push_str(&format!("  ret %{prev}\n}}\n"));
    let before = module(&s);
    let m = inlined(&s);
    let left = calls_to(&m, "f");
    assert!(left > 0 && left < 40, "{left} calls left");
    assert_eq!(outcome(&before), outcome(&m));
}

#[test]
fn constant_bonus_survives_continuation_splits_without_marking_call_results_constant() {
    let mut src = String::from("module \"constant-bonus\"\nentry @main\n");
    src.push_str("fn @bump(%x: int) -> int {\nb0:\n  %one: int = iconst 1\n  %r: int = iadd %x, %one\n  ret %r\n}\n");
    src.push_str("fn @threshold(%x: int) -> int {\nb0:\n  %v0: int = iadd %x, %x\n");
    // One instruction above the ordinary limit; multiple call sites prevent the single-use bonus.
    for i in 1..=opt::inline::BASE_THRESHOLD {
        src.push_str(&format!("  %v{i}: int = iadd %v{}, %x\n", i - 1));
    }
    src.push_str(&format!("  ret %v{}\n}}\n", opt::inline::BASE_THRESHOLD));
    src.push_str("fn @main() -> int {\nb0:\n  %early: int = iconst 1\n  %result: int = call @bump (%early)\n  %late: int = iconst 2\n  %a: int = call @threshold (%early)\n  %b: int = call @threshold (%late)\n  %c: int = call @threshold (%result)\n  %ab: int = iadd %a, %b\n  %abc: int = iadd %ab, %c\n  ret %abc\n}\n");
    let before = module(&src);
    let after = inlined(&src);
    assert_eq!(calls_to(&after, "bump"), 0);
    assert_eq!(calls_to(&after, "threshold"), 1);
    assert_eq!(outcome(&before), outcome(&after));
}

#[test]
fn closures_and_methods_are_not_inline_candidates_and_survive() {
    let m = inlined(include_str!("fixtures-opt/dead.mir"));
    // The closure reaches its call through an owning block parameter; it is still known there,
    // so its code is inlined and removed.
    assert!(!has_func(&m, "add"));
    assert!(has_func(&m, "area_int"));
    assert!(has_func(&m, "kept_exported"));
    assert!(!has_func(&m, "unused"));
    assert!(!has_func(&m, "helper"));
    assert_eq!(calls_to(&m, "helper"), 0);
    assert_eq!(outcome(&m).0, Ok(30 + 12));
}

#[test]
fn closures_built_where_they_are_called_are_inlined() {
    let src = r#"module "closure"
entry @main
fn @add(%env: ptr, %x: int) -> int closure(int) {
b0:
  %k: int = closure.cap 0 %env
  %r: int = iadd.chk %x, %k
  ret %r
}
fn @main() -> int {
b0:
  %k: int = iconst 10
  %f: fn(int) -> int = closure.new @add %k
  %x: int = iconst 5
  %r: int = call.ind (%f, %x)
  drop %f
  ret %r
}
"#;
    let m = inlined(src);
    assert!(!has_func(&m, "add"));
    let ops: Vec<Op> = m.funcs[0]
        .blocks
        .iter()
        .flat_map(|b| b.insts.iter().map(|i| i.op))
        .collect();
    assert!(!ops.contains(&Op::CallInd) && !ops.contains(&Op::ClosureNew));
    assert_eq!(outcome(&m).0, Ok(15));
}

#[test]
fn removed_functions_renumber_every_reference() {
    let m = inlined(include_str!("fixtures-opt/dead.mir"));
    let main = m.entry.expect("entry kept");
    assert_eq!(m.funcs[main.index()].name, "main");
    assert_eq!(m.funcs.len(), 3);
    let v = &m.vtables[0];
    assert_eq!(m.funcs[v.methods[0].index()].name, "area_int");
    let text = print_module(&m);
    let again = module(&text);
    assert_eq!(outcome(&again), outcome(&m));
}

#[test]
fn auto_callees_with_loops_are_not_inlined() {
    let src = r#"module "loop"
entry @main
fn @sum(%n: int) -> int {
b0:
  %z: int = iconst 0
  br loop(%z, %z)
loop(%i: int, %acc: int):
  %c: bool = icmp.lt %i, %n
  br_if %c, body(), done()
body:
  %a: int = iadd.chk %acc, %i
  %one: int = iconst 1
  %j: int = iadd %i, %one
  br loop(%j, %a)
done:
  ret %acc
}
fn @main() -> int {
b0:
  %n: int = iconst 100
  %r: int = call @sum (%n)
  ret %r
}
"#;
    let m = inlined(src);
    assert_eq!(calls_to(&m, "sum"), 1);
    assert_eq!(outcome(&m).0, Ok(4950));
}

#[test]
fn auto_callees_with_loops_are_inlined_into_loops() {
    let src = r#"module "loop2"
entry @main
fn @sum(%n: int) -> int {
b0:
  %z: int = iconst 0
  br loop(%z, %z)
loop(%i: int, %acc: int):
  %c: bool = icmp.lt %i, %n
  br_if %c, body(), done()
body:
  %a: int = iadd.chk %acc, %i
  %one: int = iconst 1
  %j: int = iadd %i, %one
  br loop(%j, %a)
done:
  ret %acc
}
fn @main() -> int {
b0:
  %z: int = iconst 0
  %four: int = iconst 4
  br outer(%z, %z)
outer(%k: int, %t: int):
  %c: bool = icmp.lt %k, %four
  br_if %c, body(), done()
body:
  %n: int = iconst 10
  %r: int = call @sum (%n)
  %t2: int = iadd %t, %r
  %one: int = iconst 1
  %k2: int = iadd %k, %one
  br outer(%k2, %t2)
done:
  ret %t
}
"#;
    let before = module(src);
    let m = inlined(src);
    assert_eq!(calls_to(&m, "sum"), 0);
    assert_eq!(outcome(&before), outcome(&m));
    assert_eq!(outcome(&m).0, Ok(180));
}

#[test]
fn faults_report_the_same_kind_and_message() {
    let src = r#"module "f"
entry @main
fn @boom(%x: int) -> int {
b0:
  %max: int = iconst 9223372036854775807
  %r: int = iadd.chk %x, %max
  ret %r
}
fn @main() -> int {
b0:
  %a: int = iconst 5
  %r: int = call @boom (%a)
  ret %r
}
"#;
    let before = module(src);
    let m = inlined(src);
    assert_eq!(calls_to(&m, "boom"), 0);
    let (r, _) = outcome(&m);
    assert!(r.is_err());
    assert_eq!(outcome(&before), outcome(&m));
}

/// A sort comparator that captures a variable is called from the specialized thunk, not
/// inlined into it: its `closure.cap` reads need the closure's own layout, which the thunk
/// (a plain function) does not have.
#[test]
fn capturing_sort_comparators_are_called_not_inlined() {
    let src = r#"module "i"
extern @msrt_list_sorted(list<int>, ptr, ptr, fn(int, int) -> int) -> list<int>
entry @main
fn @cmp(%env: ptr, %a: int, %b: int) -> int closure(int) {
b0:
  %k: int = closure.cap 0 %env
  %d: int = isub %b, %a
  %r: int = imul %d, %k
  ret %r
}
fn @sort.cmp(%f: fn(int, int) -> int, %p: ptr, %q: ptr) -> int {
b0:
  %a: int = load int %p
  %b: int = load int %q
  %r: int = call.ind (%f, %a, %b)
  ret %r
}
fn @main() -> int {
b0:
  %k: int = iconst 3
  %f: fn(int, int) -> int = closure.new @cmp %k
  %xs: list<int> = list.lit
  %t: ptr = func.addr @sort.cmp
  %d: ptr = typedesc int
  %ys: list<int> = call.rt @msrt_list_sorted (%xs, %d, %t, %f)
  drop %xs
  %n: int = list.len %ys
  drop %ys
  drop %f
  ret %n
}
"#;
    let m = inlined(src);
    for f in &m.funcs {
        let caps = f
            .blocks
            .iter()
            .flat_map(|b| b.insts.iter())
            .filter(|i| i.op == Op::ClosureCap)
            .count();
        let closure = matches!(f.kind, ms_mir::ir::FuncKind::Closure { .. });
        assert!(
            caps == 0 || closure,
            "{} reads a capture outside a closure",
            f.name
        );
    }
    let names: Vec<&str> = m.funcs.iter().map(|f| f.name.as_str()).collect();
    assert!(names.contains(&"sort.cmp.cmp"), "{names:?}");
}

const SPECIALIZE: &str = r#"module "spec"
entry @main
fn @add(%env: ptr, %x: int) -> int closure(int) {
b0:
  %k: int = closure.cap 0 %env
  %r: int = iadd %x, %k
  ret %r
}
fn @mul(%env: ptr, %x: int) -> int closure(int) {
b0:
  %k: int = closure.cap 0 %env
  %r: int = imul %x, %k
  ret %r
}
fn @total(%n: int, %f: fn(int) -> int) -> int {
b0:
  %zero: int = iconst 0
  %one: int = iconst 1
  br b1(%zero, %zero, %f)
b1(%i: int, %acc: int, %g: fn(int) -> int):
  %c: bool = icmp.lt %i, %n
  br_if %c, b2(), b3()
b2():
  %h: fn(int) -> int = copy %g
  %v: int = call.ind (%h, %i)
  drop %h
  %acc2: int = iadd %acc, %v
  %i2: int = iadd %i, %one
  br b1(%i2, %acc2, %g)
b3():
  ret %acc
}
fn @main() -> int {
b0:
  %n: int = iconst 10
  %a: int = iconst 3
  %b: int = iconst 5
  %f: fn(int) -> int = closure.new @add %a
  %r1: int = call @total (%n, %f)
  drop %f
  %f2: fn(int) -> int = closure.new @add %b
  %r2: int = call @total (%n, %f2)
  drop %f2
  %f3: fn(int) -> int = closure.new @mul %a
  %r3: int = call @total (%n, %f3)
  drop %f3
  %s1: int = iadd %r1, %r2
  %s2: int = iadd %s1, %r3
  ret %s2
}
"#;

#[test]
fn a_known_closure_argument_specializes_the_callee() {
    let before = module(SPECIALIZE);
    let m = inlined(SPECIALIZE);
    let text = print_module(&m);
    assert_eq!(calls_to(&m, "total"), 0, "{text}");
    assert!(has_func(&m, "total.add"), "{text}");
    assert!(has_func(&m, "total.mul"), "{text}");
    assert!(!has_func(&m, "total"), "{text}");
    for name in ["total.add", "total.mul"] {
        assert_eq!(count_op(&m, name, Op::CallInd), 0, "{text}");
        assert_eq!(count_op(&m, name, Op::ClosureNew), 0, "{text}");
        assert_eq!(count_op(&m, name, Op::Copy), 0, "{text}");
        assert_eq!(count_op(&m, name, Op::Drop), 0, "{text}");
    }
    assert_eq!(count_op(&m, "main", Op::ClosureNew), 0, "{text}");
    assert_eq!(outcome(&before), outcome(&m));
}

#[test]
fn a_closure_that_escapes_the_callee_is_kept_correct() {
    let src = SPECIALIZE.replace(
        "  %acc2: int = iadd %acc, %v\n",
        "  %acc2: int = iadd %acc, %v\n  %esc: int = call @use (%g)\n  %acc3: int = iadd %acc2, %esc\n",
    ).replace("br b1(%i2, %acc2, %g)", "br b1(%i2, %acc3, %g)")
    .replace("fn @total", "fn @use(%f: fn(int) -> int) -> int inline(never) {\nb0:\n  %z: int = iconst 0\n  %r: int = call.ind (%f, %z)\n  ret %r\n}\nfn @total");
    let before = module(&src);
    let m = inlined(&src);
    assert_eq!(outcome(&before), outcome(&m), "{}", print_module(&m));
}

/// Thousands of inlinable calls in one block take linear time: each split moves only the
/// instructions since the previous one.
#[test]
fn many_calls_in_one_block_inline_in_linear_time() {
    let n = 20_000;
    let mut src = String::from(
        "module \"main\"\nfile 0 \"a.ms\"\nentry @main\n\n\
         fn @id(%0: int) -> int {\nb0:\n  ret %0\n}\n\nfn @main() -> int export {\nb0:\n  %0: int = iconst 1\n",
    );
    for i in 1..=n {
        src.push_str(&format!("  %{i}: int = call @id (%{})\n", i - 1));
    }
    src.push_str(&format!("  ret %{n}\n}}\n"));
    let mut m = module(&src);
    let start = std::time::Instant::now();
    ms_mir::opt::inline::run(&mut m);
    assert!(start.elapsed().as_secs() < 10, "took {:?}", start.elapsed());
    verify_module(&m).expect("verify after");
    assert!(!print_module(&m).contains("call @id"));
}
