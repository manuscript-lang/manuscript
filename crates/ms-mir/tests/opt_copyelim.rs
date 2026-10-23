use ms_mir::interp::Interp;
use ms_mir::ir::{Module, Op};
use ms_mir::opt;
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

const TREE: &str = r#"module "t"
file 0 "t.ms"
alt Tree { Leaf, Node(left: Tree, right: Tree) }
entry @main

fn @make(%0: int) -> Tree inline(never) {
b0:
  %1: int = iconst 0
  %2: bool = icmp.eq %0, %1
  br_if %2, b1(), b2()
b1():
  %3: Tree = alt.new Tree.Leaf
  ret %3
b2():
  %4: int = iconst 1
  %5: int = isub.chk %0, %4
  %6: Tree = call @make (%5)
  %9: Tree = call @make (%5)
  %10: Tree = alt.new Tree.Node %6, %9
  ret %10
}

fn @check(%0: Tree) -> int inline(never) {
b0:
  %1: int = alt.tag %0
  switch %1 [0: b1(), 1: b2()] default b3()
b1():
  %2: int = iconst 1
  ret %2
b2():
  %3: Tree = alt.get Tree.Node.left %0
  %4: Tree = copy %3
  %5: Tree = alt.get Tree.Node.right %0
  %6: Tree = copy %5
  %7: int = iconst 1
  %8: int = call @check (%4)
  %9: int = iadd.chk %7, %8
  %10: int = call @check (%6)
  %11: int = iadd.chk %9, %10
  drop %6
  drop %4
  ret %11
b3():
  unreachable
}


fn @mirror(%0: Tree) -> Tree inline(never) {
b0:
  %1: int = alt.tag %0
  switch %1 [0: b1(), 1: b2()] default b3()
b1():
  %2: Tree = alt.new Tree.Leaf
  ret %2
b2():
  %3: Tree = alt.get Tree.Node.left %0
  %4: Tree = copy %3
  %5: Tree = alt.get Tree.Node.right %0
  %6: Tree = copy %5
  %7: Tree = alt.new Tree.Node %6, %4
  ret %7
b3():
  unreachable
}

fn @main() -> int export {
b0:
  %0: int = iconst 6
  %1: Tree = call @make (%0)
  %2: Tree = call @mirror (%1)
  %3: int = call @check (%2)
  drop %2
  drop %1
  %4: int = iconst 100
  %5: int = srem.chk %3, %4
  ret %5
}
"#;

fn count(m: &Module, name: &str, op: Op) -> usize {
    let id = m.func_by_name(name).expect("function");
    m.funcs[id.index()]
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter(|i| i.op == op)
        .count()
}

#[test]
fn copies_that_only_feed_borrows_are_removed() {
    let mut m = parse_module(TREE).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    let before = Interp::new(&m).run_entry().map_err(|f| f.message);
    assert!(opt::copyelim::run(&mut m));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    assert_eq!(count(&m, "check", Op::Copy), 0);
    assert_eq!(count(&m, "check", Op::Drop), 0);
    // Consumed copies stay.
    assert_eq!(count(&m, "mirror", Op::Copy), 2);
    let after = Interp::new(&m).run_entry().map_err(|f| f.message);
    assert_eq!(before, after);
}

const CHAIN: &str = r#"module "t"
alt List { Nil, More(next: List) }
entry @main

fn @build(%n: int) -> List inline(never) {
b0:
  %z: int = iconst 0
  %nil: List = alt.new List.Nil
  br b1(%nil, %z)
b1(%l: own List, %i: int):
  %lt: bool = icmp.lt %i, %n
  br_if %lt, b2(), b3()
b2():
  %c: List = copy %l
  %m: List = alt.new List.More %c
  drop %l
  %one: int = iconst 1
  %i2: int = iadd.chk %i, %one
  br b1(%m, %i2)
b3():
  ret %l
}

fn @main() -> int export {
b0:
  %n: int = iconst 50
  %l: List = call @build (%n)
  %t: int = alt.tag %l
  drop %l
  ret %t
}
"#;

#[test]
fn a_copy_whose_source_dies_right_after_becomes_a_move() {
    let mut m = parse_module(CHAIN).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    let before = Interp::new(&m).run_entry().map_err(|f| f.message);
    assert!(opt::copyelim::run(&mut m));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    assert_eq!(count(&m, "build", Op::Copy), 0);
    assert_eq!(count(&m, "build", Op::Drop), 0);
    assert_eq!(before, Interp::new(&m).run_entry().map_err(|f| f.message));
}

const UNWRAP: &str = r#"module "t"
alt List { Nil, More(next: List) }
entry @main

fn @build(%n: int) -> opt<List> inline(never) {
b0:
  %z: int = iconst 0
  %lt: bool = icmp.le %n, %z
  br_if %lt, b1(), b2()
b1():
  %nil: List = alt.new List.Nil
  %s: opt<List> = opt.some %nil
  ret %s
b2():
  %one: int = iconst 1
  %m: int = isub.chk %n, %one
  %r: opt<List> = call @build (%m)
  %ok: bool = opt.is_some %r
  br_if %ok, b3(), b4()
b3():
  %p: List = opt.get %r
  %c: List = copy %p
  drop %r
  %more: List = alt.new List.More %c
  %s2: opt<List> = opt.some %more
  ret %s2
b4():
  drop %r
  %none: opt<List> = opt.none
  %own: opt<List> = copy %none
  ret %own
}

fn @main() -> int export {
b0:
  %n: int = iconst 50
  %r: opt<List> = call @build (%n)
  %ok: bool = opt.is_some %r
  drop %r
  %i: int = b2i %ok
  ret %i
}
"#;

#[test]
fn unwrapping_an_owned_option_moves_the_payload_out() {
    let mut m = parse_module(UNWRAP).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    let before = Interp::new(&m).run_entry().map_err(|f| f.message);
    assert!(opt::copyelim::run(&mut m));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    // Only the owned `none` copy stays.
    assert_eq!(count(&m, "build", Op::Copy), 1);
    assert_eq!(count(&m, "build", Op::OptUnbox), 1);
    assert_eq!(before, Interp::new(&m).run_entry().map_err(|f| f.message));
}

const CLOSURE_LOOP: &str = r#"module "t"
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
  %c: fn(int) -> int = copy %f
  %x: int = iconst 5
  %r: int = call.ind (%c, %x)
  drop %c
  drop %f
  ret %r
}
"#;

#[test]
fn a_closure_copy_that_only_feeds_calls_is_removed() {
    let mut m = parse_module(CLOSURE_LOOP).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    let before = Interp::new(&m).run_entry().map_err(|f| f.message);
    assert!(opt::copyelim::run(&mut m));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    assert_eq!(count(&m, "main", Op::Copy), 0);
    assert_eq!(count(&m, "main", Op::Drop), 1);
    assert_eq!(before, Interp::new(&m).run_entry().map_err(|f| f.message));
}

#[test]
fn readonly_record_projections_borrow_the_original_without_a_deep_copy() {
    for (source, copies) in [
        (include_str!("fixtures-opt/record_readonly_copy.mir"), 0),
        (include_str!("fixtures-opt/record_copy_owner_drop.mir"), 1),
        (
            include_str!("fixtures-opt/record_copy_parent_update.mir"),
            1,
        ),
    ] {
        let mut m = parse_module(source).unwrap();
        verify_module(&m).unwrap();
        let before = Interp::new(&m).run_entry().map_err(|e| e.message);
        opt::copyelim::run(&mut m);
        verify_module(&m).unwrap_or_else(|e| panic!("{e:?}\n{}", print_module(&m)));
        assert_eq!(count(&m, "main", Op::Copy), copies, "{}", print_module(&m));
        assert_eq!(before, Interp::new(&m).run_entry().map_err(|e| e.message));
        assert_eq!(before, Ok(10));
    }
}
