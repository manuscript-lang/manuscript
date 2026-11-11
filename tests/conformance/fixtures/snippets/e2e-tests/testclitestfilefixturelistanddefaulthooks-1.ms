// conform: tags=control-flow,faults,interfaces,interpolation,modules,records,stdlib-io,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/test_fixture_test.go:106 TestCLITestFileFixtureListAndDefaultHooks
import expect_equal from "@std/test/test.ms"
import stdout from "@std/io/io.ms"

fn println(message: String) Unit:
    _written := stdout().write("{message}\n").get()

type State:
    value: Int

fn make_fixture() State:
    println("FACTORY")
    return State(7)

test "one":
    expect_equal(fixture.value, 7)?
