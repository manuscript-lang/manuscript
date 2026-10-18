import {expect_true} from "@std/testing.ms"

fn lookup(m: Map[String, Int], key: String) -> Int:
    match m.get(key: key):
        some(v):
            return v
        none:
            return -1

test "string map":
    let m = Map[String, Int]()
    m.add(key: "a", value: 1)
    m.add(key: "b", value: 2)
    m.add(key: "a", value: 3)
    (m.length() == 2) | try expect_true
    (lookup(m: m, key: "a") == 3 and lookup(m: m, key: "b") == 2) | try expect_true
    (lookup(m: m, key: "c") == -1) | try expect_true
    (lookup(m: Map[String, Int](), key: "a") == -1) | try expect_true
    m.add(key: "", value: 9)
    (lookup(m: m, key: "") == 9) | try expect_true
    var seen = 0

    for entry in m:
        m.add(key: "x{seen}", value: seen)
        seen = seen + 1

    (seen == 3 and m.length() == 6) | try expect_true
