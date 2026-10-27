# conform: tags=faults,stdlib-testing,testing,tier-core
# conform: phase=test
# conform: origin=stdlib/test.ms TestHooks
from "@std/io.ms" import stdout
from "@std/test.ms" import TestHooks, fail, skip

type Hooks:
    runs: Int

def make_fixture() -> Hooks:
    return Hooks(runs: 0)

impl TestHooks for Hooks:
    var def before_all() -> Unit:
        stdout().write("before_all\n").get()

    var def before_each() -> Unit:
        self.runs += 1
        stdout().write(f"before_each {self.runs}\n").get()

    var def after_each() -> Unit:
        stdout().write(f"after_each {self.runs}\n").get()

    var def after_all() -> Unit:
        stdout().write("after_all\n").get()

test "a skipped test still tears down":
    skip("not today")

test "a failed assertion still tears down":
    try fail("expected failure")

test "a fault still tears down":
    let numbers: List[Int] = []
    let _ = numbers[1]
