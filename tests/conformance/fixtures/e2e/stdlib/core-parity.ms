# conform: tags=aliasing,closures,control-flow,faults,generics,interfaces,lists,maps,match,modules,optional,records,sets,stdlib-errors,stdlib-json,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/core-parity.ms
from "@std/core.ms" import TextError
from "@std/core.ms" import panic
from "@std/testing.ms" import expect_equal, expect_false
from "@std/json.ms" import JsonLimits

type Counter:
    calls: Int

impl Error for Counter:
    def message() -> String: "counter"

type Pending:
    values: List[Int]

impl Error for Pending:
    def message() -> String: "pending"

def bump(var counter: Counter) -> Int:
    counter.calls += 1
    return 9

def map_result[T, E: Error, U](
    value: Result[T, E],
    transform: Callable[[T], U]
) -> Result[U, E]:
    return value.map(transform)

def chain_result[T, E: Error, U](
    value: Result[T, E],
    transform: Callable[[T], Result[U, E]]
) -> Result[U, E]:
    return value.and_then(transform)

def map_optional[T, U](value: Optional[T], transform: Callable[[T], U]) -> Optional[U]:
    return value.map(transform)

def map_set[T: Hashable, U: Hashable](
    values: Set[T],
    transform: Callable[[T], U]
) -> Set[U]:
    return values.map[U](transform)

test "core parity operations are callable":
    let success: Result[Int, TextError] = ok(2)
    let failure: Result[Int, TextError] = error(TextError("failed"))
    try expect_false(not (success.is_ok()) or success.is_error())
    try expect_false(success.get() != 2 or failure.err().message() != "failed")
    try expect_equal(failure.get(7), 7)
    try expect_equal(failure.or_else(lambda cause: cause.message().scalar_length()), 6)
    try expect_equal(success.map(lambda n: n + 1).get(), 3)

    let chained: Result[String, TextError] = success.and_then(
        lambda n: ok(n.to_string())
    )
    try expect_equal(chained.get(), "2")

    let present: Optional[Int] = some(2)
    let missing: Optional[Int] = none
    try expect_equal(present.map(lambda n: n + 1).get(), 3)
    try expect_equal(present.and_then(lambda n: some(n.to_string())).get(), "2")
    try expect_equal(missing.or_else(lambda: some(4)).get(), 4)

    let values: Map[String, Int] = {"a": 1, "b": 2}
    try expect_false(values.is_empty() or values.get_or("absent", 8) != 8)
    try expect_equal(values.filter(lambda k, v: k == "b" and v == 2).length(), 1)

    let members = Set[Int]([2, 3])
    try expect_false(
        members.is_empty() or members.filter(lambda n: n == 2).length() != 1
    )
    try expect_equal(members.map(lambda n: n.to_string()).values(), ["2", "3"])

def unexpected_text(value: Int) -> String:
    return panic("transform must not run for errors")

def unexpected_chain(value: Int) -> Result[String, Counter]:
    return panic("chain must not run for errors")

test "Result preserves unconstrained payloads and success-only composition":
    let counter = Counter(0)
    let failure: Result[Int, Counter] = error(counter.clone())
    let success: Result[Int, Counter] = ok(0)
    let skipped = map_result(failure.clone(), unexpected_text)
    try expect_false(not (skipped.is_error()) or skipped.is_ok())

    var skipped_cause = skipped.err().clone()
    skipped_cause.calls = 2
    try expect_equal(counter.calls, 0)
    try expect_equal(skipped.err().calls, 0)

    let mapped = success.clone().map(lambda value: value.to_string())
    try expect_equal(mapped.get(), "0")

    let propagated = chain_result(failure.clone(), unexpected_chain)
    try expect_false(not (propagated.is_error()))

    var propagated_cause = propagated.err().clone()
    propagated_cause.calls = 4
    try expect_equal(counter.calls, 0)

    let produced = (
        success
        .clone()
        .and_then(lambda value: Result[String, Counter].error(counter.clone()))
    )
    try expect_false(not (produced.is_error()))

    var produced_cause = produced.err().clone()
    produced_cause.calls = 6
    try expect_equal(counter.calls, 0)
    try expect_equal(produced.err().calls, 0)

    let collection_error: Result[Bool, Pending] = error(Pending([1]))
    var pending = Pending(
        collection_error.clone().map(lambda flag: not flag).err().values.clone()
    )
    pending.values.append(2)
    try expect_equal(pending.values, [1, 2])
    try expect_equal(collection_error.err().values, [1])

    let limits = JsonLimits(-1)
    let record: Result[JsonLimits, TextError] = ok(limits.clone())
    var changed = record.clone().map(lambda value: value).get().clone()
    changed.max_values = some(7)
    try expect_equal(changed.max_values.get(), 7)
    try expect_false(limits.max_values.is_some())

    let nested = success.clone().map(lambda n: some(n))
    try expect_equal(nested.get().get(), 0)

    let unit_result: Result[Unit, TextError] = ok(())
    try expect_false(not (unit_result.is_ok()))

    let bool_result: Result[Bool, TextError] = ok(False)
    try expect_false(bool_result.get(True))

test "Result fallbacks are eager or lazy and bound methods keep receivers":
    var counter = Counter(0)
    let success: Result[Int, Counter] = ok(0)
    let failure: Result[Int, Counter] = error(counter.clone())
    try expect_false(success.get(bump(var counter)) != 0 or counter.calls != 1)

    let create = lambda (cause: Counter) -> Int: 12
    let unexpected = lambda (cause: Counter) -> Int: panic("fallback must stay lazy")
    let lazy = success.clone().or_else
    try expect_false(lazy(unexpected) != 0)
    try expect_false(failure.clone().or_else(create) != 12)

    let extract = failure.clone().err
    var extracted = extract().clone()
    extracted.calls = 3
    try expect_equal(failure.err().calls, 0)
    try expect_equal(extracted.calls, 3)

    let bound_map = success.clone().map[String]
    let bound_chain = success.clone().and_then[String]
    try expect_equal(bound_map(lambda n: n.to_string()).get(), "0")
    try expect_equal(bound_chain(lambda n: ok(n.to_string())).get(), "0")

test "Optional composition keeps nesting identity and lazy callback counts":
    let counter = Counter(0)
    let present: Optional[Counter] = some(counter.clone())
    let missing: Optional[Counter] = none
    let transform = lambda (value: Counter) -> Counter:
        return Counter(value.calls + 1)
    let unexpected = lambda (value: Counter) -> Counter: panic(
        "map must not run for none"
    )
    try expect_false(not (map_optional(missing.clone(), unexpected).is_none()))

    let mapped = present.clone().map(transform)
    try expect_equal(mapped.get().calls, 1)
    try expect_equal(counter.calls, 0)

    var edited = mapped.get().clone()
    edited.calls = 2
    try expect_equal(mapped.get().calls, 1)

    let chained = present.clone().and_then(lambda value: some(value))
    try expect_equal(chained.get().calls, 0)

    let absent = present.clone().and_then(lambda unused: Optional[Int].none)
    try expect_false(not (absent.is_none()))

    let create = lambda () -> Optional[Counter]: some(Counter(5))
    let unexpected_create = lambda () -> Optional[Counter]: panic(
        "fallback must stay lazy"
    )
    let bound = present.clone().or_else
    try expect_equal(bound(unexpected_create).get().calls, 0)

    let fallback = missing.clone().or_else(create)
    try expect_equal(fallback.get().calls, 5)

    let nested = present.clone().map(lambda unused: Optional[Int].none)
    try expect_false(not (nested.is_some()) or not (nested.get().is_none()))

    let bound_map = mapped.clone().map[String]
    try expect_equal(bound_map(lambda value: value.calls.to_string()).get(), "1")

    let bound_chain = missing.clone().and_then[String]
    try expect_false(not (bound_chain(lambda unused: some("unexpected")).is_none()))

test "Map filter copies ordered membership and get_or never inserts":
    var counter = Counter(0)
    let values: Map[String, Counter] = {
        "b": counter.clone(), "a": Counter(2), "c": Counter(3)
    }
    var selected = values.clone().filter(lambda k, v: k != "a" and v.calls >= 0)
    try expect_false(selected.keys() != ["b", "c"] or values.length() != 3)

    var changed = selected.get_or("b", Counter(9)).clone()
    changed.calls = 7
    try expect_equal(values.get_or("b", Counter(9)).calls, 0)
    selected.remove("b")
    selected.add("d", Counter(4))
    try expect_equal(values.keys(), ["b", "a", "c"])

    let fallback = Counter(8)
    let lookup = values.clone().get_or
    var fallback_copy = lookup(fallback: fallback.clone(), "absent").clone()
    fallback_copy.calls = 9
    try expect_false(fallback.calls != 8 or values.contains("absent"))
    try expect_false(
        (
            Map[String, Int]().get_or("absent", bump(var counter)) != 9
            or counter.calls != 1
        )
    )

    var empty = values.clone().filter(lambda unused_key, unused_value: False)
    try expect_false(not (empty.is_empty()))
    empty.add("new", counter.clone())
    try expect_false(values.contains("new"))

    let bound_filter = values.clone().filter
    try expect_equal(bound_filter(lambda k, v: k == "a").keys(), ["a"])

    let snapshot: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    let copied = snapshot.clone().filter(lambda k, v: v != 1)
    try expect_false(copied.keys() != ["b", "c"] or copied.values() != [2, 3])
    try expect_equal(snapshot.keys(), ["b", "a", "c"])

type Key:
    id: Int
    label: String

impl Equal for Key:
    def equals(other: Equal) -> Bool:
        match other:
            case Key(value): return self.id == value.id
            case _: return False

impl Hashable for Key:
    def hash() -> Int: 0

test "Set filter and map copy snapshots and deduplicate in first-result order":
    let values = Set[Int]([3, 1, 2])
    var copied = values.clone().filter(lambda n: n != 1)
    try expect_false(copied.values() != [3, 2])
    copied.remove(3)
    copied.add(8)
    try expect_equal(values.values(), [3, 1, 2])

    let bound_filter = copied.clone().filter
    try expect_equal(bound_filter(lambda n: n == 8).values(), [8])

    let input = Set[Int]([2, 3, 4])
    let mapped = map_set(input.clone(), lambda n: Key(n % 2, n.to_string()))
    try expect_false(
        (
            mapped.length() != 2
            or mapped.values().get(0).label != "2"
            or mapped.values().get(1).label != "3"
        )
    )

    let bound = input.clone().map[String]
    var mapped_snapshot = bound(lambda n: n.to_string())
    try expect_false(mapped_snapshot.values() != ["2", "3", "4"])
    mapped_snapshot.add("8")
    try expect_equal(input.length(), 3)

    let key = Key(5, "shared")
    let keys = Set[Key]([key.clone()])
    var first = keys.clone().filter(lambda unused: True).values().get(0).clone()
    first.label = "changed"

    var second = keys.clone().map(lambda value: value).values().get(0).clone()
    second.label = "again"
    try expect_equal(key.label, "shared")
    try expect_equal(keys.values().get(0).label, "shared")
    try expect_false(not (Set[Int]().map(lambda n: n.to_string()).is_empty()))
    try expect_false(not (keys.filter(lambda unused: False).is_empty()))
