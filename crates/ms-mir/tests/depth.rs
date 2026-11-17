use ms_mir::depth;
use ms_mir::ir::{Imm, Module, Op, Term};
use ms_mir::parse::parse_module;
use ms_mir::verify::verify_module;

fn lowered(body: &str) -> Module {
    let src = format!("module \"t\"\nentry @main\n{body}");
    let mut m = parse_module(&src).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    assert!(depth::lower(&mut m));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}\n{}", ms_mir::print::print_module(&m)));
    m
}

fn ops(m: &Module, name: &str) -> Vec<Op> {
    let f = &m.funcs[m.func_by_name(name).expect("function").index()];
    f.blocks
        .iter()
        .flat_map(|b| b.insts.iter().map(|i| i.op))
        .collect()
}

const FIB: &str = "fn @main() -> int {\nb0:\n  depth.enter\n  %0: int = iconst 3\n  %1: int = call @fib (%0)\n  ret %1\n}\n\
fn @fib(%0: int) -> int {\nb0:\n  depth.enter\n  ret %0\n}\n";

#[test]
fn the_check_becomes_stack_low_and_a_branch_to_an_out_of_line_grow_path() {
    let m = lowered(FIB);
    let f = &m.funcs[m.func_by_name("fib").unwrap().index()];
    assert!(!ops(&m, "fib").contains(&Op::DepthEnter));
    assert_eq!(f.blocks[0].insts.len(), 1);
    assert_eq!(f.blocks[0].insts[0].op, Op::StackLow);
    let Term::CondBr { then, els, .. } = &f.blocks[0].term else {
        panic!("the entry block branches on the check");
    };
    assert!(f.cold.contains(&then.block) && !f.cold.contains(&els.block));
}

#[test]
fn every_recursive_function_gets_a_grow_shim_that_calls_it() {
    let m = lowered(FIB);
    let shim = m.func_by_name("fib.grow").expect("the grow shim");
    let calls: Vec<_> = m.funcs[shim.index()]
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter(|i| i.op == Op::Call)
        .collect();
    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0].imm, Imm::Func(m.func_by_name("fib").unwrap()));
}

#[test]
fn void_results_and_droppable_parameters_lower_and_round_trip_through_text() {
    let m = lowered(
        "fn @main() -> int {\nb0:\n  depth.enter\n  %0: int = iconst 0\n  ret %0\n}\n\
         fn @walk(%0: move str, %1: int) -> void {\nb0:\n  depth.enter\n  drop %0\n  %2: void = void\n  ret %2\n}\n",
    );
    let text = ms_mir::print::print_module(&m);
    assert!(text.contains("stack.low"), "{text}");
    let again = parse_module(&text).unwrap_or_else(|e| panic!("{e}\n{text}"));
    verify_module(&again).unwrap_or_else(|e| panic!("{e:?}"));
    assert!(m.func_by_name("main.grow").is_some() && m.func_by_name("walk.grow").is_some());
}

#[test]
fn a_module_without_checks_is_left_alone() {
    let src =
        "module \"t\"\nentry @main\nfn @main() -> int {\nb0:\n  %0: int = iconst 1\n  ret %0\n}\n";
    let mut m = parse_module(src).unwrap();
    assert!(!depth::lower(&mut m));
}
