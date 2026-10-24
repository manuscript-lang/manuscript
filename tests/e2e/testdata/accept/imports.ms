from "@std/testing.ms" import expect_equal

test "grouped imports":
    let values: List[Int] = [1, 2]
    var entries = Map[String, Int]()
    entries.add("count", values.length())
    try expect_equal(entries.length(), 1)
