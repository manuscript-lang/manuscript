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

// A value taken out of a local slot that no scope owns is an ordinary owner: the cancel exit drops it.
const RAW_HOLDS_TAKEN: &str = r#"
fn @main() -> int {
b0:
  scope.begin 1 0
  %lit: str = str "held"
  %s: str = clone %lit
  %p: ptr = slot str
  put %p, %s
  %t: str = take str %p
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_pause (%n)
  drop %t
  scope.end 1 0
  ret %r
}
"#;

#[test]
fn a_value_taken_from_a_local_slot_is_dropped_on_the_cancel_exit() {
    let mut m = parse_module(&format!("{HEAD}{RAW_HOLDS_TAKEN}")).unwrap_or_else(|e| panic!("{e}"));
    ms_mir::elaborate::run_with(&mut m, true).unwrap_or_else(|e| panic!("{e}"));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    assert!(m.funcs[m.func_by_name("main").expect("main").index()].explicit_cancel);
    assert_eq!(count(&m, "main", Op::Drop), 2);
}

// A value taken from a `var` slot parameter goes back into the slot on the cancel exit, so the
// caller's scope end releases it once.
const RAW_TAKES_VAR: &str = r#"
fn @held(%p: ptr) -> int {
b0:
  scope.begin 1 0
  %t: str = take str %p
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_pause (%n)
  put %p, %t
  scope.end 1 0
  ret %r
}
fn @main() -> int {
b0:
  %r: int = iconst 0
  ret %r
}
"#;

#[test]
fn a_value_taken_from_a_var_slot_is_put_back_on_the_cancel_exit() {
    let mut m = parse_module(&format!("{HEAD}{RAW_TAKES_VAR}")).unwrap_or_else(|e| panic!("{e}"));
    let held = m.func_by_name("held").expect("held");
    m.funcs[held.index()].noalias = vec![0];
    ms_mir::elaborate::run_with(&mut m, true).unwrap_or_else(|e| panic!("{e}"));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    assert!(
        m.funcs[held.index()].explicit_cancel,
        "{}",
        print_module(&m)
    );
    // The normal exit puts the value back once and the cancel exit does the same.
    assert_eq!(count(&m, "held", Op::Put), 2);
}

#[test]
fn a_value_taken_from_a_borrowed_slot_keeps_the_function_hybrid() {
    let mut m = parse_module(&format!("{HEAD}{RAW_TAKES_VAR}")).unwrap_or_else(|e| panic!("{e}"));
    ms_mir::elaborate::run_with(&mut m, true).unwrap_or_else(|e| panic!("{e}"));
    let held = m.func_by_name("held").expect("held");
    assert!(!m.funcs[held.index()].explicit_cancel);
}

// A local slot that holds an owned value no scope owns is released by the cancel exit.
const HOLDS_IN_SLOT: &str = r#"
fn @held() -> int {
b0:
  scope.begin 1 0
  %s: ptr = slot str
  %l: str = str "x"
  %v: str = clone %l
  put %s, %v
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_pause (%n)
  %t: str = take str %s
  drop %t
  scope.end 1 0
  ret %r
}
fn @main() -> int {
b0:
  %r: int = iconst 0
  ret %r
}
"#;

#[test]
fn a_local_slot_holding_an_owned_value_is_released_on_the_cancel_exit() {
    let mut m = parse_module(&format!("{HEAD}{HOLDS_IN_SLOT}")).unwrap_or_else(|e| panic!("{e}"));
    ms_mir::elaborate::run_with(&mut m, true).unwrap_or_else(|e| panic!("{e}"));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    let held = m.func_by_name("held").expect("held");
    assert!(
        m.funcs[held.index()].explicit_cancel,
        "{}",
        print_module(&m)
    );
    // The normal path takes the value once and the cancel exit takes and drops it.
    assert_eq!(count(&m, "held", Op::Take), 2);
}

// A `var` slot handed to a closure call is restored only when every closure of that type restores
// its own, so the caller converts only then.
fn closure_call_module(second_closure: &str) -> String {
    format!(
        r#"{HEAD}
fn @inner(%env: ptr, %p: ptr) -> int closure() {{
b0:
  scope.begin 1 0
  %t: str = take str %p
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_pause (%n)
  put %p, %t
  scope.end 1 0
  ret %r
}}
{second_closure}
fn @outer(%p: ptr, %f: fn(ptr) -> int) -> int {{
b0:
  scope.begin 1 0
  %t: str = take str %p
  %s: ptr = slot str
  put %s, %t
  %r: int = call.ind (%f, %s)
  %u: str = take str %s
  put %p, %u
  scope.end 1 0
  ret %r
}}
fn @main() -> int {{
b0:
  %a: fn(ptr) -> int = closure.new @inner
  %b: fn(ptr) -> int = closure.new @other
  drop %a
  drop %b
  %z: int = iconst 0
  ret %z
}}
"#
    )
}

fn converts_outer(second_closure: &str, second_restores: bool) -> bool {
    let mut m =
        parse_module(&closure_call_module(second_closure)).unwrap_or_else(|e| panic!("{e}"));
    for (name, var) in [("inner", true), ("other", second_restores), ("outer", true)] {
        let f = m.func_by_name(name).expect("function");
        let slot = if name == "outer" { 0 } else { 1 };
        m.funcs[f.index()].noalias = if var { vec![slot] } else { Vec::new() };
    }
    ms_mir::elaborate::run_with(&mut m, true).unwrap_or_else(|e| panic!("{e}"));
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    let outer = m.func_by_name("outer").expect("outer");
    m.funcs[outer.index()].explicit_cancel
}

const RESTORING_OTHER: &str = r#"
fn @other(%env: ptr, %p: ptr) -> int closure() {
b0:
  scope.begin 1 0
  %t: str = take str %p
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_pause (%n)
  put %p, %t
  scope.end 1 0
  ret %r
}
"#;

#[test]
fn a_var_slot_handed_to_a_closure_call_converts_when_every_closure_restores() {
    assert!(converts_outer(RESTORING_OTHER, true));
}

#[test]
fn a_var_slot_handed_to_a_closure_call_stays_hybrid_when_one_closure_may_not_restore() {
    // The same closure without its `var` slot marked: the call cannot assume it restores.
    assert!(!converts_outer(RESTORING_OTHER, false));
}
