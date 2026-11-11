import expect_equal from "@std/test/test.ms"

test "adds":
    expect_equal(1 + 1, 2)?

test "fails":
    expect_equal(1 + 1, 3)?

test "passes too":
    expect_equal(2 * 2, 4)?
