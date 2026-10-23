import {expect_equal} from "@std/testing.ms"

test "grouped imports":
    let values: List[Int] = [1, 2]
    var entries = Map[String, Int]()

    entries.add("count", values.length())
    try expect_equal(entries.length(), 1)
