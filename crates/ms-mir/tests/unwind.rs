use ms_mir::ir::{Imm, Module, Op};
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::unwind;
use ms_mir::verify::verify_module;

const SPAWNER: &str = "extern @msrt_scope_spawn(int) -> int\n";

fn module(body: &str, spawner: bool) -> Module {
    let src = format!(
        "module \"t\"\nentry @main\n{}extern @msrt_task_sleep(int) -> int\nextern @msrt_string_eq(str, str) -> bool\n{body}",
        if spawner { SPAWNER } else { "" }
    );
    let m = parse_module(&src).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    m
}

fn rewrite(body: &str, spawner: bool) -> (Module, bool) {
    let mut m = module(body, spawner);
    let changed = unwind::run(&mut m);
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
  %s2: str = copy %s
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  drop %s2
  ret %r
}
"#;

#[test]
fn registers_an_owned_value_around_a_parking_call() {
    let (m, changed) = rewrite(HOLDS_STRING, true);
    assert!(changed, "{}", print_module(&m));
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
    assert_eq!(calls(&m, "main", "msrt_cleanup_discard"), 1);
    assert!(m.func_by_name("unwind.drop").is_some());
}

#[test]
fn leaves_programs_without_tasks_alone() {
    let (m, changed) = rewrite(HOLDS_STRING, false);
    assert!(!changed);
    assert_eq!(count(&m, "main", Op::CleanupPush), 0);
}

#[test]
fn skips_calls_that_cannot_be_cancelled() {
    let body = r#"
fn @main() -> int {
b0:
  %s: str = str "held"
  %t: str = copy %s
  %same: bool = call.rt @msrt_string_eq (%t, %s)
  drop %t
  ret
}
"#;
    let body = body.replace("ret\n", "%z: int = iconst 0\n  ret %z\n");
    let (m, changed) = rewrite(&body, true);
    assert!(!changed, "{}", print_module(&m));
}
