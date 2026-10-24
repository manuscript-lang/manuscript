from "@std/testing.ms" import expect_equal

test "getting started":
    (2 + 3) | try expect_equal(expected: 5)
