# conform: tags=formatter,modules,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testing_runner_test.go:13 TestCLIRobustTestRunner
import {expect_equal, skip} from "@std/testing.ms"
test "passing":
    try expect_equal(2 + 2, 4)
test "skipped":
    skip("fixture unavailable")
test "failing":
    try expect_equal(1, 2)
test "later":
    try expect_equal(true, true)
