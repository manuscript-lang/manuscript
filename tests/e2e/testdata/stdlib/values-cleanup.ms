import {expect_equal, expect_false, expect_not_equal, fail} from "@std/testing.ms"
import Closeable from "@std/cleanup.ms"
import JsonError from "@std/json.ms"

type Counter:
    calls: Int

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

type Resource:
    order: List[Int]
    id: Int

impl Closeable for Resource:
    fn close() -> Unit:
        self.order.append(self.id)

fn leave(order: List[Int]) -> Int:
    with outer = Resource(order: order, id: 1):
        with inner = Resource(order: order, id: 2):
            return 42

fn propagate(result: Result[Int, JsonError]) -> Result[Int, JsonError]:
    let found = try result
    return ok(found + 1)

test "Optional lazy fallbacks preserve nested absence and payload identity":
    let counter = Counter(0)
    let create = fn():
        counter.calls = counter.calls + 1
        return 42
    let present: Optional[Int] = some(0)
    let missing: Optional[Int] = none
    (present.unwrap_or_else(create) != 0 or counter.calls != 0) | try expect_false
    (missing.unwrap_or_else(create) != 42 or counter.calls != 1) | try expect_false
    let nested: Optional[Optional[Int]] = some(missing)
    (not nested.is_some() or not nested.unwrap().is_none()) | try expect_false

test "Result propagation and Error views preserve concrete causes":
    let failed: Result[Int, JsonError] = error(JsonError.InvalidData)
    propagate(failed) | try expect_equal(expected: failed)
    let success: Result[Int, JsonError] = ok(3)
    let expected: Result[Int, JsonError] = ok(4)
    propagate(success) | try expect_equal(expected: expected)
    let view = Error(JsonError.InvalidData)
    view.message().byte_length() | try expect_not_equal(expected: 0)

    match view:
        JsonError(cause):
            try expect_equal(cause, JsonError.InvalidData)
        _: return fail("error receiver erased")

test "custom equality and hashing define map key identity":
    let first = Key(id: 1, label: "first")
    let second = Key(id: 1, label: "second")
    (first != second or first.hash() != second.hash()) | try expect_false
    let map = (
        Map[Key, String]()
        .add(key: first, value: "a")
        .add(key: second, value: "b")
    )
    (map.length() != 1 or map.get(first) != some("b")) | try expect_false

test "Closeable cleanup runs in reverse order before return delivery":
    let order: List[Int] = []
    leave(order) | try expect_equal(expected: 42)
    order | try expect_equal(expected: [2, 1])
