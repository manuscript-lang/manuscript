# conform: tags=control-flow,faults,modules,mutation,stdlib-collections,stdlib-faults,tier-stdlib
# conform: phase=run
# conform: origin=bench/language/calls.ms
from "@std/core.ms" import panic

def add(a: Int, b: Int) -> Int: a + b

export def main() -> Int:
    var sum = 0
    for i in 0..5000000:
        sum = add(sum, i)
    if sum != 12499997500000: return panic("calls checksum")

    return 0
