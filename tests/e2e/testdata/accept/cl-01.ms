import {expect_equal} from "@std/testing.ms"

fn subtract(amount: Int, deduction: Int) -> Int:
    return amount - deduction

test "named multiline call":
    let remaining = subtract(deduction: 2, amount: 9)
    remaining | try expect_equal(expected: 7)
