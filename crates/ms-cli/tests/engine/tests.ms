from "@std/testing.ms" import expect_equal

test "adds":
    try expect_equal(1 + 1, 2)

test "fails":
    try expect_equal(1 + 1, 3)

test "passes too":
    try expect_equal(2 * 2, 4)
