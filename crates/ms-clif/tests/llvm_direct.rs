//! Functions emitted straight from MIR (`mir_llvm`) must behave like the Cranelift build:
//! list reads and writes with their bounds checks, string bytes, and faults.

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

/// Runs `src` with Cranelift and with direct emission: both must exit with `code`, print the same,
/// and the functions `direct` must have been emitted straight from MIR (leaf parameters `%aN_0`).
fn check(name: &str, src: &str, code: i32, direct_fns: &[&str]) {
    let Some(opts) = direct() else { return };
    let want = run_native(src, &format!("{name}-cranelift"));
    assert_eq!(want.code, code, "{name}: the Cranelift build disagrees");
    let got = run_llvm(src, &opts, name);
    let ir = std::fs::read_to_string("ms-keep.ll").unwrap();
    for f in direct_fns {
        let header = ir
            .lines()
            .find(|l| l.starts_with("define") && l.contains(&format!("@\"{f}#")))
            .unwrap_or_else(|| panic!("{name}: no {f} in the IR"));
        assert!(
            header.contains("%a0_0") || header.contains("%a1_0") || header.contains("sret("),
            "{name}: {f} was translated: {header}"
        );
    }
    assert_eq!((got.code, &got.stdout), (want.code, &want.stdout), "{name}");
}

fn list_reads_and_writes() {
    let src = r#"module "d"
entry @main
file 0 "d.ms"
fn @pick(%l: list<int>, %i: int) -> int !0:1:1 {
b0:
  %x: int = list.get %l, %i !0:2:1
  ret %x
}
fn @put(%l: move list<int>, %i: int, %v: int) -> list<int> !0:3:1 {
b0:
  %m: list<int> = list.set %l, %i, %v !0:4:1
  ret %m
}
fn @main() -> int !0:10:1 {
b0:
  %a: int = iconst 10
  %b: int = iconst 20
  %c: int = iconst 30
  %l: list<int> = list.lit %a, %b, %c !0:11:1
  %neg: int = iconst -1
  %last: int = call @pick(%l, %neg) !0:12:1
  %zero: int = iconst 0
  %seven: int = iconst 7
  %m: list<int> = call @put(%l, %zero, %seven) !0:13:1
  %first: int = call @pick(%m, %zero) !0:14:1
  %r: int = iadd %last, %first !0:15:1
  drop %m
  ret %r
}
"#;
    check("direct_list_rw", src, 37, &["pick", "put"]);
}

fn a_bad_list_index_faults() {
    let src = r#"module "d"
entry @main
file 0 "d.ms"
fn @pick(%l: list<int>, %i: int) -> int !0:1:1 {
b0:
  %x: int = list.get %l, %i !0:2:1
  ret %x
}
fn @main() -> int !0:10:1 {
b0:
  %a: int = iconst 10
  %l: list<int> = list.lit %a !0:11:1
  %five: int = iconst 5
  %x: int = call @pick(%l, %five) !0:12:1
  drop %l
  ret %x
}
"#;
    check("direct_list_fault", src, 67, &["pick"]);
}

/// `byte` of `text` at `index`: a program that returns the byte (or the `str.ascii_at` result).
fn string_program(op: &str, text: &str, index: i64) -> String {
    format!(
        r#"module "d"
entry @main
file 0 "d.ms"
fn @get(%s: str, %i: int) -> int !0:1:1 {{
b0:
  %x: int = {op} %s, %i !0:2:1
  ret %x
}}
fn @main() -> int !0:10:1 {{
b0:
  %s: str = str "{text}" !0:11:1
  %i: int = iconst {index} !0:12:1
  %r: int = call @get(%s, %i) !0:13:1
  ret %r
}}
"#
    )
}

fn string_bytes() {
    let long = "abcdefghijklmnopqrstu";
    // An inline string holds its bytes in its words; a longer one is read from memory.
    check(
        "direct_byte_inline",
        &string_program("str.byte", "abc", 2),
        99,
        &["get"],
    );
    check(
        "direct_byte_inline_hi",
        &string_program("str.byte", "abcdefghijk", 9),
        106,
        &["get"],
    );
    check(
        "direct_byte_heap",
        &string_program("str.byte", long, 20),
        117,
        &["get"],
    );
    // `str.ascii_at` needs the ASCII flag, which a literal lacks, so it returns -1: an exit code
    // out of range, 67.
    check(
        "direct_ascii_none",
        &string_program("str.ascii_at", long, 9),
        67,
        &["get"],
    );
}

/// A function of two integers: `op` on them, returned.
fn int_program(op: &str, x: i64, y: i64) -> String {
    format!(
        r#"module "d"
entry @main
file 0 "d.ms"
fn @f(%a: int, %b: int) -> int !0:1:1 {{
b0:
  %x: int = {op} %a, %b !0:2:1
  ret %x
}}
fn @main() -> int !0:10:1 {{
b0:
  %a: int = iconst {x}
  %b: int = iconst {y}
  %r: int = call @f(%a, %b) !0:12:1
  ret %r
}}
"#
    )
}

/// A function that faults with `kind`, called from `main`.
fn fault_program(kind: &str) -> String {
    format!(
        r#"module "d"
entry @main
file 0 "d.ms"
fn @f(%a: int) -> int !0:1:1 {{
b0:
  fault {kind}
}}
fn @main() -> int !0:10:1 {{
b0:
  %a: int = iconst 1
  %r: int = call @f(%a) !0:12:1
  ret %r
}}
"#
    )
}

fn checked_arithmetic() {
    let (min, max) = (i64::MIN, i64::MAX);
    for (name, op, x, y, code) in [
        ("add", "iadd.chk", 20, 22, 42),
        ("sub", "isub.chk", 50, 8, 42),
        ("mul", "imul.chk", 6, 7, 42),
        ("div", "sdiv.chk", -85, -2, 42),
        ("rem", "srem.chk", 142, 100, 42),
        ("remmin", "srem.chk", min, -1, 0),
        ("add_over", "iadd.chk", max, 1, 67),
        ("mul_over", "imul.chk", max, 2, 67),
        ("div_zero", "sdiv.chk", 1, 0, 67),
        ("div_min", "sdiv.chk", min, -1, 67),
        ("rem_zero", "srem.chk", 1, 0, 67),
    ] {
        check(
            &format!("direct_{name}"),
            &int_program(op, x, y),
            code,
            &["f"],
        );
    }
    check("direct_fault", &fault_program("div_by_zero"), 67, &["f"]);
}

/// Interfaces: a box built from an `int` (heap, and a frame slot for a borrow), a method call
/// through the vtable, a view and a vtable test, and `map.new` as zero words. Only the method
/// call and `map.new` are emitted directly until `drop` is: every owned interface is dropped, so
/// the functions that build one still take the translation (they run, and must agree).
fn interfaces_and_maps() {
    let src = r#"module "d"
iface Area { area(int) -> int }
vtable @v_int: Area for int { @area_int }
extern @msrt_map_new() -> Map<int, int> leaf map_new
entry @main
file 0 "d.ms"
fn @area_int(%self: ptr, %k: int) -> int method !0:1:1 {
b0:
  %v: int = load int %self !0:2:1
  %r: int = imul %v, %k !0:3:1
  ret %r
}
fn @through(%s: dyn Area, %k: int) -> int !0:4:1 {
b0:
  %r: int = call.method Area.area (%s, %k) !0:5:1
  ret %r
}
fn @boxed(%x: int, %k: int) -> int !0:6:1 {
b0:
  %s: dyn Area = iface.new @v_int %x !0:7:1
  %r: int = call.method Area.area (%s, %k) !0:8:1
  drop %s !0:8:1
  ret %r
}
fn @borrowed(%x: int, %k: int) -> int !0:9:1 {
b0:
  %s: dyn Area = iface.borrow @v_int %x !0:10:1
  %r: int = call.method Area.area (%s, %k) !0:11:1
  drop %s !0:11:1
  ret %r
}
fn @viewed(%s: dyn Area) -> int !0:12:1 {
b0:
  %v: dyn Area = iface.view %s !0:13:1
  %is: bool = iface.is @v_int %v !0:14:1
  %i: int = b2i %is !0:15:1
  drop %v !0:15:1
  ret %i
}
fn @fresh() -> Map<int, int> !0:16:1 {
b0:
  %m: Map<int, int> = call.rt @msrt_map_new () !0:17:1
  ret %m
}
fn @main() -> int !0:20:1 {
b0:
  %six: int = iconst 6
  %seven: int = iconst 7
  %a: int = call @boxed(%six, %seven) !0:21:1
  %three: int = iconst 3
  %five: int = iconst 5
  %b: int = call @borrowed(%three, %five) !0:22:1
  %s: dyn Area = iface.new @v_int %three !0:23:1
  %c: int = call @through(%s, %five) !0:24:1
  %d: int = call @viewed(%s) !0:25:1
  %ab: int = iadd %a, %b !0:27:1
  %cd: int = iadd %c, %d !0:28:1
  %r: int = iadd %ab, %cd !0:29:1
  drop %s !0:29:1
  ret %r
}
"#;
    // 6*7 + 3*5 + 3*5 + 1 = 73
    check("direct_ifaces", src, 73, &["through", "fresh"]);
}

/// One test, not three: each build writes `ms-keep.ll` in the working directory.
#[test]
fn direct_lists_and_strings_match_cranelift() {
    list_reads_and_writes();
    a_bad_list_index_faults();
    string_bytes();
    checked_arithmetic();
    interfaces_and_maps();
    let _ = std::fs::remove_file("ms-keep.ll");
}
