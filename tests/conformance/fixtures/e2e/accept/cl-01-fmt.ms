# conform: tags=formatter,modules,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cl-01.ms
from "@std/testing.ms" import expect_equal

def subtract(amount: Int, deduction: Int) -> Int:
    return amount - deduction

test "named multiline call":
    let remaining = subtract(deduction: 2, amount: 9)
    try expect_equal(remaining, 7)
