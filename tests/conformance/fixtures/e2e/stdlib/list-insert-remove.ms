# conform: tags=lists,mutation,stdlib-collections,stdlib-testing,testing,tier-stdlib
# conform: phase=test
import {expect_equal} from "@std/testing.ms"

test "insert and remove shift the tail for every element kind":
    var numbers = [1, 2, 3]
    numbers.insert(0, 0)
    numbers.insert(-1, 9)
    numbers.insert(5, 4)
    numbers.remove(1)
    numbers.remove(-1)
    try expect_equal(numbers, [0, 2, 9, 3])
    var words = ["a", "b"]
    words.insert(1, "z")
    words.remove(0)
    try expect_equal(words, ["z", "b"])
    var rows: List[List[Int]] = [[1], [2]]
    let row = [7, 7]
    rows.insert(1, row)
    rows.remove(0)
    try expect_equal(rows, [[7, 7], [2]])
    try expect_equal(row, [7, 7])

test "an inserted element is independent of its source":
    var rows: List[List[Int]] = []
    var row = [1]
    rows.insert(0, row)
    row.append(2)
    try expect_equal(rows, [[1]])
    try expect_equal(row, [1, 2])
