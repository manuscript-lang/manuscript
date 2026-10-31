# conform: tags=faults,stdlib-testing,testing,tier-core
# conform: phase=test
# conform: origin=stdlib/test.ms TestHooks
import stdout from "@std/io.ms"
import TestHooks, fail, skip from "@std/test.ms"

type Hooks:
    runs: Int

fn make_fixture() Hooks:
    return Hooks(runs: 0)

impl TestHooks for Hooks:
    var fn before_all() Unit:
        stdout().write("before_all\n").get()

    var fn before_each() Unit:
        self.runs += 1
        stdout().write("before_each {self.runs}\n").get()

    var fn after_each() Unit:
        stdout().write("after_each {self.runs}\n").get()

    var fn after_all() Unit:
        stdout().write("after_all\n").get()

test "a skipped test still tears down":
    skip("not today")

test "a failed assertion still tears down":
    try fail("expected failure")

test "a fault still tears down":
    let numbers: List[Int] = []
    let _ = numbers[1]
