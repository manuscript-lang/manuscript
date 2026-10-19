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
