import {expect_equal} from "@std/testing.ms"

test "grouped imports":
    let values: List[Int] = [1, 2]
    let entries = Map[String, Int]().add(key: "count", value: values.length())
    entries.length() | try expect_equal(expected: 1)
