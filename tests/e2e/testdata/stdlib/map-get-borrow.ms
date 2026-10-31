import expect_equal, expect_true, expect_false from "@std/test.ms"

type Item:
    name: String
    tags: List[String]

test "reading through get leaves the map entry intact":
    var m = Map[String, Item]()
    m.add(key: "a", value: Item(name: "x", tags: ["p", "q"]))
    try expect_equal(m.get("a").get().name, "x")
    try expect_equal(m.get("a").get().tags.length(), 2)
    try expect_true(m.get("a").is_some())
    try expect_true(m.get("zz").is_none())
    try expect_equal(m.get("zz").get(Item(name: "d", tags: [])).name, "d")
    try expect_equal(m.get("a").get(Item(name: "d", tags: [])).name, "x")
    try expect_equal(m.get("a").get().tags.length(), 2)

test "a kept value is a copy that later changes do not reach":
    var m = Map[String, Item]()
    m.add(key: "a", value: Item(name: "x", tags: ["p"]))

    let kept = m.get("a").get().clone()
    m.add(key: "a", value: Item(name: "y", tags: []))
    try expect_equal(kept.name, "x")
    try expect_equal(kept.tags.length(), 1)
    try expect_equal(m.get("a").get().name, "y")

test "get with a default on integer values":
    var counts = Map[String, Int]()
    counts.add(key: "k", value: 5)
    try expect_equal(counts.get("k").get(0), 5)
    try expect_equal(counts.get("none").get(7), 7)
    try expect_false(counts.get("none").is_some())
