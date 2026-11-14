// conform: tags=control-flow,faults,formatter,interfaces,modules,parser,records,stdlib-io,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/test_fixture_test.go:257 TestCLITestWithoutFactoryDoesNotRunHooks
import TestHooks, expect_equal from "@std/test/test.ms"
import stdout from "@std/io/io.ms"

type UnusedFixture:
    value: Int

fn UnusedFixture.before_all() Unit!:
    _written := stdout().write("UNUSED before_all").get()

fn UnusedFixture.before_each() Unit!:
    _written := stdout().write("UNUSED before_each").get()

fn UnusedFixture.after_each() Unit!:
    _written := stdout().write("UNUSED after_each").get()

fn UnusedFixture.after_all() Unit!:
    _written := stdout().write("UNUSED after_all").get()

test "plain test":
    expect_equal(1 + 1, 2)?
