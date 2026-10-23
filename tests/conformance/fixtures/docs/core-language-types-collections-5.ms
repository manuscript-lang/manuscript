# conform: tags=control-flow,faults,lists,maps,modules,mutation,optional,stdlib-faults,strings,testing,tier-stdlib
# conform: phase=test
# conform: origin=documentation/core-language/types/collections.md:187
import panic from "@std/core.ms"

fn positives(values: List[Int]) List[Int]:
    var result: List[Int] = []
    for value in values:
        if value > 0:
            result.append(value)
    return result

test "dynamic mutable data and explicit copies":
    if not (positives([3, -1, 2]) == [3, 2]):
        return panic("check failed")
    if [1].get(5, default: -1) != -1:
        return panic("check failed")

    var original = Map[String, Int]()
    original.add("a", 1)

    var updated = original.clone()
    updated.add("b", 2)
    updated.add("a", 3)
    if not (original.get("a") == some(1)):
        return panic("check failed")
    if not (updated.get("a") == some(3)):
        return panic("check failed")
