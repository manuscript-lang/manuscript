// conform: tags=faults,stdlib-testing,testing,tier-core
// conform: phase=test
// conform: origin=stdlib/test.ms TestHooks
import stdout from "@std/io/io.ms"
import TestHooks, fail, skip from "@std/test/test.ms"

type Hooks:
    runs: Int

fn make_fixture() Hooks:
    return Hooks(runs: 0)

fn var Hooks.before_all() Unit!:
    stdout().write("before_all\n").get()

fn var Hooks.before_each() Unit!:
    self.runs += 1
    stdout().write("before_each {self.runs}\n").get()

fn var Hooks.after_each() Unit!:
    stdout().write("after_each {self.runs}\n").get()

fn var Hooks.after_all() Unit!:
    stdout().write("after_all\n").get()

test "a skipped test still tears down":
    skip("not today")?

test "a failed assertion still tears down":
    fail("expected failure")?

test "a fault still tears down":
    numbers: List[Int] := []
    _ := numbers[1]
