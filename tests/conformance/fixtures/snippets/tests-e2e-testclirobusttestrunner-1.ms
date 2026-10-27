# conform: tags=modules,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testing_runner_test.go:13 TestCLIRobustTestRunner
from "@std/test.ms" import expect_equal, skip

test "passing":
    try expect_equal(2 + 2, 4)

test "skipped":
    skip("fixture unavailable")

test "failing":
    try expect_equal(1, 2)

test "later":
    try expect_equal(True, True)
