# conform: tags=control-flow,faults,formatter,modules,mutation,parser,stdlib-collections,stdlib-faults,tier-stdlib
# conform: phase=parse
# conform: origin=bench/language/calls.ms
from "@std/core.ms" import panic
from "@std/collections.ms" import range

def add(a: Int, b: Int) -> Int: a + b

export def main() -> Int:
    var sum = 0
    for i in range(0, 5000000):
        sum = add(sum, i)
    if sum != 12499997500000: return panic("calls checksum")

    return 0
