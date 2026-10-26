//! Tests for the `range` pass: differential runs against the interpreter, one snapshot
//! per rewrite, and negative cases where the checks must stay.

use ms_mir::interp::Interp;
use ms_mir::ir::{FaultKind, Module};
use ms_mir::opt::{self, Level, range};
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;
use std::path::PathBuf;

type Outcome = (Result<i64, (FaultKind, String)>, String);

fn parse(src: &str) -> Module {
    let m = parse_module(src).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    m
}

fn exec(m: &Module) -> Outcome {
    let mut it = Interp::new(m);
    it.set_fuel(Some(200_000_000));
    let r = it.run_entry().map_err(|f| (f.kind, f.message));
    (r, it.stdout().to_string())
}

fn dir(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join(name)
}

fn fixtures() -> Vec<(String, String)> {
    let mut out = Vec::new();
    for d in ["fixtures", "fixtures-opt"] {
        for e in std::fs::read_dir(dir(d)).expect("fixture dir") {
            let p = e.expect("entry").path();
            if p.extension().is_some_and(|x| x == "mir") {
                let name = p.file_name().expect("name").to_string_lossy().into_owned();
                out.push((name, std::fs::read_to_string(&p).expect("read fixture")));
            }
        }
    }
    out.sort();
    out
}

fn optimized(name: &str) -> (Module, Module) {
    let src = std::fs::read_to_string(dir("fixtures-opt").join(name)).expect("fixture");
    let before = parse(&src);
    let mut after = before.clone();
    range::run(&mut after);
    verify_module(&after).unwrap_or_else(|e| panic!("{name}: {e:?}"));
    (before, after)
}

fn count(m: &Module, mnemonic: &str) -> usize {
    print_module(m)
        .split_whitespace()
        .filter(|t| *t == mnemonic)
        .count()
}

#[test]
fn interpreter_agrees_before_and_after() {
    for (name, src) in fixtures() {
        let before = parse(&src);
        let want = exec(&before);
        let mut after = before.clone();
        range::run(&mut after);
        verify_module(&after).unwrap_or_else(|e| panic!("{name}: range broke the module: {e:?}"));
        assert_eq!(exec(&after), want, "{name}: range changed behavior");
        let mut full = before.clone();
        opt::optimize(&mut full, Level::Speed, true);
        assert_eq!(exec(&full), want, "{name}: pipeline changed behavior");
    }
}

#[test]
fn induction_variable_is_unchecked() {
    let (b, a) = optimized("loop_induction.mir");
    assert_eq!(count(&b, "iadd.chk"), 2);
    // `i + 1` under `i < 1000`; `acc + i` can still overflow.
    assert_eq!(count(&a, "iadd.chk"), 1, "{}", print_module(&a));
    assert_eq!(count(&a, "iadd"), 1);
}

#[test]
fn bounded_counters_are_unchecked() {
    let (_, a) = optimized("decided_branch.mir");
    assert_eq!(count(&a, "iadd.chk"), 0, "{}", print_module(&a));
    let (_, a) = optimized("count_down.mir");
    // `i - 1` under `i > 0` is exact; `acc + i` can still overflow.
    assert_eq!(count(&a, "isub.chk"), 0, "{}", print_module(&a));
}

#[test]
fn list_access_in_bounds_becomes_unchecked() {
    let (b, a) = optimized("list_walk.mir");
    assert_eq!(count(&b, "list.get"), 1);
    assert_eq!(count(&a, "list.get.u"), 1, "{}", print_module(&a));
    assert_eq!(count(&a, "list.set.u"), 1, "{}", print_module(&a));
    assert_eq!(count(&a, "list.get"), 0);
    assert_eq!(count(&a, "list.set"), 0);
}

#[test]
fn arithmetic_checks_are_dropped_when_proven() {
    let (b, a) = optimized("arith_checks.mir");
    assert_eq!(count(&b, "imul.chk"), 1);
    assert_eq!(count(&a, "imul.chk"), 0);
    assert_eq!(count(&a, "isub.chk"), 0);
    assert_eq!(count(&a, "ineg.chk"), 0);
    // main: sdiv by 3 and by -1 of a constant, srem by 3; div(): all three must stay.
    assert_eq!(count(&a, "sdiv"), 2);
    assert_eq!(count(&a, "srem"), 1);
    assert_eq!(count(&a, "sdiv.chk"), 2);
    assert_eq!(count(&a, "srem.chk"), 1);
}

#[test]
fn possible_overflow_keeps_the_check() {
    let (_, a) = optimized("arith_checks.mir");
    // `inc(x)` with an unknown `x`.
    assert_eq!(count(&a, "iadd.chk"), 1);
    let (_, a) = optimized("overflow_fault.mir");
    assert_eq!(count(&a, "iadd.chk"), 1);
    let (r, _) = exec(&a);
    assert_eq!(r.expect_err("must fault").0, FaultKind::IntOverflow);
}

#[test]
fn possibly_negative_index_keeps_the_check() {
    let (_, a) = optimized("list_negative.mir");
    // `get_at(l, i)` with unknown `i` stays a plain `list.get`.
    assert_eq!(count(&a, "list.get"), 1, "{}", print_module(&a));
}

#[test]
fn push_changes_the_length() {
    let (_, a) = optimized("list_negative.mir");
    // Before the push `i < len(l0)` is known; after it only `n >= 0` is.
    assert_eq!(count(&a, "list.get.u"), 1, "{}", print_module(&a));
    assert_eq!(count(&a, "list.get.nn"), 1, "{}", print_module(&a));
}

#[test]
fn decided_comparisons_and_branches_fold() {
    let (b, a) = optimized("decided_branch.mir");
    assert_eq!(count(&b, "icmp.lt"), 2);
    assert_eq!(count(&a, "icmp.lt"), 1);
    assert_eq!(count(&a, "bconst"), 1);
    assert!(!print_module(&a).contains("iconst -1"), "dead arm kept");
}

#[test]
fn impossible_switch_cases_are_removed() {
    let (b, a) = optimized("alt_impossible.mir");
    assert!(print_module(&b).contains("iconst 99"));
    assert!(
        !print_module(&a).contains("iconst 99"),
        "{}",
        print_module(&a)
    );
}

#[test]
fn pass_reaches_a_fixpoint() {
    for (name, src) in fixtures() {
        let mut m = parse(&src);
        range::run(&mut m);
        let once = print_module(&m);
        range::run(&mut m);
        assert_eq!(print_module(&m), once, "{name}: second run changed more");
    }
}

#[test]
fn kernels_verify_after_range() {
    let kernels = dir("../../ms-clif/kernels");
    for e in std::fs::read_dir(kernels).expect("kernel dir") {
        let p = e.expect("entry").path();
        if p.extension().is_some_and(|x| x == "mir") {
            let mut m = parse(&std::fs::read_to_string(&p).expect("read kernel"));
            range::run(&mut m);
            verify_module(&m).unwrap_or_else(|e| panic!("{}: {e:?}", p.display()));
        }
    }
}

#[test]
fn ifconv_turns_a_pure_diamond_into_select() {
    let src =
        std::fs::read_to_string(dir("fixtures-opt").join("ifconv_collatz.mir")).expect("fixture");
    let before = parse(&src);
    let mut after = before.clone();
    assert!(ms_mir::opt::ifconv::run(&mut after));
    verify_module(&after).unwrap_or_else(|e| panic!("{e:?}"));
    assert_eq!(count(&after, "select"), 1);
    assert_eq!(count(&after, "br_if"), 1);
    assert_eq!(exec(&before), exec(&after));
    assert_eq!(exec(&after).0, Ok(111));
}

#[test]
fn ifconv_merges_early_returns_into_selects() {
    let src =
        std::fs::read_to_string(dir("fixtures-opt").join("early_returns.mir")).expect("fixture");
    let before = parse(&src);
    let mut after = before.clone();
    assert!(ms_mir::opt::ifconv::run(&mut after));
    verify_module(&after).unwrap_or_else(|e| panic!("{e:?}"));
    assert_eq!(count(&after, "br_if"), 0);
    assert_eq!(count(&after, "select"), 2);
    assert_eq!(exec(&before), exec(&after));
    assert_eq!(exec(&after).0, Ok(10));
}

#[test]
fn select_step_keeps_a_loop_counter_bounded() {
    let src =
        std::fs::read_to_string(dir("fixtures-opt").join("select_counter.mir")).expect("fixture");
    let before = parse(&src);
    let mut after = before.clone();
    ms_mir::opt::optimize(&mut after, ms_mir::opt::Level::Speed, true);
    verify_module(&after).unwrap_or_else(|e| panic!("{e:?}"));
    assert_eq!(exec(&before), exec(&after));
    assert_eq!(exec(&after).0, Ok(334));
}

#[test]
fn optparam_splits_merged_constructors_into_a_flag_and_a_value() {
    let src = std::fs::read_to_string(dir("fixtures-opt").join("opt_merge.mir")).expect("fixture");
    let before = parse(&src);
    let mut after = before.clone();
    assert!(ms_mir::opt::optparam::run(&mut after));
    verify_module(&after).unwrap_or_else(|e| panic!("{e:?}"));
    assert_eq!(count(&after, "opt.is_some"), 0);
    assert_eq!(count(&after, "opt.get"), 0);
    assert_eq!(exec(&before), exec(&after));
    assert_eq!(exec(&after).0, Ok(8));
}

#[test]
fn slotfuse_passes_the_field_to_the_mutator_without_a_slot() {
    // Not under `fixtures-opt`: the interpreter cannot run the runtime calls.
    let before = parse(BUILDER_APPEND);
    let mut after = before.clone();
    assert!(ms_mir::opt::slotfuse::run(&mut after));
    verify_module(&after).unwrap_or_else(|e| panic!("{e:?}"));
    // The build slot stays; the append's slot and both moves are gone.
    assert_eq!(count(&before, "slot"), count(&after, "slot") + 1);
    assert_eq!(count(&before, "take"), count(&after, "take") + 2);
}

const BUILDER_APPEND: &str = r#"module "main"
file 0 "a.ms"
record SB { sealed: bool, items: bytes }
extern @msrt_list_new() -> bytes
extern @msrt_fault_string(str) -> unit noreturn
extern @msrt_strbuilder_append(ptr, str) -> unit
extern @msrt_strbuilder_freeze(ptr) -> str
extern @msrt_string_byte_length(str) -> int
entry @main

fn @main() -> int export {
b0:
  depth.enter
  %0: bytes = call.rt @msrt_list_new ()
  %1: bool = bconst false
  %2: SB = rec.new SB %1, %0
  %3: Shared<SB> = shared.new %2
  %4: int = iconst 0
  br b1(%4, %3)
b1(%5: int, %6: own Shared<SB>):
  %7: int = iconst 10
  %8: bool = icmp.lt %5, %7
  br_if %8, b2(), b5()
b2():
  %9: str = str "x"
  %10: ptr = shared.addr %6
  %11: ptr = ptr.field SB.sealed %10
  %12: ptr = ptr.field SB.items %10
  %13: bool = load bool %11
  br_if %13, b3(), b4()
b3():
  %14: str = str "builder is sealed"
  %15: unit = call.rt @msrt_fault_string (%14)
  unreachable
b4():
  %16: bytes = take bytes %12
  %17: ptr = slot bytes
  put %17, %16
  %18: unit = call.rt @msrt_strbuilder_append (%17, %9)
  %19: bytes = take bytes %17
  put %12, %19
  %20: unit = unit
  %21: int = iconst 1
  %22: int = iadd.chk %5, %21
  br b1(%22, %6)
b5():
  %23: ptr = shared.addr %6
  %24: ptr = ptr.field SB.sealed %23
  %25: ptr = ptr.field SB.items %23
  %26: bool = bconst true
  store %24, %26
  %27: bytes = load bytes %25
  %28: bytes = copy %27
  %29: ptr = slot bytes
  put %29, %28
  %30: str = call.rt @msrt_strbuilder_freeze (%29)
  %31: int = call.rt @msrt_string_byte_length (%30)
  drop %30
  drop %6
  depth.leave
  ret %31
}
"#;

#[test]
fn saved_lengths_survive_replacement_in_nested_loops() {
    let (before, after) = optimized("list_saved_length.mir");
    assert_eq!(exec(&before), exec(&after));
    assert_eq!(exec(&after).0, Ok(12));
    assert_eq!(count(&before, "list.get"), 2);
    // The loop read and update use the entry length through two loop parameters.
    // The read after the loops is not guarded by non-emptiness and stays checked.
    assert_eq!(count(&after, "list.get.u"), 1, "{}", print_module(&after));
    assert_eq!(count(&after, "list.set.u"), 1, "{}", print_module(&after));
    assert_eq!(count(&after, "br_if"), 2, "{}", print_module(&after));
}

#[test]
fn saved_lengths_do_not_survive_shrinking_a_loop_carried_list() {
    let (before, after) = optimized("list_saved_length_shrink.mir");
    assert_eq!(exec(&before), exec(&after));
    assert!(exec(&after).0.is_err());
    assert_eq!(count(&after, "list.get.u"), 0, "{}", print_module(&after));
}

#[test]
fn a_conditional_replacement_does_not_keep_the_saved_length() {
    for choice in [true, false] {
        let src = format!(
            "module \"different_lengths\"
entry @main
fn @walk(%start: own list<int>, %choose: bool) -> int {{
b0:
  %n: int = list.len %start
  %one: int = iconst 1
  br_if %choose, keep(), replace()
keep:
  br join(%start)
replace:
  %shorter: list<int> = list.lit %one
  drop %start
  br join(%shorter)
join(%current: own list<int>):
  %inside: bool = icmp.lt %one, %n
  br_if %inside, read(), done()
read:
  %x: int = list.get %current, %one
  drop %current
  ret %x
done:
  drop %current
  ret %one
}}
fn @main() -> int {{
b0:
  %one: int = iconst 1
  %l: list<int> = list.lit %one, %one
  %choose: bool = bconst {choice}
  %r: int = call @walk(%l, %choose)
  ret %r
}}"
        );
        let before = parse(&src);
        let mut after = before.clone();
        range::run(&mut after);
        verify_module(&after).unwrap();
        assert_eq!(exec(&before), exec(&after));
        assert_eq!(count(&after, "list.get.u"), 0, "{}", print_module(&after));
        assert_eq!(exec(&after).0.is_err(), !choice);
    }
}

#[test]
fn literal_list_lengths_bound_modulo_indices() {
    let before = parse(
        "module \"literal_length\"
entry @main
fn @read(%x: int) -> int {
b0:
  %z: int = iconst 0
  %n: int = iconst 4
  %positive: bool = icmp.ge %x, %z
  br_if %positive, read(), negative()
read:
  %list: list<int> = list.lit %n, %n, %n, %n
  %i: int = srem.chk %x, %n
  %v: int = list.get %list, %i
  %len: int = list.len %list
  %r: int = iadd %v, %len
  drop %list
  ret %r
negative:
  ret %z
}
fn @main() -> int {
b0:
  %x: int = iconst 9223372036854775807
  %r: int = call @read(%x)
  ret %r
}",
    );
    let mut after = before.clone();
    range::run(&mut after);
    verify_module(&after).unwrap();
    assert_eq!(exec(&before), exec(&after));
    assert_eq!(exec(&after).0, Ok(8));
    assert_eq!(count(&after, "list.len"), 0);
    assert_eq!(count(&after, "list.get.u"), 1, "{}", print_module(&after));
}

#[test]
fn literal_lengths_preserve_negative_indices_and_out_of_bounds_faults() {
    for (idx, elements) in [(-1, "%one, %one"), (2, "%one, %one"), (0, "")] {
        let before = parse(&format!(
            "module \"literal_bounds\"
entry @main
fn @main() -> int {{
b0:
  %one: int = iconst 1
  %list: list<int> = list.lit {elements}
  %i: int = iconst {idx}
  %r: int = list.get %list, %i
  drop %list
  ret %r
}}"
        ));
        let mut after = before.clone();
        range::run(&mut after);
        verify_module(&after).unwrap();
        assert_eq!(exec(&before), exec(&after));
        assert_eq!(count(&after, "list.get.u"), 0, "{}", print_module(&after));
    }
    let before = parse(
        "module \"capacity_is_not_length\"
entry @main
fn @main() -> int {
b0:
  %capacity: int = iconst 100
  %list: list<int> = list.new %capacity
  %n: int = list.len %list
  drop %list
  ret %n
}",
    );
    let mut after = before.clone();
    range::run(&mut after);
    verify_module(&after).unwrap();
    assert_eq!(exec(&before), exec(&after));
    assert_eq!(exec(&after).0, Ok(0));
    assert_eq!(count(&after, "list.len"), 0);
}

const BYTE_VALUES: &str = r#"module "main"
file 0 "a.ms"
extern @msrt_list_new() -> bytes
extern @msrt_bytes_values(bytes) -> list<int>
entry @main

fn @main() -> int export {
b0:
  %data: bytes = call.rt @msrt_list_new ()
  %r: int = call @sum (%data)
  drop %data
  ret %r
}

fn @sum(%data: bytes) -> int {
b0:
  %l0: list<int> = call.rt @msrt_bytes_values (%data)
  %z: int = iconst 0
  br loop(%z, %z, %l0)
loop(%i: int, %acc: int, %l: own list<int>):
  %n: int = list.len %l
  %cond: bool = icmp.lt %i, %n
  br_if %cond, body(), done()
body:
  %x: int = list.get %l, %i
  %big: int = iconst 9223372036854775000
  %y: int = iadd.chk %x, %big
  %one: int = iconst 1
  %i1: int = iadd.chk %i, %one
  %acc2: int = iadd %acc, %y
  br loop(%i1, %acc2, %l)
done:
  drop %l
  ret %acc
}
"#;

const BYTE_VALUES_REPLACED: &str = r#"module "main"
file 0 "a.ms"
extern @msrt_list_new() -> bytes
extern @msrt_bytes_values(bytes) -> list<int>
entry @main

fn @main() -> int export {
b0:
  %data: bytes = call.rt @msrt_list_new ()
  %r: int = call @sum (%data)
  drop %data
  ret %r
}

fn @sum(%data: bytes) -> int {
b0:
  %l0: list<int> = call.rt @msrt_bytes_values (%data)
  %z: int = iconst 0
  br loop(%z, %z, %l0)
loop(%i: int, %acc: int, %l: own list<int>):
  %n: int = list.len %l
  %cond: bool = icmp.lt %i, %n
  br_if %cond, body(), done()
body:
  %x: int = list.get %l, %i
  %big: int = iconst 9223372036854775000
  %y: int = iadd.chk %x, %big
  %one: int = iconst 1
  %i1: int = iadd.chk %i, %one
  %acc2: int = iadd %acc, %y
  %l2: list<int> = list.set %l, %i, %y
  br loop(%i1, %acc2, %l2)
done:
  drop %l
  ret %acc
}
"#;

#[test]
fn bytes_values_elements_are_bytes() {
    let mut m = parse(BYTE_VALUES);
    // `i + 1` and `x + big`.
    assert_eq!(count(&m, "iadd.chk"), 2);
    range::run(&mut m);
    // A byte plus 9223372036854775000 fits an Int, and the elements keep the byte range
    // through the loop-carried list; only the index counter is proven separately.
    assert_eq!(count(&m, "iadd.chk"), 0, "{}", print_module(&m));
}

#[test]
fn replaced_list_loses_the_byte_range() {
    let mut m = parse(BYTE_VALUES_REPLACED);
    range::run(&mut m);
    // `list.set` makes a new list value that reaches the loop parameter, so the elements
    // are no longer known to be bytes and the addition can overflow.
    assert_eq!(count(&m, "iadd.chk"), 1, "{}", print_module(&m));
}

/// `n` list-mapping loops one after another, each over the list the one before built.
fn loop_chain(n: usize) -> String {
    let mut s = String::from(
        "module \"t\"\nentry @main\nfn @main() -> int {\nb0:\n  %one: int = iconst 1\n  %z: int = iconst 0\n  %l0: list<int> = list.lit %one\n  br h0(%l0)\n",
    );
    for k in 0..n {
        s.push_str(&format!(
            "h{k}(%in{k}: own list<int>):\n  %len{k}: int = list.len %in{k}\n  %out{k}: list<int> = list.new %len{k}\n  br l{k}(%z, %in{k}, %out{k})\n\
             l{k}(%i{k}: int, %src{k}: own list<int>, %dst{k}: own list<int>):\n  %c{k}: bool = icmp.lt %i{k}, %len{k}\n  br_if %c{k}, body{k}(), done{k}()\n\
             body{k}:\n  %x{k}: int = list.get %src{k}, %i{k}\n  %y{k}: int = iadd %x{k}, %one\n  %d2{k}: list<int> = list.push %dst{k}, %y{k}\n  %j{k}: int = iadd %i{k}, %one\n  br l{k}(%j{k}, %src{k}, %d2{k})\n\
             done{k}:\n  drop %src{k}\n  br h{}(%dst{k})\n",
            k + 1
        ));
    }
    s.push_str(&format!(
        "h{n}(%r: own list<int>):\n  %v: int = list.get %r, %z\n  drop %r\n  ret %v\n}}\n"
    ));
    s
}

#[test]
fn a_chain_of_loops_is_handled_in_linear_time() {
    // Each loop leaves facts about its own counter and list length behind; they must not pile
    // up in the environments of every later loop, which made the pass quadratic.
    let n = 6000;
    let mut m = parse(&loop_chain(n));
    let start = std::time::Instant::now();
    assert!(range::run(&mut m));
    assert!(start.elapsed().as_secs() < 20, "took {:?}", start.elapsed());
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
}
