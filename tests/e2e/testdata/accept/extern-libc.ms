from "@std/testing.ms" import expect_equal

extern def labs(value: Int) -> Int

extern def sqrt(value: Float) -> Float

export extern def fabs(value: Float) -> Float

test "extern functions call the symbol of the same name":
    expect_equal(labs(-42), 42)
    expect_equal(sqrt(2.25), 1.5)
    expect_equal(fabs(-0.5), 0.5)
