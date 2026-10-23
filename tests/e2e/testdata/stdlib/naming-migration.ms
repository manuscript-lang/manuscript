import {expect_equal, expect_false} from "@std/testing.ms"
import {MapBuilder, SetBuilder, ListBuilder} from "@std/collections.ms"
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import StringBuilder from "@std/string.ms"

type Counter:
    calls: Int

interface EntryBuilder:
    fn add(key: String, value: Int) Unit

type EntryAdapter:
    builder: MapBuilder[String, Int]

impl EntryBuilder for EntryAdapter:
    var fn add(key: String, value: Int) Unit:
        self.builder.add(key, value)

interface Defaults:
    var fn add_default(key: String, value: Int) Unit
    var fn add_default_from(key: String, create: fn(key: String) Int) Unit

type DefaultAdapter:
    values: Map[String, Int]

impl Defaults for DefaultAdapter:
    var fn add_default(key: String, value: Int) Unit:
        self.values.add_default(key, value)

    var fn add_default_from(key: String, create: fn(key: String) Int) Unit:
        self.values.add_default_from(key, create)

fn eager(var counter: Counter) Int:
    counter.calls += 1
    return 99

test "default insertion keeps eager and lazy calls and receiver identity":
    var values = Map[String, Int]()
    values.add("a", 1)

    var counter = Counter(0)
    values.add_default("a", eager(var counter))
    try expect_false(counter.calls != 1 or values.get("a") != some(1))
    values.add("b", 2)
    try expect_equal(values.keys(), ["a", "b"])

    let create = fn(key: String) Int:
        counter.calls += 1
        return key.length()

    let lazy: fn(key: String, create: fn(key: String) Int) Unit = values.add_default_from
    lazy("a", create)
    try expect_equal(counter.calls, 1)
    lazy("ccc", create)
    values.add_default("d", 4)
    try expect_false(counter.calls != 2 or values.values() != [1, 2, 3, 4])

    var view = Defaults(DefaultAdapter(values.clone()))
    view.add_default("a", 88)
    view.add_default_from("ee", create)

    var copy = values.clone()
    copy.add_default("copy", 6)
    try expect_false(values.contains("copy") or not copy.contains("copy"))
    try expect_false(
        counter.calls != 3 or values.keys() != ["a", "b", "ccc", "d", "ee"]
    )

    let legacy: fn(key: String, value: Int) Unit = values.add_default
    legacy("a", 100)
    values.add_default_from("ff", create)
    try expect_false(counter.calls != 4 or values.get("a") != some(1))

test "all builders keep Unit mutation function types":
    let list = ListBuilder[Int]()
    let append_list: fn(value: Int) Unit = list.append
    append_list(1)

    var list_result = list.freeze()
    list_result.append(2)
    try expect_equal(list.freeze(), [1, 2])

    let map = MapBuilder[String, Int]()
    let map_alias = map
    let add_map: fn(key: String, value: Int) Unit = map.add
    let legacy_map: fn(key: String, value: Int) Unit = map_alias.add
    let _unit: Unit = add_map("a", 1)
    map_alias.add("b", 2)

    let adapter = EntryBuilder(EntryAdapter(map_alias))
    let add_view: fn(key: String, value: Int) Unit = adapter.add
    add_view("b", 2)
    legacy_map("a", 3)

    var map_result = map.freeze()
    try expect_false(map_result.keys() != ["a", "b"] or map_result.values() != [3, 2])
    map_result.add("c", 4)
    try expect_equal(map_alias.freeze().keys(), ["a", "b", "c"])

    let set = SetBuilder[Int]()
    let add_set: fn(value: Int) Unit = set.add
    let legacy_set: fn(value: Int) Unit = set.add
    add_set(2)
    set.add(1)
    legacy_set(2)

    var set_result = set.freeze()
    try expect_equal(set_result.values(), [2, 1])
    set_result.add(3)
    try expect_equal(set.freeze().values(), [2, 1, 3])

    var bytes = BytesBuilder()
    let append_byte: fn(value: Int) Unit = bytes.append
    let concat_bytes: fn(values: Bytes) Unit = bytes.concat
    append_byte(65)
    concat_bytes("B".to_bytes())
    try expect_false(
        (bytes.freeze() != "AB".to_bytes() or bytes.freeze() != "AB".to_bytes())
    )

    var text = StringBuilder()
    let append_text: fn(value: String) Unit = text.append
    append_text("ab")
    try expect_false(text.freeze() != "ab" or text.freeze() != "ab")

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
