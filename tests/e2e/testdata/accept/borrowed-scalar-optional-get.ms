import (
	Closeable, panic from "@std/core.ms",
	expect_contains, expect_equal, expect_fault from "@std/test/test.ms",
)

type Marker:
	id: Int

fn var Marker.close() Unit!: error(Error("scalar marker closed"))

fn inspect(value: Marker?) Unit:
	_id := value.get().id
	_still_present := value.is_some()
	panic("borrowed owner remains alive")

fn collection(values: List[Marker]) Unit:
	_id := values.first().get().id
	_still_present := values.length()
	panic("collection owner remains alive")

test "a borrowed scalar Optional getter leaves its owner alive":
	(expect_fault(fn: inspect(Marker(1)))?) | expect_contains(
		"borrowed owner remains alive"
	)?

test "a scalar collection lend leaves its owner alive":
	(expect_fault(fn: collection([Marker(2)]))?) | expect_contains(
		"collection owner remains alive"
	)?

fn owned_result() Unit:
	value: Marker!Int := ok(Marker(3))
	_id := value.get().id

fn scalar_optional() Marker?: Marker(4)

fn owned_optional() Unit:
	_id := scalar_optional().get().id

test "owned scalar getter results still close their temporary":
	(expect_fault(owned_result)?) | expect_contains("resource could not be closed")?
	(expect_fault(owned_optional)?) | expect_contains("resource could not be closed")?

type HeapMarker:
	text: String

fn var HeapMarker.close() Unit!: error(Error("heap marker closed"))

fn inspect_heap(value: HeapMarker?) Unit:
	_length := value.get().text.length()
	_still_present := value.is_some()
	panic("heap owner remains alive")

test "heap resource Optional getters retain their existing borrow":
	(expect_fault(fn: inspect_heap(HeapMarker("heap")))?) | expect_contains(
		"heap owner remains alive"
	)?

fn collection_last(values: List[Marker]) Unit:
	_id := values.last().get().id
	_still_present := values.length()
	panic("last owner remains alive")

fn map_entry(values: Map[String, Marker]) Unit:
	_id := values.get("present").get().id
	_still_present := values.length()
	panic("map owner remains alive")

fn make_map() Map[String, Marker]:
	var values = Map[String, Marker]()
	values.add("present", Marker(8))
	return values

fn collection_named(values: List[Marker]) Unit:
	entry := values.first()
	_id := entry.get().id
	_still_present := values.length()
	panic("named owner remains alive")

fn collection_missing(values: List[Marker]) Unit:
	_id := values.first().get().id
	_still_present := values.length()

fn map_missing(values: Map[String, Marker]) Unit:
	_id := values.get("absent").get().id
	_still_present := values.length()

fn read_generic[T](values: List[T], read: fn(T) Int) Int:
	return read(values.first().get())

fn generic_collection(values: List[Marker]) Unit:
	_id := read_generic(values, fn value: value.id)
	_still_present := values.length()
	panic("generic owner remains alive")

fn temporary_text() String:
	return ["temporary payload"].first().get()

test "an inline last lend leaves its scalar owner alive":
	(expect_fault(fn: collection_last([Marker(7)]))?) | expect_contains(
		"last owner remains alive"
	)?

test "an inline map lend leaves its scalar owner alive":
	(expect_fault(fn: map_entry(make_map()))?) | expect_contains(
		"map owner remains alive"
	)?

test "named and inline scalar collection lends keep the same borrow":
	(expect_fault(fn: collection_named([Marker(9)]))?) | expect_contains(
		"named owner remains alive"
	)?

test "missing collection lends still report Optional get faults":
	(expect_fault(fn: collection_missing(List[Marker]()))?) | expect_contains(
		"called Optional.get() on none"
	)?
	(expect_fault(fn: map_missing(Map[String, Marker]()))?) | expect_contains(
		"called Optional.get() on none"
	)?

test "generic inline collection reads lend to their callback":
	(expect_fault(fn: generic_collection([Marker(10)]))?) | expect_contains(
		"generic owner remains alive"
	)?

test "Clonable results survive their temporary collection":
	text := temporary_text()
	expect_equal(text, "temporary payload")?
	expect_equal(text.length(), 17)?

fn labeled_map_entry(values: Map[String, Marker]) Unit:
	_id := values.get(key: "present").get().id
	_still_present := values.length()
	panic("labeled map owner remains alive")

fn labeled_map_binding(values: Map[String, Marker]) Unit:
	entry := values.get(key: "present")
	_id := entry.get().id
	_still_present := values.length()
	panic("labeled binding owner remains alive")

fn labeled_map_missing(values: Map[String, Marker]) Unit:
	_id := values.get(key: "absent").get().id
	_still_present := values.length()

test "a labeled map lend leaves its scalar owner alive":
	(expect_fault(fn: labeled_map_entry(make_map()))?) | expect_contains(
		"labeled map owner remains alive"
	)?

test "a labeled map binding leaves its scalar owner alive":
	(expect_fault(fn: labeled_map_binding(make_map()))?) | expect_contains(
		"labeled binding owner remains alive"
	)?

test "a missing labeled map lend still reports the Optional fault":
	(expect_fault(fn: labeled_map_missing(make_map()))?) | expect_contains(
		"called Optional.get() on none"
	)?

fn map_index(var events: List[Int]) Int:
	events.append(1)
	return 0

fn map_key(var events: List[Int]) String:
	events.append(2)
	return "present"

test "labeled map lends evaluate receiver and key once in order":
	var values = Map[String, String]()
	values.add("present", "payload")

	maps := [values]
	var events: List[Int] = []
	length := maps[map_index(var events)].get(key: map_key(var events)).get().length()
	expect_equal(length, 7)?
	expect_equal(events, [1, 2])?
	expect_equal(maps.length(), 1)?

test "labeled map keys retain their checked conversion":
	var values = Map[String?, Int]()
	values.add("present", 12)
	expect_equal(values.get(key: "present").get(), 12)?
	expect_equal(values.get(key: "absent").is_none(), true)?
	expect_equal(values.length(), 1)?
