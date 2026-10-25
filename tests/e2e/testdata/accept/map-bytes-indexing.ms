from "@std/testing.ms" import expect_equal

def total(scores: Map[String, Int]) -> Int:
    return scores["a"] + scores["b"]

def sizes(var table: Map[Int, String]) -> Int:
    table[1] = "one"
    return table[1].length()

test "map index reads and writes":
    var m = {"a": 1, "b": 2}
    m["a"] | try expect_equal(1)
    m["c"] = 3
    m["c"] | try expect_equal(3)
    m["a"] += 10
    m["a"] | try expect_equal(11)
    total(m) | try expect_equal(13)
    m.length() | try expect_equal(3)

test "map index assignment keeps insertion position":
    var m = {"x": 1, "y": 2, "z": 3}
    m["y"] = 20
    m.keys() | try expect_equal(["x", "y", "z"])
    m["y"] | try expect_equal(20)

test "map index with Int keys and String values":
    var table: Map[Int, String] = {}
    sizes(var table) | try expect_equal(3)

    var counts = {1: 10, 2: 20}
    counts[2] *= 2
    counts[2] | try expect_equal(40)

test "bytes index":
    let data = "abc".to_bytes()
    data[0] | try expect_equal(97)
    data[2] | try expect_equal(99)
    data[-1] | try expect_equal(99)
    data[-3] | try expect_equal(97)
