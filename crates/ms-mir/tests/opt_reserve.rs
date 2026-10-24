//! Tests for the `reserve` pass: lists filled by counted loops are allocated at their
//! final size, behavior is unchanged, and loops that may push fewer items keep the literal.

use ms_mir::interp::Interp;
use ms_mir::ir::Module;
use ms_mir::opt::{self, Level, reserve};
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::verify::verify_module;

fn parse(src: &str) -> Module {
    let m = parse_module(src).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:?}"));
    m
}

fn exec(m: &Module) -> (Result<i64, String>, String) {
    let mut it = Interp::new(m);
    let r = it.run_entry().map_err(|f| f.to_string());
    (r, it.stdout().to_string())
}

/// Runs the pass on a module whose `@fill` builds a list of `n` items, checks the result
/// for several `n`, and returns the rewritten module.
fn rewrite(fill: &str) -> Module {
    let mut last = None;
    for n in [-3, 0, 1, 7] {
        let src = format!(
            "module \"reserve\"\nentry @main\n{fill}\nfn @main() -> int {{\nb0:\n  %n: int = iconst {n}\n  %l: list<int> = call @fill (%n)\n  %len: int = list.len %l\n  drop %l\n  ret %len\n}}\n"
        );
        let before = parse(&src);
        let mut after = before.clone();
        reserve::run(&mut after);
        verify_module(&after).unwrap_or_else(|e| panic!("{e:?}\n{}", print_module(&after)));
        assert_eq!(exec(&after), exec(&before), "{}", print_module(&after));
        let mut full = before.clone();
        opt::optimize(&mut full, Level::Speed, true);
        assert_eq!(exec(&full), exec(&before), "{}", print_module(&full));
        last = Some(after);
    }
    last.expect("ran")
}

fn count(m: &Module, mnemonic: &str) -> usize {
    print_module(m)
        .split_whitespace()
        .filter(|t| *t == mnemonic)
        .count()
}

#[test]
fn sizes_a_list_pushed_on_every_path_of_a_counted_loop() {
    let m = rewrite(
        "fn @fill(%n: int) -> list<int> {
b0:
  %l0: list<int> = list.lit
  %z: int = iconst 0
  %l1: list<int> = list.push %l0, %z
  br head(%z, %l1)
head(%i: int, %l: own list<int>):
  %len: int = list.len %l
  %c: bool = icmp.le %i, %n
  br_if %c, body(), out()
body():
  %two: int = iconst 2
  %r: int = srem %i, %two
  %even: bool = icmp.eq %r, %z
  br_if %even, a(), b()
a():
  %la: list<int> = list.push %l, %i
  br join(%la)
b():
  %lb: list<int> = list.push %l, %z
  %lc: list<int> = list.push %lb, %i
  br join(%lc)
join(%lj: own list<int>):
  %one: int = iconst 1
  %next: int = iadd %i, %one
  br head(%next, %lj)
out():
  ret %l
}",
    );
    assert_eq!(count(&m, "list.lit"), 0, "{}", print_module(&m));
    assert_eq!(count(&m, "list.new"), 1, "{}", print_module(&m));
}

#[test]
fn keeps_the_literal_when_a_loop_may_push_less() {
    // One path skips the push.
    let skip = rewrite(
        "fn @fill(%n: int) -> list<int> {
b0:
  %l0: list<int> = list.lit
  %z: int = iconst 0
  br head(%z, %l0)
head(%i: int, %l: own list<int>):
  %c: bool = icmp.lt %i, %n
  br_if %c, body(), out()
body():
  %three: int = iconst 3
  %small: bool = icmp.lt %i, %three
  br_if %small, a(), join(%l)
a():
  %la: list<int> = list.push %l, %i
  br join(%la)
join(%lj: own list<int>):
  %one: int = iconst 1
  %next: int = iadd %i, %one
  br head(%next, %lj)
out():
  ret %l
}",
    );
    assert_eq!(count(&skip, "list.new"), 0, "{}", print_module(&skip));
    // The counter steps by two.
    let step = rewrite(
        "fn @fill(%n: int) -> list<int> {
b0:
  %l0: list<int> = list.lit
  %z: int = iconst 0
  br head(%z, %l0)
head(%i: int, %l: own list<int>):
  %c: bool = icmp.lt %i, %n
  br_if %c, body(), out()
body():
  %la: list<int> = list.push %l, %i
  %two: int = iconst 2
  %next: int = iadd %i, %two
  br head(%next, %la)
out():
  ret %l
}",
    );
    assert_eq!(count(&step, "list.new"), 0, "{}", print_module(&step));
    // The loop can return early.
    let early = rewrite(
        "fn @fill(%n: int) -> list<int> {
b0:
  %l0: list<int> = list.lit
  %z: int = iconst 0
  br head(%z, %l0)
head(%i: int, %l: own list<int>):
  %c: bool = icmp.lt %i, %n
  br_if %c, body(), out()
body():
  %la: list<int> = list.push %l, %i
  %four: int = iconst 4
  %stop: bool = icmp.eq %i, %four
  br_if %stop, done(), next()
done():
  ret %la
next():
  %one: int = iconst 1
  %next: int = iadd %i, %one
  br head(%next, %la)
out():
  ret %l
}",
    );
    assert_eq!(count(&early, "list.new"), 0, "{}", print_module(&early));
}
