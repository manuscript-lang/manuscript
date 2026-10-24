# conform: tags=alternatives,diagnostics,match,modules,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/same_type_names/conformance_test.ms
from "@std/testing.ms" import expect_equal
from "./other.ms" import flip, shifted

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
        case Mode.On: try expect_equal(flip(), 2)
        case _: try expect_equal(True, False)
