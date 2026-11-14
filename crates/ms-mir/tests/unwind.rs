use ms_mir::ir::{Imm, Module, Op};
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::types::Ty;
use ms_mir::unwind;
use ms_mir::verify::verify_module;

const SPAWNER: &str = "extern @msrt_promise_start(int) -> int spawns_task\n";

fn module(body: &str, spawner: bool) -> Module {
    let src = format!(
        "module \"t\"\nentry @main\n{}extern @msrt_task_sleep(int) -> int\nextern @msrt_string_eq(str, str) -> bool string_eq\n{body}",
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
  %s2: str = clone %s
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
fn skips_instructions_that_cannot_be_cancelled_or_fault() {
    let body = r#"
fn @main() -> int {
b0:
  %s: str = str "held"
  %t: str = clone %s
  %a: int = iconst 2
  %b: int = iadd %a, %a
  drop %t
  ret %b
}
"#;
    let (m, changed) = rewrite(body, true);
    assert!(!changed, "{}", print_module(&m));
}

#[test]
fn registers_an_owned_value_around_a_faulting_operation() {
    let body = r#"
fn @main() -> int {
b0:
  %s: str = str "held"
  %t: str = clone %s
  %a: int = iconst 2
  %b: int = iadd.chk %a, %a
  %c: int = iadd.chk %b, %a
  drop %t
  ret %c
}
"#;
    let (m, changed) = rewrite(body, true);
    assert!(changed, "{}", print_module(&m));
    // Both checked additions share one registration of the held string.
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
    assert_eq!(calls(&m, "main", "msrt_cleanup_discard"), 1);
}

#[test]
fn registers_an_owned_value_before_an_explicit_fault() {
    let body = r#"
fn @main() -> int {
b0:
  %s: str = str "held"
  %t: str = clone %s
  fault index_out_of_range
}
"#;
    let (m, changed) = rewrite(body, true);
    assert!(changed, "{}", print_module(&m));
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
    assert_eq!(calls(&m, "main", "msrt_cleanup_discard"), 0);
}

#[test]
fn drops_a_value_a_with_close_uses_after_that_close() {
    let body = r#"
fn @close(%s: str) -> unit {
b0:
  %u: unit = unit
  ret %u
}

fn @main() -> int {
b0:
  %s: str = str "held"
  %t: str = clone %s
  %h: int = cleanup.push @close %t
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  drop %t
  ret %r
}
"#;
    let (m, changed) = rewrite(body, true);
    // No per-call drop is registered above the close, which would run first and free the value
    // the close still uses; the close itself drops the value when a cancellation unwinds.
    assert!(changed, "{}", print_module(&m));
    assert_eq!(count(&m, "main", Op::CleanupPush), 1);
    assert!(
        m.funcs.iter().any(|f| f.name == "unwind.close_drop"),
        "{}",
        print_module(&m)
    );
}

#[test]
fn leaves_a_value_taken_from_a_caller_slot_to_the_caller() {
    let body = r#"
fn @hold(%slot: ptr) -> int {
b0:
  %s: str = take str %slot
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %s
  ret %r
}

fn @main() -> int {
b0:
  %z: int = iconst 0
  ret %z
}
"#;
    let (m, changed) = rewrite(body, true);
    // The slot still holds the value while the call runs and its owner drops it on unwind;
    // registering it here too would drop it twice.
    assert!(!changed, "{}", print_module(&m));
    assert_eq!(count(&m, "hold", Op::CleanupPush), 0);
}

const SLOT_CALLER: &str = r#"
fn @main() -> int {
b0:
  %s: str = str "held"
  %t: str = clone %s
  %slot: ptr = slot str
  put %slot, %t
  %r: int = call @hold (%slot)
  %back: str = take str %slot
  drop %back
  ret %r
}
"#;

#[test]
fn covers_a_slot_value_that_the_callee_only_borrows() {
    let body = format!(
        r#"
fn @hold(%slot: ptr) -> int {{
b0:
  %s: str = take str %slot
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %s
  ret %r
}}
{SLOT_CALLER}"#
    );
    let (m, changed) = rewrite(&body, true);
    // The slot holds the only copy while the callee parks, so main registers a view of it.
    assert!(changed, "{}", print_module(&m));
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
    assert_eq!(count(&m, "main", Op::Load), 1, "{}", print_module(&m));
}

#[test]
fn covers_a_slot_value_that_the_callee_parks_in_a_local_slot_for_another_borrower() {
    let body = format!(
        r#"
fn @inner(%slot: ptr) -> int {{
b0:
  %s: str = take str %slot
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %s
  ret %r
}}
fn @hold(%slot: ptr) -> int {{
b0:
  %s: str = take str %slot
  %local: ptr = slot str
  put %local, %s
  %r: int = call @inner (%local)
  %back: str = take str %local
  put %slot, %back
  ret %r
}}
{SLOT_CALLER}"#
    );
    let (m, changed) = rewrite(&body, true);
    // `hold` only forwards the value to a borrower, so main still covers the slot it passed and
    // `hold` registers nothing for the value it took back from its local slot (a double drop).
    assert!(changed, "{}", print_module(&m));
    assert_eq!(
        count(&m, "hold", Op::CleanupPush),
        0,
        "{}",
        print_module(&m)
    );
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
}

#[test]
fn leaves_a_slot_value_to_the_caller_when_a_local_slot_also_holds_another_value() {
    let body = format!(
        r#"
fn @hold(%slot: ptr) -> int {{
b0:
  %s: str = take str %slot
  %lit: str = str "x"
  %other: str = clone %lit
  %local: ptr = slot str
  put %local, %other
  put %local, %s
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  %back: str = take str %local
  put %slot, %back
  ret %r
}}
{SLOT_CALLER}"#
    );
    let (m, _) = rewrite(&body, true);
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        0,
        "{}",
        print_module(&m)
    );
}

#[test]
fn covers_a_slot_value_that_flows_through_a_block_parameter() {
    let body = format!(
        r#"
fn @hold(%slot: ptr) -> int {{
b0:
  %s: str = take str %slot
  br b1(%s)
b1(%own: move str):
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %own
  ret %r
}}
{SLOT_CALLER}"#
    );
    let (m, changed) = rewrite(&body, true);
    // The callee's parameter is still the caller's value, so only the caller registers it.
    assert!(changed, "{}", print_module(&m));
    assert_eq!(
        count(&m, "hold", Op::CleanupPush),
        0,
        "{}",
        print_module(&m)
    );
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
}

#[test]
fn leaves_a_slot_value_that_the_callee_consumes() {
    let body = format!(
        r#"
fn @hold(%slot: ptr) -> int {{
b0:
  %s: str = take str %slot
  drop %s
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  %lit: str = str "new"
  %u: str = clone %lit
  put %slot, %u
  ret %r
}}
{SLOT_CALLER}"#
    );
    let (m, _) = rewrite(&body, true);
    // Registering the old value too would drop it twice.
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        0,
        "{}",
        print_module(&m)
    );
}

const LOOP_HOLDING_STRING: &str = r#"
fn @main() -> int {
b0:
  %s: str = str "held"
  %t: str = clone %s
  %zero: int = iconst 0
  br b1(%zero)
b1(%i: int):
  %ten: int = iconst 10
  %more: bool = icmp.lt %i, %ten
  br_if %more, b2(), b3()
b2():
  %one: int = iconst 1
  %next: int = iadd.chk %i, %one
  br b1(%next)
b3():
  drop %t
  ret %i
}
"#;

#[test]
fn registers_a_value_held_across_a_loop_once() {
    let (m, changed) = rewrite(LOOP_HOLDING_STRING, true);
    assert!(changed, "{}", print_module(&m));
    // One registration before the loop and one discard where it is left, none per iteration.
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
    assert_eq!(
        calls(&m, "main", "msrt_cleanup_discard"),
        1,
        "{}",
        print_module(&m)
    );
    let f = &m.funcs[m.func_by_name("main").expect("main").index()];
    let in_loop = [2usize]
        .iter()
        .all(|b| f.blocks[*b].insts.iter().all(|i| i.op != Op::CleanupPush));
    assert!(in_loop, "{}", print_module(&m));
}

#[test]
fn keeps_per_iteration_windows_for_a_value_defined_in_the_loop() {
    let body = r#"
fn @main() -> int {
b0:
  %zero: int = iconst 0
  br b1(%zero)
b1(%i: int):
  %ten: int = iconst 10
  %more: bool = icmp.lt %i, %ten
  br_if %more, b2(), b3()
b2():
  %s: str = str "held"
  %t: str = clone %s
  %one: int = iconst 1
  %next: int = iadd.chk %i, %one
  drop %t
  br b1(%next)
b3():
  ret %i
}
"#;
    let (m, changed) = rewrite(body, true);
    assert!(changed, "{}", print_module(&m));
    let f = &m.funcs[m.func_by_name("main").expect("main").index()];
    assert!(
        f.blocks[2].insts.iter().any(|i| i.op == Op::CleanupPush),
        "{}",
        print_module(&m)
    );
}

#[test]
fn ends_a_shared_window_at_a_with_open() {
    let body = r#"
fn @close(%s: str) -> unit {
b0:
  %u: unit = unit
  ret %u
}

fn @main() -> int {
b0:
  %s: str = str "held"
  %t: str = clone %s
  %w: str = str "with"
  %v: str = clone %w
  %a: int = iconst 2
  %b: int = iadd.chk %a, %a
  %h: int = cleanup.push @close %v
  %c: int = iadd.chk %b, %a
  cleanup.run %h
  drop %v
  drop %t
  ret %c
}
"#;
    let (m, changed) = rewrite(body, true);
    assert!(changed, "{}", print_module(&m));
    // Two windows around the checked additions: one discard must not pop the scope entry.
    assert_eq!(
        calls(&m, "main", "msrt_cleanup_discard"),
        2,
        "{}",
        print_module(&m)
    );
}

const SLOT_CLOSED: &str = r#"
extern @msrt_cleanup_discard(int) -> unit leaf cleanup_discard

fn @close(%p: ptr) -> unit {
b0:
  %u: unit = unit
  ret %u
}

fn @main() -> int {
b0:
  %b: str = str "held"
  %s: str = clone %b
  %slot: ptr = slot str
  put %slot, %s
  %h: int = cleanup.push @close %slot
  %t: str = take str %slot
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %t
  %HOLD
}
"#;

fn rewrite_slot_closed(tail: &str) -> Module {
    let mut m = module(&SLOT_CLOSED.replace("%HOLD", tail), true);
    let close = m.func_by_name("close").expect("close");
    m.funcs[close.index()].slot_close = Some(Ty::STR);
    unwind::run(&mut m);
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{}", print_module(&m));
    }
    m
}

#[test]
fn leaves_a_slot_value_to_its_active_scope_close() {
    // A drop registered for the taken value would run before the slot's close and free the
    // receiver the close still uses; the close drops what the slot holds.
    let m = rewrite_slot_closed("%d: unit = call.rt @msrt_cleanup_discard (%h)\n  ret %r");
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
}

#[test]
fn registers_a_slot_value_again_once_its_scope_close_is_discarded() {
    let m = rewrite_slot_closed(
        "%d: unit = call.rt @msrt_cleanup_discard (%h)\n  %u: str = take str %slot\n  %k: int = call.rt @msrt_task_sleep (%n)\n  drop %u\n  ret %k",
    );
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        2,
        "{}",
        print_module(&m)
    );
}

#[test]
fn leaves_a_type_refilled_after_a_field_move_to_the_caller() {
    // `self.items.pop()` then a parking call: the type taken from the caller's slot is refilled
    // with the shortened field and put back, so a cancellation at the call must not drop the
    // refilled type; the slot's owner still holds it and drops it.
    let body = r#"
type Src { items: list<int>, label: str }

fn @next(%slot: ptr) -> int {
b0:
  %s: Src = take Src %slot
  %l: list<int> = type.get Src.items %s
  %m: list<int> = move.out %l
  %f: Src = type.fill Src.items %s, %m
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %f
  ret %r
}

fn @main() -> int {
b0:
  %z: int = iconst 0
  ret %z
}
"#;
    let (m, changed) = rewrite(body, true);
    assert!(!changed, "{}", print_module(&m));
    assert_eq!(count(&m, "next", Op::CleanupPush), 0);
}

const PANICS_WITH_TEMPS: &str = r#"
extern @msrt_int_to_string(int) -> str leaf int_to_string
extern @msrt_string_concat(str, str) -> str fresh leaf string_concat
extern @msrt_fault_string(str) -> unit noreturn leaf
fn @main() -> int {
b0:
  %0: int = iconst 64
  %1: str = str "found "
  %2: str = call.rt @msrt_int_to_string (%0)
  %3: str = call.rt @msrt_string_concat (%1, %2)
  %4: unit = call.rt @msrt_fault_string (%3)
  unreachable
}
"#;

#[test]
fn registers_live_temporaries_before_a_noreturn_fault_call() {
    let (m, changed) = rewrite(PANICS_WITH_TEMPS, true);
    assert!(changed);
    // The concat window covers the int, and the message joins it at the fault call without
    // registering the int again.
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        2,
        "{}",
        print_module(&m)
    );
}

/// A recursive call that moves its argument consumes it: the rewrite of the function must read
/// the callee's parameter modes from its own signature while the function itself is swapped out.
#[test]
fn a_recursive_call_that_moves_an_argument_consumes_it() {
    let (m, _) = rewrite(
        r#"
fn @walk(%n: int, %s: move str) -> int {
b0:
  %z: int = iconst 0
  %done: bool = icmp.eq %n, %z
  br_if %done, b1(), b2()
b1():
  drop %s
  ret %z
b2():
  %one: int = iconst 1
  %m: int = isub %n, %one
  %r: int = call @walk (%m, %s)
  %t: int = call.rt @msrt_task_sleep (%r)
  ret %t
}

fn @main() -> int {
b0:
  %h: str = str "held"
  %s: str = clone %h
  %n: int = iconst 3
  %r: int = call @walk (%n, %s)
  ret %r
}
"#,
        true,
    );
    // The call takes `%s`, so nothing in `walk` is left to register around it or the sleep.
    assert_eq!(
        count(&m, "walk", Op::CleanupPush),
        0,
        "{}",
        print_module(&m)
    );
}
