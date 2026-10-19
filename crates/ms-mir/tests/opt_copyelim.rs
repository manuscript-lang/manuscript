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
