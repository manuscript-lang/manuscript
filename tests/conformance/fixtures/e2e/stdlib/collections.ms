# conform: tags=aliasing,closures,control-flow,faults,lists,maps,modules,mutation,optional,stdlib-collections,stdlib-testing,strings,testing,tier-stdlib,try-result,scope-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/collections.ms
import expect_equal, expect_false from "@std/test.ms"
import (range_by, filled, map_from_entries, flatten) from "@std/collections.ms"

fn positive(value: Int) Bool: value > 0

fn twice(value: Int) Int: value * 2

fn duplicate(value: Int) List[Int]: [value, value]

fn sum(accumulator: Int, value: Int) Int: accumulator + value

fn parity(value: Int) Int: value % 2

test "list search callbacks empty identities and folding":
    let list = [-1, 2, 0, 3]
    try expect_false((list.find(positive) != 2 or list.find_last(positive) != 3))
    try expect_false(
        (list.find_index(positive) != 1 or list.find_last_index(positive) != 3)
    )
    try expect_equal(list.filter(positive).map(twice), [4, 6])
    try expect_equal(([1, 2]).flat_map(duplicate), [1, 1, 2, 2])
    try expect_false((list.fold(0, sum) != 4 or list.fold_right(0, sum) != 4))

    let empty: List[Int] = []
    try expect_false(empty.any(positive) or not empty.all(positive))
    try expect_false(not empty.first().is_none() or not empty.last().is_none())

    let groups = ([1, 2, 3]).group_by(parity)
    try expect_false(groups.get(1) != [1, 3] or groups.get(0) != [2])

test "group_by keeps first-seen key order and element order across few and many buckets":
    let values = 0..600
    let few = values.group_by(fn(x: Int) Int: x % 3)
    try expect_equal(few.keys(), [0, 1, 2])

    var total = 0

    for k in 0..3:
        let group = few.get(k).get()
        try expect_equal(group.length(), 200)

        for j in 0..200:
            try expect_equal(group[j], j * 3 + k)
            total += group[j]

    try expect_equal(total, 599 * 600 / 2)

    let words = ["b", "a", "b", "c", "a", "b"].group_by(fn(w: String) String: w)
    try expect_equal(words.keys(), ["b", "a", "c"])
    try expect_equal(words.get("b"), ["b", "b", "b"])
    try expect_equal(words.get("c"), ["c"])

    let unique = values.group_by(fn(x: Int) Int: x)
    try expect_equal(unique.length(), 600)
    try expect_equal(unique.get(599), [599])

test "list mutation and clone keep separate storage":
    let original = [1, 2, 3]
    var copy = original.clone()
    copy.splice(1, 1, [8, 9])
    try expect_false(copy != [1, 8, 9, 3] or original != [1, 2, 3])
    copy.fill(0, 1, 3)
    try expect_equal(copy, [1, 0, 0, 3])

    var overlapping = [1, 2, 3, 4]
    overlapping.copy_within(1, 0, 3)
    try expect_equal(overlapping, [1, 1, 2, 3])

test "maps preserve insertion order and overwrite duplicate keys":
    let entries = [MapEntry("a", 1), MapEntry("b", 2), MapEntry("a", 3)]
    var map = map_from_entries(entries)
    try expect_false(map.keys() != ["a", "b"] or map.values() != [3, 2])
    map.add_default("a", 99)
    try expect_equal(map.get("a"), 3)

    var copy = map.clone()
    copy.remove("a")
    try expect_false(copy.keys() != ["b"] or map.keys() != ["a", "b"])
    try expect_false(not map.get("missing").is_none())

test "set algebra removes duplicates and preserves values":
    let left = ([1, 2, 2]).to_set()
    let right = ([2, 3]).to_set()
    try expect_equal(left.values(), [1, 2])
    try expect_equal(left.union(right).values(), [1, 2, 3])
    try expect_equal(left.intersection(right).values(), [2])
    try expect_equal(left.difference(right).values(), [1])
    try expect_equal(left.symmetric_difference(right).values(), [1, 3])
    try expect_false(not left.is_subset_of(left.union(right)))
    try expect_false(not left.is_disjoint_from(([3]).to_set()))

test "collection constructors validate bounds and exact limits":
    try expect_equal((try range_by(3, -1, -1, 4)), [3, 2, 1, 0])
    try expect_equal((try filled("x", 2)), ["x", "x"])

    let invalid: Result[List[Int], CollectionError] = error(
        CollectionError.InvalidInput
    )
    try expect_equal(range_by(0, 1, 0), invalid)

    let limited: Result[List[Int], CollectionError] = error(
        CollectionError.LimitExceeded
    )
    try expect_equal(range_by(0, 3, 1, 2), limited)

test "stepped ranges handle full-width spans and minimum negative steps":
    let minimum = -9223372036854775808
    let maximum = 9223372036854775807
    try expect_equal(
        (try range_by(minimum, maximum, maximum, 3)), [minimum, -1, (maximum - 1)]
    )
    try expect_equal((try range_by(maximum, minimum, minimum, 2)), [maximum, -1])
    try expect_equal((try range_by(0, minimum, minimum, 1)), [0])

    let limited: Result[List[Int], CollectionError] = error(
        CollectionError.LimitExceeded
    )
    try expect_equal(range_by(minimum, maximum, maximum, 2), limited)

test "range counts up by one":
    try expect_equal((0..4), [0, 1, 2, 3])

    let none_between: List[Int] = []
    try expect_false((2..2) != none_between or (5..1) != none_between)
    try expect_equal((-2..1), [-2, -1, 0])

test "for over range counts without a list":
    var total = 0
    for index in 0..5:
        total += index
    try expect_equal(total, 10)

    var visits = 0
    for outer in 0..3:
        for inner in outer..3:
            visits += 1
    try expect_equal(visits, 6)

    var bound = 3
    var seen = 0

    for index in 0..bound:
        bound = 10
        seen += 1

    try expect_equal(seen, 3)

    var huge = 0
    for index in 9223372036854775800..9223372036854775807:
        huge += 1
    try expect_equal(huge, 7)

    var skipped = 0

    for index in 0..10:
        if index % 2 == 0: continue
        if index > 7: break

        skipped += index

    try expect_equal(skipped, 16)

    var callbacks: List[fn() Int] = []
    for index in 0..3:
        callbacks.append(fn: index)
    try expect_equal(callbacks.map(fn call: call()), [0, 1, 2])

test "huge sizes return LimitExceeded instead of exhausting memory":
    let limited: Result[List[Int], CollectionError] = error(
        CollectionError.LimitExceeded
    )
    try expect_equal(filled(1, 9223372036854775807), limited)
    try expect_equal(filled(1, 4611686018427387904, 9223372036854775807), limited)
    try expect_equal(range_by(0, 9223372036854775807, 1), limited)

test "imported map add interoperates with with_entry":
    var values = Map[String, Int]()
    values.add("a", 1)
    values.add("b", 2)
    values.add(value: 3, "a")

    let add = values.add
    add("c", 4)
    try expect_false(values.keys() != ["a", "b", "c"] or values.values() != [3, 2, 4])

test "flatten concatenates lists":
    try expect_equal(flatten([[1, 2], [], [3]]), [1, 2, 3])
    try expect_equal(flatten(List[List[Int]]()), List[Int]())

type JoinPoint:
    x: Int

test "List join renders any element type":
    try expect_equal([1.5, 2.5].join(","), "1.5,2.5")
    try expect_equal([true, false].join("/"), "true/false")
    try expect_equal(
        [JoinPoint(1), JoinPoint(2)].join(";"), "JoinPoint(x: 1);JoinPoint(x: 2)"
    )
    try expect_equal(List[Int]().join(","), "")
