# conform: tags=aliasing,closures,generics,lists,modules,sets,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/set-prelude.ms
import {expect_equal, expect_false} from "@std/testing.ms"

fn insert[T: Hashable](var values: Set[T], value: T) Unit: values.add(value)

test "set construction and methods need no import":
    var values: Set[Int] = Set()
    try expect_false(not values.is_empty())
    insert(var values, 3)
    values.add(1)
    values.add(3)
    let add = values.add
    add(2)
    try expect_false(values.length() != 3 or not values.contains(2))
    try expect_equal(values.values(), [3, 1, 2])
    let copy = values.clone()
    values.remove(1)
    try expect_false(values.contains(1) or not copy.contains(1))
    let other = Set[Int]([4, 2])
    try expect_equal(values.union(other).values(), [3, 2, 4])
    try expect_equal(values.filter(fn(value: Int) Bool: value > 2).values(), [3])
    try expect_equal(values.map(fn(value: Int) Int: value * 2).values(), [6, 4])
    let nested: List[Set[Int]] = [values.clone()]
    try expect_equal(nested[0].length(), 2)
    values.clear()
    try expect_false(not values.is_empty() or copy.length() != 3)

test "set constructor accepts a list":
    let values = Set[Int]([3, 1, 3, 2])
    try expect_equal(values.values(), [3, 1, 2])
    let inferred = Set(["a", "b"])
    try expect_equal(inferred.length(), 2)
    let empty: Set[Int] = Set([])
    try expect_false(not empty.is_empty())
