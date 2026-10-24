# conform: tags=modules,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=documentation/learn/testing.md:13
from "@std/testing.ms" import expect_equal

def add(a: Int, b: Int) -> Int:
    return a + b

test "addition":
    try expect_equal(add(1, 2), 3)

test "zero is unchanged":
    try expect_equal(add(0, 7), 7)
