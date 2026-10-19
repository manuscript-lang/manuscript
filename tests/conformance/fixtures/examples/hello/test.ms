import {expect_equal} from "@std/testing.ms"

test "getting started":
    (2 + 3) | try expect_equal(expected: 5)
