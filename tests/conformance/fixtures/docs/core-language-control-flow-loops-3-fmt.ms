# conform: tags=control-flow,faults,formatter,modules,mutation,parser,stdlib-faults,testing,tier-stdlib
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/loops.md:43
from "@std/core.ms" import panic

test "five iterations":
    var index = 0
    var total = 0

    while index < 5:
        total += index
        index += 1

    if index != 5 or total != 10:
        return panic("Expected five iterations and total 10")
