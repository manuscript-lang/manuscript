// conform: tags=control-flow,faults,interfaces,interpolation,modules,records,stdlib-io,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/test_fixture_test.go:106 TestCLITestFileFixtureListAndDefaultHooks
import (
	stdout from "@std/io/io.ms",
	TestHooks, expect_equal from "@std/test/test.ms",
)

fn println(message: String) Unit:
	_written := stdout().write("{message}\n").get()

type State:
	value: Int

fn make_fixture() State:
	println("FACTORY")
	return State(7)

impl TestHooks for State:

test "one":
	var hooks: TestHooks = fixture.clone()
	hooks.before_all()
	expect_equal(fixture.value, 7)?
