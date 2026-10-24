from "@std/testing.ms" import expect_equal, expect_false

def invalid_division(zero: Int) -> Bool:
    return 1 / zero == 0

test "grouping and short circuit":
    try expect_equal(2 + 3 * 4, 14)
    try expect_equal((2 + 3) * 4, 20)
    try expect_equal(10 - 3 - 2, 5)
    try expect_false(not (True or invalid_division(0)))
    try expect_false(not (not (False and invalid_division(0))))
