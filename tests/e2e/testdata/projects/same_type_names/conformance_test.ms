import expect_equal from "@std/test/test.ms"
import flip, shifted from "./other.ms"

# The same type names in two modules lower to distinct Go types.
type Point:
    x: Int

type Mode:
    case Off
    case On

test "same-named records and alternatives stay distinct":
    try expect_equal(Point(1).x, 1)
    try expect_equal(shifted(), 11)

    match Mode.On:
        Mode.On: try expect_equal(flip(), 2)
        _: try expect_equal(true, false)
