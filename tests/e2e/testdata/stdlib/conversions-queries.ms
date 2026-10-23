import {TextError} from "@std/core.ms"
import {expect_equal, expect_false, expect_true, fail} from "@std/testing.ms"

type Counter:
    calls: Int

impl Error for Counter:
    fn message() String: "counter"

type Pending:
    values: List[Int]

impl Error for Pending:
    fn message() String: "pending"

fn counted(var counter: Counter) Counter:
    counter.calls = counter.calls + 1
    return counter

fn require_value[T, E: Error](value: Optional[T], cause: E) Result[T, E]:
    return value.ok_or(cause)

fn require_lazy[T, E: Error](value: Optional[T], create: fn() E) Result[T, E]:
    return value.ok_or_else[E](create)

fn success_only[T, E: Error](value: Result[T, E]) Optional[T]:
    if let item = value:
        return some(item)

    return none

fn reduce_map[K: Hashable, V, A](
    values: Map[K, V],
    initial: A,
    step: fn(accumulator: A, key: K, value: V) A
) A:
    return values.fold[A](initial, step)

fn reduce_set[T: Hashable, A](
    values: Set[T],
    initial: A,
    step: fn(accumulator: A, value: T) A
) A:
    return values.fold(initial, step)

fn locate[K: Hashable, V](
    values: Map[K, V],
    predicate: fn(key: K, value: V) Bool
) Optional[MapEntry[K, V]]:
    return values.find(predicate)

test "conversions and collection queries are callable":
    let present: Optional[Int] = some(2)
    let missing: Optional[Int] = none
    present.ok_or(TextError("absent")).get() | try expect_equal(expected: 2)
    try expect_equal(
        missing.ok_or_else(fn(): TextError("absent")).err().message(), "absent"
    )
    let failed: Result[Int, TextError] = error(TextError("failed"))
    (failed.to_optional().is_none()) | try expect_true
    let entries: Map[String, Int] = {"b": 2, "a": 1}
    try expect_equal(entries.fold(0, fn(acc, k, v): acc + v), 3)
    try expect_equal(entries.find(fn(k, v): v == 1).get().key, "a")
    try expect_true((entries.some(fn(k, v): v == 1)))
    try expect_true((entries.every(fn(k, v): v > 0)))
    let values = Set[Int]([2, 1])
    try expect_equal(values.fold(0, fn(acc, n): acc + n), 3)
    try expect_equal(values.find(fn(n): n == 1).get(), 1)
    try expect_true((values.some(fn(n): n == 1)))
    try expect_true((values.every(fn(n): n > 0)))

test "conversions retain unconstrained payloads nesting and lazy counts":
    var counter = Counter(0)
    let present: Optional[Int] = some(0)
    let missing: Optional[Int] = none
    (require_value(present, counted(var counter)).get() != 0 or counter.calls != 1) | try expect_false
    var cause = require_value(missing, counter.clone()).err().clone()
    cause.calls = 2
    counter.calls | try expect_equal(expected: 1)
    let create = fn() Counter: Counter(10)
    (require_lazy(present, create).get() != 0 or counter.calls != 1) | try expect_false
    let error_result = require_lazy(missing, create)
    error_result.err().calls | try expect_equal(expected: 10)
    var lazy_cause = error_result.err().clone()
    lazy_cause.calls = 4
    error_result.err().calls | try expect_equal(expected: 10)
    let bound = missing.ok_or[Counter]
    var bound_cause = bound(cause: counter.clone()).err().clone()
    bound_cause.calls = 5
    counter.calls | try expect_equal(expected: 1)
    let bound_lazy = missing.ok_or_else[Counter]
    bound_lazy(create).err().calls | try expect_equal(expected: 10)
    let failure: Result[Counter, Pending] = error(Pending([1, 2]))
    (success_only(failure).is_none()) | try expect_true
    let success: Result[Counter, TextError] = ok(counter.clone())
    let extract = success.to_optional
    var extracted = extract().get().clone()
    extracted.calls = 7
    counter.calls | try expect_equal(expected: 1)
    let nested: Optional[Optional[Int]] = some(none)
    let converted = nested.ok_or(TextError("absent"))
    (not (converted.is_ok()) or not (converted.to_optional().get().is_none())) | try expect_false
    let false_value: Optional[Bool] = some(false)
    false_value.ok_or(TextError("absent")).to_optional().get() | try expect_false
    let unit_value: Optional[Unit] = some(unit)
    (unit_value.ok_or(TextError("absent")).to_optional().is_some()) | try expect_true
    let nested_result: Optional[Result[Int, TextError]] = some(
        error(TextError("nested"))
    )
    (
        nested_result.ok_or(
            TextError("absent")
        ).to_optional().get().err().message() | try expect_equal(expected: "nested")
    )

test "Map fold uses ordered snapshots and returns independent accumulators":
    var empty_calls: List[Int] = []
    let values: Map[String, Counter] = {
        "b": Counter(2), "a": Counter(1), "c": Counter(3)
    }
    let initial: List[String] = []
    var visits = reduce_map(
        values.clone(),
        initial.clone(),
        fn(acc, k, v):
            var next = acc
            next.append(k + v.calls.to_string())
            return next
    )
    (visits != ["b2", "a1", "c3"] or not (initial.is_empty())) | try expect_false
    visits.append("copy")
    initial.length() | try expect_equal(expected: 0)
    let empty = Map[String, Counter]()
    let fold = empty.fold[List[String]]
    var untouched = fold(
        step: (
            fn(acc, k, v):
                empty_calls.append(1)
                return acc
        ),
        initial: initial.clone()
    )
    untouched.append("empty copy")
    initial.length() | try expect_equal(expected: 0)
    untouched | try expect_equal(expected: ["empty copy"])
    let success: Result[Int, Counter] = ok(2)
    var chain_1 = Map[String, Int]()
    chain_1.add("a", 3)
    let nested = (chain_1.fold(success, fn(acc, k, v): acc.map(fn(n): (n + v))))
    nested.get() | try expect_equal(expected: 5)
    empty_calls.is_empty() | try expect_true

test "Map find returns fresh entry shells with copied payloads":
    var empty_calls: List[Int] = []
    let counter = Counter(2)
    let values: Map[String, Counter] = {
        "b": counter.clone(), "a": Counter(1), "c": Counter(3)
    }
    var visits: List[String] = []
    let found = locate(
        values.clone(),
        fn(k, v):
            visits.append(k.clone())
            return k == "a"
    ).get()
    (visits != ["b", "a"] or found.key != "a" or found.value.calls != 1) | try expect_false
    var source = Map[String, Counter]()
    source.add("b", counter.clone())
    let find = source.clone().find
    var original = find(fn(k, v): true).get().clone()
    var edited = original.value.clone()
    edited.calls = 5
    counter.calls | try expect_equal(expected: 2)
    original.key = "other"
    original.value = Counter(9)
    (not (source.contains("b")) or source.get("b").get().calls != 2) | try expect_false
    try expect_equal(source.find(fn(k, v): true).get().key, "b")
    try expect_true((source.find(fn(k, v): false).is_none()))
    let empty = Map[String, Counter]()
    try expect_false(
        not (
            empty
            .find(
                (
                    fn(k, v):
                        empty_calls.append(1)
                        return false
                )
            )
            .is_none()
        )
    )
    empty_calls.is_empty() | try expect_true

test "Map predicates short circuit over snapshots including empty receivers":
    var empty_calls: List[Int] = []
    var values: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    var seen: List[String] = []
    let some = values.some
    try expect_false(
        (
            not (
                some(
                    fn(k, v):
                        seen.append(k)
                        values.remove("a")
                        values.add("c", 99)
                        values.add("new", 4)
                        return v == 1
                )
            )
            or seen != ["b", "a"]
        )
    )
    values.clear()
    values.add("b", 2)
    values.add("a", 1)
    values.add("c", 3)
    seen.splice(0, seen.length(), [])
    let every = values.every
    try expect_false(
        (
            every(
                predicate: fn(k, v):
                    seen.append(k)
                    values.remove("a")
                    values.add("c", 99)
                    values.add("new", 4)
                    return v > 1
            )
            or seen != ["b", "a"]
        )
    )
    values.clear()
    try expect_false(
        values.some(
            (
                fn(k, v):
                    empty_calls.append(1)
                    return false
            )
        )
    )
    try expect_true(
        (
            values.every(
                (
                    fn(k, v):
                        empty_calls.append(1)
                        return true
                )
            )
        )
    )
    let complete: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    try expect_false(
        (complete.some(fn(k, v): false) or not (complete.every(fn(k, v): true)))
    )
    empty_calls.is_empty() | try expect_true

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

test "Set fold and find preserve ordered snapshots and copied payloads":
    var empty_calls: List[Int] = []
    let a = Key(1, "a")
    let b = Key(2, "b")
    let c = Key(3, "c")
    var values = Set[Key]([b.clone(), a.clone(), c.clone()])
    let initial: List[String] = []
    var visits = reduce_set(
        values.clone(),
        initial.clone(),
        fn(acc, v):
            var next = acc
            next.append(v.label.clone())
            return next
    )
    visits | try expect_equal(expected: ["b", "a", "c"])
    visits.append("copy")
    initial.length() | try expect_equal(expected: 0)
    let bound_empty = Set[Key]().fold[List[String]]
    var empty_result = bound_empty(
        initial.clone(),
        (
            fn(acc, v):
                empty_calls.append(1)
                return acc
        )
    )
    empty_result.append("empty copy")
    initial.length() | try expect_equal(expected: 0)
    values.clear()
    values.add(b.clone())
    values.add(a.clone())
    values.add(c.clone())
    var seen: List[Int] = []
    let find = values.clone().find
    var found = find(
        fn(v):
            seen.append(v.id)
            return v.id == 1
    ).get().clone()
    seen | try expect_equal(expected: [2, 1])
    found.label = "found"
    a.label | try expect_equal(expected: "a")
    values.clear()
    try expect_false(
        not (
            values
            .find(
                (
                    fn(v):
                        empty_calls.append(1)
                        return false
                )
            )
            .is_none()
        )
    )
    let flags = Set[Bool]([false])
    try expect_false(flags.find(fn(v): true).get())
    empty_calls.is_empty() | try expect_true

test "Set predicates short circuit over snapshots and keep empty identities":
    var empty_calls: List[Int] = []
    var values = Set[Int]([2, 1, 3])
    var seen: List[Int] = []
    let some = values.some
    try expect_false(
        (
            not (
                some(
                    fn(v):
                        seen.append(v)
                        values.remove(1)
                        values.add(4)
                        return v == 1
                )
            )
            or seen != [2, 1]
        )
    )
    values.clear()
    values.add(2)
    values.add(1)
    values.add(3)
    seen.splice(0, seen.length(), [])
    let every = values.every
    try expect_false(
        (
            every(
                fn(v):
                    seen.append(v)
                    values.remove(1)
                    values.add(4)
                    return v > 1
            )
            or seen != [2, 1]
        )
    )
    values.clear()
    try expect_false(
        values.some(
            (
                fn(v):
                    empty_calls.append(1)
                    return false
            )
        )
    )
    try expect_true(
        (
            values.every(
                (
                    fn(v):
                        empty_calls.append(1)
                        return true
                )
            )
        )
    )
    let complete = Set[Int]([2, 1])
    try expect_false(complete.some(fn(v): false) or not (complete.every(fn(v): true)))
    try expect_true((complete.find(fn(v): false).is_none()))
    empty_calls.is_empty() | try expect_true

test "nonmatching queries and all-true predicates visit the complete snapshot":
    let map: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    var map_visits: List[String] = []
    try expect_false(
        (
            map.some(
                fn(k, v):
                    map_visits.append(k)
                    return false
            )
            or map_visits != ["b", "a", "c"]
        )
    )
    map_visits.splice(0, map_visits.length(), [])
    try expect_false(
        (
            not (
                map.every(
                    fn(k, v):
                        map_visits.append(k)
                        return true
                )
            )
            or map_visits != ["b", "a", "c"]
        )
    )
    map_visits.splice(0, map_visits.length(), [])
    try expect_false(
        (
            not (
                map
                .find(
                    fn(k, v):
                        map_visits.append(k)
                        return false
                )
                .is_none()
            )
            or map_visits != ["b", "a", "c"]
        )
    )
    let set = Set[Int]([2, 1, 3])
    var set_visits: List[Int] = []
    try expect_false(
        (
            set.some(
                fn(v):
                    set_visits.append(v)
                    return false
            )
            or set_visits != [2, 1, 3]
        )
    )
    set_visits.splice(0, set_visits.length(), [])
    try expect_false(
        (
            not (
                set.every(
                    fn(v):
                        set_visits.append(v)
                        return true
                )
            )
            or set_visits != [2, 1, 3]
        )
    )
    set_visits.splice(0, set_visits.length(), [])
    try expect_false(
        (
            not (
                set
                .find(
                    fn(v):
                        set_visits.append(v)
                        return false
                )
                .is_none()
            )
            or set_visits != [2, 1, 3]
        )
    )

fn find_port(port: Optional[Int]) Result[Int, Error]:
    let value = try port.ok_or()
    return ok(value)

test "ok_or without a cause records the calling file and line":
    let absent: Optional[Int] = none
    let direct: Result[Int, MissingValue] = absent.ok_or()
    (direct.err().message().contains("conversions-queries.ms:")) | try expect_true
    let message = find_port(none).err().message()
    (message.starts_with("missing value at ")) | try expect_true
    find_port(some(8080)).get() | try expect_equal(expected: 8080)
    let named: Result[Int, TextError] = absent.ok_or(TextError("port"))
    named.err().message() | try expect_equal(expected: "port")
    let missing_port = find_port(none)

    match missing_port.err():
        MissingValue(found): unit
        _: return fail("default cause is not MissingValue")
