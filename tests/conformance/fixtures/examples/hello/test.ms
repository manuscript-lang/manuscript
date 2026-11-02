import expect_equal from "@std/test/test.ms"

test "getting started":
    (2 + 3) | try expect_equal(expected: 5)
