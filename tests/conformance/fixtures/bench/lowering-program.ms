# conform: tags=control-flow,diagnostics,faults,lists,modules,mutation,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=bench/lowering/program.ms
import range from "@std/collections.ms"

fn scalar(limit: Int) Int:
    var total = 0
    for index in range(0, limit):
        total += index
    return total

fn add(left: Int, right: Int) Int: left + right

fn calls(limit: Int) Int:
    var total = 0
    for index in range(0, limit):
        total = add(total, index)
    return total

fn items(values: List[Int], limit: Int) Int:
    var total = 0
    for index in range(0, limit):
        total += values.get(index)
    return total
