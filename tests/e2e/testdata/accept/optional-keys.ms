import expect_equal from "@std/test/test.ms"

type Named:
    name: String

test "optional string keys hash and compare":
    var m = Map[String?, Int]()
    m.add("x", 1)
    m.add("x", 2)
    m.add(none, 3)
    m.add(none, 4)
    m.add("", 5)
    try expect_equal(m.length(), 3)
    try expect_equal(m.get("x").get(0), 2)
    try expect_equal(m.get(none).get(0), 4)
    try expect_equal(m.get("").get(0), 5)

test "optional record keys in a set":
    var s = Set[Named?]()
    s.add(Named("a"))
    s.add(Named("a"))
    s.add(none)
    s.add(none)
    try expect_equal(s.length(), 2)
    try expect_equal(s.contains(Named("a")), true)
    try expect_equal(s.contains(Named("b")), false)
