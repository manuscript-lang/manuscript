# conform: tags=modules,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/e2e_test.go:30 TestStandaloneHasNoRuntimeDependency
import expect_equal from "@std/testing.ms"

test "arithmetic":
    2 + 3 | try expect_equal(expected: 5)
