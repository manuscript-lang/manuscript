import panic from "@std/faults.ms"
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
    if not (success.is_ok()) or success.is_error(): return panic("Result predicates")
    if success.unwrap() != 2 or failure.unwrap_error() != "failed": return panic(
        "Result extraction"
    )
    if failure.unwrap_or(7) != 7: return panic("Result fallback")
    if failure.unwrap_or_else(
        fn(cause): cause.scalar_length()
    ) != 6: return panic("Result lazy fallback")
    if success.map(
        fn(n): n + 1
    ).unwrap() != 3: return panic("Result map")

    let chained: Result[String, String] = success.and_then(
        fn(n): ok(n.toString())
    )
    if chained.unwrap() != "2": return panic("Result and_then")

    let present: Optional[Int] = some(2)
    let missing: Optional[Int] = none
    if present.map(
        fn(n): n + 1
    ).unwrap() != 3: return panic("Optional map")
    if present.and_then(
        fn(n): some(n.toString())
    ).unwrap() != "2": return panic("Optional and_then")
    if missing.or_else(
        fn(): some(4)
    ).unwrap() != 4: return panic("Optional or_else")

    let values: Map[String, Int] = {"a": 1, "b": 2}
    if values.is_empty() or values.get_or("absent", 8) != 8: return panic("Map lookup")
    if values.filter(
        fn(k, v): k == "b" and v == 2
    ).length() != 1: return panic("Map filter")

    let members = Set[Int]().with_value(2).with_value(3)
    if members.is_empty() or members.filter(
        fn(n): n == 2
    ).length() != 1: return panic("Set filter")
    if members.map(
        fn(n): n.toString()
    ).values() != ["2", "3"]: return panic("Set map")

test "Result preserves unconstrained payloads and success-only composition":
    let counter = Counter(0)
    let failure: Result[Int, Counter] = error(counter)
    let success: Result[Int, Counter] = ok(0)
    let transform = fn(value: Int) -> String:
        counter.calls = counter.calls + 1
        return value.toString()
    let skipped = map_result(failure, transform)
    if (
        not (skipped.is_error())
        or skipped.is_ok()
        or counter.calls != 0
    ):
        return panic("map invoked on error")

    skipped.unwrap_error().calls = 2
    if counter.calls != 2: return panic("map copied error payload")

    let mapped = success.map(transform: transform)
    if mapped.unwrap() != "0" or counter.calls != 3: return panic("map success")

    let chain = fn(value: Int) -> Result[String, Counter]:
        counter.calls = counter.calls + 1
        return error(counter)
    let propagated = chain_result(failure, chain)
    if counter.calls != 3: return panic("and_then invoked on error")

    propagated.unwrap_error().calls = 4
    if counter.calls != 4: return panic("and_then copied original error")

    let produced = success.and_then(chain)
    if counter.calls != 5: return panic("and_then success callback count")

    produced.unwrap_error().calls = 6
    if counter.calls != 6: return panic("and_then copied callback error")

    let collection_error: Result[Bool, List[Int]] = error([1])
    collection_error.map(
        fn(flag): not flag
    ).unwrap_error().append(2)
    if collection_error.unwrap_error() != [1, 2]: return panic("unconstrained error")

    let limits = JsonLimits(max_bytes: -1)
    let record: Result[JsonLimits, String] = ok(limits)
    record.map(
        fn(value): value
    ).unwrap().max_values = some(7)
    if limits.max_values.unwrap() != 7: return panic("map normalized or copied payload")

    let nested = success.map(
        fn(n): some(n)
    )
    if nested.unwrap().unwrap() != 0: return panic("Result map flattened success")

    let unit_result: Result[Unit, Bool] = ok(unit)
    if not (unit_result.is_ok()): return panic("unit success")

    let bool_result: Result[Bool, String] = ok(false)
    if bool_result.unwrap_or(true): return panic("false success absent")

test "Result fallbacks are eager or lazy and bound methods keep receivers":
    let counter = Counter(0)
    let success: Result[Int, Counter] = ok(0)
    let failure: Result[Int, Counter] = error(counter)
    if success.unwrap_or(bump(counter)) != 0 or counter.calls != 1:
        return panic("eager fallback evaluation")

    let create = fn(cause: Counter) -> Int:
        cause.calls = cause.calls + 1
        return 12
    let lazy = success.unwrap_or_else
    if lazy(create: create) != 0 or counter.calls != 1: return panic(
        "success lazy fallback"
    )
    if failure.unwrap_or_else(create) != 12 or counter.calls != 2: return panic(
        "error lazy fallback"
    )

    let extract = failure.unwrap_error
    extract().calls = 3
    if counter.calls != 3: return panic("bound extraction identity")

    let bound_map = success.map[String]
    let bound_chain = success.and_then[String]
    if bound_map(
        fn(n): n.toString()
    ).unwrap() != "0": return panic("bound Result map")
    if bound_chain(
        fn(n): ok(n.toString())
    ).unwrap() != "0": return panic("bound Result chain")

test "Optional composition keeps nesting identity and lazy callback counts":
    let counter = Counter(0)
    let present: Optional[Counter] = some(counter)
    let missing: Optional[Counter] = none
    let transform = fn(value: Counter) -> Counter:
        value.calls = value.calls + 1
        return value
    if not (map_optional(missing, transform).is_none()) or counter.calls != 0:
        return panic("none mapped")

    let mapped = present.map(transform)
    if counter.calls != 1: return panic("Optional map callback count")

    mapped.unwrap().calls = 2
    if counter.calls != 2: return panic("Optional map identity")

    let chained = present.and_then(
        fn(value): some(value)
    )
    chained.unwrap().calls = 3
    if counter.calls != 3: return panic("Optional and_then identity")

    let absent = present.and_then(
        fn(unused): Optional[Int].none
    )
    if not (absent.is_none()): return panic("and_then wrapped none")

    let create = fn() -> Optional[Counter]:
        counter.calls = counter.calls + 1
        return some(counter)
    let bound = present.or_else
    bound(create).unwrap().calls = 4
    if counter.calls != 4: return panic("or_else called on some")

    let fallback = missing.or_else(create)
    if counter.calls != 5: return panic("or_else callback count")

    fallback.unwrap().calls = 6
    if counter.calls != 6: return panic("or_else copied payload")

    let nested = present.map(
        fn(unused): Optional[Int].none
    )
    if not (nested.is_some()) or not (nested.unwrap().is_none()): return panic(
        "map flattened Optional"
    )

    let bound_map = present.map[String]
    if bound_map(
        fn(value): value.calls.toString()
    ).unwrap() != "6": return panic("bound Optional map")

    let bound_chain = missing.and_then[String]
    if not (
        bound_chain(
            fn(unused): some("unexpected")
        ).is_none()
    ): return panic("bound Optional chain")

test "Map filter copies ordered membership and get_or never inserts":
    let counter = Counter(0)
    let values: Map[String, Counter] = {"b": counter, "a": Counter(2), "c": Counter(3)}
    let selected = values.filter(
        predicate: fn(k, v): k != "a" and v.calls >= 0
    )
    if selected.keys() != ["b", "c"] or values.length() != 3: return panic(
        "Map order or mutation"
    )

    selected.get_or(
        key: "b",
        fallback: Counter(9)
    ).calls = 7
    if counter.calls != 7: return panic("Map filter copied payload")

    selected.without("b").with_entry(
        "d",
        Counter(4)
    )
    if values.keys() != ["b", "a", "c"]: return panic("Map filter aliased storage")

    let fallback = Counter(8)
    let lookup = values.get_or
    lookup(fallback: fallback, key: "absent").calls = 9
    if fallback.calls != 9 or values.contains("absent"): return panic(
        "get_or inserted or copied"
    )
    if Map[String, Int]().get_or(
        "absent",
        bump(counter)
    ) != 9 or counter.calls != 8:
        return panic("get_or fallback evaluation")

    let empty = values.filter(
        fn(unused_key, unused_value): false
    )
    if not (empty.is_empty()): return panic("Map empty filter")

    empty.with_entry("new", counter)
    if values.contains("new"): return panic("empty Map filter aliased")

    let bound_filter = values.filter
    if bound_filter(
        fn(k, v): k == "a"
    ).keys() != ["a"]: return panic("bound Map filter")

    let snapshot: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    let visits: List[String] = []
    let copied = snapshot.filter(
        fn(k, v):
            visits.append(k)
            snapshot.clear().with_entry("new", 9)
            return v != 1
    )
    if (
        visits != ["b", "a", "c"]
        or copied.keys() != ["b", "c"]
        or copied.values() != [2, 3]
    ):
        return panic("Map callback did not traverse snapshot")

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
    let values = Set[Int]().with_value(3).with_value(1).with_value(2)
    let visits: List[Int] = []
    let copied = values.filter(
        fn(n):
            visits.append(n)
            values.clear().with_value(9)
            return n != 1
    )
    if visits != [3, 1, 2] or copied.values() != [3, 2]: return panic(
        "Set filter snapshot"
    )

    copied.without(3).with_value(8)
    if values.values() != [9]: return panic("Set filter aliased storage")

    let bound_filter = copied.filter
    if bound_filter(
        fn(n): n == 8
    ).values() != [8]: return panic("bound Set filter")

    let input = Set[Int]().with_value(2).with_value(3).with_value(4)
    let mapped = map_set(
        input,
        fn(n): Key(
            n % 2,
            n.toString()
        )
    )
    if (
        mapped.length() != 2
        or mapped.values().at(0).unwrap().label != "2"
        or mapped.values().at(1).unwrap().label != "3"
    ):
        return panic("Set map hashing or order")

    let bound = input.map[String]
    let mapped_snapshot = bound(
        transform: fn(n):
            input.without(n).with_value(7)
            return n.toString()
    )
    if mapped_snapshot.values() != ["2", "3", "4"] or input.values() != [7]: return panic(
        "Set map snapshot"
    )

    mapped_snapshot.with_value("8")
    if input.length() != 1: return panic("Set map aliased storage")

    let key = Key(5, "shared")
    let keys = Set[Key]().with_value(key)
    keys.filter(
        fn(unused): true
    ).values().at(0).unwrap().label = "changed"
    keys.map(
        fn(value): value
    ).values().at(0).unwrap().label = "again"
    if key.label != "again": return panic("Set copied payloads")
    if not (
        Set[Int]()
        .map(
            fn(n): n.toString()
        )
        .is_empty()
    ): return panic("empty mapped set")
    if not (
        keys
        .filter(
            fn(unused): false
        )
        .is_empty()
    ): return panic("empty filtered set")
