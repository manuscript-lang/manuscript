import {expect_equal, expect_false, expect_true} from "@std/testing.ms"

test "Map remove direct and bound preserve aliases order and no-op absence":
    let values = Map[Int, String]().add(1, "one").add(2, "two").add(3, "three")
    let alias = values
    let returned = values.remove(key: 2)
    returned.add(4, "four")
    alias.keys() | try expect_equal(expected: [1, 3, 4])
    let remove = values.remove
    let bound_result = remove(key: 1)
    bound_result.add(5, "five")
    alias.keys() | try expect_equal(expected: [3, 4, 5])
    values.remove(99)
    values.keys() | try expect_equal(expected: [3, 4, 5])
    let empty = Map[Int, String]()
    empty.remove(1).add(2, "two")
    empty.get(2) | try expect_equal(expected: some("two"))
    let legacy = values.clone().remove(4)
    let preferred = values.clone().remove(4)
    legacy | try expect_equal(expected: preferred)

test "Map remove captures its receiver before the key and keeps conversions":
    let first = Map[Optional[Int], Int]().add(1, 10)
    let second = Map[Optional[Int], Int]().add(1, 20)
    var selected = first
    let trigger = some(1)
    selected.remove(
        key: match trigger:
            some(key):
                selected = second
                some(key)
            none: some(0)
    )
    (not first.is_empty() or second.get(1) != some(20)) | try expect_false
    var captured = second
    let remove = captured.remove
    captured = first
    remove(1)
    (second.is_empty()) | try expect_true

interface MapRemoval:
    fn remove(key: Int) -> Map[Int, String]

type MapAdapter:
    values: Map[Int, String]
    remove: fn(key: Int) -> Map[Int, String]

impl MapRemoval for MapAdapter:
    fn remove(key: Int) -> Map[Int, String]:
        return self.values.remove(key)

test "Map explicit and bound interface views preserve field shadowing":
    let values = Map[Int, String]().add(1, "one").add(2, "two").add(3, "three")
    let marker = Map[Int, String]().add(9, "field")
    let adapter = MapAdapter(values, fn(key: Int) -> Map[Int, String]: marker)
    (adapter.remove(1) != marker or values.length() != 3) | try expect_false
    let view = MapRemoval(adapter)
    let returned = view.remove(1)
    returned.add(4, "four")
    let bound = view.remove
    bound(2).add(5, "five")
    values.keys() | try expect_equal(expected: [3, 4, 5])

test "List splice direct and bound retain self staging and receiver returns":
    let values = [1, 2, 3]
    let alias = values
    let returned = values.splice(start: 1, delete_count: 1, replacement: values)
    returned.append(4)
    alias | try expect_equal(expected: [1, 1, 2, 3, 3, 4])
    let splice = values.splice
    splice(1, 4, [9]).append(5)
    alias | try expect_equal(expected: [1, 9, 4, 5])
    let legacy = values.clone().splice(0, 1, [7])
    let preferred = values.clone().splice(0, 1, [7])
    legacy | try expect_equal(expected: preferred)
    values.splice(values.length(), 0, [6])
    alias | try expect_equal(expected: [1, 9, 4, 5, 6])
    values.splice(0, values.length(), []).append(8)
    alias | try expect_equal(expected: [8])
    let empty: List[Int] = []
    empty.splice(0, 0, []).append(3)
    empty | try expect_equal(expected: [3])

type Item:
    value: Int

test "List splice preserves shallow replacement references and Optional elements":
    let item = Item(1)
    let replacement = [item]
    let values = [Item(2)]
    let returned = values.splice(0, 1, replacement)
    returned[0].unwrap().value = 7
    (item.value != 7 or replacement[0].unwrap().value != 7) | try expect_false
    let optional: List[Optional[Int]] = [some(1)]
    optional.splice(0, 1, [some(2)])
    optional[0].unwrap() | try expect_equal(expected: some(2))

interface ListSplicing:
    fn splice(start: Int, delete_count: Int, replacement: List[Int]) -> List[Int]

type ListAdapter:
    values: List[Int]
    splice: fn(start: Int, delete_count: Int, replacement: List[Int]) -> List[Int]

impl ListSplicing for ListAdapter:
    fn splice(start: Int, delete_count: Int, replacement: List[Int]) -> List[Int]:
        return self.values.splice(start, delete_count, replacement)

test "List explicit and bound interface views preserve field shadowing":
    let values = [1, 2, 3]
    let marker = [99]
    let adapter = ListAdapter(
        values,
        fn(start: Int, delete_count: Int, replacement: List[Int]) -> List[
            Int
        ]: marker
    )
    (adapter.splice(0, 1, [7]) != marker or values != [1, 2, 3]) | try expect_false
    let view = ListSplicing(adapter)
    view.splice(0, 1, [7]).append(4)
    let bound = view.splice
    bound(1, 2, [8]).append(5)
    values | try expect_equal(expected: [7, 8, 4, 5])

test "List splice through a dispatched view follows reviewed Go range shrink semantics":
    let values = [1, 2, 3]
    let adapter = ListAdapter(
        values,
        fn(start: Int, delete_count: Int, replacement: List[Int]) -> List[
            Int
        ]: []
    )
    let view = ListSplicing(adapter)
    var total = 0
    var visited = 0

    for value in values:
        total = total + value
        if visited == 0: view.splice(0, 1, [])
        visited = visited + 1

    (total != 7 or visited != 3 or values != [2, 3]) | try expect_false
