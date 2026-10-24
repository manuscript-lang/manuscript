# conform: tags=control-flow,faults,interfaces,interpolation,modules,records,stdlib-io,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/test_fixture_test.go:106 TestCLITestFileFixtureListAndDefaultHooks
from "@std/testing.ms" import TestHooks, expect_equal
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
    var hooks: TestHooks = fixture
    hooks.before_all()
    try expect_equal(fixture.value, 7)
