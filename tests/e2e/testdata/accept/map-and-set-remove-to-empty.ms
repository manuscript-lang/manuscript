import {expect_equal, fail} from "@std/test.ms"

test "maps and sets keep distinct keys after removal to empty":
    var m = Map[String, Int]()
    m.add(key: "cap", value: 1)
    m.remove("cap")
    m.add(key: "pen", value: 2)
    m.add(key: "cap", value: 3)
    if m.length() != 2: return fail("without: length {m.length()}")

    m["pen"] | try expect_equal(2)
    m["cap"] | try expect_equal(3)

    var n = Map[Int, Int]()
    n.add(key: 1, value: 10)
    n.remove(key: 1)
    n.add(key: 2, value: 20)
    n.add(key: 1, value: 30)
    if n.length() != 2: return fail("remove: length {n.length()}")

    n[2] | try expect_equal(20)
    n[1] | try expect_equal(30)

    var s = Set[String]()
    s.add("cap")
    s.remove("cap")
    s.add("pen")
    s.add("cap")
    if s.length() != 2: return fail("set: length {s.length()}")
