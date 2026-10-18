import {expect_equal} from "@std/testing.ms"

fn map_total(values: Map[String, Int]) -> Int:
    var total = 0

    for entry in values:
        let {key, value} = entry
        let label: String = key
        total = total + value

    return total

fn set_total(values: Set[Int]) -> Int:
    var total = 0
    for value in values:
        total = total + value
    return total

test "map entry type":
    let entry = MapEntry[String, Int](key: "a", value: 3)
    entry.key | try expect_equal(expected: "a")
    entry.value | try expect_equal(expected: 3)
