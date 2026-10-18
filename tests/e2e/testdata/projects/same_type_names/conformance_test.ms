import {expect_equal} from "@std/testing.ms"
import {flip, shifted} from "./other.ms"

# The same type names in two modules lower to distinct Go types.
type Point:
    x: Int

type Mode:
    case Off
    case On

test "same-named records and alternatives stay distinct":
    Point(x: 1).x | try expect_equal(expected: 1)
    shifted() | try expect_equal(expected: 11)

    match Mode.On:
        Mode.On: try expect_equal(flip(), 2)
        _: try expect_equal(true, false)
