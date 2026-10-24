# conform: tags=control-flow,faults,formatter,interfaces,modules,parser,records,stdlib-io,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/test_fixture_test.go:257 TestCLITestWithoutFactoryDoesNotRunHooks
from "@std/testing.ms" import TestHooks, expect_equal
from "@std/io.ms" import stdout

type UnusedFixture:
    value: Int

impl TestHooks for UnusedFixture:
    def before_all() -> Unit:
        let written = stdout().write("UNUSED before_all").get()

    def before_each() -> Unit:
        let written = stdout().write("UNUSED before_each").get()

    def after_each() -> Unit:
        let written = stdout().write("UNUSED after_each").get()

    def after_all() -> Unit:
        let written = stdout().write("UNUSED after_all").get()

test "plain test":
    try expect_equal(1 + 1, 2)
