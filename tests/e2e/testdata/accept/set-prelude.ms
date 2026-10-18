import {expect_equal, expect_false, expect_true} from "@std/testing.ms"

fn insert[T: Hashable](values: Set[T], value: T) -> Set[T]: values.add(value)

test "set construction and methods need no import":
    let values: Set[Int] = Set()
    (values.is_empty()) | try expect_true
    insert(values, 3).add(value: 1).add(3)
    let add = values.add
    add(2)
    (values.length() != 3 or not values.contains(2)) | try expect_false
    values.values() | try expect_equal(expected: [3, 1, 2])
    let copy = values.clone()
    values.remove(value: 1)
    (values.contains(1) or not copy.contains(1)) | try expect_false
    let other = Set[Int]().add(4).add(2)
    values.union(other).values() | try expect_equal(expected: [3, 2, 4])
    try expect_equal(values.filter(fn(value: Int) -> Bool: value > 2).values(), [3])
    try expect_equal(values.map(fn(value: Int) -> Int: value * 2).values(), [6, 4])
    let nested: List[Set[Int]] = [values]
    nested[0].unwrap().length() | try expect_equal(expected: 2)
    values.clear()
    (not values.is_empty() or copy.length() != 3) | try expect_false
