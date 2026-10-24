use ms_mir::ir::{Module, Op};
use ms_mir::opt;
use ms_mir::parse::parse_module;
use ms_mir::verify::verify_module;

fn optimized(src: &str) -> Module {
    let mut m = parse_module(src).expect("parse");
    verify_module(&m).expect("input verifies");
    opt::lastuse::run(&mut m);
    verify_module(&m).expect("output verifies");
    m
}

/// Op names of the entry function's blocks, in order, as one line per block.
fn ops(m: &Module, name: &str) -> Vec<Vec<Op>> {
    let f = &m.funcs[m.func_by_name(name).expect("function").index()];
    f.blocks
        .iter()
        .map(|b| b.insts.iter().map(|i| i.op).collect())
        .collect()
}

const STRAIGHT: &str = r#"module "t"
file 0 "t.ms"
entry @main

fn @main() -> int export {
b0:
  %0: list<int> = list.lit
  %1: int = list.len %0
  %2: list<int> = list.lit
  %3: int = list.len %2
  %4: int = iadd %1, %3
  drop %2
  drop %0
  ret %4
}
"#;

#[test]
fn a_value_is_dropped_right_after_its_last_use() {
    let m = optimized(STRAIGHT);
    let b = &ops(&m, "main")[0];
    let drops: Vec<usize> = (0..b.len()).filter(|k| b[*k] == Op::Drop).collect();
    // `%0` goes before the second list is built; `%2` right after its length is read.
    assert_eq!(b[..4], [Op::ListLit, Op::ListLen, Op::Drop, Op::ListLit]);
    assert_eq!(drops.len(), 2);
}

const LOOP: &str = r#"module "t"
file 0 "t.ms"
entry @main

fn @main() -> int export {
b0:
  %0: list<int> = list.lit
  %1: int = iconst 0
  %2: int = iconst 3
  %3: int = iconst 1
  br b1(%1)
b1(%4: int):
  %5: bool = icmp.lt %4, %2
  br_if %5, b2(), b3()
b2():
  %6: int = list.len %0
  %7: int = iadd %4, %3
  br b1(%7)
b3():
  drop %0
  ret %1
}
"#;

#[test]
fn a_value_used_in_a_loop_is_dropped_on_the_exit_edge() {
    let m = optimized(LOOP);
    let all = ops(&m, "main");
    // Never inside the loop body.
    assert!(!all[2].contains(&Op::Drop));
    assert_eq!(all.iter().flatten().filter(|o| **o == Op::Drop).count(), 1);
}
