use ms_mir::opt;
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

const CHAIN: &str = r#"module "main"
file 0 "a.ms"
extern @msrt_string_concat(str, str) -> str
extern @msrt_string_empty() -> str
entry @main

fn @join(%0: str, %1: str, %2: str, %3: str) -> str inline(never) {
b0:
  %4: str = call.rt @msrt_string_concat (%0, %1)
  %5: str = call.rt @msrt_string_concat (%4, %2)
  drop %4
  %6: str = call.rt @msrt_string_concat (%5, %3)
  drop %5
  ret %6
}

fn @main() -> int export {
b0:
  %0: str = call.rt @msrt_string_empty ()
  %1: str = call.rt @msrt_string_empty ()
  %2: str = call.rt @msrt_string_empty ()
  %3: str = call.rt @msrt_string_empty ()
  %4: str = call @join (%0, %1, %2, %3)
  drop %4
  drop %3
  drop %2
  drop %1
  drop %0
  %5: int = iconst 0
  ret %5
}
"#;

/// A left-nested chain of concatenations is one allocation.
#[test]
fn concat_chain_becomes_one_call() {
    let mut m = parse_module(CHAIN).expect("parse");
    verify_module(&m).expect("verify");
    opt::optimize(&mut m, opt::Level::Speed, true);
    verify_module(&m).expect("verify after");
    let text = print_module(&m);
    assert_eq!(
        text.matches("call.rt @msrt_string_concat4").count(),
        1,
        "{text}"
    );
    assert_eq!(
        text.matches("call.rt @msrt_string_concat (").count(),
        0,
        "{text}"
    );
    assert_eq!(text.matches("drop").count(), 5, "{text}");
}

const GROW: &str = r#"module "main"
file 0 "a.ms"
extern @msrt_string_concat(str, str) -> str
extern @msrt_string_empty() -> str
entry @main

fn @grow(%0: str, %1: int) -> str inline(never) {
b0:
  %e: str = call.rt @msrt_string_empty ()
  %z: int = iconst 0
  br b1(%e, %z)
b1(%s: own str, %i: int):
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

/// `s = s.concat(piece)` consumes the old `s` instead of copying it.
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

/// `"p0" + "p1" + ... + "p{n-1}"` as lowering emits it: a left-nested chain whose intermediate
/// results are dropped at the end of the function.
fn long_chain(n: usize) -> String {
    let mut src = String::from(
        "module \"main\"\nfile 0 \"a.ms\"\nextern @msrt_string_concat(str, str) -> str\nentry @main\n\nfn @main() -> int export {\nb0:\n  %0: str = str \"p0\"\n",
    );
    let mut next = 1;
    let mut acc = 0;
    let mut intermediates = Vec::new();
    for i in 1..n {
        let lit = next;
        let cat = next + 1;
        next += 2;
        src.push_str(&format!("  %{lit}: str = str \"p{i}\"\n"));
        src.push_str(&format!(
            "  %{cat}: str = call.rt @msrt_string_concat (%{acc}, %{lit})\n"
        ));
        if i > 1 {
            intermediates.push(acc);
        }
        acc = cat;
    }
    src.push_str(&format!("  %{next}: int = str.len %{acc}\n"));
    for v in intermediates.into_iter().rev() {
        src.push_str(&format!("  drop %{v}\n"));
    }
    src.push_str(&format!("  drop %{acc}\n  ret %{next}\n}}\n"));
    src
}

/// A chain of 1200 pieces fuses in groups within a bounded time. Before the chain walk was
/// bounded, every link walked the whole chain below it on every pass round, which made
/// `ms build` of such a program cubic in the chain's length (64 s for 2000 pieces).
#[test]
fn a_long_concat_chain_fuses_in_linear_rounds() {
    let mut m = parse_module(&long_chain(1200)).expect("parse");
    verify_module(&m).expect("input verifies");
    let start = std::time::Instant::now();
    assert!(opt::strfuse::run(&mut m));
    assert!(
        start.elapsed() < std::time::Duration::from_secs(20),
        "strfuse took {:?}",
        start.elapsed()
    );
    verify_module(&m).expect("output verifies");
    let text = print_module(&m);
    assert!(text.contains("@msrt_string_concat6 ("), "{}", &text[..600]);
    assert!(
        !text.contains("@msrt_string_concat ("),
        "an unfused pair remains"
    );
}

/// Nine pieces joined as a tree whose inner links outnumber what one call joins before the
/// walk has seen all of its leaves: `((p0 + p1) + ((p2 + p3) + p4)) + (p5 + ((p6 + p7) + p8))`.
const DEEP_TREE: &str = r#"module "main"
file 0 "a.ms"
extern @msrt_string_concat(str, str) -> str
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

const INTERP: &str = r#"module "main"
file 0 "a.ms"
extern @msrt_string_concat(str, str) -> str
extern @msrt_int_to_string(int) -> str
extern @msrt_string_empty() -> str
entry @main

fn @label(%0: str, %1: int) -> str inline(never) {
b0:
  %2: str = call.rt @msrt_int_to_string (%1)
  %3: str = call.rt @msrt_string_concat (%0, %2)
  drop %2
  ret %3
}

fn @pair(%0: str, %1: int, %2: int) -> str inline(never) {
b0:
  %3: str = call.rt @msrt_int_to_string (%1)
  %4: str = call.rt @msrt_string_concat (%3, %0)
  drop %3
  %5: str = call.rt @msrt_int_to_string (%2)
  %6: str = call.rt @msrt_string_concat (%4, %5)
  drop %4
  drop %5
  ret %6
}

fn @main() -> int export {
b0:
  %0: str = call.rt @msrt_string_empty ()
  %n: int = iconst 7
  %1: str = call @label (%0, %n)
  %2: str = call @pair (%0, %n, %n)
  drop %2
  drop %1
  drop %0
  %5: int = iconst 0
  ret %5
}
"#;

/// `f"w{i}"` and `f"{a}:{b}"` pass their integers to one `string_fmtN` call instead of building
/// a string for each.
#[test]
fn integer_interpolations_format_into_the_joined_string() {
    let mut m = parse_module(INTERP).expect("parse");
    verify_module(&m).expect("verify");
    opt::optimize(&mut m, opt::Level::Speed, true);
    verify_module(&m).expect("verify after");
    let text = print_module(&m);
    assert_eq!(
        text.matches("call.rt @msrt_int_to_string").count(),
        0,
        "{text}"
    );
    assert_eq!(
        text.matches("call.rt @msrt_string_concat").count(),
        0,
        "{text}"
    );
    assert_eq!(
        text.matches("call.rt @msrt_string_fmt2 (").count(),
        1,
        "{text}"
    );
    assert_eq!(
        text.matches("call.rt @msrt_string_fmt3 (").count(),
        1,
        "{text}"
    );
    // The masks: bit 1 for `w{i}`, bits 0 and 2 for `{a}:{b}`.
    assert!(text.contains("iconst 2"), "{text}");
    assert!(text.contains("iconst 5"), "{text}");
    assert_eq!(text.matches("drop").count(), 3, "{text}");
}
