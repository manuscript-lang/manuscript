// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Closeable, panic from "@std/core.ms",
	expect_contains, expect_equal, expect_fault from "@std/test/test.ms",
)

type Marker:
	id Int

fn move Marker.close() Void! => error(Error("scalar marker closed"))

fn inspect(value Marker?) Void:
	_id := (value or panic("called Optional.get() on null")).id
	_still_present := value != null
	panic("borrowed owner remains alive")

fn collection(values List[Marker]) Void:
	_id := (values.first() or panic("called Optional.get() on null")).id
	_still_present := values.length()
	panic("collection owner remains alive")

test "a borrowed scalar Optional getter leaves its owner alive":
	(
		(expect_fault(() => inspect(Marker(1)))?)
		| expect_contains("borrowed owner remains alive")?
	)

test "a scalar collection lend leaves its owner alive":
	(
		(expect_fault(() => collection([Marker(2)]))?)
		| expect_contains("collection owner remains alive")?
	)

fn owned_result() Void:
	value Marker!Int := ok(Marker(3))
	_id := value.get().id

fn scalar_optional() Marker? => Marker(4)

fn owned_optional() Void:
	_id := (scalar_optional() or panic("called Optional.get() on null")).id

test "owned scalar getter results still close their temporary":
	(expect_fault(owned_result)?) | expect_contains("resource could not be closed")?
	(expect_fault(owned_optional)?) | expect_contains("resource could not be closed")?

type HeapMarker:
	text String

fn move HeapMarker.close() Void! => error(Error("heap marker closed"))

fn inspect_heap(value HeapMarker?) Void:
	_length := (value or panic("called Optional.get() on null")).text.length()
	_still_present := value != null
	panic("heap owner remains alive")

test "heap resource Optional getters retain their existing borrow":
	(
		(expect_fault(() => inspect_heap(HeapMarker("heap")))?)
		| expect_contains("heap owner remains alive")?
	)

fn collection_last(values List[Marker]) Void:
	_id := (values.last() or panic("called Optional.get() on null")).id
	_still_present := values.length()
	panic("last owner remains alive")

fn map_entry(values Map[String, Marker]) Void:
	_id := (values.get("present") or panic("called Optional.get() on null")).id
	_still_present := values.length()
	panic("map owner remains alive")

fn make_map() Map[String, Marker]:
	var values = Map[String, Marker]()
	values.add("present", Marker(8))
	return values

fn collection_named(values List[Marker]) Void:
	entry := values.first()
	_id := (entry or panic("called Optional.get() on null")).id
	_still_present := values.length()
	panic("named owner remains alive")

fn collection_missing(values List[Marker]) Void:
	_id := (values.first() or panic("called Optional.get() on null")).id
	_still_present := values.length()

fn map_missing(values Map[String, Marker]) Void:
	_id := (values.get("absent") or panic("called Optional.get() on null")).id
	_still_present := values.length()

fn read_generic[T](values List[T], read fn(T) Int) Int:
	return read(values.first() or panic("called Optional.get() on null"))

fn generic_collection(values List[Marker]) Void:
	_id := read_generic(values, value => value.id)
	_still_present := values.length()
	panic("generic owner remains alive")

fn temporary_text() String:
	return (["temporary payload"].first() or panic("called Optional.get() on null")).clone()

test "an inline last lend leaves its scalar owner alive":
	(
		(expect_fault(() => collection_last([Marker(7)]))?)
		| expect_contains("last owner remains alive")?
	)

test "an inline map lend leaves its scalar owner alive":
	(
		(expect_fault(() => map_entry(make_map()))?)
		| expect_contains("map owner remains alive")?
	)

test "named and inline scalar collection lends keep the same borrow":
	(
		(expect_fault(() => collection_named([Marker(9)]))?)
		| expect_contains("named owner remains alive")?
	)

test "missing collection lends still report Optional get faults":
	(
		(expect_fault(() => collection_missing(List[Marker]()))?)
		| expect_contains("called Optional.get() on null")?
	)
	(
		(
			expect_fault(() => map_missing(Map[String, Marker]()))?
		) | expect_contains("called Optional.get() on null")?
	)

test "generic inline collection reads lend to their callback":
	(
		(expect_fault(() => generic_collection([Marker(10)]))?)
		| expect_contains("generic owner remains alive")?
	)

test "Clonable results survive their temporary collection":
	text := temporary_text()
	expect_equal(text, "temporary payload")?
	expect_equal(text.length(), 17)?

fn labeled_map_entry(values Map[String, Marker]) Void:
	_id := (values.get(key: "present") or panic("called Optional.get() on null")).id
	_still_present := values.length()
	panic("labeled map owner remains alive")

fn labeled_map_binding(values Map[String, Marker]) Void:
	entry := values.get(key: "present")
	_id := (entry or panic("called Optional.get() on null")).id
	_still_present := values.length()
	panic("labeled binding owner remains alive")

fn labeled_map_missing(values Map[String, Marker]) Void:
	_id := (values.get(key: "absent") or panic("called Optional.get() on null")).id
	_still_present := values.length()

test "a labeled map lend leaves its scalar owner alive":
	(
		(expect_fault(() => labeled_map_entry(make_map()))?)
		| expect_contains("labeled map owner remains alive")?
	)

test "a labeled map binding leaves its scalar owner alive":
	(
		(expect_fault(() => labeled_map_binding(make_map()))?)
		| expect_contains("labeled binding owner remains alive")?
	)

test "a missing labeled map lend still reports the Optional fault":
	(
		(expect_fault(() => labeled_map_missing(make_map()))?)
		| expect_contains("called Optional.get() on null")?
	)

fn map_index(var events List[Int]) Int:
	events.append(1)
	return 0

fn map_key(var events List[Int]) String:
	events.append(2)
	return "present"

test "labeled map lends evaluate receiver and key once in order":
	var values = Map[String, String]()
	values.add("present", "payload")

	maps := [values]
	var events List[Int] = []
	length := (
		maps[map_index(events)].get(key: map_key(events))
		or panic("called Optional.get() on null")
	).length()
	expect_equal(length, 7)?
	expect_equal(events, [1, 2])?
	expect_equal(maps.length(), 1)?

test "labeled map keys retain their checked conversion":
	var values = Map[String?, Int]()
	values.add("present", 12)
	expect_equal(
		values.get(key: "present") or panic("called Optional.get() on null"),
		12,
	)?
	expect_equal(values.get(key: "absent") == null, true)?
	expect_equal(values.length(), 1)?
