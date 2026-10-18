import {expect_equal} from "@std/testing.ms"

test "literal divisors":
    let n = -7
    (n / 2) | try expect_equal(expected: -3)
    (n % 3) | try expect_equal(expected: -1)
    (9 % 2) | try expect_equal(expected: 1)
    var i = 0
    var hits = 0

    while i < 100:
        if i % 3 == 0:
            hits = hits + 1
        i = i + 1

    hits | try expect_equal(expected: 34)
