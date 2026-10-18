import {expect_equal, expect_false} from "@std/testing.ms"
import range from "@std/collections.ms"

test "List count calls the predicate once per element":
    let values = [1, 2, 3, 4]
    let seen: List[Int] = []
    let even = values.count(
        fn(value: Int) Bool:
            seen.append(value)
            return value % 2 == 0
    )
    try expect_false(even != 2 or seen != values)
    let empty: List[Int] = []
    try expect_equal(empty.count(fn(value: Int) Bool: true), 0)

test "List insert mutates in place and returns the same list":
    let values = [1, 3]
    let alias = values
    let returned = values.insert(1, 2)
    try expect_false((values != [1, 2, 3] or alias != [1, 2, 3] or returned != values))
    returned.append(4)
    try expect_equal(values, [1, 2, 3, 4])
    values.insert(0, 0).insert(5, 5)
    try expect_equal(values, [0, 1, 2, 3, 4, 5])
    values.insert(-1, 9)
    try expect_equal(values, [0, 1, 2, 3, 4, 9, 5])
    values.insert(-7, 8)
    try expect_equal(values, [8, 0, 1, 2, 3, 4, 9, 5])
    let empty: List[String] = []
    try expect_equal(empty.insert(0, "a"), ["a"])

test "List pop removes and returns the last element":
    let values = [1, 2, 3]
    let alias = values
    let last = values.pop()
    try expect_false((last != some(3) or values != [1, 2] or alias != [1, 2]))
    values.pop()
    values.pop()
    try expect_false(values.pop().is_some() or not (values.is_empty()))

type Box:
    value: Int

test "List pop and distinct retain payload references":
    let shared = Box(1)
    let boxes = [shared]
    boxes.pop().get().value = 2
    try expect_equal(shared.value, 2)
    let nested = [1]
    let lists = [nested, [1], [2]]
    let unique = lists.distinct()
    unique.get(0).append(3)
    try expect_false(unique.length() != 2 or nested != [1, 3])

test "List distinct keeps the first equal element in order":
    let values = [3, 1, 3, 2, 1]
    let unique = values.distinct()
    try expect_false(unique != [3, 1, 2] or values != [3, 1, 3, 2, 1])
    unique.append(4)
    try expect_equal(values.length(), 5)
    let words = ["b", "a", "b"]
    try expect_equal(words.distinct(), ["b", "a"])
    let empty: List[Int] = []
    let copy = empty.distinct()
    copy.append(1)
    try expect_false(not (empty.is_empty()))

fn unique_count[T: Equal](values: List[T]) Int:
    return values.distinct().length()

test "List parity operations support generic and bound use":
    try expect_equal(unique_count([1, 1, 2]), 2)
    var values = [1, 2]
    let insert = values.insert
    let pop: fn() Optional[Int] = values.pop
    let count = values.count
    values = [9]
    insert(2, 3)
    try expect_false(pop() != some(3) or count(fn(value: Int) Bool: value > 0) != 2)
    try expect_equal(values, [9])

test "List distinct handles large Int and String lists":
    let numbers: List[Int] = []
    let words: List[String] = []

    for index in range(0, 60000):
        numbers.append(index % 30000)
        words.append("w{index % 20000}")

    let unique = numbers.distinct()
    try expect_false(
        (
            unique.length() != 30000
            or unique.first() != some(0)
            or unique.last() != some(29999)
        )
    )
    let uniqueWords = words.distinct()
    try expect_false(uniqueWords.length() != 20000 or uniqueWords.get(1) != "w1")
