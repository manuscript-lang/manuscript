# conform: tags=control-flow,faults,interfaces,modules,records,stdlib-io,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/test_fixture_test.go:257 TestCLITestWithoutFactoryDoesNotRunHooks
import {TestHooks, expect_equal} from "@std/testing.ms"
import stdout from "@std/io.ms"
type UnusedFixture:
    value: Int
impl TestHooks for UnusedFixture:
    fn before_all() Unit:
        let written = stdout().write("UNUSED before_all").get()
    fn before_each() Unit:
        let written = stdout().write("UNUSED before_each").get()
    fn after_each() Unit:
        let written = stdout().write("UNUSED after_each").get()
    fn after_all() Unit:
        let written = stdout().write("UNUSED after_all").get()
test "plain test":
    try expect_equal(1 + 1, 2)
