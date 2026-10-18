import {expect_equal, expect_false, expect_true} from "@std/testing.ms"

fn subtract(amount: Int, deduction: Int = 1) -> Int: amount - deduction

fn first[T](left: T, right: T) -> T: left

fn size(values: Map[String, Int]) -> Int: values.length()

fn optional_size(values: Optional[Map[String, Int]]) -> Int: (values.unwrap().length())

fn mark(log: List[Int], value: Int) -> Int:
    log.append(value)
    return value

test "map literals and positional identifier arguments":
    let amount = 10
    let deduction = 3
    subtract(amount, deduction) | try expect_equal(expected: 7)
    subtract(amount, deduction: 2) | try expect_equal(expected: 8)
    subtract(amount) | try expect_equal(expected: 9)
    let left = 4
    let right = 8
    first(left, right) | try expect_equal(expected: 4)
    let stored: fn(amount: Int, deduction: Int) -> Int = subtract
    stored(amount, deduction) | try expect_equal(expected: 7)
    let values = {"a": 1, "b": 2, "a": 3}
    (values.length() != 2 or values.get("a").unwrap() != 3) | try expect_false
    let keys = values.keys()
    (keys.at(0).unwrap() != "a" or keys.at(1).unwrap() != "b") | try expect_false
    let empty: Map[String, Int] = {}
    (empty.length() != 0 or size({}) != 0 or optional_size({}) != 0) | try expect_false
    let nested: Map[String, Map[String, Int]] = {"a": {}, "b": {"c": 1}}
    nested.get("b").unwrap().get("c").unwrap() | try expect_equal(expected: 1)
    let optional: Map[String, Optional[Int]] = {"a": none, "b": some(2)}
    (optional.get("a").unwrap().is_none()) | try expect_true
    let key = "c"
    let value = 5
    values.add(key, value)
    values.get(key).unwrap() | try expect_equal(expected: value)
    let log: List[Int] = []
    let ordered = {
        mark(log, value: 1): mark(log, value: 2),
        mark(log, value: 1): mark(log, value: 3)
    }
    (log != [1, 2, 1, 3] or ordered.get(1).unwrap() != 3) | try expect_false
    let shared = {"x": values}
    values.add(key: "d", value: 6)
    shared.get("x").unwrap().get("d").unwrap() | try expect_equal(expected: 6)

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Equal) -> Bool:
        match other:
            Key(value): return self.id == value.id
            _: return false

impl Hashable for Key:
    fn hash() -> Int: self.id

test "map literal uses custom key equality":
    let a = Key(id: 1, label: "first")
    let b = Key(id: 1, label: "second")
    let values = {a: "a", b: "b"}
    (values.length() != 1 or values.get(a).unwrap() != "b") | try expect_false
