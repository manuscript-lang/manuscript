use ms_mir::cancel_edges;
use ms_mir::ir::{Imm, Module, Op};
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

const HEAD: &str = "module \"t\"\nentry @main\nextern @msrt_promise_start(int) -> int spawns_task\nextern @msrt_task_sleep(int) -> int\n";

fn rewrite(body: &str) -> (Module, bool) {
    let mut m = parse_module(&format!("{HEAD}{body}")).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    let changed = cancel_edges::run(&mut m);
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    (m, changed)
}

fn count(m: &Module, name: &str, op: Op) -> usize {
    m.funcs[m.func_by_name(name).expect("function").index()]
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter(|i| i.op == op)
        .count()
}

fn calls(m: &Module, name: &str, symbol: &str) -> usize {
    m.funcs[m.func_by_name(name).expect("function").index()]
        .blocks
        .iter()
        .flat_map(|b| &b.insts)
        .filter(|i| matches!((i.op, i.imm), (Op::CallRt, Imm::Ext(e)) if m.externs[e.index()].name == symbol))
        .count()
}

const HOLDS_STRING: &str = r#"
fn @main() -> int {
b0:
  %s: str = str "held"
  %s2: str = clone %s
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  drop %s2
  ret %r
}
"#;

#[test]
fn tests_the_flag_after_a_parking_call_and_forgets_what_is_held() {
    let (m, changed) = rewrite(HOLDS_STRING);
    assert!(changed);
    assert_eq!(calls(&m, "main", "msrt_unwinding"), 1);
    assert_eq!(calls(&m, "main", "msrt_cleanup_base"), 1);
    assert_eq!(calls(&m, "main", "msrt_cleanup_unwind_to"), 1);
    assert_eq!(count(&m, "main", Op::Forget), 1);
}

#[test]
fn leaves_a_program_that_starts_no_task_alone() {
    let src = HOLDS_STRING;
    let mut m = parse_module(&format!(
        "module \"t\"\nentry @main\nextern @msrt_task_sleep(int) -> int\n{src}"
    ))
    .unwrap_or_else(|e| panic!("{e}"));
    assert!(!cancel_edges::run(&mut m));
}
