from "@std/test.ms" import expect_equal, expect_true

# A `String` value is two words, so `Map[Int, String]` and `Map[String, String]` take the general
# lookup entry points; the word-layout fast paths read a 24-byte slot and missed the second key.
test "int keys with string values find every key":
    var names = Map[Int, String]()
    names.add(1, "one")
    names.add(2, "two")
    try expect_true(names.contains(2))
    try expect_true(names.contains(1))
    try expect_equal(names.get(2).get(), "two")
    try expect_equal(names.get_or(key: 2, fallback: ""), "two")
    try expect_equal(names.get_or(key: 3, fallback: "none"), "none")
    if let found = names.get(1):
        try expect_equal(found, "one")

test "string keys with string values find every key":
    var m = Map[String, String]()
    m.add("a", "apple")
    m.add("b", "berry")
    try expect_true(m.contains("b"))
    try expect_equal(m.get("b").get(), "berry")
    try expect_equal(m.get_or(key: "a", fallback: ""), "apple")

test "many int keys with string values":
    var m = Map[Int, String]()
    for i in 0..200:
        m.add(i, f"v{i}")

    var hits = 0
    for i in 0..200:
        if m.contains(i):
            hits += 1
    try expect_equal(hits, 200)
    try expect_equal(m.get(199).get(), "v199")
