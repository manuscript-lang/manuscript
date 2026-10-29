# conform: tags=control-flow,faults,interpolation,modules,mutation,stdlib-collections,stdlib-faults,testing,tier-stdlib
# conform: phase=test
# conform: origin=documentation/core-language/control-flow/loops.md:26
import panic from "@std/core.ms"

test "sum indexes":
    var total = 0
    for index in 0..5:
        total += index
    if total != 10:
        return panic("Expected 10, got {total}")
