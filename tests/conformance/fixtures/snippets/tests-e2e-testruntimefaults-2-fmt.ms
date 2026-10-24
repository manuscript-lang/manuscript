# conform: tags=formatter,modules,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/e2e_test.go:68 TestRuntimeFaults
from "@std/testing.ms" import expect_equal

test "failed assertion":
    2 + 3 | try expect_equal(expected: 6)
