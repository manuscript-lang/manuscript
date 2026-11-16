use ms_mir::opt;
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

const GROW: &str = r#"module "main"
file 0 "a.ms"
extern @msrt_string_concat(str, str) -> str string_concat
extern @msrt_string_empty() -> str
entry @main

fn @grow(%0: str, %1: int) -> str inline(never) {
b0:
  %e: str = call.rt @msrt_string_empty ()
  %z: int = iconst 0
  br b1(%e, %z)
b1(%s: move str, %i: int):
  %lt: bool = icmp.lt %i, %1
  br_if %lt, b2(), b3()
b2():
  %t: str = call.rt @msrt_string_concat (%s, %0)
  drop %s
  %one: int = iconst 1
  %i2: int = iadd.chk %i, %one
  br b1(%t, %i2)
b3():
  ret %s
}

fn @main() -> int export {
b0:
  %0: str = call.rt @msrt_string_empty ()
  %n: int = iconst 3
  %1: str = call @grow (%0, %n)
  drop %1
  drop %0
  %5: int = iconst 0
  ret %5
}
"#;

/// `s = s.concat(piece)` moving_params the old `s` instead of copying it.
#[test]
fn concat_onto_a_dying_string_appends_in_place() {
    let mut m = parse_module(GROW).expect("parse");
    verify_module(&m).expect("verify");
    opt::optimize(&mut m, opt::Level::Speed, true);
    verify_module(&m).expect("verify after");
    let text = print_module(&m);
    assert_eq!(
        text.matches("call.rt @msrt_string_append").count(),
        1,
        "{text}"
    );
    assert_eq!(
        text.matches("call.rt @msrt_string_concat").count(),
        0,
        "{text}"
    );
    assert_eq!(text.matches("drop").count(), 2, "{text}");
}

/// An unoptimized build also appends in place, so a loop that grows a string stays linear.
#[test]
fn an_unoptimized_build_appends_in_place() {
    let mut m = parse_module(GROW).expect("parse");
    opt::optimize(&mut m, opt::Level::None, true);
    let text = print_module(&m);
    assert_eq!(
        text.matches("call.rt @msrt_string_append").count(),
        1,
        "{text}"
    );
}

const SIZED: &str = r#"module "main"
file 0 "a.ms"
extern @msrt_string_concat(str, str) -> str string_concat
extern @msrt_int_to_string(int32) -> str int_to_string
extern @msrt_string_empty() -> str
entry @main

fn @label(%0: str, %1: int32) -> str inline(never) {
b0:
  %2: str = call.rt @msrt_int_to_string (%1)
  %3: str = call.rt @msrt_string_concat (%0, %2)
  drop %2
  ret %3
}

fn @main() -> int export {
b0:
  %0: str = call.rt @msrt_string_empty ()
  %w: int = iconst 7
  %n: int32 = conv %w
  %1: str = call @label (%0, %n)
  drop %1
  drop %0
  %5: int = iconst 0
  ret %5
}
"#;

/// A sized integer's text is declared with its own width, which `string_fmtN` does not take: the
/// chain keeps its `int_to_string`.
#[test]
fn sized_integer_text_is_not_fused() {
    let mut m = parse_module(SIZED).expect("parse");
    verify_module(&m).expect("verify");
    opt::optimize(&mut m, opt::Level::Speed, true);
    verify_module(&m).expect("verify after");
    let text = print_module(&m);
    assert_eq!(
        text.matches("call.rt @msrt_int_to_string").count(),
        1,
        "{text}"
    );
    assert!(!text.contains("string_fmt"), "{text}");
}

/// Nine pieces joined as a tree whose inner links outnumber what one call joins before the
/// walk has seen all of its leaves: `((p0 + p1) + ((p2 + p3) + p4)) + (p5 + ((p6 + p7) + p8))`.
const DEEP_TREE: &str = r#"module "main"
file 0 "a.ms"
extern @msrt_string_concat(str, str) -> str string_concat
entry @main

fn @main() -> int export {
b0:
  %0: str = str "p0"
  %1: str = str "p1"
  %2: str = str "p2"
  %3: str = str "p3"
  %4: str = str "p4"
  %5: str = str "p5"
  %6: str = str "p6"
  %7: str = str "p7"
  %8: str = str "p8"
  %9: str = call.rt @msrt_string_concat (%0, %1)
  %10: str = call.rt @msrt_string_concat (%2, %3)
  %11: str = call.rt @msrt_string_concat (%10, %4)
  %12: str = call.rt @msrt_string_concat (%9, %11)
  %13: str = call.rt @msrt_string_concat (%6, %7)
  %14: str = call.rt @msrt_string_concat (%13, %8)
  %15: str = call.rt @msrt_string_concat (%5, %14)
  %16: str = call.rt @msrt_string_concat (%12, %15)
  %17: int = str.len %16
  drop %9
  drop %10
  drop %11
  drop %12
  drop %13
  drop %14
  drop %15
  drop %16
  ret %17
}
"#;

/// Cutting the chain walk short must keep the value it stops at as a leaf. When the cut-off
/// value vanished instead, this tree fused into one call of six pieces and lost `p6`, `p7`
/// and `p8` (conformance fixture `fuzz/run/seed-0178` printed a truncated string).
#[test]
fn a_cut_off_chain_keeps_every_piece() {
    let mut m = parse_module(DEEP_TREE).expect("parse");
    verify_module(&m).expect("input verifies");
    opt::strfuse::run(&mut m);
    verify_module(&m).expect("output verifies");
    let f = &m.funcs[m.func_by_name("main").expect("main").index()];
    let used: std::collections::HashSet<_> = f
        .blocks
        .iter()
        .flat_map(|b| b.insts.iter().flat_map(|i| i.args.iter().copied()))
        .collect();
    let text = print_module(&m);
    for b in &f.blocks {
        for i in &b.insts {
            if i.op == ms_mir::ir::Op::StrLit {
                let r = i.res.expect("literal result");
                assert!(
                    used.contains(&r),
                    "piece %{} dropped from the join:\n{text}",
                    r.index()
                );
            }
        }
    }
}

/// `n` independent `out.append(f"row {i}\n")` calls on one builder in one function.
fn many_appends(n: usize) -> String {
    let mut s = String::from(
        r#"module "main"
file 0 "a.ms"
extern @msrt_int_to_string(int) -> str fresh int_to_string
extern @msrt_string_concat(str, str) -> str fresh string_concat
extern @msrt_strbuilder_append(ptr, str) -> void strbuilder_append
entry @main

fn @fill(%0: ptr, %1: int) -> void inline(never) {
b0:
"#,
    );
    let mut v = 2;
    for _ in 0..n {
        s.push_str(&format!(
            "  %{v}: str = str \"row \"\n  %{}: str = call.rt @msrt_int_to_string (%1)\n  %{}: str = call.rt @msrt_string_concat (%{v}, %{})\n  drop %{}\n  %{}: void = call.rt @msrt_strbuilder_append (%0, %{})\n  drop %{}\n",
            v + 1,
            v + 2,
            v + 1,
            v + 1,
            v + 3,
            v + 2,
            v + 2
        ));
        v += 4;
    }
    s.push_str(&format!("  %{v}: void = void\n  ret %{v}\n}}\n"));
    s.push_str("\nfn @main() -> int export {\nb0:\n  %0: int = iconst 0\n  ret %0\n}\n");
    s
}

/// Each append used to rescan and rewrite the whole function, so many appends in one function
/// were quadratic.
#[test]
fn many_appends_in_one_function_take_linear_time() {
    let n = 12_000;
    let mut m = parse_module(&many_appends(n)).expect("parse");
    verify_module(&m).expect("verify");
    let start = std::time::Instant::now();
    ms_mir::opt::strfuse::run(&mut m);
    let took = start.elapsed();
    verify_module(&m).expect("verify after");
    assert!(took.as_secs() < 5, "took {took:?}");
    let text = print_module(&m);
    assert_eq!(
        text.matches("@msrt_strbuilder_append_int (").count(),
        n,
        "{text}"
    );
    assert_eq!(text.matches("@msrt_string_concat (").count(), 0, "{text}");
}

/// A leaf that is dropped on another path (a branch that returns elsewhere) is not dropped before
/// the join, so the chain still fuses. A leaf the loop drops and redefines each iteration is a
/// different value than the one a later iteration joins.
const LOOP_CALL: &str = r#"module "main"
file 0 "a.ms"
extern @msrt_string_concat(str, str) -> str string_concat
extern @msrt_int_to_string(int) -> str int_to_string
extern @msrt_string_empty() -> str
entry @main

fn @piece(%0: int) -> str inline(never) {
b0:
  %1: str = call.rt @msrt_int_to_string (%0)
  ret %1
}

fn @main() -> int export {
b0:
  %0: str = call.rt @msrt_string_empty ()
  %1: int = iconst 0
  %2: int = iconst 10
  %3: int = iconst 1
  br b1(%1, %0)
b1(%4: int, %5: move str):
  %6: bool = icmp.lt %4, %2
  br_if %6, b2(), b3()
b2():
  %7: str = call @piece (%4)
  %8: str = call.rt @msrt_string_concat (%5, %7)
  drop %5
  drop %7
  %9: int = iadd %4, %3
  br b1(%9, %8)
b3():
  drop %5
  %10: int = iconst 0
  ret %10
}
"#;

/// `s += f(x)` with a non-literal right side also grows the accumulator in place.
#[test]
fn appending_a_call_result_in_a_loop_grows_the_accumulator_in_place() {
    let mut m = parse_module(LOOP_CALL).expect("parse");
    verify_module(&m).expect("verify");
    opt::optimize(&mut m, opt::Level::Speed, true);
    let text = print_module(&m);
    assert_eq!(
        text.matches("call.rt @msrt_string_append").count(),
        1,
        "{text}"
    );
}
