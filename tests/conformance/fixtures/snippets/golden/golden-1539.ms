// conform: tags=diagnostics
// conform: phase=check
import TestHooks, expect_equal, fail, skip from "@std/test/test.ms"
import stdout from "@std/io/io.ms"
import panic from "@std/faults.ms"
fn println(message: String) Unit:
    written := stdout().write("{message}\n").get()

type State:
    value: Int
fn make_fixture() State:
    println("factory")
    return State(0)
impl TestHooks for State:
    fn before_all() Unit:
        println("before_all")
    fn before_each() Unit:
        self.value = self.value + 1
        println("before_each")
    fn after_each() Unit:
        println("after_each")
    fn after_all() Unit:
        println("after_all {self.value}")
test "first":
    expect_equal(fixture.value, 1)?
test "second":
    expect_equal(fixture.value, 2)?
