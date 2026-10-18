import {expect_equal, expect_false, expect_ok, expect_true} from "@std/testing.ms"
import {ListBuilder, MapBuilder, SetBuilder, range, range_by, filled, map_from_entries} from "@std/collections.ms"

fn positive(value: Int) -> Bool: value > 0

fn twice(value: Int) -> Int: value * 2

fn duplicate(value: Int) -> List[Int]: [value, value]

fn sum(accumulator: Int, value: Int) -> Int: accumulator + value

fn parity(value: Int) -> Int: value % 2

test "list search callbacks empty identities and folding":
    let list = [-1, 2, 0, 3]
    (list.find(positive) != some(2) or list.find_last(positive) != some(3)) | try expect_false
    (
        (
            list.find_index(positive) != some(1)
            or list.find_last_index(positive) != some(3)
        )
    ) | try expect_false
    list.filter(positive).map(twice) | try expect_equal(expected: [4, 6])
    ([1, 2]).flat_map(duplicate) | try expect_equal(expected: [1, 1, 2, 2])
    (
        (
            list.fold(initial: 0, step: sum) != 4
            or list.fold_right(initial: 0, step: sum) != 4
        )
    ) | try expect_false
    let empty: List[Int] = []
    (empty.some(positive) or not empty.every(positive)) | try expect_false
    (not empty.first().is_none() or not empty.last().is_none()) | try expect_false
    let groups = ([1, 2, 3]).group_by(parity)
    (groups.get(1) != some([1, 3]) or groups.get(0) != some([2])) | try expect_false

test "list mutation and clone keep separate storage":
    let original = [1, 2, 3]
    let copy = original.clone()
    copy.splice(start: 1, delete_count: 1, replacement: [8, 9])
    (copy != [1, 8, 9, 3] or original != [1, 2, 3]) | try expect_false
    copy.fill(value: 0, start: 1, end: 3)
    copy | try expect_equal(expected: [1, 0, 0, 3])
    let overlapping = [1, 2, 3, 4]
    overlapping.copy_within(target: 1, start: 0, end: 3)
    overlapping | try expect_equal(expected: [1, 1, 2, 3])

test "maps preserve insertion order and overwrite duplicate keys":
    let entries = [
        MapEntry(key: "a", value: 1),
        MapEntry(key: "b", value: 2),
        MapEntry(key: "a", value: 3)
    ]
    let map = map_from_entries(entries)
    (map.keys() != ["a", "b"] or map.values() != [3, 2]) | try expect_false
    map.add_default(key: "a", value: 99)
    map.get("a") | try expect_equal(expected: some(3))
    let copy = map.clone().remove("a")
    (copy.keys() != ["b"] or map.keys() != ["a", "b"]) | try expect_false
    (map.get("missing").is_none()) | try expect_true

test "set algebra removes duplicates and preserves values":
    let left = ([1, 2, 2]).to_set()
    let right = ([2, 3]).to_set()
    left.values() | try expect_equal(expected: [1, 2])
    left.union(right).values() | try expect_equal(expected: [1, 2, 3])
    left.intersection(right).values() | try expect_equal(expected: [2])
    left.difference(right).values() | try expect_equal(expected: [1])
    left.symmetric_difference(right).values() | try expect_equal(expected: [1, 3])
    (left.is_subset_of(left.union(right))) | try expect_true
    (left.is_disjoint_from(([3]).to_set())) | try expect_true

test "collection constructors validate bounds and exact limits":
    range_by(start: 3, end: -1, step: -1, max_items: 4) | try expect_ok | try expect_equal(
        expected: [3, 2, 1, 0]
    )
    filled(value: "x", count: 2) | try expect_ok | try expect_equal(
        expected: ["x", "x"]
    )
    let invalid: Result[List[Int], CollectionError] = error(
        CollectionError.InvalidInput
    )
    range_by(start: 0, end: 1, step: 0) | try expect_equal(expected: invalid)
    let limited: Result[List[Int], CollectionError] = error(
        CollectionError.LimitExceeded
    )
    range_by(start: 0, end: 3, step: 1, max_items: 2) | try expect_equal(
        expected: limited
    )

test "stepped ranges handle full-width spans and minimum negative steps":
    let minimum = -9223372036854775808
    let maximum = 9223372036854775807
    (
        (
            (
                range_by(
                    minimum,
                    maximum,
                    maximum,
                    max_items: 3
                ) | try expect_ok
            ) != [minimum, -1, (maximum - 1)]
        )
    ) | try expect_false
    range_by(maximum, minimum, minimum, max_items: 2) | try expect_ok | try expect_equal(
        expected: [maximum, (-1)]
    )
    range_by(0, minimum, minimum, max_items: 1) | try expect_ok | try expect_equal(
        expected: [0]
    )
    let limited: Result[List[Int], CollectionError] = error(
        CollectionError.LimitExceeded
    )
    range_by(minimum, maximum, maximum, max_items: 2) | try expect_equal(
        expected: limited
    )

test "range counts up by one":
    range(0, 4) | try expect_equal(expected: [0, 1, 2, 3])
    let none_between: List[Int] = []
    (range(start: 2, end: 2) != none_between or range(5, 1) != none_between) | try expect_false
    range(-2, 1) | try expect_equal(expected: [-2, -1, 0])

test "for over range counts without a list":
    var total = 0
    for index in range(0, 5):
        total += index
    total | try expect_equal(expected: 10)
    var visits = 0
    for outer in range(0, 3):
        for inner in range(outer, 3):
            visits += 1
    visits | try expect_equal(expected: 6)
    var bound = 3
    var seen = 0

    for index in range(0, bound):
        bound = 10
        seen += 1

    seen | try expect_equal(expected: 3)
    var huge = 0
    for index in range(9223372036854775800, 9223372036854775807):
        huge += 1
    huge | try expect_equal(expected: 7)
    var skipped = 0

    for index in range(0, 10):
        if index % 2 == 0: continue
        if index > 7: break

        skipped += index

    skipped | try expect_equal(expected: 16)
    let callbacks: List[fn() -> Int] = []
    for index in range(0, 3):
        callbacks.append(fn(): index)
    try expect_equal(callbacks.map(fn(call): call()), [0, 1, 2])

test "huge sizes return LimitExceeded instead of exhausting memory":
    let limited: Result[List[Int], CollectionError] = error(
        CollectionError.LimitExceeded
    )
    filled(value: 1, count: 9223372036854775807) | try expect_equal(expected: limited)
    (
        (
            filled(
                value: 1,
                count: 4611686018427387904,
                max_items: 9223372036854775807
            ) != limited
        )
    ) | try expect_false
    range_by(start: 0, end: 9223372036854775807, step: 1) | try expect_equal(
        expected: limited
    )

test "collection builders freeze all accumulated values":
    let list = ListBuilder[Int]()
    list.append(1)
    list.append(2)
    (list.freeze() != [1, 2] or list.freeze() != [1, 2]) | try expect_false
    let map = MapBuilder[String, Int]()
    map.add(key: "a", value: 1)
    map.add(key: "a", value: 2)
    map.freeze().get("a") | try expect_equal(expected: some(2))
    let set = SetBuilder[Int]()
    set.add(1)
    set.add(1)
    set.freeze().values() | try expect_equal(expected: [1])

test "imported map add interoperates with with_entry":
    let values = Map[String, Int]().add("a", 1)
    values.add("b", 2).add(value: 3, key: "a")
    let add = values.add
    add("c", 4)
    (values.keys() != ["a", "b", "c"] or values.values() != [3, 2, 4]) | try expect_false
