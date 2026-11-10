import (
    expect_equal, expect_false, expect_true from "@std/test/test.ms",
    first_items from "./first.ms",
    second_items, second_shared, second_empty from "./second.ms",
)

fn intersection[T: Hashable](left: Set[T], right: Set[T]) Set[T]:
    return left.intersection(right)

test "Set algebra probes each operand with its creator hash":
    left := first_items()
    right := second_items()
    left.union(right).values().map(fn key: key.id) | try expect_equal([1, 2, 3])
    left.intersection(right).values().map(fn key: key.id) | try expect_equal([1])
    left.difference(right).values().map(fn key: key.id) | try expect_equal([2])
    left.symmetric_difference(right).values().map(
        fn key: key.id
    ) | try expect_equal([2, 3])
    right.intersection(left).values().map(fn key: key.id) | try expect_equal([11])
    right.difference(left).values().map(fn key: key.id) | try expect_equal([3])
    right.symmetric_difference(left).values().map(
        fn key: key.id
    ) | try expect_equal([3, 2])
    left.values().map(fn key: key.id) | try expect_equal([1, 2])
    right.values().map(fn key: key.id) | try expect_equal([11, 3])

test "Set relations use the hash of the index being probed":
    left := first_items()
    right := second_items()
    shared := second_shared()
    shared.is_subset_of(left) | try expect_true
    left.is_superset_of(shared) | try expect_true
    left.is_disjoint_from(shared) | try expect_false
    shared.is_disjoint_from(left) | try expect_false
    left.is_subset_of(right) | try expect_false
    left.is_superset_of(right) | try expect_false

    empty := second_empty()
    empty.is_subset_of(left) | try expect_true
    left.is_superset_of(empty) | try expect_true
    left.is_disjoint_from(empty) | try expect_true
    empty.is_disjoint_from(left) | try expect_true

test "Bound and generic Set algebra retains left identity and owned copies":
    left := first_items()
    right := second_items()
    common := left.intersection
    var output = common(right)
    output.add(first_items().values().get(0).clone())
    output.length() | try expect_equal(1)
    output.contains(second_shared().values().get(0)) | try expect_true

    var copied = output.values()
    copied[0].label = "changed"
    output.values().get(0).label | try expect_equal("left shared")
    intersection(left, right).values().map(fn key: key.id) | try expect_equal([1])
