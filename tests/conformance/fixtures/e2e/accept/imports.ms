# conform: tags=lists,maps,modules,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/imports.ms
from "@std/test.ms" import expect_equal

test "grouped imports":
    let values: List[Int] = [1, 2]
    var entries = Map[String, Int]()
    entries.add("count", values.length())
    try expect_equal(entries.length(), 1)
