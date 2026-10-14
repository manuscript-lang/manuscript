import {Map, Set, List, MapEntry} from "@std/collections.ms"
import panic from "@std/faults.ms"
import {Equal, Hashable} from "@std/equality.ms"
import MissingValue from "@std/errors.ms"

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
    if present.ok_or("absent").unwrap() != 2: return panic("Optional eager conversion")
    if missing.ok_or_else(fn(): "absent").unwrap_error() != "absent": return panic(
        "Optional lazy conversion"
    )

    let failed: Result[Int, String] = error("failed")
    if not (failed.to_optional().is_none()): return panic("Result conversion")

    let entries: Map[String, Int] = {"b": 2, "a": 1}
    if entries.fold(0, fn(acc, k, v): acc + v) != 3: return panic("Map fold")
    if entries.find(fn(k, v): v == 1).unwrap().key != "a": return panic("Map find")
    if not (entries.some(fn(k, v): v == 1)): return panic("Map some")
    if not (entries.every(fn(k, v): v > 0)): return panic("Map every")

    let values = Set[Int]().add(2).add(1)
    if values.fold(0, fn(acc, n): acc + n) != 3: return panic("Set fold")
    if values.find(fn(n): n == 1).unwrap() != 1: return panic("Set find")
    if not (values.some(fn(n): n == 1)): return panic("Set some")
    if not (values.every(fn(n): n > 0)): return panic("Set every")

test "conversions retain unconstrained payloads nesting and lazy counts":
    let counter = Counter(0)
    let present: Optional[Int] = some(0)
    let missing: Optional[Int] = none
    if require_value(present, counted(counter)).unwrap() != 0 or counter.calls != 1:
        return panic("eager conversion skipped cause expression")

    let cause = require_value(missing, counter).unwrap_error()
    cause.calls = 2
    if counter.calls != 2: return panic("conversion copied error")

    let create = fn() -> Counter: counted(counter)
    if require_lazy(present, create).unwrap() != 0 or counter.calls != 2:
        return panic("present invoked lazy error construction")

    let error_result = require_lazy(missing, create)
    if counter.calls != 3: return panic("lazy error construction must run once")

    error_result.unwrap_error().calls = 4
    if counter.calls != 4: return panic("lazy conversion copied cause")

    let bound = missing.ok_or[Counter]
    bound(cause: counter).unwrap_error().calls = 5
    if counter.calls != 5: return panic("bound eager conversion lost receiver")

    let bound_lazy = missing.ok_or_else[Counter]
    if bound_lazy(create).unwrap_error().calls != 6: return panic(
        "bound lazy conversion"
    )

    let failure: Result[Counter, List[Int]] = error([1, 2])
    if not (success_only(failure).is_none()): return panic(
        "unconstrained error conversion"
    )

    let success: Result[Counter, Bool] = ok(counter)
    let extract = success.to_optional
    extract().unwrap().calls = 7
    if counter.calls != 7: return panic("Result conversion copied success")

    let nested: Optional[Optional[Int]] = some(none)
    let converted = nested.ok_or("absent")
    if not (converted.is_ok()) or not (converted.to_optional().unwrap().is_none()):
        return panic("conversion flattened nested Optional")

    let false_value: Optional[Bool] = some(false)
    if false_value.ok_or(unit).to_optional().unwrap(): return panic(
        "false payload changed"
    )

    let unit_value: Optional[Unit] = some(unit)
    if not (unit_value.ok_or(false).to_optional().is_some()): return panic(
        "Unit payload disappeared"
    )

    let nested_result: Optional[Result[Int, String]] = some(error("nested"))
    if nested_result.ok_or(false).to_optional().unwrap().unwrap_error() != "nested":
        return panic("conversion flattened nested Result")

test "Map fold uses ordered snapshots and returns accumulator aliases":
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
    if visits != ["b2", "a1", "c7"] or initial != visits:
        return panic("Map fold snapshot order or shallow references")

    visits.append("alias")
    if initial.length() != 4: return panic("Map fold copied accumulator")

    let empty = Map[String, Counter]()
    let fold = empty.fold[List[String]]
    let untouched = fold(
        step: fn(acc, k, v): panic("empty fold callback"),
        initial: initial
    )
    untouched.append("empty alias")
    if initial.length() != 5: return panic("empty fold changed initial identity")

    let success: Result[Int, Counter] = ok(2)
    let nested = (
        Map[String, Int]()
        .add("a", 3)
        .fold(success, fn(acc, k, v): acc.map(fn(n): (n + v)))
    )
    if nested.unwrap() != 5: return panic("fold flattened Result accumulator")

test "Map find returns fresh entry shells with original payload references":
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
    if (visits != ["b", "a"] or found.key != "a" or found.value.calls != 1):
        return panic("Map find order snapshot or short circuit")

    let source = Map[String, Counter]().add("b", counter)
    let find = source.find
    let original = find(fn(k, v): true).unwrap()
    original.value.calls = 5
    if counter.calls != 5: return panic("Map find copied payload")

    original.key = "other"
    original.value = Counter(9)
    if not (source.contains("b")) or source.get("b").unwrap().calls != 5:
        return panic("Map entry shell aliased source storage")
    if source.find(fn(k, v): true).unwrap().key != "b": return panic(
        "find reused entry shell"
    )
    if not (source.find(fn(k, v): false).is_none()): return panic("missing Map match")

    let empty = Map[String, Counter]()
    if not (empty.find(fn(k, v): panic("empty Map find callback")).is_none()): return panic(
        "empty Map find"
    )

test "Map predicates short circuit over snapshots including empty receivers":
    let values: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    let seen: List[String] = []
    let some = values.some
    if (
        not (
            some(
                fn(k, v):
                    seen.append(k)
                    values.remove("a").add("c", 99).add("new", 4)
                    return v == 1
            )
        )
        or seen != ["b", "a"]
    ): return panic("Map some snapshot or short circuit")

    values.clear().add("b", 2).add("a", 1).add("c", 3)
    seen.splice(0, seen.length(), [])
    let every = values.every
    if (
        every(
            predicate: fn(k, v):
                seen.append(k)
                values.remove("a").add("c", 99).add("new", 4)
                return v > 1
        )
        or seen != ["b", "a"]
    ): return panic("Map every snapshot or short circuit")

    values.clear()
    if values.some(fn(k, v): panic("empty Map some callback")): return panic(
        "empty Map some"
    )
    if not (values.every(fn(k, v): panic("empty Map every callback"))): return panic(
        "empty Map every"
    )

    let complete: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    if complete.some(fn(k, v): false) or not (complete.every(fn(k, v): true)):
        return panic("Map terminal predicate result")

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
    if visits != ["b", "a", "shared"]: return panic(
        "Set fold snapshot or shallow references"
    )

    visits.append("alias")
    if initial.length() != 4: return panic("Set fold copied initial")

    let bound_empty = Set[Key]().fold[List[String]]
    bound_empty(initial, fn(acc, v): panic("empty Set fold callback")).append(
        "empty alias"
    )
    if initial.length() != 5: return panic("empty Set fold changed initial identity")

    values.clear().add(b).add(a).add(c)
    let seen: List[Int] = []
    let find = values.find
    let found = find(
        fn(v):
            seen.append(v.id)
            values.remove(a).add(Key(4, "new"))
            return v.id == 1
    ).unwrap()
    if seen != [2, 1]: return panic("Set find snapshot or short circuit")

    found.label = "found"
    if a.label != "found": return panic("Set find copied payload")

    values.clear()
    if not (values.find(fn(v): panic("empty Set find callback")).is_none()): return panic(
        "empty Set find"
    )

    let flags = Set[Bool]().add(false)
    if flags.find(fn(v): true).unwrap(): return panic("false match disappeared")

test "Set predicates short circuit over snapshots and keep empty identities":
    let values = Set[Int]().add(2).add(1).add(3)
    let seen: List[Int] = []
    let some = values.some
    if (
        not (
            some(
                fn(v):
                    seen.append(v)
                    values.remove(1).add(4)
                    return v == 1
            )
        )
        or seen != [2, 1]
    ): return panic("Set some snapshot or short circuit")

    values.clear().add(2).add(1).add(3)
    seen.splice(0, seen.length(), [])
    let every = values.every
    if (
        every(
            fn(v):
                seen.append(v)
                values.remove(1).add(4)
                return v > 1
        )
        or seen != [2, 1]
    ): return panic("Set every snapshot or short circuit")

    values.clear()
    if values.some(fn(v): panic("empty Set some callback")): return panic(
        "empty Set some"
    )
    if not (values.every(fn(v): panic("empty Set every callback"))): return panic(
        "empty Set every"
    )

    let complete = Set[Int]().add(2).add(1)
    if complete.some(fn(v): false) or not (complete.every(fn(v): true)):
        return panic("Set terminal predicate result")
    if not (complete.find(fn(v): false).is_none()): return panic("missing Set match")

test "nonmatching queries and all-true predicates visit the complete snapshot":
    let map: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    let map_visits: List[String] = []
    if (
        map.some(
            fn(k, v):
                map_visits.append(k)
                return false
        )
        or map_visits != ["b", "a", "c"]
    ): return panic("Map some stopped without a match")

    map_visits.splice(0, map_visits.length(), [])
    if (
        not (
            map.every(
                fn(k, v):
                    map_visits.append(k)
                    return true
            )
        )
        or map_visits != ["b", "a", "c"]
    ): return panic("Map every stopped without a failure")

    map_visits.splice(0, map_visits.length(), [])
    if (
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
    ): return panic("Map find stopped without a match")

    let set = Set[Int]().add(2).add(1).add(3)
    let set_visits: List[Int] = []
    if set.some(
        fn(v):
            set_visits.append(v)
            return false
    ) or set_visits != [2, 1, 3]: return panic("Set some stopped without a match")

    set_visits.splice(0, set_visits.length(), [])
    if (
        not (
            set.every(
                fn(v):
                    set_visits.append(v)
                    return true
            )
        )
        or set_visits != [2, 1, 3]
    ): return panic("Set every stopped without a failure")

    set_visits.splice(0, set_visits.length(), [])
    if (
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
    ): return panic("Set find stopped without a match")

fn find_port(port: Optional[Int]) -> Result[Int, Error]:
    let value = try port.ok_or()
    return ok(value)

test "ok_or without a cause records the calling file and line":
    let absent: Optional[Int] = none
    let direct: Result[Int, MissingValue] = absent.ok_or()
    if not (direct.unwrap_error().message().contains("conversions-queries.ms:")): return panic(
        "missing location"
    )

    let message = find_port(none).unwrap_error().message()
    if not (message.starts_with("missing value at ")): return panic(message)
    if find_port(some(8080)).unwrap() != 8080: return panic("present payload")

    let named: Result[Int, String] = absent.ok_or("port")
    if named.unwrap_error() != "port": return panic("explicit cause")

    match find_port(none).unwrap_error():
        MissingValue(found): unit
        _: return panic("default cause is not MissingValue")
