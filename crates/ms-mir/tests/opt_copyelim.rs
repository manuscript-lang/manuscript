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

const PHI: &str = r#"module "t"
entry @main
extern @msrt_string_eq(str, str) -> bool

fn @is_q(%0: list<str>, %1: int) -> bool inline(never) {
b0:
  %2: int = list.len %0
  %3: bool = icmp.lt %1, %2
  br_if %3, b1(), b2()
b1():
  %4: str = list.get.u %0, %1
  %5: str = copy %4
  br b3(%5)
b2():
  %6: str = str ""
  %7: str = copy %6
  br b3(%7)
b3(%8: own str):
  %9: str = str "q"
  %10: bool = call.rt @msrt_string_eq (%8, %9)
  drop %8
  ret %10
}

fn @main() -> int export {
b0:
  %20: str = str "q"
  %21: str = str "r"
  %0: str = copy %20
  %1: str = copy %21
  %2: list<str> = list.lit %0, %1
  %3: int = iconst 0
  %4: bool = call @is_q (%2, %3)
  %5: int = iconst 5
  %6: bool = call @is_q (%2, %5)
  drop %2
  %7: int = iconst 1
  %8: int = iconst 0
  %9: int = select %4, %7, %8
  %10: int = select %6, %8, %7
  %11: int = iadd %9, %10
  ret %11
}
"#;

#[test]
fn copies_meeting_at_a_borrowed_block_parameter_are_removed() {
    let mut m = parse_module(PHI).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    let before = Interp::new(&m).run_entry().map_err(|f| f.message);
    assert!(opt::copyelim::run(&mut m));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    assert_eq!(count(&m, "is_q", Op::Copy), 0);
    assert_eq!(count(&m, "is_q", Op::Drop), 0);
    let after = Interp::new(&m).run_entry().map_err(|f| f.message);
    assert_eq!(before, after);
}

const LAST_USE: &str = r#"module "t"
alt List { Nil, More(next: List) }
entry @main

fn @collect(%n: int) -> List inline(never) {
b0:
  %z: int = iconst 0
  %nil: List = alt.new List.Nil
  br b1(%nil, %z)
b1(%acc: own List, %i: int):
  %nil2: List = alt.new List.Nil
  %k: List = alt.new List.More %nil2
  %c: List = copy %k
  %acc2: List = alt.new List.More %c
  %one: int = iconst 1
  %i2: int = iadd.chk %i, %one
  %lt: bool = icmp.lt %i2, %n
  drop %acc
  br_if %lt, b2(), b3()
b2():
  drop %k
  br b1(%acc2, %i2)
b3():
  drop %k
  ret %acc2
}

fn @skipped(%n: int) -> int inline(never) {
b0:
  %nil: List = alt.new List.Nil
  %k: List = alt.new List.More %nil
  %z: int = iconst 0
  %lt: bool = icmp.lt %z, %n
  br_if %lt, b1(), b2()
b1():
  %c: List = copy %k
  %t: int = alt.tag %c
  drop %c
  br b2()
b2():
  drop %k
  ret %z
}

fn @main() -> int export {
b0:
  %n: int = iconst 5
  %l: List = call @collect (%n)
  %t: int = alt.tag %l
  drop %l
  %s: int = call @skipped (%n)
  %r: int = iadd.chk %t, %s
  ret %r
}
"#;

#[test]
fn a_copy_at_the_last_use_across_blocks_becomes_a_move() {
    let mut m = parse_module(LAST_USE).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    let before = Interp::new(&m).run_entry().map_err(|f| f.message);
    assert!(opt::copyelim::run(&mut m));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    assert_eq!(count(&m, "collect", Op::Copy), 0, "{}", print_module(&m));
    // Only the drop of the previous accumulator remains.
    assert_eq!(count(&m, "collect", Op::Drop), 1, "{}", print_module(&m));
    // The drop in b2 also runs on the path that skips the copy, so it stays.
    assert_eq!(
        count(&m, "skipped", Op::Drop),
        1 + count(&m, "skipped", Op::Copy)
    );
    assert_eq!(before, Interp::new(&m).run_entry().map_err(|f| f.message));
}

/// One block that builds a collection entry by entry the way a map literal lowers: each entry
/// copies a literal key, computes the same type descriptor, moves the collection through a
/// slot around a runtime call, and the copies are all dropped at the end of the scope.
fn literal_entries(n: usize) -> String {
    let mut s = String::from(
        r#"module "t"
file 0 "t.ms"
extern @msrt_coll_new() -> list<int>
extern @msrt_coll_add(ptr, ptr, str) -> unit
entry @main

fn @main() -> int export {
b0:
  %0: list<int> = call.rt @msrt_coll_new ()
  %1: ptr = slot list<int>
  put %1, %0
"#,
    );
    let mut v = 2;
    let mut copies = Vec::new();
    for i in 0..n {
        s.push_str(&format!(
            "  %{v}: str = str \"k{i}\"\n  %{c}: str = copy %{v}\n  %{t}: list<int> = take list<int> %1\n  %{sl}: ptr = slot list<int>\n  put %{sl}, %{t}\n  %{d}: ptr = typedesc str\n  %{u}: unit = call.rt @msrt_coll_add (%{sl}, %{d}, %{c})\n  %{b}: list<int> = take list<int> %{sl}\n  put %1, %{b}\n",
            c = v + 1,
            t = v + 2,
            sl = v + 3,
            d = v + 4,
            u = v + 5,
            b = v + 6
        ));
        copies.push(v + 1);
        v += 7;
    }
    s.push_str(&format!(
        "  %{v}: list<int> = take list<int> %1\n  %{l}: int = list.len %{v}\n  drop %{v}\n",
        l = v + 1
    ));
    for c in copies {
        s.push_str(&format!("  drop %{c}\n"));
    }
    s.push_str(&format!("  ret %{}\n}}\n", v + 1));
    s
}

#[test]
fn a_long_literal_is_optimized_in_linear_time() {
    // 6000 entries (54 000 instructions). Each copy's span to its drop, each roundtrip's
    // removal and each common subexpression's removal used to be a scan or a shift of the
    // whole block.
    let mut m = parse_module(&literal_entries(6000)).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    let start = std::time::Instant::now();
    opt::optimize(&mut m, opt::Level::Speed, true);
    assert!(
        start.elapsed() < std::time::Duration::from_secs(20),
        "took {:?}",
        start.elapsed()
    );
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", &print_module(&m)[..2000]);
    }
    assert_eq!(count(&m, "main", Op::Copy), 0);
    assert_eq!(count(&m, "main", Op::TypeDesc), 1);
    // Only the collection's own slot is left; every entry's roundtrip through a slot is gone.
    assert_eq!(count(&m, "main", Op::Slot), 1);
}
