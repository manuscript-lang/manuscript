# conform: tags=control-flow,lists,modules,mutation,optional,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/proven-index-narrows-and-executes.ms
import {expect_equal} from "@std/testing.ms"

fn read(values: List[Int], index: Int) Int:
    if index < 0 or index >= values.length():
        return -1

    return values[index]

fn total(values: List[Int]) Int:
    var sum = 0
    var i = 0

    while i < values.length():
        sum = sum + values[i]
        i = i + 1

    return sum

fn nested(values: List[Optional[Int]], index: Int) Optional[Int]:
    if index >= 0 and index < values.length():
        return values[index]

    return none

test "guarded and looped lookups":
    try expect_equal(read([1, 2, 3], 1), 2)
    try expect_equal(read([1, 2, 3], 3), -1)
    try expect_equal(read([1, 2, 3], -1), -1)
    try expect_equal(total([1, 2, 3]), 6)
    try expect_equal(nested([some(1), none], 1), none)
    try expect_equal(nested([some(1), none], 0), some(1))
