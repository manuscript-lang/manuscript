# conform: tags=control-flow,faults,formatter,interfaces,interpolation,modules,parser,records,stdlib-io,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/test_fixture_test.go:106 TestCLITestFileFixtureListAndDefaultHooks
import TestHooks, expect_equal from "@std/test/test.ms"
import stdout from "@std/io/io.ms"

fn println(message: String) Unit:
    let _written = stdout().write("{message}\n").get()

type State:
    value: Int

fn make_fixture() State:
    println("FACTORY")
    return State(7)

impl TestHooks for State:

test "one":
    var hooks: TestHooks = fixture
    hooks.before_all()
    try expect_equal(fixture.value, 7)
