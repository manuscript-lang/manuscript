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
  %r1: int = iadd %acc, %pq !0:72:1
  %r2: int = iadd %r1, %u3 !0:72:1
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
        "area", "make", "find", "orelse", "present", "unpick", "wrap_len",
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
fn @chk(%x: int8) -> int8 inline(never) !0:9:1 {
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
  %c: int8 = call @chk(%n8) !0:24:1
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

/// A record of more than eight leaves lives in memory: its `Int8`, `UInt16` and `Int32` fields are
/// 1, 2 and 4 bytes there and read back sign- or zero-extended.
const NARROW_RECORD: &str = r#"module "d"
record Wide { a: int8, b: uint16, c: int32, d: int, e: int, f: int, g: int, h: int, i: int }
entry @main
file 0 "d.ms"
fn @mk(%a: int8, %b: uint16, %c: int32, %n: int) -> Wide inline(never) !0:1:1 {
b0:
  %w: Wide = rec.new Wide %a, %b, %c, %n, %n, %n, %n, %n, %n !0:2:1
  ret %w
}
fn @sum(%w: Wide) -> int inline(never) !0:3:1 {
b0:
  %a: int8 = rec.get Wide.a %w !0:4:1
  %b: uint16 = rec.get Wide.b %w !0:4:1
  %c: int32 = rec.get Wide.c %w !0:4:1
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
pub fn narrow_record_fields_match_cranelift() {
    let Some(opts) = direct() else { return };
    let want = run_native(NARROW_RECORD, "direct_narrow_record-cranelift");
    assert_eq!(want.code, 3, "the Cranelift build disagrees");
    let got = run_llvm(NARROW_RECORD, &opts, "direct_narrow_record");
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
record Pair { name: str, tag: str, n: int }
record Big { a: int, b: int, c: int, d: int, e: int, f: int, g: int, h: int, name: str, n: int }
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
  %n: int = rec.get Pair.n %p !0:41:1
  rec.release Pair.tag %p !0:42:1
  ret %n
}
fn @release_big(%p: move Big) -> int !0:50:1 {
b0:
  %n: int = rec.get Big.n %p !0:51:1
  rec.release Big %p !0:52:1
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
  %p: Pair = rec.new Pair %s1, %s2, %k !0:35:1
  %d: int = call @release_pair(%p) !0:35:1
  %s3: str = clone %lit !0:36:1
  %q: Big = rec.new Big %k, %k, %k, %k, %k, %k, %k, %k, %s3, %k !0:36:1
  %e: int = call @release_big(%q) !0:36:1
  %ab: int = iadd %a, %b !0:34:1
  %ac: int = iadd %ab, %b !0:34:1
  %ad: int = iadd %ac, %d !0:37:1
  %ae: int = iadd %ad, %g !0:37:1
  %r: int = iadd %ae, %e !0:37:1
  ret %r
}
"#;

/// Unwrapping an optional (an integer, and a string that is cloned) and releasing records; run from `llvm_direct`'s one test for the same reason.
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
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout));
    assert_eq!(got.code, 9 + 4 + 9 + 4 + 5);
}
