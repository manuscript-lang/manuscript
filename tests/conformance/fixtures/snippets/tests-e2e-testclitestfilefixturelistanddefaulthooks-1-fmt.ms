# conform: tags=control-flow,faults,formatter,interfaces,interpolation,modules,parser,records,stdlib-io,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/test_fixture_test.go:106 TestCLITestFileFixtureListAndDefaultHooks
from "@std/test.ms" import TestHooks, expect_equal
from "@std/io.ms" import stdout

def println(message: String) -> Unit:
    let written = stdout().write(f"{message}\n").get()

type State:
    value: Int

def make_fixture() -> State:
    println("FACTORY")
    return State(7)

impl TestHooks for State:

test "one":
    var hooks = TestHooks(value: fixture)
    hooks.before_all()
    try expect_equal(fixture.value, 7)
