//! Checked if-conversion must preserve the first fault, its source, and output.
use ms_mir::interp::Interp;
use ms_mir::ir::{Module, Op, Scope};
use ms_mir::opt::{self, Level, ifconv};
use ms_mir::{parse::parse_module, print::print_module, verify::verify_module};

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
fn checked_diamonds_preserve_boundaries_and_first_fault_positions() {
    let vals = [
        i64::MIN,
        i64::MIN + 1,
        -3,
        -1,
        0,
        1,
        3,
        i64::MAX - 1,
        i64::MAX,
    ];
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
                assert!(ifconv::run(&mut after));
                verify_module(&after).unwrap();
                assert_eq!(exec(&before), exec(&after), "x={x} y={y} c={c}");
                let text = print_module(&after);
                assert!(text.contains("select"));
                assert!(!text.contains("imul.chk"));
                assert!(!text.contains("iadd.chk"));
                // The new operations also survive the fixture text boundary.
                assert_eq!(exec(&after), exec(&parse(&text)));
            }
        }
    }
}

#[test]
fn overflow_in_untaken_arm_does_not_fault() {
    for c in [false, true] {
        let (then, els) = if c {
            ("%a: int = iadd %x, %y", "%b: int = imul.chk %x, %x !0:20:1")
        } else {
            ("%a: int = imul.chk %x, %x !0:10:1", "%b: int = iadd %x, %y")
        };
        let mut m = parse(&program(i64::MAX, 0, c, then, els));
        assert!(ifconv::run(&mut m));
        verify_module(&m).unwrap();
        assert_eq!(exec(&m).0, Ok(i64::MAX));
    }
}

#[test]
fn triangle_and_debug_and_inline_scope() {
    let src = program(
        i64::MAX,
        1,
        true,
        "%a: int = iadd.chk %x, %y !0:10:1",
        "%b: int = iadd %x, %y",
    );
    let src = src.replace("br_if %c, yes(), no()", "br_if %c, yes(), join(%x)");
    let mut before = parse(&src);
    before.funcs[0].scopes.push(Scope {
        name: "inlined".into(),
        file: 0,
        parent: 0,
        call_line: 8,
    });
    for b in &mut before.funcs[0].blocks {
        for i in &mut b.insts {
            if i.op == Op::IAddChk {
                i.loc.scope = 1;
            }
        }
    }
    let mut debug = before.clone();
    opt::optimize(&mut debug, Level::None, true);
    assert_eq!(print_module(&debug), print_module(&before));
    let mut after = before.clone();
    assert!(ifconv::run(&mut after));
    verify_module(&after).unwrap();
    assert_eq!(exec(&before), exec(&after));
    let guard = after.funcs[0]
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .find(|i| i.op == Op::IntOverflowIf)
        .unwrap();
    assert_eq!(guard.loc.scope, 1);
    assert_eq!(guard.loc.line, 10);
}

#[test]
fn potentially_trapping_or_effectful_arms_stay_branched() {
    for then in [
        "%a: int = sdiv %x, %y",
        "%a: int = srem %x, %y",
        "%a: int = sdiv.chk %x, %y",
        "poll\n  %a: int = iadd.chk %x, %y",
        "%a: int = isub.chk %x, %y",
    ] {
        let mut m = parse(&program(1, 0, false, then, "%b: int = iadd %x, %y"));
        let before = print_module(&m);
        assert!(!ifconv::run(&mut m), "{then}");
        assert_eq!(print_module(&m), before);
    }
    // A statically negative divisor is deliberately excluded, including -1.
    let src = program(
        i64::MIN,
        -1,
        false,
        "%d: int = iconst -1\n  %a: int = sdiv %x, %d",
        "%b: int = iadd %x, %y",
    );
    assert!(!ifconv::run(&mut parse(&src)));
    for divisor in [0, -1, -2, 1, 2] {
        let src = program(
            i64::MIN,
            0,
            false,
            &format!("%d: int = iconst {divisor}\n  %a: int = sdiv %x, %d"),
            "%b: int = iadd %x, %y",
        );
        let mut m = parse(&src);
        assert_eq!(ifconv::run(&mut m), divisor > 0);
        verify_module(&m).unwrap();
    }
}
