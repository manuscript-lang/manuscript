import {expect_equal, expect_true} from "@std/testing.ms"

type Order:
    status: String
    items: List[String]

fn count_placed(orders: Map[String, Order]) Int:
    var n = 0
    for e in orders.entries():
        if e.value.status == "placed":
            n += e.value.items.length()
    return n

fn ship(var orders: Map[String, Order], id: String) Bool:
    if var o = orders.get(id):
        o.status = "shipped"
        o.items.append("label")
        return true

    return false

test "a for loop walks a map's entries, values and keys in insertion order":
    var m = Map[String, Int]()
    m.add(key: "b", value: 2)
    m.add(key: "a", value: 1)
    m.add(key: "c", value: 3)
    m.remove("a")

    var seen = List[String]()
    for e in m.entries():
        seen.append("{e.key}={e.value}")
    for e in m:
        seen.append(e.key.clone())
    for v in m.values():
        seen.append("{v}")

    for k in m.keys():
        if k == "c":
            break

        seen.append(k.clone())

    try expect_equal(seen, ["b=2", "c=3", "b", "c", "2", "3", "b"])

test "a walk over a map the body changes still sees a snapshot":
    var m = Map[String, Int]()
    m.add(key: "x", value: 1)
    m.add(key: "y", value: 2)
    for e in m.entries():
        m.add(key: "{e.key}{e.key}", value: e.value * 10)
    try expect_equal(m.length(), 4)
    try expect_equal(m.get_or(key: "yy", fallback: 0), 20)

test "walks borrow record values and sets without copying them":
    var orders = Map[String, Order]()
    orders.add(key: "o1", value: Order(status: "placed", items: ["a", "b"]))
    orders.add(key: "o2", value: Order(status: "shipped", items: ["c"]))
    orders.add(key: "o3", value: Order(status: "placed", items: ["d"]))
    try expect_equal(count_placed(orders), 3)

    var s = Set[Int]()
    s.add(4)
    s.add(9)

    var total = 0
    for x in s:
        total += x

    for x in s.values():
        if x == 4:
            continue

        total += x

    try expect_equal(total, 22)

    var flags = Map[Bool, String]()
    flags.add(key: true, value: "yes")
    flags.add(key: false, value: "no")

    var words = List[String]()
    for e in flags.entries():
        words.append("{e.key}:{e.value}")
    try expect_equal(words, ["true:yes", "false:no"])

test "if var changes a map entry in place":
    var counts = Map[String, Int]()
    counts.add(key: "a", value: 1)

    if var n = counts.get("a"):
        n += 4
        n *= 2

    if var n = counts.get("missing"):
        n += 1
    try expect_equal(counts.get_or(key: "a", fallback: 0), 10)
    try expect_equal(counts.length(), 1)

    var orders = Map[String, Order]()
    orders.add(key: "o1", value: Order(status: "placed", items: ["a"]))
    try expect_true(ship(var orders, "o1"))
    try expect_equal(ship(var orders, "o9"), false)

    let o = orders.get("o1").get()
    try expect_equal(o.status, "shipped")
    try expect_equal(o.items, ["a", "label"])
