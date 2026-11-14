// conform: tags=modules,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testing_runner_test.go:13 TestCLIRobustTestRunner
import expect_equal, skip from "@std/test/test.ms"

test "passing":
    expect_equal(2 + 2, 4)?

test "skipped":
    skip("fixture unavailable")?

test "failing":
    expect_equal(1, 2)?

test "later":
    expect_equal(true, true)?
