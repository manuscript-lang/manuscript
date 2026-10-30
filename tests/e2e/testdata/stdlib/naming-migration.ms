import expect_equal, expect_false from "@std/test.ms"
import MapBuilder, SetBuilder, ListBuilder from "@std/collections.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import StringBuilder from "@std/string.ms"

type Counter:
    calls: Int

interface EntryBuilder:
    var fn add(key: String, value: Int) Unit

type EntryAdapter:
    builder: MapBuilder[String, Int]

impl EntryBuilder for EntryAdapter:
    var fn add(key: String, value: Int) Unit:
        self.builder.add(key, value)

interface Defaults:
    var fn add_default(key: String, value: Int) Unit
    var fn add_default_from(key: String, create: fn(String) Int) Unit

type DefaultAdapter:
    values: Map[String, Int]

impl Defaults for DefaultAdapter:
    var fn add_default(key: String, value: Int) Unit:
        self.values.add_default(key, value)

    var fn add_default_from(key: String, create: fn(String) Int) Unit:
        self.values.add_default_from(key, create)

fn eager(var counter: Counter) Int:
    counter.calls += 1
    return 99

fn key_length(key: String) Int: key.length()

test "default insertion keeps eager and lazy calls and receiver identity":
    var values = Map[String, Int]()
    values.add("a", 1)

    var counter = Counter(0)
    values.add_default("a", eager(var counter))
    try expect_false(counter.calls != 1 or values.get("a") != some(1))
    values.add("b", 2)
    try expect_equal(values.keys(), ["a", "b"])

    let lazy: fn(String, fn(String) Int) Unit = values.add_default_from
    lazy("a", key_length)
    lazy("ccc", key_length)
    values.add_default("d", 4)
    try expect_equal(values.values(), [1, 2, 3, 4])

    var view: Defaults = DefaultAdapter(values.clone())
    view.add_default("a", 88)
    view.add_default_from("ee", key_length)

    var copy = values.clone()
    copy.add_default("copy", 6)
    try expect_false(values.contains("copy") or not copy.contains("copy"))
    try expect_equal(values.keys(), ["a", "b", "ccc", "d"])

    let legacy: fn(String, Int) Unit = values.add_default
    legacy("a", 100)
    values.add_default_from("ff", key_length)
    try expect_false(counter.calls != 1 or values.get("a") != some(1))
    try expect_equal(values.keys(), ["a", "b", "ccc", "d", "ff"])

test "all builders keep Unit mutation function types":
    var list = ListBuilder[Int]()
    let append_list: fn(Int) Unit = list.append
    append_list(1)

    var list_result = list.build()
    list_result.append(2)
    try expect_equal(list.build(), [1])
    try expect_equal(list_result, [1, 2])

    var map = MapBuilder[String, Int]()
    let add_map: fn(String, Int) Unit = map.add
    let _unit: Unit = add_map("a", 1)
    map.add("b", 2)

    let legacy_map: fn(String, Int) Unit = map.add
    legacy_map("a", 3)

    var map_result = map.build()
    try expect_false(map_result.keys() != ["a", "b"] or map_result.values() != [3, 2])
    map_result.add("c", 4)
    try expect_equal(map.build().keys(), ["a", "b"])

    var adapter: EntryBuilder = EntryAdapter(MapBuilder[String, Int]())
    let add_view: fn(String, Int) Unit = adapter.add
    add_view("b", 2)

    var set = SetBuilder[Int]()
    let add_set: fn(Int) Unit = set.add
    add_set(2)
    set.add(1)

    let legacy_set: fn(Int) Unit = set.add
    legacy_set(2)

    var set_result = set.build()
    try expect_equal(set_result.values(), [2, 1])
    set_result.add(3)
    try expect_equal(set.build().values(), [2, 1])

    var bytes = BytesBuilder()
    let append_byte: fn(UInt8) Unit = bytes.append
    append_byte(65)

    let concat_bytes: fn(Bytes) Unit = bytes.append_bytes
    concat_bytes("B".to_bytes())
    try expect_false(
        (bytes.build() != "AB".to_bytes() or bytes.build() != "AB".to_bytes())
    )

    var text = StringBuilder()
    let append_text: fn(String) Unit = text.append
    append_text("ab")
    try expect_false(text.build() != "ab" or text.build() != "ab")

test "copy names preserve Bytes and collection storage":
    let bytes = Bytes([1, 2, 3])
    let copied = bytes.with_value(0, 9)
    try expect_false(bytes != Bytes([1, 2, 3]) or copied != Bytes([9, 2, 3]))

    let values = [1, 2, 3]
    var reversed = values.reversed()
    reversed.set(0, 9)
    try expect_false(values != [1, 2, 3] or reversed != [9, 2, 1])

    let set = Set[Int]([1])
    set.clone().add(2)
    try expect_equal(set.values(), [1])
