// conform: tags=diagnostics
// conform: phase=check
import TestHooks, expect_equal from "@std/test/test.ms"
import stdout from "@std/io/io.ms"
fn println(message: String) Unit:
    written := stdout().write("{message}\n").get()

type State:
    value: Int
fn make_fixture() State:
    println("FACTORY")
    return State(7)
impl TestHooks for State:
test "one":
    var hooks = TestHooks(value: fixture)
    hooks.before_all()
    expect_equal(fixture.value, 7)?
