import {expect_equal, expect_false, expect_true} from "@std/testing.ms"
import JsonLimits from "@std/json.ms"

type Counter:
    calls: Int

fn bump(counter: Counter) -> Int:
    counter.calls = counter.calls + 1
    return 9

fn map_result[T, E, U](
    value: Result[T, E],
    transform: fn(value: T) -> U
) -> Result[U, E]:
    return value.map(transform)

fn chain_result[T, E, U](
    value: Result[T, E],
    transform: fn(value: T) -> Result[U, E]
) -> Result[U, E]:
    return value.and_then(transform)

fn map_optional[T, U](value: Optional[T], transform: fn(value: T) -> U) -> Optional[U]:
    return value.map(transform)

fn map_set[T: Hashable, U: Hashable](
    values: Set[T],
    transform: fn(value: T) -> U
) -> Set[U]:
    return values.map[U](transform)

test "core parity operations are callable":
    let success: Result[Int, String] = ok(2)
    let failure: Result[Int, String] = error("failed")
    (not (success.is_ok()) or success.is_error()) | try expect_false
    (success.unwrap() != 2 or failure.unwrap_error() != "failed") | try expect_false
    failure.unwrap_or(7) | try expect_equal(expected: 7)
    try expect_equal(failure.unwrap_or_else(fn(cause): cause.scalar_length()), 6)
    try expect_equal(success.map(fn(n): n + 1).unwrap(), 3)
    let chained: Result[String, String] = success.and_then(fn(n): ok(n.toString()))
    chained.unwrap() | try expect_equal(expected: "2")
    let present: Optional[Int] = some(2)
    let missing: Optional[Int] = none
    try expect_equal(present.map(fn(n): n + 1).unwrap(), 3)
    try expect_equal(present.and_then(fn(n): some(n.toString())).unwrap(), "2")
    try expect_equal(missing.or_else(fn(): some(4)).unwrap(), 4)
    let values: Map[String, Int] = {"a": 1, "b": 2}
    (values.is_empty() or values.get_or("absent", 8) != 8) | try expect_false
    try expect_equal(values.filter(fn(k, v): k == "b" and v == 2).length(), 1)
    let members = Set[Int]().add(2).add(3)
    try expect_false(members.is_empty() or members.filter(fn(n): n == 2).length() != 1)
    try expect_equal(members.map(fn(n): n.toString()).values(), ["2", "3"])

test "Result preserves unconstrained payloads and success-only composition":
    let counter = Counter(0)
    let failure: Result[Int, Counter] = error(counter)
    let success: Result[Int, Counter] = ok(0)
    let transform = fn(value: Int) -> String:
        counter.calls = counter.calls + 1
        return value.toString()
    let skipped = map_result(failure, transform)
    (not (skipped.is_error()) or skipped.is_ok() or counter.calls != 0) | try expect_false
    skipped.unwrap_error().calls = 2
    counter.calls | try expect_equal(expected: 2)
    let mapped = success.map(transform: transform)
    (mapped.unwrap() != "0" or counter.calls != 3) | try expect_false
    let chain = fn(value: Int) -> Result[String, Counter]:
        counter.calls = counter.calls + 1
        return error(counter)
    let propagated = chain_result(failure, chain)
    counter.calls | try expect_equal(expected: 3)
    propagated.unwrap_error().calls = 4
    counter.calls | try expect_equal(expected: 4)
    let produced = success.and_then(chain)
    counter.calls | try expect_equal(expected: 5)
    produced.unwrap_error().calls = 6
    counter.calls | try expect_equal(expected: 6)
    let collection_error: Result[Bool, List[Int]] = error([1])
    collection_error.map(fn(flag): not flag).unwrap_error().append(2)
    collection_error.unwrap_error() | try expect_equal(expected: [1, 2])
    let limits = JsonLimits(max_bytes: -1)
    let record: Result[JsonLimits, String] = ok(limits)
    record.map(fn(value): value).unwrap().max_values = some(7)
    limits.max_values.unwrap() | try expect_equal(expected: 7)
    let nested = success.map(fn(n): some(n))
    nested.unwrap().unwrap() | try expect_equal(expected: 0)
    let unit_result: Result[Unit, Bool] = ok(unit)
    (unit_result.is_ok()) | try expect_true
    let bool_result: Result[Bool, String] = ok(false)
    bool_result.unwrap_or(true) | try expect_false

test "Result fallbacks are eager or lazy and bound methods keep receivers":
    let counter = Counter(0)
    let success: Result[Int, Counter] = ok(0)
    let failure: Result[Int, Counter] = error(counter)
    (success.unwrap_or(bump(counter)) != 0 or counter.calls != 1) | try expect_false
    let create = fn(cause: Counter) -> Int:
        cause.calls = cause.calls + 1
        return 12
    let lazy = success.unwrap_or_else
    (lazy(create: create) != 0 or counter.calls != 1) | try expect_false
    (failure.unwrap_or_else(create) != 12 or counter.calls != 2) | try expect_false
    let extract = failure.unwrap_error
    extract().calls = 3
    counter.calls | try expect_equal(expected: 3)
    let bound_map = success.map[String]
    let bound_chain = success.and_then[String]
    try expect_equal(bound_map(fn(n): n.toString()).unwrap(), "0")
    try expect_equal(bound_chain(fn(n): ok(n.toString())).unwrap(), "0")

test "Optional composition keeps nesting identity and lazy callback counts":
    let counter = Counter(0)
    let present: Optional[Counter] = some(counter)
    let missing: Optional[Counter] = none
    let transform = fn(value: Counter) -> Counter:
        value.calls = value.calls + 1
        return value
    (not (map_optional(missing, transform).is_none()) or counter.calls != 0) | try expect_false
    let mapped = present.map(transform)
    counter.calls | try expect_equal(expected: 1)
    mapped.unwrap().calls = 2
    counter.calls | try expect_equal(expected: 2)
    let chained = present.and_then(fn(value): some(value))
    chained.unwrap().calls = 3
    counter.calls | try expect_equal(expected: 3)
    let absent = present.and_then(fn(unused): Optional[Int].none)
    (absent.is_none()) | try expect_true
    let create = fn() -> Optional[Counter]:
        counter.calls = counter.calls + 1
        return some(counter)
    let bound = present.or_else
    bound(create).unwrap().calls = 4
    counter.calls | try expect_equal(expected: 4)
    let fallback = missing.or_else(create)
    counter.calls | try expect_equal(expected: 5)
    fallback.unwrap().calls = 6
    counter.calls | try expect_equal(expected: 6)
    let nested = present.map(fn(unused): Optional[Int].none)
    (not (nested.is_some()) or not (nested.unwrap().is_none())) | try expect_false
    let bound_map = present.map[String]
    try expect_equal(bound_map(fn(value): value.calls.toString()).unwrap(), "6")
    let bound_chain = missing.and_then[String]
    try expect_true((bound_chain(fn(unused): some("unexpected")).is_none()))

test "Map filter copies ordered membership and get_or never inserts":
    let counter = Counter(0)
    let values: Map[String, Counter] = {"b": counter, "a": Counter(2), "c": Counter(3)}
    let selected = values.filter(predicate: fn(k, v): k != "a" and v.calls >= 0)
    (selected.keys() != ["b", "c"] or values.length() != 3) | try expect_false
    selected.get_or(key: "b", fallback: Counter(9)).calls = 7
    counter.calls | try expect_equal(expected: 7)
    selected.remove("b").add("d", Counter(4))
    values.keys() | try expect_equal(expected: ["b", "a", "c"])
    let fallback = Counter(8)
    let lookup = values.get_or
    lookup(fallback: fallback, key: "absent").calls = 9
    (fallback.calls != 9 or values.contains("absent")) | try expect_false
    (Map[String, Int]().get_or("absent", bump(counter)) != 9 or counter.calls != 8) | try expect_false
    let empty = values.filter(fn(unused_key, unused_value): false)
    (empty.is_empty()) | try expect_true
    empty.add("new", counter)
    values.contains("new") | try expect_false
    let bound_filter = values.filter
    try expect_equal(bound_filter(fn(k, v): k == "a").keys(), ["a"])
    let snapshot: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    let visits: List[String] = []
    let copied = snapshot.filter(
        fn(k, v):
            visits.append(k)
            snapshot.clear().add("new", 9)
            return v != 1
    )
    (
        (
            visits != ["b", "a", "c"]
            or copied.keys() != ["b", "c"]
            or copied.values() != [2, 3]
        )
    ) | try expect_false

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Equal) -> Bool:
        match other:
            Key(value): return self.id == value.id
            _: return false

impl Hashable for Key:
    fn hash() -> Int: 0

test "Set filter and map copy snapshots and deduplicate in first-result order":
    let values = Set[Int]().add(3).add(1).add(2)
    let visits: List[Int] = []
    let copied = values.filter(
        fn(n):
            visits.append(n)
            values.clear().add(9)
            return n != 1
    )
    (visits != [3, 1, 2] or copied.values() != [3, 2]) | try expect_false
    copied.remove(3).add(8)
    values.values() | try expect_equal(expected: [9])
    let bound_filter = copied.filter
    try expect_equal(bound_filter(fn(n): n == 8).values(), [8])
    let input = Set[Int]().add(2).add(3).add(4)
    let mapped = map_set(input, fn(n): Key(n % 2, n.toString()))
    (
        (
            mapped.length() != 2
            or mapped.values().at(0).unwrap().label != "2"
            or mapped.values().at(1).unwrap().label != "3"
        )
    ) | try expect_false
    let bound = input.map[String]
    let mapped_snapshot = bound(
        transform: fn(n):
            input.remove(n).add(7)
            return n.toString()
    )
    (mapped_snapshot.values() != ["2", "3", "4"] or input.values() != [7]) | try expect_false
    mapped_snapshot.add("8")
    input.length() | try expect_equal(expected: 1)
    let key = Key(5, "shared")
    let keys = Set[Key]().add(key)
    keys.filter(fn(unused): true).values().at(0).unwrap().label = "changed"
    keys.map(fn(value): value).values().at(0).unwrap().label = "again"
    key.label | try expect_equal(expected: "again")
    try expect_true((Set[Int]().map(fn(n): n.toString()).is_empty()))
    try expect_true((keys.filter(fn(unused): false).is_empty()))
