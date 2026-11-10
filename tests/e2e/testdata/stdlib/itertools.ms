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
    pairs := pairwise([1, 2, 3])
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
    zipped := zip_longest([1, 2, 3], ["a"])
    try expect_equal(zipped.length(), 3)
    try expect_equal(zipped[0].first, 1)
    try expect_equal(zipped[0].second, "a")
    try expect_equal(zipped[2].first, 3)
    try expect_equal(zipped[2].second, none)

test "group_runs groups adjacent equal keys":
    runs := group_runs([1, 1, 2, 1], fn n: n)
    try expect_equal(runs.length(), 3)
    try expect_equal(runs[0].items, [1, 1])
    try expect_equal(runs[1].key, 2)
    try expect_equal(runs[2].items, [1])

    words := group_runs(["ant", "bee", "cat", "dog"], fn w: w.length())
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
    _first := try expect_fault(fn: discard(permutations([1, 2], 3)))
    _second := try expect_fault(fn: discard(combinations([1, 2], -1)))
    _third := try expect_fault(fn: discard(cycle([1], -1)))

test "combinations of every size keep their order":
    values := [10, 20, 30, 40]
    try expect_equal(combinations(values.clone(), 4), [[10, 20, 30, 40]])
    try expect_equal(
        combinations(values.clone(), 3),
        [[10, 20, 30], [10, 20, 40], [10, 30, 40], [20, 30, 40]]
    )
    try expect_equal(combinations(values.clone(), 1), [[10], [20], [30], [40]])
    try expect_equal(combinations(values.clone(), 0), [[]])
    try expect_equal(combinations(List[Int](), 0), [[]])

    var many: List[Int] = []
    for i in 0..30: many.append(i)
    try expect_equal(combinations(many.clone(), 30), [many.clone()])
    try expect_equal(combinations(many.clone(), 29).length(), 30)

test "product with an empty factor is empty wherever the factor sits":
    some := [1, 2]
    try expect_equal(
        product([List[Int](), some.clone(), some.clone()]), List[List[Int]]()
    )
    try expect_equal(
        product([some.clone(), List[Int](), some.clone()]), List[List[Int]]()
    )
    try expect_equal(
        product([some.clone(), some.clone(), List[Int]()]), List[List[Int]]()
    )
    try expect_equal(product(List[List[Int]]()), [[]])
    try expect_equal(product([some.clone()]), [[1], [2]])

test "cycle empty input skips repetition after validating count":
    try expect_equal(cycle(List[Int](), 9223372036854775807), List[Int]())
    try expect_equal(cycle(List[Int](), 0), List[Int]())

    _invalid := try expect_fault(fn: discard(cycle(List[Int](), -1)))
    try expect_equal(cycle(["a", "b"], 2), ["a", "b", "a", "b"])

test "full-size combinations do not consume call depth":
    var values: List[Int] = []
    for i in 0..1000000:
        values.append(i)

    result := combinations(values, values.length())
    try expect_equal(result.length(), 1)
    try expect_equal(result[0], values)

test "combinations distinguish equal positions and own nested copies":
    try expect_equal(combinations([1, 1, 2], 2), [[1, 1], [1, 2], [1, 2]])

    input := [[1], [2], [3]]
    var result = combinations(input, 2)
    result[0][0].append(9)
    try expect_equal(input, [[1], [2], [3]])
    try expect_equal(result[1], [[1], [3]])

    _too_large := try expect_fault(fn: discard(combinations([1], 2)))

test "zero-size permutations preserve shape and validate sizes":
    empty := List[Int]()
    try expect_equal(permutations(empty), [List[Int]()])
    try expect_equal(permutations(empty, none), [List[Int]()])
    try expect_equal(permutations(empty, 0), [List[Int]()])
    try expect_equal(permutations([[1], [2]], 0), [List[List[Int]]()])

    var values: List[Int] = []
    for i in 0..100000:
        values.append(i)
    try expect_equal(permutations(values, 0), [List[Int]()])
    try expect_equal(values.length(), 100000)
    try expect_equal(values[99999], 99999)

    _negative := try expect_fault(fn: discard(permutations(empty, -1)))
    _oversized := try expect_fault(fn: discard(permutations(empty, 1)))
    _minimum := try expect_fault(
        fn: discard(permutations([1], -9223372036854775808))
    )
    _maximum := try expect_fault(fn: discard(permutations([1], 9223372036854775807)))

test "nonzero permutations retain position order and own their results":
    try expect_equal(
        permutations([1, 1, 2], 2), [[1, 1], [1, 2], [1, 1], [1, 2], [2, 1], [2, 1]]
    )
    try expect_equal(permutations([10, 20], none), [[10, 20], [20, 10]])

    input := [[1], [2], [3]]
    var result = permutations(input, 2)
    result[0][0].append(9)
    try expect_equal(input, [[1], [2], [3]])
    try expect_equal(result[1], [[1], [3]])
