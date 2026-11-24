// conform: tags=control-flow,faults,formatter,interfaces,interpolation,modules,parser,records,stdlib-io,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/test_fixture_test.go:106 TestCLITestFileFixtureListAndDefaultHooks
import (
	stdout from "@std/io/io.ms",
	expect_equal from "@std/test/test.ms",
)

fn println(message String) Void {
	_written := stdout().write(f"{message}\n").get()
}

type State {
	value Int
}

fn make_fixture() State {
	println("FACTORY")
	return State(7)
}

test "one" {
	expect_equal(fixture.value, 7)?
}
