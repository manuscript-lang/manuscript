import expect_equal from "@std/test/test.ms"

test "zip pairs by position and stops at the shorter list":
    let numbers = [1, 2, 3]
    let names = ["a", "b"]
    let pairs = numbers.zip(names)
    try expect_equal(pairs.length(), 2)
    try expect_equal(pairs[1].first, 2)
    try expect_equal(pairs[1].second, "b")
    try expect_equal(names.zip(numbers).length(), 2)
    try expect_equal(numbers.zip(List[String]()).length(), 0)

test "chunks splits into copies and the last may be short":
    let parts = [1, 2, 3, 4, 5, 6, 7].chunks(3)
    try expect_equal(parts, [[1, 2, 3], [4, 5, 6], [7]])
    try expect_equal(List[Int]().chunks(3).length(), 0)
    try expect_equal(["x", "y"].chunks(5), [["x", "y"]])

test "windows overlap and a short list has none":
    try expect_equal([1, 2, 3, 4].windows(2), [[1, 2], [2, 3], [3, 4]])
    try expect_equal([1, 2].windows(3).length(), 0)
    try expect_equal(["a", "b", "c"].windows(3), [["a", "b", "c"]])

test "partition splits by predicate keeping order":
    let split = [1, 2, 3, 4, 5].partition(fn x: x % 2 == 0)
    try expect_equal(split.matching, [2, 4])
    try expect_equal(split.rest, [1, 3, 5])

    let none_split = List[Int]().partition(fn x: x > 0)
    try expect_equal(none_split.matching.length(), 0)
    try expect_equal(none_split.rest.length(), 0)

test "flat_map infers its element type from list literals returned by a callback":
    try expect_equal([1, 2].flat_map(fn x: [x, x * 10]), [1, 10, 2, 20])
    try expect_equal(["a"].flat_map(fn s: [s + "!"]), ["a!"])
    try expect_equal([1, 2].flat_map(fn x: (if x > 1: [x] else: [])), [2])
