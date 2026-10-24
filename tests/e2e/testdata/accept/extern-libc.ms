import {expect_equal} from "@std/testing.ms"

extern fn labs(value: Int) Int

extern fn sqrt(value: Float) Float

export extern fn fabs(value: Float) Float

test "extern functions call the symbol of the same name":
    expect_equal(labs(-42), 42)
    expect_equal(sqrt(2.25), 1.5)
    expect_equal(fabs(-0.5), 0.5)
