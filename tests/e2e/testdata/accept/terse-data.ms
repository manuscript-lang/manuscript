import panic from "@std/faults.ms"

fn subtract(amount: Int, deduction: Int = 1) -> Int: amount - deduction

fn first[T](left: T, right: T) -> T: left

fn size(values: Map[String, Int]) -> Int: values.length()

fn optional_size(values: Optional[Map[String, Int]]) -> Int: (values.unwrap().length())

fn mark(log: List[Int], value: Int) -> Int:
    log.append(value)
    return value

test "map literals and positional identifier arguments":
    let amount = 10
    let deduction = 3
    if subtract(amount, deduction) != 7: return panic("argument order")
    if subtract(amount, deduction: 2) != 8: return panic("mixed labels")
    if subtract(amount) != 9: return panic("default")

    let left = 4
    let right = 8
    if first(left, right) != 4: return panic("generic inference")

    let stored: fn(amount: Int, deduction: Int) -> Int = subtract
    if stored(amount, deduction) != 7: return panic("function value")

    let values = {"a": 1, "b": 2, "a": 3}
    if values.length() != 2 or values.get("a").unwrap() != 3: return panic(
        "duplicate key"
    )

    let keys = values.keys()
    if keys.at(0).unwrap() != "a" or keys.at(1).unwrap() != "b": return panic(
        "insertion order"
    )

    let empty: Map[String, Int] = {}
    if (empty.length() != 0 or size({}) != 0 or optional_size({}) != 0): return panic(
        "empty context"
    )

    let nested: Map[String, Map[String, Int]] = {"a": {}, "b": {"c": 1}}
    if nested.get("b").unwrap().get("c").unwrap() != 1: return panic("nested map")

    let optional: Map[String, Optional[Int]] = {"a": none, "b": some(2)}
    if not optional.get("a").unwrap().is_none(): return panic("context")

    let key = "c"
    let value = 5
    values.add(key, value)
    if values.get(key).unwrap() != value: return panic("method identifiers")

    let log: List[Int] = []
    let ordered = {
        mark(log, value: 1): mark(log, value: 2),
        mark(log, value: 1): mark(log, value: 3)
    }
    if log != [1, 2, 1, 3] or ordered.get(1).unwrap() != 3: return panic(
        "evaluation order"
    )

    let shared = {"x": values}
    values.add(key: "d", value: 6)
    if shared.get("x").unwrap().get("d").unwrap() != 6: return panic(
        "shared references"
    )

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Equal) -> Bool:
        match other:
        Key(value): return self.id == value.id
        _: return false

impl Hashable for Key:
    fn hash() -> Int: self.id

test "map literal uses custom key equality":
    let a = Key(id: 1, label: "first")
    let b = Key(id: 1, label: "second")
    let values = {a: "a", b: "b"}
    if values.length() != 1 or values.get(a).unwrap() != "b": return panic(
        "custom key equality"
    )
