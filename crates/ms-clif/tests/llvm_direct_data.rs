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
alt Wrap { Flag(on: bool, n: int), Items(l: list<int>) }
alt Narrow { A(n: int8), B(w: uint16, v: int32) }
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
fn @wrap_len(%w: Wrap) -> int !0:56:1 {
b0:
  %t: int = alt.tag %w !0:57:1
  %zero: int = iconst 0 !0:57:1
  %isf: bool = icmp.eq %t, %zero !0:57:1
  br_if %isf, b1(), b2() !0:57:1
b1():
  %on: bool = alt.get Wrap.Flag.on %w !0:58:1
  %n: int = alt.get Wrap.Flag.n %w !0:58:1
  %r: int = select %on, %n, %zero !0:58:1
  ret %r
b2():
  %l: list<int> = alt.get Wrap.Items.l %w !0:59:1
  %len: int = list.len %l !0:59:1
  ret %len
}
fn @narrow(%s: Narrow) -> int !0:80:1 {
b0:
  %t: int = alt.tag %s !0:81:1
  %zero: int = iconst 0 !0:81:1
  %isa: bool = icmp.eq %t, %zero !0:81:1
  br_if %isa, b1(), b2() !0:81:1
b1():
  %n: int8 = alt.get Narrow.A.n %s !0:82:1
  %three: int8 = iconst 3 !0:82:1
  %is3: bool = icmp.eq %n, %three !0:82:1
  %r: int = b2i %is3 !0:82:1
  ret %r
b2():
  %w: uint16 = alt.get Narrow.B.w %s !0:83:1
  %f: int32 = alt.get Narrow.B.v %s !0:83:1
  %lim: int32 = iconst 1 !0:83:1
  %hi: bool = icmp.gt %f, %lim !0:83:1
  %nine: uint16 = iconst 9 !0:83:1
  %isw: bool = icmp.eq %w, %nine !0:83:1
  %both: bool = and %hi, %isw !0:83:1
  %k: int = b2i %both !0:83:1
  %ten: int = iconst 10 !0:83:1
  %r2: int = iadd %k, %ten !0:83:1
  ret %r2
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
  %yes: bool = bconst true !0:73:1
  %w1: Wrap = alt.new Wrap.Flag %yes, %nine !0:73:1
  %a1: int = iconst 1 !0:73:1
  %a2: int = iconst 2 !0:73:1
  %items: list<int> = list.lit %a1, %a2, %ten !0:73:1
  %w2: Wrap = alt.new Wrap.Items %items !0:73:1
  %l1: int = call @wrap_len(%w1) !0:73:1
  %l2: int = call @wrap_len(%w2) !0:73:1
  drop %w2 !0:73:1
  drop %w1 !0:73:1
  %ll: int = iadd %l1, %l2 !0:73:1
  %u3: int = iadd %u, %ll !0:73:1
  %n3: int8 = iconst 3 !0:74:1
  %na: Narrow = alt.new Narrow.A %n3 !0:74:1
  %w9: uint16 = iconst 9 !0:74:1
  %h: int32 = iconst 5 !0:74:1
  %nb: Narrow = alt.new Narrow.B %w9, %h !0:74:1
  %m1: int = call @narrow(%na) !0:74:1
  %m2: int = call @narrow(%nb) !0:74:1
  %mm: int = iadd %m1, %m2 !0:74:1
  %u4: int = iadd %u3, %mm !0:74:1
  %r1: int = iadd %acc, %pq !0:72:1
  %r2: int = iadd %r1, %u4 !0:72:1
  ret %r2
}
"#;

/// Run from `llvm_direct`'s one test: each build writes `ms-keep.ll` in the working directory, so
/// two tests building with `keep_ll` in parallel processes would read each other's IR.
pub fn optionals_and_alternatives_match_cranelift() {
    let Some(opts) = direct() else { return };
    let want = run_native(PROGRAM, "direct_data-cranelift");
    let got = run_llvm(PROGRAM, &opts, "direct_data");
    let ir = std::fs::read_to_string("ms-keep.ll").unwrap();
    let _ = std::fs::remove_file("ms-keep.ll");
    for f in [
        "area", "make", "find", "orelse", "present", "unpick", "wrap_len", "narrow",
    ] {
        let header = ir
            .lines()
            .find(|l| l.starts_with("define") && l.contains(&format!("@\"{f}#")))
            .unwrap_or_else(|| panic!("no {f} in the IR"));
        // Direct code takes a list by borrowed pointer and the other values as leaves.
        let direct = header.contains("%a0_0") || header.contains("dereferenceable");
        assert!(direct, "{f} was translated: {header}");
    }
    assert!(ir.contains("switch i64 "), "no switch on the tag");
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout));
}

/// Narrow integers in list elements and across calls: `Int8` sign-extends and `UInt16` zero-extends
/// when read back from their 1 and 2 byte slots, and `narrow.chk` and `inarrow.opt` test the range.
const NARROW: &str = r#"module "d"
entry @main
file 0 "d.ms"
fn @pack8(%a: int8, %b: int8) -> list<int8> inline(never) !0:1:1 {
b0:
  %l: list<int8> = list.lit %a, %b !0:2:1
  ret %l
}
fn @read8(%l: list<int8>, %i: int) -> int8 inline(never) !0:3:1 {
b0:
  %x: int8 = list.get %l, %i !0:4:1
  ret %x
}
fn @read16(%l: list<uint16>, %i: int) -> uint16 inline(never) !0:5:1 {
b0:
  %x: uint16 = list.get %l, %i !0:6:1
  ret %x
}
fn @fit(%x: int) -> int inline(never) !0:7:1 {
b0:
  %o: opt<int8> = inarrow.opt %x !0:8:1
  %ok: bool = opt.is_some %o !0:8:1
  %one: int = iconst 1 !0:8:1
  %zero: int = iconst 0 !0:8:1
  %r: int = select %ok, %one, %zero !0:8:1
  ret %r
}
fn @chk(%x: int) -> int8 inline(never) !0:9:1 {
b0:
  %y: int8 = narrow.chk %x !0:10:1
  ret %y
}
fn @main() -> int !0:20:1 {
b0:
  %neg: int = iconst -3 !0:21:1
  %big: int = iconst 200 !0:21:1
  %hi: int = iconst 60000 !0:21:1
  %on: opt<int8> = inarrow.opt %neg !0:21:1
  %bn: opt<int8> = inarrow.opt %big !0:21:1
  %n8: int8 = opt.get %on !0:21:1
  %m8: int8 = iconst 100 !0:21:1
  %l8: list<int8> = call @pack8(%n8, %m8) !0:22:1
  %zero: int = iconst 0 !0:22:1
  %one: int = iconst 1 !0:22:1
  %r0: int8 = call @read8(%l8, %zero) !0:22:1
  %r1: int8 = call @read8(%l8, %one) !0:22:1
  drop %l8 !0:22:1
  %e0: bool = icmp.eq %r0, %n8 !0:23:1
  %e1: bool = icmp.eq %r1, %m8 !0:23:1
  %neg0: bool = icmp.lt %r0, %m8 !0:23:1
  %f0: int = call @fit(%neg) !0:24:1
  %f1: int = call @fit(%big) !0:24:1
  %c: int8 = call @chk(%neg) !0:24:1
  %a: int = select %e0, %one, %zero !0:25:1
  %b: int = select %e1, %one, %zero !0:25:1
  %d: int = select %neg0, %one, %zero !0:25:1
  %s1: int = iadd %a, %b !0:26:1
  %s2: int = iadd %s1, %d !0:26:1
  %s3: int = iadd %s2, %f0 !0:26:1
  %s4: int = iadd %s3, %f1 !0:26:1
  ret %s4
}
"#;

/// Run from `llvm_direct`'s one test (see above).
pub fn narrow_integers_match_cranelift() {
    let Some(opts) = direct() else { return };
    let want = run_native(NARROW, "direct_narrow-cranelift");
    assert_eq!(want.code, 4, "the Cranelift build disagrees");
    let got = run_llvm(NARROW, &opts, "direct_narrow");
    let ir = std::fs::read_to_string("ms-keep.ll").unwrap();
    let _ = std::fs::remove_file("ms-keep.ll");
    for f in ["pack8", "read8", "fit", "chk"] {
        let header = ir
            .lines()
            .find(|l| l.starts_with("define") && l.contains(&format!("@\"{f}#")))
            .unwrap_or_else(|| panic!("no {f} in the IR"));
        let direct = header.contains("%a0_0") || header.contains("dereferenceable");
        assert!(direct, "{f} was translated: {header}");
    }
    assert!(ir.contains("sext i8 "), "no sign extension of a byte");
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout));
}

/// A type of more than eight leaves lives in memory: its `Int8`, `UInt16` and `Int32` fields are
/// 1, 2 and 4 bytes there and read back sign- or zero-extended.
const NARROW_TYPE: &str = r#"module "d"
type Wide { a: int8, b: uint16, c: int32, d: int, e: int, f: int, g: int, h: int, i: int }
entry @main
file 0 "d.ms"
fn @mk(%a: int8, %b: uint16, %c: int32, %n: int) -> Wide inline(never) !0:1:1 {
b0:
  %w: Wide = type.new Wide %a, %b, %c, %n, %n, %n, %n, %n, %n !0:2:1
  ret %w
}
fn @sum(%w: Wide) -> int inline(never) !0:3:1 {
b0:
  %a: int8 = type.get Wide.a %w !0:4:1
  %b: uint16 = type.get Wide.b %w !0:4:1
  %c: int32 = type.get Wide.c %w !0:4:1
  %zero: int = iconst 0 !0:4:1
  %one: int = iconst 1 !0:4:1
  %m8: int8 = iconst -3 !0:4:1
  %ea: bool = icmp.eq %a, %m8 !0:4:1
  %hi: uint16 = iconst 60000 !0:4:1
  %eb: bool = icmp.eq %b, %hi !0:4:1
  %m32: int32 = iconst -70000 !0:4:1
  %ec: bool = icmp.eq %c, %m32 !0:4:1
  %x: int = select %ea, %one, %zero !0:5:1
  %y: int = select %eb, %one, %zero !0:5:1
  %z: int = select %ec, %one, %zero !0:5:1
  %s1: int = iadd %x, %y !0:5:1
  %s2: int = iadd %s1, %z !0:5:1
  ret %s2
}
fn @main() -> int !0:20:1 {
b0:
  %n: int = iconst 7 !0:21:1
  %o8: opt<int8> = inarrow.opt %n !0:21:1
  %a: int8 = opt.get %o8 !0:21:1
  %neg3: int = iconst -3 !0:21:1
  %on: opt<int8> = inarrow.opt %neg3 !0:21:1
  %m8: int8 = opt.get %on !0:21:1
  %big: int = iconst 60000 !0:21:1
  %ob: opt<uint16> = inarrow.opt %big !0:21:1
  %b: uint16 = opt.get %ob !0:21:1
  %m: int = iconst -70000 !0:21:1
  %oc: opt<int32> = inarrow.opt %m !0:21:1
  %c: int32 = opt.get %oc !0:21:1
  %w: Wide = call @mk(%m8, %b, %c, %n) !0:22:1
  %r: int = call @sum(%w) !0:23:1
  ret %r
}
"#;

/// Run from `llvm_direct`'s one test (see above).
pub fn narrow_type_fields_match_cranelift() {
    let Some(opts) = direct() else { return };
    let want = run_native(NARROW_TYPE, "direct_narrow_type-cranelift");
    assert_eq!(want.code, 3, "the Cranelift build disagrees");
    let got = run_llvm(NARROW_TYPE, &opts, "direct_narrow_type");
    let ir = std::fs::read_to_string("ms-keep.ll").unwrap();
    let _ = std::fs::remove_file("ms-keep.ll");
    for f in ["mk", "sum"] {
        let header = ir
            .lines()
            .find(|l| l.starts_with("define") && l.contains(&format!("@\"{f}#")))
            .unwrap_or_else(|| panic!("no {f} in the IR"));
        let direct = header.contains("%a0_0") || header.contains("dereferenceable");
        assert!(direct, "{f} was translated: {header}");
    }
    assert!(ir.contains("load i16"), "no two byte load");
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout));
}

const UNWRAP_PROGRAM: &str = r#"module "d"
entry @main
file 0 "d.ms"
alt Name { Text(s: str), Count(n: int) }
type Pair { name: str, tag: str, n: int }
type Big { a: int, b: int, c: int, d: int, e: int, f: int, g: int, h: int, name: str, n: int }
fn @unwrap_int(%o: opt<int>) -> int !0:1:1 {
b0:
  %v: int = opt.unwrap %o !0:2:1
  ret %v
}
fn @unwrap_len(%o: opt<str>) -> int !0:10:1 {
b0:
  %s: str = opt.unwrap %o !0:11:1
  drop %s !0:13:1
  %n: int = iconst 5 !0:12:1
  ret %n
}
fn @unwrap_list(%o: opt<list<int>>) -> int !0:60:1 {
b0:
  %l: list<int> = opt.unwrap %o !0:61:1
  %n: int = list.len %l !0:62:1
  drop %l !0:63:1
  ret %n
}
fn @release_pair(%p: move Pair) -> int !0:40:1 {
b0:
  %n: int = type.get Pair.n %p !0:41:1
  type.release Pair.tag %p !0:42:1
  ret %n
}
fn @release_big(%p: move Big) -> int !0:50:1 {
b0:
  %n: int = type.get Big.n %p !0:51:1
  type.release Big %p !0:52:1
  ret %n
}
fn @main() -> int !0:30:1 {
b0:
  %n: int = iconst 37 !0:31:1
  %on: opt<int> = opt.some %n !0:31:1
  %a: int = call @unwrap_int(%on) !0:31:1
  %lit: str = str "hello" !0:32:1
  %os: opt<str> = opt.view %lit !0:32:1
  %b: int = call @unwrap_len(%os) !0:32:1
  %k: int = iconst 3 !0:35:1
  %i1: int = iconst 1 !0:38:1
  %i2: int = iconst 2 !0:38:1
  %lst: list<int> = list.lit %i1, %i2, %k !0:38:1
  %ol: opt<list<int>> = opt.view %lst !0:38:1
  %g: int = call @unwrap_list(%ol) !0:38:1
  drop %lst !0:38:1
  %s1: str = clone %lit !0:35:1
  %s2: str = clone %lit !0:35:1
  %p: Pair = type.new Pair %s1, %s2, %k !0:35:1
  %d: int = call @release_pair(%p) !0:35:1
  %s3: str = clone %lit !0:36:1
  %q: Big = type.new Big %k, %k, %k, %k, %k, %k, %k, %k, %s3, %k !0:36:1
  %e: int = call @release_big(%q) !0:36:1
  %ab: int = iadd %a, %b !0:34:1
  %ac: int = iadd %ab, %b !0:34:1
  %ad: int = iadd %ac, %d !0:37:1
  %ae: int = iadd %ad, %g !0:37:1
  %r: int = iadd %ae, %e !0:37:1
  ret %r
}
"#;

/// Unwrapping an optional (an integer, and a string that is cloned) and releasing types; run from `llvm_direct`'s one test for the same reason.
pub fn unwrap_and_own_match_cranelift() {
    let Some(opts) = direct() else { return };
    let want = run_native(UNWRAP_PROGRAM, "direct_unwrap-cranelift");
    let got = run_llvm(UNWRAP_PROGRAM, &opts, "direct_unwrap");
    let ir = std::fs::read_to_string("ms-keep.ll").unwrap();
    let _ = std::fs::remove_file("ms-keep.ll");
    for f in [
        "unwrap_int",
        "unwrap_len",
        "unwrap_list",
        "release_pair",
        "release_big",
    ] {
        let header = ir
            .lines()
            .find(|l| l.starts_with("define") && l.contains(&format!("@\"{f}#")))
            .unwrap_or_else(|| panic!("no {f} in the IR"));
        let direct = header.contains("%a0_0") || header.contains("dereferenceable");
        assert!(direct, "{f} was translated: {header}");
    }
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout));
    assert_eq!(got.code, 37 + 5 + 5 + 3 + 3 + 3);
}

const BOXED_PROGRAM: &str = r#"module "d"
entry @main
file 0 "d.ms"
alt Tree { Leaf, Node(l: Tree, v: int, r: Tree), Tag(s: str, n: int) }
alt Two { A(s: str, n: int), B }
alt Chain { Nil, Cons(h: str, t: Chain) }
fn @value(%t: Tree) -> int !0:1:1 {
b0:
  %k: int = alt.tag %t !0:2:1
  switch %k [1: b1(), 2: b2()] default b3() !0:2:1
b1():
  %v: int = alt.get Tree.Node.v %t !0:3:1
  ret %v
b2():
  %n: int = alt.get Tree.Tag.n %t !0:4:1
  ret %n
b3():
  %z: int = iconst 0 !0:5:1
  ret %z
}
fn @unbox_node(%t: move Tree) -> int !0:10:1 {
b0:
  %v: int = alt.unbox Tree.Node.v %t !0:11:1
  ret %v
}
fn @release_tag(%t: move Tree) -> int !0:20:1 {
b0:
  %n: int = alt.get Tree.Tag.n %t !0:21:1
  alt.release Tree.Tag.n %t !0:22:1
  ret %n
}
fn @release_two(%p: move Two) -> int !0:30:1 {
b0:
  %n: int = alt.get Two.A.n %p !0:31:1
  alt.release Two.A.n %p !0:32:1
  ret %n
}
fn @main() -> int !0:40:1 {
b0:
  %l1: Tree = alt.new Tree.Leaf !0:41:1
  %l2: Tree = alt.new Tree.Leaf !0:41:1
  %nine: int = iconst 9 !0:41:1
  %node: Tree = alt.new Tree.Node %l1, %nine, %l2 !0:41:1
  %lit: str = str "hello" !0:42:1
  %s: str = clone %lit !0:42:1
  %four: int = iconst 4 !0:42:1
  %tag: Tree = alt.new Tree.Tag %s, %four !0:42:1
  %a: int = call @value(%node) !0:43:1
  %b: int = call @value(%tag) !0:43:1
  %c: int = call @unbox_node(%node) !0:44:1
  %d: int = call @release_tag(%tag) !0:45:1
  %s2: str = clone %lit !0:46:1
  %five: int = iconst 5 !0:46:1
  %two: Two = alt.new Two.A %s2, %five !0:46:1
  %e: int = call @release_two(%two) !0:46:1
  %n1: Chain = alt.new Chain.Nil !0:48:1
  %h1: str = clone %lit !0:48:1
  %c1: Chain = alt.new Chain.Cons %h1, %n1 !0:48:1
  %h2: str = clone %lit !0:48:1
  %c2: Chain = alt.new Chain.Cons %h2, %c1 !0:48:1
  drop %c2 !0:48:1
  %t1: Tree = alt.new Tree.Leaf !0:49:1
  %t2: Tree = alt.new Tree.Leaf !0:49:1
  %s3: str = clone %lit !0:49:1
  %tg: Tree = alt.new Tree.Tag %s3, %four !0:49:1
  %nd: Tree = alt.new Tree.Node %tg, %nine, %t1 !0:49:1
  drop %nd !0:49:1
  drop %t2 !0:49:1
  %s4: str = clone %lit !0:49:1
  %tw: Two = alt.new Two.A %s4, %five !0:49:1
  drop %tw !0:49:1
  %ab: int = iadd %a, %b !0:47:1
  %cd: int = iadd %c, %d !0:47:1
  %abcd: int = iadd %ab, %cd !0:47:1
  %r: int = iadd %abcd, %e !0:47:1
  ret %r
}
"#;

/// Boxed enums (allocation, shared payloadless blocks, tag and payload reads, unbox and release
/// with drops), and an inline enum release that drops a string; run from `llvm_direct`'s one test.
pub fn boxed_enums_match_cranelift() {
    let Some(opts) = direct() else { return };
    let want = run_native(BOXED_PROGRAM, "direct_boxed-cranelift");
    let got = run_llvm(BOXED_PROGRAM, &opts, "direct_boxed");
    let ir = std::fs::read_to_string("ms-keep.ll").unwrap();
    let _ = std::fs::remove_file("ms-keep.ll");
    for f in ["value", "unbox_node", "release_tag", "release_two"] {
        let header = ir
            .lines()
            .find(|l| l.starts_with("define") && l.contains(&format!("@\"{f}#")))
            .unwrap_or_else(|| panic!("no {f} in the IR"));
        let direct = header.contains("%a0_0") || header.contains("dereferenceable");
        assert!(direct, "{f} was translated: {header}");
    }
    assert!(ir.contains("!range"), "the tag load has a range");
    // Drop glue of enums is written directly: its native entry has a body here.
    assert!(
        ir.lines()
            .any(|l| l.starts_with("define") && l.contains(".n\"(")),
        "no direct glue"
    );
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout));
    assert_eq!(got.code, 9 + 4 + 9 + 4 + 5);
}

const ENUM_CLONE_PROGRAM: &str = r#"module "d"
entry @main
file 0 "d.ms"
alt Tree { Leaf, Node(l: Tree, v: int, r: Tree), Tag(s: str, n: int) }
alt Chain { Nil, Cons(h: str, t: Chain) }
alt Name { Text(s: str), Count(n: int) }
fn @value(%t: Tree) -> int inline(never) !0:1:1 {
b0:
  %k: int = alt.tag %t !0:2:1
  switch %k [1: b1(), 2: b2()] default b3() !0:2:1
b1():
  %v: int = alt.get Tree.Node.v %t !0:3:1
  ret %v
b2():
  %n: int = alt.get Tree.Tag.n %t !0:4:1
  ret %n
b3():
  %z: int = iconst 0 !0:5:1
  ret %z
}
fn @depth(%c: Chain) -> int inline(never) !0:10:1 {
b0:
  %k: int = alt.tag %c !0:11:1
  switch %k [1: b1()] default b2() !0:11:1
b1():
  %t: Chain = alt.get Chain.Cons.t %c !0:12:1
  %d: int = call @depth(%t) !0:12:1
  %one: int = iconst 1 !0:12:1
  %r: int = iadd %d, %one !0:12:1
  ret %r
b2():
  %z: int = iconst 0 !0:13:1
  ret %z
}
fn @count(%n: Name) -> int inline(never) !0:20:1 {
b0:
  %k: int = alt.tag %n !0:21:1
  switch %k [1: b1()] default b2() !0:21:1
b1():
  %v: int = alt.get Name.Count.n %n !0:22:1
  ret %v
b2():
  %z: int = iconst 100 !0:23:1
  ret %z
}
fn @main() -> int !0:40:1 {
b0:
  %lit: str = str "a long string that is certainly stored on the heap" !0:41:1
  %l1: Tree = alt.new Tree.Leaf !0:42:1
  %l2: Tree = alt.new Tree.Leaf !0:42:1
  %nine: int = iconst 9 !0:42:1
  %node: Tree = alt.new Tree.Node %l1, %nine, %l2 !0:42:1
  %s1: str = clone %lit !0:43:1
  %four: int = iconst 4 !0:43:1
  %tag: Tree = alt.new Tree.Tag %s1, %four !0:43:1
  %nc: Tree = clone %node !0:44:1
  %tc: Tree = clone %tag !0:44:1
  drop %node !0:44:1
  drop %tag !0:44:1
  %a: int = call @value(%nc) !0:45:1
  %b: int = call @value(%tc) !0:45:1
  drop %nc !0:45:1
  drop %tc !0:45:1
  %n1: Chain = alt.new Chain.Nil !0:46:1
  %h1: str = clone %lit !0:46:1
  %c1: Chain = alt.new Chain.Cons %h1, %n1 !0:46:1
  %h2: str = clone %lit !0:46:1
  %c2: Chain = alt.new Chain.Cons %h2, %c1 !0:46:1
  %h3: str = clone %lit !0:46:1
  %c3: Chain = alt.new Chain.Cons %h3, %c2 !0:46:1
  %cc: Chain = clone %c3 !0:47:1
  drop %c3 !0:47:1
  %d: int = call @depth(%cc) !0:47:1
  drop %cc !0:47:1
  %s2: str = clone %lit !0:48:1
  %tx: Name = alt.new Name.Text %s2 !0:48:1
  %ct: Name = alt.new Name.Count %nine !0:48:1
  %txc: Name = clone %tx !0:48:1
  %ctc: Name = clone %ct !0:48:1
  drop %tx !0:48:1
  %e: int = call @count(%txc) !0:49:1
  %f: int = call @count(%ctc) !0:49:1
  drop %txc !0:49:1
  drop %ct !0:49:1
  drop %ctc !0:49:1
  %ab: int = iadd %a, %b !0:50:1
  %abd: int = iadd %ab, %d !0:50:1
  %abe: int = iadd %abd, %e !0:50:1
  %r: int = iadd %abe, %f !0:50:1
  ret %r
}
"#;

/// Clones of boxed and inline enums (a payloadless case, a string payload, a chain copied in a
/// loop); the originals are dropped before the copies are read. Run from `llvm_direct`'s one test.
pub fn enum_clones_match_cranelift() {
    let Some(opts) = direct() else { return };
    let want = run_native(ENUM_CLONE_PROGRAM, "direct_enum_clone-cranelift");
    let got = run_llvm(ENUM_CLONE_PROGRAM, &opts, "direct_enum_clone");
    let _ = std::fs::remove_file("ms-keep.ll");
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout));
    // 9 + 4 + 3 + 100 + 9
    assert_eq!(got.code, 125);
}

/// An enum whose payload is a type of more than eight leaves: the type's leaves sit in the
/// enum's slots, as in the Cranelift build, and move to and from the type's memory.
const MEMORY_PAYLOAD: &str = r#"module "d"
type Wide { a: int8, b: uint16, c: int32, d: int, e: int, f: int, g: int, h: int, i: int }
alt Holder { Plain(n: int), Big(w: Wide) }
entry @main
file 0 "d.ms"
fn @mkb(%a: int8, %b: uint16, %c: int32, %n: int) -> Holder inline(never) !0:1:1 {
b0:
  %w: Wide = type.new Wide %a, %b, %c, %n, %n, %n, %n, %n, %n !0:2:1
  %h: Holder = alt.new Holder.Big %w !0:2:1
  ret %h
}
fn @readb(%h: Holder) -> int inline(never) !0:3:1 {
b0:
  %w: Wide = alt.get Holder.Big.w %h !0:4:1
  %a: int8 = type.get Wide.a %w !0:4:1
  %b: uint16 = type.get Wide.b %w !0:4:1
  %c: int32 = type.get Wide.c %w !0:4:1
  %d: int = type.get Wide.d %w !0:4:1
  %zero: int = iconst 0 !0:4:1
  %one: int = iconst 1 !0:4:1
  %m8: int8 = iconst -3 !0:4:1
  %ea: bool = icmp.eq %a, %m8 !0:4:1
  %hi: uint16 = iconst 60000 !0:4:1
  %eb: bool = icmp.eq %b, %hi !0:4:1
  %m32: int32 = iconst -70000 !0:4:1
  %ec: bool = icmp.eq %c, %m32 !0:4:1
  %x: int = select %ea, %one, %zero !0:5:1
  %y: int = select %eb, %one, %zero !0:5:1
  %z: int = select %ec, %one, %zero !0:5:1
  %s1: int = iadd %x, %y !0:5:1
  %s2: int = iadd %s1, %z !0:5:1
  %s3: int = iadd %s2, %d !0:5:1
  ret %s3
}
fn @main() -> int !0:20:1 {
b0:
  %n: int = iconst 7 !0:21:1
  %o8: opt<int8> = inarrow.opt %n !0:21:1
  %a: int8 = opt.get %o8 !0:21:1
  %neg3: int = iconst -3 !0:21:1
  %on: opt<int8> = inarrow.opt %neg3 !0:21:1
  %m8: int8 = opt.get %on !0:21:1
  %big: int = iconst 60000 !0:21:1
  %ob: opt<uint16> = inarrow.opt %big !0:21:1
  %b: uint16 = opt.get %ob !0:21:1
  %m: int = iconst -70000 !0:21:1
  %oc: opt<int32> = inarrow.opt %m !0:21:1
  %c: int32 = opt.get %oc !0:21:1
  %h: Holder = call @mkb(%m8, %b, %c, %n) !0:22:1
  %r: int = call @readb(%h) !0:23:1
  ret %r
}
"#;

/// Run from `llvm_direct`'s one test (see above).
pub fn memory_payload_matches_cranelift() {
    let Some(opts) = direct() else { return };
    let want = run_native(MEMORY_PAYLOAD, "direct_payload-cranelift");
    assert_eq!(want.code, 10, "the Cranelift build disagrees");
    let got = run_llvm(MEMORY_PAYLOAD, &opts, "direct_payload");
    let ir = std::fs::read_to_string("ms-keep.ll").unwrap();
    let _ = std::fs::remove_file("ms-keep.ll");
    for f in ["mkb", "readb"] {
        let header = ir
            .lines()
            .find(|l| l.starts_with("define") && l.contains(&format!("@\"{f}#")))
            .unwrap_or_else(|| panic!("no {f} in the IR"));
        let direct = header.contains("%a0_0") || header.contains("dereferenceable");
        assert!(direct, "{f} was translated: {header}");
    }
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout));
}

/// An optional record of more than eight leaves, one with a string, and an enum whose slots hold
/// that string where another case holds an integer.
const MEMORY_OPTIONAL: &str = r#"module "d"
type Wide { a: int8, b: str, c: int, d: int, e: int, f: int, g: int, h: int, i: int }
alt Holder { Plain(n: int), Big(w: Wide) }
entry @main
file 0 "d.ms"
fn @mko(%a: int8, %n: int) -> opt<Wide> inline(never) !0:1:1 {
b0:
  %lit: str = str "hello" !0:2:1
  %s: str = clone %lit !0:2:1
  %w: Wide = type.new Wide %a, %s, %n, %n, %n, %n, %n, %n, %n !0:2:1
  %o: opt<Wide> = opt.some %w !0:2:1
  ret %o
}
fn @reado(%o: opt<Wide>) -> int inline(never) !0:4:1 {
b0:
  %p: bool = opt.is_some %o !0:5:1
  %zero: int = iconst 0 !0:5:1
  br_if %p, b1(), b2() !0:5:1
b1():
  %w: Wide = opt.get %o !0:6:1
  %a: int8 = type.get Wide.a %w !0:6:1
  %c: int = type.get Wide.c %w !0:6:1
  %x: int = iadd %c, %c !0:6:1
  ret %x
b2():
  ret %zero
}
fn @mkh(%a: int8, %n: int) -> Holder inline(never) !0:7:1 {
b0:
  %lit: str = str "abc" !0:8:1
  %s: str = clone %lit !0:8:1
  %w: Wide = type.new Wide %a, %s, %n, %n, %n, %n, %n, %n, %n !0:8:1
  %h: Holder = alt.new Holder.Big %w !0:8:1
  ret %h
}
fn @tag(%h: Holder) -> int inline(never) !0:9:1 {
b0:
  %t: int = alt.tag %h !0:10:1
  ret %t
}
fn @main() -> int !0:20:1 {
b0:
  %n: int = iconst 7 !0:21:1
  %a: int8 = iconst 1 !0:21:1
  %o: opt<Wide> = call @mko(%a, %n) !0:22:1
  %r: int = call @reado(%o) !0:23:1
  %z: opt<Wide> = opt.none !0:24:1
  %q: int = call @reado(%z) !0:24:1
  %h: Holder = call @mkh(%a, %n) !0:25:1
  %t: int = call @tag(%h) !0:25:1
  %w: Wide = alt.unbox Holder.Big.w %h !0:25:1
  %wc: int = type.get Wide.c %w !0:25:1
  drop %w !0:25:1
  %u: Wide = opt.unwrap %o !0:25:1
  %uc: int = type.get Wide.c %u !0:25:1
  drop %u !0:25:1
  drop %o !0:25:1
  %s1: int = iadd %r, %q !0:26:1
  %s2: int = iadd %s1, %t !0:26:1
  %s3: int = iadd %s2, %wc !0:26:1
  %s4: int = iadd %s3, %uc !0:26:1
  ret %s4
}
"#;

/// Run from `llvm_direct`'s one test (see above).
pub fn memory_optional_matches_cranelift() {
    let Some(opts) = direct() else { return };
    let want = run_native(MEMORY_OPTIONAL, "direct_optional-cranelift");
    let got = run_llvm(MEMORY_OPTIONAL, &opts, "direct_optional");
    let ir = std::fs::read_to_string("ms-keep.ll").unwrap();
    let _ = std::fs::remove_file("ms-keep.ll");
    for f in ["mko", "reado", "mkh", "tag"] {
        let header = ir
            .lines()
            .find(|l| l.starts_with("define") && l.contains(&format!("@\"{f}#")))
            .unwrap_or_else(|| panic!("no {f} in the IR"));
        let direct = header.contains("%a0_0") || header.contains("dereferenceable");
        assert!(direct, "{f} was translated: {header}");
    }
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout));
}

/// An `Int8` sum that leaves the type's range faults like Cranelift, and one inside it does not.
fn narrow_sum(x: i64, y: i64) -> String {
    format!(
        r#"module "d"
entry @main
file 0 "d.ms"
fn @add8(%a: int8, %b: int8) -> int8 inline(never) !0:1:1 {{
b0:
  %s: int8 = iadd.chk %a, %b !0:2:1
  ret %s
}}
fn @main() -> int !0:10:1 {{
b0:
  %x: int = iconst {x} !0:11:1
  %y: int = iconst {y} !0:11:1
  %ox: opt<int8> = inarrow.opt %x !0:11:1
  %oy: opt<int8> = inarrow.opt %y !0:11:1
  %a: int8 = opt.get %ox !0:11:1
  %b: int8 = opt.get %oy !0:11:1
  %s: int8 = call @add8(%a, %b) !0:12:1
  %n: int = iconst 1 !0:12:1
  ret %n
}}
"#
    )
}

/// Run from `llvm_direct`'s one test (see above).
pub fn narrow_sums_fault_like_cranelift() {
    let Some(opts) = direct() else { return };
    for (name, x, y) in [("fits", 60, 67), ("over", 100, 100), ("under", -100, -100)] {
        let src = narrow_sum(x, y);
        let want = run_native(&src, &format!("direct_sum_{name}-cranelift"));
        let got = run_llvm(&src, &opts, &format!("direct_sum_{name}"));
        assert_eq!((got.code, &got.stdout), (want.code, &want.stdout), "{name}");
        assert_eq!(want.code, if name == "fits" { 1 } else { 67 }, "{name}");
    }
    let ir = std::fs::read_to_string("ms-keep.ll").unwrap();
    assert!(
        ir.contains("@llvm.sadd.with.overflow.i8"),
        "no i8 overflow check"
    );
    let _ = std::fs::remove_file("ms-keep.ll");
}

/// A `UInt8` value is a real `i8`: it compares, divides and overflows as unsigned.
const UNSIGNED: &str = r#"module "d"
entry @main
file 0 "d.ms"
fn @big(%a: uint8, %b: uint8) -> int inline(never) !0:1:1 {
b0:
  %c: bool = icmp.gt %a, %b !0:2:1
  %q: uint8 = sdiv.chk %a, %b !0:2:1
  %one: int = iconst 1 !0:2:1
  %zero: int = iconst 0 !0:2:1
  %g: int = select %c, %one, %zero !0:2:1
  %w: int = conv %q !0:2:1
  %r: int = iadd %g, %w !0:2:1
  ret %r
}
fn @main() -> int !0:10:1 {
b0:
  %x: int = iconst 200 !0:11:1
  %y: int = iconst 100 !0:11:1
  %ox: opt<uint8> = inarrow.opt %x !0:11:1
  %oy: opt<uint8> = inarrow.opt %y !0:11:1
  %a: uint8 = opt.get %ox !0:11:1
  %b: uint8 = opt.get %oy !0:11:1
  %r: int = call @big(%a, %b) !0:12:1
  ret %r
}
"#;

/// Run from `llvm_direct`'s one test (see above).
pub fn narrow_unsigned_matches_cranelift() {
    let Some(opts) = direct() else { return };
    let want = run_native(UNSIGNED, "direct_unsigned-cranelift");
    assert_eq!(want.code, 3, "the Cranelift build disagrees");
    let got = run_llvm(UNSIGNED, &opts, "direct_unsigned");
    let ir = std::fs::read_to_string("ms-keep.ll").unwrap();
    let _ = std::fs::remove_file("ms-keep.ll");
    assert!(ir.contains("icmp ugt i8"), "no unsigned byte compare");
    assert!(ir.contains("udiv i8"), "no unsigned byte division");
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout));
}

/// A slot of `unit` (a result that holds nothing) is still an address that is written and read.
const UNIT_SLOT_PROGRAM: &str = r#"module "d"
entry @main
file 0 "d.ms"
fn @f(%a: int) -> int !0:1:1 {
b0:
  %s: ptr = slot unit !0:2:1
  %u: unit = unit !0:3:1
  store %s, %u !0:4:1
  %v: unit = load unit %s !0:5:1
  %r: int = iadd %a, %a !0:6:1
  ret %r
}
fn @main() -> int !0:10:1 {
b0:
  %a: int = iconst 21 !0:11:1
  %r: int = call @f(%a) !0:12:1
  ret %r
}
"#;

pub fn unit_slot_matches_cranelift() {
    let Some(opts) = direct() else { return };
    let want = run_native(UNIT_SLOT_PROGRAM, "direct_unit_slot-cranelift");
    let got = run_llvm(UNIT_SLOT_PROGRAM, &opts, "direct_unit_slot");
    let ir = std::fs::read_to_string("ms-keep.ll").unwrap();
    let _ = std::fs::remove_file("ms-keep.ll");
    let header = ir
        .lines()
        .find(|l| l.starts_with("define") && l.contains("@\"f#"))
        .expect("no f in the IR");
    assert!(
        header.contains("%a0_0") || header.contains("dereferenceable") || header.contains("i64 %"),
        "f was translated: {header}"
    );
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout));
    assert_eq!(got.code, 42);
}

/// A type holding a type, in memory, behaves like the Cranelift build (the struct shape itself
/// is pinned by `nested_leaves_are_reached_by_field_indices` in `llvm_build`).
const NESTED_TYPE: &str = r#"module "d"
type Pair { a: int8, b: int }
type Outer { p: Pair, c: int32, d: int, e: int, f: int, g: int, h: int, i: int }
entry @main
file 0 "d.ms"
fn @mk(%p: Pair, %c: int32, %n: int) -> Outer inline(never) !0:1:1 {
b0:
  %w: Outer = type.new Outer %p, %c, %n, %n, %n, %n, %n, %n !0:2:1
  ret %w
}
fn @sum(%w: Outer) -> int inline(never) !0:3:1 {
b0:
  %p: Pair = type.get Outer.p %w !0:4:1
  %b: int = type.get Pair.b %p !0:4:1
  %d: int = type.get Outer.d %w !0:4:1
  %s: int = iadd %b, %d !0:4:1
  ret %s
}
fn @main() -> int !0:20:1 {
b0:
  %n: int = iconst 7 !0:21:1
  %o8: opt<int8> = inarrow.opt %n !0:21:1
  %a: int8 = opt.get %o8 !0:21:1
  %p: Pair = type.new Pair %a, %n !0:21:1
  %oc: opt<int32> = inarrow.opt %n !0:21:1
  %c: int32 = opt.get %oc !0:21:1
  %w: Outer = call @mk(%p, %c, %n) !0:22:1
  %r: int = call @sum(%w) !0:23:1
  ret %r
}
"#;

#[test]
pub fn nested_type_is_a_struct_of_structs() {
    let Some(mut opts) = direct() else { return };
    // Every test that keeps `ms-keep.ll` shares one file in the working directory; this one does
    // not read it, so it must not overwrite it.
    opts.build.keep_ll = false;
    let want = run_native(NESTED_TYPE, "direct_nested_type-cranelift");
    assert_eq!(want.code, 14, "the Cranelift build disagrees");
    let got = run_llvm(NESTED_TYPE, &opts, "direct_nested_type");
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout));
}
