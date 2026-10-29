import expect_equal from "@std/test.ms"

fn subtract(amount: Int, deduction: Int) Int:
    return amount - deduction

test "named multiline call":
    let remaining = subtract(deduction: 2, amount: 9)
    try expect_equal(remaining, 7)
