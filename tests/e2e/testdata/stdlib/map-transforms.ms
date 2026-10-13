import {Map, Set, List} from "@std/collections.ms"
import panic from "@std/faults.ms"
import {Equal, Hashable} from "@std/equality.ms"

type Counter:
    count: Int

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

fn map_values[K: Hashable, V, W](
    values: Map[K, V],
    transform: fn(key: K, value: V) -> W
) -> Map[K, W]:
    return values.map[W](transform)

fn map_keys[K: Hashable, V, W: Hashable](
    values: Map[K, V],
    transform: fn(key: K, value: V) -> W
) -> Map[W, V]:
    return values.map_keys[W](transform)

fn reverse_map[K: Hashable, V, A](
    values: Map[K, V],
    initial: A,
    step: fn(accumulator: A, key: K, value: V) -> A
) -> A:
    return values.fold_right[A](initial, step)

fn reverse_set[T: Hashable, A](
    values: Set[T],
    initial: A,
    step: fn(accumulator: A, value: T) -> A
) -> A:
    return values.fold_right(initial, step)

test "Map transformations and directional queries are callable":
    let source: Map[String, Int] = {"b": 2, "a": 1}
    let mapped = source.map(
        fn(k, v): v.toString()
    )
    if mapped.get("b").unwrap() != "2": return panic("Map value transformation")

    let keyed = source.map_keys(
        fn(k, v): v
    )
    if keyed.get(2).unwrap() != 2: return panic("Map key transformation")
    if source.find_last(
        fn(k, v): true
    ).unwrap().key != "a": return panic("Map find_last")
    if source.fold_right(
        "",
        fn(acc, k, v): acc + k
    ) != "ab": return panic("Map fold_right")

    let values = Set[Int]().with_value(2).with_value(1)
    if values.find_last(
        fn(v): true
    ).unwrap() != 1: return panic("Set find_last")
    if values.fold_right(
        "",
        fn(acc, v): acc + v.toString()
    ) != "12": return panic("Set fold_right")

test "Map value transformation copies ordered snapshots and retains aliases":
    let first = Key(2, "b")
    let second = Key(1, "a")
    let third = Key(3, "c")
    let counter = Counter(2)
    let source = (
        Map[Key, Counter]()
        .with_entry(first, counter)
        .with_entry(
            second,
            Counter(1)
        )
        .with_entry(
            third,
            Counter(3)
        )
    )
    let seen: List[String] = []
    let mapped = map_values(
        source,
        fn(k, v):
            seen.append(k.label + v.count.toString())
            (
                source.without(second).with_entry(
                    third,
                    Counter(99)
                ).with_entry(
                    Key(4, "new"),
                    Counter(4)
                )
            )
            return v
    )
    if seen != ["b2", "a1", "c3"]: return panic(
        "Map.map did not snapshot membership and values"
    )
    if mapped.keys().map(
        fn(k): k.id
    ) != [2, 1, 3]: return panic("Map.map key order")

    mapped.get(first).unwrap().count = 7
    if counter.count != 7 or source.get(first).unwrap().count != 7: return panic(
        "Map.map copied payload"
    )

    mapped.keys().at(0).unwrap().label = "shared"
    if first.label != "shared": return panic("Map.map copied keys")

    mapped.without(first).with_entry(
        Key(5, "other"),
        Counter(5)
    )
    if not (source.contains(first)) or source.contains(Key(5, "different")): return panic(
        "Map.map aliased outer storage"
    )

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
            let key = Key(
                k % 2,
                k.toString()
            )
            created.append(key)
            return key
    )
    if created.length() != 4 or mapped.length() != 2: return panic(
        "Map.map_keys callback or collision count"
    )
    if mapped.keys().map(
        fn(k): k.label
    ) != ["2", "1"]: return panic("first transformed key identity/order")
    if mapped.values().map(
        fn(v): v.count
    ) != [3, 4]: return panic("last colliding input value")

    mapped.keys().at(0).unwrap().label = "first alias"
    if (
        created.at(0).unwrap().label != "first alias"
        or created.at(2).unwrap().label != "4"
    ):
        return panic("map_keys did not retain first key reference")

    mapped.get(Key(0, "lookup")).unwrap().count = 9
    if three.count != 9: return panic("map_keys copied retained value")

    mapped.clear().with_entry(
        Key(7, "fresh"),
        Counter(10)
    )
    if source.length() != 4: return panic("map_keys aliased source storage")

test "Map key transformation snapshots callbacks and keeps generic nesting":
    let later = Counter(3)
    let source: Map[Int, Counter] = {2: Counter(2), 1: Counter(1), 3: later}
    let seen: List[Int] = []
    let bound = source.map_keys[String]
    let mapped = bound(
        transform: fn(k, v):
            seen.append(k)
            source.without(1).with_entry(
                3,
                Counter(99)
            ).with_entry(
                4,
                Counter(4)
            )
            later.count = 7
            return k.toString()
    )
    if seen != [2, 1, 3] or mapped.keys() != ["2", "1", "3"]: return panic(
        "map_keys mutation snapshot"
    )
    if mapped.get("3").unwrap().count != 7: return panic(
        "map_keys deep copied snapshot values"
    )

    let values: Map[String, Int] = {"a": 0}
    let map = values.map[Optional[Int]]
    if not (
        map(
            fn(k, v): none
        )
        .get("a")
        .unwrap()
        .is_none()
    ): return panic("Map.map flattened Optional")

    let nested = values.map(
        fn(k, v): Result[Int, String].error("nested")
    )
    if nested.get("a").unwrap().unwrap_error() != "nested": return panic(
        "Map.map flattened Result"
    )

test "empty transformations skip callbacks and allocate independent storage":
    let source = Map[String, Int]()
    let mapped = source.map[Counter](
        fn(k, v): panic("empty value transform callback")
    )
    mapped.with_entry(
        "new",
        Counter(1)
    )
    if not (source.is_empty()): return panic("empty value transform aliased source")

    let keyed = source.map_keys[Key](
        fn(k, v): panic("empty key transform callback")
    )
    keyed.with_entry(
        Key(1, "new"),
        1
    )
    if not (source.is_empty()): return panic("empty key transform aliased source")

test "Map reverse fold and last match retain ordered shallow snapshots":
    let first = Counter(2)
    let source: Map[String, Counter] = {"b": first, "a": Counter(1), "c": Counter(3)}
    let initial: List[String] = []
    let folded = reverse_map(
        source,
        initial,
        fn(acc, k, v):
            (
                source
                .without("a")
                .with_entry(
                    "b",
                    Counter(99)
                )
                .with_entry(
                    "new",
                    Counter(4)
                )
            )
            first.count = 7
            acc.append(k + v.count.toString())
            return acc
    )
    if folded != ["c3", "a1", "b7"]: return panic(
        "Map.fold_right snapshot or direction"
    )

    folded.append("alias")
    if initial.length() != 4: return panic("Map.fold_right copied accumulator")

    let original = Counter(1)
    (
        source.clear().with_entry(
            "b",
            Counter(2)
        ).with_entry("a", original).with_entry(
            "c",
            Counter(3)
        )
    )
    let seen: List[String] = []
    let find = source.find_last
    let found = find(
        predicate: fn(k, v):
            seen.append(k)
            (
                source.without("a").with_entry(
                    "b",
                    Counter(99)
                ).with_entry(
                    "new",
                    Counter(4)
                )
            )
            return k == "a"
    ).unwrap()
    if seen != ["c", "a"] or found.key != "a": return panic(
        "Map.find_last snapshot or short circuit"
    )

    found.value.count = 8
    if original.count != 8: return panic("Map.find_last copied payload")

    found.key = "changed"
    if source.contains("changed"): return panic(
        "Map.find_last entry shell aliased source"
    )

test "Set reverse fold and last match preserve references and callbacks":
    let b = Key(2, "b")
    let a = Key(1, "a")
    let c = Key(3, "c")
    let source = Set[Key]().with_value(b).with_value(a).with_value(c)
    let initial: List[String] = []
    let folded = reverse_set(
        source,
        initial,
        fn(acc, v):
            source.without(a).with_value(Key(4, "new"))
            b.label = "shared"
            acc.append(v.label)
            return acc
    )
    if folded != ["c", "a", "shared"]: return panic(
        "Set.fold_right snapshot or direction"
    )

    folded.append("alias")
    if initial.length() != 4: return panic("Set.fold_right copied accumulator")

    source.clear().with_value(b).with_value(a).with_value(c)
    let seen: List[Int] = []
    let find = source.find_last
    let found = find(
        fn(v):
            seen.append(v.id)
            source.without(a).with_value(Key(4, "new"))
            return v.id == 1
    ).unwrap()
    if seen != [3, 1]: return panic("Set.find_last snapshot or short circuit")

    found.label = "found"
    if a.label != "found": return panic("Set.find_last copied payload")

test "empty and nonmatching reverse queries keep fold and predicate contracts":
    let initial: List[Int] = []
    let empty_map = Map[String, Int]()
    let empty_set = Set[Int]()
    let map_fold = empty_map.fold_right[List[Int]]
    map_fold(
        step: fn(acc, k, v): panic("empty Map.fold_right callback"),
        initial: initial
    ).append(1)
    let set_fold = empty_set.fold_right[List[Int]]
    set_fold(
        initial,
        fn(acc, v): panic("empty Set.fold_right callback")
    ).append(2)
    if initial != [1, 2]: return panic("empty reverse fold initial identity")
    if not (
        empty_map
        .find_last(
            fn(k, v): panic("empty Map.find_last callback")
        )
        .is_none()
    ): return panic("empty Map.find_last")
    if not (
        empty_set
        .find_last(
            fn(v): panic("empty Set.find_last callback")
        )
        .is_none()
    ): return panic("empty Set.find_last")

    let values: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    let seen_map: List[String] = []
    if (
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
    ): return panic("complete reverse Map search")

    let members = Set[Int]().with_value(2).with_value(1).with_value(3)
    let seen_set: List[Int] = []
    if (
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
    ): return panic("complete reverse Set search")
