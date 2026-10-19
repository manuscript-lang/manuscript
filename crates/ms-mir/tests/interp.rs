use ms_mir::interp::{Fault, Interp};
use ms_mir::ir::FaultKind;
use ms_mir::parse::parse_module;
use ms_mir::verify::verify_module;

fn module(src: &str) -> ms_mir::ir::Module {
    let m = parse_module(src).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    m
}

fn run(src: &str) -> i64 {
    let m = module(src);
    let mut it = Interp::new(&m);
    it.run_entry().unwrap_or_else(|f| panic!("{f}"))
}

fn run_fault(src: &str) -> (Fault, String) {
    let m = module(src);
    let mut it = Interp::new(&m);
    let f = it.run_entry().expect_err("expected a fault");
    (f, it.stdout().to_string())
}

#[test]
fn sum_loop() {
    let src = r#"module "sum"
entry @main
fn @sum(%n: int) -> int {
b0:
  %z: int = iconst 0
  br loop(%z, %z)
loop(%i: int, %acc: int):
  %c: bool = icmp.lt %i, %n
  br_if %c, body(), done()
body:
  %a: int = iadd.chk %acc, %i
  %one: int = iconst 1
  %j: int = iadd %i, %one
  br loop(%j, %a)
done:
  ret %acc
}
fn @main() -> int {
b0:
  %n: int = iconst 100
  %r: int = call @sum (%n)
  ret %r
}
"#;
    assert_eq!(run(src), 4950);
}

#[test]
fn records() {
    let src = r#"module "rec"
record P { x: int, y: int }
entry @main
fn @main() -> int {
b0:
  %a: int = iconst 3
  %b: int = iconst 4
  %p: P = rec.new P %a, %b
  %nine: int = iconst 9
  %q: P = rec.set P.x %p, %nine
  %x: int = rec.get P.x %q
  %y: int = rec.get P.y %q
  %r: int = imul %x, %y
  ret %r
}
"#;
    assert_eq!(run(src), 36);
}

#[test]
fn alternatives_and_switch() {
    let src = r#"module "alt"
alt Shape { Circle(r: int), Rect(w: int, h: int), Empty }
entry @main
fn @area(%s: Shape) -> int {
b0:
  %t: int = alt.tag %s
  switch %t [0: circ(), 1: rect()] default empty()
circ:
  %r: int = alt.get Shape.Circle.r %s
  %a: int = imul %r, %r
  ret %a
rect:
  %w: int = alt.get Shape.Rect.w %s
  %h: int = alt.get Shape.Rect.h %s
  %b: int = imul %w, %h
  ret %b
empty:
  %z: int = iconst 0
  ret %z
}
fn @main() -> int {
b0:
  %two: int = iconst 2
  %five: int = iconst 5
  %c: Shape = alt.new Shape.Circle %five
  %r: Shape = alt.new Shape.Rect %two, %five
  %e: Shape = alt.new Shape.Empty
  %x: int = call @area (%c)
  %y: int = call @area (%r)
  %z: int = call @area (%e)
  %s1: int = iadd %x, %y
  %s2: int = iadd %s1, %z
  ret %s2
}
"#;
    assert_eq!(run(src), 35);
}

#[test]
fn list_push_get_set() {
    let src = r#"module "list"
entry @main
fn @main() -> int {
b0:
  %n: int = iconst 4
  %l0: list<int> = list.new %n
  %a: int = iconst 10
  %b: int = iconst 20
  %l1: list<int> = list.push %l0, %a
  %l2: list<int> = list.push %l1, %b
  %i1: int = iconst 1
  %seven: int = iconst 7
  %l3: list<int> = list.set %l2, %i1, %seven
  %m1: int = iconst -1
  %last: int = list.get %l3, %m1
  %first: int = iconst 0
  %f: int = list.get %l3, %first
  %len: int = list.len %l3
  drop %l3
  %s: int = iadd %last, %f
  %r: int = iadd %s, %len
  ret %r
}
"#;
    assert_eq!(run(src), 7 + 10 + 2);
}

#[test]
fn list_bounds_fault() {
    let src = r#"module "list"
entry @main
fn @main() -> int {
b0:
  %a: int = iconst 1
  %l: list<int> = list.lit %a
  %i: int = iconst 5
  %x: int = list.get %l, %i
  drop %l
  ret %x
}
"#;
    let (f, _) = run_fault(src);
    assert_eq!(f.kind, FaultKind::IndexOutOfRange);
    assert!(
        f.message.contains("index 5 out of range for length 1"),
        "{}",
        f.message
    );
    assert_eq!(f.stack.len(), 1);
}

#[test]
fn optionals() {
    let src = r#"module "opt"
entry @main
fn @pick(%flag: bool) -> opt<int> {
b0:
  br_if %flag, yes(), no()
yes:
  %v: int = iconst 41
  %s: opt<int> = opt.some %v
  ret %s
no:
  %n: opt<int> = opt.none
  ret %n
}
fn @main() -> int {
b0:
  %t: bool = bconst true
  %o: opt<int> = call @pick (%t)
  %p: bool = opt.is_some %o
  %v: int = opt.unwrap %o
  %one: int = iconst 1
  %w: int = iadd %v, %one
  %zero: int = iconst 0
  %r: int = select %p, %w, %zero
  ret %r
}
fn @bad() -> int {
b0:
  %f: bool = bconst false
  %o: opt<int> = call @pick (%f)
  %v: int = opt.unwrap %o
  ret %v
}
"#;
    assert_eq!(run(src), 42);
    let m = module(src);
    let bad = m.func_by_name("bad").unwrap();
    let mut it = Interp::new(&m);
    let f = it.call(bad, vec![]).unwrap_err();
    assert_eq!(f.kind, FaultKind::NoneUnwrap);
}

#[test]
fn closures_capture() {
    let src = r#"module "clo"
entry @main
fn @add(%env: ptr, %x: int) -> int closure(int) {
b0:
  %k: int = closure.cap 0 %env
  %r: int = iadd %x, %k
  ret %r
}
fn @main() -> int {
b0:
  %k: int = iconst 10
  %f: fn(int) -> int = closure.new @add %k
  %x: int = iconst 5
  %r: int = call.ind (%f, %x)
  drop %f
  ret %r
}
"#;
    assert_eq!(run(src), 15);
}

#[test]
fn interface_vtable() {
    let src = r#"module "iface"
iface Area { area() -> int }
vtable @v_int: Area for int { @area_int }
entry @main
fn @area_int(%self: ptr) -> int method {
b0:
  %r: int = iconst 99
  ret %r
}
fn @main() -> int {
b0:
  %x: int = iconst 1
  %s: dyn Area = iface.new @v_int %x
  %r: int = call.method Area.area (%s)
  drop %s
  ret %r
}
"#;
    assert_eq!(run(src), 99);
}

#[test]
fn drop_heavy() {
    let src = r#"module "drops"
entry @main
fn @build(%n: int) -> list<list<int>> {
b0:
  %cap: int = iconst 0
  %outer: list<list<int>> = list.new %cap
  %z: int = iconst 0
  br loop(%z, %outer)
loop(%i: int, %acc: own list<list<int>>):
  %c: bool = icmp.lt %i, %n
  br_if %c, body(), done()
body:
  %inner0: list<int> = list.new %cap
  %inner: list<int> = list.push %inner0, %i
  %acc2: list<list<int>> = list.push %acc, %inner
  %one: int = iconst 1
  %j: int = iadd %i, %one
  br loop(%j, %acc2)
done:
  ret %acc
}
fn @main() -> int {
b0:
  %n: int = iconst 1000
  %l: list<list<int>> = call @build (%n)
  %len: int = list.len %l
  %k: int = iconst 999
  %row: list<int> = list.get %l, %k
  %v: int = iconst 0
  %e: int = list.get %row, %v
  drop %l
  %r: int = iadd %len, %e
  ret %r
}
"#;
    let m = module(src);
    let mut it = Interp::new(&m);
    assert_eq!(it.run_entry().unwrap(), 1999);
    assert_eq!(it.drops(), 1);
}

#[test]
fn fault_runs_cleanups_lifo() {
    let src = r#"module "cleanup"
extern @msrt_print_int(int)
entry @main
fn @c1(%x: int) {
b0:
  %u: unit = call.rt @msrt_print_int (%x)
  ret
}
fn @c2(%x: int) {
b0:
  %u: unit = call.rt @msrt_print_int (%x)
  ret
}
fn @main() -> int {
b0:
  %a: int = iconst 1
  %b: int = iconst 2
  %h1: int = cleanup.push @c1 %a
  %h2: int = cleanup.push @c2 %b
  %max: int = iconst 9223372036854775807
  %r: int = iadd.chk %max, %a
  ret %r
}
"#;
    let (f, out) = run_fault(src);
    assert_eq!(f.kind, FaultKind::IntOverflow);
    assert_eq!(out, "2\n1\n");
    assert_eq!(f.stack, vec!["main".to_string()]);
}

#[test]
fn cleanup_run_pops_innermost() {
    let src = r#"module "cleanup2"
extern @msrt_print_int(int)
entry @main
fn @c1(%x: int) {
b0:
  %u: unit = call.rt @msrt_print_int (%x)
  ret
}
fn @main() -> int {
b0:
  %a: int = iconst 7
  %h: int = cleanup.push @c1 %a
  cleanup.run %h
  %z: int = iconst 0
  ret %z
}
"#;
    let m = module(src);
    let mut it = Interp::new(&m);
    assert_eq!(it.run_entry().unwrap(), 0);
    assert_eq!(it.stdout(), "7\n");
}

#[test]
fn fuel_and_cancellation() {
    let src = r#"module "spin"
entry @main
fn @main() -> int {
b0:
  br spin()
spin:
  poll
  br spin()
}
"#;
    let m = module(src);
    let mut it = Interp::new(&m);
    it.set_fuel(Some(1000));
    let f = it.run_entry().unwrap_err();
    assert!(f.fuel_exhausted);
    let mut it = Interp::new(&m);
    it.cancel_flag()
        .store(true, std::sync::atomic::Ordering::Relaxed);
    assert_eq!(it.run_entry().unwrap_err().kind, FaultKind::Cancelled);
}

#[test]
fn division_and_shift_semantics() {
    let src = r#"module "div"
entry @main
fn @main() -> int {
b0:
  %a: int = iconst -7
  %b: int = iconst 2
  %q: int = sdiv.chk %a, %b
  %r: int = srem.chk %a, %b
  %s: int = iconst 65
  %one: int = iconst 1
  %sh: int = shl %one, %s
  %t1: int = iadd %q, %r
  %t2: int = iadd %t1, %sh
  ret %t2
}
"#;
    assert_eq!(run(src), -3 + -1 + 2);
}
