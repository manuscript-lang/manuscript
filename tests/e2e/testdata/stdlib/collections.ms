import {
    List,
    Map,
    Set,
    ListBuilder,
    MapBuilder,
    SetBuilder,
    range,
    filled,
    CollectionError,
    MapEntry,
    map_from_entries
} from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn positive(value: Int) -> Bool: value > 0

fn twice(value: Int) -> Int: value * 2

fn duplicate(value: Int) -> List[Int]: [value, value]

fn sum(accumulator: Int, value: Int) -> Int: accumulator + value

fn parity(value: Int) -> Int: value % 2

test "list search callbacks empty identities and folding":
    let list = [-1, 2, 0, 3]
    if (list.find(positive) != some(2) or list.find_last(positive) != some(3)): return panic(
        "find"
    )
    if (
        list.find_index(positive) != some(1)
        or list.find_last_index(positive) != some(3)
    ): return panic("find indices")
    if list.filter(positive).map(twice) != [4, 6]: return panic("sequential callbacks")
    if ([1, 2]).flat_map(duplicate) != [1, 1, 2, 2]: return panic("flat map")
    if (
        list.fold(initial: 0, step: sum) != 4
        or list.fold_right(initial: 0, step: sum) != 4
    ): return panic("fold")

    let empty: List[Int] = []
    if empty.some(positive) or not empty.every(positive): return panic(
        "empty predicate identities"
    )
    if not empty.first().is_none() or not empty.last().is_none(): return panic(
        "empty search"
    )

    let groups = ([1, 2, 3]).group_by(parity)
    if groups.get(1) != some([1, 3]) or groups.get(0) != some([2]): return panic(
        "group order"
    )

test "list mutation and clone keep separate storage":
    let original = [1, 2, 3]
    let copy = original.clone()
    copy.splice(start: 1, delete_count: 1, replacement: [8, 9])
    if copy != [1, 8, 9, 3] or original != [1, 2, 3]: return panic("splice clone")

    copy.fill(value: 0, start: 1, end: 3)
    if copy != [1, 0, 0, 3]: return panic("fill")

    let overlapping = [1, 2, 3, 4]
    overlapping.copy_within(target: 1, start: 0, end: 3)
    if overlapping != [1, 1, 2, 3]: return panic("overlapping copy")

test "maps preserve insertion order and overwrite duplicate keys":
    let entries = [
        MapEntry(key: "a", value: 1),
        MapEntry(key: "b", value: 2),
        MapEntry(key: "a", value: 3)
    ]
    let map = map_from_entries(entries)
    if map.keys() != ["a", "b"] or map.values() != [3, 2]: return panic("map order")

    map.add_default(key: "a", value: 99)
    if map.get("a") != some(3): return panic("default overwrote value")

    let copy = map.clone().remove("a")
    if copy.keys() != ["b"] or map.keys() != ["a", "b"]: return panic("map clone")
    if not map.get("missing").is_none(): return panic("missing key")

test "set algebra removes duplicates and preserves values":
    let left = ([1, 2, 2]).to_set()
    let right = ([2, 3]).to_set()
    if left.values() != [1, 2]: return panic("set deduplication")
    if left.union(right).values() != [1, 2, 3]: return panic("union")
    if left.intersection(right).values() != [2]: return panic("intersection")
    if left.difference(right).values() != [1]: return panic("difference")
    if left.symmetric_difference(right).values() != [1, 3]: return panic(
        "symmetric difference"
    )
    if not left.is_subset_of(left.union(right)): return panic("subset")
    if not left.is_disjoint_from(([3]).to_set()): return panic("disjoint")

test "collection constructors validate bounds and exact limits":
    if (value(range(start: 3, end: -1, step: -1, max_items: 4)) != [3, 2, 1, 0]): return panic(
        "descending range"
    )
    if value(filled(value: "x", count: 2)) != ["x", "x"]: return panic("filled")

    let invalid: Result[List[Int], CollectionError] = error(
        CollectionError.InvalidInput
    )
    if range(start: 0, end: 1, step: 0) != invalid: return panic("zero step")

    let limited: Result[List[Int], CollectionError] = error(
        CollectionError.LimitExceeded
    )
    if range(start: 0, end: 3, step: 1, max_items: 2) != limited: return panic(
        "range budget"
    )

test "huge sizes return LimitExceeded instead of exhausting memory":
    let limited: Result[List[Int], CollectionError] = error(
        CollectionError.LimitExceeded
    )
    if filled(value: 1, count: 9223372036854775807) != limited: return panic(
        "filled huge"
    )
    if (
        filled(
            value: 1,
            count: 4611686018427387904,
            max_items: 9223372036854775807
        ) != limited
    ): return panic("filled huge explicit limit")
    if range(start: 0, end: 9223372036854775807, step: 1) != limited: return panic(
        "range huge"
    )

test "collection builders freeze all accumulated values":
    let list = ListBuilder[Int]()
    list.append(1)
    list.append(2)
    if list.freeze() != [1, 2] or list.freeze() != [1, 2]: return panic("list builder")

    let map = MapBuilder[String, Int]()
    map.add(key: "a", value: 1)
    map.add(key: "a", value: 2)
    if map.freeze().get("a") != some(2): return panic("map builder")

    let set = SetBuilder[Int]()
    set.add(1)
    set.add(1)
    if set.freeze().values() != [1]: return panic("set builder")

test "imported map add interoperates with with_entry":
    let values = Map[String, Int]().add("a", 1)
    values.add("b", 2).add(value: 3, key: "a")
    let add = values.add
    add("c", 4)
    if values.keys() != ["a", "b", "c"] or values.values() != [3, 2, 4]: return panic(
        "map add compatibility"
    )
