import {MapBuilder, SetBuilder, ListBuilder} from "@std/collections.ms"
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import StringBuilder from "@std/string.ms"
import panic from "@std/faults.ms"

type Counter:
    calls: Int

interface EntryBuilder:
    fn add(key: String, value: Int) Unit

type EntryAdapter:
    builder: MapBuilder[String, Int]

impl EntryBuilder for EntryAdapter:
    fn add(key: String, value: Int) Unit:
        self.builder.add(key, value)

interface Defaults:
    fn add_default(key: String, value: Int) Map[String, Int]
    fn add_default_from(key: String, create: fn(key: String) Int) Map[String, Int]

type DefaultAdapter:
    values: Map[String, Int]

impl Defaults for DefaultAdapter:
    fn add_default(key: String, value: Int) Map[String, Int]:
        return self.values.add_default(key, value)

    fn add_default_from(key: String, create: fn(key: String) Int) Map[String, Int]:
        return self.values.add_default_from(key, create)

fn eager(counter: Counter) Int:
    counter.calls = counter.calls + 1
    return 99

test "default insertion keeps eager and lazy calls and receiver identity":
    let values = Map[String, Int]().add("a", 1)
    let counter = Counter(0)
    let alias = values.add_default("a", eager(counter))
    if counter.calls != 1 or values.get("a") != some(1): return panic("eager default")

    alias.add("b", 2)
    if values.keys() != ["a", "b"]: return panic("default receiver identity")

    let create = fn(key: String) Int:
        counter.calls = counter.calls + 1
        return key.length()
    let lazy: fn(key: String, create: fn(key: String) Int) Map[String, Int] = values.add_default_from
    lazy("a", create)
    if counter.calls != 1: return panic("existing key called creator")

    lazy("ccc", create).add_default("d", 4)
    if counter.calls != 2 or values.values() != [1, 2, 3, 4]: return panic(
        "lazy insertion"
    )

    let view = Defaults(DefaultAdapter(values))
    view.add_default("a", 88)
    view.add_default_from("ee", create)
    let copy = values.clone().add_default("copy", 6)
    if values.contains("copy") or not copy.contains("copy"): return panic(
        "explicit copy"
    )
    if counter.calls != 3 or values.keys() != ["a", "b", "ccc", "d", "ee"]: return panic(
        "adapter order"
    )

    let legacy: fn(key: String, value: Int) Map[String, Int] = values.add_default
    legacy("a", 100).add_default_from("ff", create)
    if counter.calls != 4 or values.get("a") != some(1): return panic(
        "legacy compatibility"
    )

test "all builders keep Unit mutation function types":
    let list = ListBuilder[Int]()
    let append_list: fn(value: Int) Unit = list.append
    append_list(1)
    let list_result = list.freeze()
    list_result.append(2)
    if list.freeze() != [1, 2]: return panic("list freeze alias")

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
    let map_result = map.freeze()
    if map_result.keys() != ["a", "b"] or map_result.values() != [3, 2]: return panic(
        "builder map order"
    )

    map_result.add("c", 4)
    if map_alias.freeze().keys() != ["a", "b", "c"]: return panic("map freeze alias")

    let set = SetBuilder[Int]()
    let add_set: fn(value: Int) Unit = set.add
    let legacy_set: fn(value: Int) Unit = set.add
    add_set(2)
    set.add(1)
    legacy_set(2)
    let set_result = set.freeze()
    if set_result.values() != [2, 1]: return panic("builder set order")

    set_result.add(3)
    if set.freeze().values() != [2, 1, 3]: return panic("set freeze alias")

    let bytes = BytesBuilder()
    let append_byte: fn(value: Int) Unit = bytes.append
    let concat_bytes: fn(values: Bytes) Unit = bytes.concat
    append_byte(65)
    concat_bytes("B".to_bytes())
    if bytes.freeze() != "AB".to_bytes() or bytes.freeze() != "AB".to_bytes(): return panic(
        "bytes freeze"
    )

    let text = StringBuilder()
    let append_text: fn(value: String) Unit = text.append
    append_text("ab")
    if text.freeze() != "ab" or text.freeze() != "ab": return panic("text freeze")

test "copy names preserve Bytes and collection storage":
    let bytes = Bytes([1, 2, 3])
    let copied = bytes.with_value(0, 9)
    if bytes != Bytes([1, 2, 3]) or copied != Bytes([9, 2, 3]): return panic(
        "Bytes copy"
    )

    let values = [1, 2, 3]
    let reversed = values.reversed()
    reversed.set(0, 9)
    if values != [1, 2, 3] or reversed != [9, 2, 1]: return panic("List reversed copy")

    let set = Set[Int]().add(1)
    set.clone().add(2)
    if set.values() != [1]: return panic("explicit Set clone")
