//! Stage 0 of `proposals/elaborate-drops.md`: hand-written Raw MIR (markers, no scope-end
//! drops) elaborated by `ms_mir::elaborate`, then verified and run. The oracle is the verifier
//! on the output and the order of the closes the program prints.

use ms_mir::interp::Interp;
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

const HEAD: &str = r#"module "raw"
extern @msrt_print_int(int)
extern @msrt_raw_begin(int, int)
extern @msrt_raw_own(list<int>, int, int)
extern @msrt_raw_end(int)
entry @main
fn @mk(%id: int) -> list<int> {
b0:
  %cap: int = iconst 0
  %l0: list<int> = list.new %cap
  %l: list<int> = list.push %l0, %id
  ret %l
}
fn @close(%r: move list<int>) -> int {
b0:
  %z: int = iconst 0
  %id: int = list.get %r, %z
  %u: unit = call.rt @msrt_print_int (%id)
  drop %r
  ret %id
}
"#;

/// Elaborates and runs `body` (functions and `main`), returning the exit value and output.
fn elaborate_and_run(body: &str) -> (i64, String) {
    let mut m = parse_module(&format!("{HEAD}{body}")).unwrap_or_else(|e| panic!("{e}"));
    ms_mir::elaborate::run(&mut m).unwrap_or_else(|e| panic!("{e}"));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    let mut it = Interp::new(&m);
    let r = it.run_entry().unwrap_or_else(|f| panic!("{f}"));
    (r, it.stdout().to_string())
}

/// Two nested closing resources; closes print their id and fail when it is nonzero.
fn nested(n1: i64, n2: i64) -> String {
    format!(
        r#"fn @f(%n1: int, %n2: int) -> int {{
b0:
  %c1: int = iconst 1
  %c2: int = iconst 2
  %root: int = iconst -1
  %k: int = iconst 1
  %u1: unit = call.rt @msrt_raw_begin (%c1, %root)
  %a: list<int> = call @mk (%n1)
  %u2: unit = call.rt @msrt_raw_own (%a, %c1, %k)
  %u3: unit = call.rt @msrt_raw_begin (%c2, %c1)
  %b: list<int> = call @mk (%n2)
  %u4: unit = call.rt @msrt_raw_own (%b, %c2, %k)
  %r: int = iconst 7
  %u5: unit = call.rt @msrt_raw_end (%c2)
  %u6: unit = call.rt @msrt_raw_end (%c1)
  ret %r
}}
fn @main() -> int {{
b0:
  %x: int = iconst {n1}
  %y: int = iconst {n2}
  %r: int = call @f (%x, %y)
  ret %r
}}
"#
    )
}

#[test]
fn nested_closes_run_inner_first_and_the_first_error_wins() {
    // (outer id, inner id) -> (result, close order)
    assert_eq!(elaborate_and_run(&nested(0, 0)), (7, "0\n0\n".into()));
    assert_eq!(elaborate_and_run(&nested(3, 0)), (3, "0\n3\n".into()));
    assert_eq!(elaborate_and_run(&nested(0, 4)), (4, "4\n0\n".into()));
    assert_eq!(elaborate_and_run(&nested(3, 4)), (4, "4\n3\n".into()));
}

/// An arm that consumes the scrutinee leaves nothing to close; the other arm closes it. No
/// "already closed on this path" state: the live set decides.
fn arms(flag: i64) -> String {
    format!(
        r#"fn @g(%flag: int) -> int {{
b0:
  %c1: int = iconst 1
  %root: int = iconst -1
  %k: int = iconst 1
  %zero: int = iconst 0
  %one: int = iconst 1
  %u1: unit = call.rt @msrt_raw_begin (%c1, %root)
  %a: list<int> = call @mk (%flag)
  %u2: unit = call.rt @msrt_raw_own (%a, %c1, %k)
  %c: bool = icmp.eq %flag, %zero
  br_if %c, take(), keep()
take:
  %x: list<int> = list.push %a, %one
  drop %x
  %r10: int = iconst 10
  %u3: unit = call.rt @msrt_raw_end (%c1)
  ret %r10
keep:
  %r20: int = iconst 20
  %u4: unit = call.rt @msrt_raw_end (%c1)
  ret %r20
}}
fn @main() -> int {{
b0:
  %x: int = iconst {flag}
  %r: int = call @g (%x)
  ret %r
}}
"#
    )
}

#[test]
fn an_arm_that_consumed_the_value_is_not_closed_again() {
    assert_eq!(elaborate_and_run(&arms(0)), (10, String::new()));
    assert_eq!(elaborate_and_run(&arms(5)), (5, "5\n".into()));
}
