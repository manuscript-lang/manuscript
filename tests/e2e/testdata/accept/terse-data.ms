import {expect_equal, expect_false} from "@std/testing.ms"

fn subtract(amount: Int, deduction: Int = 1) Int: amount - deduction

fn first[T](left: T, right: T) T: left

fn size(values: Map[String, Int]) Int: values.length()

fn optional_size(values: Optional[Map[String, Int]]) Int: (values.get().length())

fn mark(var log: List[Int], value: Int) Int:
    log.append(value)
    return value

test "map literals and positional identifier arguments":
    let amount = 10
    let deduction = 3
    try expect_equal(subtract(amount, deduction), 7)
    try expect_equal(subtract(amount, 2), 8)
    try expect_equal(subtract(amount), 9)
    let left = 4
    let right = 8
    try expect_equal(first(left, right), 4)
    let stored: fn(amount: Int, deduction: Int) Int = subtract
    try expect_equal(stored(amount, deduction), 7)
    var values = {"a": 1, "b": 2, "a": 3}
    try expect_false(values.length() != 2 or values.get("a").get() != 3)
    let keys = values.keys()
    try expect_false(keys.get(0) != "a" or keys.get(1) != "b")
    let empty: Map[String, Int] = {}
    try expect_false((empty.length() != 0 or size({}) != 0 or optional_size({}) != 0))
    let nested: Map[String, Map[String, Int]] = {"a": {}, "b": {"c": 1}}
    try expect_equal(nested.get("b").get().get("c").get(), 1)
    let optional: Map[String, Optional[Int]] = {"a": none, "b": some(2)}
    try expect_false(not optional.get("a").get().is_none())
    let key = "c"
    let value = 5
    values.add(key, value)
    try expect_equal(values.get(key).get(), value)
    var log: List[Int] = []
    let ordered = {
        mark(var log, 1): mark(var log, 2), mark(var log, 1): mark(var log, 3)
    }
    try expect_false(log != [1, 2, 1, 3] or ordered.get(1).get() != 3)
    let shared = {"x": values.clone()}
    values.add("d", 6)
    try expect_false(shared.get("x").get().get("d").is_some())
    try expect_equal(values.get("d").get(), 6)

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Equal) Bool:
        match other:
            Key(value): return self.id == value.id
            _: return false

impl Hashable for Key:
    fn hash() Int: self.id

test "map literal uses custom key equality":
    let a = Key(1, "first")
    let b = Key(1, "second")
    let values = {a: "a", b: "b"}
    try expect_false(values.length() != 1 or values.get(a).get() != "b")
