# conform: tags=formatter,modules,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/e2e_test.go:68 TestRuntimeFaults
import expect_equal from "@std/test.ms"

test "failed assertion":
    2 + 3 | try expect_equal(expected: 6)
