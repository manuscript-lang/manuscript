# conform: tags=aliasing,closures,control-flow,faults,interfaces,lists,maps,match,modules,optional,records,stdlib-cleanup,stdlib-json,stdlib-testing,strings,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/values-cleanup.ms
import {expect_equal, expect_false, expect_not_equal, fail} from "@std/testing.ms"
import Closeable from "@std/cleanup.ms"
import JsonError from "@std/json.ms"

type Counter:
    calls: Int

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

type Resource:
    order: List[Int]
    id: Int

impl Closeable for Resource:
    var fn close() Unit:
        self.order.append(self.id)

fn leave(order: List[Int]) Int:
    with outer = Resource(order, 1):
        with inner = Resource(order, 2):
            return 42

fn propagate(result: Result[Int, JsonError]) Result[Int, JsonError]:
    let found = try result
    return ok(found + 1)

test "Optional lazy fallbacks preserve nested absence and payload identity":
    var counter = Counter(0)
    let create = fn():
        counter.calls += 1
        return some(42)
    let present: Optional[Int] = some(0)
    let missing: Optional[Int] = none
    try expect_false(present.or_else(create).get() != 0 or counter.calls != 0)
    try expect_false(missing.or_else(create).get() != 42 or counter.calls != 1)
    let nested: Optional[Optional[Int]] = some(missing)
    try expect_false(not nested.is_some() or not nested.get().is_none())

test "Result propagation and Error views preserve concrete causes":
    let failed: Result[Int, JsonError] = error(JsonError.InvalidData)
    try expect_equal(propagate(failed), failed)
    let success: Result[Int, JsonError] = ok(3)
    let expected: Result[Int, JsonError] = ok(4)
    try expect_equal(propagate(success), expected)
    let view = Error(JsonError.InvalidData)
    try expect_not_equal(view.message().byte_length(), 0)

    match view:
        JsonError(cause):
            try expect_equal(cause, JsonError.InvalidData)
        _: return fail("error receiver erased")

test "custom equality and hashing define map key identity":
    let first = Key(1, "first")
    let second = Key(1, "second")
    try expect_false(first != second or first.hash() != second.hash())
    var map = Map[Key, String]()
    map.add(first, "a")
    map.add(second, "b")
    try expect_false(map.length() != 1 or map.get(first) != some("b"))

test "Closeable cleanup runs in reverse order before return delivery":
    let order: List[Int] = []
    try expect_equal(leave(order), 42)
    try expect_equal(order, [2, 1])
