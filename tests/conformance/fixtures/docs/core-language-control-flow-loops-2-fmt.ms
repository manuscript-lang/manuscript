# conform: tags=control-flow,faults,formatter,interpolation,modules,mutation,parser,stdlib-collections,stdlib-faults,testing,tier-stdlib
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/loops.md:26
from "@std/core.ms" import panic

test "sum indexes":
    var total = 0
    for index in 0..5:
        total += index
    if total != 10:
        return panic(f"Expected 10, got {total}")
