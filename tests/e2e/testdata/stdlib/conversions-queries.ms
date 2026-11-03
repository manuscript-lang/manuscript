import expect_equal, expect_false, expect_true, fail from "@std/test/test.ms"

type Counter:
    calls: Int

type Pending:
    values: List[Int]

fn counted(var counter: Counter) Counter:
    counter.calls = counter.calls + 1
    return counter

fn require_value[T, E](value: T?, cause: E) T!E:
    return value.ok_or(cause)

fn require_lazy[T, E](value: T?, create: fn() E) T!E:
    return value.ok_or_else[E](create)

fn success_only[T, E](value: T!E) T?:
    if let item = value:
        return item

    return none

fn reduce_map[K: Hashable, V, A](values: Map[K, V], initial: A, step: fn(A, K, V) A) A:
    return values.fold[A](initial, step)

fn reduce_set[T: Hashable, A](values: Set[T], initial: A, step: fn(A, T) A) A:
    return values.fold(initial, step)

fn locate[K: Hashable, V: Clonable](
    values: Map[K, V],
    predicate: fn(K, V) Bool
) MapEntry[K, V]?:
    return values.find(predicate)

test "conversions and collection queries are callable":
    let present: Int? = 2
    let missing: Int? = none
    present.ok_or(Error("absent")).get() | try expect_equal(2)
    try expect_equal(missing.ok_or_else(fn: Error("absent")).err().message, "absent")

    let failed: Int!Error = error(Error("failed"))
    (failed.to_optional().is_none()) | try expect_true

    let entries: Map[String, Int] = {"b": 2, "a": 1}
    try expect_equal(entries.fold(0, fn acc, k, v: acc + v), 3)
    try expect_equal(entries.find(fn k, v: v == 1).get().key, "a")
    try expect_true((entries.any(fn k, v: v == 1)))
    try expect_true((entries.all(fn k, v: v > 0)))

    let values = Set[Int]([2, 1])
    try expect_equal(values.fold(0, fn acc, n: acc + n), 3)
    try expect_equal(values.find(fn n: n == 1).get(), 1)
    try expect_true((values.any(fn n: n == 1)))
    try expect_true((values.all(fn n: n > 0)))

test "conversions retain unconstrained payloads nesting and lazy counts":
    var counter = Counter(0)
    let present: Int? = 0
    let missing: Int? = none
    (require_value(present, counted(var counter)).get() != 0 or counter.calls != 1) | try expect_false

    var cause = require_value(missing, counter.clone()).err().clone()
    cause.calls = 2
    counter.calls | try expect_equal(1)

    let create = fn() Counter: Counter(10)
    (require_lazy(present, create).get() != 0 or counter.calls != 1) | try expect_false

    let error_result = require_lazy(missing, create)
    error_result.err().calls | try expect_equal(10)

    var lazy_cause = error_result.err().clone()
    lazy_cause.calls = 4
    error_result.err().calls | try expect_equal(10)

    let bound = missing.ok_or[Counter]
    var bound_cause = bound(cause: counter.clone()).err().clone()
    bound_cause.calls = 5
    counter.calls | try expect_equal(1)

    let bound_lazy = missing.ok_or_else[Counter]
    bound_lazy(create).err().calls | try expect_equal(10)

    let failure: Counter!Pending = error(Pending([1, 2]))
    (success_only(failure).is_none()) | try expect_true

    let success: Counter!Error = ok(counter.clone())
    let extract = success.to_optional
    var extracted = extract().get().clone()
    extracted.calls = 7
    counter.calls | try expect_equal(1)

    let nested_none: Int? = none
    let nested: Int?? = nested_none
    let converted = nested.ok_or(Error("absent"))
    (not (converted.is_ok()) or not (converted.to_optional().get().is_none())) | try expect_false

    let false_value: Bool? = false
    false_value.ok_or(Error("absent")).to_optional().get() | try expect_false

    let unit_value: Unit? = unit
    (unit_value.ok_or(Error("absent")).to_optional().is_some()) | try expect_true

    let nested_inner: Int!Error = error(Error("nested"))
    let nested_result: Int!Error? = nested_inner
    nested_result.ok_or(
        Error("absent")
    ).to_optional().get().err().message | try expect_equal("nested")

test "Map fold uses ordered snapshots and returns independent accumulators":
    var empty_calls: List[Int] = []
    let values: Map[String, Counter] = {
        "b": Counter(2), "a": Counter(1), "c": Counter(3)
    }
    let initial: List[String] = []

    var visits = reduce_map(
        values.clone(),
        initial.clone(),
        fn acc,
        k,
        v:
            var next = acc
            next.append(k + v.calls.to_string())
            return next
    )

    (visits != ["b2", "a1", "c3"] or not (initial.is_empty())) | try expect_false
    visits.append("copy")
    initial.length() | try expect_equal(0)

    let empty = Map[String, Counter]()
    let fold = empty.fold[List[String]]

    var untouched = fold(
        step: (
            fn acc,
            k,
            v:
                empty_calls.append(1)
                return acc
        ),
        initial: initial.clone()
    )

    untouched.append("empty copy")
    initial.length() | try expect_equal(0)
    untouched | try expect_equal(["empty copy"])

    let success: Int!Counter = ok(2)
    var chain_1 = Map[String, Int]()
    chain_1.add("a", 3)

    let nested = (chain_1.fold(success, fn acc, k, v: acc.map(fn n: (n + v))))
    nested.get() | try expect_equal(5)
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
        fn k,
        v:
            visits.append(k.clone())
            return k == "a"
    ).get()
    (visits != ["b", "a"] or found.key != "a" or found.value.calls != 1) | try expect_false

    var source = Map[String, Counter]()
    source.add("b", counter.clone())

    let find = source.clone().find
    var original = find(fn k, v: true).get().clone()
    var edited = original.value.clone()
    edited.calls = 5
    counter.calls | try expect_equal(2)
    original.key = "other"
    original.value = Counter(9)
    (not (source.contains("b")) or source["b"].calls != 2) | try expect_false
    try expect_equal(source.find(fn k, v: true).get().key, "b")
    try expect_true((source.find(fn k, v: false).is_none()))

    let empty = Map[String, Counter]()
    try expect_false(
        not (
            empty
            .find(
                (
                    fn k,
                    v:
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
    let any_of = values.any
    try expect_false(
        (
            not (
                any_of(
                    fn k,
                    v:
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

    let every = values.all
    try expect_false(
        (
            every(
                predicate: fn k,
                v:
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
        values.any(
            (
                fn k,
                v:
                    empty_calls.append(1)
                    return false
            )
        )
    )
    try expect_true(
        (
            values.all(
                (
                    fn k,
                    v:
                        empty_calls.append(1)
                        return true
                )
            )
        )
    )

    let complete: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    try expect_false(
        (complete.any(fn k, v: false) or not (complete.all(fn k, v: true)))
    )
    empty_calls.is_empty() | try expect_true

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Key) Bool:
        return self.id == other.id

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
        fn acc,
        v:
            var next = acc
            next.append(v.label.clone())
            return next
    )

    visits | try expect_equal(["b", "a", "c"])
    visits.append("copy")
    initial.length() | try expect_equal(0)

    let bound_empty = Set[Key]().fold[List[String]]

    var empty_result = bound_empty(
        initial.clone(),
        (
            fn acc,
            v:
                empty_calls.append(1)
                return acc
        )
    )

    empty_result.append("empty copy")
    initial.length() | try expect_equal(0)
    values.clear()
    values.add(b.clone())
    values.add(a.clone())
    values.add(c.clone())

    var seen: List[Int] = []
    let find = values.clone().find
    var found = find(
        fn v:
            seen.append(v.id)
            return v.id == 1
    ).get().clone()
    seen | try expect_equal([2, 1])
    found.label = "found"
    a.label | try expect_equal("a")
    values.clear()
    try expect_false(
        not (
            values
            .find(
                (
                    fn v:
                        empty_calls.append(1)
                        return false
                )
            )
            .is_none()
        )
    )

    let flags = Set[Bool]([false])
    try expect_false(flags.find(fn v: true).get())
    empty_calls.is_empty() | try expect_true

test "Set predicates short circuit over snapshots and keep empty identities":
    var empty_calls: List[Int] = []
    var values = Set[Int]([2, 1, 3])
    var seen: List[Int] = []
    let any_of = values.any
    try expect_false(
        (
            not (
                any_of(
                    fn v:
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

    let every = values.all
    try expect_false(
        (
            every(
                fn v:
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
        values.any(
            (
                fn v:
                    empty_calls.append(1)
                    return false
            )
        )
    )
    try expect_true(
        (
            values.all(
                (
                    fn v:
                        empty_calls.append(1)
                        return true
                )
            )
        )
    )

    let complete = Set[Int]([2, 1])
    try expect_false(complete.any(fn v: false) or not (complete.all(fn v: true)))
    try expect_true((complete.find(fn v: false).is_none()))
    empty_calls.is_empty() | try expect_true

test "nonmatching queries and all-true predicates visit the complete snapshot":
    let map: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    var map_visits: List[String] = []
    try expect_false(
        (
            map.any(
                fn k,
                v:
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
                map.all(
                    fn k,
                    v:
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
                    fn k,
                    v:
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
            set.any(
                fn v:
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
                set.all(
                    fn v:
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
                    fn v:
                        set_visits.append(v)
                        return false
                )
                .is_none()
            )
            or set_visits != [2, 1, 3]
        )
    )

fn find_port(port: Int?) Int!:
    let value = try port.ok_or()
    return ok(value)

test "ok_or without a cause records the calling file and line":
    let absent: Int? = none
    let direct: Int! = absent.ok_or()
    (direct.err().message.contains("conversions-queries.ms:")) | try expect_true

    let message = find_port(none).err().message
    (message.starts_with("missing value at ")) | try expect_true
    find_port(8080).get() | try expect_equal(8080)

    let named: Int!Error = absent.ok_or(Error("port"))
    named.err().message | try expect_equal("port")

    let missing_port = find_port(none)
    missing_port.err().kind | try expect_equal(ErrorCategory.NotFound)
