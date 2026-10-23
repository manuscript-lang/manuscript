# conform: tags=modules,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/e2e_test.go:68 TestRuntimeFaults
import expect_equal from "@std/testing.ms"

test "failed assertion":
    2 + 3 | try expect_equal(expected: 6)
