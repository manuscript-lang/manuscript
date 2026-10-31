# conform: tags=formatter,modules,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cl-02.ms
import expect_equal, expect_false from "@std/test.ms"

fn invalid_division(zero: Int) Bool:
    return 1 / zero == 0

test "grouping and short circuit":
    try expect_equal(2 + 3 * 4, 14)
    try expect_equal((2 + 3) * 4, 20)
    try expect_equal(10 - 3 - 2, 5)
    try expect_false(not (true or invalid_division(0)))
    try expect_false(not (not (false and invalid_division(0))))
