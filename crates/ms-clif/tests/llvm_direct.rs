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
            header.contains("%a0_0") || header.contains("%a1_0"),
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

fn closures_and_runtime_calls() {
    // A closure that escapes (heap object, returned), one that stays in the frame (passed to a
    // borrowing call), the captures read in the body, a call through the code pointer, and a
    // runtime call that takes its argument by value.
    let src = r#"module "d"
entry @main
file 0 "d.ms"
extern @msrt_print_int(int)
fn @adder(%n: int, %k: int) -> fn(int) -> int inline(never) !0:1:1 {
b0:
  %c: fn(int) -> int = closure.new @body %n, %k !0:2:1
  ret %c
}
fn @body(%env: ptr, %x: int) -> int closure(int, int) inline(never) !0:3:1 {
b0:
  %n: int = closure.cap 0 %env !0:4:1
  %k: int = closure.cap 1 %env !0:4:1
  %a: int = iadd %x, %n !0:5:1
  %b: int = imul %a, %k !0:5:1
  ret %b
}
fn @apply(%f: fn(int) -> int, %x: int) -> int inline(never) !0:6:1 {
b0:
  %r: int = call.ind (%f, %x) !0:7:1
  ret %r
}
fn @main() -> int !0:10:1 {
b0:
  %n: int = iconst 3
  %k: int = iconst 4
  %c: fn(int) -> int = call @adder(%n, %k) !0:11:1
  %x: int = iconst 5
  %r: int = call @apply(%c, %x) !0:12:1
  drop %c
  %one: int = iconst 1
  %two: int = iconst 2
  %f: fn(int) -> int = closure.new @body %one, %two !0:13:1
  %s: int = call @apply(%f, %x) !0:14:1
  drop %f
  %t: int = iadd %r, %s !0:15:1
  %u: unit = call.rt @msrt_print_int(%t) !0:16:1
  ret %t
}
"#;
    // (5 + 3) * 4 + (5 + 1) * 2 = 44
    check("direct_closures", src, 44, &["adder", "body", "apply"]);
}

fn interfaces() {
    // An owned interface box built and returned, and calls through the vtable of a method that
    // reads the data and takes an argument; `probe` reads the data word and tests the vtable.
    // Borrowed boxes and views are owned values the verifier wants dropped, and drops are not
    // emitted directly yet, so their functions stay with the translation.
    let src = r#"module "d"
entry @main
file 0 "d.ms"
iface Scale { scale(int) -> int }
vtable @v_int: Scale for int { @scale_int }
extern @msrt_print_int(int)
fn @scale_int(%self: ptr, %k: int) -> int method inline(never) !0:1:1 {
b0:
  %n: int = load int %self !0:2:1
  %r: int = imul %n, %k !0:2:1
  ret %r
}
fn @use(%s: dyn Scale, %k: int) -> int inline(never) !0:3:1 {
b0:
  %r: int = call.method Scale.scale (%s, %k) !0:4:1
  ret %r
}
fn @make(%x: int) -> dyn Scale inline(never) !0:5:1 {
b0:
  %s: dyn Scale = iface.new @v_int %x !0:6:1
  ret %s
}
fn @probe(%s: dyn Scale, %k: int) -> int inline(never) !0:7:1 {
b0:
  %d: ptr = iface.data %s !0:8:1
  %n: int = load int %d !0:8:1
  %m: int = call.method Scale.scale (%s, %k) !0:9:1
  %is: bool = iface.is @v_int %s !0:10:1
  %bonus_n: int = iconst 10
  %zero: int = iconst 0
  %bonus: int = select %is, %bonus_n, %zero !0:10:1
  %a: int = iadd %n, %m !0:11:1
  %r: int = iadd %a, %bonus !0:11:1
  ret %r
}
fn @main() -> int !0:20:1 {
b0:
  %x: int = iconst 7
  %three: int = iconst 3
  %s: dyn Scale = call @make(%x) !0:21:1
  %a: int = call @use(%s, %three) !0:22:1
  %p: int = call @probe(%s, %three) !0:23:1
  drop %s
  %t: int = iadd %a, %p !0:24:1
  %u: unit = call.rt @msrt_print_int(%t) !0:25:1
  ret %t
}
"#;
    // 7 * 3 + (7 + 7 * 3 + 10) = 59
    check(
        "direct_interfaces",
        src,
        59,
        &["scale_int", "use", "make", "probe"],
    );
}

/// One test, not three: each build writes `ms-keep.ll` in the working directory.
#[test]
fn direct_lists_and_strings_match_cranelift() {
    list_reads_and_writes();
    a_bad_list_index_faults();
    string_bytes();
    closures_and_runtime_calls();
    interfaces();
    let _ = std::fs::remove_file("ms-keep.ll");
}
