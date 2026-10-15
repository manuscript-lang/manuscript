import {flip, shifted} from "./other.ms"
import {expect_equal} from "@std/testing.ms"

# The same type names in two modules lower to distinct Go types.
type Point:
    x: Int

type Mode:
    case Off
    case On

test "same-named records and alternatives stay distinct":
    expect_equal(Point(x: 1).x, 1)
    expect_equal(shifted(), 11)

    match Mode.On:
        Mode.On: expect_equal(flip(), 2)
        _: expect_equal(true, false)
