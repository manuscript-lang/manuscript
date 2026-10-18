import {expect_equal, expect_true} from "@std/testing.ms"

fn invalid_division(zero: Int) -> Bool:
    return 1 / zero == 0

test "grouping and short circuit":
    (2 + 3 * 4) | try expect_equal(expected: 14)
    ((2 + 3) * 4) | try expect_equal(expected: 20)
    (10 - 3 - 2) | try expect_equal(expected: 5)
    (true or invalid_division(zero: 0)) | try expect_true
    (not (false and invalid_division(zero: 0))) | try expect_true
