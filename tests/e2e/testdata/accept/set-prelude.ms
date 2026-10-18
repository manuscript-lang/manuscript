import {expect_equal, expect_false} from "@std/testing.ms"

fn insert[T: Hashable](values: Set[T], value: T) Set[T]: values.add(value)

test "set construction and methods need no import":
    let values: Set[Int] = Set()
    try expect_false(not values.is_empty())
    insert(values, 3).add(1).add(3)
    let add = values.add
    add(2)
    try expect_false(values.length() != 3 or not values.contains(2))
    try expect_equal(values.values(), [3, 1, 2])
    let copy = values.clone()
    values.remove(1)
    try expect_false(values.contains(1) or not copy.contains(1))
    let other = Set[Int]().add(4).add(2)
    try expect_equal(values.union(other).values(), [3, 2, 4])
    try expect_equal(values.filter(fn(value: Int) Bool: value > 2).values(), [3])
    try expect_equal(values.map(fn(value: Int) Int: value * 2).values(), [6, 4])
    let nested: List[Set[Int]] = [values]
    try expect_equal(nested[0].get().length(), 2)
    values.clear()
    try expect_false(not values.is_empty() or copy.length() != 3)
