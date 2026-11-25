// conform: tags=control-flow,faults,formatter,interfaces,modules,records,stdlib-io,stdlib-testing,testing,tier-core,try-result
// conform: phase=test,parse
// conform: origin=tests/e2e/test_fixture_test.go:257 TestCLITestWithoutFactoryDoesNotRunHooks
import (
	stdout from "@std/io/io.ms",
	TestHooks, expect_equal from "@std/test/test.ms",
)

type UnusedFixture {
	value Int
}

fn UnusedFixture.before_all() Void! {
	_written := stdout().write("UNUSED before_all").get()
}

fn UnusedFixture.before_each() Void! {
	_written := stdout().write("UNUSED before_each").get()
}

fn UnusedFixture.after_each() Void! {
	_written := stdout().write("UNUSED after_each").get()
}

fn UnusedFixture.after_all() Void! {
	_written := stdout().write("UNUSED after_all").get()
}

test "plain test" {
	expect_equal(1 + 1, 2)?
}
