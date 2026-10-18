import {expect_equal, expect_false} from "@std/testing.ms"

fn byLength(left: String, right: String) -> Int: left.length() - right.length()

fn record(into: List[Int], value: Int) -> Unit:
    into.append(value: value)
    return unit

test "map callbacks":
    let m = {"a": 1, "bb": 2, "ccc": 3}
    let sums = m.map(fn(key: String, value: Int) -> Int: key.length() + value)
    sums.get("bb") | try expect_equal(expected: some(4))
    try expect_equal(
        m.filter(fn(key: String, value: Int) -> Bool: value > 1).length(),
        2
    )
    try expect_equal(
        m.fold(
            initial: 0,
            step: fn(accumulator: Int, key: String, value: Int) -> Int: (
                accumulator
                + value
            )
        ),
        6
    )
    try expect_equal(
        m.fold_right(
            initial: 0,
            step: fn(accumulator: Int, key: String, value: Int) -> Int: (
                accumulator * 10
                + value
            )
        ),
        321
    )
    let visited = List[Int]()
    m.for_each(fn(key: String, value: Int) -> Unit: record(into: visited, value: value))
    visited.length() | try expect_equal(expected: 3)

test "set callbacks":
    let s = [1, 2, 3].to_set()
    try expect_equal(s.map(fn(value: Int) -> Int: value % 2).length(), 2)
    try expect_equal(s.filter(fn(value: Int) -> Bool: value > 1).length(), 2)
    try expect_equal(
        s.fold(
            initial: 0,
            step: fn(accumulator: Int, value: Int) -> Int: (
                accumulator
                + value
            )
        ),
        6
    )
    try expect_equal(
        s.fold_right(
            initial: 0,
            step: fn(accumulator: Int, value: Int) -> Int: (
                accumulator * 10
                + value
            )
        ),
        321
    )

test "sort with a comparator":
    let words = ["ccc", "a", "bb"]
    let sorted = words.sorted(compare: byLength)
    try expect_false(
        not (
            sorted.at(index: 0) == some("a")
            and sorted.at(index: 2) == some("ccc")
        )
    )
    let lambda = words.sorted(
        compare: fn(left: String, right: String) -> Int: (
            right.length()
            - left.length()
        )
    )
    lambda.at(index: 0) | try expect_equal(expected: some("ccc"))
