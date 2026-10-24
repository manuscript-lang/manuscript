# conform: tags=closures,faults,lists,modules,optional,stdlib-testing,strings,testing,tier-core,try-result,with-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/map-set-and-sort-callbacks-keep-semantics.ms
from "@std/testing.ms" import expect_true

def byLength(left: String, right: String) -> Int: left.length() - right.length()

def record(var into: List[Int], value: Int) -> Unit:
    into.append(value: value)
    return ()

test "map callbacks":
    let m = {"a": 1, "bb": 2, "ccc": 3}
    let sums = m.map(lambda (key: String, value: Int) -> Int: key.length() + value)
    try expect_true((sums.get("bb") == some(4)))
    try expect_true(
        (
            m.filter(
                lambda (key: String, value: Int) -> Bool: value > 1
            ).length() == 2
        )
    )
    try expect_true(
        (
            m.fold(
                initial: 0,
                step: lambda (
                    accumulator: Int,
                    key: String,
                    value: Int
                ) -> Int: (accumulator + value)
            ) == 6
        )
    )
    try expect_true(
        (
            m.fold_right(
                initial: 0,
                step: lambda (
                    accumulator: Int,
                    key: String,
                    value: Int
                ) -> Int: (accumulator * 10 + value)
            ) == 321
        )
    )

    var visited = List[Int]()
    m.for_each(
        lambda (key: String, value: Int) -> Unit: record(
            into: var visited, value: value
        )
    )

test "set callbacks":
    let s = [1, 2, 3].to_set()
    try expect_true((s.map(lambda (value: Int) -> Int: value % 2).length() == 2))
    try expect_true((s.filter(lambda (value: Int) -> Bool: value > 1).length() == 2))
    try expect_true(
        (
            s.fold(
                initial: 0,
                step: lambda (accumulator: Int, value: Int) -> Int: (
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
                step: lambda (accumulator: Int, value: Int) -> Int: (
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

    let closure = words.sorted(
        compare: lambda (left: String, right: String) -> Int: (
            right.length()
            - left.length()
        )
    )
    try expect_true((closure.get(index: 0) == "ccc"))
