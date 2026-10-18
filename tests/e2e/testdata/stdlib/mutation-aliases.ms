import panic from "@std/faults.ms"

test "Map remove direct and bound preserve aliases order and no-op absence":
    let values = Map[Int, String]().add(1, "one").add(2, "two").add(3, "three")
    let alias = values
    let returned = values.remove(2)
    returned.add(4, "four")
    if alias.keys() != [1, 3, 4]: return panic("receiver return or insertion order")

    let remove = values.remove
    let bound_result = remove(1)
    bound_result.add(5, "five")
    if alias.keys() != [3, 4, 5]: return panic("bound receiver return")

    values.remove(99)
    if values.keys() != [3, 4, 5]: return panic("absent key changed values")

    let empty = Map[Int, String]()
    empty.remove(1).add(2, "two")
    if empty.get(2) != some("two"): return panic("empty receiver return")

    let legacy = values.clone().remove(4)
    let preferred = values.clone().remove(4)
    if legacy != preferred: return panic("legacy equivalence")

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
    if not first.is_empty() or second.get(1) != some(20):
        return panic("receiver order or Some conversion")

    var captured = second
    let remove = captured.remove
    captured = first
    remove(1)
    if not second.is_empty(): return panic("stored receiver capture")

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
    if adapter.remove(1) != marker or values.length() != 3:
        return panic("callable field shadowing")

    let view = MapRemoval(adapter)
    let returned = view.remove(1)
    returned.add(4, "four")
    let bound = view.remove
    bound(2).add(5, "five")
    if values.keys() != [3, 4, 5]: return panic("view method or bound return")

test "List splice direct and bound retain self staging and receiver returns":
    let values = [1, 2, 3]
    let alias = values
    let returned = values.splice(1, 1, values)
    returned.append(4)
    if alias != [1, 1, 2, 3, 3, 4]: return panic("self staging or return")

    let splice = values.splice
    splice(1, 4, [9]).append(5)
    if alias != [1, 9, 4, 5]: return panic("bound splice")

    let legacy = values.clone().splice(0, 1, [7])
    let preferred = values.clone().splice(0, 1, [7])
    if legacy != preferred: return panic("legacy equivalence")

    values.splice(values.length(), 0, [6])
    if alias != [1, 9, 4, 5, 6]: return panic("end insertion")

    values.splice(0, values.length(), []).append(8)
    if alias != [8]: return panic("full shrink return")

    let empty: List[Int] = []
    empty.splice(0, 0, []).append(3)
    if empty != [3]: return panic("empty no-op return")

type Item:
    value: Int

test "List splice preserves shallow replacement references and Optional elements":
    let item = Item(1)
    let replacement = [item]
    let values = [Item(2)]
    let returned = values.splice(0, 1, replacement)
    returned[0].get().value = 7
    if item.value != 7 or replacement[0].get().value != 7:
        return panic("replacement was deep copied")

    let optional: List[Optional[Int]] = [some(1)]
    optional.splice(0, 1, [some(2)])
    if optional[0].get() != some(2): return panic("element conversion")

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
    if adapter.splice(0, 1, [7]) != marker or values != [1, 2, 3]:
        return panic("callable field shadowing")

    let view = ListSplicing(adapter)
    view.splice(0, 1, [7]).append(4)
    let bound = view.splice
    bound(1, 2, [8]).append(5)
    if values != [7, 8, 4, 5]: return panic("interface view or bound alias")

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

    if (total != 7 or visited != 3 or values != [2, 3]):
        return panic("captured backing, shifted values or valid retained tail changed")
