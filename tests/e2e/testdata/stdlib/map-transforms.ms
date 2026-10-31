import TextError from "@std/core.ms"
import expect_equal, expect_false, expect_true from "@std/test.ms"

type Counter:
    count: Int

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Key) Bool:
        return self.id == other.id

impl Hashable for Key:
    fn hash() Int: 0

fn map_values[K: Hashable, V, W](values: Map[K, V], transform: fn(K, V) W) Map[K, W]:
    return values.map[W](transform)

fn map_keys[K: Hashable, V: Clonable, W: Hashable](
    values: Map[K, V],
    transform: fn(K, V) W
) Map[W, V]:
    return values.map_keys[W](transform)

fn reverse_map[K: Hashable, V, A](values: Map[K, V], initial: A, step: fn(A, K, V) A) A:
    return values.fold_right[A](initial, step)

fn reverse_set[T: Hashable, A](values: Set[T], initial: A, step: fn(A, T) A) A:
    return values.fold_right(initial, step)

test "Map transformations and directional queries are callable":
    let source: Map[String, Int] = {"b": 2, "a": 1}
    let mapped = source.map(fn k, v: v.to_string())
    mapped["b"] | try expect_equal("2")

    let keyed = source.map_keys(fn k, v: v)
    keyed[2] | try expect_equal(2)
    try expect_equal(source.find_last(fn k, v: true).get().key, "a")
    try expect_equal(source.fold_right("", fn acc, k, v: acc + k), "ab")

    let values = Set[Int]([2, 1])
    try expect_equal(values.find_last(fn v: true).get(), 1)
    try expect_equal(values.fold_right("", fn acc, v: acc + v.to_string()), "12")

test "Map value transformation copies ordered snapshots and keeps independent values":
    let first = Key(2, "b")
    let second = Key(1, "a")
    let third = Key(3, "c")
    var source = Map[Key, Counter]()
    source.add(first.clone(), Counter(2))
    source.add(second.clone(), Counter(1))
    source.add(third.clone(), Counter(3))

    var seen: List[String] = []

    var mapped = map_values(
        source.clone(),
        fn k,
        v:
            seen.append(k.label + v.count.to_string())
            return v
    )

    seen | try expect_equal(["b2", "a1", "c3"])
    try expect_equal(mapped.keys().map(fn k: k.id), [2, 1, 3])

    var edited = mapped[first].clone()
    edited.count = 7
    (mapped[first].count != 2 or source[first].count != 2) | try expect_false
    mapped.remove(first.clone())
    mapped.add(Key(5, "other"), Counter(5))
    (not (source.contains(first)) or source.contains(Key(5, "different"))) | try expect_false

test "Map key transformation retains first equal keys and last values":
    let source: Map[Int, Counter] = {
        2: Counter(1), 1: Counter(2), 4: Counter(3), 3: Counter(4)
    }
    var created: List[Key] = []

    var mapped = map_keys(
        source.clone(),
        fn k,
        v:
            let key = Key(k % 2, k.to_string())
            created.append(key.clone())
            return key
    )

    (created.length() != 4 or mapped.length() != 2) | try expect_false
    try expect_equal(mapped.keys().map(fn k: k.label.clone()), ["2", "1"])
    try expect_equal(mapped.values().map(fn v: v.count), [3, 4])

    var first_key = mapped.keys().get(0).clone()
    first_key.label = "first copy"
    try expect_false((created.get(0).label != "2" or created.get(2).label != "4"))

    var looked_up = mapped[Key(0, "lookup")].clone()
    looked_up.count = 9
    source[4].count | try expect_equal(3)
    mapped.clear()
    mapped.add(Key(7, "fresh"), Counter(10))
    source.length() | try expect_equal(4)

test "Map key transformation snapshots callbacks and keeps generic nesting":
    let source: Map[Int, Counter] = {2: Counter(2), 1: Counter(1), 3: Counter(3)}
    var seen: List[Int] = []
    let bound = source.clone().map_keys[String]

    let mapped = bound(
        transform: fn k,
        v:
            seen.append(k)
            return k.to_string()
    )

    (seen != [2, 1, 3] or mapped.keys() != ["2", "1", "3"]) | try expect_false
    mapped["3"].count | try expect_equal(3)

    let values: Map[String, Int] = {"a": 0}
    let map = values.clone().map[Int?]
    try expect_true((map(fn k, v: none) ["a"].is_none()))

    let nested = values.map(fn k, v: Result[Int, TextError].error(TextError("nested")))
    nested["a"].err().message() | try expect_equal("nested")

test "empty transformations skip callbacks and allocate independent storage":
    var empty_calls: List[Int] = []
    let source = Map[String, Int]()

    var mapped = source.map[Counter](
        (
            fn k,
            v:
                empty_calls.append(1)
                return Counter(0)
        )
    )

    mapped.add("new", Counter(1))
    (source.is_empty()) | try expect_true

    var keyed = source.map_keys[Key](
        (
            fn k,
            v:
                empty_calls.append(1)
                return Key(0, "unused")
        )
    )

    keyed.add(Key(1, "new"), 1)
    (source.is_empty()) | try expect_true
    empty_calls.is_empty() | try expect_true

test "Map reverse fold and last match retain ordered snapshots":
    let source: Map[String, Counter] = {
        "b": Counter(2), "a": Counter(1), "c": Counter(3)
    }
    let initial: List[String] = []

    var folded = reverse_map(
        source.clone(),
        initial.clone(),
        fn acc,
        k,
        v:
            var next = acc
            next.append(k + v.count.to_string())
            return next
    )

    folded | try expect_equal(["c3", "a1", "b2"])
    folded.append("copy")
    initial.length() | try expect_equal(0)

    var seen: List[String] = []
    let find = source.clone().find_last
    var found = (
        find(
            predicate: fn k,
            v:
                seen.append(k.clone())
                return k == "a"
        )
        .get()
        .clone()
    )
    (seen != ["c", "a"] or found.key != "a") | try expect_false

    var edited = found.value.clone()
    edited.count = 8
    source["a"].count | try expect_equal(1)
    found.key = "changed"
    source.contains("changed") | try expect_false

test "Set reverse fold and last match preserve snapshots and callbacks":
    let b = Key(2, "b")
    let a = Key(1, "a")
    let c = Key(3, "c")
    let source = Set[Key]([b.clone(), a.clone(), c.clone()])
    let initial: List[String] = []

    var folded = reverse_set(
        source.clone(),
        initial.clone(),
        fn acc,
        v:
            var next = acc
            next.append(v.label.clone())
            return next
    )

    folded | try expect_equal(["c", "a", "b"])
    folded.append("copy")
    initial.length() | try expect_equal(0)

    var seen: List[Int] = []
    let find = source.clone().find_last
    var found = find(
        fn v:
            seen.append(v.id)
            return v.id == 1
    ).get().clone()
    seen | try expect_equal([3, 1])
    found.label = "found"
    a.label | try expect_equal("a")

test "empty and nonmatching reverse queries keep fold and predicate contracts":
    var empty_calls: List[Int] = []
    let initial: List[Int] = []
    let empty_map = Map[String, Int]()
    let empty_set = Set[Int]()
    let map_fold = empty_map.fold_right[List[Int]]

    var map_result = map_fold(
        step: (
            fn acc,
            k,
            v:
                empty_calls.append(1)
                return acc
        ),
        initial: initial.clone()
    )

    map_result.append(1)

    let set_fold = empty_set.fold_right[List[Int]]

    var set_result = set_fold(
        initial.clone(),
        (
            fn acc,
            v:
                empty_calls.append(1)
                return acc
        )
    )

    set_result.append(2)
    map_result | try expect_equal([1])
    set_result | try expect_equal([2])
    initial.is_empty() | try expect_true
    try expect_false(
        not (
            empty_map
            .find_last(
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
    try expect_false(
        not (
            empty_set
            .find_last(
                (
                    fn v:
                        empty_calls.append(1)
                        return false
                )
            )
            .is_none()
        )
    )

    let values: Map[String, Int] = {"b": 2, "a": 1, "c": 3}
    var seen_map: List[String] = []
    try expect_false(
        (
            not (
                values
                .find_last(
                    fn k,
                    v:
                        seen_map.append(k)
                        return false
                )
                .is_none()
            )
            or seen_map != ["c", "a", "b"]
        )
    )

    let members = Set[Int]([2, 1, 3])
    var seen_set: List[Int] = []
    try expect_false(
        (
            not (
                members
                .find_last(
                    fn v:
                        seen_set.append(v)
                        return false
                )
                .is_none()
            )
            or seen_set != [3, 1, 2]
        )
    )
    empty_calls.is_empty() | try expect_true
