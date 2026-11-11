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
