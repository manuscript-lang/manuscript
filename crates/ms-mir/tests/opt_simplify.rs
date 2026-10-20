//! Differential and snapshot tests for the `simplify` pass.

use ms_mir::interp::Interp;
use ms_mir::ir::Module;
use ms_mir::opt::simplify;
use ms_mir::parse::parse_module;
use ms_mir::print::{print_func, print_module};
use ms_mir::verify::verify_module;
use std::path::Path;

fn load(src: &str) -> Module {
    let m = parse_module(src).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    m
}

/// Result, output and drop count of running the entry function.
fn observe(m: &Module) -> (Result<i64, String>, String, u64) {
    let mut it = Interp::new(m);
    let r = it.run_entry().map_err(|f| f.to_string());
    (r, it.stdout().to_string(), it.drops())
}

fn check(src: &str) -> Module {
    let before = load(src);
    let expected = observe(&before);
    let mut after = before.clone();
    simplify::run(&mut after);
    if let Err(e) = verify_module(&after) {
        panic!(
            "verify failed after simplify: {e:?}\n{}",
            print_module(&after)
        );
    }
    assert_eq!(observe(&after), expected, "{}", print_module(&after));
    // A second run reaches a fixpoint.
    let mut twice = after.clone();
    assert!(
        !simplify::run(&mut twice),
        "not idempotent:\n{}",
        print_module(&twice)
    );
    after
}

fn root() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests")
}

#[test]
fn interpreter_agrees_on_all_fixtures() {
    let mut n = 0;
    for dir in ["fixtures", "fixtures-opt"] {
        for e in std::fs::read_dir(root().join(dir)).unwrap() {
            let p = e.unwrap().path();
            if p.extension().is_some_and(|x| x == "mir") {
                check(&std::fs::read_to_string(&p).unwrap());
                n += 1;
            }
        }
    }
    assert!(n >= 18, "found only {n} fixtures");
}

fn func_text(m: &Module, name: &str) -> String {
    let id = m.func_by_name(name).expect("function exists");
    print_func(m, &m.funcs[id.index()])
}

fn opt_fixture(name: &str) -> Module {
    check(&std::fs::read_to_string(root().join("fixtures-opt").join(name)).unwrap())
}

fn count(text: &str, needle: &str) -> usize {
    text.matches(needle).count()
}

#[test]
fn folds_constants_and_identities() {
    let m = opt_fixture("arith_fold.mir");
    let main = func_text(&m, "main");
    for op in ["imul.chk", "iadd.chk", "select", "fadd"] {
        assert_eq!(count(&main, op), 0, "{op} left in:\n{main}");
    }
    let ident = func_text(&m, "ident");
    for op in ["imul", "isub", "iadd", "and", "or", "not", "select"] {
        assert_eq!(
            count(&ident, &format!("= {op} ")),
            0,
            "{op} left in:\n{ident}"
        );
    }
}

#[test]
fn strength_reduces_division_and_multiplication() {
    let m = opt_fixture("strength.mir");
    let t = func_text(&m, "reduce");
    assert_eq!(count(&t, ".chk"), 0, "{t}");
    assert_eq!(count(&t, "= sdiv "), 1, "{t}");
    assert_eq!(count(&t, "= srem "), 1, "{t}");
    assert_eq!(count(&t, "imul"), 0, "{t}");
    assert_eq!(count(&t, "= shl "), 1, "{t}");
    let p = func_text(&m, "parity");
    assert_eq!(count(&p, "srem"), 0, "{p}");
    assert_eq!(count(&p, "= and "), 1, "{p}");
}

#[test]
fn checked_ops_with_constants_stay_checked() {
    let m = opt_fixture("checked_stay.mir");
    let keep = func_text(&m, "keep");
    for op in ["iadd.chk", "imul.chk", "isub.chk"] {
        assert_eq!(count(&keep, op), 1, "{op} lost in:\n{keep}");
    }
    let by = func_text(&m, "by_minus_one");
    assert_eq!(count(&by, "sdiv.chk"), 1, "{by}");
}

#[test]
fn faults_are_preserved() {
    for name in ["overflow_fault.mir", "div_zero_fault.mir"] {
        let m = opt_fixture(name);
        assert!(observe(&m).0.is_err(), "{name} must still fault");
        assert_eq!(count(&func_text(&m, "main"), ".chk"), 1, "{name}");
    }
}

#[test]
fn simplifies_control_flow() {
    let m = opt_fixture("cfg.mir");
    let route = func_text(&m, "route");
    assert_eq!(count(&route, "br_if"), 0, "{route}");
    assert_eq!(
        count(&route, "\nb"),
        1,
        "route should be one block:\n{route}"
    );
    let sw = func_text(&m, "sw");
    assert_eq!(count(&sw, "switch"), 0, "{sw}");
    let lp = func_text(&m, "loop_sum");
    assert!(
        lp.contains("b1(%2: int, %3: int):"),
        "invariant parameter removed:\n{lp}"
    );
}

#[test]
fn numbers_values_and_removes_dead_code() {
    let m = opt_fixture("cse_dce.mir");
    let t = func_text(&m, "dup");
    assert_eq!(count(&t, "list.len"), 1, "{t}");
    assert_eq!(count(&t, "imul"), 0, "{t}");
    // `x + y`, `y + x` and the dominated repeat in the branch collapse to one add.
    assert_eq!(
        count(&t, "= iadd %0, %1") + count(&t, "= iadd %1, %0"),
        1,
        "{t}"
    );
}

#[test]
fn ownership_is_never_dropped() {
    let m = opt_fixture("cse_dce.mir");
    let t = func_text(&m, "owned_unused");
    assert_eq!(count(&t, "drop "), 2, "{t}");
    assert_eq!(count(&t, "list.new"), 2, "{t}");
}

#[test]
fn folds_operations_on_a_known_plain_case() {
    // Deleting the construction deletes its paired drop, so only result and output are compared.
    let before =
        load(&std::fs::read_to_string(root().join("fixtures-opt-nocheck/alt_known.mir")).unwrap());
    let mut m = before.clone();
    simplify::run(&mut m);
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    assert_eq!(observe(&m).0, observe(&before).0);
    assert_eq!(observe(&m).1, observe(&before).1);
    let main = func_text(&m, "main");
    for op in ["alt.new", "alt.tag", "alt.get", "drop"] {
        assert_eq!(count(&main, op), 0, "{op} left in:\n{main}");
    }
}
