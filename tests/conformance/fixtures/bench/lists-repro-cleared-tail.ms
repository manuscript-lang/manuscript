# conform: tags=aliasing,control-flow,faults,modules,mutation,stdlib-faults,tier-stdlib
# conform: phase=run
# conform: origin=bench/lists/repro-cleared-tail.ms
import panic from "@std/faults.ms"

export fn main() Int:
    var values = [1, 2, 3]
    var total = 0
    var count = 0

    for value in values:
        total += value
        if count == 0:
            values.remove(0)
        count += 1

    if total != 7:
        panic("unexpected sum")
    return 0
