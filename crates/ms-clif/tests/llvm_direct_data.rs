//! Optionals, alternatives and `switch` emitted straight from MIR (`mir_llvm`) must behave like
//! the Cranelift build.

use crate::native::{Outcome, dir, module, run_native, runtime};
use crate::support;
use ms_clif::{BuildOptions, Options};
use std::process::Command;

/// Compiles `src` with LLVM (direct emission on), links it with the test runtime and runs it.
fn run_llvm(src: &str, opts: &Options, tag: &str) -> Outcome {
    let m = module(src);
    let parts = ms_clif::compile_parts(&m, opts).unwrap_or_else(|e| panic!("{e}"));
    let d = dir();
    let object = d.join(format!("{tag}.o"));
    std::fs::write(&object, parts.object).unwrap();
    let mut extra = vec![runtime().clone()];
    for (i, o) in parts.llvm.iter().enumerate() {
        let p = d.join(format!("{tag}.llvm{i}.o"));
        std::fs::write(&p, o).unwrap();
        extra.push(p);
    }
    let exe = d.join(tag);
    let inputs: Vec<&std::path::Path> = extra.iter().map(|p| p.as_path()).collect();
    support::link_objects(&object, &inputs, &exe).unwrap_or_else(|e| panic!("{e}"));
    let out = Command::new(&exe).output().expect("run");
    Outcome {
        stdout: String::from_utf8_lossy(&out.stdout).replace("\r\n", "\n"),
        code: out.status.code().unwrap_or(-1),
    }
}

/// Release options that emit supported functions directly; `None` when LLVM is not installed.
fn direct() -> Option<Options> {
    let build = BuildOptions {
        llvm_direct: true,
        llvm_units: Some(1),
        keep_ll: true,
        ..BuildOptions::default()
    };
    ms_clif::llvm_available(&build).then(|| Options {
        llvm: Some("3"),
        build,
        ..Options::default()
    })
}

const PROGRAM: &str = r#"module "d"
entry @main
file 0 "d.ms"
alt Shape { Circle(r: float), Rect(w: int, h: int), Dot }
alt Pick { Left(x: int), Right(y: float, z: int) }
fn @area(%s: Shape) -> int !0:1:1 {
b0:
  %t: int = alt.tag %s !0:2:1
  switch %t [0: b1(), 1: b4()] default b5() !0:2:1
b1():
  %r: float = alt.get Shape.Circle.r %s !0:3:1
  %rr: float = fmul %r, %r !0:3:1
  %lim: float = fconst 3.0 !0:3:1
  %big: bool = fcmp.gt %rr, %lim !0:3:1
  br_if %big, b2(), b3() !0:3:1
b2():
  %twelve: int = iconst 12 !0:4:1
  ret %twelve
b3():
  %three: int = iconst 3 !0:5:1
  ret %three
b4():
  %w: int = alt.get Shape.Rect.w %s !0:6:1
  %h: int = alt.get Shape.Rect.h %s !0:6:1
  %a: int = imul %w, %h !0:6:1
  ret %a
b5():
  %one: int = iconst 1 !0:7:1
  ret %one
}
fn @make(%i: int) -> Shape !0:10:1 {
b0:
  %zero: int = iconst 0 !0:11:1
  %is0: bool = icmp.eq %i, %zero !0:11:1
  br_if %is0, b1(), b2() !0:11:1
b1():
  %d: Shape = alt.new Shape.Dot !0:12:1
  ret %d
b2():
  %one: int = iconst 1 !0:13:1
  %is1: bool = icmp.eq %i, %one !0:13:1
  br_if %is1, b3(), b4() !0:13:1
b3():
  %five: int = iconst 5 !0:14:1
  %r: Shape = alt.new Shape.Rect %i, %five !0:14:1
  ret %r
b4():
  %two: float = fconst 2.0 !0:15:1
  %c: Shape = alt.new Shape.Circle %two !0:15:1
  ret %c
}
fn @find(%i: int) -> opt<int> !0:20:1 {
b0:
  %two: int = iconst 2 !0:21:1
  %big: bool = icmp.gt %i, %two !0:21:1
  br_if %big, b1(), b2() !0:21:1
b1():
  %ten: int = iconst 10 !0:22:1
  %v: int = imul %i, %ten !0:22:1
  %s: opt<int> = opt.some %v !0:22:1
  ret %s
b2():
  %n: opt<int> = opt.none !0:23:1
  ret %n
}
fn @orelse(%o: opt<int>, %d: int) -> int !0:30:1 {
b0:
  %has: bool = opt.is_some %o !0:31:1
  br_if %has, b1(), b2() !0:31:1
b1():
  %v: int = opt.get %o !0:32:1
  ret %v
b2():
  ret %d
}
fn @present(%o: opt<str>) -> int !0:40:1 {
b0:
  %has: bool = opt.is_some %o !0:41:1
  %n: int = b2i %has !0:41:1
  ret %n
}
fn @unpick(%p: Pick, %sel: int) -> int !0:50:1 {
b0:
  %t: int = alt.tag %p !0:51:1
  %zero: int = iconst 0 !0:51:1
  switch %t [0: b1(%zero), 1: b1(%zero)] default b2() !0:51:1
b1(%base: int):
  %c: bool = icmp.eq %t, %zero !0:52:1
  br_if %c, b3(), b4() !0:52:1
b2():
  unreachable
b3():
  %x: int = alt.get Pick.Left.x %p !0:53:1
  %r: int = iadd %x, %base !0:53:1
  ret %r
b4():
  %z: int = alt.get Pick.Right.z %p !0:54:1
  %y: float = alt.get Pick.Right.y %p !0:54:1
  %yy: float = fadd %y, %y !0:54:1
  %lim: float = fconst 1.0 !0:54:1
  %hi: bool = fcmp.gt %yy, %lim !0:54:1
  %zi: int = select %hi, %z, %sel !0:54:1
  ret %zi
}
fn @main() -> int !0:60:1 {
b0:
  %z: int = iconst 0 !0:61:1
  br b1(%z, %z) !0:61:1
b1(%i: int, %acc: int):
  %four: int = iconst 4 !0:62:1
  %more: bool = icmp.lt %i, %four !0:62:1
  br_if %more, b2(), b3() !0:62:1
b2():
  %s: Shape = call @make(%i) !0:63:1
  %a: int = call @area(%s) !0:63:1
  %o: opt<int> = call @find(%i) !0:64:1
  %seven: int = iconst 7 !0:64:1
  %f: int = call @orelse(%o, %seven) !0:64:1
  %t1: int = iadd %acc, %a !0:65:1
  %t2: int = iadd %t1, %f !0:65:1
  %one: int = iconst 1 !0:65:1
  %j: int = iadd %i, %one !0:65:1
  br b1(%j, %t2) !0:65:1
b3():
  %lit: str = str "x" !0:70:1
  %some: opt<str> = opt.view %lit !0:70:1
  %none: opt<str> = opt.none !0:70:1
  %p1: int = call @present(%some) !0:70:1
  %p0: int = call @present(%none) !0:70:1
  %ten: int = iconst 10 !0:70:1
  %pp: int = imul %p1, %ten !0:70:1
  %pq: int = iadd %pp, %p0 !0:70:1
  %two: float = fconst 2.0 !0:71:1
  %three: int = iconst 3 !0:71:1
  %pk: Pick = alt.new Pick.Right %two, %three !0:71:1
  %lft: Pick = alt.new Pick.Left %ten !0:71:1
  %nine: int = iconst 9 !0:71:1
  %u1: int = call @unpick(%pk, %nine) !0:71:1
  %u2: int = call @unpick(%lft, %nine) !0:71:1
  %u: int = iadd %u1, %u2 !0:71:1
  %r1: int = iadd %acc, %pq !0:72:1
  %r2: int = iadd %r1, %u !0:72:1
  ret %r2
}
"#;

#[test]
fn direct_optionals_and_alternatives_match_cranelift() {
    let Some(opts) = direct() else { return };
    let _kept = support::KEPT_IR.lock().unwrap_or_else(|e| e.into_inner());
    let want = run_native(PROGRAM, "direct_data-cranelift");
    let got = run_llvm(PROGRAM, &opts, "direct_data");
    let ir = std::fs::read_to_string("ms-keep.ll").unwrap();
    let _ = std::fs::remove_file("ms-keep.ll");
    for f in ["area", "make", "find", "orelse", "present", "unpick"] {
        let header = ir
            .lines()
            .find(|l| l.starts_with("define") && l.contains(&format!("@\"{f}#")))
            .unwrap_or_else(|| panic!("no {f} in the IR"));
        assert!(header.contains("%a0_0"), "{f} was translated: {header}");
    }
    assert!(ir.contains("switch i64 "), "no switch on the tag");
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout));
}
