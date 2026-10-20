# conform: tags=control-flow,faults,formatter,lists,maps,modules,optional,parser,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/data-1.ms
import {expect_equal} from "@std/testing.ms"

fn positives(values: List[Int]) List[Int]:
    var result: List[Int] = []
    for value in values:
        if value > 0:
            result.append(value)
    return result

test "dynamic mutable data and explicit copies":
    try expect_equal(positives([3, -1, 2]), [3, 2])
    let absent: Optional[Int] = none
    try expect_equal([1].get(5, default: -1), -1)
    var original = Map[String, Int]()
    original.add("a", 1)
    var updated = original.clone()
    updated.add("b", 2)
    updated.add("a", 3)
    try expect_equal(original.get("a"), some(1))
    try expect_equal(updated.get("a"), some(3))
