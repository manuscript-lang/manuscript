//! Arms with checked arithmetic stay branches: predicating an overflow check costs about as
//! much as the branch it saves, and the first fault must keep its source position.
use ms_mir::interp::Interp;
use ms_mir::ir::Module;
use ms_mir::opt::ifconv;
use ms_mir::{parse::parse_module, verify::verify_module};

fn program(x: i64, y: i64, c: bool, then: &str, els: &str) -> String {
    format!(
        r#"module "overflow"
file 0 "checks.ms"
entry @main
fn @choose(%x: int, %y: int, %c: bool) -> int !0:2:1 {{
b0:
  br_if %c, yes(), no()
yes:
  {then}
  br join(%a)
no:
  {els}
  br join(%b)
join(%r: int):
  ret %r
}}
fn @main() -> int !0:50:1 {{
b0:
  %x: int = iconst {x}
  %y: int = iconst {y}
  %c: bool = bconst {c}
  %r: int = call @choose(%x, %y, %c) !0:51:1
  ret %r
}}
"#
    )
}

fn parse(src: &str) -> Module {
    let m = parse_module(src).unwrap();
    verify_module(&m).unwrap();
    m
}

fn exec(m: &Module) -> (Result<i64, String>, String) {
    let mut it = Interp::new(m);
    let r = it.run_entry().map_err(|e| e.to_string());
    (r, it.stdout().to_string())
}

#[test]
fn checked_arms_stay_branches_and_fault_at_the_taken_arm() {
    let vals = [i64::MIN, -1, 0, 1, i64::MAX - 1, i64::MAX];
    for x in vals {
        for y in vals {
            for c in [false, true] {
                let before = parse(&program(
                    x,
                    y,
                    c,
                    "%p: int = imul.chk %x, %y !0:10:3\n  %a: int = iadd.chk %p, %x !0:11:5",
                    "%b: int = iadd.chk %x, %y !0:20:7",
                ));
                let mut after = before.clone();
                assert!(!ifconv::run(&mut after));
                assert_eq!(exec(&before), exec(&after), "x={x} y={y} c={c}");
            }
        }
    }
}

#[test]
fn unchecked_arms_still_convert() {
    for c in [false, true] {
        let before = parse(&program(
            7,
            9,
            c,
            "%a: int = iadd %x, %y",
            "%b: int = imul %x, %y",
        ));
        let mut after = before.clone();
        assert!(ifconv::run(&mut after));
        verify_module(&after).unwrap_or_else(|e| panic!("{e:?}"));
        assert_eq!(exec(&before), exec(&after));
    }
}
