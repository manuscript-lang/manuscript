import {expect_equal} from "@std/testing.ms"

fn read(values: List[Int], index: Int) -> Int:
    if index < 0 or index >= values.length():
        return -1

    return values[index]

fn total(values: List[Int]) -> Int:
    var sum = 0
    var i = 0

    while i < values.length():
        sum = sum + values[i]
        i = i + 1

    return sum

fn nested(values: List[Optional[Int]], index: Int) -> Optional[Int]:
    if index >= 0 and index < values.length():
        return values[index]

    return none

test "guarded and looped lookups":
    read([1, 2, 3], 1) | try expect_equal(expected: 2)
    read([1, 2, 3], 3) | try expect_equal(expected: -1)
    read([1, 2, 3], -1) | try expect_equal(expected: -1)
    total([1, 2, 3]) | try expect_equal(expected: 6)
    nested([some(1), none], 1) | try expect_equal(expected: none)
    nested([some(1), none], 0) | try expect_equal(expected: some(1))
