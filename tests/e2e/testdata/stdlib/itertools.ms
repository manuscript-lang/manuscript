import expect_equal, expect_fault from "@std/test/test.ms"
import (
    accumulate,
    combinations,
    cycle,
    group_runs,
    pairwise,
    permutations,
    product,
    zip_longest
) from "@std/collections/itertools.ms"

test "pairwise pairs neighbors":
    let pairs = pairwise([1, 2, 3])
    try expect_equal(pairs.length(), 2)
    try expect_equal(pairs[1].first, 2)
    try expect_equal(pairs[1].second, 3)
    try expect_equal(pairwise([1]).length(), 0)
    try expect_equal(pairwise(List[Int]()).length(), 0)

test "accumulate and cycle":
    try expect_equal(accumulate([1, 2, 3, 4], fn a, b: a + b), [1, 3, 6, 10])
    try expect_equal(accumulate(List[Int](), fn a, b: a + b), List[Int]())
    try expect_equal(cycle([1, 2], 3), [1, 2, 1, 2, 1, 2])
    try expect_equal(cycle([1, 2], 0), List[Int]())

test "zip_longest pads with none":
    let zipped = zip_longest([1, 2, 3], ["a"])
    try expect_equal(zipped.length(), 3)
    try expect_equal(zipped[0].first, 1)
    try expect_equal(zipped[0].second, "a")
    try expect_equal(zipped[2].first, 3)
    try expect_equal(zipped[2].second, none)

test "group_runs groups adjacent equal keys":
    let runs = group_runs([1, 1, 2, 1], fn n: n)
    try expect_equal(runs.length(), 3)
    try expect_equal(runs[0].items, [1, 1])
    try expect_equal(runs[1].key, 2)
    try expect_equal(runs[2].items, [1])

    let words = group_runs(["ant", "bee", "cat", "dog"], fn w: w.length())
    try expect_equal(words.length(), 1)
    try expect_equal(group_runs(List[Int](), fn n: n).length(), 0)

test "permutations and combinations":
    try expect_equal(
        permutations([1, 2, 3], 2), [[1, 2], [1, 3], [2, 1], [2, 3], [3, 1], [3, 2]]
    )
    try expect_equal(permutations([1, 2, 3]).length(), 6)
    try expect_equal(permutations([1, 1]).length(), 2)
    try expect_equal(permutations([1, 2], 0), [List[Int]()])
    try expect_equal(combinations([1, 2, 3], 2), [[1, 2], [1, 3], [2, 3]])
    try expect_equal(combinations([1, 2, 3], 3), [[1, 2, 3]])
    try expect_equal(combinations([1, 2, 3], 0), [List[Int]()])

test "product is the cartesian product":
    try expect_equal(product([[1, 2], [3, 4]]), [[1, 3], [1, 4], [2, 3], [2, 4]])
    try expect_equal(product(List[List[Int]]()), [List[Int]()])
    try expect_equal(product([[1], List[Int]()]), List[List[Int]]())

fn discard[T](value: T) Unit:
    return unit

test "invalid sizes fault":
    let _first = try expect_fault(fn: discard(permutations([1, 2], 3)))
    let _second = try expect_fault(fn: discard(combinations([1, 2], -1)))
    let _third = try expect_fault(fn: discard(cycle([1], -1)))
