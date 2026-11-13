//! Stage 0 of `proposals/elaborate-drops.md`: hand-written Raw MIR (markers, no scope-end
//! drops) elaborated by `ms_mir::elaborate`, then verified and run. The oracle is the verifier
//! on the output and the order of the closes the program prints.

use ms_mir::interp::Interp;
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

const HEAD: &str = r#"module "raw"
alt Msg { Pair(a: list<int>, b: list<int>), Empty }
extern @msrt_print_int(int)
entry @main
fn @mk(%id: int) -> list<int> {
b0:
  %cap: int = iconst 0
  %l0: list<int> = list.new %cap
  %l: list<int> = list.push %l0, %id
  ret %l
}
fn @close(%r: move list<int>) -> int {
b0:
  %z: int = iconst 0
  %id: int = list.get %r, %z
  %u: unit = call.rt @msrt_print_int (%id)
  drop %r
  ret %id
}
"#;

/// Elaborates and runs `body` (functions and `main`), returning the exit value and output. A
/// discarded cleanup entry prints `~`, so the output shows where the entries retire.
fn elaborate_and_run(body: &str) -> (i64, String) {
    let (r, out, _) = elaborate_and_run_text(body);
    (r, out)
}

/// The same, with the elaborated module's text.
fn elaborate_and_run_text(body: &str) -> (i64, String, String) {
    let mut m = parse_module(&format!("{HEAD}{body}")).unwrap_or_else(|e| panic!("{e}"));
    ms_mir::elaborate::run(&mut m).unwrap_or_else(|e| panic!("{e}"));
    let text = print_module(&m);
    if let Err(e) = verify_module(&m) {
        panic!("{e:?}\n{text}");
    }
    let mut it = Interp::new(&m);
    it.register("msrt_cleanup_discard", |out, _| {
        out.push_str("~\n");
        Ok(ms_mir::interp::Val::Unit)
    });
    it.register("msrt_cleanup_cancel", |out, _| {
        out.push_str("x\n");
        Ok(ms_mir::interp::Val::Unit)
    });
    for name in ["msrt_shield_enter", "msrt_shield_exit"] {
        it.register(name, |_, _| Ok(ms_mir::interp::Val::Unit));
    }
    let r = it.run_entry().unwrap_or_else(|f| panic!("{f}"));
    (r, it.stdout().to_string(), text)
}

/// Two nested closing resources; closes print their id and fail when it is nonzero.
fn nested(n1: i64, n2: i64) -> String {
    format!(
        r#"fn @f(%n1: int, %n2: int) -> int {{
b0:
  scope.begin 1 0
  %a: list<int> = call @mk (%n1)
  scope.own 1 1 %a
  scope.begin 2 2
  %b: list<int> = call @mk (%n2)
  scope.own 2 1 %b
  %r: int = iconst 7
  scope.end 2 0
  scope.end 1 0
  ret %r
}}
fn @main() -> int {{
b0:
  %x: int = iconst {n1}
  %y: int = iconst {n2}
  %r: int = call @f (%x, %y)
  ret %r
}}
"#
    )
}

#[test]
fn nested_closes_run_inner_first_and_the_first_error_wins() {
    // (outer id, inner id) -> (result, close order)
    assert_eq!(elaborate_and_run(&nested(0, 0)), (7, "~\n0\n~\n0\n".into()));
    assert_eq!(elaborate_and_run(&nested(3, 0)), (3, "~\n0\n~\n3\n".into()));
    assert_eq!(elaborate_and_run(&nested(0, 4)), (4, "~\n4\n~\n0\n".into()));
    assert_eq!(elaborate_and_run(&nested(3, 4)), (4, "~\n4\n~\n3\n".into()));
}

/// An arm that consumes the scrutinee leaves nothing to close; the other arm closes it. No
/// "already closed on this path" state: the live set decides.
fn arms(flag: i64) -> String {
    format!(
        r#"fn @g(%flag: int) -> int {{
b0:
  %zero: int = iconst 0
  %one: int = iconst 1
  scope.begin 1 0
  %a: list<int> = call @mk (%flag)
  scope.own 1 1 %a
  %c: bool = icmp.eq %flag, %zero
  br_if %c, take(), keep()
take:
  %x: list<int> = list.push %a, %one
  drop %x
  %r10: int = iconst 10
  scope.end 1 0
  ret %r10
keep:
  %r20: int = iconst 20
  scope.end 1 0
  ret %r20
}}
fn @main() -> int {{
b0:
  %x: int = iconst {flag}
  %r: int = call @g (%x)
  ret %r
}}
"#
    )
}

#[test]
fn an_arm_that_consumed_the_value_is_not_closed_again() {
    // The move retires the cleanup entry (`~`); nothing closes afterwards.
    assert_eq!(elaborate_and_run(&arms(0)), (10, "~\n".into()));
    assert_eq!(elaborate_and_run(&arms(5)), (5, "~\n5\n".into()));
}

/// An owner (`kind` 0 drops, 1 closes) moved on one branch and kept on the other, then a join
/// where the scope ends: the owner is `MaybeMoved`, so it gets a drop flag.
fn joined(flag: i64, kind: i64) -> String {
    format!(
        r#"fn @h(%flag: int) -> int {{
b0:
  %zero: int = iconst 0
  %one: int = iconst 1
  scope.begin 1 0
  %a: list<int> = call @mk (%flag)
  scope.own 1 {kind} %a
  %c: bool = icmp.eq %flag, %zero
  br_if %c, take(), keep()
take:
  %x: list<int> = list.push %a, %one
  drop %x
  br join()
keep:
  br join()
join:
  %r: int = iconst 10
  scope.end 1 0
  ret %r
}}
fn @main() -> int {{
b0:
  %x: int = iconst {flag}
  %r: int = call @h (%x)
  ret %r
}}
"#
    )
}

#[test]
fn an_owner_moved_on_one_branch_is_closed_only_when_live() {
    // Moved on the `flag == 0` branch: nothing closes. Kept: closes at the join, and the
    // close error (the id) wins as the result.
    let (r, out, text) = elaborate_and_run_text(&joined(0, 1));
    assert_eq!((r, out.as_str()), (10, "~\n"));
    assert!(text.contains("move.out"), "{text}");
    assert_eq!(elaborate_and_run(&joined(5, 1)), (5, "~\n5\n".into()));
}

#[test]
fn a_dropped_owner_moved_on_one_branch_drops_through_its_flag() {
    let (_, _, text) = elaborate_and_run_text(&joined(0, 0));
    assert!(text.contains("drop.if"), "{text}");
    let (_, _, text) = elaborate_and_run_text(&joined(5, 0));
    assert!(text.contains("drop.if"), "{text}");
}

/// An owner declared before a loop; each iteration opens a resource in its own scope, and
/// iteration `stop` leaves the loop. `break` and `continue` end the iteration scope first.
fn looped(stop: i64) -> String {
    format!(
        r#"fn @lp(%stop: int) -> int {{
b0:
  %zero: int = iconst 0
  scope.begin 1 0
  %a: list<int> = call @mk (%zero)
  scope.own 1 1 %a
  br loop(%zero)
loop(%i: int):
  %three: int = iconst 3
  %more: bool = icmp.lt %i, %three
  br_if %more, body(), done()
body:
  scope.begin 2 2
  %b: list<int> = call @mk (%zero)
  scope.own 2 1 %b
  %hit: bool = icmp.eq %i, %stop
  br_if %hit, leave(), next()
leave:
  scope.end 2 0
  br done()
next:
  scope.end 2 0
  %one: int = iconst 1
  %j: int = iadd %i, %one
  br loop(%j)
done:
  %r: int = iconst 9
  scope.end 1 0
  ret %r
}}
fn @main() -> int {{
b0:
  %x: int = iconst {stop}
  %r: int = call @lp (%x)
  ret %r
}}
"#
    )
}

#[test]
fn loop_scopes_close_per_iteration_and_break_leaves_the_iteration_scope() {
    let pair = "~\n0\n";
    // Three iterations close their resource, then the outer owner closes once.
    assert_eq!(elaborate_and_run(&looped(7)), (9, pair.repeat(4)));
    // Leaving at iteration 1: two iteration closes, then the outer one.
    assert_eq!(elaborate_and_run(&looped(1)), (9, pair.repeat(3)));
    assert_eq!(elaborate_and_run(&looped(0)), (9, pair.repeat(2)));
}

/// The outer owner is moved on the iteration that breaks: the exit joins a path where it is
/// gone with the path where the loop ran out, so it is flagged.
fn moved_then_break(stop: i64) -> String {
    format!(
        r#"fn @mb(%stop: int) -> int {{
b0:
  %zero: int = iconst 0
  scope.begin 1 0
  %a: list<int> = call @mk (%zero)
  scope.own 1 1 %a
  br loop(%zero)
loop(%i: int):
  %three: int = iconst 3
  %more: bool = icmp.lt %i, %three
  br_if %more, body(), done()
body:
  %hit: bool = icmp.eq %i, %stop
  br_if %hit, take(), next()
take:
  %one: int = iconst 1
  %x: list<int> = list.push %a, %one
  drop %x
  br done()
next:
  %one2: int = iconst 1
  %j: int = iadd %i, %one2
  br loop(%j)
done:
  %r: int = iconst 9
  scope.end 1 0
  ret %r
}}
fn @main() -> int {{
b0:
  %x: int = iconst {stop}
  %r: int = call @mb (%x)
  ret %r
}}
"#
    )
}

#[test]
fn an_owner_moved_in_a_loop_before_break_is_closed_only_when_kept() {
    assert_eq!(elaborate_and_run(&moved_then_break(1)), (9, "~\n".into()));
    assert_eq!(
        elaborate_and_run(&moved_then_break(7)),
        (9, "~\n0\n".into())
    );
}

/// An arm takes one payload field out of an owned alternative; the scope end releases the rest.
fn partial(empty: bool) -> String {
    let make = if empty {
        "drop %p\n  drop %q\n  %m: Msg = alt.new Msg.Empty"
    } else {
        "%m: Msg = alt.new Msg.Pair %p, %q"
    };
    let take = if empty {
        ""
    } else {
        "%t: list<int> = alt.take Msg.Pair.a %m\n  drop %t"
    };
    format!(
        r#"fn @pm() -> int {{
b0:
  %zero: int = iconst 0
  scope.begin 1 0
  %p: list<int> = call @mk (%zero)
  %q: list<int> = call @mk (%zero)
  {make}
  scope.own 1 0 %m
  {take}
  %r: int = iconst 4
  scope.end 1 0
  ret %r
}}
fn @main() -> int {{
b0:
  %r: int = call @pm ()
  ret %r
}}
"#
    )
}

#[test]
fn a_taken_payload_is_released_with_alt_release_and_otherwise_dropped() {
    let (r, _, text) = elaborate_and_run_text(&partial(false));
    assert_eq!(r, 4);
    assert!(text.contains("alt.release Msg.Pair.a"), "{text}");
    let (_, _, text) = elaborate_and_run_text(&partial(true));
    assert!(!text.contains("alt.release"), "{text}");
}

#[test]
fn unsupported_shapes_are_reported_not_miscompiled() {
    // Consuming an owner that an earlier iteration may have moved.
    let src = moved_then_break(1).replace("br done()\nnext:", "br loop(%i)\nnext:");
    let mut m = parse_module(&format!("{HEAD}{src}")).unwrap();
    let e = ms_mir::elaborate::run(&mut m).unwrap_err();
    assert!(e.contains("moved"), "{e}");
}

#[test]
fn markers_round_trip_and_raw_ownership_is_checked_only_after_elaboration() {
    let mut m = parse_module(&format!("{HEAD}{}", nested(0, 0))).expect("parse");
    let text = print_module(&m);
    assert!(text.contains("scope.own 2 1 %"), "{text}");
    let again = parse_module(&text).expect("reparse");
    assert_eq!(print_module(&again), text);
    // Raw: the owners are live at `ret`, which only an elaborated function may not do.
    verify_module(&m).expect("raw verifies");
    ms_mir::elaborate::run(&mut m).expect("elaborate");
    assert!(!print_module(&m).contains("scope."));
    verify_module(&m).expect("elaborated verifies");
}

#[test]
fn a_disowned_value_is_not_dropped_at_the_scope_end() {
    let (kept, out) = elaborate_and_run(
        r#"fn @h() -> int {
b0:
  %n: int = iconst 4
  scope.begin 1 0
  %a: list<int> = call @mk (%n)
  scope.own 1 0 %a
  %z: int = iconst 0
  %v: int = list.get %a, %z
  scope.disown %a
  drop %a
  scope.end 1 0
  ret %v
}
fn @main() -> int {
b0:
  %r: int = call @h ()
  ret %r
}
"#,
    );
    assert_eq!((kept, out.as_str()), (4, ""));
}

/// A value moved out of its scope on one branch and owned there by an inner scope (a statement's
/// temporary), which drops it: the other branch still holds it in the outer scope.
fn reowned(flag: i64) -> String {
    format!(
        r#"fn @h(%flag: int) -> int {{
b0:
  %zero: int = iconst 0
  scope.begin 1 0
  %a: list<int> = call @mk (%flag)
  scope.own 1 0 %a
  %c: bool = icmp.eq %flag, %zero
  br_if %c, take(), keep()
take:
  scope.disown %a
  scope.begin 2 2
  scope.own 2 0 %a
  drop %a
  scope.end 2 0
  br join()
keep:
  br join()
join:
  %r: int = iconst 10
  scope.end 1 0
  ret %r
}}
fn @main() -> int {{
b0:
  %x: int = iconst {flag}
  %r: int = call @h (%x)
  ret %r
}}
"#
    )
}

#[test]
fn a_value_an_inner_scope_owns_again_stays_the_outer_scopes_on_the_other_path() {
    for flag in [0, 5] {
        let (r, _, text) = elaborate_and_run_text(&reowned(flag));
        assert_eq!(r, 10, "{text}");
        assert!(text.contains("drop.if"), "{text}");
    }
}

/// An owner whose close cannot fail names its own function (`scope.own S K v`, K = function
/// index + 2): the pass closes it shielded and drops what is left, only on the paths that
/// still hold it.
fn infallible(keep: bool) -> String {
    format!(
        r#"fn @shut(%r: list<int>) -> unit {{
b0:
  %z: int = iconst 0
  %id: int = list.get %r, %z
  %u: unit = call.rt @msrt_print_int (%id)
  ret %u
}}
fn @sink(%r: move list<int>) -> unit {{
b0:
  drop %r
  %u: unit = unit
  ret %u
}}
fn @main() -> int {{
b0:
  scope.begin 1 0
  %n: int = iconst 7
  %a: list<int> = call @mk (%n)
  scope.own 1 4 %a
  %k: bool = bconst {keep}
  br_if %k, b1(), b2()
b1():
  br b3()
b2():
  %u: unit = call @sink (%a)
  br b3()
b3():
  scope.end 1 0
  %r: int = iconst 0
  ret %r
}}
"#
    )
}

#[test]
fn an_infallible_owner_is_closed_shielded_only_where_it_is_still_held() {
    let (_, out, text) = elaborate_and_run_text(&infallible(true));
    assert_eq!(out, "~\n7\n", "{text}");
    assert!(text.contains("msrt_shield_enter"), "{text}");
    let (_, out, _) = elaborate_and_run_text(&infallible(false));
    assert_eq!(out, "~\n", "a moved owner is not closed");
}

/// A resource that lives in memory is owned by its slot's address: the close function takes the
/// address, and the pass closes it shielded at the scope end.
#[test]
fn a_memory_slot_owner_is_closed_in_place_at_the_scope_end() {
    let (_, out, text) = elaborate_and_run_text(
        r#"fn @shut(%p: ptr) -> unit {
b0:
  %r: list<int> = load list<int> %p
  %z: int = iconst 0
  %id: int = list.get %r, %z
  %u: unit = call.rt @msrt_print_int (%id)
  ret %u
}
fn @main() -> int {
b0:
  scope.begin 1 0
  %n: int = iconst 7
  %a: list<int> = call @mk (%n)
  %s: ptr = slot list<int>
  put %s, %a
  scope.own 1 4 %s
  scope.end 1 0
  %r: int = iconst 0
  ret %r
}
"#,
    );
    assert_eq!(out, "~\n7\n", "{text}");
    assert!(text.contains("msrt_shield_enter"), "{text}");
}

/// A slot owner whose value moves out on one branch: that path cancels its entry and closes
/// nothing, the other closes it in place; the entry leaves the stack at the scope end either way.
#[test]
fn a_conditionally_moved_slot_owner_closes_only_where_it_still_holds_the_value() {
    for (cond, want) in [(1, "x\n~\n"), (0, "~\n7\n")] {
        let (_, out, text) = elaborate_and_run_text(&format!(
            r#"fn @shut(%p: ptr) -> unit {{
b0:
  %r: list<int> = load list<int> %p
  %z: int = iconst 0
  %id: int = list.get %r, %z
  %u: unit = call.rt @msrt_print_int (%id)
  ret %u
}}
fn @main() -> int {{
b0:
  scope.begin 1 0
  %n: int = iconst 7
  %a: list<int> = call @mk (%n)
  %s: ptr = slot list<int>
  put %s, %a
  scope.own 1 4 %s
  %k: int = iconst {cond}
  %one: int = iconst 1
  %c: bool = icmp.eq %k, %one
  br_if %c, b1(), b2()
b1():
  %t: list<int> = take list<int> %s
  scope.disown %s
  drop %t
  br b3()
b2():
  br b3()
b3():
  scope.end 1 0
  %r: int = iconst 0
  ret %r
}}
"#
        ));
        assert_eq!(out, want, "cond {cond}\n{text}");
    }
}

/// A slot owner whose value moves out on one branch and is then refilled: the path that kept
/// the value closes it before the store, the path that moved it registers a new entry, and the
/// scope end closes the new value.
#[test]
fn a_refilled_slot_owner_is_closed_again_at_the_scope_end() {
    for (cond, want) in [(1, "x\n~\n9\n"), (0, "7\n~\n9\n")] {
        let (_, out, text) = elaborate_and_run_text(&format!(
            r#"fn @shut(%p: ptr) -> unit {{
b0:
  %r: list<int> = load list<int> %p
  %z: int = iconst 0
  %id: int = list.get %r, %z
  %u: unit = call.rt @msrt_print_int (%id)
  ret %u
}}
fn @main() -> int {{
b0:
  scope.begin 1 0
  %n: int = iconst 7
  %a: list<int> = call @mk (%n)
  %s: ptr = slot list<int>
  put %s, %a
  scope.own 1 4 %s
  %k: int = iconst {cond}
  %one: int = iconst 1
  %c: bool = icmp.eq %k, %one
  br_if %c, b1(), b2()
b1():
  %t: list<int> = take list<int> %s
  scope.disown %s
  drop %t
  br b3()
b2():
  br b3()
b3():
  scope.mark 2 %s
  %m: int = iconst 9
  %b: list<int> = call @mk (%m)
  put %s, %b
  scope.end 1 0
  %r: int = iconst 0
  ret %r
}}
"#
        ));
        assert_eq!(out, want, "cond {cond}\n{text}");
    }
}

/// A slot owner the program closes by hand on one branch: `scope.mark` types it, the join
/// carries a flag, and the scope end still releases the owner on both paths.
#[test]
fn a_slot_owner_closed_by_hand_on_some_paths_is_still_released_at_the_scope_end() {
    for (cond, want) in [(1, "7\n~\n7\n"), (0, "~\n7\n")] {
        let (_, out, text) = elaborate_and_run_text(&format!(
            r#"fn @shut(%p: ptr) -> unit {{
b0:
  %r: list<int> = load list<int> %p
  %z: int = iconst 0
  %id: int = list.get %r, %z
  %u: unit = call.rt @msrt_print_int (%id)
  ret %u
}}
fn @main() -> int {{
b0:
  scope.begin 1 0
  %n: int = iconst 7
  %a: list<int> = call @mk (%n)
  %s: ptr = slot list<int>
  put %s, %a
  scope.own 1 4 %s
  %k: int = iconst {cond}
  %one: int = iconst 1
  %c: bool = icmp.eq %k, %one
  br_if %c, b1(), b2()
b1():
  %u: unit = call @shut (%s)
  scope.mark 1 %s
  br b3()
b2():
  br b3()
b3():
  scope.end 1 0
  %r: int = iconst 0
  ret %r
}}
"#
        ));
        assert_eq!(out, want, "cond {cond}\n{text}");
    }
}

/// A slot owner the program closes by hand on one branch and moves out of on the other: the
/// join carries a drop flag and a closed flag, and only the hand-closed path closes it again.
#[test]
fn a_slot_owner_closed_by_hand_on_one_path_and_moved_on_another_is_released_once() {
    for (cond, want) in [(1, "7\n~\n7\n"), (0, "x\n~\n")] {
        let (_, out, text) = elaborate_and_run_text(&format!(
            r#"fn @shut(%p: ptr) -> unit {{
b0:
  %r: list<int> = load list<int> %p
  %z: int = iconst 0
  %id: int = list.get %r, %z
  %u: unit = call.rt @msrt_print_int (%id)
  ret %u
}}
fn @main() -> int {{
b0:
  scope.begin 1 0
  %n: int = iconst 7
  %a: list<int> = call @mk (%n)
  %s: ptr = slot list<int>
  put %s, %a
  scope.own 1 4 %s
  %k: int = iconst {cond}
  %one: int = iconst 1
  %c: bool = icmp.eq %k, %one
  br_if %c, b1(), b2()
b1():
  %u: unit = call @shut (%s)
  scope.mark 1 %s
  br b3()
b2():
  %t: list<int> = take list<int> %s
  scope.disown %s
  drop %t
  br b3()
b3():
  scope.end 1 0
  %r: int = iconst 0
  ret %r
}}
"#
        ));
        assert_eq!(out, want, "cond {cond}\n{text}");
    }
}

/// A slot owner handed on to the enclosing scope (a pending temporary that outlives the scope it
/// was made in): the exit before the hand-over uses the entry registered first, the scope end
/// after it the entry registered again, and the value closes once.
#[test]
fn a_slot_owner_handed_to_the_enclosing_scope_is_closed_once_on_every_path() {
    for (cond, want) in [(1, "~\n7\n"), (0, "x\n~\n7\n")] {
        let (_, out, text) = elaborate_and_run_text(&format!(
            r#"fn @shut(%p: ptr) -> unit {{
b0:
  %r: list<int> = load list<int> %p
  %z: int = iconst 0
  %id: int = list.get %r, %z
  %u: unit = call.rt @msrt_print_int (%id)
  ret %u
}}
fn @main() -> int {{
b0:
  scope.begin 1 0
  scope.begin 2 1
  %n: int = iconst 7
  %a: list<int> = call @mk (%n)
  %s: ptr = slot list<int>
  put %s, %a
  scope.own 2 4 %s
  %k: int = iconst {cond}
  %one: int = iconst 1
  %c: bool = icmp.eq %k, %one
  br_if %c, b1(), b2()
b1():
  scope.end 2 0
  scope.end 1 0
  %e: int = iconst 1
  ret %e
b2():
  scope.disown %s
  scope.end 2 0
  scope.own 1 4 %s
  scope.end 1 0
  %r: int = iconst 0
  ret %r
}}
"#
        ));
        assert_eq!(out, want, "cond {cond}\n{text}");
    }
}

/// A memory-slot owner whose close returns a `Result`: the close runs shielded, its error becomes
/// the function's return value through the function's close exit, and a close that succeeds
/// leaves the normal return alone.
fn fallible(code: i64) -> String {
    format!(
        r#"alt Res {{ Ok(v: list<int>), Error(e: list<int>) }} result
fn @shutr(%p: ptr) -> Res {{
b0:
  %r: list<int> = load list<int> %p
  %z: int = iconst 0
  %id: int = list.get %r, %z
  %u: unit = call.rt @msrt_print_int (%id)
  %bad: bool = icmp.ne %id, %z
  br_if %bad, b1(), b2()
b1():
  %pe: list<int> = call @mk (%id)
  %e: Res = alt.new Res.Error %pe
  ret %e
b2():
  %po: list<int> = call @mk (%z)
  %o: Res = alt.new Res.Ok %po
  ret %o
}}
fn @thunk(%p: ptr) -> unit {{
b0:
  %u: unit = unit
  ret %u
}}
fn @exit0(%e: move Res) -> Res {{
b0:
  ret %e
}}
fn @exit1(%e: move Res, %p: move Res) -> Res {{
b0:
  drop %p
  ret %e
}}
fn @work() -> Res {{
b0:
  scope.begin 1 0
  %n: int = iconst {code}
  %a: list<int> = call @mk (%n)
  %s: ptr = slot list<int>
  put %s, %a
  scope.own 1 5 %s
  %z: int = iconst 0
  %pf: list<int> = call @mk (%z)
  %fine: Res = alt.new Res.Ok %pf
  scope.end 1 0
  ret %fine
}}
fn @main() -> int {{
b0:
  %r: Res = call @work ()
  %t: int = alt.tag %r
  %u: unit = call.rt @msrt_print_int (%t)
  drop %r
  %z: int = iconst 0
  ret %z
}}
"#
    )
}

#[test]
fn a_fallible_slot_close_returns_its_error_through_the_close_exit() {
    for (code, tag) in [(0, "0"), (7, "1")] {
        let mut m =
            parse_module(&format!("{HEAD}{}", fallible(code))).unwrap_or_else(|e| panic!("{e}"));
        let list = m.funcs[0].ret;
        m.funcs[3].slot_close = Some(list);
        m.funcs[3].slot_result = Some(ms_mir::ir::FuncId(2));
        m.funcs[6].close_exit = Some((ms_mir::ir::FuncId(4), ms_mir::ir::FuncId(5)));
        ms_mir::elaborate::run(&mut m).unwrap_or_else(|e| panic!("{e}"));
        let text = print_module(&m);
        if let Err(e) = verify_module(&m) {
            panic!("{e:?}\n{text}");
        }
        let mut it = Interp::new(&m);
        it.register("msrt_cleanup_discard", |_, _| Ok(ms_mir::interp::Val::Unit));
        for name in ["msrt_shield_enter", "msrt_shield_exit"] {
            it.register(name, |_, _| Ok(ms_mir::interp::Val::Unit));
        }
        it.run_entry().unwrap_or_else(|f| panic!("{f}"));
        let want = format!("{code}\n{tag}\n");
        assert_eq!(it.stdout(), want, "{text}");
    }
}

#[test]
fn a_value_disowned_before_a_loop_back_edge_does_not_make_the_parameter_an_owner() {
    // `%w` leaves its scope in b2 and reaches the back edge through b3: the loop parameter
    // `%v` is lowering's own, so its explicit drop is the only one.
    let (r, _) = elaborate_and_run(
        r#"
fn @main() -> int {
b0:
  %z: int = iconst 0
  %a: list<int> = call @mk (%z)
  br b1(%z, %a)
b1(%i: int, %v: move list<int>):
  %n: int = iconst 2
  %c: bool = icmp.lt %i, %n
  br_if %c, b2(), b4()
b2():
  %id: int = iconst 7
  %w: list<int> = call @mk (%id)
  scope.begin 0 0
  scope.own 0 0 %w
  scope.disown %w
  drop %v
  scope.end 0 0
  br b3()
b3():
  %one: int = iconst 1
  %j: int = iadd %i, %one
  br b1(%j, %w)
b4():
  drop %v
  %r: int = iconst 0
  ret %r
}
"#,
    );
    assert_eq!(r, 0);
}

#[test]
fn an_owner_disowned_before_its_consuming_call_is_not_released_on_a_later_exit() {
    // b1 moves `%a` into `@close` and may return at once; b2 only reads it. The exit in b1
    // must not release it again, and the join releases it only on the b2 path.
    for (arg, want) in [(0, "7\n"), (1, "")] {
        let (r, out) = elaborate_and_run(&format!(
            r#"
fn @main() -> int {{
b0:
  %id: int = iconst 7
  %a: list<int> = call @mk (%id)
  scope.begin 0 0
  scope.own 0 0 %a
  %z: int = iconst {arg}
  %zero: int = iconst 0
  %c: bool = icmp.eq %z, %zero
  br_if %c, b1(), b2()
b1():
  scope.disown %a
  %x: int = call @close (%a)
  %early: bool = icmp.eq %x, %id
  br_if %early, b3(), b5()
b2():
  %n: int = list.len %a
  br b5()
b3():
  scope.end 0 0
  ret %x
b5():
  scope.end 0 0
  %r: int = iconst 0
  ret %r
}}
"#
        ));
        assert_eq!((r, out.as_str()), (if arg == 0 { 7 } else { 0 }, want));
    }
}
