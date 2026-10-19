# conform: tags=formatter,lists,maps,modules,parser,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/imports.ms
import {expect_equal} from "@std/testing.ms"

test "grouped imports":
    let values: List[Int] = [1, 2]
    let entries = Map[String, Int]().add("count", values.length())
    try expect_equal(entries.length(), 1)
