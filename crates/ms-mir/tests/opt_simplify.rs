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

#[test]
fn folds_safe_constant_division_by_minus_one() {
    for op in ["sdiv", "sdiv.chk", "srem", "srem.chk"] {
        for x in [i64::MIN + 1, -7, 0, 7, i64::MAX] {
            let m = check(&format!(
                "module \"minus_one\"\nentry @main\nfn @main() -> int {{\nb0:\n  %x: int = iconst {x}\n  %y: int = iconst -1\n  %r: int = {op} %x, %y\n  ret %r\n}}"
            ));
            let text = func_text(&m, "main");
            assert!(!text.contains(op), "{text}");
        }
    }
    // The checked overflow and zero divisor must still fault.
    for (op, x, y) in [
        ("sdiv.chk", i64::MIN, -1),
        ("sdiv.chk", 7, 0),
        ("srem.chk", 7, 0),
    ] {
        let m = check(&format!(
            "module \"fault\"\nentry @main\nfn @main() -> int {{\nb0:\n  %x: int = iconst {x}\n  %y: int = iconst {y}\n  %r: int = {op} %x, %y\n  ret %r\n}}"
        ));
        assert!(observe(&m).0.is_err());
        assert!(func_text(&m, "main").contains(op));
    }
}

#[test]
fn canonicalizes_boolean_negation() {
    for expr in ["select %b, %f, %t", "xor %b, %t", "xor %t, %b"] {
        for b in [false, true] {
            let m = check(&format!(
                "module \"bool_negation\"\nentry @main\nfn @negate(%b: bool) -> bool {{\nb0:\n  %f: bool = bconst false\n  %t: bool = bconst true\n  %r: bool = {expr}\n  ret %r\n}}\nfn @main() -> int {{\nb0:\n  %b: bool = bconst {b}\n  %r: bool = call @negate (%b)\n  %i: int = b2i %r\n  ret %i\n}}"
            ));
            let text = func_text(&m, "negate");
            assert!(!text.contains("select") && !text.contains("xor"), "{text}");
            assert_eq!(count(&text, "= not "), 1, "{text}");
        }
    }
}

#[test]
fn remainder_by_minus_one_is_zero_even_at_min() {
    for x in [i64::MIN, -1, 0, i64::MAX] {
        let m = check(&format!(
            "module \"remainder\"\nentry @main\nfn @rem(%x: int) -> int {{\nb0:\n  %y: int = iconst -1\n  %r: int = srem.chk %x, %y\n  ret %r\n}}\nfn @main() -> int {{\nb0:\n  %x: int = iconst {x}\n  %r: int = call @rem (%x)\n  ret %r\n}}"
        ));
        assert_eq!(observe(&m).0, Ok(0));
        assert!(!func_text(&m, "rem").contains("srem"));
    }
}

#[test]
fn folding_remainder_keeps_numerator_faults() {
    let m = check(
        "module \"numerator_fault\"
entry @main
fn @main() -> int {
b0:
  %one: int = iconst 1
  %zero: int = iconst 0
  %minus_one: int = iconst -1
  %x: int = sdiv.chk %one, %zero
  %r: int = srem.chk %x, %minus_one
  ret %r
}",
    );
    assert!(observe(&m).0.is_err());
    let text = func_text(&m, "main");
    assert!(text.contains("sdiv.chk"), "{text}");
    assert!(!text.contains("srem"), "{text}");
}

#[test]
fn reuses_dominating_checked_arithmetic_across_io() {
    for (op, x, y) in [
        ("iadd.chk", 7, 3),
        ("iadd.chk", i64::MAX, 1),
        ("isub.chk", 7, 3),
        ("isub.chk", i64::MIN, 1),
        ("imul.chk", 7, 3),
        ("imul.chk", i64::MAX, 2),
        ("ineg.chk", 7, 0),
        ("ineg.chk", i64::MIN, 0),
        ("sdiv.chk", 7, 3),
        ("sdiv.chk", 7, 0),
        ("sdiv.chk", i64::MIN, -1),
        ("srem.chk", 7, 3),
        ("srem.chk", 7, 0),
    ] {
        let args = if op == "ineg.chk" { "%x" } else { "%x, %y" };
        let repeated = if matches!(op, "iadd.chk" | "imul.chk") {
            "%y, %x"
        } else {
            args
        };
        let m = check(&format!(
            "module \"checked_cse\"
extern @msrt_print_int(int) -> unit
entry @main
fn @calc(%x: int, %y: int) -> int {{
b0:
  %a: int = {op} {args} !0:10:1
  %out: unit = call.rt @msrt_print_int(%a)
  %b: int = {op} {repeated} !0:12:1
  %sum: int = iadd %a, %b
  ret %sum
}}
fn @main() -> int {{
b0:
  %x: int = iconst {x}
  %y: int = iconst {y}
  %r: int = call @calc(%x, %y)
  ret %r
}}"
        ));
        let text = func_text(&m, "calc");
        assert_eq!(count(&text, op), 1, "{text}");
        assert!(text.contains("!0:10:1"), "first check moved: {text}");
    }
}

#[test]
fn checked_arithmetic_in_sibling_blocks_is_not_reused_at_the_join() {
    for c in [false, true] {
        let m = check(&format!(
            "module \"checked_siblings\"
entry @main
fn @calc(%x: int, %y: int, %c: bool) -> int {{
b0:
  br_if %c, yes(), no()
yes:
  %a: int = iadd.chk %x, %y
  br join(%a)
no:
  %b: int = iadd.chk %x, %y
  br join(%b)
join(%p: int):
  %d: int = iadd.chk %x, %y
  %r: int = iadd %p, %d
  ret %r
}}
fn @main() -> int {{
b0:
  %x: int = iconst 7
  %y: int = iconst 3
  %c: bool = bconst {c}
  %r: int = call @calc(%x, %y, %c)
  ret %r
}}"
        ));
        let text = func_text(&m, "calc");
        assert_eq!(count(&text, "iadd.chk"), 3, "{text}");
    }
}

#[test]
fn a_dominating_check_is_kept_when_only_its_repeat_is_used() {
    for c in [false, true] {
        let m = check(&format!(
            "module \"checked_dominator\"
entry @main
fn @calc(%x: int, %y: int, %c: bool) -> int {{
b0:
  %first: int = iadd.chk %x, %y !0:6:1
  br_if %c, yes(), no()
yes:
  %second: int = iadd.chk %y, %x !0:9:1
  ret %second
no:
  %other: int = isub.chk %x, %y
  ret %other
}}
fn @main() -> int {{
b0:
  %x: int = iconst 7
  %y: int = iconst 3
  %c: bool = bconst {c}
  %r: int = call @calc(%x, %y, %c)
  ret %r
}}"
        ));
        let text = func_text(&m, "calc");
        assert_eq!(count(&text, "iadd.chk"), 1, "{text}");
        assert!(text.contains("!0:6:1"), "first check removed: {text}");
        assert_eq!(
            count(&text, "isub.chk"),
            1,
            "different operation lost: {text}"
        );
    }
}

#[test]
fn removes_dead_expression_graphs_but_keeps_unused_faulting_roots() {
    use std::fmt::Write;
    for (x, y) in [(7, 3), (i64::MAX, 1)] {
        let mut src = String::from(
            "module \"dead_graph\"
entry @main
fn @graph(%x: int, %y: int) -> int {
b0:
  %checked: int = iadd.chk %x, %y
  %v0: int = imul %x, %y
",
        );
        for i in 1..512 {
            let prev = i - 1;
            writeln!(src, "  %v{i}: int = iadd %v{prev}, %v{prev}").unwrap();
        }
        write!(
            src,
            "  ret %x
}}
fn @main() -> int {{
b0:
  %x: int = iconst {x}
  %y: int = iconst {y}
  %r: int = call @graph(%x, %y)
  ret %r
}}"
        )
        .unwrap();
        let m = check(&src);
        let text = func_text(&m, "graph");
        assert_eq!(count(&text, "iadd.chk"), 1, "{text}");
        assert!(
            !text.contains("= imul ") && !text.contains("= iadd "),
            "{text}"
        );
    }
}

#[test]
fn folds_scalar_optional_constructors_and_readers() {
    let m = check(
        "module \"known_optional\"
entry @main
fn @read(%x: int) -> int {
b0:
  %some: opt<int> = opt.some %x
  %none: opt<int> = opt.none
  %yes: bool = opt.is_some %some
  %no: bool = opt.is_some %none
  %get: int = opt.get %some
  %unwrap: int = opt.unwrap %some
  %sum: int = iadd %get, %unwrap
  %flag: bool = xor %yes, %no
  %one: int = b2i %flag
  %result: int = iadd %sum, %one
  ret %result
}
fn @main() -> int {
b0:
  %x: int = iconst 5
  %r: int = call @read(%x)
  ret %r
}",
    );
    assert_eq!(observe(&m).0, Ok(11));
    let text = func_text(&m, "read");
    assert!(!text.contains("opt."), "{text}");
}

#[test]
fn optional_folding_keeps_owned_payloads_and_none_unwrap_faults() {
    let m = check(
        "module \"owned_optional\"
entry @main
fn @main() -> int {
b0:
  %literal: str = str \"kept\"
  %s: str = copy %literal
  %o: opt<str> = opt.some %s
  %p: str = opt.get %o
  %n: int = str.len %p
  drop %o
  ret %n
}",
    );
    let text = func_text(&m, "main");
    assert!(
        text.contains("opt.some") && text.contains("opt.get"),
        "{text}"
    );
    assert_eq!(observe(&m).0, Ok(4));
    let m = check(
        "module \"none_unwrap\"
entry @main
fn @main() -> int {
b0:
  %o: opt<int> = opt.none
  %r: int = opt.unwrap %o
  ret %r
}",
    );
    assert!(observe(&m).0.is_err());
    assert!(func_text(&m, "main").contains("opt.unwrap"));
}

#[test]
fn folds_reads_of_a_scalar_list_literal_and_deletes_it() {
    let before = load(
        "module \"known_list\"
entry @main
fn @main() -> int {
b0:
  %a: int = iconst 7
  %b: int = iconst 11
  %zero: int = iconst 0
  %one: int = iconst 1
  %l: list<int> = list.lit %a, %b
  %x: int = list.get.u %l, %zero
  %y: int = list.get %l, %one
  %n: int = list.len %l
  %s: int = iadd %x, %y
  %r: int = iadd %s, %n
  drop %l
  ret %r
}",
    );
    let mut m = before.clone();
    simplify::run(&mut m);
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    // The literal and its one drop are gone; everything else is observed unchanged.
    let (r, out, drops) = observe(&before);
    assert_eq!(observe(&m), (r, out, drops - 1));
    assert_eq!(observe(&m).0, Ok(20));
    let text = func_text(&m, "main");
    assert!(!text.contains("list."), "{text}");
}

#[test]
fn list_literal_folding_keeps_changed_and_out_of_range_lists() {
    let m = check(
        "module \"changed_list\"
entry @main
fn @main() -> int {
b0:
  %a: int = iconst 7
  %two: int = iconst 2
  %l: list<int> = list.lit %a, %a
  %x: int = list.get %l, %two
  drop %l
  ret %x
}",
    );
    assert!(observe(&m).0.is_err());
    assert!(func_text(&m, "main").contains("list.get"));
}
