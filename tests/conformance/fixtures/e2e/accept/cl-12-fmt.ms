# conform: tags=control-flow,formatter,maps,modules,mutation,parser,sets,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cl-12.ms
import expect_equal from "@std/test/test.ms"

fn map_total(values: Map[String, Int]) Int:
    var total = 0

    for entry in values:
        let {value} = entry
        total += value

    return total

fn set_total(values: Set[Int]) Int:
    var total = 0
    for value in values:
        total += value
    return total

test "map entry type":
    let entry = MapEntry[String, Int]("a", 3)
    try expect_equal(entry.key, "a")
    try expect_equal(entry.value, 3)
