# conform: tags=control-flow,faults,interfaces,interpolation,modules,records,stdlib-io,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/test_fixture_test.go:106 TestCLITestFileFixtureListAndDefaultHooks
import {TestHooks, expect_equal} from "@std/test.ms"
import stdout from "@std/io.ms"

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
