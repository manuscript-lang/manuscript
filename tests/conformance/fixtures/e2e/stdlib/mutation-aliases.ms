# conform: tags=aliasing,closures,control-flow,faults,interfaces,lists,maps,match,modules,mutation,optional,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/mutation-aliases.ms
import {expect_equal, expect_false} from "@std/testing.ms"

test "Map remove direct and bound preserve aliases order and no-op absence":
    let values = Map[Int, String]().add(1, "one").add(2, "two").add(3, "three")
    let alias = values
    let returned = values.remove(2)
    returned.add(4, "four")
    try expect_equal(alias.keys(), [1, 3, 4])
    let remove = values.remove
    let bound_result = remove(1)
    bound_result.add(5, "five")
    try expect_equal(alias.keys(), [3, 4, 5])
    values.remove(99)
    try expect_equal(values.keys(), [3, 4, 5])
    let empty = Map[Int, String]()
    empty.remove(1).add(2, "two")
    try expect_equal(empty.get(2), some("two"))
    let legacy = values.clone().remove(4)
    let preferred = values.clone().remove(4)
    try expect_equal(legacy, preferred)

test "Map remove captures its receiver before the key and keeps conversions":
    let first = Map[Optional[Int], Int]().add(1, 10)
    let second = Map[Optional[Int], Int]().add(1, 20)
    var selected = first
    let trigger = some(1)
    selected.remove(
        match trigger:
            some(key):
                selected = second
                some(key)
            none: some(0)
    )
    try expect_false(not first.is_empty() or second.get(1) != some(20))
    var captured = second
    let remove = captured.remove
    captured = first
    remove(1)
    try expect_false(not second.is_empty())

interface MapRemoval:
    fn remove(key: Int) Map[Int, String]

type MapAdapter:
    values: Map[Int, String]
    remove: fn(key: Int) Map[Int, String]

impl MapRemoval for MapAdapter:
    fn remove(key: Int) Map[Int, String]:
        return self.values.remove(key)

test "Map explicit and bound interface views preserve field shadowing":
    let values = Map[Int, String]().add(1, "one").add(2, "two").add(3, "three")
    let marker = Map[Int, String]().add(9, "field")
    let adapter = MapAdapter(values, fn(key: Int) Map[Int, String]: marker)
    try expect_false(adapter.remove(1) != marker or values.length() != 3)
    let view = MapRemoval(adapter)
    let returned = view.remove(1)
    returned.add(4, "four")
    let bound = view.remove
    bound(2).add(5, "five")
    try expect_equal(values.keys(), [3, 4, 5])

test "List splice direct and bound retain self staging and receiver returns":
    let values = [1, 2, 3]
    let alias = values
    let returned = values.splice(1, 1, values)
    returned.append(4)
    try expect_equal(alias, [1, 1, 2, 3, 3, 4])
    let splice = values.splice
    splice(1, 4, [9]).append(5)
    try expect_equal(alias, [1, 9, 4, 5])
    let legacy = values.clone().splice(0, 1, [7])
    let preferred = values.clone().splice(0, 1, [7])
    try expect_equal(legacy, preferred)
    values.splice(values.length(), 0, [6])
    try expect_equal(alias, [1, 9, 4, 5, 6])
    values.splice(0, values.length(), []).append(8)
    try expect_equal(alias, [8])
    let empty: List[Int] = []
    empty.splice(0, 0, []).append(3)
    try expect_equal(empty, [3])

type Item:
    value: Int

test "List splice preserves shallow replacement references and Optional elements":
    let item = Item(1)
    let replacement = [item]
    let values = [Item(2)]
    let returned = values.splice(0, 1, replacement)
    returned[0].value = 7
    try expect_false(item.value != 7 or replacement[0].value != 7)
    let optional: List[Optional[Int]] = [some(1)]
    optional.splice(0, 1, [some(2)])
    try expect_equal(optional[0], some(2))

interface ListSplicing:
    fn splice(start: Int, delete_count: Int, replacement: List[Int]) List[Int]

type ListAdapter:
    values: List[Int]
    splice: fn(start: Int, delete_count: Int, replacement: List[Int]) List[Int]

impl ListSplicing for ListAdapter:
    fn splice(start: Int, delete_count: Int, replacement: List[Int]) List[Int]:
        return self.values.splice(start, delete_count, replacement)

test "List explicit and bound interface views preserve field shadowing":
    let values = [1, 2, 3]
    let marker = [99]
    let adapter = ListAdapter(
        values,
        fn(start: Int, delete_count: Int, replacement: List[Int]) List[
            Int
        ]: marker
    )
    try expect_false(adapter.splice(0, 1, [7]) != marker or values != [1, 2, 3])
    let view = ListSplicing(adapter)
    view.splice(0, 1, [7]).append(4)
    let bound = view.splice
    bound(1, 2, [8]).append(5)
    try expect_equal(values, [7, 8, 4, 5])

test "List splice through a dispatched view follows reviewed Go range shrink semantics":
    let values = [1, 2, 3]
    let adapter = ListAdapter(
        values,
        fn(start: Int, delete_count: Int, replacement: List[Int]) List[Int]: []
    )
    let view = ListSplicing(adapter)
    var total = 0
    var visited = 0

    for value in values:
        total += value
        if visited == 0: view.splice(0, 1, [])
        visited += 1

    try expect_false((total != 7 or visited != 3 or values != [2, 3]))
