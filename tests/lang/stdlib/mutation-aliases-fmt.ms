// conform: tags=closures,control-flow,faults,formatter,interfaces,lists,maps,match,modules,mutation,optional,parser,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/stdlib/mutation-aliases.ms
import expect_equal, expect_false from "@std/test/test.ms"

test "Map remove direct and bound preserve order and no-op absence" {
	var values = Map[Int, String]()
	values.add(1, "one")
	values.add(2, "two")
	values.add(3, "three")

	snapshot := values.clone()
	values.remove(2)
	values.add(4, "four")
	expect_equal(values.keys(), [1, 3, 4])?
	expect_equal(snapshot.keys(), [1, 2, 3])?
	values.remove(1)
	values.add(5, "five")
	expect_equal(values.keys(), [3, 4, 5])?
	values.remove(99)
	expect_equal(values.keys(), [3, 4, 5])?

	var empty = Map[Int, String]()
	empty.remove(1)
	empty.add(2, "two")
	expect_equal(empty.get(2), "two")?

	var legacy = values.clone()
	legacy.remove(4)

	var preferred = values.clone()
	preferred.remove(4)
	expect_equal(legacy, preferred)?
}

test "Map remove evaluates its key after choosing the receiver and keeps conversions" {
	var first = Map[Int?, Int]()
	first.add(1, 10)

	trigger Int? := 1
	first.remove(
		match trigger {
			key => key
			null => 0
		}
	)
	expect_false(not first.is_empty())?
}

interface MapRemoval {
	var fn remove(key Int) Void
	fn keys() List[Int]
}

type MapAdapter {
	values Map[Int, String]
}

fn var MapAdapter.remove(key Int) Void {
	self.values.remove(key)
}

fn hold MapAdapter.keys() &List[Int] => self.values.keys()

test "Map explicit and bound interface views remove through the adapter" {
	var values = Map[Int, String]()
	values.add(1, "one")
	values.add(2, "two")
	values.add(3, "three")

	var adapter = MapAdapter(values)
	adapter.remove(1)
	expect_equal(adapter.values.keys(), [2, 3])?

	var view MapRemoval = adapter
	view.remove(2)
	expect_equal(view.keys(), [3])?
	view.remove(3)
	expect_equal(view.keys(), [])?
}

test "List splice direct and bound stage a copy of the receiver as replacement" {
	var values = [1, 2, 3]
	values.splice(1, 1, values.clone())
	values.append(4)
	expect_equal(values, [1, 1, 2, 3, 3, 4])?
	values.splice(1, 4, [9])
	values.append(5)
	expect_equal(values, [1, 9, 4, 5])?

	var legacy = values.clone()
	legacy.splice(0, 1, [7])

	var preferred = values.clone()
	preferred.splice(0, 1, [7])
	expect_equal(legacy, preferred)?
	values.splice(values.length(), 0, [6])
	expect_equal(values, [1, 9, 4, 5, 6])?
	values.splice(0, values.length(), [])
	values.append(8)
	expect_equal(values, [8])?

	var empty List[Int] = []
	empty.splice(0, 0, [])
	empty.append(3)
	expect_equal(empty, [3])?
}

type Item {
	value Int
}

test "List splice moves replacement elements and handles Optional elements" {
	var values = [Item(2)]
	values.splice(0, 1, [Item(1)])
	expect_equal(values[0].value, 1)?

	var optional List[Int?] = [1]
	optional.splice(0, 1, [2])
	expect_equal(optional[0], 2)?
}

interface ListSplicing {
	var fn splice(start Int, delete_count Int, replacement List[Int]) Void
	fn contents() List[Int]
}

type ListAdapter {
	values List[Int]
}

fn var ListAdapter.splice(start Int, delete_count Int, replacement List[Int]) Void {
	self.values.splice(start, delete_count, replacement.clone())
}

fn ListAdapter.contents() List[Int] => self.values.clone()

test "List explicit and bound interface views splice through the adapter" {
	var adapter = ListAdapter([1, 2, 3])
	adapter.splice(0, 1, [7])
	expect_equal(adapter.values, [7, 2, 3])?

	var view ListSplicing = adapter
	view.splice(0, 1, [7])
	expect_equal(view.contents(), [7, 2, 3])?
	view.splice(1, 2, [8])
	expect_equal(view.contents(), [7, 8])?
}
// expect-format: rewritten
// expect-formatted: import expect_equal, expect_false from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: test "Map remove direct and bound preserve order and no-op absence" {
// expect-formatted: \tvar values = Map[Int, String]()
// expect-formatted: \tvalues.add(1, "one")
// expect-formatted: \tvalues.add(2, "two")
// expect-formatted: \tvalues.add(3, "three")
// expect-formatted:
// expect-formatted: \tsnapshot := values.clone()
// expect-formatted: \tvalues.remove(2)
// expect-formatted: \tvalues.add(4, "four")
// expect-formatted: \texpect_equal(values.keys(), [1, 3, 4])?
// expect-formatted: \texpect_equal(snapshot.keys(), [1, 2, 3])?
// expect-formatted: \tvalues.remove(1)
// expect-formatted: \tvalues.add(5, "five")
// expect-formatted: \texpect_equal(values.keys(), [3, 4, 5])?
// expect-formatted: \tvalues.remove(99)
// expect-formatted: \texpect_equal(values.keys(), [3, 4, 5])?
// expect-formatted:
// expect-formatted: \tvar empty = Map[Int, String]()
// expect-formatted: \tempty.remove(1)
// expect-formatted: \tempty.add(2, "two")
// expect-formatted: \texpect_equal(empty.get(2), "two")?
// expect-formatted:
// expect-formatted: \tvar legacy = values.clone()
// expect-formatted: \tlegacy.remove(4)
// expect-formatted:
// expect-formatted: \tvar preferred = values.clone()
// expect-formatted: \tpreferred.remove(4)
// expect-formatted: \texpect_equal(legacy, preferred)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "Map remove evaluates its key after choosing the receiver and keeps conversions" {
// expect-formatted: \tvar first = Map[Int?, Int]()
// expect-formatted: \tfirst.add(1, 10)
// expect-formatted:
// expect-formatted: \ttrigger Int? := 1
// expect-formatted: \tfirst.remove(
// expect-formatted: \t\tmatch trigger {
// expect-formatted: \t\t\tkey => key
// expect-formatted: \t\t\tnull => 0
// expect-formatted: \t\t}
// expect-formatted: \t)
// expect-formatted: \texpect_false(not first.is_empty())?
// expect-formatted: }
// expect-formatted:
// expect-formatted: interface MapRemoval {
// expect-formatted: \tvar fn remove(key Int) Void
// expect-formatted: \tfn keys() List[Int]
// expect-formatted: }
// expect-formatted:
// expect-formatted: type MapAdapter {
// expect-formatted: \tvalues Map[Int, String]
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn var MapAdapter.remove(key Int) Void {
// expect-formatted: \tself.values.remove(key)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn hold MapAdapter.keys() &List[Int] => self.values.keys()
// expect-formatted:
// expect-formatted: test "Map explicit and bound interface views remove through the adapter" {
// expect-formatted: \tvar values = Map[Int, String]()
// expect-formatted: \tvalues.add(1, "one")
// expect-formatted: \tvalues.add(2, "two")
// expect-formatted: \tvalues.add(3, "three")
// expect-formatted:
// expect-formatted: \tvar adapter = MapAdapter(values)
// expect-formatted: \tadapter.remove(1)
// expect-formatted: \texpect_equal(adapter.values.keys(), [2, 3])?
// expect-formatted:
// expect-formatted: \tvar view MapRemoval = adapter
// expect-formatted: \tview.remove(2)
// expect-formatted: \texpect_equal(view.keys(), [3])?
// expect-formatted: \tview.remove(3)
// expect-formatted: \texpect_equal(view.keys(), [])?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "List splice direct and bound stage a copy of the receiver as replacement" {
// expect-formatted: \tvar values = [1, 2, 3]
// expect-formatted: \tvalues.splice(1, 1, values.clone())
// expect-formatted: \tvalues.append(4)
// expect-formatted: \texpect_equal(values, [1, 1, 2, 3, 3, 4])?
// expect-formatted: \tvalues.splice(1, 4, [9])
// expect-formatted: \tvalues.append(5)
// expect-formatted: \texpect_equal(values, [1, 9, 4, 5])?
// expect-formatted:
// expect-formatted: \tvar legacy = values.clone()
// expect-formatted: \tlegacy.splice(0, 1, [7])
// expect-formatted:
// expect-formatted: \tvar preferred = values.clone()
// expect-formatted: \tpreferred.splice(0, 1, [7])
// expect-formatted: \texpect_equal(legacy, preferred)?
// expect-formatted: \tvalues.splice(values.length(), 0, [6])
// expect-formatted: \texpect_equal(values, [1, 9, 4, 5, 6])?
// expect-formatted: \tvalues.splice(0, values.length(), [])
// expect-formatted: \tvalues.append(8)
// expect-formatted: \texpect_equal(values, [8])?
// expect-formatted:
// expect-formatted: \tvar empty List[Int] = []
// expect-formatted: \tempty.splice(0, 0, [])
// expect-formatted: \tempty.append(3)
// expect-formatted: \texpect_equal(empty, [3])?
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Item {
// expect-formatted: \tvalue Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "List splice moves replacement elements and handles Optional elements" {
// expect-formatted: \tvar values = [Item(2)]
// expect-formatted: \tvalues.splice(0, 1, [Item(1)])
// expect-formatted: \texpect_equal(values[0].value, 1)?
// expect-formatted:
// expect-formatted: \tvar optional List[Int?] = [1]
// expect-formatted: \toptional.splice(0, 1, [2])
// expect-formatted: \texpect_equal(optional[0], 2)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: interface ListSplicing {
// expect-formatted: \tvar fn splice(start, delete_count Int, replacement List[Int]) Void
// expect-formatted: \tfn contents() List[Int]
// expect-formatted: }
// expect-formatted:
// expect-formatted: type ListAdapter {
// expect-formatted: \tvalues List[Int]
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn var ListAdapter.splice(start, delete_count Int, replacement List[Int]) Void {
// expect-formatted: \tself.values.splice(start, delete_count, replacement.clone())
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn ListAdapter.contents() List[Int] => self.values.clone()
// expect-formatted:
// expect-formatted: test "List explicit and bound interface views splice through the adapter" {
// expect-formatted: \tvar adapter = ListAdapter([1, 2, 3])
// expect-formatted: \tadapter.splice(0, 1, [7])
// expect-formatted: \texpect_equal(adapter.values, [7, 2, 3])?
// expect-formatted:
// expect-formatted: \tvar view ListSplicing = adapter
// expect-formatted: \tview.splice(0, 1, [7])
// expect-formatted: \texpect_equal(view.contents(), [7, 2, 3])?
// expect-formatted: \tview.splice(1, 2, [8])
// expect-formatted: \texpect_equal(view.contents(), [7, 8])?
// expect-formatted: }
