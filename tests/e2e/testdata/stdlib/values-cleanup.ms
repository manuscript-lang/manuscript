import Closeable from "@std/cleanup.ms"
import JsonError from "@std/json.ms"
import panic from "@std/faults.ms"

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
    if present.unwrap_or_else(create) != 0 or counter.calls != 0: return panic(
        "eager lazy fallback"
    )
    if missing.unwrap_or_else(create) != 42 or counter.calls != 1: return panic(
        "missing fallback"
    )

    let nested: Optional[Optional[Int]] = some(missing)
    if not nested.is_some or not nested.unwrap().is_none: return panic(
        "nested optional flattened"
    )

test "Result propagation and Error views preserve concrete causes":
    let failed: Result[Int, JsonError] = error(JsonError.InvalidData)
    if propagate(failed) != failed: return panic("try changed cause")

    let success: Result[Int, JsonError] = ok(3)
    let expected: Result[Int, JsonError] = ok(4)
    if propagate(success) != expected: return panic("try success")

    let view = Error(JsonError.InvalidData)
    if view.message().byte_length == 0: return panic("error message")

    match view:
        JsonError(cause):
            if cause != JsonError.InvalidData: return panic("concrete error lost")

        _: return panic("error receiver erased")

test "custom equality and hashing define map key identity":
    let first = Key(id: 1, label: "first")
    let second = Key(id: 1, label: "second")
    if first != second or first.hash() != second.hash(): return panic("domain equality")

    let map = (
        Map[Key, String]()
        .add(key: first, value: "a")
        .add(key: second, value: "b")
    )
    if map.length != 1 or map.get(first) != some("b"): return panic(
        "domain map identity"
    )

test "Closeable cleanup runs in reverse order before return delivery":
    let order: List[Int] = []
    if leave(order) != 42: return panic("return value")
    if order != [2, 1]: return panic("cleanup order")
