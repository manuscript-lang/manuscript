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

fn list_building() {
    let src = r#"module "d"
entry @main
file 0 "d.ms"
fn @build(%n: int, %cap: int) -> list<int> !0:1:1 {
b0:
  %zero: int = iconst 0 !0:2:1
  %l0: list<int> = list.new %cap !0:3:1
  br loop(%zero, %l0) !0:3:1
loop(%i: int, %l: move list<int>):
  %c: bool = icmp.lt %i, %n !0:4:1
  br_if %c, body(), done() !0:4:1
body():
  %l2: list<int> = list.push %l, %i !0:5:1
  %one: int = iconst 1 !0:6:1
  %i2: int = iadd %i, %one !0:6:1
  br loop(%i2, %l2) !0:6:1
done():
  ret %l !0:7:1
}
fn @at(%l: list<int>, %i: int) -> int !0:8:1 {
b0:
  %x: int = list.get %l, %i !0:9:1
  ret %x
}
fn @main() -> int !0:20:1 {
b0:
  %zero: int = iconst 0 !0:21:1
  %ten: int = iconst 10 !0:21:1
  %three: int = iconst 3 !0:21:1
  %cap: int = iconst 16 !0:21:1
  %nine: int = iconst 9 !0:21:1
  %two: int = iconst 2 !0:21:1
  %one: int = iconst 1 !0:21:1
  %a: list<int> = call @build(%ten, %zero) !0:22:1
  %b: list<int> = call @build(%three, %cap) !0:23:1
  %f: int = iconst 4 !0:24:1
  %g: int = iconst 5 !0:24:1
  %lit: list<int> = list.lit %f, %g !0:24:1
  %x: int = call @at(%a, %nine) !0:25:1
  %n: int = list.len %a !0:25:1
  %y: int = call @at(%b, %two) !0:26:1
  %z: int = call @at(%lit, %one) !0:27:1
  %s1: int = iadd %x, %n !0:28:1
  %s2: int = iadd %s1, %y !0:28:1
  %s3: int = iadd %s2, %z !0:28:1
  drop %a !0:29:1
  drop %b !0:29:1
  drop %lit !0:29:1
  ret %s3 !0:30:1
}
"#;
    // 9 + 10 + 2 + 5: growth from empty (4, 8, 16) and no growth with room to spare.
    check("direct_list_build", src, 26, &["build"]);
}

fn string_literals() {
    // A literal is a private constant of the LLVM module, not data of the Cranelift object.
    let src = r#"module "d"
entry @main
file 0 "d.ms"
fn @pick(%i: int) -> int !0:1:1 {
b0:
  %s: str = str "hello, \"world\"" !0:2:1
  %x: int = str.byte %s, %i !0:3:1
  ret %x
}
fn @other(%i: int) -> int !0:4:1 {
b0:
  %s: str = str "hello, \"world\"" !0:5:1
  %t: str = str "xyz" !0:5:1
  %x: int = str.byte %s, %i !0:6:1
  %one: int = iconst 1 !0:6:1
  %y: int = str.byte %t, %one !0:6:1
  %r: int = isub %x, %y !0:7:1
  ret %r
}
fn @main() -> int !0:10:1 {
b0:
  %i: int = iconst 8 !0:12:1
  %a: int = call @pick(%i) !0:13:1
  %b: int = call @other(%i) !0:14:1
  %r: int = isub %a, %b !0:15:1
  ret %r
}
"#;
    // "hello, \"world\"": byte 8 is 'w' (119); 'w' - 'y' = -2, so 119 - (-2) = 121.
    check("direct_str_lit", src, 121, &["pick"]);
    let ir = std::fs::read_to_string("ms-keep.ll").unwrap();
    assert!(
        ir.contains(
            "private unnamed_addr constant [15 x i8] c\"hello, \\22world\\22\\00\", align 16"
        ),
        "no LLVM constant for the literal"
    );
}

/// Taking the last element, dropping it and releasing the block.
fn list_take_release() {
    let src = r#"module "d"
entry @main
file 0 "d.ms"
fn @drain(%a: int) -> int !0:1:1 {
b0:
  %one: int = iconst 1 !0:2:1
  %b: int = iadd %a, %one !0:2:1
  %l: list<int> = list.lit %a, %b !0:3:1
  %n: int = list.len %l !0:3:1
  %i: int = isub %n, %one !0:3:1
  %x: int = list.take %l, %i !0:4:1
  %l2: list<int> = list.droplast 1 %l !0:5:1
  %zero: int = iconst 0 !0:6:1
  list.release %l2, %zero !0:6:1
  ret %x
}
fn @main() -> int !0:10:1 {
b0:
  %a: int = iconst 34 !0:11:1
  %x: int = call @drain(%a) !0:12:1
  ret %x
}
"#;
    check("direct_take_release", src, 35, &["drain"]);
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
    // `framed` borrows a box that stays in the frame, views it and drops both.
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
fn @framed(%y: int, %k: int) -> int inline(never) !0:30:1 {
b0:
  %v: dyn Scale = iface.borrow @v_int %y !0:31:1
  %w: dyn Scale = iface.view %v !0:32:1
  %r: int = call @use(%w, %k) !0:33:1
  drop %w
  drop %v
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
  %five: int = iconst 5
  %two: int = iconst 2
  %f: int = call @framed(%five, %two) !0:26:1
  %af: int = iadd %a, %f !0:27:1
  %t: int = iadd %af, %p !0:24:1
  %u: unit = call.rt @msrt_print_int(%t) !0:25:1
  ret %t
}
"#;
    // 7 * 3 + 5 * 2 + (7 + 7 * 3 + 10) = 69
    check(
        "direct_interfaces",
        src,
        69,
        &["scale_int", "use", "make", "probe", "framed"],
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
/// through the vtable, a view and a vtable test, and `map.new` as zero words.
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
    check(
        "direct_ifaces",
        src,
        73,
        &["through", "boxed", "borrowed", "viewed", "fresh"],
    );
}

/// One test, not three: each build writes `ms-keep.ll` in the working directory.
#[test]
fn direct_lists_and_strings_match_cranelift() {
    list_reads_and_writes();
    a_bad_list_index_faults();
    string_bytes();
    list_building();
    string_literals();
    list_take_release();
    crate::llvm_direct_data::optionals_and_alternatives_match_cranelift();
    crate::llvm_direct_data::narrow_integers_match_cranelift();
    crate::llvm_direct_data::narrow_record_fields_match_cranelift();
    crate::llvm_direct_data::narrow_sums_fault_like_cranelift();
    closures_and_runtime_calls();
    interfaces();
    checked_arithmetic();
    interfaces_and_maps();
    let _ = std::fs::remove_file("ms-keep.ll");
}
