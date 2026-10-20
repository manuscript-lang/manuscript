import {expect_true} from "@std/testing.ms"

fn byLength(left: String, right: String) Int: left.length() - right.length()

fn record(var into: List[Int], value: Int) Unit:
    into.append(value: value)
    return unit

test "map callbacks":
    let m = {"a": 1, "bb": 2, "ccc": 3}
    let sums = m.map(fn(key: String, value: Int) Int: key.length() + value)
    try expect_true((sums.get("bb") == some(4)))
    try expect_true(
        (m.filter(fn(key: String, value: Int) Bool: value > 1).length() == 2)
    )
    try expect_true(
        (
            m.fold(
                initial: 0,
                step: fn(accumulator: Int, key: String, value: Int) Int: (
                    accumulator
                    + value
                )
            ) == 6
        )
    )
    try expect_true(
        (
            m.fold_right(
                initial: 0,
                step: fn(accumulator: Int, key: String, value: Int) Int: (
                    accumulator * 10
                    + value
                )
            ) == 321
        )
    )
    var visited = List[Int]()
    m.for_each(
        fn(key: String, value: Int) Unit: record(
            into: var visited,
            value: value
        )
    )

test "set callbacks":
    let s = [1, 2, 3].to_set()
    try expect_true((s.map(fn(value: Int) Int: value % 2).length() == 2))
    try expect_true((s.filter(fn(value: Int) Bool: value > 1).length() == 2))
    try expect_true(
        (
            s.fold(
                initial: 0,
                step: fn(accumulator: Int, value: Int) Int: (
                    accumulator
                    + value
                )
            ) == 6
        )
    )
    try expect_true(
        (
            s.fold_right(
                initial: 0,
                step: fn(accumulator: Int, value: Int) Int: (
                    accumulator * 10
                    + value
                )
            ) == 321
        )
    )

test "sort with a comparator":
    let words = ["ccc", "a", "bb"]
    let sorted = words.sorted(compare: byLength)
    try expect_true((sorted.get(index: 0) == "a" and sorted.get(index: 2) == "ccc"))
    let lambda = words.sorted(
        compare: fn(left: String, right: String) Int: (
            right.length()
            - left.length()
        )
    )
    try expect_true((lambda.get(index: 0) == "ccc"))
