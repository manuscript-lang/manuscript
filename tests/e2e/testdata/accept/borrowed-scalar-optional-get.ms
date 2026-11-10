import (
    Closeable, panic from "@std/core.ms",
    expect_contains, expect_equal, expect_fault from "@std/test/test.ms",
)

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: error(Error("scalar marker closed"))

fn inspect(value: Marker?) Unit:
    let _id = value.get().id
    let _still_present = value.is_some()
    panic("borrowed owner remains alive")

fn collection(values: List[Marker]) Unit:
    let _id = values.first().get().id
    let _still_present = values.length()
    panic("collection owner remains alive")

test "a borrowed scalar Optional getter leaves its owner alive":
    (try expect_fault(fn: inspect(Marker(1)))) | try expect_contains(
        "borrowed owner remains alive"
    )

test "a scalar collection lend leaves its owner alive":
    (try expect_fault(fn: collection([Marker(2)]))) | try expect_contains(
        "collection owner remains alive"
    )

fn owned_result() Unit:
    let value: Marker!Int = ok(Marker(3))
    let _id = value.get().id

fn scalar_optional() Marker?: Marker(4)

fn owned_optional() Unit:
    let _id = scalar_optional().get().id

test "owned scalar getter results still close their temporary":
    (try expect_fault(owned_result)) | try expect_contains(
        "resource could not be closed"
    )
    (try expect_fault(owned_optional)) | try expect_contains(
        "resource could not be closed"
    )

type HeapMarker:
    text: String

impl Closeable for HeapMarker:
    var fn close() Unit!: error(Error("heap marker closed"))

fn inspect_heap(value: HeapMarker?) Unit:
    let _length = value.get().text.length()
    let _still_present = value.is_some()
    panic("heap owner remains alive")

test "heap resource Optional getters retain their existing borrow":
    (try expect_fault(fn: inspect_heap(HeapMarker("heap")))) | try expect_contains(
        "heap owner remains alive"
    )

fn collection_last(values: List[Marker]) Unit:
    let _id = values.last().get().id
    let _still_present = values.length()
    panic("last owner remains alive")

fn map_entry(values: Map[String, Marker]) Unit:
    let _id = values.get("present").get().id
    let _still_present = values.length()
    panic("map owner remains alive")

fn make_map() Map[String, Marker]:
    var values = Map[String, Marker]()
    values.add("present", Marker(8))
    return values

fn collection_named(values: List[Marker]) Unit:
    let entry = values.first()
    let _id = entry.get().id
    let _still_present = values.length()
    panic("named owner remains alive")

fn collection_missing(values: List[Marker]) Unit:
    let _id = values.first().get().id
    let _still_present = values.length()

fn map_missing(values: Map[String, Marker]) Unit:
    let _id = values.get("absent").get().id
    let _still_present = values.length()

fn read_generic[T](values: List[T], read: fn(T) Int) Int:
    return read(values.first().get())

fn generic_collection(values: List[Marker]) Unit:
    let _id = read_generic(values, fn value: value.id)
    let _still_present = values.length()
    panic("generic owner remains alive")

fn temporary_text() String:
    return ["temporary payload"].first().get()

test "an inline last lend leaves its scalar owner alive":
    (try expect_fault(fn: collection_last([Marker(7)]))) | try expect_contains(
        "last owner remains alive"
    )

test "an inline map lend leaves its scalar owner alive":
    (try expect_fault(fn: map_entry(make_map()))) | try expect_contains(
        "map owner remains alive"
    )

test "named and inline scalar collection lends keep the same borrow":
    (try expect_fault(fn: collection_named([Marker(9)]))) | try expect_contains(
        "named owner remains alive"
    )

test "missing collection lends still report Optional get faults":
    (try expect_fault(fn: collection_missing(List[Marker]()))) | try expect_contains(
        "called Optional.get() on none"
    )
    (try expect_fault(fn: map_missing(Map[String, Marker]()))) | try expect_contains(
        "called Optional.get() on none"
    )

test "generic inline collection reads lend to their callback":
    (try expect_fault(fn: generic_collection([Marker(10)]))) | try expect_contains(
        "generic owner remains alive"
    )

test "Clonable results survive their temporary collection":
    let text = temporary_text()
    try expect_equal(text, "temporary payload")
    try expect_equal(text.length(), 17)

fn labeled_map_entry(values: Map[String, Marker]) Unit:
    let _id = values.get(key: "present").get().id
    let _still_present = values.length()
    panic("labeled map owner remains alive")

fn labeled_map_binding(values: Map[String, Marker]) Unit:
    let entry = values.get(key: "present")
    let _id = entry.get().id
    let _still_present = values.length()
    panic("labeled binding owner remains alive")

fn labeled_map_missing(values: Map[String, Marker]) Unit:
    let _id = values.get(key: "absent").get().id
    let _still_present = values.length()

test "a labeled map lend leaves its scalar owner alive":
    (try expect_fault(fn: labeled_map_entry(make_map()))) | try expect_contains(
        "labeled map owner remains alive"
    )

test "a labeled map binding leaves its scalar owner alive":
    (try expect_fault(fn: labeled_map_binding(make_map()))) | try expect_contains(
        "labeled binding owner remains alive"
    )

test "a missing labeled map lend still reports the Optional fault":
    (try expect_fault(fn: labeled_map_missing(make_map()))) | try expect_contains(
        "called Optional.get() on none"
    )

fn map_index(var events: List[Int]) Int:
    events.append(1)
    return 0

fn map_key(var events: List[Int]) String:
    events.append(2)
    return "present"

test "labeled map lends evaluate receiver and key once in order":
    var values = Map[String, String]()
    values.add("present", "payload")

    let maps = [values]
    var events: List[Int] = []
    let length = maps[map_index(var events)].get(
        key: map_key(var events)
    ).get().length()
    try expect_equal(length, 7)
    try expect_equal(events, [1, 2])
    try expect_equal(maps.length(), 1)

test "labeled map keys retain their checked conversion":
    var values = Map[String?, Int]()
    values.add("present", 12)
    try expect_equal(values.get(key: "present").get(), 12)
    try expect_equal(values.get(key: "absent").is_none(), true)
    try expect_equal(values.length(), 1)
