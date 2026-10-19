import {TextError} from "@std/errors.ms"
import {expect_equal, expect_false} from "@std/testing.ms"
import JsonLimits from "@std/json.ms"

type Counter:
    calls: Int

impl Error for Counter:
    fn message() String: "counter"

type Pending:
    values: List[Int]

impl Error for Pending:
    fn message() String: "pending"

fn bump(var counter: Counter) Int:
    counter.calls += 1
    return 9

fn map_result[T, E: Error, U](
    value: Result[T, E],
    transform: fn(value: T) U
) Result[U, E]:
    return value.map(transform)

fn chain_result[T, E: Error, U](
    value: Result[T, E],
    transform: fn(value: T) Result[U, E]
) Result[U, E]:
    return value.and_then(transform)

fn map_optional[T, U](value: Optional[T], transform: fn(value: T) U) Optional[U]:
    return value.map(transform)

fn map_set[T: Hashable, U: Hashable](values: Set[T], transform: fn(value: T) U) Set[U]:
    return values.map[U](transform)

test "core parity operations are callable":
    let success: Result[Int, TextError] = ok(2)
    let failure: Result[Int, TextError] = error(TextError("failed"))
    try expect_false(not (success.is_ok()) or success.is_error())
    try expect_false(success.get() != 2 or failure.err().message() != "failed")
    try expect_equal(failure.get(7), 7)
    try expect_equal(failure.or_else(fn(cause): cause.message().scalar_length()), 6)
    try expect_equal(success.map(fn(n): n + 1).get(), 3)
    let chained: Result[String, TextError] = success.and_then(fn(n): ok(n.to_string()))
    try expect_equal(chained.get(), "2")
    let present: Optional[Int] = some(2)
    let missing: Optional[Int] = none
    try expect_equal(present.map(fn(n): n + 1).get(), 3)
    try expect_equal(present.and_then(fn(n): some(n.to_string())).get(), "2")
    try expect_equal(missing.or_else(fn(): some(4)).get(), 4)
    let values: Map[String, Int] = {"a": 1, "b": 2}
    try expect_false(values.is_empty() or values.get_or("absent", 8) != 8)
    try expect_equal(values.filter(fn(k, v): k == "b" and v == 2).length(), 1)
    let members = Set[Int]([2, 3])
    try expect_false(members.is_empty() or members.filter(fn(n): n == 2).length() != 1)
    try expect_equal(members.map(fn(n): n.to_string()).values(), ["2", "3"])

test "Result preserves unconstrained payloads and success-only composition":
    var counter = Counter(0)
    let failure: Result[Int, Counter] = error(counter)
    let success: Result[Int, Counter] = ok(0)
    let transform = fn(value: Int) String:
        counter.calls += 1
        return value.to_string()
    let skipped = map_result(failure, transform)
    try expect_false(
        (not (skipped.is_error()) or skipped.is_ok() or counter.calls != 0)
    )
    skipped.err().calls = 2
    try expect_equal(counter.calls, 2)
    let mapped = success.map(transform)
    try expect_false(mapped.get() != "0" or counter.calls != 3)
    let chain = fn(value: Int) Result[String, Counter]:
        counter.calls += 1
        return error(counter)
    let propagated = chain_result(failure, chain)
    try expect_equal(counter.calls, 3)
    propagated.err().calls = 4
    try expect_equal(counter.calls, 4)
    let produced = success.and_then(chain)
    try expect_equal(counter.calls, 5)
    produced.err().calls = 6
    try expect_equal(counter.calls, 6)
    let collection_error: Result[Bool, Pending] = error(Pending([1]))
    collection_error.map(fn(flag): not flag).err().values.append(2)
    try expect_equal(collection_error.err().values, [1, 2])
    let limits = JsonLimits(-1)
    let record: Result[JsonLimits, TextError] = ok(limits)
    record.map(fn(value): value).get().max_values = some(7)
    try expect_equal(limits.max_values.get(), 7)
    let nested = success.map(fn(n): some(n))
    try expect_equal(nested.get().get(), 0)
    let unit_result: Result[Unit, TextError] = ok(unit)
    try expect_false(not (unit_result.is_ok()))
    let bool_result: Result[Bool, TextError] = ok(false)
    try expect_false(bool_result.get(true))

test "Result fallbacks are eager or lazy and bound methods keep receivers":
    var counter = Counter(0)
    let success: Result[Int, Counter] = ok(0)
    let failure: Result[Int, Counter] = error(counter)
    try expect_false(success.get(bump(var counter)) != 0 or counter.calls != 1)
    let create = fn(cause: Counter) Int:
        cause.calls += 1
        return 12
    let lazy = success.or_else
    try expect_false(lazy(create) != 0 or counter.calls != 1)
    try expect_false(failure.or_else(create) != 12 or counter.calls != 2)
    let extract = failure.err
    extract().calls = 3
    try expect_equal(counter.calls, 3)
    let bound_map = success.map[String]
    let bound_chain = success.and_then[String]
    try expect_equal(bound_map(fn(n): n.to_string()).get(), "0")
    try expect_equal(bound_chain(fn(n): ok(n.to_string())).get(), "0")

test "Optional composition keeps nesting identity and lazy callback counts":
    var counter = Counter(0)
    let present: Optional[Counter] = some(counter)
    let missing: Optional[Counter] = none
    let transform = fn(value: Counter) Counter:
        value.calls += 1
        return value
    try expect_false(
        (not (map_optional(missing, transform).is_none()) or counter.calls != 0)
    )
    let mapped = present.map(transform)
    try expect_equal(counter.calls, 1)
    mapped.get().calls = 2
    try expect_equal(counter.calls, 2)
    let chained = present.and_then(fn(value): some(value))
    chained.get().calls = 3
    try expect_equal(counter.calls, 3)
    let absent = present.and_then(fn(unused): Optional[Int].none)
    try expect_false(not (absent.is_none()))
    let create = fn() Optional[Counter]:
        counter.calls += 1
        return some(counter)
    let bound = present.or_else
    bound(create).get().calls = 4
    try expect_equal(counter.calls, 4)
    let fallback = missing.or_else(create)
    try expect_equal(counter.calls, 5)
    fallback.get().calls = 6
    try expect_equal(counter.calls, 6)
    let nested = present.map(fn(unused): Optional[Int].none)
    try expect_false(not (nested.is_some()) or not (nested.get().is_none()))
    let bound_map = present.map[String]
    try expect_equal(bound_map(fn(value): value.calls.to_string()).get(), "6")
    let bound_chain = missing.and_then[String]
    try expect_false(not (bound_chain(fn(unused): some("unexpected")).is_none()))

test "Map filter copies ordered membership and get_or never inserts":
    var counter = Counter(0)
    let values: Map[String, Counter] = {"b": counter, "a": Counter(2), "c": Counter(3)}
    var selected = values.filter(fn(k, v): k != "a" and v.calls >= 0)
    try expect_false(selected.keys() != ["b", "c"] or values.length() != 3)
    selected.get_or("b", Counter(9)).calls = 7
    try expect_equal(counter.calls, 7)
    selected.remove("b")
    selected.add("d", Counter(4))
    try expect_equal(values.keys(), ["b", "a", "c"])
    let fallback = Counter(8)
    let lookup = values.get_or
    lookup(fallback: fallback, "absent").calls = 9
    try expect_false(fallback.calls != 9 or values.contains("absent"))
    try expect_false(
        (
            Map[String, Int]().get_or("absent", bump(var counter)) != 9
            or counter.calls != 8
        )
    )
    var empty = values.filter(fn(unused_key, unused_value): false)
    try expect_false(not (empty.is_empty()))
    empty.add("new", counter)
    try expect_false(values.contains("new"))
    let bound_filter = values.filter
    try expect_equal(bound_filter(fn(k, v): k == "a").keys(), ["a"])
    var snapshot: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    var visits: List[String] = []
    let copied = snapshot.filter(
        fn(k, v):
            visits.append(k)
            snapshot.clear()
            snapshot.add("new", 9)
            return v != 1
    )
    try expect_false(
        (
            visits != ["b", "a", "c"]
            or copied.keys() != ["b", "c"]
            or copied.values() != [2, 3]
        )
    )

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Equal) Bool:
        match other:
            Key(value): return self.id == value.id
            _: return false

impl Hashable for Key:
    fn hash() Int: 0

test "Set filter and map copy snapshots and deduplicate in first-result order":
    var values = Set[Int]([3, 1, 2])
    var visits: List[Int] = []
    var copied = values.filter(
        fn(n):
            visits.append(n)
            values.clear()
            values.add(9)
            return n != 1
    )
    try expect_false(visits != [3, 1, 2] or copied.values() != [3, 2])
    copied.remove(3)
    copied.add(8)
    try expect_equal(values.values(), [9])
    let bound_filter = copied.filter
    try expect_equal(bound_filter(fn(n): n == 8).values(), [8])
    var input = Set[Int]([2, 3, 4])
    let mapped = map_set(input, fn(n): Key(n % 2, n.to_string()))
    try expect_false(
        (
            mapped.length() != 2
            or mapped.values().get(0).label != "2"
            or mapped.values().get(1).label != "3"
        )
    )
    let bound = input.map[String]
    var mapped_snapshot = bound(
        fn(n):
            input.remove(n)
            input.add(7)
            return n.to_string()
    )
    try expect_false(
        (mapped_snapshot.values() != ["2", "3", "4"] or input.values() != [7])
    )
    mapped_snapshot.add("8")
    try expect_equal(input.length(), 1)
    let key = Key(5, "shared")
    let keys = Set[Key]([key])
    keys.filter(fn(unused): true).values().get(0).label = "changed"
    keys.map(fn(value): value).values().get(0).label = "again"
    try expect_equal(key.label, "again")
    try expect_false(not (Set[Int]().map(fn(n): n.to_string()).is_empty()))
    try expect_false(not (keys.filter(fn(unused): false).is_empty()))
