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
fn skips_instructions_that_cannot_be_cancelled_or_fault() {
    let body = r#"
fn @main() -> int {
b0:
  %s: str = str "held"
  %t: str = copy %s
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
  %t: str = copy %s
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
  %t: str = copy %s
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
  %t: str = copy %s
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
  %t: str = copy %s
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
fn covers_a_slot_value_that_flows_through_a_block_parameter() {
    let body = format!(
        r#"
fn @hold(%slot: ptr) -> int {{
b0:
  %s: str = take str %slot
  br b1(%s)
b1(%own: own str):
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
  %u: str = copy %lit
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
  %t: str = copy %s
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
  %t: str = copy %s
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
  %t: str = copy %s
  %w: str = str "with"
  %v: str = copy %w
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

const SLOT_CLOSE: &str = r#"
fn @close_slot(%slot: ptr) -> unit {
b0:
  %held: str = load str %slot
  %u: unit = unit
  ret %u
}
"#;

fn slot_round_trip(before_take: &str, during: &str, callback: &str) -> Module {
    let body = format!(
        r#"
extern @msrt_cleanup_discard(int) -> unit
extern @msrt_cleanup_cancel(int) -> unit
{SLOT_CLOSE}
fn @opaque(%slot: ptr) -> unit {{
b0:
  %u: unit = unit
  ret %u
}}
fn @main() -> int {{
b0:
  %s: str = str "held"
  %t: str = copy %s
  %slot: ptr = slot str
  put %slot, %t
  %h: int = cleanup.push @{callback} %slot
  {before_take}
  %v: str = take str %slot
  {during}
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %v
  %back: str = take str %slot
  drop %back
  ret %r
}}
"#
    );
    rewrite(&body, true).0
}

#[test]
fn active_slot_close_owns_the_borrowed_round_trip() {
    let m = slot_round_trip("", "", "close_slot");
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
}

#[test]
fn invalidated_slot_close_does_not_own_a_later_take() {
    for invalidation in [
        "%gone: unit = call.rt @msrt_cleanup_discard (%h)",
        "%gone: unit = call.rt @msrt_cleanup_cancel (%h)",
        "cleanup.run %h",
    ] {
        let m = slot_round_trip(invalidation, "", "close_slot");
        assert_eq!(
            count(&m, "main", Op::CleanupPush),
            2,
            "{}",
            print_module(&m)
        );
    }
}

#[test]
fn overwritten_slot_does_not_cover_its_old_value() {
    let m = slot_round_trip(
        "",
        "%fresh: str = copy %s\n  put %slot, %fresh",
        "close_slot",
    );
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        2,
        "{}",
        print_module(&m)
    );
}

#[test]
fn arbitrary_pointer_cleanup_is_not_a_slot_owner() {
    let m = slot_round_trip("", "", "opaque");
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        2,
        "{}",
        print_module(&m)
    );
}

#[test]
fn discarding_a_newer_cleanup_preserves_the_older_slot_owner() {
    let before = "%other: ptr = slot str\n  %extra: int = cleanup.push @opaque %other\n  %gone: unit = call.rt @msrt_cleanup_discard (%extra)";
    let m = slot_round_trip(before, "", "close_slot");
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        2,
        "{}",
        print_module(&m)
    );
}

fn conditional_slot_round_trip(fresh: bool, loop_back: bool) -> Module {
    let branch_value = if fresh {
        "drop %right\n  %fresh: str = copy %s\n  br b3(%fresh, %r2)"
    } else {
        "br b3(%right, %r2)"
    };
    let back = if loop_back {
        "br_if %choose, b1(%joined), b4()"
    } else {
        "br b4()"
    };
    let body = format!(
        r#"
{SLOT_CLOSE}
fn @main() -> int {{
b0:
  %s: str = str "held"
  %t: str = copy %s
  %slot: ptr = slot str
  put %slot, %t
  %h: int = cleanup.push @close_slot %slot
  %v: str = take str %slot
  %choose: bool = bconst true
  %n: int = iconst 5
  br_if %choose, b1(%v), b2(%v)
b1(%left: own str):
  %r1: int = call.rt @msrt_task_sleep (%n)
  br b3(%left, %r1)
b2(%right: own str):
  %r2: int = call.rt @msrt_task_sleep (%n)
  {branch_value}
b3(%joined: own str, %result: int):
  %r3: int = call.rt @msrt_task_sleep (%n)
  {back}
b4():
  put %slot, %joined
  %back: str = take str %slot
  drop %back
  ret %result
}}
"#
    );
    rewrite(&body, true).0
}

#[test]
fn active_slot_close_covers_identity_through_both_branch_parameters() {
    let m = conditional_slot_round_trip(false, false);
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
}

#[test]
fn active_slot_close_covers_an_identity_loop_without_hoisting_a_second_drop() {
    let m = conditional_slot_round_trip(false, true);
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
}

#[test]
fn mixed_fresh_phi_does_not_inherit_slot_coverage() {
    let m = conditional_slot_round_trip(true, false);
    let f = &m.funcs[m.func_by_name("main").unwrap().index()];
    assert!(
        f.blocks[3].insts.iter().any(|i| i.op == Op::CleanupPush),
        "{}",
        print_module(&m)
    );
}

#[test]
fn cell_drop_covers_normal_close_after_its_scope_entry_ends() {
    let body = format!(
        r#"
extern @msrt_cleanup_discard(int) -> unit
{SLOT_CLOSE}
fn @hold(%slot: ptr) -> int {{
b0:
  %value: str = take str %slot
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %value
  ret %r
}}
fn @main() -> int {{
b0:
  %s: str = str "held"
  %t: str = copy %s
  %slot: ptr = slot str
  put %slot, %t
  %h: int = cleanup.push @close_slot %slot
  %first: int = call @hold (%slot)
  %gone: unit = call.rt @msrt_cleanup_discard (%h)
  %second: int = call @hold (%slot)
  %back: str = take str %slot
  drop %back
  ret %second
}}
"#
    );
    let (m, _) = rewrite(&body, true);
    // Active first call needs no duplicate drop; the second call has no scope owner left.
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        2,
        "{}",
        print_module(&m)
    );
    assert_eq!(count(&m, "main", Op::Load), 1, "{}", print_module(&m));
}

#[test]
fn escaped_slot_address_before_take_cannot_prove_a_round_trip() {
    let body = format!(
        r#"
{SLOT_CLOSE}
fn @main() -> int {{
b0:
  %s: str = str "held"
  %t: str = copy %s
  %slot: ptr = slot str
  put %slot, %t
  %h: int = cleanup.push @close_slot %slot
  br b1(%slot)
b1(%alias: ptr):
  %v: str = take str %slot
  %fresh: str = copy %s
  put %alias, %fresh
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %v
  %back: str = take str %slot
  drop %back
  ret %r
}}
"#
    );
    let (m, _) = rewrite(&body, true);
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        2,
        "{}",
        print_module(&m)
    );
}

#[test]
fn borrowed_projection_cannot_escape_a_covered_slot_snapshot() {
    for escape in ["", "store %destination, %field"] {
        let body = format!(
            r#"
record Holder {{ field: str }}
fn @close_holder(%slot: ptr) -> unit {{
b0:
  %held: Holder = load Holder %slot
  %u: unit = unit
  ret %u
}}
fn @main() -> int {{
b0:
  %s: str = str "held"
  %t: str = copy %s
  %initial: Holder = rec.new Holder %t
  %slot: ptr = slot Holder
  put %slot, %initial
  %h: int = cleanup.push @close_holder %slot
  %v: Holder = take Holder %slot
  %field: str = rec.get Holder.field %v
  %destination: ptr = slot str
  {escape}
  %equal: bool = call.rt @msrt_string_eq (%field, %field)
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %v
  %back: Holder = take Holder %slot
  drop %back
  ret %r
}}
"#
        );
        let (m, _) = rewrite(&body, true);
        let expected = if escape.is_empty() { 1 } else { 2 };
        assert_eq!(
            count(&m, "main", Op::CleanupPush),
            expected,
            "{}",
            print_module(&m)
        );
    }
}

#[test]
fn interface_payload_pointer_requires_a_proven_borrowing_callee() {
    for consumes in [false, true] {
        let finish = if consumes {
            "drop %value"
        } else {
            "put %slot, %value"
        };
        let body = format!(
            r#"
iface Area {{ area() -> int }}
vtable @v_str: Area for str {{ @area_str }}
fn @area_str(%self: ptr) -> int method {{
b0:
  %r: int = iconst 1
  ret %r
}}
fn @close_iface(%slot: ptr) -> unit {{
b0:
  %held: dyn Area = load dyn Area %slot
  %u: unit = unit
  ret %u
}}
fn @payload(%slot: ptr) -> int {{
b0:
  %value: str = take str %slot
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  {finish}
  ret %r
}}
fn @main() -> int {{
b0:
  %s: str = str "held"
  %t: str = copy %s
  %initial: dyn Area = iface.new @v_str %t
  %slot: ptr = slot dyn Area
  put %slot, %initial
  %h: int = cleanup.push @close_iface %slot
  %v: dyn Area = take dyn Area %slot
  %data: ptr = iface.data %v
  %r: int = call @payload (%data)
  put %slot, %v
  %back: dyn Area = take dyn Area %slot
  drop %back
  ret %r
}}
"#
        );
        let (m, _) = rewrite(&body, true);
        let expected = if consumes { 2 } else { 1 };
        assert_eq!(
            count(&m, "main", Op::CleanupPush),
            expected,
            "{}",
            print_module(&m)
        );
    }
}

fn cell_with_result_branch(discard: bool) -> Module {
    let ending = if discard {
        "%gone: unit = call.rt @msrt_cleanup_discard (%h)"
    } else {
        ""
    };
    let body = format!(
        r#"
extern @msrt_cleanup_discard(int) -> unit
{SLOT_CLOSE}
fn @hold(%slot: ptr) -> int {{
b0:
  %value: str = take str %slot
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %value
  ret %r
}}
fn @main() -> int {{
b0:
  %s: str = str "held"
  %t: str = copy %s
  %slot: ptr = slot str
  put %slot, %t
  %h: int = cleanup.push @close_slot %slot
  {ending}
  %r: int = call @hold (%slot)
  %z: int = iconst 0
  %choose: bool = icmp.eq %r, %z
  br_if %choose, b1(), b2()
b1():
  %left: str = take str %slot
  drop %left
  ret %r
b2():
  %right: str = take str %slot
  drop %right
  ret %r
}}
"#
    );
    rewrite(&body, true).0
}

#[test]
fn scoped_cell_full_across_result_branches_gets_only_the_uncovered_call_drop() {
    for discard in [false, true] {
        let m = cell_with_result_branch(discard);
        let expected = if discard { 2 } else { 1 };
        assert_eq!(
            count(&m, "main", Op::CleanupPush),
            expected,
            "{}",
            print_module(&m)
        );
    }
}

#[test]
fn unknown_cleanup_handle_does_not_imply_an_inactive_slot_owner() {
    let body = format!(
        r#"
extern @msrt_cleanup_cancel(int) -> unit
{SLOT_CLOSE}
fn @hold(%slot: ptr) -> int {{
b0:
  %value: str = take str %slot
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %value
  ret %r
}}
fn @main() -> int {{
b0:
  %s: str = str "held"
  %t: str = copy %s
  %slot: ptr = slot str
  put %slot, %t
  %h: int = cleanup.push @close_slot %slot
  %zero: int = iconst 0
  %none: unit = call.rt @msrt_cleanup_cancel (%zero)
  %r: int = call @hold (%slot)
  %back: str = take str %slot
  drop %back
  ret %r
}}
"#
    );
    let (m, _) = rewrite(&body, true);
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
}

#[test]
fn mixed_scope_activity_at_a_join_cannot_add_a_cell_snapshot() {
    let body = format!(
        r#"
extern @msrt_cleanup_discard(int) -> unit
{SLOT_CLOSE}
fn @hold(%slot: ptr) -> int {{
b0:
  %value: str = take str %slot
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %value
  ret %r
}}
fn @main() -> int {{
b0:
  %s: str = str "held"
  %t: str = copy %s
  %slot: ptr = slot str
  put %slot, %t
  %h: int = cleanup.push @close_slot %slot
  %choose: bool = bconst true
  br_if %choose, b1(), b2()
b1():
  %gone: unit = call.rt @msrt_cleanup_discard (%h)
  br b3()
b2():
  br b3()
b3():
  %r: int = call @hold (%slot)
  %back: str = take str %slot
  drop %back
  ret %r
}}
"#
    );
    let (m, _) = rewrite(&body, true);
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
}

#[test]
fn mixed_cell_occupancy_at_fault_join_cannot_register_uninitialized_memory() {
    let body = format!(
        r#"
extern @msrt_cleanup_discard(int) -> unit
{SLOT_CLOSE}
fn @main() -> int {{
b0:
  %s: str = str "held"
  %t: str = copy %s
  %slot: ptr = slot str
  put %slot, %t
  %h: int = cleanup.push @close_slot %slot
  %gone: unit = call.rt @msrt_cleanup_discard (%h)
  %choose: bool = bconst true
  br_if %choose, b1(), b2()
b1():
  %back: str = take str %slot
  drop %back
  br b3()
b2():
  br b3()
b3():
  fault "stopped"
}}
"#
    );
    let (m, _) = rewrite(&body, true);
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
}

fn snapshot_branch_transition(transition: &str) -> Module {
    let body = format!(
        r#"
extern @msrt_cleanup_discard(int) -> unit
extern @msrt_cleanup_cancel(int) -> unit
{SLOT_CLOSE}
fn @probe(%choice: bool, %other: bool) -> int {{
b0:
  %s: str = str "held allocated contents"
  %t: str = copy %s
  %slot: ptr = slot str
  put %slot, %t
  %h: int = cleanup.push @close_slot %slot
  %v: str = take str %slot
  %n: int = iconst 5
  br_if %choice, b1(), b2()
b1():
  %sleep: int = call.rt @msrt_task_sleep (%n)
  put %slot, %v
  %gone1: unit = call.rt @msrt_cleanup_discard (%h)
  %back: str = take str %slot
  drop %back
  %zero: int = iconst 0
  ret %zero
b2():
  {transition}
}}
fn @main() -> int {{
b0:
  %choice: bool = bconst true
  %other: bool = bconst false
  %r: int = call @probe (%choice, %other)
  ret %r
}}
"#
    );
    rewrite(&body, true).0
}

fn block_registrations(m: &Module, name: &str) -> Vec<usize> {
    m.funcs[m.func_by_name(name).unwrap().index()]
        .blocks
        .iter()
        .map(|b| b.insts.iter().filter(|i| i.op == Op::CleanupPush).count())
        .collect()
}

#[test]
fn detached_fault_branch_is_covered_without_dropping_the_protected_sibling() {
    let m = snapshot_branch_transition(
        "%gone: unit = call.rt @msrt_cleanup_discard (%h)\n  fault \"detached\"",
    );
    assert_eq!(
        block_registrations(&m, "probe"),
        [1, 0, 1],
        "{}",
        print_module(&m)
    );
}

#[test]
fn exact_owner_transitions_cover_implicit_exits_only_on_the_detached_branch() {
    for transition in [
        "%gone: unit = call.rt @msrt_cleanup_discard (%h)\n  fault \"detached\"",
        "%gone: unit = call.rt @msrt_cleanup_cancel (%h)\n  fault \"detached\"",
        "%fresh: str = copy %s\n  put %slot, %fresh\n  fault \"replaced\"",
    ] {
        let m = snapshot_branch_transition(transition);
        assert_eq!(
            block_registrations(&m, "probe"),
            [1, 0, 1],
            "{}",
            print_module(&m)
        );
    }
    let m = snapshot_branch_transition(
        "%gone: unit = call.rt @msrt_cleanup_discard (%h)\n  %r2: int = call.rt @msrt_task_sleep (%n)\n  fault \"detached\"",
    );
    assert_eq!(
        block_registrations(&m, "probe"),
        [1, 0, 2],
        "{}",
        print_module(&m)
    );
}

#[test]
fn uncertain_and_executed_scope_cleanup_preserve_existing_snapshot_suppression() {
    for transition in [
        "fault \"protected\"",
        "%nil: int = iconst 0\n  %unknown: unit = call.rt @msrt_cleanup_cancel (%nil)\n  fault \"unknown\"",
        "cleanup.run %h\n  fault \"already dropped\"",
    ] {
        let m = snapshot_branch_transition(transition);
        assert_eq!(
            block_registrations(&m, "probe"),
            [1, 0, 0],
            "{}",
            print_module(&m)
        );
    }
    let m = snapshot_branch_transition(
        "br_if %other, b3(), b4()\nb3():\n  %gone: unit = call.rt @msrt_cleanup_discard (%h)\n  br b5()\nb4():\n  br b5()\nb5():\n  fault \"mixed\"",
    );
    assert_eq!(
        block_registrations(&m, "probe"),
        [1, 0, 0, 0, 0, 0],
        "{}",
        print_module(&m)
    );
}

#[test]
fn independent_snapshot_ownership_at_a_join_requires_detachment_on_both_paths() {
    let m = snapshot_branch_transition(
        "br_if %other, b3(), b4()\nb3():\n  %gone3: unit = call.rt @msrt_cleanup_discard (%h)\n  br b5()\nb4():\n  %gone4: unit = call.rt @msrt_cleanup_cancel (%h)\n  br b5()\nb5():\n  fault \"detached on both paths\"",
    );
    assert_eq!(
        block_registrations(&m, "probe"),
        [1, 0, 0, 0, 0, 1],
        "{}",
        print_module(&m)
    );
}

#[test]
fn new_scope_owner_can_reown_released_but_not_overwritten_snapshot_data() {
    let m = snapshot_branch_transition(
        "%gone: unit = call.rt @msrt_cleanup_discard (%h)\n  %new: int = cleanup.push @close_slot %slot\n  fault \"owned again\"",
    );
    assert_eq!(
        block_registrations(&m, "probe"),
        [1, 0, 1],
        "{}",
        print_module(&m)
    );
    let m = snapshot_branch_transition(
        "%gone: unit = call.rt @msrt_cleanup_discard (%h)\n  %fresh: str = copy %s\n  put %slot, %fresh\n  %new: int = cleanup.push @close_slot %slot\n  fault \"old snapshot independent\"",
    );
    assert_eq!(
        block_registrations(&m, "probe"),
        [1, 0, 2],
        "{}",
        print_module(&m)
    );
}

#[test]
fn released_snapshot_can_be_reowned_then_become_independent_again() {
    let m = snapshot_branch_transition(
        "%gone: unit = call.rt @msrt_cleanup_discard (%h)\n  %new: int = cleanup.push @close_slot %slot\n  %gone2: unit = call.rt @msrt_cleanup_discard (%new)\n  fault \"independent again\"",
    );
    assert_eq!(
        block_registrations(&m, "probe"),
        [1, 0, 2],
        "{}",
        print_module(&m)
    );
}

#[test]
fn a_fault_after_scope_discard_keeps_a_taken_value_owned_on_that_branch() {
    let body = format!(
        r#"
extern @msrt_cleanup_discard(int) -> unit
{SLOT_CLOSE}
fn @subject(%choose: bool) -> int {{
b0:
  %s: str = str "held"
  %t: str = copy %s
  %slot: ptr = slot str
  put %slot, %t
  %h: int = cleanup.push @close_slot %slot
  %v: str = take str %slot
  br_if %choose, b1(), b2()
b1():
  put %slot, %v
  %back: str = take str %slot
  drop %back
  %z: int = iconst 0
  ret %z
b2():
  %gone: unit = call.rt @msrt_cleanup_discard (%h)
  fault "stopped"
}}
fn @main() -> int {{
b0:
  %choose: bool = bconst false
  %result: int = call @subject (%choose)
  ret %result
}}
"#
    );
    let (m, _) = rewrite(&body, true);
    // A putback on the other branch cannot cover this branch's live value after discard.
    assert_eq!(
        count(&m, "subject", Op::CleanupPush),
        2,
        "{}",
        print_module(&m)
    );
}

fn slot_with_native_result(result_type: &str, materialize: bool) -> Module {
    let (return_type, finish) = if materialize {
        (
            "int",
            "%label: str = copy %literal\n  %record: Materialized = rec.new Materialized %label, %derived\n  drop %record\n  %zero: int = iconst 0\n  put %slot, %held\n  ret %zero".to_string(),
        )
    } else {
        (result_type, "put %slot, %held\n  ret %derived".to_string())
    };
    let body = format!(
        r#"
record Position {{ offset: int, line: int, column: int }}
record PointerPosition {{ pointer: ptr, offset: int }}
record Materialized {{ label: str, position: Position }}
extern @native_derive(str) -> {result_type}
fn @hold(%slot: ptr) -> {return_type} {{
b0:
  %held: str = take str %slot
  %derived: {result_type} = call.rt @native_derive (%held)
  %literal: str = str "owned payload"
  %n: int = iconst 5
  %sleep: int = call.rt @msrt_task_sleep (%n)
  {finish}
}}
fn @main() -> int {{
b0:
  %literal: str = str "slot payload"
  %value: str = copy %literal
  %slot: ptr = slot str
  put %slot, %value
  %result: {return_type} = call @hold (%slot)
  %back: str = take str %slot
  drop %back
  %zero: int = iconst 0
  ret %zero
}}
"#
    );
    rewrite(&body, true).0
}

#[test]
fn native_plain_position_materialization_preserves_caller_slot_coverage() {
    let m = slot_with_native_result("Position", true);
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
}

#[test]
fn returning_native_plain_position_does_not_escape_the_slot_owner() {
    for result_type in ["Position", "int"] {
        let m = slot_with_native_result(result_type, false);
        assert_eq!(
            count(&m, "main", Op::CleanupPush),
            1,
            "type={result_type}\n{}",
            print_module(&m)
        );
    }
}

#[test]
fn returned_raw_or_nested_pointers_still_escape_the_slot_owner() {
    for result_type in ["ptr", "PointerPosition", "opt<ptr>"] {
        let m = slot_with_native_result(result_type, false);
        assert_eq!(
            count(&m, "main", Op::CleanupPush),
            0,
            "type={result_type}\n{}",
            print_module(&m)
        );
    }
}

const MUTABLE_RESOURCE: &str = r#"
record Resource { payload: str, closed: bool }
fn @close_resource(%slot: ptr) -> unit {
b0:
  %held: Resource = load Resource %slot
  %u: unit = unit
  ret %u
}
fn @hold_resource(%slot: ptr) -> int {
b0:
  %held: Resource = take Resource %slot
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %held
  ret %r
}
"#;

fn resource_mutation(mutate: &str, before_discard: &str, after_discard: &str) -> Module {
    let body = format!(
        r#"
extern @msrt_cleanup_discard(int) -> unit
{MUTABLE_RESOURCE}
{mutate}
fn @main() -> int {{
b0:
  %literal: str = str "resource"
  %payload: str = copy %literal
  %closed: bool = bconst false
  %resource: Resource = rec.new Resource %payload, %closed
  %slot: ptr = slot Resource
  put %slot, %resource
  %h: int = cleanup.push @close_resource %slot
  {before_discard}
  %gone: unit = call.rt @msrt_cleanup_discard (%h)
  {after_discard}
  %back: Resource = take Resource %slot
  drop %back
  %zero: int = iconst 0
  ret %zero
}}
"#
    );
    rewrite(&body, true).0
}

const REPLACE_RESOURCE: &str = r#"
fn @replace_resource(%slot: ptr) -> unit {
b0:
  %held: Resource = take Resource %slot
  %literal: str = str "replacement"
  %replacement: str = copy %literal
  %updated: Resource = rec.set Resource.payload %held, %replacement
  put %slot, %updated
  %u: unit = unit
  ret %u
}
"#;

#[test]
fn scalar_record_update_keeps_resource_identity_across_a_faulting_call() {
    let mutate = r#"
fn @mark_closed(%slot: ptr) -> int {
b0:
  %held: Resource = take Resource %slot
  %closed: bool = bconst true
  %updated: Resource = rec.set Resource.closed %held, %closed
  put %slot, %updated
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  ret %r
}
"#;
    let m = resource_mutation(mutate, "", "%r: int = call @mark_closed (%slot)");
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        2,
        "{}",
        print_module(&m)
    );
    assert_eq!(count(&m, "main", Op::Load), 1, "{}", print_module(&m));
}

#[test]
fn restored_owned_field_mutation_allows_a_later_scope_free_snapshot() {
    let m = resource_mutation(
        REPLACE_RESOURCE,
        "%changed: unit = call @replace_resource (%slot)",
        "%r: int = call @hold_resource (%slot)",
    );
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        2,
        "{}",
        print_module(&m)
    );
    assert_eq!(count(&m, "main", Op::Load), 1, "{}", print_module(&m));
}

#[test]
fn missing_or_conditional_owned_field_putback_cannot_certify_a_local_slot() {
    for finish in [
        "drop %updated\n  %u: unit = unit\n  ret %u",
        "br_if %choose, b1(), b2()\nb1():\n  put %slot, %updated\n  %u1: unit = unit\n  ret %u1\nb2():\n  drop %updated\n  %u2: unit = unit\n  ret %u2",
    ] {
        let mutate = format!(
            r#"
fn @replace_resource(%slot: ptr, %choose: bool) -> unit {{
b0:
  %held: Resource = take Resource %slot
  %literal: str = str "replacement"
  %replacement: str = copy %literal
  %updated: Resource = rec.set Resource.payload %held, %replacement
  {finish}
}}
"#
        );
        let m = resource_mutation(
            &mutate,
            "%changed: unit = call @replace_resource (%slot, %closed)",
            "%r: int = call @hold_resource (%slot)",
        );
        assert_eq!(
            count(&m, "main", Op::CleanupPush),
            1,
            "{}",
            print_module(&m)
        );
        assert_eq!(count(&m, "main", Op::Load), 0, "{}", print_module(&m));
    }
}

#[test]
fn owned_field_mutator_is_not_covered_by_a_stale_cell_snapshot() {
    let mutate = REPLACE_RESOURCE.replace(
        "  %u: unit = unit\n  ret %u",
        "  %n: int = iconst 5\n  %r: int = call.rt @msrt_task_sleep (%n)\n  %u: unit = unit\n  ret %u",
    );
    let m = resource_mutation(
        &mutate,
        "",
        "%changed: unit = call @replace_resource (%slot)\n  %r: int = call @hold_resource (%slot)",
    );
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        2,
        "{}",
        print_module(&m)
    );
    assert_eq!(count(&m, "main", Op::Load), 1, "{}", print_module(&m));
    let f = &m.funcs[m.func_by_name("main").unwrap().index()];
    let insts = &f.blocks[0].insts;
    let replacement = insts
        .iter()
        .position(
            |i| matches!(i.imm, Imm::Func(g) if m.funcs[g.index()].name == "replace_resource"),
        )
        .unwrap();
    let snapshot = insts.iter().position(|i| i.op == Op::Load).unwrap();
    assert!(snapshot > replacement, "{}", print_module(&m));
}

#[test]
fn nonfaulting_owned_field_mutation_separates_snapshot_windows() {
    let m = resource_mutation(
        REPLACE_RESOURCE,
        "",
        "%first: int = call @hold_resource (%slot)\n  %changed: unit = call @replace_resource (%slot)\n  %second: int = call @hold_resource (%slot)",
    );
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        3,
        "{}",
        print_module(&m)
    );
    assert_eq!(count(&m, "main", Op::Load), 2, "{}", print_module(&m));
}

#[test]
fn an_earlier_callee_cannot_escape_a_later_scope_free_slot_snapshot() {
    let mutate = r#"
fn @escape_resource(%slot: ptr) -> ptr {
b0:
  ret %slot
}
"#;
    let m = resource_mutation(
        mutate,
        "%escaped: ptr = call @escape_resource (%slot)",
        "%r: int = call @hold_resource (%slot)",
    );
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
    assert_eq!(count(&m, "main", Op::Load), 0, "{}", print_module(&m));
}

#[test]
fn forwarding_an_owned_mutator_cannot_restore_an_old_taken_record() {
    let mutate = format!(
        r#"
{REPLACE_RESOURCE}
fn @restore_stale(%slot: ptr) -> unit {{
b0:
  %old: Resource = take Resource %slot
  %changed: unit = call @replace_resource (%slot)
  put %slot, %old
  %u: unit = unit
  ret %u
}}
"#
    );
    let m = resource_mutation(
        &mutate,
        "%changed: unit = call @restore_stale (%slot)",
        "%r: int = call @hold_resource (%slot)",
    );
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        1,
        "{}",
        print_module(&m)
    );
    assert_eq!(count(&m, "main", Op::Load), 0, "{}", print_module(&m));
}

#[test]
fn a_forwarder_without_a_taken_alias_can_restore_owned_field_mutations() {
    let mutate = format!(
        r#"
{REPLACE_RESOURCE}
fn @forward_replacement(%slot: ptr) -> unit {{
b0:
  %changed: unit = call @replace_resource (%slot)
  ret %changed
}}
"#
    );
    let m = resource_mutation(
        &mutate,
        "%changed: unit = call @forward_replacement (%slot)",
        "%r: int = call @hold_resource (%slot)",
    );
    assert_eq!(
        count(&m, "main", Op::CleanupPush),
        2,
        "{}",
        print_module(&m)
    );
    assert_eq!(count(&m, "main", Op::Load), 1, "{}", print_module(&m));
}

#[test]
fn a_scalar_updated_record_held_across_a_call_has_only_one_drop_owner() {
    let mutate = r#"
fn @mark_closed(%slot: ptr) -> int {
b0:
  %held: Resource = take Resource %slot
  %closed: bool = bconst true
  %updated: Resource = rec.set Resource.closed %held, %closed
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  put %slot, %updated
  ret %r
}
"#;
    let m = resource_mutation(mutate, "", "%r: int = call @mark_closed (%slot)");
    // The updated SSA record already receives a callee unwind drop. The caller must
    // not independently register the same resource leaves through the old slot bits.
    assert_eq!(
        count(&m, "mark_closed", Op::CleanupPush),
        1,
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
fn a_guard_held_update_changes_drop_ownership_but_an_ordinary_flag_does_not() {
    let body = r#"
record Guard { box: int, value: str, held: bool }
extern @msrt_cleanup_discard(int) -> unit
fn @close_guard(%slot: ptr) -> unit {
b0:
  %guard: Guard = load Guard %slot
  %u: unit = unit
  ret %u
}
fn @release_guard(%slot: ptr) -> int {
b0:
  %guard: Guard = take Guard %slot
  %released: bool = bconst false
  %updated: Guard = rec.set Guard.held %guard, %released
  put %slot, %updated
  %n: int = iconst 5
  %r: int = call.rt @msrt_task_sleep (%n)
  ret %r
}
fn @main() -> int {
b0:
  %literal: str = str "guard payload"
  %payload: str = copy %literal
  %box: int = iconst 0
  %held: bool = bconst true
  %guard: Guard = rec.new Guard %box, %payload, %held
  %slot: ptr = slot Guard
  put %slot, %guard
  %h: int = cleanup.push @close_guard %slot
  %gone: unit = call.rt @msrt_cleanup_discard (%h)
  %r: int = call @release_guard (%slot)
  %back: Guard = take Guard %slot
  drop %back
  ret %r
}
"#;
    for (record_name, expected) in [("Guard", 2), ("SharedGuard[String]", 1)] {
        let mut m = module(body, true);
        // Generic instantiated names are recorded after parsing. Match the backend's
        // existing SharedGuard shape without requiring that spelling in the MIR grammar.
        let guard = m.record_by_name("Guard").unwrap();
        m.records[guard.index()].name = record_name.to_owned();
        verify_module(&m).unwrap();
        unwind::run(&mut m);
        verify_module(&m).unwrap_or_else(|e| panic!("{e:?}\n{}", print_module(&m)));
        // An old true flag must not cause the caller to drop a payload that the
        // released guard's false flag no longer owns. An ordinary flag has no such role.
        assert_eq!(
            count(&m, "main", Op::CleanupPush),
            expected,
            "record={record_name}\n{}",
            print_module(&m)
        );
        assert_eq!(
            count(&m, "release_guard", Op::CleanupPush),
            0,
            "{}",
            print_module(&m)
        );
    }
}
