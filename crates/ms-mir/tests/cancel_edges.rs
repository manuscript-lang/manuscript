use ms_mir::cancel_edges;
use ms_mir::ir::{Imm, Module, Op};
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

const HEAD: &str = "module \"t\"\nentry @main\nextern @msrt_promise_start(int) -> int spawns_task\nextern @msrt_task_pause(int) -> int\n";

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
  %r: int = call.rt @msrt_task_pause (%n)
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
        "module \"t\"\nentry @main\nextern @msrt_task_pause(int) -> int\n{src}"
    ))
    .unwrap_or_else(|e| panic!("{e}"));
    assert!(!cancel_edges::run(&mut m));
}

const RAW_HOLDS_OWNER: &str = r#"
fn @main() -> int {
b0:
  scope.begin 1 0
  %lit: str = str "held"
  %s: str = clone %lit
  scope.own 1 0 %s
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_pause (%n)
  scope.end 1 0
  ret %r
}
"#;

#[test]
fn a_raw_function_leaves_by_scope_end_and_pops_its_registrations() {
    let mut m = parse_module(&format!("{HEAD}{RAW_HOLDS_OWNER}")).unwrap_or_else(|e| panic!("{e}"));
    ms_mir::elaborate::run_with(&mut m, true).unwrap_or_else(|e| panic!("{e}"));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    let main = &m.funcs[m.func_by_name("main").expect("main").index()];
    assert!(main.explicit_cancel);
    assert_eq!(calls(&m, "main", "msrt_cleanup_truncate"), 1);
    assert_eq!(calls(&m, "main", "msrt_unwinding"), 1);
    // The held string is dropped on the normal path and on the cancel exit; no hybrid exit follows.
    assert_eq!(count(&m, "main", Op::Drop), 2);
    assert!(!cancel_edges::run(&mut m) || calls(&m, "main", "msrt_cleanup_unwind_to") == 0);
}

#[test]
fn a_program_that_starts_no_task_gets_no_explicit_exit() {
    let mut m = parse_module(&format!(
        "module \"t\"\nentry @main\nextern @msrt_task_pause(int) -> int\n{RAW_HOLDS_OWNER}"
    ))
    .unwrap_or_else(|e| panic!("{e}"));
    ms_mir::elaborate::run_with(&mut m, true).unwrap_or_else(|e| panic!("{e}"));
    assert!(!m.funcs[m.func_by_name("main").expect("main").index()].explicit_cancel);
}
