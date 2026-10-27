from "@std/test.ms" import expect_equal
from "@std/sorted.ms" import SortedMap

test "map update counts and transforms":
    var counts = Map[String, Int]()
    for word in ["a", "b", "a"]:
        counts.update(word, 0, lambda n: n + 1)
    try expect_equal(counts["a"], 2)
    try expect_equal(counts["b"], 1)
    counts.update("c", 10, lambda n: n * 2)
    try expect_equal(counts["c"], 20)
    try expect_equal(counts.length(), 3)

test "sorted map get_or":
    var sorted = SortedMap[Int, String]()
    sorted.add(1, "one")
    try expect_equal(sorted.get_or(1, "?"), "one")
    try expect_equal(sorted.get_or(2, "?"), "?")
