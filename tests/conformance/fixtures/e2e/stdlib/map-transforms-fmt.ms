# conform: tags=aliasing,closures,control-flow,faults,formatter,generics,interfaces,lists,maps,match,modules,optional,parser,records,sets,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/map-transforms.ms
import {TextError} from "@std/errors.ms"
import {expect_equal, expect_false, expect_true} from "@std/testing.ms"

type Counter:
    count: Int

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

fn map_values[K: Hashable, V, W](
    values: Map[K, V],
    transform: fn(key: K, value: V) W
) Map[K, W]:
    return values.map[W](transform)

fn map_keys[K: Hashable, V, W: Hashable](
    values: Map[K, V],
    transform: fn(key: K, value: V) W
) Map[W, V]:
    return values.map_keys[W](transform)

fn reverse_map[K: Hashable, V, A](
    values: Map[K, V],
    initial: A,
    step: fn(accumulator: A, key: K, value: V) A
) A:
    return values.fold_right[A](initial, step)

fn reverse_set[T: Hashable, A](
    values: Set[T],
    initial: A,
    step: fn(accumulator: A, value: T) A
) A:
    return values.fold_right(initial, step)

test "Map transformations and directional queries are callable":
    let source: Map[String, Int] = {"b": 2, "a": 1}
    let mapped = source.map(fn(k, v): v.to_string())
    mapped.get("b").get() | try expect_equal(expected: "2")
    let keyed = source.map_keys(fn(k, v): v)
    keyed.get(2).get() | try expect_equal(expected: 2)
    try expect_equal(source.find_last(fn(k, v): true).get().key, "a")
    try expect_equal(source.fold_right("", fn(acc, k, v): acc + k), "ab")
    let values = Set[Int]([2, 1])
    try expect_equal(values.find_last(fn(v): true).get(), 1)
    try expect_equal(values.fold_right("", fn(acc, v): acc + v.to_string()), "12")

test "Map value transformation copies ordered snapshots and retains aliases":
    let first = Key(2, "b")
    let second = Key(1, "a")
    let third = Key(3, "c")
    let counter = Counter(2)
    let source = (
        Map[Key, Counter]()
        .add(first, counter)
        .add(second, Counter(1))
        .add(third, Counter(3))
    )
    let seen: List[String] = []
    let mapped = map_values(
        source,
        fn(k, v):
            seen.append(k.label + v.count.to_string())
            (
                source.remove(second).add(third, Counter(99)).add(
                    Key(4, "new"),
                    Counter(4)
                )
            )
            return v
    )
    seen | try expect_equal(expected: ["b2", "a1", "c3"])
    try expect_equal(mapped.keys().map(fn(k): k.id), [2, 1, 3])
    mapped.get(first).get().count = 7
    (counter.count != 7 or source.get(first).get().count != 7) | try expect_false
    mapped.keys().get(0).label = "shared"
    first.label | try expect_equal(expected: "shared")
    mapped.remove(first).add(Key(5, "other"), Counter(5))
    (not (source.contains(first)) or source.contains(Key(5, "different"))) | try expect_false

test "Map key transformation retains first equal keys and last values":
    let one = Counter(1)
    let two = Counter(2)
    let three = Counter(3)
    let four = Counter(4)
    let source: Map[Int, Counter] = {2: one, 1: two, 4: three, 3: four}
    let created: List[Key] = []
    let mapped = map_keys(
        source,
        fn(k, v):
            let key = Key(k % 2, k.to_string())
            created.append(key)
            return key
    )
    (created.length() != 4 or mapped.length() != 2) | try expect_false
    try expect_equal(mapped.keys().map(fn(k): k.label), ["2", "1"])
    try expect_equal(mapped.values().map(fn(v): v.count), [3, 4])
    mapped.keys().get(0).label = "first alias"
    try expect_false(
        (created.get(0).label != "first alias" or created.get(2).label != "4")
    )
    mapped.get(Key(0, "lookup")).get().count = 9
    three.count | try expect_equal(expected: 9)
    mapped.clear().add(Key(7, "fresh"), Counter(10))
    source.length() | try expect_equal(expected: 4)

test "Map key transformation snapshots callbacks and keeps generic nesting":
    let later = Counter(3)
    let source: Map[Int, Counter] = {2: Counter(2), 1: Counter(1), 3: later}
    let seen: List[Int] = []
    let bound = source.map_keys[String]
    let mapped = bound(
        transform: fn(k, v):
            seen.append(k)
            source.remove(1).add(3, Counter(99)).add(4, Counter(4))
            later.count = 7
            return k.to_string()
    )
    (seen != [2, 1, 3] or mapped.keys() != ["2", "1", "3"]) | try expect_false
    mapped.get("3").get().count | try expect_equal(expected: 7)
    let values: Map[String, Int] = {"a": 0}
    let map = values.map[Optional[Int]]
    try expect_true((map(fn(k, v): none).get("a").get().is_none()))
    let nested = values.map(fn(k, v): Result[Int, TextError].error(TextError("nested")))
    nested.get("a").get().err().message() | try expect_equal(expected: "nested")

test "empty transformations skip callbacks and allocate independent storage":
    let empty_calls: List[Int] = []
    let source = Map[String, Int]()
    let mapped = source.map[Counter](
        (
            fn(k, v):
                empty_calls.append(1)
                return Counter(0)
        )
    )
    mapped.add("new", Counter(1))
    (source.is_empty()) | try expect_true
    let keyed = source.map_keys[Key](
        (
            fn(k, v):
                empty_calls.append(1)
                return Key(0, "unused")
        )
    )
    keyed.add(Key(1, "new"), 1)
    (source.is_empty()) | try expect_true
    empty_calls.is_empty() | try expect_true

test "Map reverse fold and last match retain ordered shallow snapshots":
    let first = Counter(2)
    let source: Map[String, Counter] = {"b": first, "a": Counter(1), "c": Counter(3)}
    let initial: List[String] = []
    let folded = reverse_map(
        source,
        initial,
        fn(acc, k, v):
            (source.remove("a").add("b", Counter(99)).add("new", Counter(4)))
            first.count = 7
            acc.append(k + v.count.to_string())
            return acc
    )
    folded | try expect_equal(expected: ["c3", "a1", "b7"])
    folded.append("alias")
    initial.length() | try expect_equal(expected: 4)
    let original = Counter(1)
    (source.clear().add("b", Counter(2)).add("a", original).add("c", Counter(3)))
    let seen: List[String] = []
    let find = source.find_last
    let found = find(
        predicate: fn(k, v):
            seen.append(k)
            (source.remove("a").add("b", Counter(99)).add("new", Counter(4)))
            return k == "a"
    ).get()
    (seen != ["c", "a"] or found.key != "a") | try expect_false
    found.value.count = 8
    original.count | try expect_equal(expected: 8)
    found.key = "changed"
    source.contains("changed") | try expect_false

test "Set reverse fold and last match preserve references and callbacks":
    let b = Key(2, "b")
    let a = Key(1, "a")
    let c = Key(3, "c")
    let source = Set[Key]([b, a, c])
    let initial: List[String] = []
    let folded = reverse_set(
        source,
        initial,
        fn(acc, v):
            source.remove(a).add(Key(4, "new"))
            b.label = "shared"
            acc.append(v.label)
            return acc
    )
    folded | try expect_equal(expected: ["c", "a", "shared"])
    folded.append("alias")
    initial.length() | try expect_equal(expected: 4)
    source.clear().add(b).add(a).add(c)
    let seen: List[Int] = []
    let find = source.find_last
    let found = find(
        fn(v):
            seen.append(v.id)
            source.remove(a).add(Key(4, "new"))
            return v.id == 1
    ).get()
    seen | try expect_equal(expected: [3, 1])
    found.label = "found"
    a.label | try expect_equal(expected: "found")

test "empty and nonmatching reverse queries keep fold and predicate contracts":
    let empty_calls: List[Int] = []
    let initial: List[Int] = []
    let empty_map = Map[String, Int]()
    let empty_set = Set[Int]()
    let map_fold = empty_map.fold_right[List[Int]]
    map_fold(
        step: (
            fn(acc, k, v):
                empty_calls.append(1)
                return acc
        ),
        initial: initial
    ).append(1)
    let set_fold = empty_set.fold_right[List[Int]]
    set_fold(
        initial,
        (
            fn(acc, v):
                empty_calls.append(1)
                return acc
        )
    ).append(2)
    initial | try expect_equal(expected: [1, 2])
    try expect_false(
        not (
            empty_map
            .find_last(
                (
                    fn(k, v):
                        empty_calls.append(1)
                        return false
                )
            )
            .is_none()
        )
    )
    try expect_false(
        not (
            empty_set
            .find_last(
                (
                    fn(v):
                        empty_calls.append(1)
                        return false
                )
            )
            .is_none()
        )
    )
    let values: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    let seen_map: List[String] = []
    try expect_false(
        (
            not (
                values
                .find_last(
                    fn(k, v):
                        seen_map.append(k)
                        return false
                )
                .is_none()
            )
            or seen_map != ["c", "a", "b"]
        )
    )
    let members = Set[Int]([2, 1, 3])
    let seen_set: List[Int] = []
    try expect_false(
        (
            not (
                members
                .find_last(
                    fn(v):
                        seen_set.append(v)
                        return false
                )
                .is_none()
            )
            or seen_set != [3, 1, 2]
        )
    )
    empty_calls.is_empty() | try expect_true
