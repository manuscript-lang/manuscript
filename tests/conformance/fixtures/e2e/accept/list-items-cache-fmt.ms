# conform: tags=aliasing,closures,control-flow,faults,formatter,lists,modules,mutation,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/list-items-cache.ms
import {expect_contains, expect_equal, expect_fault} from "@std/testing.ms"

fn grow(values: List[Int]) Unit:
    values.append(values.length())

test "indexed loops over a list read and write through the shared storage":
    var flags = [true, true, true, true, true, true]
    var i = 2

    while i < flags.length():
        flags.set(i, false)
        i += 2

    try expect_equal(flags, [true, true, false, true, false, true])

test "negative indexes inside a cached loop count from the end":
    let values = [10, 20, 30]
    var total = 0
    var i = 1

    while i <= 3:
        total += values.get(-i)
        i += 1

    try expect_equal(total, 60)

test "a list that grows inside the loop is read through its current storage":
    let values = [1, 2, 3]
    var seen = 0
    var i = 0

    while i < 6:
        seen += values.get(i % values.length())
        if i < 3:
            grow(values)
        i += 1

    try expect_equal(values.length(), 6)
    try expect_equal(seen, 1 + 2 + 3 + 3 + 4 + 5)

test "appending directly inside the loop is visible to later reads":
    var values = [1]
    var i = 0
    var total = 0

    while i < 4:
        total += values.get(i)
        values.append(i + 2)
        i += 1

    try expect_equal(total, 1 + 2 + 3 + 4)

test "rebinding the list inside the loop selects the new storage":
    var values = [1, 2, 3]
    let other = [10, 20, 30]
    var total = 0
    var i = 0

    while i < 3:
        total += values.get(i)
        values = other
        i += 1

    try expect_equal(total, 1 + 20 + 30)

test "nested loops share one cached list":
    let grid = [[1, 2], [3, 4]]
    var total = 0
    var row = 0

    while row < 2:
        var column = 0

        while column < 2:
            total += grid.get(row).get(column)
            column += 1

        row += 1

    try expect_equal(total, 10)

test "an out of range read or write inside a cached loop faults":
    let values = [1, 2, 3]
    let read = try expect_fault(
        fn():
            var i = 0
            var total = 0

            while i < 5:
                total += values.get(i)
                i += 1
    )
    try expect_contains(read, "out of range")
    let write = try expect_fault(
        fn():
            var i = 0

            while i < 5:
                values.set(i, 0)
                i += 1
    )
    try expect_contains(write, "List.set")
