# conform: tags=closures,control-flow,faults,formatter,interfaces,lists,maps,match,modules,mutation,optional,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/mutation-aliases.ms
import {expect_equal, expect_false} from "@std/testing.ms"

test "Map remove direct and bound preserve order and no-op absence":
    var values = Map[Int, String]()
    values.add(1, "one")
    values.add(2, "two")
    values.add(3, "three")
    let snapshot = values.clone()
    values.remove(2)
    values.add(4, "four")
    try expect_equal(values.keys(), [1, 3, 4])
    try expect_equal(snapshot.keys(), [1, 2, 3])
    values.remove(1)
    values.add(5, "five")
    try expect_equal(values.keys(), [3, 4, 5])
    values.remove(99)
    try expect_equal(values.keys(), [3, 4, 5])
    var empty = Map[Int, String]()
    empty.remove(1)
    empty.add(2, "two")
    try expect_equal(empty.get(2), some("two"))
    var legacy = values.clone()
    legacy.remove(4)
    var preferred = values.clone()
    preferred.remove(4)
    try expect_equal(legacy, preferred)

test "Map remove evaluates its key after choosing the receiver and keeps conversions":
    var first = Map[Optional[Int], Int]()
    first.add(1, 10)
    let trigger = some(1)
    first.remove(
        match trigger:
            some(key): some(key)
            none: some(0)
    )
    try expect_false(not first.is_empty())

interface MapRemoval:
    var fn remove(key: Int) Unit
    fn keys() List[Int]

type MapAdapter:
    values: Map[Int, String]

impl MapRemoval for MapAdapter:
    var fn remove(key: Int) Unit:
        self.values.remove(key)

    fn keys() List[Int]: self.values.keys()

test "Map explicit and bound interface views remove through the adapter":
    var values = Map[Int, String]()
    values.add(1, "one")
    values.add(2, "two")
    values.add(3, "three")
    var adapter = MapAdapter(values)
    adapter.remove(1)
    try expect_equal(adapter.values.keys(), [2, 3])
    var view = MapRemoval(adapter)
    view.remove(2)
    try expect_equal(view.keys(), [3])
    view.remove(3)
    try expect_equal(view.keys(), [])

test "List splice direct and bound stage a copy of the receiver as replacement":
    var values = [1, 2, 3]
    values.splice(1, 1, values.clone())
    values.append(4)
    try expect_equal(values, [1, 1, 2, 3, 3, 4])
    values.splice(1, 4, [9])
    values.append(5)
    try expect_equal(values, [1, 9, 4, 5])
    var legacy = values.clone()
    legacy.splice(0, 1, [7])
    var preferred = values.clone()
    preferred.splice(0, 1, [7])
    try expect_equal(legacy, preferred)
    values.splice(values.length(), 0, [6])
    try expect_equal(values, [1, 9, 4, 5, 6])
    values.splice(0, values.length(), [])
    values.append(8)
    try expect_equal(values, [8])
    var empty: List[Int] = []
    empty.splice(0, 0, [])
    empty.append(3)
    try expect_equal(empty, [3])

type Item:
    value: Int

test "List splice moves replacement elements and handles Optional elements":
    var values = [Item(2)]
    values.splice(0, 1, [Item(1)])
    try expect_equal(values[0].value, 1)
    var optional: List[Optional[Int]] = [some(1)]
    optional.splice(0, 1, [some(2)])
    try expect_equal(optional[0], some(2))

interface ListSplicing:
    var fn splice(start: Int, delete_count: Int, replacement: List[Int]) Unit
    fn contents() List[Int]

type ListAdapter:
    values: List[Int]

impl ListSplicing for ListAdapter:
    var fn splice(start: Int, delete_count: Int, replacement: List[Int]) Unit:
        self.values.splice(start, delete_count, replacement)

    fn contents() List[Int]: self.values.clone()

test "List explicit and bound interface views splice through the adapter":
    var adapter = ListAdapter([1, 2, 3])
    adapter.splice(0, 1, [7])
    try expect_equal(adapter.values, [7, 2, 3])
    var view = ListSplicing(adapter)
    view.splice(0, 1, [7])
    try expect_equal(view.contents(), [7, 2, 3])
    view.splice(1, 2, [8])
    try expect_equal(view.contents(), [7, 8])
