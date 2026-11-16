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
    // The in-place append is a fast path in the caller; the runtime call is its slow case.
    assert!(text.contains("ptr.storeu"), "{text}");
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

/// A loop that appends a call's result to an accumulator grows the accumulator in place.
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
