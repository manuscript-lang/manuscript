import {expect_equal, expect_false, expect_true, fail} from "@std/testing.ms"

type Counter:
    calls: Int

fn counted(counter: Counter) -> Counter:
    counter.calls = counter.calls + 1
    return counter

fn require_value[T, E](value: Optional[T], cause: E) -> Result[T, E]:
    return value.ok_or(cause)

fn require_lazy[T, E](value: Optional[T], create: fn() -> E) -> Result[T, E]:
    return value.ok_or_else[E](create)

fn success_only[T, E](value: Result[T, E]) -> Optional[T]:
    return value.to_optional()

fn reduce_map[K: Hashable, V, A](
    values: Map[K, V],
    initial: A,
    step: fn(accumulator: A, key: K, value: V) -> A
) -> A:
    return values.fold[A](initial, step)

fn reduce_set[T: Hashable, A](
    values: Set[T],
    initial: A,
    step: fn(accumulator: A, value: T) -> A
) -> A:
    return values.fold(initial, step)

fn locate[K: Hashable, V](
    values: Map[K, V],
    predicate: fn(key: K, value: V) -> Bool
) -> Optional[MapEntry[K, V]]:
    return values.find(predicate)

test "conversions and collection queries are callable":
    let present: Optional[Int] = some(2)
    let missing: Optional[Int] = none
    present.ok_or("absent").unwrap() | try expect_equal(expected: 2)
    try expect_equal(missing.ok_or_else(fn(): "absent").unwrap_error(), "absent")
    let failed: Result[Int, String] = error("failed")
    (failed.to_optional().is_none()) | try expect_true
    let entries: Map[String, Int] = {"b": 2, "a": 1}
    try expect_equal(entries.fold(0, fn(acc, k, v): acc + v), 3)
    try expect_equal(entries.find(fn(k, v): v == 1).unwrap().key, "a")
    try expect_true((entries.some(fn(k, v): v == 1)))
    try expect_true((entries.every(fn(k, v): v > 0)))
    let values = Set[Int]().add(2).add(1)
    try expect_equal(values.fold(0, fn(acc, n): acc + n), 3)
    try expect_equal(values.find(fn(n): n == 1).unwrap(), 1)
    try expect_true((values.some(fn(n): n == 1)))
    try expect_true((values.every(fn(n): n > 0)))

test "conversions retain unconstrained payloads nesting and lazy counts":
    let counter = Counter(0)
    let present: Optional[Int] = some(0)
    let missing: Optional[Int] = none
    (require_value(present, counted(counter)).unwrap() != 0 or counter.calls != 1) | try expect_false
    let cause = require_value(missing, counter).unwrap_error()
    cause.calls = 2
    counter.calls | try expect_equal(expected: 2)
    let create = fn() -> Counter: counted(counter)
    (require_lazy(present, create).unwrap() != 0 or counter.calls != 2) | try expect_false
    let error_result = require_lazy(missing, create)
    counter.calls | try expect_equal(expected: 3)
    error_result.unwrap_error().calls = 4
    counter.calls | try expect_equal(expected: 4)
    let bound = missing.ok_or[Counter]
    bound(cause: counter).unwrap_error().calls = 5
    counter.calls | try expect_equal(expected: 5)
    let bound_lazy = missing.ok_or_else[Counter]
    bound_lazy(create).unwrap_error().calls | try expect_equal(expected: 6)
    let failure: Result[Counter, List[Int]] = error([1, 2])
    (success_only(failure).is_none()) | try expect_true
    let success: Result[Counter, Bool] = ok(counter)
    let extract = success.to_optional
    extract().unwrap().calls = 7
    counter.calls | try expect_equal(expected: 7)
    let nested: Optional[Optional[Int]] = some(none)
    let converted = nested.ok_or("absent")
    (not (converted.is_ok()) or not (converted.to_optional().unwrap().is_none())) | try expect_false
    let false_value: Optional[Bool] = some(false)
    false_value.ok_or(unit).to_optional().unwrap() | try expect_false
    let unit_value: Optional[Unit] = some(unit)
    (unit_value.ok_or(false).to_optional().is_some()) | try expect_true
    let nested_result: Optional[Result[Int, String]] = some(error("nested"))
    (
        nested_result.ok_or(
            false
        ).to_optional().unwrap().unwrap_error() | try expect_equal(expected: "nested")
    )

test "Map fold uses ordered snapshots and returns accumulator aliases":
    let empty_calls: List[Int] = []
    let later = Counter(3)
    let values: Map[String, Counter] = {"b": Counter(2), "a": Counter(1), "c": later}
    let initial: List[String] = []
    let visits = reduce_map(
        values,
        initial,
        fn(acc, k, v):
            if k == "b":
                (values.add("a", Counter(99)).remove("c").add("d", Counter(4)))
                later.calls = 7

            acc.append(k + v.calls.toString())
            return acc
    )
    (visits != ["b2", "a1", "c7"] or initial != visits) | try expect_false
    visits.append("alias")
    initial.length() | try expect_equal(expected: 4)
    let empty = Map[String, Counter]()
    let fold = empty.fold[List[String]]
    let untouched = fold(
        step: (
            fn(acc, k, v):
                empty_calls.append(1)
                return acc
        ),
        initial: initial
    )
    untouched.append("empty alias")
    initial.length() | try expect_equal(expected: 5)
    let success: Result[Int, Counter] = ok(2)
    let nested = (
        Map[String, Int]()
        .add("a", 3)
        .fold(success, fn(acc, k, v): acc.map(fn(n): (n + v)))
    )
    nested.unwrap() | try expect_equal(expected: 5)
    empty_calls.is_empty() | try expect_true

test "Map find returns fresh entry shells with original payload references":
    let empty_calls: List[Int] = []
    let counter = Counter(2)
    let values: Map[String, Counter] = {"b": counter, "a": Counter(1), "c": Counter(3)}
    let visits: List[String] = []
    let found = locate(
        values,
        fn(k, v):
            visits.append(k)
            (values.remove("a").add("c", Counter(99)).add("new", Counter(9)))
            return k == "a"
    ).unwrap()
    (visits != ["b", "a"] or found.key != "a" or found.value.calls != 1) | try expect_false
    let source = Map[String, Counter]().add("b", counter)
    let find = source.find
    let original = find(fn(k, v): true).unwrap()
    original.value.calls = 5
    counter.calls | try expect_equal(expected: 5)
    original.key = "other"
    original.value = Counter(9)
    (not (source.contains("b")) or source.get("b").unwrap().calls != 5) | try expect_false
    try expect_equal(source.find(fn(k, v): true).unwrap().key, "b")
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
    let empty_calls: List[Int] = []
    let values: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    let seen: List[String] = []
    let some = values.some
    try expect_false(
        (
            not (
                some(
                    fn(k, v):
                        seen.append(k)
                        values.remove("a").add("c", 99).add("new", 4)
                        return v == 1
                )
            )
            or seen != ["b", "a"]
        )
    )
    values.clear().add("b", 2).add("a", 1).add("c", 3)
    seen.splice(0, seen.length(), [])
    let every = values.every
    try expect_false(
        (
            every(
                predicate: fn(k, v):
                    seen.append(k)
                    values.remove("a").add("c", 99).add("new", 4)
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
    fn equals(other: Equal) -> Bool:
        match other:
            Key(value): return self.id == value.id
            _: return false

impl Hashable for Key:
    fn hash() -> Int: 0

test "Set fold and find preserve ordered snapshots and reference identity":
    let empty_calls: List[Int] = []
    let a = Key(1, "a")
    let b = Key(2, "b")
    let c = Key(3, "c")
    let values = Set[Key]().add(b).add(a).add(c)
    let initial: List[String] = []
    let visits = reduce_set(
        values,
        initial,
        fn(acc, v):
            if v.id == 2:
                values.remove(a).remove(c).add(Key(4, "d"))
                c.label = "shared"

            acc.append(v.label)
            return acc
    )
    visits | try expect_equal(expected: ["b", "a", "shared"])
    visits.append("alias")
    initial.length() | try expect_equal(expected: 4)
    let bound_empty = Set[Key]().fold[List[String]]
    bound_empty(
        initial,
        (
            fn(acc, v):
                empty_calls.append(1)
                return acc
        )
    ).append("empty alias")
    initial.length() | try expect_equal(expected: 5)
    values.clear().add(b).add(a).add(c)
    let seen: List[Int] = []
    let find = values.find
    let found = find(
        fn(v):
            seen.append(v.id)
            values.remove(a).add(Key(4, "new"))
            return v.id == 1
    ).unwrap()
    seen | try expect_equal(expected: [2, 1])
    found.label = "found"
    a.label | try expect_equal(expected: "found")
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
    let flags = Set[Bool]().add(false)
    try expect_false(flags.find(fn(v): true).unwrap())
    empty_calls.is_empty() | try expect_true

test "Set predicates short circuit over snapshots and keep empty identities":
    let empty_calls: List[Int] = []
    let values = Set[Int]().add(2).add(1).add(3)
    let seen: List[Int] = []
    let some = values.some
    try expect_false(
        (
            not (
                some(
                    fn(v):
                        seen.append(v)
                        values.remove(1).add(4)
                        return v == 1
                )
            )
            or seen != [2, 1]
        )
    )
    values.clear().add(2).add(1).add(3)
    seen.splice(0, seen.length(), [])
    let every = values.every
    try expect_false(
        (
            every(
                fn(v):
                    seen.append(v)
                    values.remove(1).add(4)
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
    let complete = Set[Int]().add(2).add(1)
    try expect_false(complete.some(fn(v): false) or not (complete.every(fn(v): true)))
    try expect_true((complete.find(fn(v): false).is_none()))
    empty_calls.is_empty() | try expect_true

test "nonmatching queries and all-true predicates visit the complete snapshot":
    let map: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    let map_visits: List[String] = []
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
    let set = Set[Int]().add(2).add(1).add(3)
    let set_visits: List[Int] = []
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

fn find_port(port: Optional[Int]) -> Result[Int, Error]:
    let value = try port.ok_or()
    return ok(value)

test "ok_or without a cause records the calling file and line":
    let absent: Optional[Int] = none
    let direct: Result[Int, MissingValue] = absent.ok_or()
    (direct.unwrap_error().message().contains("conversions-queries.ms:")) | try expect_true
    let message = find_port(none).unwrap_error().message()
    (message.starts_with("missing value at ")) | try expect_true
    find_port(some(8080)).unwrap() | try expect_equal(expected: 8080)
    let named: Result[Int, String] = absent.ok_or("port")
    named.unwrap_error() | try expect_equal(expected: "port")

    match find_port(none).unwrap_error():
        MissingValue(found): unit
        _: return fail("default cause is not MissingValue")
